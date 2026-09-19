#!/usr/bin/env python3
"""
genesi-store — the window.

It draws, and nothing else: every question about what exists and every change
to the machine goes to `genesi-store`, the CLI next to this file. Same split
as Genesi Center and genesi-display, and for the same reason -- a look can
then be applied from a terminal, a keybind or an automation, and all of them
do the identical thing.

The work happens off the GUI thread because two of the three verbs take real
time: `install` downloads a picture, `apply` may ask pacman for a locker
behind a password prompt. A store that freezes while it fetches is a store
people think has crashed.
"""
import json
import os
import subprocess
import sys
import threading

from PySide6.QtCore import QObject, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication, QIcon, QFont, QFontDatabase
from PySide6.QtQml import QQmlApplicationEngine

APP_ID = "org.genesi.store"
HERE = os.path.dirname(os.path.abspath(__file__))
CLI = "genesi-store"


def cli(*args, timeout=180):
    """Run the data plane. Returns (ok, parsed-or-text)."""
    argv = [CLI] + list(args)
    local = os.path.join(os.path.dirname(HERE), "genesi-store")
    if not _on_path(CLI) and os.path.exists(local):
        argv = [sys.executable, local] + list(args)
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return False, "genesi-store is not installed"
    except subprocess.TimeoutExpired:
        return False, "genesi-store took too long"
    if proc.returncode:
        detail = (proc.stderr or proc.stdout or "").strip().splitlines()
        return False, (detail[-1] if detail else "genesi-store failed")
    text = (proc.stdout or "").strip()
    try:
        return True, json.loads(text) if text else {}
    except ValueError:
        return True, text


def _on_path(name):
    for part in (os.environ.get("PATH") or "").split(os.pathsep):
        if part and os.path.exists(os.path.join(part, name)):
            return True
    return False


class Store(QObject):
    catalogLoaded = Signal(str)
    sectionsLoaded = Signal(str)
    stateChanged = Signal(str)
    busyChanged = Signal(str, str)      # item id, what is happening
    finished = Signal(str, bool, str)   # item id, ok, message

    def __init__(self):
        super().__init__()
        self._busy = set()

    # ── Reading ────────────────────────────────────────────────────────────
    @Slot()
    def load(self):
        def work():
            ok, sections = cli("sections")
            if ok:
                self.sectionsLoaded.emit(json.dumps(sections))
            ok, catalog = cli("catalog")
            if ok:
                self.catalogLoaded.emit(json.dumps(catalog))
            else:
                self.finished.emit("", False, str(catalog))
        threading.Thread(target=work, daemon=True).start()

    @Slot()
    def refreshState(self):
        ok, state = cli("state")
        if ok:
            self.stateChanged.emit(json.dumps(state))

    # ── Changing ───────────────────────────────────────────────────────────
    def _job(self, ident, verb, saying):
        if ident in self._busy:
            return
        self._busy.add(ident)
        self.busyChanged.emit(ident, saying)

        def work():
            ok, result = cli(verb, ident, timeout=900)
            self._busy.discard(ident)
            self.busyChanged.emit(ident, "")
            self.finished.emit(ident, ok, "" if ok else str(result))
            self.refreshState()
            self.load()
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def install(self, ident):
        self._job(ident, "install", "baixando")

    @Slot(str)
    def apply(self, ident):
        self._job(ident, "apply", "aplicando")

    @Slot(str)
    def revert(self, ident):
        self._job(ident, "revert", "revertendo")

    @Slot(str)
    def remove(self, ident):
        self._job(ident, "remove", "removendo")

    # ── Small favours for the UI ───────────────────────────────────────────
    @Slot(str, result=str)
    def assetPath(self, ident):
        """Where an installed picture landed, as a file:// url, or ""."""
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        folder = os.path.join(base, "genesi", "store", "assets", ident)
        if not os.path.isdir(folder):
            return ""
        for name in sorted(os.listdir(folder)):
            path = os.path.join(folder, name)
            if os.path.isfile(path):
                return QUrl.fromLocalFile(path).toString()
        return ""

    @Slot(result=str)
    def thumbDir(self):
        """Where the shipped thumbnails live.

        They are part of the package, not something downloaded: a shelf of
        wallpapers has to be a shelf of PICTURES before anybody presses
        anything, and the alternative is eighteen grey rectangles with file
        sizes in them.
        """
        for folder in ("/usr/share/genesi-store/thumbs",
                       os.path.join(os.path.dirname(HERE), "catalog", "thumbs")):
            if os.path.isdir(folder):
                # A url, not a path: "file://" + a Windows path is a hostname,
                # and the harness that renders this runs there.
                return QUrl.fromLocalFile(folder).toString()
        return ""

    @Slot()
    def openCenter(self):
        try:
            subprocess.Popen(["genesi-center"], start_new_session=True)
        except OSError:
            pass

    @Slot(result=str)
    def user(self):
        return os.environ.get("USER") or os.environ.get("USERNAME") or ""


def main():
    # Fusion, like every other Genesi app: the desktop style refuses to let a
    # control be re-drawn ("The current style does not support customization"),
    # and this window draws its own scrollbar, field and buttons.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    app = QGuiApplication(sys.argv)
    try:
        from PySide6.QtQuickControls2 import QQuickStyle
        QQuickStyle.setStyle("Fusion")
    except Exception:
        pass
    app.setApplicationName("Genesi Store")
    app.setApplicationDisplayName("Genesi Store")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(QIcon.fromTheme("genesi-store"))
    try:
        if "Rubik" in QFontDatabase.families():
            font = app.font()
            font.setFamily("Rubik")
            font.setStyleStrategy(QFont.PreferAntialias)
            app.setFont(font)
    except Exception:
        pass

    engine = QQmlApplicationEngine()
    store = Store()
    engine.rootContext().setContextProperty("store", store)
    # The singleton lives in this directory's qmldir; Main.qml reaches it
    # with `import "."`, the same way Genesi Center does.
    engine.addImportPath(HERE)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("genesi-store: the window did not load\n")
        return 1
    store.load()
    store.refreshState()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
