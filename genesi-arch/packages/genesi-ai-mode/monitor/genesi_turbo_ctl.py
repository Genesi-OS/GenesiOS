#!/usr/bin/env python3
"""
Shared, Qt-free control of the Genesi Turbo llama-server (:11435).

Both the AI Mode Monitor backend (genesi_ai_monitor.py) and the automation
daemon (genesi-automationd) reuse this to:
  * detect the installed backend (cuda/vulkan) and whether llama-server exists,
  * know if a Turbo server is alive and WHICH model it's serving,
  * ensure Turbo serves a specific model, restarting it if it's the wrong one,
  * stop Turbo and free the port cleanly.

There is deliberately NO PySide6 import here so the headless daemon can import
it without a Qt runtime. The Monitor keeps its own signal-emitting _start_turbo/
_stop_turbo (proven, shipped) and only borrows the probes + the model marker from
here; the daemon uses ensure()/stop() directly.

Model marker
------------
llama-server exposes /health but not the tag it's serving, and the tag→blob
resolution lives inside `genesi-ai-turbo serve`. So whoever starts Turbo through
Genesi (the Monitor or this module) records the resolved tag in a per-user marker
file; current_model() reads it back. A server started outside Genesi (a manual
`genesi-ai-turbo serve X`, or genesi-turbo.service) leaves the marker empty, i.e.
"unknown" — callers that need a specific model then restart to be safe.
"""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.request

OLLAMA = "http://127.0.0.1:11434"
TURBO = "http://127.0.0.1:11435"
TURBO_PORT = 11435
STATE_FILE = "/run/genesi-ai-mode/state.json"


# ── model marker (per-user runtime file) ─────────────────────────────────────
def _runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()


def _marker_path():
    return os.path.join(_runtime_dir(), "genesi-turbo-model")


def write_marker(model):
    try:
        with open(_marker_path(), "w") as fh:
            fh.write(model or "")
    except OSError:
        pass


def clear_marker():
    try:
        os.unlink(_marker_path())
    except OSError:
        pass


def marker_model():
    try:
        with open(_marker_path()) as fh:
            return fh.read().strip()
    except OSError:
        return ""


# ── backend / server probing ─────────────────────────────────────────────────
def has_llama_server():
    """Is the Turbo backend (llama-server, from genesi-llama-cpp) present?"""
    return bool(shutil.which("llama-server") or os.path.exists("/usr/bin/llama-server"))


def installed_backend():
    """Which Turbo backend is installed: 'cuda', 'vulkan', or None."""
    def has(pkg):
        try:
            return subprocess.run(["pacman", "-Qq", pkg],
                                  capture_output=True, timeout=6).returncode == 0
        except Exception:
            return False
    if has("genesi-llama-cpp-cuda") or has("llama.cpp-cuda"):
        return "cuda"
    if has("genesi-llama-cpp"):
        return "vulkan"
    return "vulkan" if has_llama_server() else None


def nvidia_smi_works():
    """True only when the NVIDIA kernel driver is loaded AND functional."""
    if not shutil.which("nvidia-smi"):
        return False
    try:
        return subprocess.run(["nvidia-smi"], capture_output=True,
                              text=True, timeout=6).returncode == 0
    except Exception:
        return False


def has_gpu():
    try:
        s = json.loads(open(STATE_FILE).read())
        if (s.get("hardware") or {}).get("gpus"):
            return True
    except Exception:
        pass
    return shutil.which("nvidia-smi") is not None


def turbo_alive():
    """Is a Turbo llama-server answering on the port?"""
    try:
        with urllib.request.urlopen(TURBO + "/health", timeout=1) as r:
            if r.status != 200:
                return False
            try:
                return json.loads(r.read()).get("status", "ok") == "ok"
            except Exception:
                return True
    except Exception:
        return False


def current_model():
    """Tag of the model the running Turbo server is serving, or "" if Turbo is
    down or was started outside Genesi (unknown)."""
    if not turbo_alive():
        return ""
    return marker_model()


