#!/usr/bin/env python3
"""genesi-ai-island -- the AI island on every desktop but caelestia's.

caelestia draws the island inside its own shell on Hyprland. Everywhere else
-- KDE Plasma, GNOME, Xfce, Cinnamon, Budgie, LXDE, COSMIC, Niri -- this is
the island: the SAME card (GenesiAiIslandCard.qml, bundled from the shell
package) in a window of its own at the top of the screen.

What kind of window depends on what the desktop allows (genesi_island_link.
platform_choice): a wlr-layer-shell surface where the compositor has one (it
sits at the top, above windows, out of the taskbar, and takes the keyboard
only while you type in it), an X11 window placed at the top centre where it
does not, and a plain window as the last resort.

It only reads what the Quick Chat publishes and sends commands back over the
chat's socket -- the chat is still the one place anything is decided. Started
by the chat at login; leaves by itself when the island is switched off.
"""

import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import genesi_island_link as link  # noqa: E402

# Importing Qt does not start it: the platform is read when the application
# is made, after choose_platform() has set it.
from PySide6.QtCore import (QFileSystemWatcher, QObject, QRect, QTimer, QUrl,  # noqa: E402
                            Property, Signal, Slot)
from PySide6.QtGui import QCursor, QGuiApplication, QRegion  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402
from PySide6.QtQuick import QQuickWindow  # noqa: F401,E402  (so the root is typed as one)

WINDOW_W, WINDOW_H = 640, 470


def choose_platform():
    """Before Qt starts: which platform plugin, and which shell."""
    kind = link.platform_choice()
    if kind == "layer":
        os.environ["QT_QPA_PLATFORM"] = "wayland"
        # Every window of THIS process is a layer surface -- there is one.
        os.environ["QT_WAYLAND_SHELL_INTEGRATION"] = "layer-shell"
    elif kind == "xcb":
        os.environ["QT_QPA_PLATFORM"] = "xcb"
    return kind


def claim_instance():
    """One island per session. The pid file is also how the chat knows an
    island is on screen to ask for approvals."""
    if link.standalone_running():
        return False
    try:
        with open(link.ui_pid_path(), "w", encoding="utf-8") as handle:
            handle.write(str(os.getpid()))
    except OSError:
        return False
    return True


def release_instance():
    try:
        with open(link.ui_pid_path(), encoding="utf-8") as handle:
            if handle.read().strip() == str(os.getpid()):
                os.unlink(link.ui_pid_path())
    except OSError:
        pass


def material_palette():
    """The theme's colours under the names the card reads (m3onSurface...)."""
    try:
        from genesi_palette import resolve
        colours, _following = resolve()
    except Exception:
        colours = {}
    # caelestia's own spelling: m3 + the name as it is (m3onSurface, m3primary).
    return {"m3" + key: value for key, value in colours.items()}


def quick_command():
    found = shutil.which("genesi-ai-quick")
    if found:
        return [found]
    return [sys.executable, os.path.join(HERE, "genesi_ai_quick.py")]


