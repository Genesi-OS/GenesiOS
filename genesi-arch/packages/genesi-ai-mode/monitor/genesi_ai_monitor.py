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
    turboRecommended = Signal(str)    # advisor's biggest-fits-VRAM model pick
    backendAdvice = Signal(str)       # JSON: which backend (cuda/vulkan) to install
    # Benchmark (wraps `genesi-ai-mode bench`): live progress + parsed result.
    benchRunning = Signal(bool)    # a benchmark is in flight
    benchProgress = Signal(str)    # human-readable step ("warming up …", "AI Mode ON …")
    benchDone = Signal(str)        # JSON: {model, off_rate, on_rate, delta_pct, rows[], raw}
    benchError = Signal(str)

    def __init__(self):
        super().__init__()
        self._stop = False
        self._turbo = False          # route chat to the Turbo server?
        self._turbo_proc = None      # the genesi-ai-turbo serve subprocess
        self._turbo_model = None
        self._turbo_log = None       # captured stderr of the serve subprocess
        self._turbo_spec = False     # is the running Turbo using speculative decoding?
        self._bench_running = False  # a benchmark is in flight (guard re-entry)

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
            return f"error querying the advisor: {e}"

    # ── benchmark (wrap `genesi-ai-mode bench`, stream progress, parse result) ─
    @Slot(str)
    def runBench(self, model):
        """Run `genesi-ai-mode bench [model]` in a worker thread, streaming each
        step to the UI and emitting the parsed OFF-vs-ON generation rate so the
        QML can draw a comparison graph. Single source of truth is still the CLI;
        we only parse its output (never re-implement the measurement)."""
        if self._bench_running:
            return
        model = (model or "llama3.2").strip() or "llama3.2"
        threading.Thread(target=self._bench_work, args=(model,), daemon=True).start()

    def _bench_work(self, model):
        import re
        if not shutil.which("genesi-ai-mode"):
            self.benchError.emit("genesi-ai-mode not found")
            return
        self._bench_running = True
        self.benchRunning.emit(True)
        try:
            proc = subprocess.Popen(
                ["genesi-ai-mode", "bench", model],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1)
        except Exception as e:
            self.benchError.emit(str(e))
            self._bench_running = False
            self.benchRunning.emit(False)
            return

        lines = []
        rows = []
        off_rate = on_rate = delta = None
        # table rows look like: "  generation rate   123.4 tokens/s   145.6 tokens/s"
        row_re = re.compile(r"^\s{2}([a-z][a-z ]+?)\s{2,}(\S.*?)\s{2,}(\S.*)$")
        sum_re = re.compile(
            r"generation:\s*([0-9.]+)\s*->\s*([0-9.]+)\s*tokens/s\s*\(([-+0-9.]+)%\)")
        try:
            for raw in proc.stdout:
                line = raw.rstrip("\n")
                lines.append(line)
                s = line.strip()
                if s.startswith("::"):                       # progress step
                    self.benchProgress.emit(s.lstrip(": ").strip())
                    continue
                m = sum_re.search(line)
                if m:
                    off_rate = float(m.group(1))
                    on_rate = float(m.group(2))
                    delta = float(m.group(3))
                    continue
                rm = row_re.match(line)
                if rm and rm.group(1).strip() not in ("metric",):
                    rows.append([rm.group(1).strip(),
                                 rm.group(2).strip(), rm.group(3).strip()])
            proc.wait()
        except Exception as e:
            self.benchError.emit(str(e))
            self._bench_running = False
            self.benchRunning.emit(False)
            return

        self._bench_running = False
        self.benchRunning.emit(False)
        if off_rate is None or on_rate is None:
            self.benchError.emit(
                "benchmark returned no result — check the model is installed "
                "(ollama pull " + model + ")")
            return
        self.benchDone.emit(json.dumps({
            "model": model,
            "off_rate": off_rate,
            "on_rate": on_rate,
            "delta_pct": delta if delta is not None else
                         (round((on_rate - off_rate) / off_rate * 100, 1)
                          if off_rate else 0),
            "rows": rows,
            "raw": "\n".join(lines).strip(),
        }))

    @Slot(str)
    def setMode(self, mode):
        if mode in ("on", "off", "auto", "toggle"):
            try:
                subprocess.Popen(["genesi-ai-mode", mode],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except OSError:
                pass
            # Force OFF = "stop everything". Also release the RAM Ollama holds via
            # keep-alive — otherwise the model stays resident ~15 min and RAM
            # never returns to baseline after the user turns AI Mode off.
            if mode == "off":
                threading.Thread(target=self._ollama_unload_all, daemon=True).start()

    @Slot(str)
    def setProfile(self, profile):
        """Set the intensity profile: max | balanced | battery | auto."""
        if profile in ("max", "balanced", "battery", "auto"):
            try:
                subprocess.Popen(["genesi-ai-mode", "profile", profile],
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
            except OSError:
                pass

    # ── chat (talk to the locally-running Ollama, stream + verbose stats) ─────
    def _ollama_up(self):
        """Is Ollama's HTTP API answering?"""
        try:
            urllib.request.urlopen(OLLAMA + "/api/tags", timeout=2).read()
            return True
        except Exception:
            return False

    def _ensure_ollama(self):
        """Bring Ollama up if it's installed but its API is down (the classic
        'Errno 111 Connection refused' the user hit: ollama installed via pacman
        but the service never started). Tries the system service first (silent if
        polkit/sudo allows), then a user-owned `ollama serve` fallback (no root,
        and it inherits the user's OLLAMA_MODELS). Returns True once the API
        answers (waits up to ~10s)."""
        if self._ollama_up():
            return True
        if not shutil.which("ollama"):
            return False
        try:
            subprocess.run(["systemctl", "start", "ollama"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=15)
        except Exception:
            pass
        if not self._ollama_up():
            try:
                subprocess.Popen(["ollama", "serve"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
        for _ in range(10):
            if self._ollama_up():
                return True
            time.sleep(1)
        return False

    @Slot()
    def loadModels(self):
        def work():
            self._ensure_ollama()
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
        if not self._ensure_ollama():
            self.chatError.emit("Ollama isn't running (systemctl start ollama)")
            return
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
        # Talk to llama-server's OpenAI-compatible /v1/chat/completions so the
        # SERVER applies the model's chat template (system/user/assistant turns +
        # the correct stop tokens). The native /completion endpoint does NOT
        # apply any template — sending the raw prompt there makes the model
        # ramble forever (it never sees an EOS in context), which is exactly the
        # "AI goes crazy / infinite garbage" seen ONLY in Turbo. The loaded model
        # + draft are already on the server, so `model` is informational here.
        body = json.dumps({
            "messages": [{"role": "user", "content": prompt}],
            "stream": True,
            "max_tokens": 512,
            "cache_prompt": True,
        }).encode()
        req = urllib.request.Request(TURBO + "/v1/chat/completions", data=body,
                                     headers={"Content-Type": "application/json"})
        timings = {}
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                for raw in r:
                    if self._stop:
                        break
                    line = raw.decode().strip()
                    if not line or not line.startswith("data:"):
                        continue
                    line = line[5:].strip()
                    if line == "[DONE]":
                        break
                    try:
                        o = json.loads(line)
                    except ValueError:
                        continue
                    if o.get("timings"):
                        timings = o["timings"]          # llama.cpp SSE extension
                    choices = o.get("choices") or []
                    if choices:
                        tok = (choices[0].get("delta") or {}).get("content") or ""
                        if tok:
                            self.chatToken.emit(tok)
            if timings:
                pms = timings.get("prompt_ms") or 0
                gms = timings.get("predicted_ms") or 0
                self.chatDone.emit(json.dumps({
                    "mode": "turbo",
                    "rate": round(timings.get("predicted_per_second") or 0, 1),
                    "eval": timings.get("predicted_n") or 0,
                    "prompt": timings.get("prompt_n") or 0,
                    "gen_s": round(gms / 1000.0, 2),
                    "prompt_s": round(pms / 1000.0, 2),
                    "total_s": round((pms + gms) / 1000.0, 2),
                }))
            else:
                self.chatDone.emit("")
        except Exception as e:
            self.chatError.emit("Turbo: " + str(e))

    @Slot()
    def stopChat(self):
        self._stop = True

    # ── Turbo (speculative decoding via genesi-ai-turbo) ─────────────────────
    @Slot(bool, str, bool)
    def setTurbo(self, on, model, spec=False):
        if on:
            self._start_turbo(model, spec)
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
        # Backstop: a llama-server may hold the Turbo port even when we didn't
        # start it (e.g. the user ran `genesi-ai-turbo <model>` in a terminal),
        # so our tracked proc is None and stopping would otherwise leave it
        # running — the next "on" then sees the port busy and says "already
        # running", which is the dumb on/off the user hit. Kill any stray Turbo
        # server on our port and WAIT for the socket to actually free.
        self._kill_stray_turbo()
        log, self._turbo_log = self._turbo_log, None
        if log:
            try:
                os.unlink(log)
            except Exception:
                pass
        self.turboReady.emit(False)
        self.turboStatus.emit("")

    def _turbo_alive(self):
        """Is a Turbo llama-server still answering on the port?"""
        try:
            with urllib.request.urlopen(TURBO + "/health", timeout=1) as r:
                return r.status == 200
        except Exception:
            return False

    def _kill_stray_turbo(self):
        """SIGTERM any llama-server bound to the Turbo port (even one we didn't
        start), wait for /health to go away, then SIGKILL if it's stubborn.
        Without the wait, the next `_start_turbo` saw the port still busy and
        refused — the on/off flakiness. Best-effort; needs pkill."""
        if not shutil.which("pkill"):
            return
        pattern = "llama-server.*--port 11435"
        subprocess.run(["pkill", "-f", pattern], check=False)
        for _ in range(24):              # up to ~6s for a clean shutdown
            if not self._turbo_alive():
                return
            time.sleep(0.25)
        subprocess.run(["pkill", "-9", "-f", pattern], check=False)
        for _ in range(16):              # up to ~4s after a force-kill
            if not self._turbo_alive():
                return
            time.sleep(0.25)

    @staticmethod
    def _has_llama_server():
        """Is the Turbo backend (llama-server, from genesi-llama-cpp) present?"""
        return bool(shutil.which("llama-server")
                    or os.path.exists("/usr/bin/llama-server"))

    @staticmethod
    def _nvidia_smi_works():
        """True only when the proprietary/open NVIDIA kernel driver is loaded AND
        functional (nvidia-smi returns 0). False under nouveau/NVK even on an
        NVIDIA card — which is exactly the case where CUDA is NOT available."""
        if not shutil.which("nvidia-smi"):
            return False
        try:
            return subprocess.run(["nvidia-smi"], capture_output=True,
                                  text=True, timeout=6).returncode == 0
        except Exception:
            return False

    def _has_nvidia_gpu(self):
        """Is there an NVIDIA GPU at all (even on the open nouveau/NVK driver)?
        Reads the daemon's profiled GPUs first, then falls back to nvidia-smi's
        mere presence (it ships with the NVIDIA stack)."""
        try:
            s = json.loads(open(STATE_FILE).read())
            for g in (s.get("hardware") or {}).get("gpus") or []:
                if "nvidia" in (g.get("vendor") or "").lower():
                    return True
        except Exception:
            pass
        return shutil.which("nvidia-smi") is not None

    @staticmethod
    def _aur_helper():
        """AUR helper available to build the CUDA backend (CachyOS ships paru)."""
        for h in ("paru", "yay"):
            if shutil.which(h):
                return h
        return None

    @Slot()
    def backendInfo(self):
        """Detect which Turbo backend to recommend and hand the UI everything it
        needs to offer a CUDA-vs-Vulkan choice. CUDA is ~1.5–2× faster but only
        works on an NVIDIA card with the proprietary/open driver actually loaded
        (nvidia-smi works) — useless on nouveau/NVK or non-NVIDIA. Vulkan is the
        universal, already-shipped backend that runs on any GPU. Runs in a worker
        thread (nvidia-smi can take a couple seconds)."""
        def work():
            nv_works = self._nvidia_smi_works()
            has_nv = self._has_nvidia_gpu()
            if nv_works:
                recommend, reason = "cuda", (
                    "Detected an NVIDIA GPU with the proprietary driver active — "
                    "CUDA runs ~1.5–2× faster than Vulkan here.")
            elif has_nv:
                recommend, reason = "vulkan", (
                    "You have an NVIDIA GPU, but the proprietary driver/CUDA isn't "
                    "active (likely nouveau/NVK). Use Vulkan now; CUDA only pays "
                    "off after you install the proprietary driver.")
            else:
                recommend, reason = "vulkan", (
                    "Vulkan is the universal backend and runs on your GPU. CUDA is "
                    "NVIDIA-only and needs the proprietary driver.")
            self.backendAdvice.emit(json.dumps({
                "recommend": recommend,
                "reason": reason,
                "nvidia_works": nv_works,
                "has_nvidia": has_nv,
                "installed": self._has_llama_server(),
                "aur": self._aur_helper() or "",
            }))
        threading.Thread(target=work, daemon=True).start()

    def _has_gpu(self):
        try:
            s = json.loads(open(STATE_FILE).read())
            if (s.get("hardware") or {}).get("gpus"):
                return True
        except Exception:
            pass
        # Fallback: the daemon may have missed the GPU (profiled before the
        # driver was ready). Trust a working nvidia-smi as ground truth.
        return shutil.which("nvidia-smi") is not None

    def _ollama_unload_all(self):
        """Free the RAM Ollama holds via keep-alive by unloading every loaded
        model (keep_alive=0). Best-effort; blocks until Ollama releases it, so
        call it from a worker thread. Used to (a) make room for the Turbo
        llama-server and (b) return RAM to baseline on Force OFF."""
        try:
            with urllib.request.urlopen(OLLAMA + "/api/ps", timeout=2) as r:
                models = json.loads(r.read().decode()).get("models", [])
        except Exception:
            return
        for m in models:
            name = m.get("name") or m.get("model")
            if not name:
                continue
            try:
                body = json.dumps({"model": name, "keep_alive": 0}).encode()
                req = urllib.request.Request(
                    OLLAMA + "/api/generate", data=body,
                    headers={"Content-Type": "application/json"})
                urllib.request.urlopen(req, timeout=15).read()
            except Exception:
                pass

    def _start_turbo(self, model, spec=False):
        # Already serving this exact model + same spec mode AND the server is
        # still alive? Nothing to do. The poll() check matters: a dead Popen
        # object would otherwise make us think Turbo is up and never restart a
        # server that crashed.
        if (self._turbo_proc and self._turbo_proc.poll() is None
                and self._turbo_model == model
                and getattr(self, "_turbo_spec", False) == spec):
            return
        self._stop_turbo()
        self._turbo_spec = spec
        if not shutil.which("genesi-ai-turbo"):
            self.turboStatus.emit("genesi-ai-turbo not found")
            return
        # Pre-check the backend so we never hang ~3 min polling a server that
        # can't even start. If llama-server is missing, ask the UI to offer the
        # one-click install (genesi-llama-cpp) instead of failing silently.
        if not self._has_llama_server():
            self.turboNeedsInstall.emit(True)
            self.turboStatus.emit(
                "Turbo backend not installed — click “Install Backend”")
            return
        self._turbo_model = model
        gpu_hint = "" if self._has_gpu() else "   (no GPU: small gain)"
        ready_msg = ("Turbo active ⚡ speculative decoding" if spec
                     else "Turbo active ⚡ full GPU offload")
        self.turboStatus.emit("preparing Turbo…")

        def run():
            # Free the RAM Ollama holds via keep-alive BEFORE llama-server loads.
            # Turbo serves through llama-server, so Ollama doesn't need the model
            # resident meanwhile — and on low-RAM machines (e.g. a 6 GB VM) two
            # ~3 GB copies won't fit, which is exactly why Turbo "never came up":
            # llama-server OOM'd/swapped to death. Ollama reloads on demand once
            # Turbo is switched off. Done in this worker thread so the UI toggle
            # never freezes while Ollama releases the memory.
            if self._turbo_model != model:
                return
            self.turboStatus.emit("freeing Ollama's memory…")
            self._ollama_unload_all()
            if self._turbo_model != model:
                return
            self.turboStatus.emit("starting Turbo (loading the model)…")
            # Capture the serve subprocess's stderr so we can surface the REAL
            # reason it failed (bad arg, OOM, missing blob…), not a generic msg.
            try:
                self._turbo_log = tempfile.NamedTemporaryFile(
                    "w", delete=False, suffix=".log").name
                proc = subprocess.Popen(
                    ["genesi-ai-turbo", "serve", model] + (["--spec"] if spec else []),
                    stdout=subprocess.DEVNULL, stderr=open(self._turbo_log, "w"))
                self._turbo_proc = proc
            except Exception as e:
                self.turboStatus.emit("error starting Turbo: " + str(e))
                return
            log = self._turbo_log

            def _tail():
                try:
                    return "".join(open(log).readlines()[-2:]).strip()
                except Exception:
                    return ""

            # Up to ~15 min: an 8B on a CPU-only VM can take 5-8 min to load and
            # warm up (confirmed on a 6 GB VM). Real failures still surface in
            # seconds via the proc.poll() death-check below, so a long ceiling
            # only ever helps a genuine slow load — it never hides a crash.
            for i in range(900):
                if self._turbo_model != model:      # cancelled or model changed
                    return
                # Ready? Check health FIRST — `serve` may have reused an already
                # running Turbo and exited 0 right away (its helper proc is gone,
                # but the server is healthy). So health wins over a dead proc.
                try:
                    with urllib.request.urlopen(TURBO + "/health", timeout=2) as r:
                        if json.loads(r.read()).get("status") == "ok":
                            self._turbo = True
                            self.turboReady.emit(True)
                            self.turboStatus.emit(ready_msg + gpu_hint)
                            return
                except Exception:
                    pass
                # Helper process gone AND not serving → real failure; surface why.
                if proc.poll() is not None:
                    msg = _tail()
                    self.turboStatus.emit(
                        "Turbo failed: " + (msg.splitlines()[-1] if msg else
                        "run in a terminal: genesi-ai-turbo serve " + model))
                    return
                # live elapsed-time feedback so it never looks frozen
                secs = i + 1
                elapsed = f"{secs // 60}m{secs % 60:02d}s" if secs >= 60 else f"{secs}s"
                hint = "  ·  large models on CPU/VM take a few minutes" if secs > 25 else ""
                self.turboStatus.emit(f"loading the model… {elapsed}{hint}")
                time.sleep(1)
            self.turboStatus.emit(
                "Turbo took too long — run in a terminal to see the error: "
                "genesi-ai-turbo serve " + model)
        threading.Thread(target=run, daemon=True).start()

    @Slot()
    def recommendTurboModel(self):
        """Advisor → Turbo model pick: ask `genesi-ai-turbo recommend` for the
        biggest model that fits 100% in VRAM and hand the tag to the UI. Runs in
        a worker thread (it may probe the GPU via the Vulkan backend, ~seconds)."""
        def work():
            try:
                r = subprocess.run(["genesi-ai-turbo", "recommend"],
                                   capture_output=True, text=True, timeout=30)
                tag = (r.stdout or "").strip().splitlines()
                tag = tag[0].strip() if tag else ""
            except Exception:
                tag = ""
            self.turboRecommended.emit(tag)
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def installTurboBackend(self, kind="vulkan"):
        """One-click install of the Turbo backend.

        kind="vulkan" (default): genesi-llama-cpp — the PREBUILT Vulkan llama.cpp
        from the genesi repo (~tens of MB), via pkexec (graphical auth). Universal:
        runs on any GPU (AMD/Intel/NVIDIA, incl. nouveau/NVK).

        kind="cuda": llama.cpp-cuda from the AUR (a source build that pulls CUDA)
        via the user's AUR helper. ~1.5–2× faster, but NVIDIA + proprietary driver
        only, and a heavy build — best run on an INSTALLED system, not the RAM-
        backed live ISO. Best-effort: if no AUR helper is present we print the
        manual command instead of failing silently."""
        kind = "cuda" if str(kind).lower() == "cuda" else "vulkan"
        if self._has_llama_server():
            self.turboNeedsInstall.emit(False)
            self.turboStatus.emit("Backend already installed ✓ — turn on Turbo")
            return
        if kind == "cuda":
            self._install_cuda_backend()
            return
        if not shutil.which("pkexec"):
            self.turboStatus.emit(
                "pkexec missing — run: sudo pacman -S genesi-llama-cpp")
            return

        def work():
            self.turboStatus.emit(
                "installing genesi-llama-cpp (Vulkan)… (authorize in the dialog)")
            try:
                p = subprocess.run(
                    ["pkexec", "pacman", "-Sy", "--needed", "--noconfirm",
                     "genesi-llama-cpp"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=900)
            except Exception as e:
                self.turboStatus.emit("install failed: " + str(e))
                return
            if p.returncode == 0 and self._has_llama_server():
                self.turboNeedsInstall.emit(False)
                self.turboStatus.emit("Vulkan backend installed ✓ — turn Turbo on again")
            else:
                last = ""
                if p.stdout:
                    lines = [l for l in p.stdout.splitlines() if l.strip()]
                    last = lines[-1] if lines else ""
                self.turboStatus.emit("install not completed — " + last)
        threading.Thread(target=work, daemon=True).start()

    def _install_cuda_backend(self):
        """Build/install llama.cpp-cuda from the AUR via the user's AUR helper.
        Heavy (pulls CUDA + base-devel) and NVIDIA-only — opt-in. Surfaces a clear
        manual command when no helper exists."""
        helper = self._aur_helper()
        if not helper:
            self.turboStatus.emit(
                "CUDA needs an AUR helper (paru/yay). Install paru and "
                "run: paru -S llama.cpp-cuda")
            return
        if not self._nvidia_smi_works():
            self.turboStatus.emit(
                "Warning: nvidia-smi isn't responding — CUDA only runs with the "
                "proprietary NVIDIA driver active. Installing anyway…")

        def work():
            self.turboStatus.emit(
                f"building llama.cpp-cuda via {helper}… (heavy, may take a while)")
            try:
                p = subprocess.run(
                    [helper, "-S", "--needed", "--noconfirm", "llama.cpp-cuda"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=3600)
            except Exception as e:
                self.turboStatus.emit("CUDA install failed: " + str(e))
                return
            if p.returncode == 0 and self._has_llama_server():
                self.turboNeedsInstall.emit(False)
                self.turboStatus.emit("CUDA backend installed ✓ — turn Turbo on again")
            else:
                last = ""
                if p.stdout:
                    lines = [l for l in p.stdout.splitlines() if l.strip()]
                    last = lines[-1] if lines else ""
                self.turboStatus.emit("CUDA not completed — " + last
                                      + "  (try in a terminal: " + helper
                                      + " -S llama.cpp-cuda)")
        threading.Thread(target=work, daemon=True).start()

    @Slot(str)
    def pullModel(self, name):
        """Download a model via Ollama /api/pull (streamed), reporting progress —
        so the user never has to drop to a terminal."""
        name = (name or "").strip()
        if not name:
            return

        def work():
            if not self._ensure_ollama():
                self.pullStatus.emit(
                    "error: Ollama isn't running and I couldn't start it "
                    "(try in a terminal: systemctl start ollama)")
                self.pullDone.emit(False)
                return
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
                            self.pullStatus.emit("error: " + o["error"])
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
                self.pullStatus.emit(f"{name} downloaded")
                self.pullDone.emit(True)
            except Exception as e:
                self.pullStatus.emit("error: " + str(e))
                self.pullDone.emit(False)
        threading.Thread(target=work, daemon=True).start()

    @staticmethod
    def _stats(obj):
        # All durations from Ollama are in nanoseconds.
        ec = obj.get("eval_count") or 0
        ed = obj.get("eval_duration") or 0
        pc = obj.get("prompt_eval_count") or 0
        pd = obj.get("prompt_eval_duration") or 0
        ld = obj.get("load_duration") or 0
        total = obj.get("total_duration") or 0
        if not ec:
            return ""
        rate = ec / (ed / 1e9) if ed else 0
        return json.dumps({
            "mode": "ollama",
            "rate": round(rate, 1),
            "eval": ec,
            "prompt": pc,
            "gen_s": round(ed / 1e9, 2),
            "prompt_s": round(pd / 1e9, 2),
            "load_s": round(ld / 1e9, 2),
            "total_s": round(total / 1e9, 2),
        })


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
