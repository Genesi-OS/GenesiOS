#!/usr/bin/env python3
"""Does Stop actually stop a generation that has not produced a byte yet?

Reported as "the button to make the AI stop does not work, it does not stop
for good". The old Stop set a flag that each transport checked between lines
of the reply -- and a model still loading, still thinking, or answering a
non-streaming agent request sends no lines at all, so the check never ran
and the read sat blocked until the server was done.

This reproduces exactly that: an endpoint that accepts the request and then
says nothing for thirty seconds. A reader blocks on it, Stop is pressed, and
the reader has to be back within a couple of seconds -- through the Monitor's
own _track/_abort_live, not a copy of them. It also checks that the server
SEES the client go, because that is what makes Ollama and llama-server stop
generating rather than just stop being listened to.
"""
import importlib.machinery
import importlib.util
import os
import sys
import threading
import time
import types
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
MON = os.path.join(HERE, "..", "packages", "genesi-ai-mode", "monitor",
                   "genesi_ai_monitor.py")

failures = []


def ok(what):
    print(f"  ok   {what}")


def bad(what, why):
    print(f"  FAIL {what}")
    print(f"         {why}")
    failures.append(what)


print("== stop ==")

# The Monitor module needs Qt and a stack of sibling modules to import. Only
# three methods are under test, so they are lifted out of the source by name
# and bound to a bare object -- the real code, without the application.
src = open(MON, encoding="utf-8").read()
ns = {}
wanted = ("_track", "_untrack", "_abort_live")
chunks = []
for name in wanted:
    start = src.index(f"    def {name}(self")
    end = src.index("\n    def ", start + 10)
    # Stop at a decorator line too, so the next method's @Slot is not taken.
    at = src.find("\n    @", start + 10)
    if 0 < at < end:
        end = at
    chunks.append(src[start:end])
code = "import threading\nclass B:\n" + "\n".join(chunks) + "\n"
exec(compile(code, "monitor-methods", "exec"), ns)

hung_up = threading.Event()


class Silent(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(n)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.flush()
        # A model thinking. Nothing for up to thirty seconds -- unless the
        # client goes away, which is what a stopped request looks like here.
        self.connection.settimeout(0.2)
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                if self.connection.recv(1) == b"":
                    hung_up.set()
                    return
            except OSError as e:
                if "timed out" in str(e):
                    continue
                hung_up.set()
                return


class Quiet(HTTPServer):
    def handle_error(self, *a):
        pass


srv = Quiet(("127.0.0.1", 0), Silent)
threading.Thread(target=srv.serve_forever, daemon=True).start()

b = ns["B"]()
b._live = set()
b._live_lock = threading.Lock()
b._stop = False

result = {}


def reader():
    req = urllib.request.Request(
        f"http://127.0.0.1:{srv.server_address[1]}/api/chat", data=b"{}",
        headers={"Content-Type": "application/json"})
    t = time.time()
    try:
        r = urllib.request.urlopen(req, timeout=60)
        b._track(r)
        r.read()
        result["how"] = "returned"
    except Exception as e:  # noqa: BLE001
        result["how"] = type(e).__name__
    result["took"] = time.time() - t
    result["done_at"] = time.time()


th = threading.Thread(target=reader, daemon=True)
th.start()
time.sleep(1.0)
pressed = time.time()
b._stop = True
b._abort_live()
returned = time.time() - pressed
th.join(40)

# Two clocks, because the first version of this test had one and passed on the
# bug: with close() instead of shutdown(), close() itself blocked for the full
# thirty seconds waiting on the reader's buffer lock, so by the time anything
# was measured the reader had long finished. Stop must return at once (it runs
# on the UI thread), and the reader must be back at once.
if returned > 2:
    bad("pressing Stop returns immediately",
        f"_abort_live took {returned:.1f}s -- it runs on the UI thread, so the "
        "whole window freezes for that long")
else:
    ok(f"pressing Stop returned in {returned:.2f}s")

done = result.get("done_at")
if done is None or done - pressed > 3:
    bad("a request that has sent nothing stops when Stop is pressed",
        "the reader was blocked until the server finished -- which is the "
        "reported bug: nothing a flag can do reaches a read that is waiting")
else:
    ok(f"the blocked reader returned {done - pressed:.2f}s after Stop "
       f"({result.get('how')})")

if hung_up.wait(5):
    ok("the server saw the client go, so it stops generating")
else:
    bad("the server sees the connection end",
        "the reader returned but the socket stayed open, so the model keeps "
        "generating on the server for nobody")

srv.shutdown()
print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("stop: OK")
