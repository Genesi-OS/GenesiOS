#!/usr/bin/env python3
"""
ai-island-standalone-test.py -- the AI island on every desktop but caelestia's.

genesi-ai-island draws the same card caelestia does, in a window of its own.
None of it can be watched on a real desktop here, so this pins what decides
whether it works there:

  * which window it becomes on each desktop Genesi offers (layer-shell where
    the compositor has it, X11 where it does not, never layer-shell on
    Mutter, never X11 without a display);
  * its settings file and its switch, shared with caelestia and the chat --
    and that it is ON by default outside caelestia and OFF inside it;
  * Smart Copy only ever offers help with an error or a long text, and never
    with something that looks like a password or a token;
  * every button on the card turns into the right message to the chat, and
    a chat that is not running is started with the right arguments;
  * the window itself loads with the bundled card, shows and hides with the
    mode, and gives the pointer only to the card.
"""
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
if sys.platform == "win32":
    os.environ.setdefault("QT_QPA_FONTDIR", "C:/Windows/Fonts")
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
PKGS = os.path.normpath(os.path.join(HERE, "..", "packages"))
MON = os.path.join(PKGS, "genesi-ai-mode", "monitor")
SHELL = os.path.join(PKGS, "genesi-caelestia-shell")
sys.path.insert(0, MON)
# genesi_palette is genesi-ui-kit's; the PKGBUILD installs it beside the
# monitor's files, so it is found beside them here too.
sys.path.insert(1, os.path.join(PKGS, "genesi-ui-kit", "components"))

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== AI island, standalone ==")
tmp = tempfile.mkdtemp(prefix="island-ui-")
os.environ["XDG_RUNTIME_DIR"] = os.path.join(tmp, "run")
os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

import genesi_island_link as link  # noqa: E402

if not os.path.isdir("/proc"):
    # No /proc (a Windows run): this process is the one live pid there is.
    link.pid_alive = lambda pid: str(pid) == str(os.getpid())

