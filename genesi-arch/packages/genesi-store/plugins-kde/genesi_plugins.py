#!/usr/bin/env python3
"""
genesi-plugins — Genesi's shell plugins on KDE Plasma.

On Hyprland the plugins (Game Center, the leaf, live weather, the turntable,
the Retrospective) live inside caelestia. Plasma has no caelestia, so this is
their host there: the SAME plugin QML -- the games, the leaf and its mind, the
deck, the weather, the story -- bundled from genesi-caelestia-shell, in layer
surfaces of their own, fed by a small backend instead of caelestia's services.

The switches are the same files the store and caelestia use,
~/.config/genesi/plugins/<id>.json {"enabled": true}, and so are the state
files under ~/.local/state/caelestia (records, the leaf's XP, the week), so a
person who uses both desktops has one Game Center and one leaf, not two.

    genesi-plugins                     run the host (once per session)
    genesi-plugins toggle game-center  open or close the Game Center
    genesi-plugins wrapped [7|30]      open the Retrospective (days)

Never inside Hyprland: caelestia hosts them there, and two leaves on one
screen is a bug, not a feature.
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PLUGINS = ("game-center", "leaf", "live-weather", "vinyl", "wrapped")
STATE_FILES = ("genesi-games.json", "genesi-pet.json", "genesi-wrapped.json")


def config_dir(env=None):
    env = os.environ if env is None else env
    base = env.get("XDG_CONFIG_HOME") or os.path.join(env.get("HOME", os.path.expanduser("~")), ".config")
    return os.path.join(base, "genesi", "plugins")


def state_dir(env=None):
    """caelestia's Paths.state, so both desktops share one set of files."""
    env = os.environ if env is None else env
    base = env.get("XDG_STATE_HOME") or os.path.join(env.get("HOME", os.path.expanduser("~")), ".local", "state")
    return os.path.join(base, "caelestia")


def socket_path(env=None):
    env = os.environ if env is None else env
    return os.path.join(env.get("XDG_RUNTIME_DIR") or "/tmp", "genesi-plugins.sock")


def inside_hyprland(env=None):
    env = os.environ if env is None else env
    return bool(env.get("HYPRLAND_INSTANCE_SIGNATURE"))


def enabled_map(env=None):
    """Which plugins are switched on. Missing or broken file = off."""
    out = {}
    for pid in PLUGINS:
        try:
            with open(os.path.join(config_dir(env), pid + ".json"), encoding="utf-8") as fh:
                out[pid] = json.load(fh).get("enabled") is True
        except (OSError, ValueError, AttributeError):
            out[pid] = False
    return out


def parse_command(argv):
    """argv after the program name -> a one-line command for the host, or
    None for "run the host". Raises ValueError on nonsense."""
    if not argv:
        return None
    if argv[0] == "toggle" and len(argv) == 2 and argv[1] == "game-center":
        return "toggle game-center"
    if argv[0] == "wrapped":
        days = argv[1] if len(argv) > 1 else "7"
        if days not in ("7", "30"):
            raise ValueError("wrapped takes 7 or 30 (days)")
        return "wrapped " + days
    raise ValueError("usage: genesi-plugins [toggle game-center | wrapped [7|30]]")


def send(line, env=None):
    import socket
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1.5)
            s.connect(socket_path(env))
            s.sendall((line + "\n").encode())
        return True
    except OSError:
        return False


# ── what the leaf and the deck read ──────────────────────────────────────────

def _run(argv, timeout=4):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.stdout if p.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


PLAYER_FORMAT = "{{status}}\t{{title}}\t{{artist}}\t{{mpris:artUrl}}\t{{position}}\t{{mpris:length}}"


def parse_player(text):
    """`playerctl metadata --format PLAYER_FORMAT` -> what the deck draws."""
    parts = (text.rstrip("\n").split("\t") + [""] * 6)[:6]
    status, title, artist, art, pos, length = parts
    try:
        pos_f, len_f = float(pos or 0), float(length or 0)
    except ValueError:
        pos_f = len_f = 0.0
    return {"present": bool(title), "playing": status == "Playing", "title": title,
            "artist": artist, "art": art,
            "progress": (pos_f / len_f) if len_f > 0 else 0.0}


def idle_seconds():
    """KDE answers org.freedesktop.ScreenSaver.GetSessionIdleTime (ms)."""
    out = _run(["busctl", "--user", "--json=short", "call", "org.freedesktop.ScreenSaver",
                "/ScreenSaver", "org.freedesktop.ScreenSaver", "GetSessionIdleTime"])
    try:
        return int(json.loads(out)["data"][0]) / 1000.0
    except (ValueError, KeyError, IndexError, TypeError):
        return 0.0


