"""Shared logic for Genesi Mesh — pooling GPU memory across machines on a LAN.

Genesi Mesh lets several machines contribute their GPUs to ONE inference run, so
a model that fits on no single box (or on none of their GPUs) still runs fully
accelerated. It is a thin, security-conscious control plane on top of a facility
llama.cpp already provides: the **RPC backend**.

    machine A (client)                     machine B (worker)
    llama-server --rpc B:50052  ───────►   rpc-server -H 0.0.0.0 -p 50052
      holds the model, serves the API        contributes its GPU as a device

llama.cpp treats each `--rpc` endpoint as an extra backend *device*, so `-ngl`
distributes layers across the local GPU and the remote ones. Nothing here
reimplements inference; Mesh's job is the part llama.cpp deliberately leaves
out — finding peers, proving they are yours, and deciding whether pooling is
actually a good idea for a given model.

Why this lives in the OS and not in an app
------------------------------------------
Discovery, a machine-wide trust secret, a privileged listening service, and
firewall-visible ports are all system concerns. An application cannot make your
other computer offer up its GPU; a system service can.

SECURITY — read before enabling worker mode
-------------------------------------------
Upstream is explicit that `rpc-server` performs **no authentication and no
validation** of what it receives, and must never face an untrusted network. So:

  * Worker mode is **OFF by default**. A machine never offers its GPU until
    someone deliberately turns it on.
  * Every discovery beacon is **HMAC-SHA256 signed** with a pre-shared mesh
    secret. Machines without your secret are invisible to you and you to them.
    This authenticates *discovery* only.
  * The signed beacon is NOT a substitute for network trust on the RPC port
    itself. `rpc_bind` defaults to the loopback address; binding it to a LAN
    address is an explicit, documented choice for a network you control.

Stdlib only, matching the rest of the Genesi AI stack.
"""

import hashlib
import hmac
import json
import os
import re
import shutil
import socket
import struct
import subprocess
import time

# ── Wire protocol ────────────────────────────────────────────────────────────
# Bumped only on an INCOMPATIBLE beacon change. Nodes ignore beacons whose major
# protocol differs, so a half-upgraded mesh degrades to "peer not seen" instead
# of misparsing a peer and planning a run against a node that cannot serve it.
PROTOCOL = 1

DISCOVERY_PORT = 47100                 # UDP, beacons
MULTICAST_GROUP = "239.255.42.99"      # site-local scope, unassigned
DEFAULT_RPC_PORT = 50052               # llama.cpp rpc-server's own default

BEACON_INTERVAL = 5.0                  # seconds between our announcements
PEER_TTL = 20.0                        # drop a peer unheard-from for this long
CLOCK_SKEW = 180.0                     # max accepted beacon age, both directions

CONF_DIR = "/etc/genesi-mesh"
CONF_PATH = os.path.join(CONF_DIR, "mesh.conf")
SECRET_PATH = os.path.join(CONF_DIR, "secret")
RUN_DIR = "/run/genesi-mesh"
PEERS_PATH = os.path.join(RUN_DIR, "peers.json")
STATE_PATH = os.path.join(RUN_DIR, "state.json")

DEFAULTS = {
    "worker": "off",           # offer this machine's GPU to the mesh?
    "rpc_bind": "127.0.0.1",   # address rpc-server listens on when worker=on
    "rpc_port": str(DEFAULT_RPC_PORT),
    "rpc_mem_mb": "0",         # 0 = let rpc-server decide from the device
    "discovery": "on",
    "name": "",                # display name; defaults to the hostname
    # Use peers whose only GPU is integrated? Off by default — see plan_pool.
    "pool_integrated": "off",
}


# ── Config ───────────────────────────────────────────────────────────────────

def load_conf(path=CONF_PATH):
    """Parse the `key = value` config. Unknown keys are kept (forward-compatible
    with a newer daemon writing options this build does not know), missing file
    is not an error — the defaults are a working configuration."""
    conf = dict(DEFAULTS)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    except OSError:
        pass
    return conf


def conf_flag(conf, key):
    return str(conf.get(key, "")).strip().lower() in ("1", "on", "true", "yes")


def conf_int(conf, key, default):
    try:
        return int(str(conf.get(key, "")).strip())
    except (TypeError, ValueError):
        return default