# ── Which window, on which desktop ──────────────────────────────────────────
pc = link.platform_choice
cases = [
    ("KDE Plasma on Wayland", {"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "KDE", "DISPLAY": ":0"}, True, "layer"),
    ("Niri", {"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "niri"}, True, "layer"),
    ("COSMIC", {"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "COSMIC", "DISPLAY": ":1"}, True, "layer"),
    ("GNOME on Wayland goes through XWayland", {"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "GNOME", "DISPLAY": ":0"}, True, "xcb"),
    ("Cinnamon on Wayland too", {"XDG_SESSION_TYPE": "wayland", "XDG_CURRENT_DESKTOP": "X-Cinnamon", "DISPLAY": ":0"}, True, "xcb"),
    ("GNOME with no XWayland is a plain window", {"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "GNOME"}, True, "native"),
    ("Xfce on X11", {"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE", "XDG_SESSION_TYPE": "x11"}, True, "xcb"),
    ("LXDE on X11", {"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "LXDE"}, False, "xcb"),
    ("Wayland without layer-shell-qt falls back to XWayland", {"WAYLAND_DISPLAY": "w", "XDG_CURRENT_DESKTOP": "KDE", "DISPLAY": ":0"}, False, "xcb"),
]
for name, env, layer_ok, want in cases:
    got = pc(env, layer_ok=layer_ok)
    check(f"{name}: {want}", got == want, got)
check("layer-shell needs BOTH the Qt plugin and the QML module",
      link.layer_shell_available(globber=lambda g: ["x.so"], isdir=lambda d: False) is False
      and link.layer_shell_available(globber=lambda g: ["x.so"], isdir=lambda d: True) is True)

# ── Settings and the switch ─────────────────────────────────────────────────
check("no settings yet: always shown, Smart Copy off", link.read_prefs() == {"mode": "always", "smartClip": False})
link.write_prefs(mode="quickchat")
link.write_prefs(smartClip=True)
check("settings change one at a time and keep the rest",
      link.read_prefs() == {"mode": "quickchat", "smartClip": True})
link.write_prefs(mode="sideways")
check("a mode nobody knows is not written", link.read_prefs()["mode"] == "quickchat")
check("settings parse as the island sends them",
      link.parse_setting("smartClip", "on") == ("smartClip", True)
      and link.parse_setting("enabled", "off") == ("enabled", False)
      and link.parse_setting("actions", "automatic") == ("actions", "automatic")
      and link.parse_setting("mode", "x") is None and link.parse_setting("rm", "-rf") is None)

real_which = link.shutil.which
check("outside caelestia the island is on before anyone touches a switch", link.enabled() is True)
os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "abc"
link.shutil.which = lambda name: "/usr/bin/caelestia" if name == "caelestia" else real_which(name)
check("inside caelestia it is a shell plugin: off until switched on", link.enabled() is False)
link.set_enabled(True)
check("...and the switch is the same file caelestia reads", link.enabled() is True
      and json.load(io.open(link.plugin_path(), encoding="utf-8")) == {"enabled": True})
check("caelestia draws its own: the standalone one stands down", link.caelestia_session() is True)
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE")
link.shutil.which = real_which
link.set_enabled(False)
check("switched off is off everywhere", link.enabled() is False)
link.set_enabled(True)

# ── Smart Copy ──────────────────────────────────────────────────────────────
cc = link.classify_clip
trace = 'Traceback (most recent call last):\n  File "app.py", line 3, in <module>\n    main()\nKeyError: \'id\''
kind = cc(trace)
check("a Python traceback is an error, previewed by its last line", kind and kind[0] == "error" and "KeyError" in kind[1], kind)
check("a git failure is an error", (cc("error: failed to push some refs to 'origin'") or ("",))[0] == "error")
check("a shell failure is an error", (cc("bash: foo: command not found") or ("",))[0] == "error")
essay = " ".join(["Este é um parágrafo comum sobre o tempo e as plantas do jardim."] * 20)
check("a long text is offered a summary", (cc(essay) or ("",))[0] == "text")
check("a word, a link or a short sentence is left alone",
      cc("ok") is None and cc("https://genesios.org") is None and cc("vamos almoçar às 12h?") is None)
check("a token or a password is never offered to anyone",
      cc("ghp_abcdefghijklmnopqrstuvwxyz0123456789") is None and cc("sk-proj-AbCdEf123456789xyz") is None
      and cc("Xk9#mP2$vL8@qR5!wN3&") is None)

# ── The host: buttons become messages ───────────────────────────────────────
spec = importlib.util.spec_from_file_location("genesi_ai_island", os.path.join(MON, "genesi_ai_island.py"))
island = importlib.util.module_from_spec(spec)
spec.loader.exec_module(island)

sent, started = [], []
island.link.send = lambda wire, timeout=0.5: (sent.append(wire), True)[1]
host = island.Host("xcb")
host.command("approve", "req-1")
host.command("stop", "")
host.command("ask", json.dumps({"text": "quanto de RAM?", "clip": True}))
host.command("set", "mode=always")
host.command("attach", json.dumps({"path": "/tmp/a.pdf", "prompt": "Resuma"}))
host.command("toggle", "")
msgs = [json.loads(w) if w.startswith("{") else w for w in sent]
check("approve carries its id", msgs[0] == {"cmd": "approve", "id": "req-1"}, msgs[0])
check("stop is stop", msgs[1] == {"cmd": "stop"})
check("a question goes with its clipboard flag", msgs[2] == {"cmd": "ask", "text": "quanto de RAM?", "clip": True}, msgs[2])
check("a setting goes to the chat AND into the file at once",
      msgs[3] == {"cmd": "set", "key": "mode", "value": "always"} and link.read_prefs()["mode"] == "always")
check("a file goes with its request", msgs[4] == {"cmd": "attach", "path": "/tmp/a.pdf", "prompt": "Resuma"})
check("the pill's click toggles the chat", msgs[5] == "toggle")

island.link.send = lambda wire, timeout=0.5: False
island.subprocess.Popen = lambda argv, **kw: started.append(argv)
host.command("ask", json.dumps({"text": "oi", "clip": False}))
check("no chat running: the CLI is started with the question, and starts one",
      started and started[-1][-2:] == ["--ask", "oi"], started)

os.makedirs(os.environ["XDG_RUNTIME_DIR"], exist_ok=True)
with io.open(link.state_path(), "w", encoding="utf-8") as fh:
    json.dump({"phase": "thinking", "pid": os.getpid(), "turn": 1}, fh)
host.refresh()
check("the chat's state is read, and a live pid makes it live", host.live and json.loads(host.stateJson)["phase"] == "thinking")
with io.open(link.state_path(), "w", encoding="utf-8") as fh:
    json.dump({"phase": "thinking", "pid": 99999999, "turn": 1}, fh)
host.refresh()
check("a state left by a chat that died is not live", host.live is False)
pal = island.material_palette()
check("the theme reaches the card under its own names", "m3primary" in pal and "m3onSurface" in pal, sorted(pal)[:5])

# ── The window, with the bundled card ───────────────────────────────────────
# Installed side by side (PKGBUILD bundles the card and the leaf from the
# shell package into monitor/), so staged side by side here.
stage = os.path.join(tmp, "stage")
os.makedirs(stage)
for name in ("IslandPlain.qml", "IslandStage.qml", "IslandLayer.qml"):
    shutil.copy(os.path.join(MON, name), stage)
for name in ("GenesiAiIslandCard.qml", "GenesiLeaf.qml"):
    shutil.copy(os.path.join(SHELL, name), stage)

from PySide6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

warnings = []
qInstallMessageHandler(lambda m, c, s: warnings.append(s))
app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])

masks = []
island.link.send = lambda wire, timeout=0.5: True
host = island.Host("xcb")
real_mask = host.setInputRect
host.setInputRect = lambda x, y, w, h: (masks.append((x, y, w, h)), real_mask(x, y, w, h))
link.write_prefs(mode="quickchat")
host.refreshPrefs()
host.refresh()
engine = QQmlApplicationEngine()
engine.rootContext().setContextProperty("islandHost", host)
engine.load(QUrl.fromLocalFile(os.path.join(stage, "IslandPlain.qml")))
roots = engine.rootObjects()
check("the island window loads with the bundled card", len(roots) == 1,
      "\n         ".join(w for w in warnings if "FT_New_Face" not in w))


def settle(seconds):
    end = time.time() + seconds
    while time.time() < end:
        app.processEvents()
        time.sleep(0.01)


if roots:
    win = roots[0]
    settle(0.5)
    check("with the chat closed and nothing going on, 'with the chat' mode hides it",
          win.property("visible") is False)
    with io.open(link.state_path(), "w", encoding="utf-8") as fh:
        json.dump({"phase": "running", "pid": os.getpid(), "turn": 2, "total": 1,
                   "steps": [{"title": "Run", "state": "running"}]}, fh)
    host.refresh()
    settle(0.6)
    check("...and the AI starting to work brings it up", win.property("visible") is True)
    check("only the card takes the pointer, not the whole window",
          masks and 0 < masks[-1][2] < 640 and 0 < masks[-1][3] < 470, masks[-3:])
    link.write_prefs(mode="always")
    host.refreshPrefs()
    with io.open(link.state_path(), "w", encoding="utf-8") as fh:
        json.dump({"phase": "idle", "pid": os.getpid(), "turn": 2}, fh)
    host.refresh()
    settle(0.6)
    check("'always' keeps the pill on screen when nothing is going on", win.property("visible") is True)
    noisy = [w for w in warnings if "FT_New_Face" not in w and "propagateSizeHints" not in w
             and "does not support" not in w]
    check("Qt printed no warnings", not noisy, "\n         ".join(noisy[:8]))

print()
if fails:
    print(f"ai island standalone: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("ai island standalone: OK")
