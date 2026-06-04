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
import time
import signal
import shutil
import tempfile
import threading
import subprocess
import urllib.request

try:
    from PySide6.QtCore import QObject, Slot, Signal, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError:
    sys.stderr.write(
        "Genesi AI Mode Monitor needs PySide6.\n"
        "  Install it with:  sudo pacman -S pyside6\n")
    sys.exit(1)

STATE_FILE = "/run/genesi-ai-mode/state.json"
OLLAMA = "http://127.0.0.1:11434"
TURBO = "http://127.0.0.1:11435"      # genesi-ai-turbo's llama-server


class Backend(QObject):
    # Chat signals (emitted from a worker thread; Qt queues them to the GUI).
    chatToken = Signal(str)      # one streamed token
    chatDone = Signal(str)       # verbose stats line ("" if none)
    chatError = Signal(str)
    modelsLoaded = Signal(str)   # JSON array of model names
    pullStatus = Signal(str)     # human-readable download progress
    pullDone = Signal(bool)      # finished (ok?)
    turboStatus = Signal(str)    # Turbo (speculative decoding) state text
    turboReady = Signal(bool)    # Turbo server up and serving?
    turboNeedsInstall = Signal(bool)  # backend (llama-server) missing -> offer install

    def __init__(self):
        super().__init__()
        self._stop = False
        self._turbo = False          # route chat to the Turbo server?
        self._turbo_proc = None      # the genesi-ai-turbo serve subprocess
        self._turbo_model = None
        self._turbo_log = None       # captured stderr of the serve subprocess

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

    @Slot(result=str)
    def advise(self):
        """Model Advisor text — single source of truth is the CLI."""
        try:
            r = subprocess.run(["genesi-ai-mode", "advise"],
                               capture_output=True, text=True, timeout=10)
            return (r.stdout or r.stderr or "").strip()
        except Exception as e:
            return f"erro ao consultar o advisor: {e}"

    @Slot(str)
    def setMode(self, mode):
        if mode in ("on", "off", "auto", "toggle"):
            try:
                subprocess.Popen(["genesi-ai-mode", mode],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except OSError:
                pass

    # ── chat (talk to the locally-running Ollama, stream + verbose stats) ─────
    @Slot()
    def loadModels(self):
        def work():
            try:
                with urllib.request.urlopen(OLLAMA + "/api/tags", timeout=4) as r:
                    data = json.loads(r.read().decode())
                names = [m.get("name") for m in data.get("models", []) if m.get("name")]
            except Exception:
                names = []
            self.modelsLoaded.emit(json.dumps(names))
        threading.Thread(target=work, daemon=True).start()

    @Slot(str, str)
    def sendPrompt(self, model, prompt):
        self._stop = False
        target = self._chat_turbo if self._turbo else self._chat_ollama
        threading.Thread(target=target, args=(model, prompt), daemon=True).start()

    def _chat_ollama(self, model, prompt):
        body = json.dumps({"model": model, "prompt": prompt, "stream": True}).encode()
        req = urllib.request.Request(OLLAMA + "/api/generate", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                for raw in r:
                    if self._stop:
                        break
                    raw = raw.strip()
                    if not raw:
                        continue
                    obj = json.loads(raw.decode())
                    tok = obj.get("response", "")
                    if tok:
                        self.chatToken.emit(tok)
                    if obj.get("done"):
                        self.chatDone.emit(self._stats(obj))
                        return
            self.chatDone.emit("")
        except Exception as e:
            self.chatError.emit(str(e))

    def _chat_turbo(self, model, prompt):
        # llama-server native /completion (the Turbo server is already loaded
        # with the model + draft, so `model` is ignored here).
        body = json.dumps({"prompt": prompt, "stream": True,
                           "n_predict": 512, "cache_prompt": True}).encode()
        req = urllib.request.Request(TURBO + "/completion", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                for raw in r:
                    if self._stop:
                        break
                    line = raw.decode().strip()
                    if not line:
                        continue
                    if line.startswith("data:"):
                        line = line[5:].strip()
                    try:
                        o = json.loads(line)
                    except ValueError:
                        continue
                    tok = o.get("content", "")
                    if tok:
                        self.chatToken.emit(tok)
                    if o.get("stop"):
                        t = o.get("timings", {})
                        tps, n = t.get("predicted_per_second"), t.get("predicted_n")
                        self.chatDone.emit(
                            f"⚡ {tps:.1f} tok/s   •   {n} tokens   •   Turbo (speculative)"
                            if tps else "⚡ Turbo")
                        return
            self.chatDone.emit("")
        except Exception as e:
            self.chatError.emit("Turbo: " + str(e))

    @Slot()
    def stopChat(self):
        self._stop = True

    # ── Turbo (speculative decoding via genesi-ai-turbo) ─────────────────────
    @Slot(bool, str)
    def setTurbo(self, on, model):
        if on:
            self._start_turbo(model)
        else:
            self._stop_turbo()

    def _stop_turbo(self):
        self._turbo = False
        self._turbo_model = None
        p, self._turbo_proc = self._turbo_proc, None
        if p:
            try:
                p.send_signal(signal.SIGINT)
                p.wait(timeout=8)
            except Exception:
                try:
                    p.kill()
                except Exception:
                    pass
        log, self._turbo_log = self._turbo_log, None
        if log:
            try:
                os.unlink(log)
            except Exception:
                pass
        self.turboReady.emit(False)
        self.turboStatus.emit("")

    @staticmethod
    def _has_llama_server():
        """Is the Turbo backend (llama-server, from genesi-llama-cpp) present?"""
        return bool(shutil.which("llama-server")
                    or os.path.exists("/usr/bin/llama-server"))

    def _has_gpu(self):
        try:
            s = json.loads(open(STATE_FILE).read())
            return bool((s.get("hardware") or {}).get("gpus"))
        except Exception:
            return False

    def _start_turbo(self, model):
        # Already serving this exact model AND the server is still alive? Nothing
        # to do. The poll() check matters: a dead Popen object would otherwise
        # make us think Turbo is up and never restart a server that crashed.
        if (self._turbo_proc and self._turbo_proc.poll() is None
                and self._turbo_model == model):
            return
        self._stop_turbo()
        if not shutil.which("genesi-ai-turbo"):
            self.turboStatus.emit("genesi-ai-turbo não encontrado")
            return
        # Pre-check the backend so we never hang ~3 min polling a server that
        # can't even start. If llama-server is missing, ask the UI to offer the
        # one-click install (genesi-llama-cpp) instead of failing silently.
        if not self._has_llama_server():
            self.turboNeedsInstall.emit(True)
            self.turboStatus.emit(
                "Backend do Turbo não instalado — clique em “Instalar Turbo”")
            return
        self._turbo_model = model
        gpu_hint = "" if self._has_gpu() else "   (sem GPU: ganho pequeno)"
        self.turboStatus.emit("iniciando Turbo (carregando o modelo)…")
        # Capture the serve subprocess's stderr so we can surface the REAL reason
        # it failed (bad arg, OOM, missing blob…) instead of a generic message.
        try:
            self._turbo_log = tempfile.NamedTemporaryFile(
                "w", delete=False, suffix=".log").name
            self._turbo_proc = subprocess.Popen(
                ["genesi-ai-turbo", "serve", model],
                stdout=subprocess.DEVNULL, stderr=open(self._turbo_log, "w"))
        except Exception as e:
            self.turboStatus.emit("erro ao iniciar Turbo: " + str(e))
            return

        proc, log = self._turbo_proc, self._turbo_log

        def _tail():
            try:
                return "".join(open(log).readlines()[-2:]).strip()
            except Exception:
                return ""

        def wait():
            for i in range(180):
                if self._turbo_model != model:      # cancelled or model changed
                    return
                # The server process exited before becoming ready → surface why.
                if proc.poll() is not None:
                    msg = _tail()
                    self.turboStatus.emit(
                        "Turbo falhou: " + (msg.splitlines()[-1] if msg else
                        "rode no terminal: genesi-ai-turbo serve " + model))
                    return
                try:
                    with urllib.request.urlopen(TURBO + "/health", timeout=2) as r:
                        if json.loads(r.read()).get("status") == "ok":
                            self._turbo = True
                            self.turboReady.emit(True)
                            self.turboStatus.emit(
                                "Turbo ativo ⚡ speculative decoding" + gpu_hint)
                            return
                except Exception:
                    pass
                # live elapsed-time feedback so it never looks frozen
                self.turboStatus.emit(
                    f"iniciando Turbo (carregando o modelo)… {i + 1}s")
                time.sleep(1)
            self.turboStatus.emit(
                "Turbo não subiu — rode no terminal p/ ver o erro: "
                "genesi-ai-turbo serve " + model)
        threading.Thread(target=wait, daemon=True).start()

    @Slot()
    def installTurboBackend(self):
        """One-click install of the Turbo backend: genesi-llama-cpp — the
        PREBUILT Vulkan llama.cpp from the genesi repo (~tens of MB), NOT a heavy
        AUR source build. Runs via pkexec so the user authorizes graphically."""
        if self._has_llama_server():
            self.turboNeedsInstall.emit(False)
            self.turboStatus.emit("Backend já instalado ✓ — ligue o Turbo")
            return
        if not shutil.which("pkexec"):
            self.turboStatus.emit(
                "pkexec ausente — rode: sudo pacman -S genesi-llama-cpp")
            return

        def work():
            self.turboStatus.emit(
                "instalando genesi-llama-cpp… (autorize no diálogo)")
            try:
                p = subprocess.run(
                    ["pkexec", "pacman", "-Sy", "--needed", "--noconfirm",
                     "genesi-llama-cpp"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=900)
            except Exception as e:
                self.turboStatus.emit("falha ao instalar: " + str(e))
                return
            if p.returncode == 0 and self._has_llama_server():
                self.turboNeedsInstall.emit(False)
                self.turboStatus.emit("Backend instalado ✓ — ligue o Turbo de novo")
            else:
                last = ""
                if p.stdout:
                    lines = [l for l in p.stdout.splitlines() if l.strip()]
                    last = lines[-1] if lines else ""
                self.turboStatus.emit("instalação não concluída — " + last)
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def pullModel(self, name):
        """Download a model via Ollama /api/pull (streamed), reporting progress —
        so the user never has to drop to a terminal."""
        name = (name or "").strip()
        if not name:
            return

        def work():
            body = json.dumps({"name": name, "stream": True}).encode()
            req = urllib.request.Request(
                OLLAMA + "/api/pull", data=body,
                headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=3600) as r:
                    for raw in r:
                        raw = raw.strip()
                        if not raw:
                            continue
                        o = json.loads(raw.decode())
                        if o.get("error"):
                            self.pullStatus.emit("erro: " + o["error"])
                            self.pullDone.emit(False)
                            return
                        st = o.get("status", "")
                        comp, tot = o.get("completed"), o.get("total")
                        if comp and tot:
                            self.pullStatus.emit(
                                f"{st}  {comp / tot * 100:.0f}%  "
                                f"({comp / 1e9:.1f}/{tot / 1e9:.1f} GB)")
                        elif st:
                            self.pullStatus.emit(st)
                self.pullStatus.emit(f"{name} baixado")
                self.pullDone.emit(True)
            except Exception as e:
                self.pullStatus.emit("erro: " + str(e))
                self.pullDone.emit(False)
        threading.Thread(target=work, daemon=True).start()

    @staticmethod
    def _stats(obj):
        ec = obj.get("eval_count") or 0
        ed = obj.get("eval_duration") or 0           # ns
        pc = obj.get("prompt_eval_count") or 0
        total = obj.get("total_duration") or 0
        tps = (ec / (ed / 1e9)) if ed else 0
        if not ec:
            return ""
        return (f"{tps:.1f} tok/s   •   {ec} tokens   •   "
                f"prompt {pc}   •   total {total / 1e9:.1f}s")


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
    app.aboutToQuit.connect(backend._stop_turbo)   # don't leave llama-server up
    engine.rootContext().setContextProperty("backend", backend)

    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "Main.qml")))
    if not engine.rootObjects():
        sys.stderr.write("Failed to load the Monitor UI (is kirigami installed?)\n")
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
