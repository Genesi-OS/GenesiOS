#!/usr/bin/env python3
"""Always-ready, approval-only Genesi AI Quick Chat."""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

from PySide6.QtCore import QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

import genesi_island_link as link
import genesi_turbo_ctl as turbo_ctl
# _turbo_base() rather than a constant: on a machine with no GPU, Turbo
# often runs on a mesh peer, and it has to be asked WHERE it is at the
# moment of use. The constant this used to import was renamed to
# LOCAL_TURBO when that landed, and Quick Chat was not updated with it —
# so it has been dying on the import ever since, on every login.
from genesi_ai_monitor import Backend, OLLAMA, _turbo_base


APP_ID = "org.genesi.aiquick"
SOCKET_NAME = "genesi-ai-quick.sock"
# What the Quick Chat is doing, for the AI island at the top of the screen
# (genesi-caelestia-shell's GenesiAiIsland). One writer -- this process --
# and the shell only reads it.
ISLAND_NAME = "genesi-ai-island.json"

# Attachments: how much of a dropped file is handed to the model. A local
# model with an 8k context would drown in a whole book, so the text is cut
# per file and in total, and the model is told that it was cut.
ATTACH_FILE_CHARS = 24_000
ATTACH_TOTAL_CHARS = 48_000
TEXT_SUFFIXES = {
    ".txt", ".md", ".csv", ".tsv", ".json", ".yaml", ".yml", ".toml", ".ini",
    ".conf", ".cfg", ".log", ".xml", ".html", ".htm", ".css", ".js", ".ts",
    ".tsx", ".jsx", ".py", ".rs", ".go", ".c", ".h", ".cpp", ".hpp", ".java",
    ".kt", ".rb", ".php", ".sh", ".fish", ".zsh", ".sql", ".lua", ".qml",
    ".srt", ".tex", ".rst", ".env", ".gitignore",
}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg", ".heic"}


# The paths and the socket are the island's contract too, so they live in
# genesi_island_link, which the islands import without pulling in all of this.
runtime_dir = link.runtime_dir
socket_path = link.socket_path
island_path = link.state_path
send_to_running = link.send