def cpu_temperature():
    try:
        import psutil
        temps = psutil.sensors_temperatures() or {}
    except Exception:
        return 0.0
    for name in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"):
        vals = [t.current for t in temps.get(name, []) if t.current]
        if vals:
            return max(vals)
    return 0.0


def weather_code(lat, lon):
    url = ("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
           "&current=weather_code,wind_speed_10m" % (lat, lon))
    with urllib.request.urlopen(url, timeout=10) as r:
        cur = json.load(r).get("current", {})
    return int(cur.get("weather_code") or 0), float(cur.get("wind_speed_10m") or 0)


def where_am_i():
    """Coarse location from the IP, as caelestia's weather does without a city."""
    with urllib.request.urlopen("https://ipinfo.io/json", timeout=10) as r:
        loc = json.load(r).get("loc", "")
    lat, lon = loc.split(",")
    return float(lat), float(lon)


# Roles the plugins draw with that the shared Genesi palette does not carry
# (caelestia's scheme has every Material role; genesi_palette.GENESI has the
# ones the Genesi apps use). Missing, they were `undefined` -- a QColor
# warning and an unpainted cell in the games.
PLUGIN_ROLES = {
    "surface": "#040b17",
    "surfaceContainer": "#0d1623",
    "surfaceContainerHigh": "#16223a",
    "surfaceContainerHighest": "#1b2740",
    "onSurface": "#e8f0f8",
    "onSurfaceVariant": "#9fb0c4",
    "outline": "#27374f",
    "outlineVariant": "#1c2a3f",
    "primary": "#1FBE6A",
    "onPrimary": "#04180d",
    "primaryContainer": "#0e3d27",
    "onPrimaryContainer": "#b6f2cf",
    "secondary": "#34D989",
    "secondaryContainer": "#123528",
    "tertiary": "#3AAFE0",
    "error": "#E74C3C",
    "onError": "#2b0703",
}


def plugin_palette():
    """Every m3 role the plugins read: the desktop's (genesi_palette) where it
    has one, Genesi's own for the rest."""
    try:
        from genesi_palette import resolve
        colours, _following = resolve()
    except Exception:
        colours = {}
    full = dict(PLUGIN_ROLES)
    full.update(colours)
    return {"m3" + k: v for k, v in full.items()}


def app_info(cls, dirs=None):
    """A window class -> {"name", "icon"} from the .desktop files, the way
    caelestia's DesktopEntries.heuristicLookup does: StartupWMClass first,
    then the file's own name. Falls back to the class itself."""
    if not cls:
        return {"name": "", "icon": ""}
    low = cls.lower()
    if dirs is None:
        data = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
        home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        dirs = [os.path.join(d, "applications") for d in [home] + data.split(":")]
    best = None
    for d in dirs:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".desktop"):
                continue
            fields = {}
            try:
                with open(os.path.join(d, fn), encoding="utf-8", errors="replace") as fh:
                    section = ""
                    for line in fh:
                        line = line.strip()
                        if line.startswith("["):
                            section = line
                        elif section == "[Desktop Entry]" and "=" in line:
                            k, v = line.split("=", 1)
                            fields.setdefault(k, v)
            except OSError:
                continue
            stem = fn[:-len(".desktop")].lower()
            if fields.get("StartupWMClass", "").lower() == low:
                return {"name": fields.get("Name", cls), "icon": fields.get("Icon", low)}
            if best is None and (stem == low or stem.endswith("." + low)):
                best = {"name": fields.get("Name", cls), "icon": fields.get("Icon", low)}
    return best or {"name": cls, "icon": low}


KWIN_SCRIPT = os.path.join(HERE, "kwin", "genesi-plugins-active.js")
KWIN_SCRIPT_NAME = "genesi-plugins-active"


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        command = parse_command(argv)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    if inside_hyprland():
        print("genesi-plugins: on Hyprland the plugins run inside caelestia", file=sys.stderr)
        return 0
    if command and send(command):
        return 0
    if command is None and send("ping"):
        return 0                       # already running

    os.environ.setdefault("QT_QPA_PLATFORM", "wayland")
    if os.environ.get("QT_QPA_PLATFORM") == "wayland":
        # Every window of this process is a layer surface, the same choice
        # genesi-ai-island makes on Plasma.
        os.environ["QT_WAYLAND_SHELL_INTEGRATION"] = "layer-shell"
    return run_host(first_command=command)


