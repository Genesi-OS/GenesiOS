#!/usr/bin/env python3
"""
Genesi Find — describe a file, get the file.

Pure front-end, exactly like Genesi Sandboxes: every search is delegated to the
`genesi-find` CLI (the single source of truth) in a worker thread, so the window
never blocks while a home directory is being walked. The UI lives in Main.qml.

Launched three ways:
  * from the app menu,
  * from Dolphin's right-click menu on a folder ("Search with AI here"), which
    passes that folder as argv[1] and scopes the search to it,
  * from a terminal, as `genesi-find-ui [folder]`.
"""
import json
import os
import shutil
import subprocess
import sys
import threading

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon, QClipboard
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Find needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

CLI = "/usr/local/bin/genesi-find"
APP_DIR = os.path.dirname(os.path.abspath(__file__))


class Backend(QObject):
    resultsReady = Signal(str)      # JSON from `genesi-find --json`
    busyChanged = Signal(bool)

    def __init__(self, scope=""):
        super().__init__()
        self._busy = False
        self._scope = scope
        self._seq = 0               # so a slow search cannot overwrite a newer one

    @Slot(result=str)
    def scope(self):
        return self._scope

    def _set_busy(self, value):
        self._busy = value
        self.busyChanged.emit(value)

    @Slot(str)
    def search(self, query):
        query = (query or "").strip()
        if not query or self._busy:
            return
        self._seq += 1
        seq = self._seq
        self._set_busy(True)
        threading.Thread(target=self._run, args=(query, seq), daemon=True).start()

    def _run(self, query, seq):
        payload = '{"results": [], "plan": {}, "roots": []}'
        try:
            args = [CLI, "--json", "-n", "40"]
            if self._scope:
                args += ["-p", self._scope]
            args.append(query)
            done = subprocess.run(args, capture_output=True, text=True, timeout=90)
            if done.stdout.strip():
                payload = done.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        if seq == self._seq:        # a newer search already started: drop this one
            self.resultsReady.emit(payload)
            self._set_busy(False)

    # ── acting on a result ───────────────────────────────────────────────────
    #
    # Opening is the one thing this app does to your machine, and it is always
    # the system handler for a file the user just clicked. Nothing is moved,
    # renamed or deleted from here.

    @Slot(str)
    def openPath(self, path):
        if os.path.exists(path):
            subprocess.Popen(["xdg-open", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @Slot(str)
    def revealPath(self, path):
        if not os.path.exists(path):
            return
        # A file manager that can highlight the file beats opening its folder
        # and leaving the user to find it a second time.
        for manager, flag in (("dolphin", "--select"), ("nautilus", "--select"),
                              ("nemo", None), ("thunar", None)):
            if not shutil.which(manager):
                continue
            args = [manager] + ([flag, path] if flag else [os.path.dirname(path)])
            subprocess.Popen(args, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
            return
        subprocess.Popen(["xdg-open", os.path.dirname(path)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @Slot(str)
    def copyToClipboard(self, text):
        """Alias for copyPath.

        FileCard is shared with the Monitor's chat, whose backend spells this
        verb `copyToClipboard`. One component driving two backends means the
        two backends have to answer to the same names."""
        self.copyPath(text)

    @Slot(str)
    def copyPath(self, path):
        QGuiApplication.clipboard().setText(path, QClipboard.Clipboard)


def main():
    scope = ""
    if len(sys.argv) > 1:
        candidate = os.path.abspath(os.path.expanduser(sys.argv[1]))
        if os.path.isdir(candidate):
            scope = candidate
        elif os.path.isfile(candidate):
            scope = os.path.dirname(candidate)

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi Find")
    app.setDesktopFileName("org.genesi.find")
    icon = "/usr/share/icons/hicolor/scalable/apps/genesi-ai-monitor.svg"
    if os.path.exists(icon):
        app.setWindowIcon(QIcon(icon))

    backend = Backend(scope)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("initialScope", scope)
    engine.load(QUrl.fromLocalFile(os.path.join(APP_DIR, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("Genesi Find: the UI failed to load.\n")
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
