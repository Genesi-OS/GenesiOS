#!/usr/bin/env python3
"""
Genesi Sandboxes — GUI for isolated developer workspaces (Distrobox).

Pure front-end: every action is delegated to the `genesi-sandboxes` CLI (the
single source of truth), run in a worker thread so the UI never blocks. The UI
lives in Main.qml; this is the QML engine plus a small backend object.
"""
import os
import sys
import json
import shutil
import threading
import subprocess

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Sandboxes needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

CLI = "genesi-sandboxes"


class Backend(QObject):
    boxesLoaded = Signal(str)       # JSON: {distrobox, boxes[]}
    templatesLoaded = Signal(str)   # JSON: [{id,label,image,packages,hint}]
    busyChanged = Signal(bool)
    logLine = Signal(str)           # streamed output from create/remove
    actionDone = Signal(str)        # human-readable "done" message

    def __init__(self):
        super().__init__()
        self._busy = False

    def _set_busy(self, v):
        self._busy = v
        self.busyChanged.emit(v)

    # --- queries (fast, run inline) -----------------------------------------
    @Slot()
    def refresh(self):
        try:
            out = subprocess.run([CLI, "list-json"], capture_output=True,
                                 text=True, timeout=20).stdout.strip()
            self.boxesLoaded.emit(out or '{"distrobox":false,"boxes":[]}')
        except Exception as e:
            self.boxesLoaded.emit('{"distrobox":false,"boxes":[]}')
            self.logLine.emit("error listing sandboxes: %s" % e)

    @Slot()
    def loadTemplates(self):
        try:
            out = subprocess.run([CLI, "templates-json"], capture_output=True,
                                 text=True, timeout=20).stdout.strip()
            self.templatesLoaded.emit(out or "[]")
        except Exception:
            self.templatesLoaded.emit("[]")

    # --- mutations (threaded, streamed) -------------------------------------
    def _run_stream(self, args, done_msg):
        if self._busy:
            return
        self._set_busy(True)

        def work():
            try:
                proc = subprocess.Popen(args, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True,
                                        bufsize=1)
                for line in iter(proc.stdout.readline, ""):
                    if line:
                        self.logLine.emit(line.rstrip("\n"))
                proc.wait()
                if proc.returncode == 0:
                    self.actionDone.emit(done_msg)
                else:
                    self.actionDone.emit("failed (exit %d)" % proc.returncode)
            except Exception as e:
                self.logLine.emit("error: %s" % e)
                self.actionDone.emit("failed")
            finally:
                self._set_busy(False)
                self.refresh()

        threading.Thread(target=work, daemon=True).start()

    @Slot(str, str)
    def createSandbox(self, name, template):
        name = (name or "").strip()
        if not name:
            self.logLine.emit("Please enter a name.")
            return
        self.logLine.emit("=== creating '%s' (%s) ===" % (name, template))
        self._run_stream([CLI, "create", name, template],
                         "Sandbox '%s' ready." % name)

    @Slot(str)
    def removeSandbox(self, name):
        self.logLine.emit("=== removing '%s' ===" % name)
        self._run_stream([CLI, "rm", name], "Sandbox '%s' removed." % name)

    @Slot(str)
    def enterSandbox(self, name):
        # Detached: opens its own terminal; never blocks the GUI.
        try:
            subprocess.Popen([CLI, "enter", name],
                             start_new_session=True)
        except Exception as e:
            self.logLine.emit("error: %s" % e)

    @Slot(str)
    def openInCode(self, name):
        # Open the workspace's project folder in Genesi Code (host-side IDE).
        # Detached so the GUI never blocks on the editor process.
        try:
            subprocess.Popen([CLI, "code", name], start_new_session=True)
            self.logLine.emit("Opening '%s' in Genesi Code…" % name)
        except Exception as e:
            self.logLine.emit("error: %s" % e)


def main():
    # Use Plasma's Qt Quick Controls style so the app inherits the system color
    # scheme (the dark Genesi theme) AND renders controls — notably the template
    # ComboBox — with the proper desktop style. Without this the app falls back
    # to the Basic QtQuick style, where the (unstyled) ComboBox paints as a flat
    # accent-green box and its items are unreadable, so the template dropdown
    # looked permanently empty ("no sandbox option appears"). Needs
    # qqc2-desktop-style (a hard dependency); falls back silently if absent.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    # In a VM the guest GL stack (VirtualBox/VMware SVGA) lies about its
    # capabilities and Qt Quick's RHI SIGSEGVs creating the GL context — the app
    # crashes before the window appears. Fall back to the software scene graph
    # when virtualized (bare metal keeps GPU rendering): no GPU needed, the whole
    # UI still renders, and this app isn't perf-critical. A user QT_QUICK_BACKEND
    # always wins (setdefault).
    try:
        if subprocess.run(["systemd-detect-virt", "--quiet"],
                          timeout=4).returncode == 0:
            os.environ.setdefault("QT_QUICK_BACKEND", "software")
    except Exception:
        pass
    try:
        from PySide6.QtQuickControls2 import QQuickStyle
        QQuickStyle.setStyle("org.kde.desktop")
    except ImportError:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi Sandboxes")
    app.setApplicationDisplayName("Genesi Sandboxes")
    app.setOrganizationName("Genesi OS")
    # Match the .desktop so the taskbar shows our name+icon, not "python3".
    app.setDesktopFileName("org.genesi.sandboxes")
    app.setWindowIcon(QIcon.fromTheme("genesi-sandboxes"))
    if not shutil.which(CLI):
        sys.stderr.write("genesi-sandboxes CLI not found in PATH\n")

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    backend.loadTemplates()
    backend.refresh()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
