#!/usr/bin/env python3
"""genesi-ai-key + the hosted branch: does each provider's shape reach it?

`anthropic` sat in the provider table for months under a comment saying every
endpoint in it speaks the OpenAI chat-completions shape. It does not: it takes
/v1/messages with an `x-api-key` header and answers with content[0].text. So
an Anthropic key produced a 404 from `test` and a silent fall back to the
local model from every `ask()`. Listed, documented, and never once working --
and nothing could have noticed, because no test had ever sent a request.

This sends one. A fake endpoint that speaks BOTH shapes, and refuses the
wrong one, so a provider pointed at the wrong dialect fails here rather than
on somebody's machine:

  * every provider in the table reaches the path its dialect uses, with the
    header its dialect uses, and its answer is parsed back out
  * the system prompt survives the trip -- Anthropic takes it as a field of
    its own, and getting that wrong produces a worse answer rather than an
    error, which is the kind of bug that never gets reported
  * one request is one use; a request that fails is an error and NOT a use;
    local and hosted are counted apart
  * the names the settings page offers are the names the writer accepts
  * STREAMING, per dialect. The chat gets its answer a token at a time, and
    the two dialects disagree about everything in that path: the event names,
    where the text sits in each event, and where the token counts arrive. A
    parser written for one silently produces an empty answer on the other --
    no error, no tokens, a bubble that finishes blank.
  * the chat can actually reach it: a `cloud:` model has to be in the picker's
    list, has to be recognised, and must not be handed to the agent loop,
    which runs against a local transport.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
AI = os.path.join(ROOT, "packages", "genesi-ai-mode")
ASSIST = os.path.join(AI, "genesi_ai_assist.py")
KEY = os.path.join(AI, "genesi-ai-key")
PAGE = os.path.join(ROOT, "packages", "genesi-center", "app", "pages",
                    "AiPage.qml")
MONITOR = os.path.join(AI, "monitor", "genesi_ai_monitor.py")
QUICK = os.path.join(AI, "monitor", "QuickChat.qml")

failures = []


def ok(what):
    print(f"  ok   {what}")


def bad(what, why):
    print(f"  FAIL {what}")
    print(f"         {why}")
    failures.append(what)


print("== hosted models ==")

# The state directory is redirected before the module is imported: it reads
# XDG_STATE_HOME at import time, and a test that counted requests into the
# developer's own usage file would be a test that changes what it measures.
TMP = tempfile.mkdtemp(prefix="genesi-ai-cloud-")
os.environ["XDG_STATE_HOME"] = os.path.join(TMP, "state")

spec = importlib.util.spec_from_loader(
    "assist", importlib.machinery.SourceFileLoader("assist", ASSIST))
assist = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assist)

SEEN = []

# What each provider REALLY speaks, written from its own documentation and
# kept deliberately apart from genesi_ai_assist.PROVIDERS.
#
# The first version of this test asked the fake endpoint to answer in whatever
# dialect the table claimed, and so it passed with `anthropic` mislabelled as
# `openai` -- the exact bug it exists to catch, certified by the test. A guard
# that reads its answer out of the thing it is checking is not a guard. This
# list is the second opinion:
#
#   openai      POST {base}/chat/completions   Authorization: Bearer
#   anthropic   POST {base}/messages           x-api-key + anthropic-version
#
# A provider added to the table has to be added here too, from its docs, which
# is the point: the moment of writing it down twice is the moment somebody
# checks.
REAL = {
    "openai": "openai",
    "anthropic": "anthropic",
    "gemini": "openai",
    "groq": "openai",
    "openrouter": "openai",
    "together": "openai",
}


class Fake(BaseHTTPRequestHandler):
    """Both shapes, each refusing the other's request.

    The provider's name is the first path segment, so this knows who it is
    pretending to be and can hold them to REAL rather than to the table.
    """

    def log_message(self, *a):
        pass

    def sse(self, chunks):
        """An event stream, in the wire shape each dialect really uses."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for c in chunks:
            self.wfile.write(("data: " + json.dumps(c) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        SEEN.append({"path": self.path, "body": body,
                     "auth": self.headers.get("Authorization"),
                     "xkey": self.headers.get("x-api-key"),
                     "version": self.headers.get("anthropic-version")})
        who = self.path.strip("/").split("/")[0]
        speaks = REAL.get(who)
        if speaks == "anthropic" and not self.path.endswith("/messages"):
            return self.fail(404, f"{who} has no {self.path}; it takes "
                                  "/v1/messages")
        if speaks == "openai" and self.path.endswith("/messages"):
            return self.fail(404, f"{who} has no /messages; it takes "
                                  "/chat/completions")
        if self.path.endswith("/messages"):
            if not self.headers.get("x-api-key"):
                return self.fail(401, "anthropic wants x-api-key")
            if not self.headers.get("anthropic-version"):
                return self.fail(400, "anthropic wants a version header")
            if body.get("stream"):
                # Anthropic's real event sequence, abbreviated: the usage
                # arrives in message_start and message_delta, and the text in
                # content_block_delta.
                return self.sse([
                    {"type": "message_start",
                     "message": {"usage": {"input_tokens": 11}}},
                    {"type": "content_block_start", "index": 0},
                    {"type": "content_block_delta",
                     "delta": {"type": "text_delta", "text": "streamed "}},
                    {"type": "content_block_delta",
                     "delta": {"type": "text_delta", "text": "anthropic"}},
                    {"type": "message_delta",
                     "usage": {"output_tokens": 5}},
                ])
            out = {"content": [{"type": "text", "text": "ok-anthropic"}],
                   "usage": {"input_tokens": 11, "output_tokens": 3}}
        elif self.path.endswith("/chat/completions"):
            if not (self.headers.get("Authorization") or "").startswith(
                    "Bearer "):
                return self.fail(401, "openai wants a bearer token")
            if body.get("stream"):
                return self.sse([
                    {"choices": [{"delta": {"content": "streamed "}}]},
                    {"choices": [{"delta": {"content": "openai"}}]},
                    {"choices": [{"delta": {}}],
                     "usage": {"prompt_tokens": 7, "completion_tokens": 4}},
                ])
            out = {"choices": [{"message": {"content": "ok-openai"}}],
                   "usage": {"prompt_tokens": 7, "completion_tokens": 2}}
        else:
            return self.fail(404, "no such endpoint")
        blob = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

    def fail(self, code, why):
        blob = json.dumps({"error": why}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)


srv = HTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=srv.serve_forever, daemon=True).start()
HOST = f"http://127.0.0.1:{srv.server_address[1]}"

PAYLOAD = {"messages": [{"role": "system", "content": "SYSTEM-MARK"},
                        {"role": "user", "content": "hello"}],
           "max_tokens": 16, "stream": False}

# ── Every provider, in its own dialect ─────────────────────────────────────
for name in sorted(assist.PROVIDERS):
    base, model, dialect = assist.PROVIDERS[name]
    if name != "custom" and not base:
        bad(f"{name} has an endpoint", "its base URL is empty")
        continue
    if name != "custom" and not model:
        bad(f"{name} has a default model", "it has none, so `set` cannot "
            "store one and every request asks for a model called ''")
        continue
    if name == "custom":
        continue
    if name not in REAL:
        # Without this the fake answers anything, and a new provider is
        # checked against nothing at all -- which is how the last version of
        # this file passed on the bug it was written for.
        bad(f"{name}'s real shape is written down",
            "add it to REAL at the top of this file, from the provider's own "
            "documentation. Until it is there the fake endpoint accepts "
            "whatever the table claims, and this checks nothing.")
        continue
    SEEN.clear()
    cloud = {"provider": name, "base_url": f"{HOST}/{name}/v1",
             "model": model,
             "dialect": dialect, "key": "k-" + name}
    try:
        text, tin, tout = assist.cloud_request(cloud, dict(PAYLOAD), 10)
    except Exception as e:  # noqa: BLE001 -- any failure is the finding
        bad(f"{name} ({dialect}) gets an answer",
            f"{type(e).__name__}: {e}\n"
            "         The dialect in the table is what decides the path, the "
            "auth header and how the answer is read.")
        continue
    got = SEEN[-1] if SEEN else {}
    want_path = "/messages" if dialect == "anthropic" else "/chat/completions"
    if not got.get("path", "").endswith(want_path):
        bad(f"{name} posts to {want_path}", f"it posted to {got.get('path')}")
    elif text != ("ok-anthropic" if dialect == "anthropic" else "ok-openai"):
        bad(f"{name}'s answer is read back", f"got {text!r}")
    elif (tin, tout) == (0, 0):
        bad(f"{name} reports its token use",
            "both counts came back zero, so nothing can be billed against it")
    else:
        # The system prompt is the silent one: Anthropic takes it as a
        # top-level field, and sending it as a message is accepted, ignored,
        # and answered slightly worse for ever.
        b = got.get("body") or {}
        carried = (b.get("system") == "SYSTEM-MARK" if dialect == "anthropic"
                   else any(m.get("content") == "SYSTEM-MARK"
                            for m in b.get("messages", [])))
        if not carried:
            bad(f"{name} carries the system prompt",
                "it did not arrive in the shape this dialect reads it from")
        else:
            ok(f"{name}: {dialect} dialect, {want_path}, system prompt "
               f"carried, {tin}/{tout} tokens")

# ── Streaming, per dialect ─────────────────────────────────────────────────
for name in ("openai", "anthropic"):
    _base, model, dialect = assist.PROVIDERS[name]
    cloud = {"provider": name, "base_url": f"{HOST}/{name}/v1",
             "model": model, "dialect": dialect, "key": "k"}
    seen = []
    try:
        text, tin, tout = assist.cloud_stream(
            cloud, dict(PAYLOAD), 10, on_token=seen.append)
    except Exception as e:  # noqa: BLE001
        bad(f"{name} streams", f"{type(e).__name__}: {e}")
        continue
    want = "streamed " + ("anthropic" if dialect == "anthropic" else "openai")
    if text != want:
        bad(f"{name}'s stream is read back whole", f"got {text!r}")
    elif len(seen) < 2:
        bad(f"{name} streams token by token",
            f"the callback fired {len(seen)} time(s), so the chat would get "
            "the whole answer at once and the typing effect is a lie")
    elif "".join(seen) != want:
        bad(f"{name}'s tokens add up to its answer",
            f"the callback saw {seen!r}")
    elif (tin, tout) == (0, 0):
        bad(f"{name} reports token use while streaming",
            "both counts came back zero")
    else:
        ok(f"{name}: streamed in {len(seen)} tokens, {tin}/{tout} counted")

# A stopped stream still counts as a request -- the provider served it.
cloud = {"provider": "openai", "base_url": f"{HOST}/openai/v1", "model": "m",
         "dialect": "openai", "key": "k"}
before = (assist.usage_read().get("cloud", {}).get("openai") or {})
assist.cloud_stream(cloud, dict(PAYLOAD), 10, on_token=None,
                    stop=lambda: True)
after = (assist.usage_read().get("cloud", {}).get("openai") or {})
if after.get("requests", 0) != before.get("requests", 0) + 1:
    bad("a stream stopped by the user still counts",
        "it was not counted, and the provider served it either way")
else:
    ok("a stream stopped partway still counts as one request")

# ── One request is one use ─────────────────────────────────────────────────
before = assist.usage_read()
cloud = {"provider": "openai", "base_url": f"{HOST}/openai/v1", "model": "m",
         "dialect": "openai", "key": "k"}
for _ in range(3):
    assist._ask_cloud(cloud, dict(PAYLOAD), 10)
after = assist.usage_read()
n = ((after.get("cloud", {}).get("openai") or {}).get("requests", 0)
     - (before.get("cloud", {}).get("openai") or {}).get("requests", 0))
if n != 3:
    bad("three requests count as three uses", f"the count moved by {n}")
else:
    ok("three hosted requests count as three uses")

dead = {"provider": "openai", "base_url": "http://127.0.0.1:1/v1",
        "model": "m", "dialect": "openai", "key": "k"}
before = assist.usage_read()
assist._ask_cloud(dead, dict(PAYLOAD), 2)
after = assist.usage_read()
b = after.get("cloud", {}).get("openai") or {}
a = before.get("cloud", {}).get("openai") or {}
if b.get("requests", 0) != a.get("requests", 0):
    bad("a request that never landed is not a use",
        "it was counted as one, so the number says somebody was billed for a "
        "connection that failed")
elif b.get("errors", 0) != a.get("errors", 0) + 1:
    bad("a failed request is counted as an error", "it was not counted at all")
else:
    ok("a failed request is an error, not a use")

assist.usage_note("local", ok=True)
u = assist.usage_read()
if (u.get("local") or {}).get("requests", 0) < 1:
    bad("local requests are counted", "the local bucket stayed empty")
elif "local" in (u.get("cloud") or {}):
    bad("local and hosted are kept apart",
        "a local request landed in the hosted table")
else:
    ok("local and hosted are counted apart")

# ── The page's list and the table ──────────────────────────────────────────
#
# The settings page offers provider names as buttons and genesi-ai-key
# validates them against the table. A name in one and not the other is a
# button that reports an unknown provider, which is this repository's oldest
# failure and has its own guard for every other setting.
page = re.sub(r"//[^\n]*", "", io.open(PAGE, encoding="utf-8").read())
m = re.search(r"readonly property var cloudProviders:\s*\[(.*?)\]", page,
              re.S)
if not m:
    bad("AiPage lists the providers it offers",
        "no `cloudProviders` list, so the names it shows cannot be checked "
        "against the ones genesi-ai-key accepts")
else:
    shown = set(re.findall(r'id:\s*"(\w+)"', m.group(1)))
    known = set(assist.PROVIDERS) - {"custom"}
    if shown - known:
        bad("every provider the page offers exists",
            f"the page offers {sorted(shown - known)}, which genesi-ai-key "
            "refuses")
    elif known - shown:
        bad("every provider is offered",
            f"{sorted(known - shown)} can be set from a terminal and not from "
            "the page")
    else:
        ok(f"the page and the writer agree on {sorted(shown)}")

# ── genesi-ai-key itself ───────────────────────────────────────────────────
src = io.open(KEY, encoding="utf-8").read()
body = re.sub(r"#[^\n]*", "", src)
if re.search(r'^PROVIDERS\s*=', body, re.M):
    bad("there is one provider table",
        "genesi-ai-key has its own again; it writes the config that "
        "genesi_ai_assist reads, and two tables of defaults disagree")
else:
    ok("one provider table, in the module that sends the request")

# ── Can the chat reach it? ─────────────────────────────────────────────────
#
# Three separate things have to line up for "you can choose to use the API key
# in the Monitor" to be true, and each of them fails silently on its own: the
# ref has to be in the list the picker reads, the send path has to recognise
# it, and the AGENT path must refuse it rather than handing a provider to a
# loop built on a local transport.
mon = io.open(MONITOR, encoding="utf-8").read()
body = re.sub(r"#[^\n]*", "", mon)
for what, pattern, why in (
    ("the model list offers it",
     r"names\.append\(CLOUD_PREFIX",
     "loadModels never appends it, so it is not in the picker and cannot be "
     "chosen"),
    ("the chat routes it",
     r"startswith\(CLOUD_PREFIX\)[\s\S]{0,200}_chat_cloud",
     "sendPrompt does not branch on it, so a cloud ref is handed to "
     "_prepare_transport, which tries to load it as a local model"),
    ("the agent refuses it",
     r"startswith\(CLOUD_PREFIX\)[\s\S]{0,400}_agent_status\(\"error\"",
     "sendAgentPrompt would hand a provider to the tool loop"),
    ("the streaming goes through the shared module",
     r"assist\.cloud_stream\(",
     "the Monitor speaks to the provider itself, which is a second place "
     "that has to know how Anthropic differs from OpenAI"),
):
    if re.search(pattern, body):
        ok(what)
    else:
        bad(what, why)

quick = io.open(QUICK, encoding="utf-8").read()
if "isCloudModel" not in quick:
    bad("Quick Chat routes a hosted model past the agent loop",
        "it sends everything through sendAgentPrompt, which refuses a cloud "
        "ref -- so picking one there is an error message rather than an "
        "answer")
else:
    ok("Quick Chat sends a hosted model through the plain chat path")

srv.shutdown()
print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("hosted models: OK")
