"""Genesi AI Assist — the shared gate for passive, always-on AI helpers.

Features like "explain the command that just failed" are only pleasant if they
are *free*. The moment one of them loads a model, spins the GPU, or fires while
the user is already generating something, it stops being a helper and becomes
the reason the machine feels slow. So every passive helper in Genesi asks this
module for permission first, and every one of them obeys the same rules:

  1. NEVER load a model. Passive helpers use whatever is ALREADY warm on the
     Turbo daemon. No warm model means the feature silently does not happen —
     it does not queue, it does not fall back, it does not "just this once".
  2. Yield to real work. If AI Mode reports the workload as `active` (the user
     is generating something), or Studio Mode has handed the machine to one
     app, passive helpers go quiet.
  3. Respect battery. On battery they are off by default, because a background
     inference the user did not ask for is the rudest possible use of a laptop's
     remaining charge.
  4. Stay tiny. Small token budgets, short timeouts, and an on-disk cache so the
     same question is never paid for twice.
  5. Be individually switchable, and fail silent. A helper that errors must
     leave no trace in the user's terminal.

Config: /etc/genesi-ai-assist.conf, overridden per-user by
~/.config/genesi-ai-assist.conf. Read live; no restart.

Stdlib only, matching the rest of the Genesi AI stack.
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path



def turbo_url():
    """Where to send inference: GENESI_TURBO_URL, else a mesh peer serving
    Turbo, else loopback.

    A machine with no GPU finds the one that has it through the same discovery
    the mesh already runs, so nothing has to be configured by hand. Serving over
    HTTP beats pooling VRAM whenever the model fits on the far box: this ships
    the text of a conversation, pooling ships layer activations per token."""
    override = (os.environ.get("GENESI_TURBO_URL") or "").strip()
    if override:
        return override.rstrip("/")
    sys.path.insert(0, "/usr/lib/genesi-mesh")
    try:
        import genesi_mesh_common as _mesh
        return _mesh.turbo_url()
    except Exception:
        return "http://127.0.0.1:11435"
STATE_JSON = "/run/genesi-ai-mode/state.json"
STUDIO_STATE = "/run/genesi-studio/state.json"

SYSTEM_CONF = "/etc/genesi-ai-assist.conf"
USER_CONF = Path.home() / ".config/genesi-ai-assist.conf"
CACHE_DIR = Path.home() / ".cache/genesi-ai-assist"

DEFAULTS = {
    "enabled": "on",           # master switch for every passive helper
    "explain_errors": "on",    # the shell hook that explains a failed command
    "on_battery": "off",       # run passive helpers while on battery?
    "max_tokens": "160",       # per call; an explanation is a paragraph, not an essay
    "timeout": "6",            # seconds; if the model is busy we would rather give up
    "cache_days": "30",
}


# ── Config ───────────────────────────────────────────────────────────────────

def load_conf():
    conf = dict(DEFAULTS)
    for path in (SYSTEM_CONF, USER_CONF):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, value = line.split("=", 1)
                    conf[key.strip()] = value.strip()
        except OSError:
            continue
    return conf


def _flag(conf, key):
    return str(conf.get(key, "")).strip().lower() in ("1", "on", "true", "yes")


def _int(conf, key, default):
    try:
        return int(str(conf.get(key, "")).strip())
    except (TypeError, ValueError):
        return default


# ── Machine state ────────────────────────────────────────────────────────────

def _read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def on_battery():
    """True when running on battery. Reads sysfs directly: `upower` may not be
    installed and spawning it would cost more than the check is worth."""
    try:
        for supply in Path("/sys/class/power_supply").iterdir():
            try:
                if (supply / "type").read_text().strip() != "Mains":
                    continue
                return (supply / "online").read_text().strip() == "0"
            except OSError:
                continue
    except OSError:
        pass
    return False          # no battery reported: treat as a desktop


def ai_activity():
    """AI Mode's own classification: active | warm | idle | unknown.

    `active` means the user is generating something right now, which is exactly
    when a passive helper must not add a second request to the queue."""
    return (_read_json(STATE_JSON).get("activity") or "unknown")


def studio_active():
    state = _read_json(STUDIO_STATE)
    return bool(state.get("active") or state.get("enabled"))


def warm_model():
    """The model already resident on the Turbo daemon, or None.

    This is the whole gate. Passive helpers ride an existing warm model or do
    not run at all; asking /v1/models is cheap and, crucially, does NOT cause a
    load the way a completion request against a cold server would."""
    try:
        with urllib.request.urlopen(turbo_url() + "/v1/models", timeout=1.5) as resp:
            data = json.load(resp)
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return None
    items = data.get("data") or []
    if not items:
        return None
    return items[0].get("id") or None


# ── The gate ─────────────────────────────────────────────────────────────────

def allowed(feature, conf=None):
    """(ok, reason). `reason` is for `--why`, never for the user's terminal."""
    conf = conf if conf is not None else load_conf()

    if not _flag(conf, "enabled"):
        return False, "genesi-ai-assist is disabled"
    if feature and feature in conf and not _flag(conf, feature):
        return False, "%s is disabled" % feature
    if on_battery() and not _flag(conf, "on_battery"):
        return False, "on battery (set on_battery = on to allow)"
    if studio_active():
        return False, "Studio Mode has the machine"

    activity = ai_activity()
    if activity == "active":
        return False, "a real inference is running"

    model = warm_model()
    if not model:
        return False, "no model is warm on the Turbo daemon"
    return True, model


# ── Asking the warm model ────────────────────────────────────────────────────

def _cache_path(key):
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]
    return CACHE_DIR / (digest + ".json")


def cache_get(key, conf=None):
    conf = conf if conf is not None else load_conf()
    path = _cache_path(key)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    age_days = (time.time() - payload.get("ts", 0)) / 86400.0
    if age_days > _int(conf, "cache_days", 30):
        return None
    return payload.get("text")


def cache_put(key, text):
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _cache_path(key).write_text(
            json.dumps({"ts": time.time(), "text": text}), encoding="utf-8")
    except OSError:
        pass


def ask(system, user, feature="", cache_key=None, conf=None):
    """One small completion against the already-warm model, or None.

    Returns None for every failure — no model, gate closed, timeout, malformed
    reply. Callers print nothing when they get None, so a passive helper can
    never leave an error in the user's terminal.
    """
    conf = conf if conf is not None else load_conf()

    if cache_key:
        hit = cache_get(cache_key, conf)
        if hit is not None:
            return hit

    ok, _reason = allowed(feature, conf)
    if not ok:
        return None

    body = json.dumps({
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": user}],
        "max_tokens": _int(conf, "max_tokens", 160),
        "temperature": 0.1,
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        turbo_url() + "/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=_int(conf, "timeout", 6)) as resp:
            data = json.load(resp)
        text = data["choices"][0]["message"]["content"].strip()
    except (urllib.error.URLError, OSError, ValueError, KeyError,
            IndexError, TimeoutError):
        return None

    if not text:
        return None
    if cache_key:
        cache_put(cache_key, text)
    return text
