#!/usr/bin/env python3
"""
ai-island-bridge-test.py -- the Quick Chat's side of the AI island.

The island (genesi-caelestia-shell's GenesiAiIsland) only READS a state file
the Quick Chat writes, and answers by running `genesi-ai-quick --approve ID`
and friends, which reach the running chat over its socket. ci/plugins-test.py
plays the island's card; this plays the chat's half:

  * every command the island sends is understood, and the old bare words
    ("show", "toggle") still are -- the hotkey sends those;
  * the CLI turns into the right message and reaches a listening chat;
  * the state file is written whole (atomically), stamped with the pid the
    island checks to tell a live chat from a crashed one;
  * a dropped file becomes text the model can read, cut to size, and a file
    with no text still goes along by name;
  * a question asked ON the island (--ask, --clip) and a setting changed
    there (--set) reach the chat, and settings land in the shared file every
    island reads.
"""
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
# Qt on Windows ships no fonts offscreen, and a PDF written with no font has
# no text in it to read back.
if sys.platform == "win32":
    os.environ.setdefault("QT_QPA_FONTDIR", "C:/Windows/Fonts")
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
MON = os.path.normpath(os.path.join(HERE, "..", "packages", "genesi-ai-mode", "monitor"))
sys.path.insert(0, MON)

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== AI island bridge ==")
tmp = tempfile.mkdtemp(prefix="island-")
os.environ["XDG_RUNTIME_DIR"] = tmp

spec = importlib.util.spec_from_file_location("genesi_ai_quick", os.path.join(MON, "genesi_ai_quick.py"))
quick = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quick)

# ── Commands ────────────────────────────────────────────────────────────────
pc = quick.parse_command
check("the hotkey's bare words still work", pc("show") == {"cmd": "show"} and pc("toggle") == {"cmd": "toggle"})
check("an island command is JSON with a cmd",
      pc('{"cmd": "approve", "id": "r1"}') == {"cmd": "approve", "id": "r1"})
check("garbage is a toggle, never a crash", pc("{nope") == {"cmd": "toggle"} and pc('{"x": 1}') == {"cmd": "toggle"})


class Emitter:
    def __init__(self):
        self.calls = []

    def emit(self, *args):
        self.calls.append(args)


class FakeBackend:
    def __init__(self):
        for name in ("showRequested", "hideRequested", "toggleRequested", "islandApproval",
                     "islandStop", "attachRequested", "askRequested", "settingRequested"):
            setattr(self, name, Emitter())
        self._socket = None

    dispatch = quick.QuickBackend.dispatch


fb = FakeBackend()
fb.dispatch({"cmd": "approve", "id": "req-9"})
fb.dispatch({"cmd": "deny", "id": "req-9"})
fb.dispatch({"cmd": "stop"})
fb.dispatch({"cmd": "hide"})
fb.dispatch({"cmd": "attach", "path": "/tmp/a.pdf", "prompt": "Resuma"})
fb.dispatch({"cmd": "attach"})
check("approve and deny carry the request id",
      fb.islandApproval.calls == [("req-9", True), ("req-9", False)], fb.islandApproval.calls)
check("stop and hide reach the window", len(fb.islandStop.calls) == 1 and len(fb.hideRequested.calls) == 1)
check("attach carries the path and the request; an attach with no path is a toggle",
      fb.attachRequested.calls == [("/tmp/a.pdf", "Resuma")] and len(fb.toggleRequested.calls) == 1,
      (fb.attachRequested.calls, fb.toggleRequested.calls))
fb.dispatch({"cmd": "ask", "text": "quanto de RAM?", "clip": True})
fb.dispatch({"cmd": "ask", "text": "   "})
fb.dispatch({"cmd": "set", "key": "smartClip", "value": "on"})
fb.dispatch({"cmd": "set"})
check("a question asked on the island reaches the chat, with or without the clipboard",
      fb.askRequested.calls == [("quanto de RAM?", True)], fb.askRequested.calls)
check("an empty question or setting does nothing -- it does not toggle the window either",
      fb.settingRequested.calls == [("smartClip", "on")] and len(fb.toggleRequested.calls) == 1,
      (fb.settingRequested.calls, fb.toggleRequested.calls))

# ── Asking about the clipboard ──────────────────────────────────────────────
prompt = quick.clip_prompt("Explique isto.", "KeyError: 'id'\n")
check("a clipboard question carries the question and the copied text, fenced",
      prompt.startswith("Explique isto.") and "```\nKeyError: 'id'\n```" in prompt, prompt)
check("a huge clipboard is cut, and says so",
      "cut here" in quick.clip_prompt("q", "z" * (quick.CLIP_LIMIT * 2)))
done, rest = quick.split_clips(b"first\x1esecond\x1epart")
check("Smart Copy splits wl-paste's stream into whole copies",
      done == [b"first", b"second"] and rest == b"part", (done, rest))
check("the CLI and the islands share one socket path", quick.socket_path() == quick.link.socket_path())

