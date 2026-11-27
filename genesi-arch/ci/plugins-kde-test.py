#!/usr/bin/env python3
"""
plugins-kde-test.py — Genesi's shell plugins, hosted on Plasma, played offscreen.

genesi-plugins hosts the SAME plugin QML caelestia draws (bundled from
genesi-caelestia-shell) in windows of its own, fed by a backend instead of
caelestia's services. This loads the real Stage with plain windows and a stub
backend, and checks each plugin comes up, does its job and writes the state
files in caelestia's own format -- so a person on both desktops keeps one set
of records and one leaf. Plus the backend's own pure functions, and that it
refuses to run inside Hyprland, where caelestia hosts them.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..", "packages", "genesi-store", "plugins-kde")
SHELL = os.path.join(HERE, "..", "packages", "genesi-caelestia-shell")
SHARED = ["GenesiGames", "GenesiGame2048", "GenesiGameBlocks", "GenesiGameBreakout",
          "GenesiGameFlappy", "GenesiGameMemory", "GenesiGameMines", "GenesiGameSimon",
          "GenesiGameSnake", "GenesiLeaf", "GenesiPetMind", "GenesiVinylDeck",
          "GenesiWeatherFx", "GenesiWrappedMath", "GenesiWrappedStory"]

fails = []


def check(name, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + name + (("  -- %s" % detail) if detail and not ok else ""))
    if not ok:
        fails.append(name)


# genesi_palette ships next to the host; in the tree it lives in the ui-kit.
sys.path.insert(0, os.path.join(HERE, "..", "packages", "genesi-ui-kit", "components"))
spec = importlib.util.spec_from_loader("gp", importlib.machinery.SourceFileLoader(
    "gp", os.path.join(PKG, "genesi_plugins.py")))
gp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gp)

# ── the backend's own functions ─────────────────────────────────────────────
print("== backend ==")
tmp = tempfile.mkdtemp(prefix="genesi-plugins-test-")
env = {"HOME": tmp, "XDG_CONFIG_HOME": os.path.join(tmp, "cfg")}
check("every plugin is off before anything is switched on",
      gp.enabled_map(env) == {p: False for p in gp.PLUGINS})
os.makedirs(gp.config_dir(env))
with open(os.path.join(gp.config_dir(env), "leaf.json"), "w") as fh:
    fh.write('{"enabled": true}')
with open(os.path.join(gp.config_dir(env), "vinyl.json"), "w") as fh:
    fh.write("not json")
on = gp.enabled_map(env)
check("the store's switch file turns a plugin on", on["leaf"] is True)
check("a broken switch file is off, not a crash", on["vinyl"] is False)
check("state lives where caelestia keeps it",
      gp.state_dir({"HOME": "/h"}) == os.path.join("/h", ".local", "state", "caelestia"))
check("commands parse", gp.parse_command(["toggle", "game-center"]) == "toggle game-center"
      and gp.parse_command(["wrapped"]) == "wrapped 7" and gp.parse_command([]) is None)
try:
    gp.parse_command(["rm", "-rf"])
    check("nonsense is refused", False)
except ValueError:
    check("nonsense is refused", True)
p = gp.parse_player("Playing\tSong\tArtist\tfile:///a.png\t30000000\t120000000\n")
check("playerctl output becomes what the deck draws",
      p["playing"] and p["present"] and p["title"] == "Song" and abs(p["progress"] - 0.25) < 1e-6)
check("nothing playing is not present", gp.parse_player("")["present"] is False)
apps = os.path.join(tmp, "apps")
os.makedirs(apps)
with open(os.path.join(apps, "org.mozilla.firefox.desktop"), "w") as fh:
    fh.write("[Desktop Entry]\nName=Firefox\nIcon=firefox\nStartupWMClass=firefox\n")
check("a window class finds its app name and icon",
      gp.app_info("firefox", [apps]) == {"name": "Firefox", "icon": "firefox"})
check("an unknown class falls back to itself",
      gp.app_info("weird", [apps]) == {"name": "weird", "icon": "weird"})
import re  # noqa: E402
used = set()
for name in SHARED:
    used |= set(re.findall(r"\bpal\.(m3[A-Za-z]+)", open(os.path.join(SHELL, name + ".qml"), encoding="utf-8").read()))
missing = sorted(used - set(gp.plugin_palette()))
check("the palette has every colour the plugin QML reads (%d roles)" % len(used), not missing, missing)
os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "x"
check("never runs inside Hyprland (caelestia hosts them there)", gp.main([]) == 0)
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE")

# ── the Stage, offscreen ────────────────────────────────────────────────────
print("== stage ==")
stage = os.path.join(tmp, "qml")
os.makedirs(stage)
for f in os.listdir(os.path.join(PKG, "qml")):
    shutil.copy(os.path.join(PKG, "qml", f), stage)
for name in SHARED:
    shutil.copy(os.path.join(SHELL, name + ".qml"), stage)

from PySide6.QtCore import Property, QObject, QUrl, Signal, Slot, qInstallMessageHandler  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

warnings = []
qInstallMessageHandler(lambda m, c, s: warnings.append(s))
app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])

statedir = os.path.join(tmp, "state")
os.makedirs(statedir)


class Host(QObject):
    changed = Signal()
    gameCenterToggled = Signal()
    wrappedRequested = Signal(int)

    def __init__(self):
        super().__init__()
        self._enabled = {"leaf": True, "vinyl": True, "live-weather": True,
                         "game-center": True, "wrapped": True}
        self.calls = []

    enabled = Property("QVariant", lambda s: s._enabled, notify=changed)
    palette = Property("QVariant", lambda s: gp.plugin_palette(), notify=changed)
    stats = Property("QVariant", lambda s: {"cpu": 12, "temp": 50, "idle": False, "updates": 0,
                                             "disk": 0.4, "hour": 10}, notify=changed)
    player = Property("QVariant", lambda s: {"present": True, "playing": True, "title": "Song",
                                              "artist": "Band", "art": "", "progress": 0.3}, notify=changed)
    weather = Property("QVariant", lambda s: {"code": 61, "wind": 0.4}, notify=changed)
    activeApp = Property(str, lambda s: "firefox", notify=changed)

    @Slot(str, result=str)
    def readState(self, name):
        try:
            with open(os.path.join(statedir, name)) as fh:
                return fh.read()
        except OSError:
            return ""

    @Slot(str, str)
    def writeState(self, name, text):
        with open(os.path.join(statedir, name), "w") as fh:
            fh.write(text)

    @Slot(str, result="QVariant")
    def appInfo(self, cls):
        return {"name": cls.title(), "icon": cls}

    @Slot(str)
    def playerCommand(self, verb):
        self.calls.append(("player", verb))

    @Slot(QObject, int, int, int, int)
    def setInputRect(self, w, x, y, ww, hh):
        self.calls.append(("mask", ww, hh))

    @Slot(str)
    def turnOn(self, pid):
        self._enabled = dict(self._enabled, **{pid: True})
        self.changed.emit()

    @Slot(str)
    def turnOff(self, pid):
        self._enabled = dict(self._enabled, **{pid: False})
        self.changed.emit()


def js(v):
    """A property that came back as a JavaScript value, as Python data."""
    return v.toVariant() if hasattr(v, "toVariant") else v


def settle(seconds):
    end = time.time() + seconds
    while time.time() < end:
        app.processEvents()
        time.sleep(0.01)


host = Host()
engine = QQmlApplicationEngine()
engine.rootContext().setContextProperty("host", host)
engine.rootContext().setContextProperty("windowFile", "PluginWindowPlain.qml")
engine.load(QUrl.fromLocalFile(os.path.join(stage, "Stage.qml")))
roots = engine.rootObjects()
check("the stage loads with the bundled plugin QML", len(roots) == 1,
      "\n         ".join(w for w in warnings[:12]))
if roots:
    st = roots[0]
    settle(0.6)
    keys = set((js(st.property("wins")) or {}).keys())
    check("switched-on plugins get a window each: leaf, turntable, weather",
          {"leaf", "vinyl", "live-weather"} <= keys, sorted(keys))
    check("the Game Center waits to be opened", "game-center" not in keys)

    host.gameCenterToggled.emit()
    settle(0.5)
    keys = set((js(st.property("wins")) or {}).keys())
    check("`genesi-plugins toggle game-center` opens it", "game-center" in keys, sorted(keys))
    gc = js(st.property("wins"))["game-center"]
    body = None
    for child in gc.findChildren(QObject):
        if child.metaObject().className().startswith("HostGames"):
            body = child
            break
    check("...with the shared GenesiGames in it", body is not None)
    if body is not None:
        from PySide6.QtCore import QMetaObject, Q_ARG
        QMetaObject.invokeMethod(body, "record", Q_ARG(str, "snake"),
                                 Q_ARG(int, 12), Q_ARG(bool, False))
        settle(0.1)
        gfile = os.path.join(statedir, "genesi-games.json")
        saved = json.loads(open(gfile).read() or "{}") if os.path.exists(gfile) else {}
        check("a game played is saved in caelestia's genesi-games.json format",
              saved.get("plays", {}).get("snake") == 1 and saved.get("best", {}).get("snake") == 12
              and "corner" in saved, saved)
    host.gameCenterToggled.emit()
    settle(0.3)
    check("toggling again puts it away", "game-center" not in (js(st.property("wins")) or {}))

    host.wrappedRequested.emit(7)
    settle(0.6)
    check("the Retrospective's story opens on request", "story" in (js(st.property("wins")) or {}))

    leaf = js(st.property("wins"))["leaf"]
    lb = next((c for c in leaf.findChildren(QObject)
               if c.metaObject().className().startswith("HostLeaf")), None)
    check("the leaf says hello when it arrives", lb is not None and len(js(lb.property("lines")) or []) > 0)
    check("its mood comes from the backend's senses", lb is not None and lb.property("mood") == "dancing",
          lb.property("mood") if lb else None)
    check("windows take the pointer only over the plugin",
          any(c[0] == "mask" for c in host.calls))

    host.turnOff("leaf")
    settle(0.4)
    check("switching a plugin off closes its window", "leaf" not in (js(st.property("wins")) or {}))

    noisy = [w for w in warnings if "FT_New_Face" not in w and "propagateSizeHints" not in w
             and "does not support" not in w and "Material Symbols" not in w
             and "font directory" not in w and "no longer ships fonts" not in w]
    check("Qt printed no warnings", not noisy, "\n         ".join(noisy[:10]))

# The tracker saves on the way out: let it, before its folder goes.
del engine
settle(0.1)
shutil.rmtree(tmp, ignore_errors=True)
print()
if fails:
    print("plugins on KDE: %d failure(s)" % len(fails))
    sys.exit(1)
print("plugins on KDE: OK")
