#!/usr/bin/env python3
"""An API model drives the agent: it asks for a tool, the tool runs, it answers.

Reported as "API models need to run commands and things like the local ones
do -- agent mode, and in the Automations workflows". Before this, agent mode
refused a hosted model outright and an automation block could not name one.

This runs a real automation -- a manual trigger into an AI block set to act
on its own, naming `cloud:testprov` -- through the real Engine, against a fake
provider that speaks the OpenAI shape. The provider's first reply is a tool
call; its second, after it has been shown the result, is the final answer.
What has to be true:

  * the tool the provider asked for is the tool the loop executed, with the
    provider's arguments -- the whole point is that the API model ACTS
  * the second request carried the tool's result back to the provider
  * the block's output is the provider's final answer
  * each step was one counted request: two steps, two uses
  * an AI condition on the same provider answers true/false through it too
  * a provider with no key fails the block loudly instead of quietly asking a
    local model
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DAEMON = ROOT / "packages" / "genesi-ai-mode" / "genesi-automationd"

TMP = tempfile.mkdtemp(prefix="genesi-agent-cloud-")
os.environ["XDG_CONFIG_HOME"] = os.path.join(TMP, "conf")
os.environ["XDG_STATE_HOME"] = os.path.join(TMP, "state")

failures = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name
          + ("   " + detail if detail and not cond else ""))
    if not cond:
        failures.append(name)


# ── a provider that asks for a tool, then answers ─────────────────────────
SEEN = []


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        SEEN.append(body)
        text = json.dumps(body.get("messages", []))
        # The LAST message decides. The agent's system prompt explains the
        # GENESI_TOOL_RESULT convention in its own text, so looking for that
        # word anywhere in the conversation finds it in the very first request
        # -- which is what the first version of this fake did, answering
        # before any tool had been asked for.
        last = json.dumps((body.get("messages") or [{}])[-1])
        if "true or false" in text:
            reply = '{"answer": "true"}'
        elif "GENESI_TOOL_RESULT" not in last:
            reply = json.dumps({"type": "action", "tool": "system_info",
                                "arguments": {}, "reason": "look first"})
        else:
            reply = "The machine answered; all good."
        blob = json.dumps({"choices": [{"message": {"content": reply}}],
                           "usage": {"prompt_tokens": 5,
                                     "completion_tokens": 3}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)


srv = HTTPServer(("127.0.0.1", 0), Provider)
threading.Thread(target=srv.serve_forever, daemon=True).start()

conf = os.path.join(os.environ["XDG_CONFIG_HOME"], "genesi", "ai")
os.makedirs(conf, exist_ok=True)
json.dump({"active": "testprov", "use_for": "manual", "providers": {
    "testprov": {"base_url": f"http://127.0.0.1:{srv.server_address[1]}/v1",
                 "model": "big-model-1", "dialect": "openai", "key": "k"}}},
          io.open(os.path.join(conf, "cloud.json"), "w"))

spec = importlib.util.spec_from_loader(
    "automationd", importlib.machinery.SourceFileLoader("automationd", str(DAEMON)))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

if mod.assist is None:
    print("  FAIL  the daemon can import the shared module")
    sys.exit(1)
# The module read CLOUD_CONF at import, from the environment set above.
mod.assist.CLOUD_CONF = os.path.join(conf, "cloud.json")
mod.assist.USAGE_PATH = os.path.join(os.environ["XDG_STATE_HOME"], "usage.json")


class Status:
    def __init__(self):
        self.lines = []
        self.node_states = {}

    def state(self, *a, **k):
        pass

    def log(self, aid, line, level="out"):
        self.lines.append((level, line))

    def nodes_reset(self, aid, states=None):
        self.node_states = dict(states or {})

    def node_state(self, aid, node_id, state):
        self.node_states[node_id] = state

    def set_pending(self, aid, items):
        pass


class Tools:
    """Records what it was asked to do. The loop is under test, not the tool."""

    def __init__(self):
        self.calls = []

    def execute(self, tool, arguments):
        self.calls.append((tool, arguments))
        return {"ok": True, "tool": tool, "result": {"hostname": "genesi-test"}}

    def cancel(self):
        pass


def run(nodes, links):
    st = Status()
    eng = mod.Engine(st)
    eng._tools = Tools()
    auto = {"id": "a1", "name": "t", "enabled": True, "nodes": nodes,
            "links": links}
    eng.run_chain(auto, "trg", "test")
    return st, eng


TRIGGER = {"id": "trg", "kind": "evt_manual", "config": {}}

print("\n[1] an AI block on an API model acts on its own")
ai = {"id": "ai", "kind": "act_ai", "title": "check",
      "config": {"model": "cloud:testprov", "exec": "auto",
                 "prompt": "How is this machine?"}}
st, eng = run([TRIGGER, ai], [{"from": "trg", "to": "ai"}])
check("the block succeeded", st.node_states.get("ai") in ("done", "ok", "success"),
      str(st.node_states) + " " + str(st.lines[-4:]))
check("the tool the provider asked for is the tool that ran",
      eng._tools.calls == [("system_info", {})], str(eng._tools.calls))
check("two requests went to the provider", len(SEEN) == 2, str(len(SEEN)))
check("the provider was asked with the model set for it",
      all(b.get("model") == "big-model-1" for b in SEEN),
      str([b.get("model") for b in SEEN]))
check("the second request carried the tool's result",
      len(SEEN) == 2 and "GENESI_TOOL_RESULT" in json.dumps(SEEN[1]),
      "the provider never saw what its tool call produced")
check("the provider's final answer is what the block said",
      any("all good" in line for _lvl, line in st.lines), str(st.lines[-4:]))
use = mod.assist.usage_read().get("cloud", {}).get("testprov", {})
check("each step was one counted request", use.get("requests") == 2, str(use))

print("\n[2] an AI condition decides through the provider")
SEEN.clear()
cond = {"id": "c", "kind": "act_cond", "title": "is it fine",
        "config": {"mode": "ai", "model": "cloud:testprov",
                   "prompt": "Is the machine fine?"}}
yes = {"id": "yes", "kind": "act_script", "title": "yes",
       "config": {"command": "echo yes"}}
st, eng = run([TRIGGER, cond, yes],
              [{"from": "trg", "to": "c"},
               {"from": "c", "to": "yes", "fromPort": "true"}])
check("the condition asked the provider", len(SEEN) >= 1, str(len(SEEN)))
check("it took the true branch", any("condition → true" in line
                                     for _l, line in st.lines),
      str(st.lines[-5:]))

print("\n[3] a provider with no key fails loudly")
SEEN.clear()
bad = {"id": "ai", "kind": "act_ai", "title": "check",
       "config": {"model": "cloud:nosuch", "exec": "advisory",
                  "prompt": "hello"}}
st, eng = run([TRIGGER, bad], [{"from": "trg", "to": "ai"}])
check("nothing was sent anywhere", len(SEEN) == 0, str(len(SEEN)))
check("the block failed and said why",
      any("no API key" in line for _l, line in st.lines), str(st.lines[-3:]))

srv.shutdown()
print()
if failures:
    print(f"{len(failures)} check(s) failed")
    sys.exit(1)
print("ALL TESTS PASSED")
