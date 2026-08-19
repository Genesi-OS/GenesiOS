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

import fcntl
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
TURBO_PORT = 11435                     # genesi-ai-turbo's OpenAI-compatible API

# Local addresses that only THIS machine can reach, in /proc/net/tcp's hex form.
# A Turbo bound to one of these is useless to a peer, so it must not be
# advertised: a peer that believed it would sit there retrying a port that can
# never answer.
_LOOPBACK_HEX = frozenset((
    "0100007F",                                          # 127.0.0.1
    "00000000000000000000000001000000",                  # ::1
))

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
    # Extra peer addresses to beacon DIRECTLY (comma/space separated).
    # Multicast cannot cross a VPN, but unicast can — see static_peers().
    "peers": "",
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


def listening_addrs(port):
    """Hex local addresses holding a LISTEN socket on `port`.

    Read from /proc/net/tcp{,6} rather than shelling out to ss: this runs every
    beacon interval on every node, and it must not depend on iproute2 being
    installed or on parsing a localised tool."""
    want = ":%04X" % port
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                next(fh, None)                            # header
                for line in fh:
                    fields = line.split()
                    if len(fields) < 4 or fields[3] != "0A":   # 0A = LISTEN
                        continue
                    if fields[1].endswith(want):
                        found.add(fields[1].rsplit(":", 1)[0])
        except OSError:
            pass
    return found


def turbo_reachable(port=TURBO_PORT):
    """Is a Turbo listening on an address a PEER could dial?

    Loopback-only does not count. Turbo binds 127.0.0.1 unless
    GENESI_TURBO_HOST says otherwise, so this is what separates "I run a model
    for myself" from "I can run models for you"."""
    return any(a not in _LOOPBACK_HEX for a in listening_addrs(port))


def turbo_peer(peers=None, now=None):
    """The peer offering Turbo over HTTP, or None.

    This is the answer to "who should I ask to run a model?" whenever a machine
    has no GPU of its own. It is deliberately preferred over pooling VRAM: HTTP
    moves the TEXT of a conversation, while the mesh moves layer activations for
    every token and leaves the far GPU idle waiting on round trips. Pooling is
    for a model that fits on no single machine; this is for every other case.

    Ties break toward the most free VRAM, so the box best able to hold the model
    wins."""
    candidates = [p for p in (peers if peers is not None else read_peers(now=now))
                  if p.get("turbo_port")]
    if not candidates:
        return None
    candidates.sort(key=lambda p: peer_available_mb(p), reverse=True)
    return candidates[0]


def turbo_url(peers=None, env=None):
    """Where this machine's Genesi clients should send inference.

    Order: an explicit GENESI_TURBO_URL, then a mesh peer advertising Turbo,
    then loopback. The env var stays first so a manual setup always wins over
    discovery -- but nobody should NEED to set it, which is the whole point."""
    env = env if env is not None else os.environ
    override = (env.get("GENESI_TURBO_URL") or "").strip()
    if override:
        return override.rstrip("/")
    if not turbo_reachable():           # our own Turbo, if any, comes first
        peer = turbo_peer(peers)
        if peer and peer.get("addr"):
            return "http://%s:%d" % (peer["addr"], int(peer["turbo_port"]))
    return "http://127.0.0.1:%d" % TURBO_PORT


