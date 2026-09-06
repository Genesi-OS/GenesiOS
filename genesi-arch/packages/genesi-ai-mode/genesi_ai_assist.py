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
import re
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
    "suggest_fix": "on",       # offer the fix as ghost text, accepted with →
    "suggest_fix_history": "on",  # fish only: seed the fix into fish's history
    "smart_find": "on",        # plain-language file search (genesi-find)
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


def flag(conf, key):
    """Public form of the on/off reader, for the helper scripts."""
    return _flag(conf, key)


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

def allowed(feature, conf=None, passive=True):
    """(ok, reason). `reason` is for `--why`, never for the user's terminal.

    `passive=False` is for helpers the user INVOKED (genesi-find), as opposed to
    ones that fire on their own. Those skip the courtesy checks — battery,
    Studio Mode, an inference already running — because the user asked for this
    one and is waiting for it. Rule 1 still holds for both: no warm model, no
    call. Nothing here ever loads a model.
    """
    conf = conf if conf is not None else load_conf()

    if not _flag(conf, "enabled"):
        return False, "genesi-ai-assist is disabled"
    if feature and feature in conf and not _flag(conf, feature):
        return False, "%s is disabled" % feature

    if passive:
        if on_battery() and not _flag(conf, "on_battery"):
            return False, "on battery (set on_battery = on to allow)"
        if studio_active():
            return False, "Studio Mode has the machine"
        if ai_activity() == "active":
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


CLOUD_CONF = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "genesi", "ai", "cloud.json")


def cloud_config():
    """
    The hosted model, if one is configured. None otherwise.

    Written by `genesi-ai-key`, which is also the only thing that should ever
    create this file: it is 0600 and holds a secret. Read here rather than
    passed in, because `ask()` is called from half a dozen helpers and none of
    them should have to know a cloud exists.
    """
    try:
        with open(CLOUD_CONF, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(d, dict) or not d.get("key") or not d.get("base_url"):
        return None
    return d


def _ask_cloud(cloud, payload, timeout):
    """
    One completion from the hosted model, or None.

    None on ANY failure, so `ask()` falls back to the local model. That
    fallback is the point: a settings app can turn the cloud on, but a network
    that is down or a key that expired must not stop the ghost-text fix in
    somebody's terminal from working. The local model is always there.
    """
    payload["model"] = cloud["model"]
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        cloud["base_url"].rstrip("/") + "/chat/completions", data=body,
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + cloud["key"]})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
        text = (data["choices"][0]["message"]["content"] or "").strip()
    except (urllib.error.URLError, OSError, ValueError, KeyError,
            IndexError, TimeoutError):
        return None
    return text or None


def ask(system, user, feature="", cache_key=None, conf=None,
        passive=True, max_tokens=None, timeout=None):
    """One small completion against the already-warm model, or None.

    Returns None for every failure — no model, gate closed, timeout, malformed
    reply. Callers print nothing when they get None, so a passive helper can
    never leave an error in the user's terminal.

    `passive=False`, `max_tokens` and `timeout` are for user-invoked helpers,
    which are allowed a slightly bigger budget than a helper that fires on its
    own — the user is sitting there waiting for the answer.
    """
    conf = conf if conf is not None else load_conf()

    if cache_key:
        hit = cache_get(cache_key, conf)
        if hit is not None:
            return hit

    ok, _reason = allowed(feature, conf, passive=passive)
    if not ok:
        return None

    payload = {
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": user}],
        "max_tokens": max_tokens or _int(conf, "max_tokens", 160),
        "temperature": 0.1,
        "stream": False,
    }

    # A hosted model, when one is configured AND this call is allowed to use
    # it. `passive` is the gate: the helpers that fire on their own -- the
    # ghost-text fix after a failed command -- run several times a minute in a
    # busy terminal, and a hosted model bills per token. They stay local unless
    # the key was set with `--for all`.
    text = None
    cloud = cloud_config()
    if cloud and (not passive or cloud.get("use_for") == "all"):
        text = _ask_cloud(cloud, dict(payload),
                          timeout or _int(conf, "timeout", 6) * 3)

    if text is None:
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            turbo_url() + "/v1/chat/completions", data=body,
            headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(
                    req, timeout=timeout or _int(conf, "timeout", 6)) as resp:
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


