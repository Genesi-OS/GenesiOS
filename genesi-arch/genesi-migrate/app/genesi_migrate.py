#!/usr/bin/env python3
"""
Genesi Migrate -- move from any Linux to Genesi.

This is the window people open on the distro they are LEAVING. It scans the
system (scanner.py, read-only, no root), lets them pick which apps, files and
settings come along, and writes the migration manifest the Genesi installer
reads. The UI lives in Main.qml.

Runs from an AppImage on Ubuntu, Fedora, openSUSE, Mint, Arch... so it must
not lean on anything a Genesi install has and they don't: no Kirigami, no
genesi_palette, no KDE platform theme.

  --demo           use demo-manifest.json instead of scanning (UI work on a
                   machine that isn't Linux, and the screenshots)
  --manifest FILE  like --demo, but replay a manifest saved from a real scan
                   (reproduce what a tester saw without their machine)
  --page N         open on page N (implies an immediate scan)
  --shot FILE      render, save a PNG of the window to FILE, quit
"""
import argparse
import json
import os
import stat
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow  # noqa: F401 -- root object is cast to it (grabWindow)
except ImportError:
    sys.stderr.write("Genesi Migrate needs PySide6 (bundled in the AppImage).\n")
    sys.exit(1)

import appmap
import scanner

DATA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                        "genesi-migrate")
MANIFEST = os.path.join(DATA_DIR, "manifest.json")


class Backend(QObject):
    progress = Signal(str, float)       # stage id, 0..1
    scanned = Signal(str)               # full manifest JSON
    machineUpdated = Signal(str)        # {"machine":…, "plan":…} after a disk rescan
    saved = Signal(bool, str)           # ok, path or error

    def __init__(self, demo=False, replay=""):
        super().__init__()
        self._demo = demo or bool(replay)
        self._replay = replay or os.path.join(HERE, "demo-manifest.json")
        self._os = scanner.Scanner().detect_os() if not self._demo else self._replayed()["os"]

    def _replayed(self):
        with open(self._replay, encoding="utf-8") as f:
            return json.load(f)

    @Property(str, constant=True)
    def osPretty(self):
        return self._os.get("pretty", "Linux")

    @Property(str, constant=True)
    def desktopsJson(self):
        return json.dumps([{"id": i, "name": n} for i, n in appmap.GENESI_DESKTOPS])

    @Property(bool, constant=True)
    def demo(self):
        return self._demo

    @Slot()
    def scan(self):
        def work():
            try:
                if self._demo:
                    for stage, frac in (("system", .1), ("apps", .3), ("flatpak", .45),
                                        ("files", .6), ("machine", .85), ("settings", .95)):
                        self.progress.emit(stage, frac)
                        time.sleep(0.35)
                    result = self._replayed()
                    self.progress.emit("done", 1.0)
                else:
                    result = scanner.Scanner(progress=self.progress.emit).scan()
                self.scanned.emit(json.dumps(result))
            except Exception as e:  # never leave the scan page spinning forever
                self.scanned.emit(json.dumps({"error": str(e)}))
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def rescanDisks(self, files_json):
        """Re-read the disks (the user just plugged in a drive)."""
        def work():
            try:
                files = json.loads(files_json)
                machine = scanner.Scanner().machine() if not self._demo else None
                if machine is None:
                    machine = self._replayed()["machine"]
                self.machineUpdated.emit(json.dumps({"machine": machine,
                                                     "plan": scanner.plan(machine, files)}))
            except Exception as e:
                self.machineUpdated.emit(json.dumps({"error": str(e)}))
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def saveManifest(self, manifest_json):
        try:
            data = json.loads(manifest_json)
            os.makedirs(DATA_DIR, exist_ok=True)
            tmp = MANIFEST + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            # Wi-Fi names and the user's account are in here: owner-only.
            os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
            os.replace(tmp, MANIFEST)
            self.saved.emit(True, MANIFEST)
        except Exception as e:
            self.saved.emit(False, str(e))

    @Slot(str)
    def openFolder(self, path):
        folder = path if os.path.isdir(path) else os.path.dirname(path)
        try:
            subprocess.Popen(["xdg-open", folder], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--manifest", default="")
    ap.add_argument("--page", type=int, default=0)
    ap.add_argument("--shot", default="")
    ap.add_argument("--lang", default="")
    ap.add_argument("--size", default="", help="WxH, for screenshots")
    args, qt_args = ap.parse_known_args()

    # Fusion draws itself, so it looks the same on every distro. The platform
    # theme is left alone: forcing "kde" on a GNOME box would just fail.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    # VMs: the guest GL stack lies and Qt Quick's RHI can crash creating the
    # context, so use the software scene graph there. Bare metal keeps the GPU.
    # (The whole UI is shader-free, so software rendering looks identical.)
    if sys.platform.startswith("linux"):
        try:
            if subprocess.run(["systemd-detect-virt", "--quiet"], timeout=4).returncode == 0:
                os.environ.setdefault("QT_QUICK_BACKEND", "software")
        except (OSError, subprocess.SubprocessError):
            pass

    app = QGuiApplication([sys.argv[0]] + qt_args)
    app.setApplicationName("Genesi Migrate")
    app.setApplicationDisplayName("Genesi Migrate")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName("org.genesi.migrate")
    icon = os.path.join(HERE, "icons", "genesi-migrate.svg")
    if os.path.isfile(icon):
        app.setWindowIcon(QIcon(icon))

    backend = Backend(demo=args.demo, replay=args.manifest)
    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("backend", backend)
    ctx.setContextProperty("startPage", args.page)
    ctx.setContextProperty("forcedLang", args.lang)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)

    win = engine.rootObjects()[0]
    if args.size:
        w, h = (int(v) for v in args.size.lower().split("x"))
        win.resize(w, h)
    if args.shot:

        def grab():
            try:
                win.grabWindow().save(args.shot)
            finally:
                app.quit()
        # Long enough for the demo scan (≈2.5 s) and the page transition.
        QTimer.singleShot(4200 if args.page > 1 else 1200, grab)

    code = app.exec()
    # Tear the QML down while `backend` still exists; otherwise Python frees
    # the backend first and every binding on it logs "of null" on the way out.
    del engine
    sys.exit(code)


if __name__ == "__main__":
    main()