def kill_stray_turbo():
    """SIGTERM any llama-server bound to the Turbo port (even one we didn't
    start), wait for /health to go away, then SIGKILL if it's stubborn."""
    if not shutil.which("pkill"):
        return
    pattern = "llama-server.*--port %d" % TURBO_PORT
    subprocess.run(["pkill", "-f", pattern], check=False)
    for _ in range(24):              # up to ~6s for a clean shutdown
        if not turbo_alive():
            clear_marker()
            return
        time.sleep(0.25)
    subprocess.run(["pkill", "-9", "-f", pattern], check=False)
    for _ in range(16):              # up to ~4s after a force-kill
        if not turbo_alive():
            break
        time.sleep(0.25)
    clear_marker()


def ollama_unload_all():
    """Free the RAM Ollama holds via keep-alive by unloading every loaded model,
    so the Turbo llama-server has room. Blocks until Ollama releases it."""
    try:
        with urllib.request.urlopen(OLLAMA + "/api/ps", timeout=2) as r:
            models = json.loads(r.read().decode()).get("models", [])
    except Exception:
        return
    for m in models:
        name = m.get("name") or m.get("model")
        if not name:
            continue
        try:
            body = json.dumps({"model": name, "keep_alive": 0}).encode()
            req = urllib.request.Request(
                OLLAMA + "/api/generate", data=body,
                headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=15).read()
        except Exception:
            pass


# ── local GGUF models ────────────────────────────────────────────────────────
# A GGUF is addressed everywhere by the stable reference `gguf:<file stem>`, the
# form `genesi-ai-turbo` resolves. Keeping it a plain STRING is what lets a local
# model flow through every existing path unchanged — the chat/Quick Chat/Turbo
# pickers, an automation node's saved config, a chat session on disk — all of
# which already store a model as a string.
#
# The one hard rule: a GGUF can only be served by llama-server. Ollama's chat API
# knows its own registry and nothing else, so callers must route a GGUF to Turbo
# REGARDLESS of the user's Turbo preference (that switch selects speculative
# decoding, it is not what makes a local file loadable). Use serves_model() to do
# that routing and ensure() to bring the right server up.

def is_gguf_ref(model):
    """True when `model` names a local GGUF rather than an Ollama tag."""
    if not model:
        return False
    m = str(model)
    return (m.startswith("gguf:") or m.lower().endswith(".gguf")
            or (os.sep in m and os.path.isfile(os.path.expanduser(m))))


_GGUF_CACHE = {"at": 0.0, "items": []}
_GGUF_TTL = 20.0          # seconds; a rescan walks several directories


def list_gguf_models(force=False):
    """Local GGUF models as [{ref, label, path, moe, size_gb, params_b, fit}].

    Cached briefly so a picker can ask for labels repeatedly without re-walking
    the filesystem. Returns [] when the CLI is missing — never raises.
    """
    now = time.time()
    if not force and _GGUF_CACHE["items"] and now - _GGUF_CACHE["at"] < _GGUF_TTL:
        return _GGUF_CACHE["items"]
    items = []
    if shutil.which("genesi-ai-turbo"):
        try:
            r = subprocess.run(["genesi-ai-turbo", "gguf-list"],
                               capture_output=True, text=True, timeout=60)
            for e in json.loads(r.stdout or "[]"):
                stem = os.path.basename(e.get("path", ""))[:-5]
                if not stem:
                    continue
                items.append({
                    "ref": "gguf:" + stem,
                    "label": _label_for(e, stem),
                    "path": e.get("path", ""),
                    "moe": bool(e.get("moe")),
                    "size_gb": e.get("size_gb", 0),
                    "params_b": e.get("params_b", 0),
                    "fit": e.get("fit", ""),
                })
        except Exception:
            items = []
    _GGUF_CACHE["at"], _GGUF_CACHE["items"] = now, items
    return items


def _label_for(entry, stem):
    """A short human name for a picker: the GGUF's own name when it is
    meaningful, else the file stem, plus the parameter size when known."""
    name = (entry.get("name") or "").strip() or stem
    if len(name) > 42:
        name = name[:41].rstrip() + "…"
    params = entry.get("params_b") or 0
    size = f" · {params:g}B" if params else ""
    return f"{name}{size} (GGUF)"


def invalidate_gguf_cache():
    _GGUF_CACHE["at"] = 0.0


