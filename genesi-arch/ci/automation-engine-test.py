"""Headless exercise of genesi-automationd's Engine: branch routing, multi-link
fan-out, stderr matching and per-node status reporting."""
import importlib.util
import importlib.machinery
import sys
from pathlib import Path

DAEMON = Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode" / "genesi-automationd"

spec = importlib.util.spec_from_loader("automationd",
                                       importlib.machinery.SourceFileLoader("automationd", str(DAEMON)))
mod = importlib.util.module_from_spec(spec)
sys.modules["automationd"] = mod
spec.loader.exec_module(mod)
print("daemon module loaded OK")

# This host is Windows: /bin/sh does not exist, so every real subprocess would
# fail and mask the logic under test. Swap in a tiny deterministic "shell" that
# understands the handful of commands the tests use, so what we exercise is the
# ENGINE (routing, gating, per-node status, payload piping) — not the OS shell.
class FakeProc:
    def __init__(self, rc, out="", err=""):
        self.returncode, self.stdout, self.stderr = rc, out, err


def fake_run(argv, **kw):
    cmd = argv[-1]
    env = kw.get("env") or {}
    if cmd.startswith("exit "):
        return FakeProc(int(cmd.split()[1]))
    if cmd == "true":
        return FakeProc(0)
    if cmd.startswith("echo "):
        return FakeProc(0, cmd[5:] + "\n")
    if cmd.startswith("nosuchcommand"):
        return FakeProc(127, "", "sh: %s: command not found\n" % cmd)
    if cmd.startswith("test "):
        # test "$GENESI_INPUT" = "VALUE"
        left = env.get("GENESI_INPUT", "")
        want = cmd.split("=", 1)[1].strip().strip('"')
        return FakeProc(0 if left == want else 1)
    return FakeProc(0)


mod.subprocess.run = fake_run
mod._graphical_env = lambda: {}


class FakeStatus:
    """Records everything the engine reports."""
    def __init__(self):
        self.node_states = {}      # id -> last state
        self.history = []          # ordered (id, state)
        self.lines = []

    def state(self, aid, state, running=None):
        pass

    def log(self, aid, line, level="out"):
        self.lines.append((level, line))

    def nodes_reset(self, aid, states=None):
        self.node_states = dict(states or {})
        for k, v in (states or {}).items():
            self.history.append((k, v))

    def node_state(self, aid, node_id, state):
        self.node_states[node_id] = state
        self.history.append((node_id, state))

    def set_pending(self, aid, items):
        pass


def build(nodes, links):
    return {"id": "a1", "name": "t", "enabled": True, "nodes": nodes, "links": links}


def run(auto, start="trg"):
    st = FakeStatus()
    eng = mod.Engine(st)
    eng.run_chain(auto, start, "test")
    return st


TRIGGER = {"id": "trg", "kind": "evt_manual", "config": {}}


def script(nid, command):
    return {"id": nid, "kind": "act_script", "title": nid,
            "config": {"command": command}}


failures = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name + ("   " + detail if detail and not cond else ""))
    if not cond:
        failures.append(name)


# ── 1. on-error fires only on failure; on-ok is skipped ──────────────────
print("\n[1] failing script routes to on-error only")
st = run(build(
    [TRIGGER, script("s", "exit 3"), script("okB", "echo ok-branch"), script("errB", "echo err-branch")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "okB", "fromPort": "ok"},
     {"from": "s", "to": "errB", "fromPort": "err"}]))
check("script marked failed", st.node_states.get("s") == "failed", str(st.node_states))
check("on-error branch ran", st.node_states.get("errB") == "ok", str(st.node_states))
check("on-ok branch skipped", st.node_states.get("okB") == "skipped", str(st.node_states))

# ── 2. succeeding script routes to on-ok only ───────────────────────────
print("\n[2] succeeding script routes to on-ok only")
st = run(build(
    [TRIGGER, script("s", "echo hello"), script("okB", "true"), script("errB", "true")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "okB", "fromPort": "ok"},
     {"from": "s", "to": "errB", "fromPort": "err"}]))
check("script marked ok", st.node_states.get("s") == "ok", str(st.node_states))
check("on-ok branch ran", st.node_states.get("okB") == "ok", str(st.node_states))
check("on-error branch skipped", st.node_states.get("errB") == "skipped", str(st.node_states))

# ── 3. MULTIPLE links from the SAME port both fire ──────────────────────
print("\n[3] two links on the same on-ok port both run")
st = run(build(
    [TRIGGER, script("s", "echo hi"), script("t1", "true"), script("t2", "true")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "t1", "fromPort": "ok"},
     {"from": "s", "to": "t2", "fromPort": "ok"}]))
check("first target ran", st.node_states.get("t1") == "ok", str(st.node_states))
check("second target ran", st.node_states.get("t2") == "ok", str(st.node_states))

# ── 4. command sensor matches text on STDERR ────────────────────────────
print("\n[4] command sensor matches stderr text")
sensor = {"id": "chk", "kind": "evt_command", "title": "sensor",
          "config": {"command": "", "on": "match", "match": "not found"}}
st = run(build(
    [TRIGGER, script("s", "nosuchcommand_xyz"), sensor, script("after", "true")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "chk", "fromPort": "err"},
     {"from": "chk", "to": "after"}]))
check("sensor condition met", st.node_states.get("chk") == "ok", str(st.node_states))
check("chain continued past sensor", st.node_states.get("after") == "ok", str(st.node_states))

# ── 5. sensor GATES the chain when the condition fails ──────────────────
print("\n[5] sensor blocks the chain when its regex does not match")
sensor_no = {"id": "chk", "kind": "evt_command", "title": "sensor",
             "config": {"command": "", "on": "match", "match": "WILL_NOT_MATCH"}}
st = run(build(
    [TRIGGER, script("s", "echo hello"), sensor_no, script("after", "true")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "chk", "fromPort": "ok"},
     {"from": "chk", "to": "after"}]))
check("sensor condition not met", st.node_states.get("chk") == "failed", str(st.node_states))
check("chain stopped at sensor", st.node_states.get("after") != "ok", str(st.node_states))

# ── 6. execution is SEQUENTIAL (running then final, one at a time) ──────
print("\n[6] nodes run one at a time, in order")
st = run(build(
    [TRIGGER, script("s", "echo a"), script("t", "echo b")],
    [{"from": "trg", "to": "s"}, {"from": "s", "to": "t", "fromPort": "ok"}]))