# ── The CLI reaches a running chat ──────────────────────────────────────────
if hasattr(socket, "AF_UNIX") and sys.platform != "win32":
    live = FakeBackend()
    quick.QuickBackend.listen(live)
    script = os.path.join(MON, "genesi_ai_quick.py")
    cfg = os.path.join(tmp, "config")
    env = dict(os.environ, XDG_CONFIG_HOME=cfg)
    for argv in (["--approve", "abc"], ["--stop"], ["--attach", "rel/file.txt", "--prompt", "oi"],
                 ["--ask", "o que é isso?", "--clip"], ["--set", "mode=quickchat"], ["--toggle"]):
        done = subprocess.run([sys.executable, script] + argv, capture_output=True, timeout=30,
                              env=env)
        check(f"`genesi-ai-quick {' '.join(argv)}` exits at once when a chat is running",
              done.returncode == 0, done.stderr.decode()[-400:])
    deadline = time.time() + 3
    while time.time() < deadline and not live.toggleRequested.calls:
        time.sleep(0.05)
    check("...and the chat got each of them",
          live.islandApproval.calls == [("abc", True)] and len(live.islandStop.calls) == 1
          and len(live.attachRequested.calls) == 1 and len(live.toggleRequested.calls) == 1,
          (live.islandApproval.calls, live.islandStop.calls, live.attachRequested.calls))
    check("--ask carries the question and --clip",
          live.askRequested.calls == [("o que é isso?", True)], live.askRequested.calls)
    check("--set reaches the chat AND lands in the shared file every island reads",
          live.settingRequested.calls == [("mode", "quickchat")]
          and json.load(io.open(os.path.join(cfg, "genesi", "ai-island.json"), encoding="utf-8"))["mode"] == "quickchat",
          live.settingRequested.calls)
    bad = subprocess.run([sys.executable, script, "--set", "mode=sideways"], capture_output=True, timeout=30, env=env)
    check("a setting nobody knows is refused, not written", bad.returncode == 2)
    check("an attached path is made absolute before it travels",
          live.attachRequested.calls and os.path.isabs(live.attachRequested.calls[0][0])
          and live.attachRequested.calls[0][1] == "oi")
    live._socket.close()
    os.unlink(quick.socket_path())
    done = subprocess.run([sys.executable, script, "--approve", "x"], capture_output=True, timeout=30)
    check("an answer with no chat running exits quietly instead of starting one", done.returncode == 0)
else:
    print("  skip the socket round trip: no AF_UNIX here")

# ── The state file ──────────────────────────────────────────────────────────
quick.QuickBackend.publishIsland(None, json.dumps({"v": 1, "phase": "running", "steps": [{"title": "Run"}]}))
st = json.load(io.open(quick.island_path(), encoding="utf-8"))
check("the state is written where the island reads it, with pid and time",
      st["phase"] == "running" and st["pid"] == os.getpid() and st["t"] > 0)
check("...atomically: no temporary file is left beside it",
      [n for n in os.listdir(tmp) if n.startswith(".genesi-ai-island.")] == [])
quick.QuickBackend.publishIsland(None, "not json")
check("a broken payload leaves the last good state alone",
      json.load(io.open(quick.island_path(), encoding="utf-8"))["phase"] == "running")
quick.QuickBackend.clearIsland(None)
check("quitting removes it, so the island knows the chat is gone", not os.path.exists(quick.island_path()))

# ── Attachments ─────────────────────────────────────────────────────────────
text_file = os.path.join(tmp, "notas.md")
io.open(text_file, "w", encoding="utf-8").write("# Orçamento\nTotal: R$ 1.240\n")
info, text = quick.read_attachment(text_file)
check("a text file is read", info["kind"] == "text" and "R$ 1.240" in text and not info["error"], info)

big = os.path.join(tmp, "big.log")
io.open(big, "w", encoding="utf-8").write("x" * (quick.ATTACH_FILE_CHARS * 2))
info, text = quick.read_attachment(big)
check("a huge file is cut, and says so", len(text) < quick.ATTACH_FILE_CHARS + 100 and "cut here" in text)

binary = os.path.join(tmp, "blob.bin")
open(binary, "wb").write(b"\x00\x01\x02" * 100)
info, text = quick.read_attachment(binary)
check("a binary file is not fed to the model as text", info["error"] == "binary" and text == "")

image = os.path.join(tmp, "foto.png")
open(image, "wb").write(b"\x89PNG\r\n\x1a\n" + b"\x00" * 20)
info, text = quick.read_attachment(image)
check("an image goes by its path", info["kind"] == "image" and text == "")

missing = quick.read_attachment(os.path.join(tmp, "nope.txt"))[0]
check("a file that is not there says so", missing["error"] == "not-found")

try:
    from PySide6.QtGui import QGuiApplication, QPdfWriter, QPainter, QPageSize
    from PySide6.QtCore import QMarginsF
    app = QGuiApplication.instance() or QGuiApplication(sys.argv)
    pdf = os.path.join(tmp, "quote.pdf")
    writer = QPdfWriter(pdf)
    writer.setPageSize(QPageSize(QPageSize.A4))
    painter = QPainter(writer)
    painter.drawText(200, 400, "Total due 1240 EUR")
    painter.end()
    info, text = quick.read_attachment(pdf)
    from PySide6.QtGui import QFontDatabase
    if info["error"] == "no-pdf-reader":
        print("  skip PDF text: neither pdftotext nor QtPdf here")
    elif not QFontDatabase.families():
        print("  skip PDF text: no fonts here, so the test PDF has no text")
    else:
        check("a PDF's text is read", "1240" in text.replace(" ", "") and info["kind"] == "pdf", (info, text[:200]))
except ImportError:
    print("  skip PDF: no PySide6")

ctx = quick.attachment_context([quick.read_attachment(text_file), quick.read_attachment(image)])
check("the model is told what each file is and where it lives",
      "notas.md" in ctx and text_file in ctx and "R$ 1.240" in ctx and "foto.png" in ctx and "image" in ctx)
many = [({"name": "f%d" % i, "path": "/f%d" % i, "error": ""}, "y" * quick.ATTACH_FILE_CHARS) for i in range(4)]
check("several big files are cut in TOTAL too", len(quick.attachment_context(many)) < quick.ATTACH_TOTAL_CHARS + 2000)

print()
if fails:
    print(f"ai island bridge: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("ai island bridge: OK")