def model_label(model):
    """Display name for any model reference (GGUF ref or Ollama tag)."""
    if not is_gguf_ref(model):
        return model or ""
    for item in list_gguf_models():
        if item["ref"] == model:
            return item["label"]
    # Known-shape ref whose file is gone (deleted, or an external drive is
    # unplugged): show the stem rather than the raw `gguf:` scheme.
    m = str(model)
    return (m[5:] if m.startswith("gguf:") else os.path.basename(m)) + " (GGUF)"


def serves_model(model, spec=False, on_status=None, stop_check=None):
    """Bring up whatever `model` needs, and say whether Turbo is now REQUIRED.

    Returns (force_turbo, ok, message):
      * Ollama tag -> (False, True, "")   nothing to do; the caller's own Turbo
                                          preference still decides where it goes.
      * GGUF ref   -> (True,  ok,   msg)  ensure() ran; llama-server is the only
                                          thing that can load a GGUF, so the
                                          caller MUST use the Turbo path when ok.

    Callers combine it with their own preference:  use_turbo = force or self._turbo
    That is what makes a local GGUF behave like any pulled model in the chat,
    Quick Chat and automations, with or without the Turbo switch.
    """
    if not is_gguf_ref(model):
        return False, True, ""
    ok, msg = ensure(model, spec=spec, on_status=on_status, stop_check=stop_check)
    return True, ok, msg


def _noop(_msg):
    pass


def ensure(model, spec=False, on_status=None, timeout=900, stop_check=None):
    """Make Turbo serve `model` with the given spec mode, restarting it if it is
    serving something else (or an unknown/outside server). Returns (ok, message).

    BLOCKS until the server is healthy or times out — call it from a worker
    thread. `on_status(msg)` receives human-readable progress; `stop_check()`
    returning True aborts early. This is the headless twin of the Monitor's
    _start_turbo and the core of the automation AI block's "turbo on the chosen
    model" requirement.
    """
    status = on_status or _noop
    should_stop = stop_check or (lambda: False)
    if not model:
        return False, "no model chosen"
    if not shutil.which("genesi-ai-turbo"):
        return False, "genesi-ai-turbo not found"
    if not has_llama_server():
        return False, "Turbo backend (llama-server) not installed"

    # Right model already up? nothing to do.
    if turbo_alive() and marker_model() == model:
        write_marker(model)
        return True, "Turbo already serving " + model

    # Wrong model, or a server we didn't start: tear it down and start clean.
    status("freeing the Turbo port…")
    kill_stray_turbo()
    status("freeing Ollama's memory…")
    ollama_unload_all()
    if should_stop():
        return False, "cancelled"

    status("starting Turbo (loading the model)…")
    log = tempfile.NamedTemporaryFile("w", delete=False, suffix=".log").name
    try:
        proc = subprocess.Popen(
            ["genesi-ai-turbo", "serve", model] + (["--spec"] if spec else ["--no-spec"]),
            stdout=subprocess.DEVNULL, stderr=open(log, "w"),
            start_new_session=True)
    except Exception as exc:
        return False, "error starting Turbo: " + str(exc)

    def _tail():
        try:
            return "".join(open(log).readlines()[-2:]).strip()
        except Exception:
            return ""

    for i in range(int(timeout)):
        if should_stop():
            try:
                proc.send_signal(signal.SIGINT)
            except Exception:
                pass
            return False, "cancelled"
        if turbo_alive():
            write_marker(model)
            try:
                os.unlink(log)
            except OSError:
                pass
            return True, ("Turbo active ⚡ " +
                          ("speculative decoding" if spec else "full GPU offload"))
        if proc.poll() is not None:
            # Helper gone. `serve` may have reused a healthy server and exited 0 —
            # health wins over a dead helper proc.
            if turbo_alive():
                write_marker(model)
                return True, "Turbo active"
            msg = _tail()
            return False, ("Turbo failed: " +
                           (msg.splitlines()[-1] if msg else
                            "run: genesi-ai-turbo serve " + model))
        secs = i + 1
        elapsed = f"{secs // 60}m{secs % 60:02d}s" if secs >= 60 else f"{secs}s"
        status(f"loading the model… {elapsed}")
        time.sleep(1)
    return False, "Turbo took too long to load"


def stop(on_status=None):
    """Stop any Turbo server and free the port + marker. Best-effort."""
    (on_status or _noop)("stopping Turbo…")
    kill_stray_turbo()
    clear_marker()