# ── Identity & the shared secret ─────────────────────────────────────────────

def node_id():
    """A stable per-machine id. Derived from /etc/machine-id but HASHED, because
    machine-id is a documented do-not-expose value and these beacons go out on
    the wire. Falls back to the hostname so the mesh still works in a container
    or live session without a persistent machine-id."""
    seed = ""
    try:
        with open("/etc/machine-id", "r", encoding="utf-8") as fh:
            seed = fh.read().strip()
    except OSError:
        pass
    if not seed:
        seed = socket.gethostname()
    return hashlib.sha256(("genesi-mesh:" + seed).encode()).hexdigest()[:16]


def read_secret(path=SECRET_PATH):
    """The pre-shared mesh secret, or None. Every node in one mesh holds the
    same value; it is what makes a beacon trustworthy."""
    try:
        with open(path, "rb") as fh:
            data = fh.read().strip()
        return data or None
    except OSError:
        return None


def create_secret(path=SECRET_PATH):
    """Generate the mesh secret. 0600 and created with O_EXCL so we can never
    silently overwrite an existing mesh's secret (that would partition the mesh
    into two halves that cannot see each other, which is confusing to debug)."""
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    secret = hashlib.sha256(os.urandom(32)).hexdigest().encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, secret + b"\n")
    finally:
        os.close(fd)
    return secret


def install_secret(value, path=SECRET_PATH):
    """Adopt an existing mesh's secret (the `join` path). Overwrites, because
    the caller explicitly asked to move this node into another mesh."""
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    data = value.strip().encode() if isinstance(value, str) else value.strip()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data + b"\n")
    finally:
        os.close(fd)


# ── Beacon encode / verify ───────────────────────────────────────────────────

def _canonical(payload):
    """Deterministic bytes for signing: sorted keys, no incidental whitespace.
    Both ends must derive the identical byte string or every signature fails."""
    return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()


def sign_beacon(payload, secret):
    body = dict(payload)
    body.pop("sig", None)
    body["sig"] = hmac.new(secret, _canonical(body), hashlib.sha256).hexdigest()
    return json.dumps(body, sort_keys=True, separators=(",", ":")).encode()


def verify_beacon(raw, secret, now=None):
    """Parse and authenticate a beacon. Returns the payload dict or None.

    Rejects, in order: malformed JSON, a different protocol major, a missing or
    forged signature, and a timestamp outside the skew window (a replayed
    beacon should not resurrect a peer that is long gone). Every rejection is
    silent by design — this socket is exposed to the LAN and must not become a
    log-spam amplifier for anything that sprays UDP at the port."""
    try:
        payload = json.loads(raw.decode("utf-8", "strict"))
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if payload.get("v") != PROTOCOL:
        return None

    sig = payload.get("sig")
    if not isinstance(sig, str):
        return None
    body = dict(payload)
    body.pop("sig", None)
    expect = hmac.new(secret, _canonical(body), hashlib.sha256).hexdigest()
    # compare_digest: constant time, so the port cannot be used as a signature
    # oracle by timing responses.
    if not hmac.compare_digest(sig, expect):
        return None

    ts = payload.get("ts")
    if not isinstance(ts, (int, float)):
        return None
    if abs((now if now is not None else time.time()) - ts) > CLOCK_SKEW:
        return None
    return payload


def build_beacon(conf, gpu):
    """The advertisement this node broadcasts: who I am, what I can contribute."""
    return {
        "v": PROTOCOL,
        "node": node_id(),
        "host": conf.get("name") or socket.gethostname(),
        "worker": conf_flag(conf, "worker"),
        "rpc_port": conf_int(conf, "rpc_port", DEFAULT_RPC_PORT),
        "backend": gpu.get("backend", "CPU"),
        "vram_mb": int(gpu.get("vram_mb") or 0),
        # Advertised so the CLIENT can decide. Whether an integrated peer is
        # worth using depends on the model and the link, which only the machine
        # planning the run knows — the worker just states what it is.
        "integrated": bool(gpu.get("integrated")),
        "ts": time.time(),
    }


# ── Sockets ──────────────────────────────────────────────────────────────────