class Host(QObject):
    """What the island's QML reads, and the commands it runs."""
    changed = Signal()

    def __init__(self, kind="xcb"):
        super().__init__()
        self._kind = kind
        self._state = "{}"
        self._live = False
        self._prefs = json.dumps(link.read_prefs())
        self._palette = json.dumps(material_palette())
        self._place = (0, 0, False)
        self.window = None

    # ── What the card reads ───────────────────────────────────────────
    @Property(str, notify=changed)
    def stateJson(self):
        return self._state

    @Property(bool, notify=changed)
    def live(self):
        return self._live

    @Property(str, notify=changed)
    def prefsJson(self):
        return self._prefs

    @Property(str, notify=changed)
    def paletteJson(self):
        return self._palette

    @Property(str, constant=True)
    def platform(self):
        return self._kind

    @Property(int, notify=changed)
    def placeX(self):
        return self._place[0]

    @Property(int, notify=changed)
    def placeY(self):
        return self._place[1]

    # Something sits at the top of the screen (GNOME's bar, a panel):
    # the island hangs under it instead of being a notch on the edge.
    @Property(bool, notify=changed)
    def hangs(self):
        return self._place[2]

    # ── Reading ──────────────────────────────────────────────────────
    @Slot()
    def refresh(self):
        state = link.read_state()
        live = bool(state) and link.pid_alive(state.get("pid"))
        text = json.dumps(state, sort_keys=True)
        if text != self._state or live != self._live:
            self._state, self._live = text, live
            self.changed.emit()

    @Slot()
    def refreshPrefs(self):
        if not link.enabled() or link.caelestia_session():
            QGuiApplication.quit()
            return
        prefs = json.dumps(link.read_prefs())
        palette = json.dumps(material_palette())
        if prefs != self._prefs or palette != self._palette:
            self._prefs, self._palette = prefs, palette
            self.changed.emit()

    @Slot()
    def place(self):
        """Top centre of the screen the pointer is on (X11 only: on a
        layer surface the compositor places it)."""
        screen = QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
        if screen is None:
            return
        full, avail = screen.geometry(), screen.availableGeometry()
        hangs = avail.y() > full.y()
        x = full.x() + (full.width() - WINDOW_W) // 2
        y = avail.y() + (6 if hangs else 0)
        if (x, y, hangs) != self._place:
            self._place = (x, y, hangs)
            self.changed.emit()

    # ── What the card asks for ───────────────────────────────────────
    @Slot(str, str)
    def command(self, cmd, arg):
        """Approve, deny, stop, toggle, ask, set -- over the chat's
        socket; if no chat is listening, through the CLI, which starts
        one where that makes sense."""
        if cmd in ("approve", "deny"):
            message, argv = {"cmd": cmd, "id": arg}, ["--" + cmd, arg]
        elif cmd == "stop":
            message, argv = {"cmd": "stop"}, ["--stop"]
        elif cmd == "ask":
            data = json.loads(arg)
            message = {"cmd": "ask", "text": data.get("text", ""), "clip": bool(data.get("clip"))}
            argv = ["--ask", message["text"]] + (["--clip"] if message["clip"] else [])
        elif cmd == "set":
            key, _, value = arg.partition("=")
            parsed = link.parse_setting(key, value)
            if parsed and parsed[0] in ("mode", "smartClip"):
                try:
                    link.write_prefs(**{parsed[0]: parsed[1]})
                except OSError:
                    pass
                self.refreshPrefs()
            message, argv = {"cmd": "set", "key": key, "value": value}, ["--set", arg]
        elif cmd == "attach":
            data = json.loads(arg)
            message = {"cmd": "attach", "path": data.get("path", ""), "prompt": data.get("prompt", "")}
            argv = ["--attach", message["path"]] + (["--prompt", message["prompt"]] if message["prompt"] else [])
        else:
            message, argv = None, ["--toggle"]
        wire = json.dumps(message) if message else "toggle"
        if link.send(wire):
            return
        try:
            subprocess.Popen(quick_command() + argv, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass

    @Slot(str)
    def copy(self, text):
        try:
            if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
                subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=3)
                return
        except (OSError, subprocess.SubprocessError):
            pass
        QGuiApplication.clipboard().setText(text)

    @Slot(int, int, int, int)
    def setInputRect(self, x, y, w, h):
        """Only the card takes the pointer: the rest of the window is
        glass the desktop below must still be clickable through."""
        if self.window is None or w <= 0 or h <= 0:
            return
        self.window.setMask(QRegion(QRect(x, y, w, h)))


def main():
    kind = choose_platform()
    if link.caelestia_session():
        return 0                       # caelestia draws its own
    if not link.enabled():
        return 0
    if not claim_instance():
        return 0

    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("Genesi AI Island")
    app.setDesktopFileName("org.genesi.aiisland")
    app.setQuitOnLastWindowClosed(False)
    try:
        from PySide6.QtGui import QFont, QFontDatabase
        if "Rubik" in QFontDatabase.families():
            font = app.font()
            font.setFamily("Rubik")
            font.setStyleStrategy(QFont.PreferAntialias)
            app.setFont(font)
    except Exception:
        pass

    host = Host(kind)
    host.place()
    host.refresh()

    engine = QQmlApplicationEngine()
    engine.addImportPath(HERE)
    engine.rootContext().setContextProperty("islandHost", host)
    page = "IslandLayer.qml" if kind == "layer" else "IslandPlain.qml"
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, page)))
    if not engine.rootObjects() and kind == "layer":
        # The layer-shell QML module is missing: a placed window still works.
        page = "IslandPlain.qml"
        engine.load(QUrl.fromLocalFile(os.path.join(HERE, page)))
    if not engine.rootObjects():
        release_instance()
        return 1
    host.window = engine.rootObjects()[0]

    # The chat replaces its state file atomically (a rename), which a watch
    # on the FILE would lose; the directory sees every replacement.
    watcher = QFileSystemWatcher([link.runtime_dir()])
    watcher.directoryChanged.connect(lambda _path: host.refresh())
    poll = QTimer()
    poll.setInterval(700)
    poll.timeout.connect(host.refresh)
    poll.start()
    prefs_poll = QTimer()
    prefs_poll.setInterval(2500)
    prefs_poll.timeout.connect(host.refreshPrefs)
    prefs_poll.start()
    if kind != "layer":
        place_poll = QTimer()
        place_poll.setInterval(4000)
        place_poll.timeout.connect(host.place)
        place_poll.start()

    app.aboutToQuit.connect(release_instance)
    try:
        return app.exec()
    finally:
        release_instance()


if __name__ == "__main__":
    raise SystemExit(main())
