"""genesi_island_link -- what the Quick Chat and every AI island share.

The AI island is one card (GenesiAiIslandCard.qml) in two hosts: caelestia
draws it on Hyprland, and genesi-ai-island draws it on every other desktop.
Both READ the state the Quick Chat publishes and both send their answers back
over the Quick Chat's socket. This module is that contract, and nothing else:
no Qt, so the Quick Chat, the standalone island and the tests can all import
it without starting a GUI.

    $XDG_RUNTIME_DIR/genesi-ai-island.json      what the chat is doing (chat writes)
    $XDG_RUNTIME_DIR/genesi-ai-quick.sock       commands to the chat
    $XDG_RUNTIME_DIR/genesi-ai-island-ui.pid    the standalone island, when it runs
    ~/.config/genesi/ai-island.json             how the island behaves {mode, smartClip}
    ~/.config/genesi/plugins/ai-island.json     whether there is an island {enabled}
"""

import glob
import json
import os
import re
import shutil
import socket
import tempfile

SOCKET_NAME = "genesi-ai-quick.sock"
STATE_NAME = "genesi-ai-island.json"
UI_PID_NAME = "genesi-ai-island-ui.pid"

DEFAULT_PREFS = {"mode": "always", "smartClip": False}
MODES = ("always", "quickchat")


# ── Where things are ────────────────────────────────────────────────────────

def runtime_dir():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp/genesi-ai-%d" % os.getuid()
    os.makedirs(runtime, mode=0o700, exist_ok=True)
    return runtime


def socket_path():
    return os.path.join(runtime_dir(), SOCKET_NAME)


def state_path():
    return os.path.join(runtime_dir(), STATE_NAME)


def ui_pid_path():
    return os.path.join(runtime_dir(), UI_PID_NAME)


def config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ.get("HOME") or os.path.expanduser("~"), ".config")


def prefs_path():
    return os.path.join(config_home(), "genesi", "ai-island.json")


def plugin_path():
    return os.path.join(config_home(), "genesi", "plugins", "ai-island.json")


def _write_json(path, data):
    """Whole or not at all: a reader never sees half a file."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False)
            handle.write("\n")
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ── How the island behaves ──────────────────────────────────────────────────

def read_prefs():
    prefs = dict(DEFAULT_PREFS)
    try:
        with open(prefs_path(), encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return prefs
    if isinstance(raw, dict):
        if raw.get("mode") in MODES:
            prefs["mode"] = raw["mode"]
        if isinstance(raw.get("smartClip"), bool):
            prefs["smartClip"] = raw["smartClip"]
    return prefs


def write_prefs(**changes):
    """Change some of the island's settings; the rest stay. Returns them all."""
    prefs = read_prefs()
    if changes.get("mode") in MODES:
        prefs["mode"] = changes["mode"]
    if isinstance(changes.get("smartClip"), bool):
        prefs["smartClip"] = changes["smartClip"]
    _write_json(prefs_path(), prefs)
    return prefs


def parse_setting(key, value):
    """A setting as the island sends it ("smartClip", "on") -> (key, value),
    or None for one nobody knows. Strings on the wire, real types here."""
    value = str(value).strip().lower()
    if key == "mode" and value in MODES:
        return "mode", value
    if key == "smartClip" and value in ("on", "off", "true", "false", "1", "0"):
        return "smartClip", value in ("on", "true", "1")
    if key == "actions" and value in ("approval", "automatic"):
        return "actions", value
    if key == "enabled" and value in ("on", "off", "true", "false", "1", "0"):
        return "enabled", value in ("on", "true", "1")
    return None


# ── Whether there is an island, and who draws it ────────────────────────────

def caelestia_session(env=None):
    """caelestia draws the island in its own shell on Hyprland. The
    standalone one must never show up next to it."""
    env = os.environ if env is None else env
    return bool(env.get("HYPRLAND_INSTANCE_SIGNATURE")) and shutil.which("caelestia") is not None


def enabled(env=None):
    """The plugin switch. Written -> what it says. Never written: off inside
    caelestia (a shell plugin is off until switched on, like every other),
    ON everywhere else -- there the island is how the chat asks for approval
    without jumping over what you are doing, and in "always" mode it is a
    small pill; nobody has to find a switch to get it."""
    try:
        with open(plugin_path(), encoding="utf-8") as handle:
            return json.load(handle).get("enabled") is True
    except (OSError, ValueError, AttributeError):
        return not caelestia_session(env)


def set_enabled(on):
    path = plugin_path()
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}
    data["enabled"] = bool(on)
    _write_json(path, data)