def open_listen_socket(port=DISCOVERY_PORT, group=MULTICAST_GROUP):
    """UDP socket joined to the mesh multicast group.

    SO_REUSEADDR so a daemon restart never hits "address already in use" while
    the old socket drains, and so a loopback test can run a second node on the
    same host. Multicast (not broadcast) because broadcast is dropped by many
    APs and by every bridged VM network worth using."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
    sock.bind(("", port))
    mreq = struct.pack("4sl", socket.inet_aton(group), socket.INADDR_ANY)
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except OSError:
        # No multicast route (isolated container, no NIC up). Discovery is then
        # loopback-only, which is exactly what the single-machine mode needs.
        pass
    return sock


def open_send_socket(ttl=2):
    """Sender socket. TTL 2 keeps beacons on the local LAN (one router hop at
    most) — a mesh is a house/office thing, never something to leak onward."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
    except OSError:
        pass
    return sock


def primary_address():
    """This host's LAN-facing address, found by asking the kernel which source
    address it would use to reach an off-link destination. No packet is sent (a
    UDP connect only sets the socket's route), and it beats parsing `ip addr` or
    trusting gethostbyname, which returns 127.0.0.1 on many configurations."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))       # TEST-NET-1: guaranteed unrouted
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


# ── GPU probing ──────────────────────────────────────────────────────────────

def llama_bin(name):
    for cand in (name, "/usr/bin/" + name):
        found = shutil.which(cand) or (cand if os.path.exists(cand) else None)
        if found:
            return found
    return None


# What upstream calls the RPC server binary, newest name first.
#
# llama.cpp renamed it: builds now install `ggml-rpc-server`, older ones shipped
# `rpc-server`. Probing only one name means reporting "not installed" on a
# machine where it IS installed — `genesi-mesh doctor` would send the user off
# to reinstall a package they already have. Same reason the Turbo flags are
# probed from `--help` instead of hardcoded.
RPC_SERVER_NAMES = ("ggml-rpc-server", "rpc-server")


def rpc_server_bin():
    """Path to the llama.cpp RPC server under whichever name this build uses."""
    for name in RPC_SERVER_NAMES:
        found = llama_bin(name)
        if found:
            return found
    return None


# Device names that mean "this GPU has no memory of its own".
#
# An integrated GPU's "VRAM" is a slice of system RAM, which changes everything
# for a mesh: contributing it does not add a separate fast memory pool, it adds
# ordinary RAM reached over the network, backed by ~50-90 GB/s of bandwidth
# shared with the CPU instead of a discrete card's 200+ GB/s. Since llama.cpp
# splits layers by reported CAPACITY and not by speed, an integrated peer takes
# a full share of the work and then makes every token wait for it.
_INTEGRATED_HINTS = re.compile(
    r"\b(uhd graphics|hd graphics|iris|integrated|igpu|vega \d+ graphics|"
    r"radeon graphics|radeon vega|llvmpipe|swiftshader|softpipe|lavapipe)\b",
    re.I)


def _total_ram_mb():
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) // 1024
    except (OSError, ValueError, IndexError):
        pass
    return 0


def _looks_integrated(name, vram_mb):
    """Best-effort 'is this GPU's memory really system RAM?'.

    Two independent signals, because neither alone is reliable across drivers:

      * The device NAME. Intel's UHD/Iris and AMD's APU graphics identify
        themselves clearly, and the software rasterizers (llvmpipe, lavapipe)
        are the same story taken further — they are the CPU wearing a hat.
      * The SIZE relative to system RAM. A discrete card's VRAM is unrelated to
        how much RAM the host has; shared memory is carved straight out of it,
        so a device claiming a large fraction of total RAM is almost certainly
        not holding memory of its own.

    Deliberately conservative: when in doubt, treat it as discrete. A false
    'integrated' would silently drop a real GPU from the mesh, which is a worse
    failure than including a weak one the user can exclude by hand."""
    if name and _INTEGRATED_HINTS.search(name):
        return True
    total_ram = _total_ram_mb()
    if total_ram and vram_mb and vram_mb >= total_ram * 0.4:
        return True
    return False


def probe_gpu():
    """What this machine can contribute: {backend, vram_mb, name, integrated}.

    Mirrors genesi-ai-turbo's detection deliberately — nvidia-smi first (it is
    authoritative where the proprietary/open driver is loaded), then llama.cpp's
    own device list, which is vendor-agnostic and, importantly, reports the
    device the RPC server would actually expose. Under nouveau/NVK nvidia-smi
    exists but cannot talk to the driver, so the second probe is not a
    nicety — it is the only one that works on a stock live session."""
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.run(
                ["nvidia-smi", "--query-gpu=memory.total,name",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=5).stdout
            best, best_name = 0, ""
            for line in out.splitlines():
                parts = [p.strip() for p in line.split(",")]
                if parts and parts[0].isdigit() and int(parts[0]) > best:
                    best = int(parts[0])
                    best_name = parts[1] if len(parts) > 1 else ""
            if best:
                # nvidia-smi answering at all means a real NVIDIA card with its
                # own memory; NVIDIA ships no integrated consumer GPU here.
                return {"backend": "CUDA", "vram_mb": best,
                        "name": best_name or "NVIDIA GPU", "integrated": False}
        except (OSError, subprocess.SubprocessError, ValueError):
            pass

    binp = llama_bin("llama-server") or rpc_server_bin()
    if binp:
        try:
            res = subprocess.run([binp, "--list-devices"],
                                 capture_output=True, text=True, timeout=20)
            text = (res.stdout or "") + (res.stderr or "")
            best, best_name = 0, ""
            # e.g. "  Vulkan0: Intel(R) Iris(R) Xe Graphics (7808 MiB, ...)"
            for match in re.finditer(r"^\s*\w+\d+:\s*(.+?)\s*\((\d+)\s*MiB",
                                     text, re.M):
                size = int(match.group(2))
                if size > best:
                    best, best_name = size, match.group(1)
            if not best:            # older builds print only the size
                best = max([int(m.group(1))
                            for m in re.finditer(r"\((\d+)\s*MiB", text)],
                           default=0)
            if best:
                backend = "CUDA" if re.search(r"\bCUDA\d", text) else "Vulkan"
                return {"backend": backend, "vram_mb": best,
                        "name": best_name,
                        "integrated": _looks_integrated(best_name, best)}
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
    return {"backend": "CPU", "vram_mb": 0, "name": "", "integrated": False}


def rpc_supported():
    """True when the installed llama.cpp was built with -DGGML_RPC=ON.

    Two independent signals, because a partial install can have one without the
    other: the `rpc-server` binary (needed to BE a worker) and the `--rpc` flag
    on llama-server (needed to USE workers). Reported separately so the CLI can
    tell the user which half is missing instead of a vague 'unsupported'."""
    has_server = rpc_server_bin() is not None
    has_flag = False
    binp = llama_bin("llama-server")
    if binp:
        try:
            res = subprocess.run([binp, "--help"], capture_output=True,
                                 text=True, timeout=15)
            has_flag = "--rpc" in ((res.stdout or "") + (res.stderr or ""))
        except (OSError, subprocess.SubprocessError):
            pass
    return {"rpc_server": has_server, "rpc_flag": has_flag}


# ── Peer table ───────────────────────────────────────────────────────────────

# Interfaces that mean "this machine reaches others over a VPN/overlay".
# Multicast does not cross any of them, so LAN discovery is structurally
# impossible there and an empty peer list is the CORRECT result, not a fault.
VPN_IFACE_HINTS = ("tailscale", "wg", "zt", "tun", "nebula")


def vpn_interfaces():
    """Names of VPN-ish interfaces that are UP on this machine."""
    found = []
    try:
        for iface in sorted(os.listdir("/sys/class/net")):
            if not iface.startswith(VPN_IFACE_HINTS):
                continue
            try:
                state = open("/sys/class/net/%s/operstate" % iface).read().strip()
            except OSError:
                state = "unknown"
            if state != "down":
                found.append(iface)
    except OSError:
        pass
    return found


def read_peers(path=PEERS_PATH, now=None):
    """Live peers, already expired-filtered. Readers (the CLI, Turbo, the
    Monitor) never need to know the TTL rule — they just get what is usable
    right now, so a stale daemon cannot make Turbo plan against a dead node."""
    now = now if now is not None else time.time()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    peers = data.get("peers", []) if isinstance(data, dict) else []
    return [p for p in peers
            if isinstance(p, dict) and (now - (p.get("last_seen") or 0)) <= PEER_TTL]


def write_json_atomic(path, data):
    """Write via temp+rename so a reader never observes a half-written file.
    The peer table is read by other processes on every Turbo start."""
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


# ── Planning ─────────────────────────────────────────────────────────────────

# Headroom held back per GPU for the KV cache, activations and driver overhead.
# Same 1.2 GB figure genesi-ai-turbo's budget uses, so Mesh and Turbo agree on
# whether a model "fits" instead of contradicting each other.
GPU_OVERHEAD_GB = 1.2


def plan_pool(local_gpu, peers, model_gb, pool_integrated=False):
    """Decide whether pooling helps for a model of `model_gb`.

    Returns a dict describing the decision, always including `endpoints` (what
    to hand `--rpc`) and `reason` (why, in words a user can act on).

    The honest caveat this encodes: pooling moves layer activations across the
    network every single token. It is a way to run a model that OTHERWISE COULD
    NOT RUN, not a way to make a fitting model faster. So when the model already
    fits locally we deliberately return no endpoints — using the mesh there
    would be slower, and silently doing it would make Mesh look bad for a reason
    the user could never guess."""
    # An integrated GPU has no memory of its own, so it contributes nothing to a
    # POOL of dedicated memory — on either side of the link.
    #
    # Locally that means the budget is 0, which is correct and is what makes the
    # interesting case work: a laptop with only integrated graphics reports "the
    # model does not fit here", so the mesh engages and the remote discrete GPU
    # does the work. That is the whole point of Mesh, and treating the iGPU's
    # shared memory as real VRAM would wrongly conclude the model already fits
    # and refuse to pool.
    local_mb = 0 if local_gpu.get("integrated") else int(local_gpu.get("vram_mb") or 0)
    local_budget = max(local_mb / 1024.0 - GPU_OVERHEAD_GB, 0.0)

    usable, skipped_integrated = [], []
    for peer in peers:
        if not peer.get("worker") or int(peer.get("vram_mb") or 0) <= 0:
            continue
        if peer.get("integrated") and not pool_integrated:
            skipped_integrated.append(peer)
            continue
        usable.append(peer)
    usable.sort(key=lambda p: int(p.get("vram_mb") or 0), reverse=True)

    pooled = local_budget + sum(
        max(int(p.get("vram_mb") or 0) / 1024.0 - GPU_OVERHEAD_GB, 0.0)
        for p in usable)

    def _result(**kw):
        kw.setdefault("skipped_integrated",
                      [p.get("host", "?") for p in skipped_integrated])
        return kw

    if model_gb <= 0:
        return {"use_mesh": False, "endpoints": [], "local_gb": local_budget,
                "pooled_gb": pooled, "peers": usable,
                "reason": "model size unknown"}

    if model_gb <= local_budget:
        return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                       pooled_gb=pooled, peers=usable,
                       reason=("fits in local VRAM (%.1f GB of %.1f GB) — pooling "
                               "would only add network latency"
                               % (model_gb, local_budget)))

    if not usable:
        if skipped_integrated:
            names = ", ".join(p.get("host", "?") for p in skipped_integrated)
            return _result(
                use_mesh=False, endpoints=[], local_gb=local_budget,
                pooled_gb=pooled, peers=[],
                reason=("only integrated-graphics peers online (%s). Their "
                        "memory IS system RAM, and llama.cpp splits layers by "
                        "capacity rather than speed, so they would take a full "
                        "share of the work and make every token wait. Set "
                        "pool_integrated = on to use them anyway." % names))
        return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                       pooled_gb=pooled, peers=[],
                       reason="no worker peers online")

    if model_gb > pooled:
        return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                       pooled_gb=pooled, peers=usable,
                       reason=("too big even pooled (%.1f GB needed, %.1f GB "
                               "across the mesh)" % (model_gb, pooled)))

    endpoints = ["%s:%d" % (p["addr"], int(p.get("rpc_port") or DEFAULT_RPC_PORT))
                 for p in usable if p.get("addr")]
    return _result(use_mesh=True, endpoints=endpoints, local_gb=local_budget,
                   pooled_gb=pooled, peers=usable,
                   reason=("%.1f GB model does not fit locally (%.1f GB) but fits "
                           "across %d machine(s) (%.1f GB pooled)"
                           % (model_gb, local_budget, len(usable), pooled)))
