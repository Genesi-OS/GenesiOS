#!/usr/bin/env python3
"""
Genesi AI Mode Monitor — standalone Qt6/Kirigami dashboard for genesi-aid.

Pure front-end: it reads the daemon's state.json for display and drives the
`genesi-ai-mode` CLI for control (so no privileges of its own are needed). The
UI lives in Main.qml; this is just the QML engine plus a tiny backend object the
QML can call.
"""
import os
import sys
import json
import shutil
import subprocess

try:
    from PySide6.QtCore import QObject, Slot, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi AI Mode Monitor needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

STATE_FILE = "/run/genesi-ai-mode/state.json"


class Backend(QObject):
    @Slot(result=str)
    def state(self):
        try:
            with open(STATE_FILE) as f:
                return f.read()
        except OSError:
            return "{}"

    @Slot(result=bool)
    def hasOllama(self):
        return shutil.which("ollama") is not None

    @Slot(str)
    def setMode(self, mode):
        if mode in ("on", "off", "auto", "toggle"):
            try:
                subprocess.Popen(["genesi-ai-mode", mode],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except OSError:
                pass


def main():
    # Use Plasma's Qt Quick Controls style so the app inherits the system color
    # scheme (incl. the dark Genesi theme) instead of the light Qt default.
    # Needs qqc2-desktop-style; falls back silently to the default if absent.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    try:
        from PySide6.QtQuickControls2 import QQuickStyle
        QQuickStyle.setStyle("org.kde.desktop")
    except ImportError:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi AI Mode Monitor")
    app.setApplicationDisplayName("Genesi AI Mode Monitor")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName("org.genesi.aimonitor")
    app.setWindowIcon(QIcon.fromTheme("cpu"))

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("Failed to load the Monitor UI (is kirigami installed?)\n")
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