def pid_alive(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    return os.path.exists("/proc/%d" % pid)


def standalone_running():
    try:
        with open(ui_pid_path(), encoding="utf-8") as handle:
            return pid_alive(handle.read().strip())
    except OSError:
        return False


# ── Which kind of window the standalone island can be ───────────────────────

LAYER_PLUGIN_GLOBS = (
    "/usr/lib/qt6/plugins/wayland-shell-integration/liblayer-shell*.so",
    "/usr/lib/qt/plugins/wayland-shell-integration/liblayer-shell*.so",
)
LAYER_QML_DIRS = ("/usr/lib/qt6/qml/org/kde/layershell", "/usr/lib/qt/qml/org/kde/layershell")
# Mutter and its forks have no layer-shell: a Wayland surface there cannot
# say "the top of the screen". Through XWayland a window can.
NO_LAYER_SHELL = ("gnome", "cinnamon", "pantheon", "unity")


def layer_shell_available(globber=glob.glob, isdir=os.path.isdir):
    return any(globber(g) for g in LAYER_PLUGIN_GLOBS) and any(isdir(d) for d in LAYER_QML_DIRS)


def platform_choice(env=None, layer_ok=None):
    """
    "layer"  -- a wlr-layer-shell surface: KDE Plasma, Niri, COSMIC, Sway,
                labwc (Budgie 10.10, Xfce on Wayland)... pinned to the top,
                above windows, never in the taskbar.
    "xcb"    -- an X11 window: every X11 session, and GNOME/Cinnamon on
                Wayland through XWayland, where it can still be placed.
    "native" -- a plain Wayland window, where neither exists. It works; the
                compositor decides where it goes.
    """
    env = os.environ if env is None else env
    desktop = (env.get("XDG_CURRENT_DESKTOP") or "").lower()
    wayland = bool(env.get("WAYLAND_DISPLAY")) or env.get("XDG_SESSION_TYPE") == "wayland"
    if not wayland:
        return "xcb"
    if any(name in desktop for name in NO_LAYER_SHELL):
        return "xcb" if env.get("DISPLAY") else "native"
    if layer_ok is None:
        layer_ok = layer_shell_available()
    if layer_ok:
        return "layer"
    return "xcb" if env.get("DISPLAY") else "native"


# ── Talking to the Quick Chat ───────────────────────────────────────────────

def send(command, timeout=0.5):
    """A command for the running Quick Chat: a bare word or a JSON object
    string. False when there is no chat to hear it."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(timeout)
            client.connect(socket_path())
            client.sendall(command.encode("utf-8"))
        return True
    except OSError:
        return False


def read_state():
    try:
        with open(state_path(), encoding="utf-8") as handle:
            state = json.load(handle)
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


# ── Smart Copy ──────────────────────────────────────────────────────────────
#
# Copying an error is the most common "I need help with this" there is: the
# island notices and offers to explain it. A long text gets "summarize?".
# Everything else -- a word, a link, a password -- is left alone, and the
# text never leaves the machine unless the person clicks.

ERROR_PATTERNS = re.compile(
    r"(Traceback \(most recent call last\)|^\s*(?:[\w.]*Error|Exception)\b[:(]|\berror(?:\[[A-Z]?\d+\])?:"
    r"|\bfatal:|\bFATAL\b|\bpanic(?:ked)?\b|Segmentation fault|core dumped|command not found"
    r"|No such file or directory|Permission denied|\bfailed\b.*\b(?:with|to)\b|npm ERR!|E: |"
    r"undefined reference|cannot find symbol|SyntaxError|TypeError|ReferenceError|Uncaught\b)",
    re.IGNORECASE | re.MULTILINE)
SECRETISH = re.compile(r"^(?:\S{20,}|(?:sk|pk|ghp|gho|xox[abp])[-_][\w-]{10,})$")
LONG_TEXT = 600


def classify_clip(text):
    """(kind, preview) for a clipboard worth offering help with, else None.
    kind is "error" or "text"; preview is one line, short."""
    if not isinstance(text, str):
        return None
    body = text.strip()
    if len(body) < 12 or len(body) > 200_000:
        return None
    if "\n" not in body and SECRETISH.match(body):
        return None              # a token or a password: never offer to send it anywhere
    if ERROR_PATTERNS.search(body):
        lines = [l.strip() for l in body.splitlines() if l.strip()]
        hit = next((l for l in reversed(lines) if ERROR_PATTERNS.search(l)), lines[-1])
        return "error", hit[:140]
    words = len(body.split())
    if len(body) >= LONG_TEXT and words >= 80:
        first = " ".join(body.split()[:18])
        return "text", first[:140] + ("…" if words > 18 else "")
    return None