def build_beacon(conf, gpu, llama=None):
    """The advertisement this node broadcasts: who I am, what I can contribute.

    `free_mb` is included only when this machine can actually measure it. An
    absent key means UNKNOWN and consumers fall back to capacity; a present 0
    means genuinely nothing free. Collapsing those two into a single number
    would either make every un-pollable machine look permanently full, or make
    a genuinely full one look available — opposite bugs, both silent."""
    beacon = {
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
    # What a peer could actually ALLOCATE here right now. Capacity alone is a
    # promise this machine may not be able to keep: a worker busy with its own
    # model still advertises a full card while having almost nothing left, and
    # the client finds out only when llama.cpp fails to allocate the buffer.
    # Re-sent every beacon (5s) because, unlike capacity, it changes constantly.
    if gpu.get("free_mb") is not None:
        beacon["free_mb"] = int(gpu["free_mb"])
    # Advertised ONLY while a Turbo is actually reachable from off-box, so a
    # peer never has to guess. Re-evaluated every beacon: Turbo is a service a
    # user toggles, and a stale "yes" points clients at a dead port.
    if turbo_reachable():
        beacon["turbo_port"] = TURBO_PORT
    # llama.cpp identity, so the other end can refuse a pairing that would hang
    # rather than discovering it minutes into a load. Only the fields we could
    # actually read — an absent one means "unknown", which rpc_compatibility
    # treats as usable.
    for key, value in (llama or {}).items():
        if value is not None:
            beacon["llama_" + key] = value
    return beacon


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


def static_peers(conf):
    """Addresses to beacon directly, from the `peers` config key.

    Multicast does not cross a VPN, a routed subnet or most APs' client
    isolation — but plain unicast does. Beaconing to a known address makes
    discovery work anywhere the machines can reach each other at all, which is
    the whole point of having them on a VPN in the first place. Both sides
    announce, so listing the other machine on either end is enough for both to
    learn about each other.

    Accepts "host", "host:port", comma- or space-separated.
    """
    out = []
    raw = str(conf.get("peers", "") or "")
    for item in raw.replace(",", " ").split():
        host, _, port = item.rpartition(":")
        if host and port.isdigit():
            out.append((host, int(port)))
        else:
            out.append((item, DISCOVERY_PORT))
    return out


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


def primary_interface(addr=None):
    """The interface that carries primary_address(), or None.

    Peers on the SAME LAN arrive here, not on the VPN — and that interface has
    its own firewall zone, which nothing else in Mesh ever looked at. Found by
    matching the address rather than by parsing routes, so a bond, a bridge or a
    renamed NIC all resolve the same way."""
    addr = addr or primary_address()
    if addr == "127.0.0.1":
        return None
    try:
        ifaces = sorted(os.listdir("/sys/class/net"))
    except OSError:
        return None
    for iface in ifaces:
        if iface == "lo":
            continue
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                packed = fcntl.ioctl(
                    sock.fileno(), 0x8915,               # SIOCGIFADDR
                    struct.pack("256s", iface[:15].encode()))
                if socket.inet_ntoa(packed[20:24]) == addr:
                    return iface
            finally:
                sock.close()
        except OSError:
            continue
    return None


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


# rpc-server picks its own device: it takes every non-CPU device it can see and
# only falls back to the CPU when there is NO accelerator. That fallback is the
# difference between a mesh that offloads and a mesh that hands a remote machine
# a pile of CPU work over the network -- which is strictly worse than not
# meshing at all, and looks like "the worker's CPU is pinned at 100% while its
# GPU idles at 5%". It happens silently whenever the backend module fails to
# load: a CUDA build whose driver/toolkit libraries are not on the loader path,
# a Vulkan build with no usable ICD, a container without /dev/dri.
#
# The server ANNOUNCES its choice on stdout at startup ("Devices:" followed by
# one line per device). We used to send that to DEVNULL, so the single fact that
# distinguishes a working worker from a useless one was thrown away. It is now
# kept here, and `genesi-mesh doctor` reads it.
WORKER_LOG = os.path.join(RUN_DIR, "worker.log")

_DEV_LINE = re.compile(r"^\s{2}(\w+):\s+(.+?)\s+\((\d+)\s*MiB,\s*(\d+)\s*MiB free\)")


def worker_devices(path=WORKER_LOG):
    """Devices the running rpc-server reported serving, newest run only.

    Returns a list of {name, desc, total_mb, free_mb, is_cpu}. Empty when the
    log is missing or the server has not got as far as its banner.
    """
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return []

    # A supervised worker restarts (rpc-server exits when a client disconnects),
    # and the log is truncated per start -- but read the LAST banner regardless,
    # so a stale prefix can never be reported as the current device.
    idx = text.rfind("Devices:")
    if idx < 0:
        return []

    out = []
    for line in text[idx:].splitlines()[1:]:
        m = _DEV_LINE.match(line)
        if not m:
            break                       # the banner is one contiguous block
        name, desc, total, free = m.group(1), m.group(2), m.group(3), m.group(4)
        out.append({
            "name": name,
            "desc": desc,
            "total_mb": int(total),
            "free_mb": int(free),
            # Name, not description: ggml calls the CPU device "CPU" on every
            # backend, while the description is the marketing CPU model string.
            "is_cpu": name.upper().startswith("CPU"),
        })
    return out


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
    """What this machine can contribute:
    {backend, vram_mb, free_mb, name, integrated}.

    `vram_mb` is the card's TOTAL memory; `free_mb` is what is unused right now.
    Both are reported because they answer different questions, and confusing
    them is a bug with a very confusing symptom: a worker whose GPU is busy
    still has its full capacity, but a peer can only ALLOCATE what is free. A
    mesh that advertises capacity invites a client to plan a run against memory
    that does not exist, and llama.cpp then fails at load time with a raw
    "failed to allocate RPC0 buffer" — long after the point where anything
    could have explained why.

    Mirrors genesi-ai-turbo's detection deliberately — nvidia-smi first (it is
    authoritative where the proprietary/open driver is loaded), then llama.cpp's
    own device list, which is vendor-agnostic and, importantly, reports the
    device the RPC server would actually expose. Under nouveau/NVK nvidia-smi
    exists but cannot talk to the driver, so the second probe is not a
    nicety — it is the only one that works on a stock live session."""
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.run(
                ["nvidia-smi", "--query-gpu=memory.total,memory.free,name",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=5).stdout
            best, best_free, best_name = 0, None, ""
            for line in out.splitlines():
                parts = [p.strip() for p in line.split(",")]
                if parts and parts[0].isdigit() and int(parts[0]) > best:
                    best = int(parts[0])
                    best_free = int(parts[1]) if len(parts) > 1 \
                        and parts[1].isdigit() else None
                    best_name = parts[2] if len(parts) > 2 else ""
            if best:
                # nvidia-smi answering at all means a real NVIDIA card with its
                # own memory; NVIDIA ships no integrated consumer GPU here.
                return {"backend": "CUDA", "vram_mb": best, "free_mb": best_free,
                        "name": best_name or "NVIDIA GPU", "integrated": False}
        except (OSError, subprocess.SubprocessError, ValueError):
            pass

    binp = llama_bin("llama-server") or rpc_server_bin()
    if binp:
        try:
            res = subprocess.run([binp, "--list-devices"],
                                 capture_output=True, text=True, timeout=20)
            text = (res.stdout or "") + (res.stderr or "")
            best, best_free, best_name = 0, None, ""
            # e.g. "  CUDA0: NVIDIA GeForce RTX 3050 (7837 MiB, 801 MiB free)".
            # The free figure is optional: older builds print only the capacity.
            for match in re.finditer(
                    r"^\s*\w+\d+:\s*(.+?)\s*\((\d+)\s*MiB"
                    r"(?:,\s*(\d+)\s*MiB\s+free)?", text, re.M):
                size = int(match.group(2))
                if size > best:
                    best, best_name = size, match.group(1)
                    best_free = int(match.group(3)) if match.group(3) else None
            if not best:            # older builds print only the size
                best = max([int(m.group(1))
                            for m in re.finditer(r"\((\d+)\s*MiB", text)],
                           default=0)
            if best:
                backend = "CUDA" if re.search(r"\bCUDA\d", text) else "Vulkan"
                return {"backend": backend, "vram_mb": best,
                        "free_mb": best_free, "name": best_name,
                        "integrated": _looks_integrated(best_name, best)}
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
    return {"backend": "CPU", "vram_mb": 0, "free_mb": None, "name": "",
            "integrated": False}


def llama_build():
    """This machine's llama.cpp identity: {build, proto, ops} — any may be None.

    Why the mesh cares about a version number at all: the RPC backend's wire
    format is tied to the ggml build on BOTH ends, and a mismatch does not fail
    cleanly. It fails like this, observed on two real machines —

        worker: build 10438      client: build 10454
        the weights transfer fine (2002 MiB land on the worker's GPU)
        and then the client hangs forever at "loading model"

    — because the handshake compares only RPC_PROTO_*, which matched, while the
    thing that actually diverged was the ggml OPERATION ENUM. Op codes are sent
    as bare integers, so once the two sides disagree about what op 47 means, the
    server does the wrong work and the client waits for a reply that fits a
    shape it will never get. Upstream marks this with a static_assert on
    GGML_OP_COUNT precisely because the protocol version is easy to forget.

    So `ops` is the discriminating field, not `proto`: proto catches the
    mismatches that already announce themselves, ops catches the silent one."""
    info = {"build": None, "proto": None, "ops": None}

    # The installed header is authoritative and free to read — no subprocess,
    # no GPU touched. Absent on a runtime-only install, hence the build number
    # as a coarser fallback.
    try:
        with open("/usr/include/ggml-rpc.h", "r", encoding="utf-8") as fh:
            text = fh.read()
        ver = [re.search(r"RPC_PROTO_%s_VERSION\s+(\d+)" % part, text)
               for part in ("MAJOR", "MINOR", "PATCH")]
        if all(ver):
            info["proto"] = ".".join(m.group(1) for m in ver)
        ops = re.search(r"GGML_OP_COUNT\s*==\s*(\d+)", text)
        if ops:
            info["ops"] = int(ops.group(1))
    except (OSError, ValueError):
        pass

    binp = llama_bin("llama-server") or rpc_server_bin()
    if binp:
        try:
            res = subprocess.run([binp, "--version"], capture_output=True,
                                 text=True, timeout=15)
            match = re.search(r"build\s+(\d+)",
                              (res.stdout or "") + (res.stderr or ""))
            if match:
                info["build"] = int(match.group(1))
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
    return info


def rpc_compatibility(local, peer):
    """(ok, note) for pooling between two llama.cpp builds.

    Conservative in one direction only. A KNOWN difference is reported as
    incompatible, because the failure mode is a silent hang that costs minutes
    and explains nothing. Anything unknown stays usable — refusing to pool over
    a version we could not read would break working setups to prevent a
    hypothetical one."""
    l_ops, p_ops = local.get("ops"), peer.get("ops")
    if l_ops and p_ops and l_ops != p_ops:
        return False, ("different ggml operation sets (%d here, %d there). The "
                       "RPC protocol sends op codes as plain numbers, so the "
                       "two ends would disagree about what each one means — "
                       "the load hangs instead of failing" % (l_ops, p_ops))

    l_proto, p_proto = local.get("proto"), peer.get("proto")
    if l_proto and p_proto and l_proto.split(".")[0] != p_proto.split(".")[0]:
        return False, ("incompatible RPC protocol (v%s here, v%s there)"
                       % (l_proto, p_proto))

    l_build, p_build = local.get("build"), peer.get("build")
    if l_build and p_build and l_build != p_build:
        # Not fatal on its own — many builds interoperate — but it is the first
        # thing to check when a pooled load misbehaves, so say it out loud.
        return True, ("different llama.cpp builds (%d here, %d there); if a "
                      "pooled load hangs, match them first" % (l_build, p_build))
    return True, ""


def probe_free_mb():
    """Free VRAM right now, or None when it cannot be measured cheaply.

    Deliberately nvidia-smi only. probe_gpu()'s other path shells out to
    `llama-server --list-devices`, which INITIALISES the backend — seconds of
    work that touches the GPU. Fine once at startup, unacceptable every five
    seconds on a beacon timer.

    Returning None where we cannot poll is the point: it makes the beacon omit
    the field, so peers fall back to capacity instead of trusting a boot-time
    reading that went stale the instant anything allocated."""
    if not shutil.which("nvidia-smi"):
        return None
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.free",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5).stdout
        vals = [int(line.strip()) for line in out.splitlines()
                if line.strip().isdigit()]
        # The largest card, matching probe_gpu's "best device" choice — they
        # must describe the SAME GPU or the free figure belongs to another one.
        return max(vals) if vals else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


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


def peer_available_mb(peer):
    """What a peer can actually give us, in MiB.

    Its FREE memory when the peer reports it, its capacity when it does not
    (an older node, or a machine that cannot poll cheaply). Capacity is the
    optimistic answer and it is what this planner used to assume for everyone,
    which is precisely the bug: a worker with an 8 GB card busy running its own
    5.7 GB model advertised 8 GB, this planner promised the client 6.8 GB of
    pooled VRAM, and llama.cpp then died with

        failed to allocate RPC0[host:50052] buffer of size 2011539712

    after the model was already loading. The number has to be honest here, at
    planning time, or the failure surfaces where nothing can explain it."""
    free = peer.get("free_mb")
    if isinstance(free, (int, float)):
        return int(free)
    return int(peer.get("vram_mb") or 0)


def peer_budget_gb(peer):
    """A peer's usable contribution in GB, after per-GPU overhead."""
    return max(peer_available_mb(peer) / 1024.0 - GPU_OVERHEAD_GB, 0.0)


def peer_llama(peer):
    """The llama.cpp identity a peer advertised, in llama_build()'s shape."""
    return {key: peer.get("llama_" + key) for key in ("build", "proto", "ops")}


def plan_pool(local_gpu, peers, model_gb, pool_integrated=False, local_llama=None):
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

    local_llama = local_llama if local_llama is not None else llama_build()
    usable, skipped_integrated, skipped_busy = [], [], []
    skipped_incompatible = []
    for peer in peers:
        if not peer.get("worker") or int(peer.get("vram_mb") or 0) <= 0:
            continue
        if peer.get("integrated") and not pool_integrated:
            skipped_integrated.append(peer)
            continue
        # Before memory, before anything: can these two llama.cpp builds even
        # talk? Pooling with a mismatched peer does not fail, it HANGS, so this
        # has to be caught while there is still someone to report it to.
        compatible, note = rpc_compatibility(local_llama, peer_llama(peer))
        if not compatible:
            peer = dict(peer, incompatible=note)
            skipped_incompatible.append(peer)
            continue
        if peer_budget_gb(peer) <= 0:
            # Capacity it has; room it does not. Almost always the peer is busy
            # running something on the GPU it is offering.
            skipped_busy.append(peer)
            continue
        usable.append(peer)
    usable.sort(key=peer_budget_gb, reverse=True)

    pooled = local_budget + sum(peer_budget_gb(p) for p in usable)

    def _result(**kw):
        kw.setdefault("skipped_integrated",
                      [p.get("host", "?") for p in skipped_integrated])
        kw.setdefault("skipped_incompatible",
                      [p.get("host", "?") for p in skipped_incompatible])
        kw.setdefault("skipped_busy",
                      ["%s (%d MiB free)" % (p.get("host", "?"),
                                             peer_available_mb(p))
                       for p in skipped_busy])
        return kw

    def _incompatible_note():
        if not skipped_incompatible:
            return ""
        return " " + "; ".join(
            "%s skipped: %s" % (p.get("host", "?"), p.get("incompatible"))
            for p in skipped_incompatible)

    def _busy_note():
        """A peer with a GPU but no room is the confusing case: `peers` lists it
        as a healthy worker, so "no worker peers online" would flatly contradict
        what the user just saw. Name it and say what to do."""
        if not skipped_busy:
            return ""
        return (" %s has a GPU but almost nothing free — something is already "
                "using it there (check `nvidia-smi` on that machine)."
                % ", ".join(p.get("host", "?") for p in skipped_busy))

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
        if skipped_incompatible:
            return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                           pooled_gb=pooled, peers=[],
                           reason="no usable worker peers." + _incompatible_note())
        if skipped_busy:
            return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                           pooled_gb=pooled, peers=[],
                           reason="no worker peers with free VRAM." + _busy_note())
        return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                       pooled_gb=pooled, peers=[],
                       reason="no worker peers online")

    if model_gb > pooled:
        return _result(use_mesh=False, endpoints=[], local_gb=local_budget,
                       pooled_gb=pooled, peers=usable,
                       reason=("too big even pooled (%.1f GB needed, %.1f GB "
                               "free across the mesh)%s"
                               % (model_gb, pooled, _busy_note())))

    endpoints = ["%s:%d" % (p["addr"], int(p.get("rpc_port") or DEFAULT_RPC_PORT))
                 for p in usable if p.get("addr")]
    return _result(use_mesh=True, endpoints=endpoints, local_gb=local_budget,
                   pooled_gb=pooled, peers=usable,
                   reason=("%.1f GB model does not fit locally (%.1f GB) but fits "
                           "across %d machine(s) (%.1f GB pooled)"
                           % (model_gb, local_budget, len(usable), pooled)))
