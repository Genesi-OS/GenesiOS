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
import getpass
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error

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
import stage


def fmt_bytes(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return ("%.1f %s" % (n, unit)) if unit in ("GB", "TB") else ("%d %s" % (n, unit))
        n /= 1024

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
        self._cancel = False

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

    # ── prepare: download, copy, arm the restart ──────────────────────
    prepStep = Signal(str, float, str)  # step id, 0..1, detail ("1.2 / 3.4 GB · 18 MB/s")
    prepFailed = Signal(str, str)       # translation key, JSON list of args
    prepDone = Signal(str)              # JSON: the stage plan

    def _pkexec(self, *args):
        """Run the root helper through pkexec. The AppImage's FUSE mount is not
        readable by root, so the helper is copied out to the user's runtime
        dir first and run by /bin/sh."""
        rt = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        helper = os.path.join(rt, "genesi-migrate-helper.sh")
        shutil.copyfile(os.path.join(HERE, "helper.sh"), helper)
        os.chmod(helper, 0o700)
        p = subprocess.run(["pkexec", "/bin/sh", helper] + list(args),
                           capture_output=True, text=True)
        if p.returncode in (126, 127) and not p.stderr.strip().startswith("error:"):
            raise stage.StageError("st.auth")
        if p.returncode != 0:
            raise stage.StageError("st.helper", (p.stderr or p.stdout).strip().splitlines()[-1:] or ["?"])
        return p.stdout

    @Slot(str)
    def prepare(self, manifest_json):
        self._cancel = False
        threading.Thread(target=self._prepare, args=(json.loads(manifest_json),), daemon=True).start()

    @Slot()
    def cancelPrepare(self):
        self._cancel = True

    def _prepare(self, manifest):
        cancelled = lambda: self._cancel  # noqa: E731
        home = os.path.expanduser("~")
        try:
            if self._demo:
                return self._prepare_demo(manifest, cancelled)
            self.prepStep.emit("space", 0, "")
            p = stage.plan(manifest, home)
            if p["needsRoot"]:
                self._pkexec("mkdir", p["dir"], getpass.getuser())
            os.makedirs(p["dir"], exist_ok=True)
            need = 0 if os.path.exists(p["iso"]) else stage.ISO_ROOM
            if p["filesDir"]:
                need += manifest["choices"].get("selectedBytes", 0)
            free = shutil.disk_usage(p["dir"]).free
            if free < need:
                raise stage.StageError("st.space", fmt_bytes(need), fmt_bytes(free))
            self.prepStep.emit("space", 1, "")

            # download (skipped when a verified ISO is already there)
            want = stage.expected_sha()
            ok_marker = p["iso"] + ".ok"
            if not (os.path.exists(p["iso"]) and os.path.exists(ok_marker)
                    and open(ok_marker).read().strip() == want):
                def dl(done, total, speed):
                    detail = "%s / %s" % (fmt_bytes(done), fmt_bytes(total))
                    if speed:
                        detail += " · %s/s" % fmt_bytes(speed)
                    self.prepStep.emit("download", done / total if total else 0, detail)
                stage.download(p["iso"], dl, cancelled)
                self.prepStep.emit("verify", 0, "")
                got = stage.sha256_of(p["iso"], lambda d, t: self.prepStep.emit("verify", d / t, ""), cancelled)
                if got != want:
                    os.remove(p["iso"])
                    raise stage.StageError("st.sha")
                with open(ok_marker, "w") as f:
                    f.write(want)
            self.prepStep.emit("download", 1, "")
            self.prepStep.emit("verify", 1, "")

            if p["filesDir"]:
                pairs = stage.sources(manifest, home)
                errs = stage.copy_tree(
                    pairs, p["filesDir"],
                    lambda d, t: self.prepStep.emit("files", d / t if t else 1,
                                                    "%s / %s" % (fmt_bytes(d), fmt_bytes(t))),
                    cancelled, skip={os.path.join(home, s) for s in scanner.SKIP_IN_HOME} | {p["dir"]})
                if errs:
                    with open(os.path.join(p["dir"], "copy-errors.txt"), "w") as f:
                        f.write("\n".join(errs))
                self.prepStep.emit("files", 1, "%d" % len(errs) if errs else "")

            self.prepStep.emit("arm", 0, "")
            stage.write_stage(manifest, p, home)
            entry = os.path.join(p["stage"], "grub-entry.cfg")
            with open(entry, "w") as f:
                f.write(stage.grub_entry(p))
            self._pkexec("arm", p["stage"], entry)
            self.prepStep.emit("arm", 1, "")
            self.prepDone.emit(json.dumps(p))
        except stage.StageError as e:
            self.prepFailed.emit(e.key, json.dumps([str(a) for a in e.args_]))
        except urllib.error.URLError as e:
            self.prepFailed.emit("st.net", json.dumps([str(getattr(e, "reason", e))]))
        except Exception as e:
            self.prepFailed.emit("st.other", json.dumps([str(e)]))

    def _prepare_demo(self, manifest, cancelled):
        # The same steps and pacing as the real thing, nothing downloaded.
        steps = ["space", "download", "verify"]
        if manifest["choices"]["strategy"].startswith("external:"):
            steps.append("files")
        steps.append("arm")
        for s in steps:
            n = 24 if s == "download" else 6
            for i in range(n + 1):
                if cancelled():
                    raise stage.StageError("st.cancelled")
                total = 3457810432
                detail = "%s / %s · 42 MB/s" % (fmt_bytes(total * i / n), fmt_bytes(total)) if s == "download" else ""
                self.prepStep.emit(s, i / n, detail)
                time.sleep(0.05)
        self.prepDone.emit(json.dumps({"copytoram": False, "demo": True}))

    @Slot()
    def disarm(self):
        if self._demo:
            return
        try:
            self._pkexec("disarm")
        except stage.StageError:
            pass

    @Slot()
    def reboot(self):
        if self._demo:
            return
        for cmd in (["systemctl", "reboot"], ["loginctl", "reboot"], ["pkexec", "systemctl", "reboot"]):
            try:
                if subprocess.run(cmd).returncode == 0:
                    return
            except OSError:
                continue

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