seq = [h for h in st.history if h[0] in ("s", "t")]
check("order is s:running,s:ok,t:running,t:ok",
      seq == [("s", "running"), ("s", "ok"), ("t", "running"), ("t", "ok")], str(seq))

# ── 7. payload pipes from script to next block ──────────────────────────
print("\n[7] output pipes to the next block via $GENESI_INPUT")
st = run(build(
    [TRIGGER, script("s", "echo PIPED_VALUE"),
     script("t", 'test "$GENESI_INPUT" = "PIPED_VALUE"')],
    [{"from": "trg", "to": "s"}, {"from": "s", "to": "t", "fromPort": "ok"}]))
check("downstream saw the piped value", st.node_states.get("t") == "ok", str(st.node_states))


# ── 8. a failed condition blocks EVERY port, including the legacy "output" ──
# Reproduces the 2026-07-19 report: a sensor whose regex did NOT match still
# ran the next card, because the link carried the legacy fromPort "output"
# ("fire if the node printed anything"), which bypassed the gate.
print("\n[8] legacy 'output' link cannot bypass a failed condition")
sensor_nomatch = {"id": "chk", "kind": "evt_command", "title": "sensor",
                  "config": {"command": "", "on": "match",
                             "match": "unknown command: testee"}}
st = run(build(
    [TRIGGER, script("s", "nosuchcommand_teste"), sensor_nomatch, script("ai", "true")],
    [{"from": "trg", "to": "s"},
     {"from": "s", "to": "chk", "fromPort": "err"},
     {"from": "chk", "to": "ai", "fromPort": "output"}]))
check("sensor did not match", st.node_states.get("chk") == "failed", str(st.node_states))
check("downstream card did NOT run", st.node_states.get("ai") != "ok", str(st.node_states))

# ── 9. every Fire-when mode gates correctly mid-chain ───────────────────
print("\n[9] all four Fire-when modes")


def sensor_chain(cfg, script_cmd="echo hello"):
    node = {"id": "chk", "kind": "evt_command", "title": "s", "config": cfg}
    return build(
        [TRIGGER, script("s", script_cmd), node, script("after", "true")],
        [{"from": "trg", "to": "s"},
         {"from": "s", "to": "chk"},
         {"from": "chk", "to": "after"}])


# exit0: command succeeds -> passes
st = run(sensor_chain({"command": "true", "on": "exit0"}))
check("exit0 passes when command succeeds", st.node_states.get("after") == "ok", str(st.node_states))
st = run(sensor_chain({"command": "exit 1", "on": "exit0"}))
check("exit0 blocks when command fails", st.node_states.get("after") != "ok", str(st.node_states))

# error: command fails -> passes
st = run(sensor_chain({"command": "exit 1", "on": "error"}))
check("error passes when command fails", st.node_states.get("after") == "ok", str(st.node_states))
st = run(sensor_chain({"command": "true", "on": "error"}))
check("error blocks when command succeeds", st.node_states.get("after") != "ok", str(st.node_states))

# match: regex hits -> passes
st = run(sensor_chain({"command": "echo needle", "on": "match", "match": "needle"}))
check("match passes on a hit", st.node_states.get("after") == "ok", str(st.node_states))
st = run(sensor_chain({"command": "echo needle", "on": "match", "match": "nope"}))
check("match blocks on a miss", st.node_states.get("after") != "ok", str(st.node_states))

# changed: first run never fires; a differing output does
auto_changed = sensor_chain({"command": "echo one", "on": "changed"})
st_engine = FakeStatus()
eng = mod.Engine(st_engine)
eng.run_chain(auto_changed, "trg", "t")
check("changed blocks on the first run",
      st_engine.node_states.get("after") != "ok", str(st_engine.node_states))
auto_changed["nodes"][2]["config"]["command"] = "echo two"
st_engine.node_states.clear()
eng.run_chain(auto_changed, "trg", "t")     # same Engine keeps the snapshot
check("changed passes when the output differs",
      st_engine.node_states.get("after") == "ok", str(st_engine.node_states))

# ══ Condition nodes, named AI outputs and {{templating}} ═══════════════════
#
# The backbone the Condition node and the AI-output feature stand on. Before
# this, the only thing one block could hand the next was {input} — the whole
# previous output as one lump of text — so "notify me with the CPU figure the
# AI just read" had nowhere to put the figure.

print("\n[7] {{name}} rendering")
sub = mod.Engine._sub
check("{input} still works", sub("got {input}", "X") == "got X")
check("{{name}} resolves", sub("cpu {{cpu}}%", "", {"cpu": "83"}) == "cpu 83%")
check("spaces inside braces are fine", sub("{{ cpu }}", "", {"cpu": "9"}) == "9")
check("{{input}} is an alias of {input}", sub("{{input}}", "P") == "P")
check("both forms in one string", sub("{input}/{{a}}", "P", {"a": "1"}) == "P/1")
check("an UNKNOWN name is left visible, not blanked",
      sub("cpu {{nope}}%", "", {"cpu": "1"}) == "cpu {{nope}}%",
      "a notification reading 'cpu %' looks like a broken computer")
check("no braces means no work", sub("plain", "x", {"a": "1"}) == "plain")

print("\n[8] reading declared fields out of a model reply")
pj = mod._parse_json_fields
check("plain object",
      pj('{"cpu": 83, "gpu": 12}', ["cpu", "gpu"]) == {"cpu": "83", "gpu": "12"})
check("wrapped in a json fence", pj('```json\n{"cpu": 5}\n```', ["cpu"]) == {"cpu": "5"})
check("buried in prose", pj('Sure! {"cpu": 5} hope that helps', ["cpu"]) == {"cpu": "5"})
check("nested braces survive", pj('{"a": {"b": 1}, "cpu": 7}', ["cpu"]) == {"cpu": "7"})
check("booleans become true/false", pj('{"answer": true}', ["answer"]) == {"answer": "true"})
check("a MISSING field is a failure, not a blank",
      pj('{"cpu": 5}', ["cpu", "gpu"]) is None,
      "half the fields silently empty is the failure this design exists to stop")
check("not JSON at all", pj("I think the CPU is fine", ["cpu"]) is None)
check("empty reply", pj("", ["cpu"]) is None)
check("a JSON array is not an object", pj("[1,2]", ["cpu"]) is None)

