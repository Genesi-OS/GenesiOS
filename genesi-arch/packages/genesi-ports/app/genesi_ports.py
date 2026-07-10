#!/usr/bin/env python3
"""PySide6 bridge for the Genesi PortScope dashboard."""
import json
import os
import shutil
import subprocess
import sys
import threading

from PySide6.QtCore import QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine


CLI = shutil.which("genesi-ports") or "/usr/bin/genesi-ports"


class Backend(QObject):
    listenersLoaded = Signal(str)
    inspectionLoaded = Signal(str)
    busyChanged = Signal(bool)
    message = Signal(str)

    def __init__(self):
        super().__init__()
        self._busy = False

    def _set_busy(self, value):
        self._busy = value
        self.busyChanged.emit(value)

    def _thread(self, task):
        threading.Thread(target=task, daemon=True).start()

    @Slot()
    def refresh(self):
        def work():
            try:
                proc = subprocess.run([CLI, "list-json"], capture_output=True,
                                      text=True, timeout=12)
                self.listenersLoaded.emit(proc.stdout.strip() or '{"listeners":[]}')
            except Exception as exc:
                self.listenersLoaded.emit('{"listeners":[]}')
                self.message.emit("Could not read ports: %s" % exc)
        self._thread(work)

    @Slot()
    def refreshPrivileged(self):
        if self._busy:
            return
        self._set_busy(True)

        def work():
            try:
                proc = subprocess.run(["pkexec", CLI, "list-json"],
                                      capture_output=True, text=True, timeout=45)
                if proc.returncode == 0:
                    self.listenersLoaded.emit(proc.stdout.strip() or '{"listeners":[]}')
                elif proc.returncode == 126:
                    self.message.emit("Cancelled.")
                else:
                    self.message.emit(proc.stderr.strip() or "Could not reveal protected processes.")
            except Exception as exc:
                self.message.emit("Could not reveal protected processes: %s" % exc)
            finally:
                self._set_busy(False)
        self._thread(work)

    @Slot(int, str)
    def inspectPort(self, port, address):
        if self._busy:
            return
        self._set_busy(True)

        def work():
            try:
                proc = subprocess.run(
                    [CLI, "inspect-json", str(port), address or "127.0.0.1"],
                    capture_output=True, text=True, timeout=12)
                self.inspectionLoaded.emit(proc.stdout.strip() or '{"reachable":false}')
            except Exception as exc:
                self.inspectionLoaded.emit('{"reachable":false,"endpoints":[]}')
                self.message.emit("Inspection failed: %s" % exc)
            finally:
                self._set_busy(False)
        self._thread(work)

    @Slot(int, int)
    def killProcess(self, pid, port):
        if self._busy or pid <= 0:
            return
        self._set_busy(True)

        def work():
            try:
                proc = subprocess.run([CLI, "kill", str(pid), str(port)],
                                      capture_output=True, text=True, timeout=8)
                if proc.returncode == 13:
                    proc = subprocess.run(
                        ["pkexec", CLI, "kill", str(pid), str(port)],
                        capture_output=True, text=True, timeout=45)
                data = json.loads(proc.stdout or "{}")
                if proc.returncode == 0 and data.get("ok"):
                    self.message.emit("Process %d stopped." % pid)
                elif proc.returncode == 126:
                    self.message.emit("Cancelled.")
                else:
                    self.message.emit(data.get("error") or proc.stderr.strip() or "Could not stop process.")
            except Exception as exc:
                self.message.emit("Could not stop process: %s" % exc)
            finally:
                self._set_busy(False)
                self.refresh()
        self._thread(work)


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    try:
        if subprocess.run(["systemd-detect-virt", "--quiet"], timeout=4).returncode == 0:
            os.environ.setdefault("QT_QUICK_BACKEND", "software")
    except Exception:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi PortScope")
    app.setApplicationDisplayName("Genesi PortScope")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName("org.genesi.ports")
    app.setWindowIcon(QIcon.fromTheme("genesi-ports"))

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        return 1
    backend.refresh()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