def run_host(first_command=None, qml_dir=None, layer=True):
    from PySide6.QtCore import (ClassInfo, Property, QObject, QTimer, QUrl, Signal, Slot)
    from PySide6.QtDBus import QDBusConnection, QDBusInterface
    from PySide6.QtGui import QGuiApplication, QRegion
    from PySide6.QtNetwork import QLocalServer
    from PySide6.QtQml import QQmlApplicationEngine

    @ClassInfo({"D-Bus Interface": "org.genesi.plugins"})
    class ActiveSink(QObject):
        """Where the KWin script reports the focused window's class."""
        def __init__(self, host):
            super().__init__()
            self._host = host

        @Slot(str)
        def setActive(self, cls):
            self._host._set_active(cls)

    class Host(QObject):
        changed = Signal()
        gameCenterToggled = Signal()
        wrappedRequested = Signal(int)

        def __init__(self):
            super().__init__()
            self._enabled = enabled_map()
            self._palette = {}
            self._stats = {"cpu": 0, "temp": 0, "idle": False, "music": False,
                           "updates": 0, "disk": 0, "hour": time.localtime().tm_hour}
            self._player = parse_player("")
            self._weather = {"code": 0, "wind": 0.25}
            self._active = ""
            self._cpu = []
            self._coords = None
            self._lock = threading.Lock()
            self._palette = plugin_palette()

        # what QML reads
        @Property("QVariant", notify=changed)
        def enabled(self):
            return self._enabled

        @Property("QVariant", notify=changed)
        def palette(self):
            return self._palette

        @Property("QVariant", notify=changed)
        def stats(self):
            return self._stats

        @Property("QVariant", notify=changed)
        def player(self):
            return self._player

        @Property("QVariant", notify=changed)
        def weather(self):
            return self._weather

        @Property(str, notify=changed)
        def activeApp(self):
            return self._active

        @Property(bool, constant=True)
        def portuguese(self):
            return (os.environ.get("LANG") or "").startswith("pt")

        # what QML asks for
        @Slot(str, result=str)
        def readState(self, name):
            if name not in STATE_FILES:
                return ""
            try:
                with open(os.path.join(state_dir(), name), encoding="utf-8") as fh:
                    return fh.read()
            except OSError:
                return ""

        @Slot(str, str)
        def writeState(self, name, text):
            if name not in STATE_FILES:
                return
            d = state_dir()
            os.makedirs(d, exist_ok=True)
            tmp = os.path.join(d, ".%s.%d" % (name, os.getpid()))
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.replace(tmp, os.path.join(d, name))

        @Slot(str, result="QVariant")
        def appInfo(self, cls):
            return app_info(cls)

        @Slot(str)
        def playerCommand(self, verb):
            if verb in ("play-pause", "next", "previous"):
                try:
                    subprocess.Popen(["playerctl", verb], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
                except OSError:
                    pass

        @Slot(QObject, int, int, int, int)
        def setInputRect(self, window, x, y, w, h):
            """Only the plugin takes the pointer; the rest of its window is
            glass the desktop below must still be clickable through."""
            try:
                window.setMask(QRegion(x, y, max(1, w), max(1, h)))
            except Exception:
                pass

        @Slot(str)
        def turnOn(self, pid):
            """The same switch file the store writes."""
            if pid not in PLUGINS:
                return
            os.makedirs(config_dir(), exist_ok=True)
            with open(os.path.join(config_dir(), pid + ".json"), "w", encoding="utf-8") as fh:
                fh.write('{"enabled": true}\n')
            self.refreshSwitches()

        @Slot(str)
        def turnOff(self, pid):
            if pid not in PLUGINS:
                return
            path = os.path.join(config_dir(), pid + ".json")
            try:
                os.unlink(path)
            except OSError:
                pass
            self.refreshSwitches()

        # polling
        @Slot()
        def refreshSwitches(self):
            now = enabled_map()
            if now != self._enabled:
                self._enabled = now
                self.changed.emit()

        def _set_active(self, cls):
            if cls != self._active:
                self._active = cls
                self.changed.emit()

        def sample(self):
            on = self._enabled
            if on.get("leaf") or on.get("vinyl"):
                self._player = parse_player(_run(["playerctl", "metadata", "--format", PLAYER_FORMAT], 2))
            if on.get("leaf"):
                try:
                    import psutil
                    self._cpu = (self._cpu + [psutil.cpu_percent(interval=None)])[-5:]
                except Exception:
                    pass
                total, used, _free = shutil.disk_usage("/")
                self._stats = dict(self._stats, cpu=sum(self._cpu) / max(1, len(self._cpu)),
                                   temp=cpu_temperature(), idle=idle_seconds() > 300,
                                   music=self._player["playing"], disk=used / total,
                                   hour=time.localtime().tm_hour)
            self.changed.emit()

        def updates_later(self):
            if not self._enabled.get("leaf"):
                return
            def work():
                out = _run(["sh", "-c", "if command -v checkupdates >/dev/null; then checkupdates; "
                            "else pacman -Qu; fi"], 120)
                with self._lock:
                    self._stats = dict(self._stats, updates=len([l for l in out.splitlines() if l.strip()]))
            threading.Thread(target=work, daemon=True).start()

        def weather_later(self):
            if not self._enabled.get("live-weather"):
                return
            def work():
                try:
                    if self._coords is None:
                        self._coords = where_am_i()
                    code, wind = weather_code(*self._coords)
                    with self._lock:
                        self._weather = {"code": code, "wind": min(1.0, 0.15 + wind / 40.0)}
                except Exception:
                    pass
            threading.Thread(target=work, daemon=True).start()

    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("Genesi Plugins")
    app.setDesktopFileName("org.genesi.plugins")
    app.setQuitOnLastWindowClosed(False)

    host = Host()

    # Commands from `genesi-plugins toggle ...`, and "ping" to say we run.
    server = QLocalServer()
    QLocalServer.removeServer(socket_path())
    server.listen(socket_path())

    def on_conn():
        conn = server.nextPendingConnection()
        if conn is None:
            return
        conn.waitForReadyRead(500)
        line = bytes(conn.readAll()).decode(errors="replace").strip()
        conn.disconnectFromServer()
        handle(line)

    def handle(line):
        if line == "toggle game-center":
            host.gameCenterToggled.emit()
        elif line.startswith("wrapped "):
            host.wrappedRequested.emit(int(line.split()[1]))

    server.newConnection.connect(on_conn)

    # The focused window, for the Retrospective: a KWin script reports it.
    bus = QDBusConnection.sessionBus()
    sink = ActiveSink(host)
    if bus.registerService("org.genesi.plugins"):
        bus.registerObject("/Active", sink, QDBusConnection.ExportAllSlots)
        scripting = QDBusInterface("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", bus)
        if scripting.isValid() and os.path.exists(KWIN_SCRIPT):
            scripting.call("unloadScript", KWIN_SCRIPT_NAME)
            scripting.call("loadScript", KWIN_SCRIPT, KWIN_SCRIPT_NAME)
            scripting.call("start")

    from PySide6.QtGui import QIcon, QPixmap
    from PySide6.QtQuick import QQuickImageProvider

    class IconProvider(QQuickImageProvider):
        """image://icon/<name>: the current icon theme's picture, as
        caelestia's Icons.getAppIcon gives the story."""
        def __init__(self):
            super().__init__(QQuickImageProvider.Pixmap)

        def requestPixmap(self, ident, size, requested):
            side = max(requested.width(), requested.height(), 64)
            icon = QIcon.fromTheme(ident, QIcon.fromTheme("application-x-executable"))
            pm = icon.pixmap(side, side)
            return pm if not pm.isNull() else QPixmap(side, side)

    engine = QQmlApplicationEngine()
    engine.addImageProvider("icon", IconProvider())
    qml = qml_dir or os.path.join(HERE, "qml")
    engine.addImportPath(qml)
    engine.rootContext().setContextProperty("host", host)
    engine.rootContext().setContextProperty("windowFile",
                                            "PluginWindow.qml" if layer else "PluginWindowPlain.qml")
    engine.load(QUrl.fromLocalFile(os.path.join(qml, "Stage.qml")))
    if not engine.rootObjects():
        return 1

    timers = []
    for ms, fn in ((3000, host.refreshSwitches), (4000, host.sample),
                   (3600 * 1000, host.updates_later), (30 * 60 * 1000, host.weather_later)):
        t = QTimer()
        t.setInterval(ms)
        t.timeout.connect(fn)
        t.start()
        timers.append(t)
    QTimer.singleShot(1500, host.updates_later)
    QTimer.singleShot(1500, host.weather_later)
    if first_command:
        QTimer.singleShot(800, lambda: handle(first_command))

    def bye():
        try:
            QDBusInterface("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
                           bus).call("unloadScript", KWIN_SCRIPT_NAME)
        except Exception:
            pass
        QLocalServer.removeServer(socket_path())
    app.aboutToQuit.connect(bye)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
