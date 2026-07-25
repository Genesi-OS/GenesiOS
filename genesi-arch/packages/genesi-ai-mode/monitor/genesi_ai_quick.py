#!/usr/bin/env python3
"""Always-ready, approval-only Genesi AI Quick Chat."""

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import urllib.request

from PySide6.QtCore import QUrl, Signal, Slot
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

import genesi_turbo_ctl as turbo_ctl
from genesi_ai_monitor import Backend, OLLAMA, TURBO


APP_ID = "org.genesi.aiquick"
SOCKET_NAME = "genesi-ai-quick.sock"


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/genesi-ai-{os.getuid()}"
    os.makedirs(runtime, mode=0o700, exist_ok=True)
    return os.path.join(runtime, SOCKET_NAME)


def send_to_running(command):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(0.5)
            client.connect(socket_path())
            client.sendall(command.encode("utf-8"))
        return True
    except OSError:
        return False


class QuickBackend(Backend):
    toggleRequested = Signal()
    showRequested = Signal()
    modelChanged = Signal(str)

    def __init__(self):
        super().__init__()
        self._quick_model = ""
        self._socket = None
        # Model/service discovery may need to wake Ollama. Keep it off the GUI
        # thread so Ctrl+Alt+Space can paint immediately after login.
        threading.Thread(target=self._prepare_model, daemon=True).start()

    @Slot(result=str)
    def quickModel(self):
        return self._quick_model

    @Slot(result=bool)
    def quickTurboActive(self):
        return self._turbo_alive()

    @Slot()
    def refreshModel(self):
        threading.Thread(target=self._prepare_model, daemon=True).start()

    def _prepare_model(self):
        # Reuse an already-running Turbo server. The Quick Chat never starts,
        # stops or reconfigures Turbo, so it cannot disturb Monitor performance.
        try:
            with urllib.request.urlopen(TURBO + "/health", timeout=0.8) as response:
                self._turbo = response.status == 200
        except Exception:
            self._turbo = False

        model = ""
        if self._ensure_ollama():
            try:
                with urllib.request.urlopen(OLLAMA + "/api/tags", timeout=3) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                models = [item.get("name") for item in payload.get("models", [])]
                model = next((name for name in models if name), "")
            except Exception:
                pass
        # A running Turbo may have unloaded Ollama and therefore be the only
        # source that still knows its model. Use its OpenAI models endpoint as a
        # fallback, while keeping the real model name (never the string "turbo").
        if not model and self._turbo:
            marker = turbo_ctl.current_model()
            if marker:
                model = marker            # exact reference, incl. a `gguf:` one
            else:
                try:
                    with urllib.request.urlopen(TURBO + "/v1/models", timeout=2) as response:
                        payload = json.loads(response.read().decode("utf-8"))
                    model = next((item.get("id") for item in payload.get("data", [])
                                  if item.get("id")), "")
                except Exception:
                    pass
        # Nothing from Ollama (not installed, or the user only keeps local GGUF
        # files): fall back to the GGUF library so Quick Chat still has a model.
        if not model:
            local = turbo_ctl.list_gguf_models()
            if local:
                model = local[0]["ref"]
        self.turboReady.emit(self._turbo)
        if model != self._quick_model:
            self._quick_model = model
            self.modelChanged.emit(model)

    def listen(self):
        path = socket_path()
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        os.chmod(path, 0o600)
        server.listen(4)
        self._socket = server

        def serve():
            while True:
                try:
                    connection, _ = server.accept()
                    with connection:
                        command = connection.recv(64).decode("utf-8", "replace").strip()
                    if command == "show":
                        self.showRequested.emit()
                    else:
                        self.toggleRequested.emit()
                except OSError:
                    return

        threading.Thread(target=serve, daemon=True).start()

    def closeSocket(self):
        if self._socket:
            self._socket.close()
        try:
            os.unlink(socket_path())
        except FileNotFoundError:
            pass


def configure_qt():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if "kde" in desktop or "plasma" in desktop:
        os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    try:
        if subprocess.run(["systemd-detect-virt", "--quiet"], timeout=3).returncode == 0:
            os.environ.setdefault("QT_QUICK_BACKEND", "software")
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--toggle", action="store_true")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()

    command = "toggle" if args.toggle else "show"
    if send_to_running(command):
        return 0

    configure_qt()
    app = QGuiApplication(sys.argv[:1])
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Genesi AI Quick Chat")
    app.setApplicationDisplayName("Genesi AI Quick Chat")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName(APP_ID)
    app.setWindowIcon(QIcon.fromTheme("genesi-ai-monitor"))
    try:
        if "Rubik" in QFontDatabase.families():
            font = app.font()
            font.setFamily("Rubik")
            font.setStyleStrategy(QFont.PreferAntialias)
            app.setFont(font)
    except Exception:
        pass

    backend = QuickBackend()
    try:
        backend.listen()
    except OSError:
        if send_to_running(command):
            return 0
        raise

    # Register the shortcut in the active compositor/session. It is idempotent
    # and also repairs registrations after a DE switch.
    try:
        subprocess.Popen(["genesi-ai-quick-shortcuts"], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    except OSError:
        pass

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "QuickChat.qml")))
    if not engine.rootObjects():
        backend.closeSocket()
        return 1
    root = engine.rootObjects()[0]
    backend.toggleRequested.connect(root.toggleQuick)
    backend.showRequested.connect(root.showQuick)
    app.aboutToQuit.connect(backend.closeSocket)
    app.aboutToQuit.connect(backend.stopChat)
    if not args.background:
        root.showQuick()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