def start_island():
    """The island on every desktop but caelestia's (which draws its own):
    started beside the chat, and it goes away by itself when switched off.
    Started more than once is harmless -- a second one sees the first and
    leaves."""
    if link.caelestia_session() or not link.enabled() or link.standalone_running():
        return
    command = shutil.which("genesi-ai-island")
    if command:
        command_line = [command]
    else:
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "genesi_ai_island.py")
        if not os.path.isfile(script):
            return
        command_line = [sys.executable, script]
    try:
        subprocess.Popen(command_line, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def read_clipboard():
    """What is on the clipboard, as text, from outside a focused window --
    which is where the chat is when the island asks. Wayland only lets a
    focused window read it through Qt, so wl-paste first; X11 tools after."""
    tools = []
    if os.environ.get("WAYLAND_DISPLAY"):
        tools.append(["wl-paste", "--no-newline", "--type", "text"])
    tools += [["xclip", "-o", "-selection", "clipboard"], ["xsel", "--clipboard", "--output"]]
    for argv in tools:
        if not shutil.which(argv[0]):
            continue
        try:
            done = subprocess.run(argv, capture_output=True, timeout=2)
        except (OSError, subprocess.SubprocessError):
            continue
        if done.returncode == 0 and done.stdout:
            return done.stdout.decode("utf-8", "replace")
    try:
        return QGuiApplication.clipboard().text() or ""
    except Exception:
        return ""


def parse_command(raw):
    """A socket message: the old bare words ("show", "toggle") or, for
    everything the island sends, one JSON object with a "cmd"."""
    raw = (raw or "").strip()
    if raw.startswith("{"):
        try:
            message = json.loads(raw)
            if isinstance(message, dict) and isinstance(message.get("cmd"), str):
                return message
        except ValueError:
            pass
        return {"cmd": "toggle"}
    return {"cmd": "show" if raw == "show" else "toggle"}


CLIP_LIMIT = 12_000
# wl-paste --watch runs this on every clipboard change; each copy reaches us
# on its stdout, ended by an ASCII record separator (0x1e).
CLIP_SEPARATOR = b"\x1e"
CLIP_WATCH = ["wl-paste", "--type", "text", "--watch", "sh", "-c", "cat; printf '\\036'"]


def clip_prompt(question, clip):
    """A question about the clipboard, as the model gets it."""
    clip = (clip or "").strip()
    if len(clip) > CLIP_LIMIT:
        clip = clip[:CLIP_LIMIT] + "\n[... cut here: the copied text goes on]"
    return "%s\n\nThe text I copied:\n```\n%s\n```" % (question.strip(), clip)


def split_clips(buf):
    """(complete copies, what is left over) from wl-paste --watch's output."""
    parts = buf.split(CLIP_SEPARATOR)
    return parts[:-1], parts[-1]


def _pdf_text(path):
    """A PDF's text: poppler's pdftotext when it is there, Qt's own PDF module
    when it is not. Empty when neither can read it -- a scanned PDF is
    pictures, and there is no text in it to read."""
    if shutil.which("pdftotext"):
        try:
            done = subprocess.run(["pdftotext", "-layout", "-l", "60", path, "-"],
                                  capture_output=True, timeout=30)
            if done.returncode == 0:
                return done.stdout.decode("utf-8", "replace")
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        from PySide6.QtPdf import QPdfDocument
    except ImportError:
        return None
    doc = QPdfDocument()
    if doc.load(path) != QPdfDocument.Error.None_:
        return ""
    return "\n\n".join(doc.getAllText(i).text() for i in range(min(doc.pageCount(), 60)))


def read_attachment(path):
    """(info, text) for a file the person attached. info is what the window
    shows; text is what the model will be given, or "" when there is none."""
    name = os.path.basename(path)
    info = {"name": name, "path": path, "kind": "file", "chars": 0, "size": 0, "error": ""}
    if not os.path.isfile(path):
        info["error"] = "not-found"
        return info, ""
    info["size"] = os.path.getsize(path)
    suffix = os.path.splitext(name)[1].lower()
    text = ""
    if suffix == ".pdf":
        info["kind"] = "pdf"
        got = _pdf_text(path)
        if got is None:
            info["error"] = "no-pdf-reader"
        else:
            text = got
            if not text.strip():
                info["error"] = "no-text"
    elif suffix in IMAGE_SUFFIXES:
        info["kind"] = "image"
        info["error"] = "image"
    else:
        try:
            with open(path, "rb") as handle:
                data = handle.read(ATTACH_FILE_CHARS * 4)
        except OSError:
            info["error"] = "unreadable"
            return info, ""
        if b"\0" in data[:65536] and suffix not in TEXT_SUFFIXES:
            info["kind"] = "binary"
            info["error"] = "binary"
        else:
            info["kind"] = "text"
            text = data.decode("utf-8", "replace")
    if len(text) > ATTACH_FILE_CHARS:
        text = text[:ATTACH_FILE_CHARS] + "\n[... cut here: the file goes on]"
    info["chars"] = len(text)
    return info, text


def attachment_context(entries):
    """The block put in front of the person's message: each file's name,
    where it is, and its text -- or why there is no text."""
    parts = ["The user attached these files to the message below."]
    left = ATTACH_TOTAL_CHARS
    for info, text in entries:
        head = "### %s (%s)" % (info["name"], info["path"])
        if not text:
            why = {"image": "an image -- its pixels are not readable here, only its path",
                   "no-text": "a PDF with no text layer (scanned pages)",
                   "no-pdf-reader": "a PDF, and no PDF reader is installed",
                   "binary": "a binary file"}.get(info.get("error"), "not readable")
            parts.append(head + "\n(%s)" % why)
            continue
        piece = text[:max(0, left)]
        left -= len(piece)
        if len(piece) < len(text):
            piece += "\n[... cut here: too much text in total]"
        parts.append(head + "\n```\n" + piece + "\n```")
    return "\n\n".join(parts)


class QuickBackend(Backend):
    toggleRequested = Signal()
    showRequested = Signal()
    hideRequested = Signal()
    modelChanged = Signal(str)
    # From the AI island, through the socket.
    islandApproval = Signal(str, bool)      # request id, approved
    islandStop = Signal()
    attachRequested = Signal(str, str)      # path, a prompt to send with it ("" = none)
    askRequested = Signal(str, bool)        # a question asked on the island; with the clipboard?
    settingRequested = Signal(str, str)     # an island setting changed (key, value)
    clipHint = Signal(str, str)             # Smart Copy: kind ("error"/"text"), preview
    paletteChanged = Signal(str)            # the theme's colours, as JSON

    def __init__(self):
        super().__init__()
        self._quick_model = ""
        self._socket = None
        self._attached = {}
        self._clip_watch = None
        self._clip_seen = ""
        self._copied_last = ""
        self._scheme_mtime = self._scheme_stamp()
        # Model/service discovery may need to wake Ollama. Keep it off the GUI
        # thread so Ctrl+Alt+Space can paint immediately after login.
        threading.Thread(target=self._prepare_model, daemon=True).start()

    @Slot(result=str)
    def quickModel(self):
        return self._quick_model

    # ── When the compositor hands back a window we did not ask for ──────────
    #
    # The Quick Chat tells Qt one legal size, which Qt forwards as the
    # xdg_toplevel minimum AND maximum. Hyprland honours that for a FLOATING
    # window and ignores it for a tiled one: tiled, the window is the size of
    # the workspace, the card stretches across the screen and the rest of the
    # surface is transparent -- which Hyprland then blurs, so what a person
    # sees is a bar across the top of a huge frosted rectangle.
    #
    # Three windowrules are supposed to prevent that. They live in Genesi's
    # hyprland.conf, are re-applied at login by genesi_ai_quick_shortcuts, and
    # they still only reach a window if that config is the one in use and the
    # rule matched the app_id the window actually mapped with. A rule that
    # silently did not match is exactly what this looks like, and the report
    # ("it goes full screen when the AI asks to run something") is the one
    # thing we can act on without knowing which of the two it was.
    #
    # So the window checks what it got. If the compositor gave it a size it
    # never asked for, it asks Hyprland -- by class, the same one the rules
    # name -- to float, resize and centre it. Best-effort and quiet: no
    # Hyprland, no problem, and an error here must never take the chat down.
    @Slot(int, int, float)
    def fitWindow(self, width, height, ratio):
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return
        ratio = ratio if ratio and ratio > 0 else 1.0
        # Hyprland speaks physical pixels; Qt's geometry is logical.
        w = max(1, int(round(width * ratio)))
        h = max(1, int(round(height * ratio)))
        match = "class:^(%s)$" % APP_ID.replace(".", r"\.")
        for args in (["setfloating", match],
                     ["resizewindowpixel", "exact %d %d,%s" % (w, h, match)],
                     ["centerwindow", match],
                     ["pin", match]):
            try:
                subprocess.run(["hyprctl", "dispatch"] + args,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=2)
            except Exception:
                return
        sys.stderr.write(
            "genesi-ai-quick: the compositor sized this window itself; "
            "asked Hyprland to float it at %dx%d\n" % (w, h))

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
            with urllib.request.urlopen(_turbo_base() + "/health", timeout=0.8) as response:
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
                    with urllib.request.urlopen(_turbo_base() + "/v1/models", timeout=2) as response:
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
        # No hosted fallback here any more. A provider used to be slipped in
        # when no local model existed; now "local or API" is a switch the
        # person sets, and a local answer quietly coming from a paid API would
        # be exactly the mixing of the two that switch exists to prevent.
        self.turboReady.emit(self._turbo)
        if model != self._quick_model:
            self._quick_model = model
            self.modelChanged.emit(model)

    # ── The AI island ────────────────────────────────────────────────────────
    #
    # The window says what it is doing; this writes it where the shell reads
    # it. Atomic (a temporary file renamed over the old one), so the island
    # never reads half a state.
    @Slot(str)
    def publishIsland(self, payload):
        try:
            state = json.loads(payload)
        except ValueError:
            return
        state["pid"] = os.getpid()
        state["t"] = int(time.time() * 1000)
        target = island_path()
        try:
            fd, tmp = tempfile.mkstemp(prefix=".genesi-ai-island.", dir=os.path.dirname(target))
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(state, handle, ensure_ascii=False)
            os.replace(tmp, target)
        except OSError:
            pass

    def clearIsland(self):
        try:
            os.unlink(island_path())
        except OSError:
            pass

    @Slot(result=bool)
    def islandShowsApprovals(self):
        """True when an AI island is on screen to show an approval -- and an
        answer asked from it -- so the chat window does not have to jump open
        over whatever the person is doing. caelestia's when it is switched
        on in a caelestia session; the standalone one when it is running."""
        if not link.enabled():
            return False
        return link.caelestia_session() or link.standalone_running()

    # ── The island's settings ───────────────────────────────────────────────
    @Slot(result=str)
    def islandPrefs(self):
        prefs = link.read_prefs()
        prefs["enabled"] = link.enabled()
        prefs["caelestia"] = link.caelestia_session()
        return json.dumps(prefs)

    @Slot(str, str, result=str)
    def setIslandPref(self, key, value):
        """One island setting, from the chat's settings or from the island's
        own menu. Files first, so every island sees it on its next read."""
        parsed = link.parse_setting(key, value)
        if parsed:
            key, value = parsed
            try:
                if key == "enabled":
                    link.set_enabled(value)
                    if value:
                        start_island()
                elif key in ("mode", "smartClip"):
                    link.write_prefs(**{key: value})
            except OSError:
                pass
            if key == "smartClip":
                self.setSmartClip(value)
        return self.islandPrefs()

    # ── The clipboard ────────────────────────────────────────────────────────
    @Slot(result=str)
    def clipboardText(self):
        return read_clipboard()

    @Slot(str, str, result=str)
    def clipPrompt(self, question, clip):
        return clip_prompt(question, clip)

    @Slot(str)
    def copyText(self, text):
        # Remembered, so Smart Copy does not offer help with our own answer.
        self._copied_last = text
        try:
            if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
                subprocess.run(["wl-copy"], input=text.encode("utf-8"), timeout=3)
                return
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            QGuiApplication.clipboard().setText(text)
        except Exception:
            pass

    # Smart Copy: off unless switched on. When on, every new clipboard is
    # looked at HERE, on this machine, and only an error or a long text makes
    # the island offer something; nothing is sent until the person clicks.
    @Slot(bool)
    def setSmartClip(self, on):
        if on:
            self._start_clip_watch()
        else:
            self._stop_clip_watch()

    def _clip_changed(self, text):
        text = text or ""
        if text == self._clip_seen or text == self._copied_last:
            return
        self._clip_seen = text
        found = link.classify_clip(text)
        if found:
            self.clipHint.emit(found[0], found[1])

    def _start_clip_watch(self):
        if self._clip_watch is not None:
            return
        if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
            try:
                proc = subprocess.Popen(CLIP_WATCH, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            except OSError:
                proc = None
            if proc is not None:
                self._clip_watch = proc

                def pump():
                    buf = b""
                    first = True
                    while True:
                        chunk = proc.stdout.read1(65536)
                        if not chunk:
                            return
                        done, buf = split_clips(buf + chunk)
                        for item in done:
                            text = item.decode("utf-8", "replace")
                            if first:
                                # What was already copied when the watch
                                # started is not something just copied.
                                first = False
                                self._clip_seen = text
                                continue
                            self._clip_changed(text)
                        if len(buf) > 400_000:
                            buf = b""

                threading.Thread(target=pump, daemon=True).start()
                return
        # X11 (and XWayland): Qt hears the clipboard change without focus.
        try:
            clipboard = QGuiApplication.clipboard()
            self._clip_seen = clipboard.text() or ""
            handler = lambda: self._clip_changed(clipboard.text())
            clipboard.dataChanged.connect(handler)
            self._clip_watch = ("qt", clipboard, handler)
        except Exception:
            self._clip_watch = None

    def _stop_clip_watch(self):
        watch, self._clip_watch = self._clip_watch, None
        if watch is None:
            return
        if isinstance(watch, tuple):
            try:
                watch[1].dataChanged.disconnect(watch[2])
            except Exception:
                pass
            return
        try:
            watch.terminate()
        except OSError:
            pass

    # ── The theme, live ──────────────────────────────────────────────────────
    @staticmethod
    def _scheme_stamp():
        try:
            from genesi_palette import SCHEME, CENTER_SETTINGS
            return tuple(os.path.getmtime(p) if os.path.exists(p) else 0 for p in (SCHEME, CENTER_SETTINGS))
        except Exception:
            return ()

    @Slot()
    def checkPalette(self):
        stamp = self._scheme_stamp()
        if stamp == self._scheme_mtime:
            return
        self._scheme_mtime = stamp
        try:
            from genesi_palette import resolve
            colours, _following = resolve()
        except Exception:
            return
        self.paletteChanged.emit(json.dumps(colours))

    # ── Attachments ──────────────────────────────────────────────────────────
    @Slot(str, result=str)
    def attachFile(self, source):
        path = QUrl(source).toLocalFile() if source.startswith("file:") else source
        info, text = read_attachment(path)
        # Even a file with no readable text goes along by name and path: the
        # agent can still open, move or convert it.
        if info["error"] not in ("not-found", "unreadable"):
            self._attached[path] = (info, text)
        return json.dumps(info, ensure_ascii=False)

    @Slot(str)
    def detachFile(self, path):
        self._attached.pop(path, None)

    @Slot(str, result=str)
    def attachmentContext(self, paths_json):
        try:
            paths = json.loads(paths_json)
        except ValueError:
            return ""
        entries = [self._attached[p] for p in paths if p in self._attached]
        for p in paths:
            self._attached.pop(p, None)
        return attachment_context(entries) if entries else ""

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
                        connection.settimeout(1)
                        chunks = []
                        while sum(len(c) for c in chunks) < 65536:
                            chunk = connection.recv(4096)
                            if not chunk:
                                break
                            chunks.append(chunk)
                    self.dispatch(parse_command(b"".join(chunks).decode("utf-8", "replace")))
                except OSError:
                    return

        threading.Thread(target=serve, daemon=True).start()

    def dispatch(self, message):
        cmd = message.get("cmd")
        if cmd == "show":
            self.showRequested.emit()
        elif cmd == "hide":
            self.hideRequested.emit()
        elif cmd in ("approve", "deny"):
            self.islandApproval.emit(str(message.get("id", "")), cmd == "approve")
        elif cmd == "stop":
            self.islandStop.emit()
        elif cmd == "attach" and message.get("path"):
            self.attachRequested.emit(str(message["path"]), str(message.get("prompt") or ""))
        elif cmd == "ask":
            if str(message.get("text") or "").strip():
                self.askRequested.emit(str(message["text"]), bool(message.get("clip")))
        elif cmd == "set":
            if message.get("key"):
                self.settingRequested.emit(str(message["key"]), str(message.get("value", "")))
        else:
            self.toggleRequested.emit()

    def closeSocket(self):
        self._stop_clip_watch()
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
    # What the AI island asks for.
    parser.add_argument("--hide", action="store_true")
    parser.add_argument("--approve", metavar="ID")
    parser.add_argument("--deny", metavar="ID")
    parser.add_argument("--stop", action="store_true")
    parser.add_argument("--attach", metavar="PATH")
    parser.add_argument("--prompt", default="", help="with --attach: send this right away")
    # Asked from an island, or from caelestia's launcher (>ai ...).
    parser.add_argument("--ask", metavar="TEXT", help="ask without opening the chat window")
    parser.add_argument("--clip", action="store_true", help="with --ask: about what is on the clipboard")
    parser.add_argument("--set", metavar="KEY=VALUE",
                        help="an island setting: mode=always|quickchat, smartClip=on|off, "
                             "actions=approval|automatic, enabled=on|off")
    args = parser.parse_args()

    if args.set:
        key, _, value = args.set.partition("=")
        parsed = link.parse_setting(key.strip(), value)
        if not parsed:
            sys.stderr.write("genesi-ai-quick: unknown setting %r\n" % args.set)
            return 2
        key, value = parsed
        # The files first: the islands read them whether or not a chat runs.
        try:
            if key == "enabled":
                link.set_enabled(value)
            elif key in ("mode", "smartClip"):
                link.write_prefs(**{key: value})
        except OSError as error:
            sys.stderr.write("genesi-ai-quick: %s\n" % error)
            return 1
        wire = "on" if value is True else "off" if value is False else value
        if not send_to_running(json.dumps({"cmd": "set", "key": key, "value": wire})) and key == "enabled" and value:
            start_island()
        return 0

    if args.ask:
        message = {"cmd": "ask", "text": args.ask, "clip": bool(args.clip)}
    elif args.approve or args.deny:
        message = {"cmd": "approve" if args.approve else "deny", "id": args.approve or args.deny}
    elif args.stop:
        message = {"cmd": "stop"}
    elif args.hide:
        message = {"cmd": "hide"}
    elif args.attach:
        message = {"cmd": "attach", "path": os.path.abspath(args.attach), "prompt": args.prompt}
    else:
        message = {"cmd": "toggle" if args.toggle else "show"}
    command = message["cmd"] if message["cmd"] in ("show", "toggle") else json.dumps(message)
    if send_to_running(command):
        return 0
    # Nobody running: an answer to a question nobody asked has nowhere to go,
    # but a file someone dropped on the island should open the chat with it.
    if message["cmd"] in ("approve", "deny", "stop", "hide"):
        return 0
    # An island is where an answer to --ask shows; start it with the chat.
    start_island()

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
    # The theme's colours, and again whenever they change: the chat follows
    # the desktop's scheme the way the island beside it does.
    try:
        from genesi_palette import install as install_palette, qpalette
        install_palette(app, engine)

        def repaint(payload):
            colours = json.loads(payload)
            engine.rootContext().setContextProperty("genesiPalette", colours)
            try:
                app.setPalette(qpalette(colours))
            except Exception:
                pass
        backend.paletteChanged.connect(repaint)
    except Exception:
        pass
    here = os.path.dirname(os.path.abspath(__file__))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "QuickChat.qml")))
    if not engine.rootObjects():
        backend.closeSocket()
        return 1
    root = engine.rootObjects()[0]
    backend.toggleRequested.connect(root.toggleQuick)
    backend.showRequested.connect(root.showQuick)
    backend.hideRequested.connect(root.hideQuick)
    backend.islandApproval.connect(root.islandAnswer)
    backend.islandStop.connect(root.stopWork)
    backend.attachRequested.connect(root.attachAndShow)
    backend.askRequested.connect(root.askFromIsland)
    backend.settingRequested.connect(root.islandSetting)
    backend.clipHint.connect(root.showClipHint)
    if link.read_prefs().get("smartClip"):
        backend.setSmartClip(True)
    palette_timer = QTimer()
    palette_timer.setInterval(3000)
    palette_timer.timeout.connect(backend.checkPalette)
    palette_timer.start()
    app.aboutToQuit.connect(backend.closeSocket)
    app.aboutToQuit.connect(backend.clearIsland)
    app.aboutToQuit.connect(backend.stopChat)

    # Pick up an update without a logout.
    #
    # Quick Chat is a service started at login and left running, so an update
    # installed afterwards reached everything EXCEPT it: after the release
    # that added a voice setting and hosted models to Quick Chat, the Monitor
    # had both and Quick Chat -- the same package, still running the code it
    # started with -- had neither. It looked like the change had not shipped.
    #
    # So once a minute it compares the files it runs against the moment it
    # started, and when one is newer and the window is not in use, it becomes
    # a fresh copy of itself: same arguments, same PID, no systemd involved.
    started = time.time()
    watched = [os.path.join(here, f) for f in
               ("genesi_ai_quick.py", "genesi_ai_monitor.py", "QuickChat.qml",
                "genesi_turbo_ctl.py", "genesi_island_link.py")]
    watched.append("/usr/share/genesi-ai-mode/genesi_ai_assist.py")

    def updated():
        for path in watched:
            try:
                if os.path.getmtime(path) > started:
                    return True
            except OSError:
                pass
        return False

    def maybe_reload():
        if not updated() or root.property("visible"):
            return
        backend.closeSocket()
        argv = [a for a in sys.argv if a != "--background"] + ["--background"]
        try:
            os.execv(sys.executable, [sys.executable] + argv)
        except OSError:
            pass

    reload_timer = QTimer()
    reload_timer.setInterval(60_000)
    reload_timer.timeout.connect(maybe_reload)
    reload_timer.start()

    if message["cmd"] == "attach":
        root.attachAndShow(message["path"], message.get("prompt") or "")
    elif message["cmd"] == "ask":
        root.askFromIsland(message["text"], message.get("clip", False))
    elif not args.background:
        root.showQuick()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