# ── The pending fix (ghost text in the shell) ────────────────────────────────
#
# When the explainer produces a one-line fix, it drops that line in a file the
# shell reads back at the next prompt, so the shell can offer it as dim ghost
# text that → accepts. The file is keyed by the SHELL's pid and lives on tmpfs
# (XDG_RUNTIME_DIR), so it is per-terminal, never survives a logout, and is
# unreadable by other users.
#
# The shell is what actually runs the command, and only after the user presses
# a key. Nothing here executes anything.

def fix_path(shell_pid):
    """Where this terminal's pending fix lives, or None.

    No XDG_RUNTIME_DIR (a non-systemd login, a stripped container) means no
    ghost text — we do NOT fall back to /tmp, where the path would be guessable
    by another user and the content is a command line about to be offered to a
    keypress."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if not runtime or not str(shell_pid).strip().isdigit():
        return None
    # Built with "/" rather than os.path.join: the shell hook composes the very
    # same path by hand, and the two must agree byte for byte.
    return "%s/genesi-ai-assist/fix.%s" % (runtime.rstrip("/"), shell_pid)


# Fixes that must never be one keypress away.
#
# The model is usually right, but "usually" is not the standard for a command
# the user can run by brushing an arrow key. Anything that deletes, overwrites
# or rewrites history stays PRINTED (the user can read it and type it out) and
# is never armed on →. This is the same instinct as the hook never re-running
# the failed command.
#
# Matched on WORD BOUNDARIES, not as substrings: a bare "dd " also appears in
# the middle of `cargo add serde`, and blocking every fix containing the letters
# d-d would quietly gut the feature.
_DANGEROUS_WORDS = re.compile(
    r"\b(rm|rmdir|shred|dd|fdisk|parted|wipefs|userdel|groupdel|truncate|"
    r"mkfs(\.\w+)?)\b")

# Phrases that are only dangerous as a whole, so a substring test is right.
_DANGEROUS_PHRASES = (
    "chmod -r", "chown -r", "> /dev/", ">/dev/", ":(){",
    "git reset --hard", "git clean -", "git push --force", "git push -f",
    "pacman -rdd", "pacman -rns", "systemctl mask", "mv /",
)


def fix_is_offerable(fix, failed_cmd=""):
    """True when `fix` is safe and sensible to arm on a keypress."""
    if not fix:
        return False
    fix = fix.strip()
    if not fix or "\n" in fix or len(fix) > 300:
        return False
    # A "fix" that is really a description, or a template the user must fill in.
    # A leading dash is refused too: a command line starts with a command, and
    # the shells put this string in front of builtins that would read it as a
    # flag.
    if fix.startswith(("#", "//", "-")) or "<" in fix or "..." in fix:
        return False
    # Never hand back the command that just failed.
    if failed_cmd and fix == failed_cmd.strip():
        return False
    # Piping a download straight into a shell, in any order of words.
    low = fix.lower()
    if ("curl" in low or "wget" in low) and ("| sh" in low or "| bash" in low
                                             or "|sh" in low or "|bash" in low):
        return False
    if any(bad in low for bad in _DANGEROUS_PHRASES):
        return False
    return not _DANGEROUS_WORDS.search(low)


def write_fix(path, fix, hist=False):
    """Publish the pending fix for the shell. Best effort, never raises.

    Two lines: the fix, then flags. bash and zsh `read` the first line and stop,
    which costs them nothing; fish reads both, because it is the one shell whose
    ghost text has to come from its own history (it has no API for setting an
    autosuggestion — fish-shell#9809), and `hist` says whether it may.
    """
    if not path or not fix:
        return False
    try:
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            os.write(fd, ("%s\nhist=%d\n" % (fix.strip(), 1 if hist else 0))
                     .encode("utf-8"))
        finally:
            os.close(fd)
        return True
    except OSError:
        return False