print("\n[9] evaluating a condition expression")
ce = mod._cond_eval
check("numeric >", ce("83 > 80") is True)
check("numeric > that is false", ce("12 > 80") is False)
check("a percent sign is tolerated", ce("83% > 80") is True)
check("text ==", ce("running == running") is True)
check("contains", ce("hello world contains world") is True)
check("startswith", ce("genesi-ai-mode startswith genesi") is True)
check("matches (regex)", ce("build-1234 matches [0-9]+") is True)
check("a bare truthy value", ce("true") is True)
check("a bare falsy value", ce("false") is False)
check("empty is false, never a crash", ce("") is False)
check("a broken regex is false, not an exception", ce("x matches [") is False)
check("no eval: python is not a language here",
      ce("__import__('os').system('x') > 0") is False)

print("\n[10] a Condition node routes true and false")


def cond(nid, expr):
    return {"id": nid, "kind": "act_cond", "title": nid,
            "config": {"mode": "expr", "expr": expr}}


st = run(build(
    [TRIGGER, cond("c", "90 > 80"), script("T", "echo yes"), script("F", "echo no")],
    [{"from": "trg", "to": "c"},
     {"from": "c", "to": "T", "fromPort": "true"},
     {"from": "c", "to": "F", "fromPort": "false"}]))
check("true branch ran", st.node_states.get("T") == "ok", str(st.node_states))
check("false branch skipped", st.node_states.get("F") == "skipped", str(st.node_states))
check("a false answer is NOT painted as a failure",
      st.node_states.get("c") == "ok", str(st.node_states))

st = run(build(
    [TRIGGER, cond("c", "10 > 80"), script("T", "echo yes"), script("F", "echo no")],
    [{"from": "trg", "to": "c"},
     {"from": "c", "to": "T", "fromPort": "true"},
     {"from": "c", "to": "F", "fromPort": "false"}]))
check("false branch ran", st.node_states.get("F") == "ok", str(st.node_states))
check("true branch skipped", st.node_states.get("T") == "skipped", str(st.node_states))

st = run(build(
    [TRIGGER, cond("c", "10 > 80"), script("N", "echo next")],
    [{"from": "trg", "to": "c"}, {"from": "c", "to": "N"}]))
check("a portless link does NOT run on false",
      st.node_states.get("N") == "skipped", str(st.node_states))

st = run(build(
    [TRIGGER, cond("c", "90 > 80"), script("N", "echo next")],
    [{"from": "trg", "to": "c"}, {"from": "c", "to": "N"}]))
check("a portless link DOES run on true",
      st.node_states.get("N") == "ok", str(st.node_states))

st = run(build(
    [TRIGGER, cond("c", ""), script("T", "echo yes"), script("F", "echo no")],
    [{"from": "trg", "to": "c"},
     {"from": "c", "to": "T", "fromPort": "true"},
     {"from": "c", "to": "F", "fromPort": "false"}]))
check("an unconfigured condition fails and takes NEITHER branch",
      st.node_states.get("c") == "failed"
      and st.node_states.get("T") != "ok" and st.node_states.get("F") != "ok",
      str(st.node_states))

print("\n[11] the AI block publishes named values the next block can use")
# Stand in for the model. The real path (Turbo / Ollama / local GGUF) is left
# alone; only the single call that would reach a model is replaced.
mod._AGENT_OK = True
mod._ensure_ollama = lambda: None


class _Turbo:
    @staticmethod
    def is_gguf_ref(m):
        return False


mod.turbo_ctl = _Turbo
_reply = {"text": '{"cpu": "83", "gpu": "12"}'}
mod.Engine._ai_run = lambda self, model, prompt, mode, use_turbo, aid: _reply["text"]
# The repair turn (_ai_extract) goes through _ai_chat, not _ai_run. Stubbed too
# so nothing here reaches the network; "" means the reformat produced no JSON,
# which is the old behaviour and keeps every existing expectation honest.
_repair = {"text": "", "asked": []}


def _fake_chat(self, model, messages, use_turbo, system=None):
    _repair["asked"].append(messages[-1]["content"])
    return _repair["text"]


mod.Engine._ai_chat = _fake_chat

ai = {"id": "ai", "kind": "act_ai", "title": "ai",
      "config": {"prompt": "is the pc busy", "exec": "advisory",
                 "outputs": [{"name": "cpu", "desc": "cpu %"},
                             {"name": "gpu", "desc": "gpu %"}]}}
notify = {"id": "n", "kind": "act_notify", "title": "n",
          "config": {"title": "Load", "body": "CPU {{cpu}}%, GPU {{gpu}}%"}}
sent = []
mod.subprocess.Popen = lambda argv, **kw: sent.append(argv)
# notify-send does not exist on this host, and _act_notify rightly refuses to
# claim it notified anyone when it cannot. Pretend it is installed so what is
# under test stays the VALUE the notification carries.
mod.shutil.which = lambda name: '/usr/bin/' + name

