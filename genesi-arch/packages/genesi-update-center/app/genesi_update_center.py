#!/usr/bin/env python3
"""
Genesi Update Center — what is available, what changes, and one safe button.

Runs on EVERY desktop, and that is a design decision rather than a convenience:
a Plasma applet only exists on Plasma, a Quickshell widget only on caelestia,
and Genesi ships nine desktop options. An ordinary Qt app is the only shape
that reaches all of them, which is the same reasoning that made genesi-report
a shell script.

Pure front-end. Every read is a plain command run as the user; the single
privileged operation is delegated to `genesi-update-center-apply`, a root-owned
script that takes no arguments reaching pacman. Nothing typed or clicked here
can widen what runs as root — see that file's header.
"""
import json
import os
import shutil
import subprocess
import sys
import threading

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi Update precisa do PySide6.\n"
        "  Instale com:  sudo pacman -S pyside6\n")
    sys.exit(1)

APPLY = "/usr/bin/genesi-update-center-apply"


def _run(cmd, timeout=60):
    """Run a read-only command as the user. Returns (rc, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"{cmd[0]}: not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"{cmd[0]}: timed out"
    except OSError as e:
        return 1, "", str(e)


class Backend(QObject):
    updatesLoaded = Signal(str)     # JSON {state,count,packages[],error}
    systemLoaded = Signal(str)      # JSON {channel,snapshots,lastUpdate}
    busyChanged = Signal(bool)
    logLine = Signal(str)
    applyDone = Signal(int, str)    # rc, human message

    def __init__(self):
        super().__init__()
        self._busy = False

    # ── busy ────────────────────────────────────────────────────────────────
    def _set_busy(self, v):
        self._busy = v
        self.busyChanged.emit(v)

    @Slot(result=bool)
    def isBusy(self):
        return self._busy

    # ── what is available ───────────────────────────────────────────────────
    @Slot()
    def refresh(self):
        if self._busy:
            return
        self._set_busy(True)
        threading.Thread(target=self._refresh_worker, daemon=True).start()

    def _refresh_worker(self):
        out = {"state": "unknown", "count": 0, "packages": [], "error": ""}
        try:
            # `checkupdates` (pacman-contrib) is the right tool: it syncs into a
            # PRIVATE database, so it never needs root and never leaves the real
            # one half-updated — the classic `pacman -Sy` footgun that produces
            # partial upgrades later.
            if shutil.which("checkupdates"):
                rc, so, se = _run(["checkupdates"], timeout=120)
                # checkupdates exits 2 for "nothing to do". Treating a normal,
                # happy answer as an error is how an updater starts lying.
                if rc not in (0, 2):
                    out["state"] = "error"
                    out["error"] = (se or so).strip() or "checkupdates falhou"
                    self.updatesLoaded.emit(json.dumps(out))
                    return
                lines = [l for l in so.splitlines() if l.strip()]
            else:
                # Without pacman-contrib we can still answer from the database
                # already on disk. It can be stale, and the UI says so rather
                # than pretending otherwise.
                rc, so, se = _run(["pacman", "-Qu"], timeout=60)
                lines = [l for l in so.splitlines() if l.strip()]
                out["error"] = "stale"

            pkgs = []
            for line in lines:
                # "name old -> new"
                parts = line.split()
                if len(parts) >= 4 and parts[2] == "->":
                    pkgs.append({"name": parts[0], "old": parts[1], "new": parts[3]})
                elif parts:
                    pkgs.append({"name": parts[0], "old": "", "new": ""})
            out["packages"] = pkgs
            out["count"] = len(pkgs)
            out["state"] = "available" if pkgs else "current"
        except Exception as e:                       # never let the UI hang
            out["state"] = "error"
            out["error"] = str(e)
        finally:
            self.updatesLoaded.emit(json.dumps(out))
            self._set_busy(False)

    # ── context around the update ───────────────────────────────────────────
    @Slot()
    def loadSystem(self):
        threading.Thread(target=self._system_worker, daemon=True).start()

    def _system_worker(self):
        info = {"channel": "", "snapshots": False, "lastUpdate": ""}
        rc, so, _ = _run(["genesi-channel", "get"], timeout=10)
        if rc == 0:
            info["channel"] = so.strip()

        # Whether this machine can undo an update is the single most reassuring
        # thing an updater can say, and Genesi already does it -- snap-pac takes
        # a snapshot around every pacman transaction. It just was never shown.
        info["snapshots"] = bool(shutil.which("snapper")) and \
            os.path.exists("/etc/snapper/configs/root")

        # Last upgrade, read from pacman's own log rather than tracked
        # separately: a second source of truth would only drift.
        try:
            with open("/var/log/pacman.log", "r", errors="replace") as fh:
                last = ""
                for line in fh:
                    if "starting full system upgrade" in line:
                        last = line
                if last.startswith("["):
                    info["lastUpdate"] = last[1:last.find("]")]
        except OSError:
            pass
        self.systemLoaded.emit(json.dumps(info))

    # ── the one privileged action ───────────────────────────────────────────
    @Slot()
    def applyUpdates(self):
        if self._busy:
            return
        self._set_busy(True)
        threading.Thread(target=self._apply_worker, daemon=True).start()

    def _apply_worker(self):
        rc = 1
        try:
            # A FIXED argv. No element of it comes from the UI, so there is
            # nothing here for a crafted package name or a stray click to
            # influence. pkexec raises the privilege; the script decides what
            # the privilege is spent on.
            proc = subprocess.Popen(
                ["pkexec", APPLY],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1)
            for line in proc.stdout:
                self.logLine.emit(line.rstrip())
            rc = proc.wait()
        except FileNotFoundError:
            self.logLine.emit("pkexec não encontrado — instale polkit.")
        except Exception as e:
            self.logLine.emit(f"Falha ao executar a atualização: {e}")
        finally:
            # 126/127 are pkexec's own "authentication failed / not authorised".
            # Calling that a failed update would be a lie: nothing was attempted.
            if rc == 0:
                msg = "Sistema atualizado."
            elif rc == 2:
                msg = "Nada a atualizar — já estava em dia."
            elif rc in (126, 127):
                msg = "Autenticação cancelada. Nada foi alterado."
            else:
                msg = "A atualização falhou. Nada ficou pela metade."
            self.applyDone.emit(rc, msg)
            self._set_busy(False)
            self._refresh_worker()

    # ── small helpers the UI needs ──────────────────────────────────────────
    @Slot(str)
    def openApp(self, name):
        """Launch a sibling Genesi app, detached, never blocking the UI."""
        exe = shutil.which(name)
        if not exe:
            return
        try:
            subprocess.Popen([exe], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass


def main():
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi Update")
    app.setOrganizationName("Genesi OS")
    app.setWindowIcon(QIcon.fromTheme("system-software-update"))

    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)

    here = os.path.dirname(os.path.abspath(__file__))
    # The shared UI kit lives beside the app on an installed system and one
    # level up in a checkout; adding both keeps `preview.py` working without
    # the package having to be installed.
    for p in (here, os.path.join(here, ".."), "/usr/share/genesi/ui-kit"):
        if os.path.isdir(p):
            engine.addImportPath(p)

    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("Não foi possível carregar a interface.\n")
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
