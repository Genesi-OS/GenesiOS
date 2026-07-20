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

print("\n" + ("ALL TESTS PASSED" if not failures else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