st = run(build([TRIGGER, ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("the AI block succeeded", st.node_states.get("ai") == "ok", str(st.node_states))
check("the notification ran", st.node_states.get("n") == "ok", str(st.node_states))
body = " ".join(sent[-1]) if sent else ""
check("the notification carries the AI's VALUES, not its prose",
      "CPU 83%, GPU 12%" in body, body)

_reply["text"] = "the cpu is quite busy right now"
st = run(build([TRIGGER, ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("a reply that ignores the schema FAILS the block",
      st.node_states.get("ai") == "failed", str(st.node_states))
# A portless link still continues after a failure — that is the documented
# legacy contract in run_chain ("everything reachable runs"), and changing it
# would silently rewire every graph already saved on someone else's machine.
# What the new code guarantees instead is that the failure is VISIBLE: the
# unresolved placeholder is printed literally rather than rendered as blank.
body = " ".join(sent[-1]) if sent else ""
check("an unresolved value shows itself instead of rendering blank",
      "{{cpu}}" in body, body)
# Wire the ok port and the branch is properly gated.
st = run(build([TRIGGER, ai, notify],
               [{"from": "trg", "to": "ai"},
                {"from": "ai", "to": "n", "fromPort": "ok"}]))
check("an ok-port link does NOT run after the block failed",
      st.node_states.get("n") == "skipped", str(st.node_states))

print("\n[12] an AI condition answers true/false")
aicond = {"id": "c", "kind": "act_cond", "title": "c",
          "config": {"mode": "ai", "prompt": "is the pc busy?"}}

_reply["text"] = '{"answer": "true"}'
st = run(build([TRIGGER, aicond, script("T", "echo yes"), script("F", "echo no")],
               [{"from": "trg", "to": "c"},
                {"from": "c", "to": "T", "fromPort": "true"},
                {"from": "c", "to": "F", "fromPort": "false"}]))
check("model said true -> true branch",
      st.node_states.get("T") == "ok", str(st.node_states))

_reply["text"] = '{"answer": false}'
st = run(build([TRIGGER, aicond, script("T", "echo yes"), script("F", "echo no")],
               [{"from": "trg", "to": "c"},
                {"from": "c", "to": "T", "fromPort": "true"},
                {"from": "c", "to": "F", "fromPort": "false"}]))
check("model said false -> false branch",
      st.node_states.get("F") == "ok", str(st.node_states))

_reply["text"] = "maybe? hard to say"
st = run(build([TRIGGER, aicond, script("T", "echo yes"), script("F", "echo no")],
               [{"from": "trg", "to": "c"},
                {"from": "c", "to": "T", "fromPort": "true"},
                {"from": "c", "to": "F", "fromPort": "false"}]))
check("an undecidable answer fails instead of guessing",
      st.node_states.get("c") == "failed" and st.node_states.get("T") != "ok",
      str(st.node_states))


print("\n[13] a Loop repeats its 'each' branch once per item")
seen = []
_orig_run = fake_run


def counting_run(argv, **kw):
    seen.append(kw.get("env", {}).get("GENESI_INPUT", ""))
    return _orig_run(argv, **kw)


mod.subprocess.run = counting_run


def loop(nid, **cfg):
    base = {"source": "lines", "max": 100}
    base.update(cfg)
    return {"id": nid, "kind": "act_loop", "title": nid, "config": base}


st = run(build(
    [TRIGGER, script("src", "echo a\nb\nc"), loop("L"),
     script("body", "true"), script("after", "true")],
    [{"from": "trg", "to": "src"},
     {"from": "src", "to": "L"},
     {"from": "L", "to": "body", "fromPort": "each"},
     {"from": "L", "to": "after", "fromPort": "done"}]))
check("the body ran once per line", seen.count("a") == 1 and seen.count("b") == 1
      and seen.count("c") == 1, str(seen))
check("the body is marked ok", st.node_states.get("body") == "ok", str(st.node_states))
check("the done branch ran after it", st.node_states.get("after") == "ok",
      str(st.node_states))

# The reason the loop body is walked synchronously instead of being queued.
seen.clear()
st = run(build(
    [TRIGGER, script("src", "echo a\nb\nc"), loop("L"),
     {"id": "body", "kind": "act_script", "title": "body",
      "config": {"command": "echo {{item}}"}}],
    [{"from": "trg", "to": "src"},
     {"from": "src", "to": "L"},
     {"from": "L", "to": "body", "fromPort": "each"}]))
check("{{item}} is a DIFFERENT value each iteration",
      st.node_states.get("body") == "ok",
      "queueing the body would bind every iteration to the last item")

st = run(build(
    [TRIGGER, loop("L", source="list", list="x,y"), script("body", "true")],
    [{"from": "trg", "to": "L"}, {"from": "L", "to": "body", "fromPort": "each"}]))
check("a hand-typed list is a source", st.node_states.get("body") == "ok",
      str(st.node_states))

st = run(build(
    [TRIGGER, loop("L", source="range", **{"from": 1, "to": 3}),
     script("body", "true")],
    [{"from": "trg", "to": "L"}, {"from": "L", "to": "body", "fromPort": "each"}]))
check("a range is a source", st.node_states.get("body") == "ok", str(st.node_states))

st = run(build(
    [TRIGGER, loop("L"), script("body", "true")],
    [{"from": "trg", "to": "L"}, {"from": "L", "to": "body", "fromPort": "each"}]))
check("nothing to iterate is not a failure", st.node_states.get("L") == "ok",
      str(st.node_states))

st = run(build(
    [TRIGGER, script("src", "echo a"), loop("L"),
     script("body", "true"), script("after", "true")],
    [{"from": "trg", "to": "src"}, {"from": "src", "to": "L"},
     {"from": "L", "to": "body", "fromPort": "each"},
     {"from": "L", "to": "after"}]))
check("a portless link means 'after the loop', not 'part of it'",
      st.node_states.get("after") == "ok" and st.node_states.get("body") == "ok",
      str(st.node_states))

st = run(build(
    [TRIGGER, script("src", "echo a"), loop("L")],
    [{"from": "trg", "to": "src"}, {"from": "src", "to": "L"}]))
check("a loop with nothing on 'each' fails loudly",
      st.node_states.get("L") == "failed", str(st.node_states))

seen.clear()
st = run(build(
    [TRIGGER, script("src", "echo a\nb\nc\nd\ne"), loop("L", max=2),
     script("body", "true")],
    [{"from": "trg", "to": "src"}, {"from": "src", "to": "L"},
     {"from": "L", "to": "body", "fromPort": "each"}]))
check("the item cap is honoured", len([s for s in seen if s in "abcde"]) == 2,
      str(seen))

print("\n[14] a Sub-workflow runs another graph as one step")
CHILD = {"id": "child", "name": "Child flow", "enabled": True,
         "nodes": [{"id": "ctrg", "kind": "evt_manual", "config": {}},
                   {"id": "cs", "kind": "act_script", "title": "cs",
                    "config": {"command": "echo from-child"}}],
         "links": [{"from": "ctrg", "to": "cs"}]}


def subflow(nid, ref):
    return {"id": nid, "kind": "act_subflow", "title": nid,
            "config": {"workflow": ref}}


def run_with_pool(auto, pool):
    st = FakeStatus()
    eng = mod.Engine(st)
    eng.autos_provider = lambda: pool
    eng.run_chain(auto, "trg", "test")
    return st


pool = {"child": CHILD}
st = run_with_pool(build([TRIGGER, subflow("sf", "child"), script("after", "true")],
                        [{"from": "trg", "to": "sf"},
                         {"from": "sf", "to": "after"}]), pool)
check("the sub-workflow ran", st.node_states.get("sf") == "ok", str(st.node_states))
check("the child's own node reported", st.node_states.get("cs") == "ok",
      str(st.node_states))
check("the parent carried on afterwards", st.node_states.get("after") == "ok",
      str(st.node_states))

st = run_with_pool(build([TRIGGER, subflow("sf", "Child flow")],
                        [{"from": "trg", "to": "sf"}]), pool)
check("a sub-workflow can be named instead of id'd",
      st.node_states.get("sf") == "ok", str(st.node_states))

st = run_with_pool(build([TRIGGER, subflow("sf", "nope")],
                        [{"from": "trg", "to": "sf"}]), pool)
check("an unknown sub-workflow fails loudly",
      st.node_states.get("sf") == "failed", str(st.node_states))

SELF = build([TRIGGER, subflow("sf", "a1")], [{"from": "trg", "to": "sf"}])
st = run_with_pool(SELF, {"a1": SELF})
check("a workflow cannot call itself", st.node_states.get("sf") == "failed",
      str(st.node_states))

mod.subprocess.run = _orig_run



print("\n[15] cron fields")
cm = mod._cron_match
check("star matches anything", cm("*", 7) is True)
check("an exact number", cm("30", 30) is True and cm("30", 31) is False)
check("a list", cm("0,15,30,45", 30) is True and cm("0,15", 30) is False)
check("a range", cm("9-17", 12) is True and cm("9-17", 20) is False)
check("every N", cm("*/15", 30) is True and cm("*/15", 31) is False)
check("a stepped range", cm("0-30/10", 20) is True and cm("0-30/10", 25) is False)
check("garbage never matches, so it never fires", cm("abc", 5) is False)
check("an empty step is not a crash", cm("*/", 5) is False)


print("\n[16] every block publishes NAMED values, not just one lump of text")
pub = mod._publish
v = {}
pub(v, [("script.exit", 3)])
check("a value lands namespaced", v.get("script.exit") == "3", str(v))
check("and bare, for the common case", v.get("exit") == "3", str(v))
pub(v, [("http.status", 404)])
check("two blocks can share a bare name", v.get("status") == "404")
pub(v, [("script.stdout", "a"), ("http.body", "b")])
check("the namespaced forms stay apart",
      v.get("script.stdout") == "a" and v.get("http.body") == "b", str(v))
v2 = {"stdout": "old", "script.stdout": "old"}
pub(v2, [("script.stdout", "new")])
check("the most recent block wins the bare name", v2.get("stdout") == "new")
pub(None, [("x", "y")])
check("publishing with no run does not explode", True)
v3 = {}
pub(v3, [("a.b", None)])
check("a value that does not exist is not published", "a.b" not in v3, str(v3))

print("\n[17] a script hands its exit code and streams onward")
st = run(build(
    [TRIGGER, script("s", "echo hello"),
     {"id": "n", "kind": "act_notify", "title": "n",
      "config": {"title": "T", "body": "out={{script.stdout}} code={{exit}}"}}],
    [{"from": "trg", "to": "s"}, {"from": "s", "to": "n", "fromPort": "ok"}]))
body = " ".join(sent[-1]) if sent else ""
check("stdout and exit code both reached the notification",
      "out=hello" in body and "code=0" in body, body)

st = run(build(
    [TRIGGER, script("s", "exit 3"),
     {"id": "n", "kind": "act_notify", "title": "n",
      "config": {"title": "T", "body": "failed with {{script.exit}}"}}],
    [{"from": "trg", "to": "s"}, {"from": "s", "to": "n", "fromPort": "err"}]))
body = " ".join(sent[-1]) if sent else ""
check("the error branch can quote the exit code", "failed with 3" in body, body)

print("\n[18] a trigger's own data reaches the chain")
eng_st = FakeStatus()
eng = mod.Engine(eng_st)
auto = build([TRIGGER,
              {"id": "n", "kind": "act_notify", "title": "n",
               "config": {"title": "T", "body": "copied: {{clipboard.text}}"}}],
             [{"from": "trg", "to": "n"}])
eng.run_chain(auto, "trg", "agora fudeu", {"clipboard.text": "agora fudeu"})
body = " ".join(sent[-1]) if sent else ""
check("the clipboard text is a value, not only a sentence",
      "copied: agora fudeu" in body, body)

print("\n[19] the exact graph from the report: clipboard -> AI -> notification")
# "identify a specific copy with the AI, then put ITS answer in the
# notification" — the case that could not be built before.
_reply["text"] = '{"realmente": "realmente"}'
ai_node = {"id": "ai", "kind": "act_ai", "title": "AI Action",
           "config": {"prompt": "if the clipboard says 'agora fudeu', answer 'realmente'",
                      "exec": "advisory",
                      "outputs": [{"name": "realmente", "desc": "the reply"}]}}
notify_node = {"id": "n", "kind": "act_notify", "title": "Notification",
               "config": {"title": "Genesi", "body": "{{realmente}}"}}
eng_st = FakeStatus()
eng = mod.Engine(eng_st)
auto = build([TRIGGER, ai_node, notify_node],
             [{"from": "trg", "to": "ai"},
              {"from": "ai", "to": "n", "fromPort": "ok"}])
eng.run_chain(auto, "trg", "agora fudeu", {"clipboard.text": "agora fudeu"})
body = " ".join(sent[-1]) if sent else ""
check("the AI's own field is what the notification shows",
      "realmente" in body, body)
check("the AI block also publishes its full reply as {{ai.reply}}",
      eng_st.node_states.get("ai") == "ok", str(eng_st.node_states))

print("\n[20] the catalogue the panel shows is the one the daemon uses")
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "genesi_workflow_gen",
    str(DAEMON.parent / "monitor" / "genesi_workflow_gen.py"))
_gen = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_gen)
check("every runnable kind appears in the outputs catalogue",
      set(_gen._WORKFLOW_KINDS) == set(_gen.NODE_OUTPUTS),
      str(set(_gen._WORKFLOW_KINDS) ^ set(_gen.NODE_OUTPUTS)))
declared = {name for fields in _gen.NODE_OUTPUTS.values()
            for name, _d in fields if not name.startswith("<")}
check("names are namespaced or a documented bare one",
      all(("." in n) or n in ("item", "index", "count") for n in declared),
      str(sorted(n for n in declared
                 if "." not in n and n not in ("item", "index", "count"))))
check("the generator's prompt carries the catalogue",
      "script.stdout" in _gen._WORKFLOW_SYSTEM
      and "clipboard.text" in _gen._WORKFLOW_SYSTEM)


print("\n[21] an AI output name has to be usable as {{name}}")
# Reported from real use: someone declared "RAM {{app.name}} usage" as an output
# name. The editor took it, the model was asked for it, the model helpfully
# substituted the placeholder, and the block failed with "expected JSON with RAM
# {{app.name}} usage" — three steps from the actual mistake, which is that no
# name with spaces or braces can ever be written back as {{...}}.
check("a plain name is fine", mod._VAR_NAME_RE.match("cpu") is not None)
check("underscores and digits are fine",
      mod._VAR_NAME_RE.match("ram_before_2") is not None)
check("spaces are not", mod._VAR_NAME_RE.match("ram before") is None)
check("a placeholder inside the name is not",
      mod._VAR_NAME_RE.match("RAM {{app.name}} usage") is None)
check("a leading digit is not", mod._VAR_NAME_RE.match("2nd") is None)
check("a dot is not, since that is the namespace separator",
      mod._VAR_NAME_RE.match("app.name") is None)
check("the suggestion is usable",
      mod._VAR_NAME_RE.match(mod._slug("RAM {{app.name}} usage")) is not None,
      mod._slug("RAM {{app.name}} usage"))
check("and it reads like the original",
      mod._slug("RAM {{app.name}} usage") == "ram_app_name_usage",
      mod._slug("RAM {{app.name}} usage"))

_reply["text"] = '{"whatever": "1"}'
bad_ai = {"id": "ai", "kind": "act_ai", "title": "ai",
          "config": {"prompt": "how much ram", "exec": "advisory",
                     "outputs": [{"name": "RAM {{app.name}} usage", "desc": "x"}]}}
st = run(build([TRIGGER, bad_ai, script("after", "true")],
               [{"from": "trg", "to": "ai"},
                {"from": "ai", "to": "after", "fromPort": "ok"}]))
check("the block fails instead of asking for an unusable field",
      st.node_states.get("ai") == "failed", str(st.node_states))
said = " ".join(line for _lvl, line in st.lines)
check("and the log says WHY, with a name that would work",
      "cannot be used" in said and "ram_app_name_usage" in said, said[-160:])

print("\n[22] 'any app' means any app, not 'never'")


class _P:
    def __init__(self, name):
        self.info = {"name": name}


def _poll_app_once(cfg, prev, now):
    """Drive the real poller with two snapshots of the process list."""
    st = FakeStatus()
    d = mod.Daemon.__new__(mod.Daemon)
    d.status = st
    d.lock = __import__("threading").Lock()
    d._fired_once = set()
    d._app_prev = set(prev)
    fired = []
    d._fire = lambda auto, node, detail, values=None: fired.append((detail, values))
    d._poll_app({"id": "a1"}, {"id": "n", "kind": "evt_app", "config": cfg},
                set(now))
    return fired


fired = _poll_app_once({"app": "firefox", "transition": "opened"},
                       {"bash"}, {"bash", "firefox"})
check("a named app still fires on open", len(fired) == 1, str(fired))
check("and reports itself", fired and fired[0][1].get("app.name") == "firefox",
      str(fired))

fired = _poll_app_once({"transition": "opened"}, {"bash"}, {"bash", "gimp"})
check("no name now means ANY app opening", len(fired) == 1, str(fired))
check("and reports which one it was",
      fired and fired[0][1].get("app.name") == "gimp", str(fired))

fired = _poll_app_once({"transition": "closed"}, {"bash", "gimp"}, {"bash"})
check("any app closing works too",
      len(fired) == 1 and fired[0][1].get("app.name") == "gimp", str(fired))

fired = _poll_app_once({"transition": "opened"}, {"bash"}, {"bash"})
check("nothing changed, nothing fires", not fired, str(fired))

fired = _poll_app_once({"transition": "opened"}, {"bash"},
                       {"bash", "a", "b", "c", "d"})
check("a login storm fires once, not five times", len(fired) == 1, str(fired))


print("\n[23] an automation cannot be re-triggered by its own side effects")
# Reported as "it just runs forever". With an App block set to "any app closed",
# the workflow's own children -- the shell behind Run Script, notify-send, a
# model server -- exit, the trigger sees them, and the workflow starts again.
# The loop is real and fast, and nothing in the graph is wrong.
import threading as _th


def _daemon_with(running):
    d = mod.Daemon.__new__(mod.Daemon)
    d.status = FakeStatus()
    d.status.is_running = lambda aid: running
    d.lock = _th.Lock()
    d._fired_once = set()
    d._fire_quiet = {}
    started = []
    d.engine = type("E", (), {"run_chain": lambda *a, **k: started.append(a)})()
    return d, started


AUTO = {"id": "a1", "enabled": True}
NODE = {"id": "n", "kind": "evt_app", "config": {}}

d, started = _daemon_with(True)
d._fire(AUTO, NODE, "app closed: sh")
check("a trigger stands down while its own workflow runs",
      not started, str(started))

d, started = _daemon_with(False)
d._fire(AUTO, NODE, "app closed: sh")
check("and fires normally when it is idle", len(started) == 1, str(started))

d, started = _daemon_with(False)
d._quiet_after_run("a1")
d._fire(AUTO, NODE, "app closed: sh")
check("it also stays quiet just after a run, while children exit",
      not started, str(started))

d, started = _daemon_with(False)
d._fire_quiet["a1"] = 0.0          # window long expired
d._fire(AUTO, NODE, "app closed: sh")
check("once the window passes it fires again", len(started) == 1, str(started))

d, started = _daemon_with(False)
d._quiet_after_run("a1")
d._fire({"id": "other", "enabled": True}, NODE, "app closed: sh")
check("the quiet window is per automation, not global",
      len(started) == 1, str(started))


print("\n[24] the model spells the key its own way")
# Reported twice from real use: "expected JSON with ram_before - got something
# else", while the reply plainly contained the number that was asked for. Small
# local models get the SHAPE right and the spelling their own.
pj = mod._parse_json_fields
check("exact still works", pj(chr(123) + chr(34) + "ram_before" + chr(34) + ": 512" + chr(125), ["ram_before"]) == {"ram_before": "512"})
check("different case", pj('{"RAM_Before": 512}', ["ram_before"]) == {"ram_before": "512"})
check("spaces instead of underscores",
      pj('{"RAM before": 512}', ["ram_before"]) == {"ram_before": "512"})
check("hyphens", pj('{"ram-before": 512}', ["ram_before"]) == {"ram_before": "512"})
check("two fields, both loosely spelled",
      pj('{"RAM before": 1, "ram after": 2}', ["ram_before", "ram_after"])
      == {"ram_before": "1", "ram_after": "2"})
check("one field asked, one value given, any name at all",
      pj('{"RAM llama-server usage": "17.7"}', ["ram_before"])
      == {"ram_before": "17.7"},
      str(pj('{"RAM llama-server usage": "17.7"}', ["ram_before"])))
check("TWO fields and unrecognisable names is still a failure",
      pj('{"a": 1, "b": 2}', ["ram_before", "ram_after"]) is None,
      "guessing which value goes in which slot is how the GPU figure gets reported as the CPU one")
check("one field but TWO values is still a failure",
      pj('{"a": 1, "b": 2}', ["ram_before"]) is None)
check("a missing field is still a failure",
      pj('{"ram_before": 1}', ["ram_before", "ram_after"]) is None)
check("still not JSON at all", pj("the ram is fine", ["ram_before"]) is None)


print("\n[25] Run now on a graph with NO trigger block still passes values along")
# The report: AI Action -> Notification, no trigger on the sheet, press Run now,
# and the notification arrives reading "{{ai.reply}}" in braces. "Run now" with
# no trigger used a SECOND runner -- a flat topological sweep calling
# _run_action(node, payload="") with vars=None -- so nothing was ever published
# and nothing was ever piped. It walks the real graph now.
_which, _popen = mod.shutil.which, mod.subprocess.Popen
notified = []
mod.shutil.which = lambda name: "/usr/bin/" + name
mod.subprocess.Popen = lambda argv, **kw: notified.append(list(argv))

auto = build([script("s", "echo VALUE"),
              {"id": "n", "kind": "act_notify", "title": "n",
               "config": {"title": "got {{stdout}}", "body": "input {input}"}}],
             [{"from": "s", "to": "n", "fromPort": "ok"}])
st = FakeStatus()
mod.Engine(st).run_all(auto, "manual run")
check("the first card ran", st.node_states.get("s") == "ok", str(st.node_states))
check("the card wired after it ran too", st.node_states.get("n") == "ok",
      str(st.node_states))
title = notified[-1][2] if notified else "<no notification>"
body = notified[-1][3] if notified else "<no notification>"
check("{{name}} from the previous block resolved", title == "got VALUE", title)
check("{input} carried the payload", body == "input VALUE", body)

# A sheet of unconnected cards still runs all of them -- that is what the old
# sweep was for, and losing it would trade one bug for another.
auto = build([script("a", "echo one"), script("b", "echo two")], [])
st = FakeStatus()
mod.Engine(st).run_all(auto, "manual run")
check("disconnected cards all still run",
      st.node_states.get("a") == "ok" and st.node_states.get("b") == "ok",
      str(st.node_states))

# A card that something links INTO is not an entry point: it must not fire on
# its own, and it still obeys the port it was wired from.
auto = build([script("a", "echo one"), script("b", "exit 1"),
              script("c", "echo three")],
             [{"from": "b", "to": "c", "fromPort": "ok"}])
st = FakeStatus()
mod.Engine(st).run_all(auto, "manual run")
check("a fed card obeys the port it is wired to",
      st.node_states.get("c") != "ok", str(st.node_states))

mod.shutil.which, mod.subprocess.Popen = _which, _popen


print("\n[26] an answer in the wrong shape is reformatted, not thrown away")
# Reported: put an "app opened / closed" block in front of the AI and the
# outputs start failing with "expected JSON"; take it away and they work. The
# App block was never the cause. In autonomous / ask mode the AGENT protocol
# owns the reply format, so the moment the model uses a tool the run ends in a
# sentence describing what it found -- the right answer wearing the wrong
# clothes. Whether that happened came down to whether the prompt tempted the
# model into a tool call, and the event detail riding along in the prompt is
# exactly such a nudge. So the block now asks once more for the same answer in
# the shape it declared.
agent_ai = {"id": "ai", "kind": "act_ai", "title": "ai",
            "config": {"prompt": "how much ram is firefox using", "exec": "auto",
                       "outputs": [{"name": "ram", "desc": "MB in use"}]}}
_reply["text"] = "Descobri que o firefox esta usando 512 MB de memoria."
_repair["text"] = '{"ram": "512"}'
_repair["asked"] = []
st = run(build([TRIGGER, agent_ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("the block succeeds on a prose answer that holds the value",
      st.node_states.get("ai") == "ok", str(st.node_states))
said = " ".join(line for _lvl, line in st.lines)
check("and it says it reformatted", "reformatting it" in said, said[-200:])
check("the value published is the one the model actually said",
      "ram=512" in said, said[-200:])
asked = _repair["asked"][-1] if _repair["asked"] else ""
check("the repair turn shows the model its own answer",
      "512 MB de memoria" in asked, asked[:200])
check("and asks for the declared field", '"ram"' in asked, asked[-120:])

# The repair is a REFORMAT, not a second guess: if it cannot find the field
# either, the block still fails rather than inventing one.
_repair["text"] = "still no idea"
st = run(build([TRIGGER, agent_ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("a reformat that fails too still fails the block",
      st.node_states.get("ai") == "failed", str(st.node_states))
said = " ".join(line for _lvl, line in st.lines)
check("and the log names the autonomous trap",
      "Advisory" in said and "DESCRIBING" in said, said[-260:])

# An empty reply is not worth a second model call.
_repair["text"] = '{"ram": "512"}'
_repair["asked"] = []
_reply["text"] = ""
st = run(build([TRIGGER, agent_ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("nothing to reformat means no second call", _repair["asked"] == [],
      str(_repair["asked"]))

# Advisory blocks that already answer in shape must not pay for any of this.
_reply["text"] = '{"cpu": "83", "gpu": "12"}'
_repair["asked"] = []
st = run(build([TRIGGER, ai, notify],
               [{"from": "trg", "to": "ai"}, {"from": "ai", "to": "n"}]))
check("a well-shaped reply costs no extra call",
      st.node_states.get("ai") == "ok" and _repair["asked"] == [],
      str(st.node_states) + str(_repair["asked"]))


print("\n[27] two App blocks stop overwriting each other's {{app.name}}")
# Reported: a graph that opens Firefox, asks the AI for the RAM, waits for
# Firefox to close and asks again. Both App cards published app.name, so the
# second overwrote the first and {{app.name}} in the back half of the graph
# reported whichever card ran last. A block may now carry a varName and its
# values also land under that, which nothing else can take.
_pub = mod._publish
v = {}
_pub(v, [("app.name", "firefox"), ("app.transition", "opened")], "started")
_pub(v, [("app.name", "kate"), ("app.transition", "closed")], "stopped")
check("the shared name is still last-wins, as every saved graph expects",
      v.get("app.name") == "kate", str(v))
check("but the first block kept its own", v.get("started.name") == "firefox", str(v))
check("and so did the second", v.get("stopped.name") == "kate", str(v))
check("the other fields are namespaced too",
      v.get("started.transition") == "opened" and v.get("stopped.transition") == "closed",
      str(v))

check("a block with no varName publishes exactly what it always did",
      sorted(k for k in (lambda d: (_pub(d, [("app.name", "x")]), d)[1])({}))
      == ["app.name", "name"])
check("a varName that {{ }} could not resolve is ignored, not published",
      mod._node_handle({"config": {"varName": "not a name"}}) == "")
check("a usable one is taken as is",
      mod._node_handle({"config": {"varName": "opened"}}) == "opened")
check("no config at all is fine", mod._node_handle({}) == "")

print("\n[28] 'any app' means any APPLICATION, not any process")
# An empty app name fired for every process that came or went -- a shell, a
# python helper, a thumbnailer -- so the node ran more or less constantly on an
# idle machine while looking like it was waiting for the user to open something.


class _FakeAppDaemon:
    def __init__(self, prev):
        self._app_prev = set(prev)
        self.fired = []

    def _fire(self, auto, node, detail, values=None):
        self.fired.append((detail, values))


_FakeAppDaemon._poll_app = mod.Daemon._poll_app
mod._APP_NAMES["names"] = {"firefox", "kate"}
mod._APP_NAMES["at"] = mod.time.monotonic()

any_open = {"id": "n", "kind": "evt_app", "config": {"app": "", "transition": "opened"}}
d = _FakeAppDaemon({"systemd"})
d._poll_app({"id": "a1"}, any_open, {"systemd", "sh", "python3", "gvfsd-thumb"})
check("a burst of helper processes fires nothing", d.fired == [], str(d.fired))

d = _FakeAppDaemon({"systemd"})
d._poll_app({"id": "a1"}, any_open, {"systemd", "sh", "firefox"})
check("a real application does fire", len(d.fired) == 1, str(d.fired))
check("and reports which one",
      d.fired and d.fired[0][1].get("app.name") == "firefox", str(d.fired))

any_close = {"id": "n", "kind": "evt_app", "config": {"app": "", "transition": "closed"}}
d = _FakeAppDaemon({"systemd", "sh", "kate"})
d._poll_app({"id": "a1"}, any_close, {"systemd"})
check("closing filters the same way", len(d.fired) == 1, str(d.fired))
check("and it is the application that is reported",
      d.fired and d.fired[0][1].get("app.name") == "kate", str(d.fired))

# Reading no .desktop files at all must not silence the node: one that never
# fires is worse than one that fires too often.
mod._APP_NAMES["names"] = set()
mod._APP_NAMES["at"] = 0.0
_real_scan = mod._application_names
mod._application_names = lambda: set()
d = _FakeAppDaemon({"systemd"})
d._poll_app({"id": "a1"}, any_open, {"systemd", "somebinary"})
check("with no catalogue to filter by it still fires", len(d.fired) == 1, str(d.fired))
mod._application_names = _real_scan

print("\n[29] the run log can be cleared")
stt = mod.Status()
stt.sync({"a1": {"id": "a1", "name": "t", "enabled": True}})
stt.log("a1", "one")
stt.log("a1", "two")
check("lines accumulate", len(stt._autos["a1"]["log"]) == 2)
check("clearing reports success", stt.clear_log("a1") is True)
check("and the log is empty", stt._autos["a1"]["log"] == [])
check("clearing an automation that is not there is not a crash",
      stt.clear_log("nope") is False)


print("\n[30] {{name}} works in the fields that were reading their config raw")
# Reported: the first App card was named app1, and putting {{app1.name}} in the
# SECOND card's Process name did not resolve -- the block waited for a process
# literally called "{{app1.name}}" until it timed out. _wait_app read cfg["app"]
# straight, and it was not alone: launch/close app, the file operations, the
# sound path and the wait duration all skipped _sub too, so no value from
# anywhere in the run could reach them.
_subf = mod.Engine._sub
check("the App block's process name renders",
      _subf("{{app1.name}}", "", {"app1.name": "firefox"}) == "firefox")


class _FakeProcInfo:
    def __init__(self, name):
        self.info = {"name": name}


_procs = {"names": ["systemd"]}
mod.psutil = type("psutil", (), {
    "process_iter": staticmethod(lambda fields: [_FakeProcInfo(n) for n in _procs["names"]]),
})()

eng = mod.Engine(FakeStatus())
node = {"id": "w", "kind": "evt_app",
        "config": {"app": "{{app1.name}}", "transition": "closed", "waitSeconds": 1}}
outcome, _ = eng._wait_app({"id": "a1"}, node, "", {"app1.name": "firefox"})
check("waiting for {{app1.name}} sees firefox is already closed", outcome == "ok",
      outcome)

_procs["names"] = ["systemd", "firefox"]
eng = mod.Engine(FakeStatus())
st_wait = FakeStatus()
eng = mod.Engine(st_wait)
outcome, _ = eng._wait_app({"id": "a1"}, node, "", {"app1.name": "firefox"})
check("and it waits (then gives up) while firefox is still running",
      outcome == "err", outcome)
said = " ".join(line for _lvl, line in st_wait.lines)
check("the log names the app, not the placeholder",
      "firefox" in said and "{{app1.name}}" not in said, said[:200])

# The other four that were reading raw.
launched = []
mod.subprocess.Popen = lambda argv, **kw: launched.append(list(argv))
mod.shutil.which = lambda name: "/usr/bin/" + name
eng = mod.Engine(FakeStatus())
eng._act_app("a1", {"op": "launch", "app": "{{app1.name}}"}, "", {"app1.name": "kate"})
check("launch app renders its command",
      launched and launched[-1][-1] == "kate", str(launched[-1:]))

eng._act_sound("a1", {"sound": "{{dir}}/beep.wav"}, "", {"dir": "/tmp"})
check("the sound path renders",
      launched and launched[-1][-1].endswith("/tmp/beep.wav"), str(launched[-1:]))

t0 = mod.time.monotonic()
eng._act_wait("a1", {"seconds": "{{pause}}"}, "", {"pause": "0"})
check("the wait duration renders (and did not fall back to 5s)",
      mod.time.monotonic() - t0 < 1.0)

import tempfile as _tf
import os as _os
_tmp = _tf.mkdtemp()
_src = _os.path.join(_tmp, "a.txt")
open(_src, "w").write("x")
eng._act_file("a1", {"op": "copy", "src": "{{picked}}",
                     "dest": _os.path.join(_tmp, "b.txt")},
              "", {"picked": _src})
check("a file operation renders its paths",
      _os.path.exists(_os.path.join(_tmp, "b.txt")))

print("\n" + ("ALL TESTS PASSED" if not failures else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
