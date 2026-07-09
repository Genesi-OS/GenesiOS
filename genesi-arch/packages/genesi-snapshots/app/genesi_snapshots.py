#!/usr/bin/env python3
"""
Genesi Snapshots — GUI for the "indestructible OS" snapshot system.

Pure front-end: every action is delegated to the `genesi-snapshots` CLI (the
single source of truth), run in a worker thread so the UI never blocks. Read-only
queries (status/list) run as the user; mutating ones (create/delete/rollback) go
through pkexec so the user authenticates graphically. The UI lives in Main.qml.
"""
import os
import sys
import shutil
import threading
import subprocess

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Snapshots needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

CLI = "genesi-snapshots"
# Absolute path for pkexec: it runs a root-owned program by full path (the
# read-only queries below still use the PATH name, run as the current user).
CLI_ABS = shutil.which(CLI) or "/usr/bin/genesi-snapshots"


class Backend(QObject):
    statusLoaded = Signal(str)      # JSON: {btrfs,configured,snapPac,grubBtrfs,count}
    snapshotsLoaded = Signal(str)   # JSON: {configured,snapshots[]}
    busyChanged = Signal(bool)
    logLine = Signal(str)
    actionDone = Signal(str)        # human-readable result message

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
            st = subprocess.run([CLI, "status-json"], capture_output=True,
                                text=True, timeout=20).stdout.strip()
            self.statusLoaded.emit(st or '{"btrfs":false,"configured":false}')
        except Exception as e:
            self.statusLoaded.emit('{"btrfs":false,"configured":false}')
            self.logLine.emit("error reading status: %s" % e)
        try:
            ls = subprocess.run([CLI, "list-json"], capture_output=True,
                                text=True, timeout=20).stdout.strip()
            self.snapshotsLoaded.emit(ls or '{"configured":false,"snapshots":[]}')
        except Exception as e:
            self.snapshotsLoaded.emit('{"configured":false,"snapshots":[]}')
            self.logLine.emit("error listing snapshots: %s" % e)

    # --- mutations (threaded, pkexec) ---------------------------------------
    def _run(self, args, done_msg):
        if self._busy:
            return
        self._set_busy(True)

        def work():
            try:
                proc = subprocess.run(args, capture_output=True, text=True)
                out = (proc.stdout or "").strip()
                err = (proc.stderr or "").strip()
                if out:
                    self.logLine.emit(out)
                if proc.returncode == 0:
                    self.actionDone.emit(done_msg)
                elif proc.returncode == 126:
                    # pkexec: user dismissed the auth dialog
                    self.actionDone.emit("cancelled")
                else:
                    self.logLine.emit(err or "exit %d" % proc.returncode)
                    self.actionDone.emit("failed")
            except Exception as e:
                self.logLine.emit("error: %s" % e)
                self.actionDone.emit("failed")
            finally:
                self._set_busy(False)
                self.refresh()

        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def createSnapshot(self, desc):
        desc = (desc or "").strip() or "Manual snapshot"
        self.logLine.emit("=== creating snapshot: %s ===" % desc)
        self._run(["pkexec", CLI_ABS, "create", desc], "Snapshot created.")

    @Slot(int)
    def deleteSnapshot(self, number):
        self.logLine.emit("=== deleting snapshot %d ===" % number)
        self._run(["pkexec", CLI_ABS, "delete", str(number)],
                  "Snapshot %d deleted." % number)

    @Slot(int)
    def rollback(self, number):
        self.logLine.emit("=== rolling back to snapshot %d ===" % number)
        self._run(["pkexec", CLI_ABS, "rollback", str(number)],
                  "Rolled back to #%d. Reboot to apply." % number)


def main():
    # Fusion QQC2 style (self-drawn, dark via QT_QPA_PLATFORMTHEME=kde). The
    # org.kde.desktop style delegates to Darkly, which SIGSEGVs from QML — same
    # reasoning as the AI Monitor / Sandboxes.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    # In a VM the guest GL stack lies and Qt Quick's RHI SIGSEGVs building the GL
    # context — fall back to the software scene graph when virtualized (bare metal
    # keeps GPU rendering). A user QT_QUICK_BACKEND always wins (setdefault).
    try:
        if subprocess.run(["systemd-detect-virt", "--quiet"],
                          timeout=4).returncode == 0:
            os.environ.setdefault("QT_QUICK_BACKEND", "software")
    except Exception:
        pass
    try:
        from PySide6.QtQuickControls2 import QQuickStyle
        QQuickStyle.setStyle("Fusion")
    except ImportError:
        pass

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi Snapshots")
    app.setApplicationDisplayName("Genesi Snapshots")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName("org.genesi.snapshots")
    app.setWindowIcon(QIcon.fromTheme("genesi-snapshots"))
    if not shutil.which(CLI):
        sys.stderr.write("genesi-snapshots CLI not found in PATH\n")

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    backend.refresh()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
