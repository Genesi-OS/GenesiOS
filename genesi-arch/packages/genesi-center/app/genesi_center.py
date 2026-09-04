#!/usr/bin/env python3
"""
Genesi Center — QML engine plus the thread that feeds it.

Pure front-end, the same contract every Genesi app follows: this process draws
and delegates, and every fact on screen comes from `genesi-center-data`. It
never reads /proc itself, so the numbers in the window and the numbers in a
terminal cannot disagree.

The tick runs on a worker thread. `genesi-center-data telemetry` deliberately
sleeps ~120ms twice, sampling /proc/stat and /proc/net/dev, because a rate needs
two readings -- and a quarter second on the UI thread is a visible stutter every
tick. Nothing about the reading is urgent, so it belongs off the main loop.
"""
import json
import os
import subprocess
import sys
import threading

try:
    from PySide6.QtCore import QObject, QUrl, Signal, Slot, QTimer
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Center needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

DATA = "genesi-center-data"
APPDIR = os.path.dirname(os.path.abspath(__file__))
TICK_MS = 5000


class Backend(QObject):
    dataReady = Signal(str)

    def __init__(self):
        super().__init__()
        # One tick at a time. The reader takes a moment by design, and a slow
        # machine could otherwise stack ticks until every one of them is late.
        self._busy = threading.Lock()

    def _read(self, what):
        try:
            p = subprocess.run([DATA, what], capture_output=True, text=True,
                               timeout=40, encoding="utf-8", errors="replace")
            return p.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    def _tick_body(self, sections):
        try:
            out = {}
            for s in sections:
                raw = self._read(s)
                if raw:
                    try:
                        out[s] = json.loads(raw)
                    except json.JSONDecodeError:
                        pass
            if out:
                self.dataReady.emit(json.dumps(out))
        finally:
            self._busy.release()

    def _tick(self, sections):
        if not self._busy.acquire(blocking=False):
            return
        threading.Thread(target=self._tick_body, args=(sections,),
                         daemon=True).start()

    @Slot()
    def refresh(self):
        # Storage walks the filesystem with du, so it is not on the fast tick.
        self._tick(["telemetry", "core", "storage", "activity"])

    @Slot()
    def poll(self):
        self._tick(["telemetry"])

    @Slot(list)
    def launch(self, argv):
        """
        Start a tool and forget it.

        argv is a fixed list from the page, never a string a user typed, and it
        is never handed to a shell -- so nothing here can be turned into an
        injection by a filename or a locale.
        """
        if not argv:
            return
        try:
            subprocess.Popen([str(a) for a in argv],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError as e:
            sys.stderr.write(f"genesi-center: cannot start {argv[0]}: {e}\n")


def tree_art():
    """
    Where the Overview's artwork comes from.

    A user drop-in wins over the packaged file, so the art can be replaced and
    seen by reopening the window -- no rebuild, no root, no package. That is
    the whole reason this is resolved here rather than hardcoded in QML: an
    Image cannot try one path and fall back to another, and deciding it in
    Python costs four lines.

    Returns "" when neither exists, and the page then draws its procedural glow
    instead of an empty rectangle.
    """
    for p in (os.path.expanduser("~/.config/genesi/center/tree.png"),
              os.path.expanduser("~/.config/genesi/center/tree.svg"),
              os.path.join(APPDIR, "art", "tree.png")):
        if os.path.exists(p):
            return "file://" + p
    return ""


def main():
    QGuiApplication.setApplicationName("Genesi Center")
    QGuiApplication.setDesktopFileName("org.genesi.center")
    app = QGuiApplication(sys.argv)

    icon = "/usr/share/icons/hicolor/scalable/apps/genesi-center.svg"
    if os.path.exists(icon):
        app.setWindowIcon(QIcon(icon))

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.addImportPath(APPDIR)
    engine.setInitialProperties({"backend": backend, "treeArt": tree_art()})
    engine.load(QUrl.fromLocalFile(os.path.join(APPDIR, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("genesi-center: the interface failed to load\n")
        return 1

    backend.refresh()
    fast = QTimer()
    fast.timeout.connect(backend.poll)
    fast.start(TICK_MS)
    # The slow half -- disk usage and the activity log -- every minute.
    slow = QTimer()
    slow.timeout.connect(backend.refresh)
    slow.start(TICK_MS * 12)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
