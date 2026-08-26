"""Tests for the AI workflow generator's validator.

The model is not tested here — it cannot be, and that is exactly the point.
What IS tested is everything that stands between a model's answer and a graph
the user is shown, because a workflow is a program: a node kind the model
invented would draw perfectly on the canvas and then silently never run, and the
person looking at it would have no way to tell those two apart.

No PySide6, no model, no network: genesi_workflow_gen is deliberately Qt-free.
"""
import importlib.util
import sys
from pathlib import Path

MOD = (Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode"
       / "monitor" / "genesi_workflow_gen.py")
spec = importlib.util.spec_from_file_location("genesi_workflow_gen", MOD)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

failures = []


def check(name, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ") + name + (("  — " + detail) if detail and not ok else ""))
    if not ok:
        failures.append(name)


print("\n[1] the catalogue the model writes against")
check("every kind the daemon runs is offered",
      {"act_cond", "act_loop", "act_subflow", "act_email", "evt_webhook",
       "evt_clipboard", "evt_screenshot"} <= set(gen._WORKFLOW_KINDS))
check("the prompt lists them all",
      all(k in gen._WORKFLOW_SYSTEM for k in gen._WORKFLOW_KINDS))
check("the placeholder was rendered", "__KINDS__" not in gen._WORKFLOW_SYSTEM)
check("every kind has an icon",
      all(k in gen._ICON_FOR_KIND for k in gen._WORKFLOW_KINDS),
      str(set(gen._WORKFLOW_KINDS) - set(gen._ICON_FOR_KIND)))

print("\n[2] finding the JSON in whatever the model actually said")
fj = gen._first_json_object
check("a plain object", fj('{"a": 1}') == {"a": 1})
check("inside a fence", fj('```json\n{"a": 1}\n```') == {"a": 1})
check("after an apology", fj('Sure thing!\n{"a": 1}') == {"a": 1})
check("nested braces", fj('{"a": {"b": 2}}') == {"a": {"b": 2}})
check("no JSON at all", fj("I cannot do that") is None)
check("an array is not a workflow", fj("[1, 2]") is None)
check("truncated JSON", fj('{"a": ') is None)
check("empty", fj("") is None)

print("\n[3] a good answer survives intact")
good = {
    "name": "Warn me when the PC is hot",
    "nodes": [
        {"id": "t", "kind": "evt_resource", "title": "CPU high",
         "config": {"metric": "cpu", "op": ">", "threshold": "90"}},
        {"id": "a", "kind": "act_ai", "title": "Look",
         "config": {"prompt": "what is using the cpu",
                    "outputs": [{"name": "top", "desc": "the busiest process"}]}},
        {"id": "c", "kind": "act_cond", "title": "Bad?",
         "config": {"mode": "expr", "expr": "{{top}} contains chrome"}},
        {"id": "n", "kind": "act_notify", "title": "Tell me",
         "config": {"title": "Hot", "body": "{{top}} is eating the CPU"}},
    ],
    "links": [{"from": "t", "to": "a"},
              {"from": "a", "to": "c", "fromPort": "ok"},
              {"from": "c", "to": "n", "fromPort": "true"}],
}
graph, dropped = gen._sanitise_graph(good)
check("all four nodes kept", len(graph["nodes"]) == 4, str(len(graph["nodes"])))
check("nothing dropped", not dropped, str(dropped))
check("ports preserved",
      [l["fromPort"] for l in graph["links"]] == ["", "ok", "true"],
      str(graph["links"]))
check("declared outputs survive",
      graph["nodes"][1]["config"]["outputs"] == [{"name": "top", "desc": "the busiest process"}])
check("icons were assigned", graph["nodes"][2]["icon"] == "git-branch")
check("nodes were laid out, not left on top of each other",
      len({(n["x"], n["y"]) for n in graph["nodes"]}) == 4)

print("\n[4] an invented node kind is dropped and REPORTED")
graph, dropped = gen._sanitise_graph({
    "nodes": [{"id": "t", "kind": "evt_manual", "config": {}},
              {"id": "x", "kind": "act_send_sms", "config": {"to": "+55"}},
              {"id": "n", "kind": "act_notify", "config": {"body": "hi"}}],
    "links": [{"from": "t", "to": "x"}, {"from": "x", "to": "n"}]})
check("the made-up kind is gone",
      [n["kind"] for n in graph["nodes"]] == ["evt_manual", "act_notify"],
      str([n["kind"] for n in graph["nodes"]]))
check("and it is named so the user is told", dropped == {"act_send_sms"},
      str(dropped))
check("links to a dropped node go with it", graph["links"] == [],
      str(graph["links"]))

print("\n[5] invented FIELDS are dropped too")
graph, _ = gen._sanitise_graph({
    "nodes": [{"id": "n", "kind": "act_notify",
               "config": {"body": "hi", "urgency": "critical", "sound": True}}],
    "links": []})
check("only real fields are kept", graph["nodes"][0]["config"] == {"body": "hi"},
      str(graph["nodes"][0]["config"]))

print("\n[6] structurally broken answers cannot produce a broken graph")
graph, _ = gen._sanitise_graph({"nodes": "not a list"})
check("nodes must be a list", graph["nodes"] == [])
graph, _ = gen._sanitise_graph({"nodes": [{"id": "a", "kind": "evt_manual"},
                                          {"id": "a", "kind": "act_notify"}],
                                "links": []})
check("a duplicate id is refused", len(graph["nodes"]) == 1)
graph, _ = gen._sanitise_graph({
    "nodes": [{"id": "a", "kind": "evt_manual"}],
    "links": [{"from": "a", "to": "ghost"}, {"from": "a", "to": "a"}]})
check("a link to a node that does not exist is dropped", graph["links"] == [],
      str(graph["links"]))
check("a node cannot link to itself", graph["links"] == [])
graph, _ = gen._sanitise_graph({
    "nodes": [{"id": "a", "kind": "evt_manual"}, {"id": "b", "kind": "act_notify"}],
    "links": [{"from": "a", "to": "b", "fromPort": "sideways"}]})
check("an unknown port becomes the default one",
      graph["links"][0]["fromPort"] == "", str(graph["links"]))
graph, _ = gen._sanitise_graph({
    "nodes": [{"id": "a", "kind": "evt_manual"}, {"id": "b", "kind": "act_notify"}],
    "links": [{"from": "a", "to": "b"}, {"from": "a", "to": "b"}]})
check("a duplicated link is collapsed", len(graph["links"]) == 1)

print("\n[7] runaway answers are bounded")
many = {"nodes": [{"id": "n%d" % i, "kind": "act_notify", "config": {}}
                  for i in range(200)], "links": []}
graph, _ = gen._sanitise_graph(many)
check("a 200-node answer is capped", len(graph["nodes"]) <= 24,
      str(len(graph["nodes"])))
outs = {"nodes": [{"id": "a", "kind": "act_ai", "config": {
    "outputs": [{"name": "f%d" % i} for i in range(30)]}}], "links": []}
graph, _ = gen._sanitise_graph(outs)
check("an absurd output list is capped",
      len(graph["nodes"][0]["config"]["outputs"]) <= 6)
graph, _ = gen._sanitise_graph({"nodes": [{"id": "a", "kind": "act_ai", "config": {
    "outputs": [{"desc": "no name"}, {"name": "  "}]}}], "links": []})
check("an output with no name is not a field",
      "outputs" not in graph["nodes"][0]["config"],
      str(graph["nodes"][0]["config"]))

print("\n[8] the prompt insists on the two things that make it trustworthy")
check("it forbids inventing kinds", "Never invent" in gen._WORKFLOW_SYSTEM)
check("it requires admitting what it cannot build",
      "cannot" in gen._WORKFLOW_SYSTEM and "closest" in gen._WORKFLOW_SYSTEM)
check("it explains the true/false ports", "true" in gen._WORKFLOW_SYSTEM
      and "false" in gen._WORKFLOW_SYSTEM)
check("it explains named outputs", "{{cpu}}" in gen._WORKFLOW_SYSTEM)


print("\nthe catalogue, the panel and the daemon agree on every field")
# Three classes of bug kept arriving as "the block looks configured and does
# nothing", and all three are a NAME disagreeing across the three files that
# have to spell it identically: the panel writes it, the daemon reads it, the
# catalogue tells the model about it. act_file said "source" where the other
# two say "src"; act_app and act_power said "action" where both say "op";
# evt_command said "pattern" where both say "match", and forgot "interval"
# outright. The validator drops any key not in the catalogue, so each one meant
# a generated block carried the wrong name or none at all. Read all three.
import ast as _ast
import re as _re

_PKG = Path(__file__).resolve().parents[1] / "packages" / "genesi-ai-mode"
_tree = _ast.parse((_PKG / "genesi-automationd").read_text(encoding="utf-8"))
_funcs = {}
for _n in _ast.walk(_tree):
    if isinstance(_n, _ast.FunctionDef):
        _funcs.setdefault(_n.name, []).append(_n)


def _cfg_keys(names):
    """Config keys read inside these functions, however the dict was reached."""
    found = set()
    for name in names:
        for fn in _funcs.get(name, []):
            for node in _ast.walk(fn):
                if not (isinstance(node, _ast.Call)
                        and isinstance(node.func, _ast.Attribute)
                        and node.func.attr == "get" and node.args
                        and isinstance(node.args[0], _ast.Constant)
                        and isinstance(node.args[0].value, str)):
                    continue
                # cfg.get("x"), and also node.get("config", {}).get("x") --
                # the hotkey registry reads it the second way.
                recv = _ast.unparse(node.func.value)
                if "cfg" in recv or "config" in recv:
                    found.add(node.args[0].value)
    return found


def _published(names):
    """Value names handed to _fire / _edge_fire / _publish in these functions."""
    out = set()
    for name in names:
        for fn in _funcs.get(name, []):
            for node in _ast.walk(fn):
                if not isinstance(node, _ast.Call):
                    continue
                fname = (node.func.attr if isinstance(node.func, _ast.Attribute)
                         else getattr(node.func, "id", ""))
                if fname not in ("_fire", "_edge_fire", "_publish"):
                    continue
                for arg in list(node.args) + [k.value for k in node.keywords]:
                    for sub in _ast.walk(arg):
                        if isinstance(sub, _ast.Dict):
                            for k in sub.keys:
                                if isinstance(k, _ast.Constant):
                                    out.add(k.value)
                        elif isinstance(sub, (_ast.Tuple, _ast.List)):
                            for el in sub.elts:
                                if (isinstance(el, _ast.Tuple) and el.elts
                                        and isinstance(el.elts[0], _ast.Constant)):
                                    out.add(el.elts[0].value)
    return out


# kind -> the daemon functions that handle it. Keeping this by hand is the
# price of the check; a wrong entry shows up as a failure, not as silence.
_HANDLERS = {
    "evt_fs": ("_on_fs_event", "_rearm"),
    "evt_resource": ("_poll_resource",),
    "evt_app": ("_poll_app", "_wait_app"),
    "evt_process": ("_poll_process",),
    "evt_power": ("_poll_power",),
    "evt_disk": ("_poll_disk",),
    "evt_usb": ("_poll_usb",),
    "evt_network": ("_poll_network",),
    "evt_bluetooth": ("_poll_bluetooth",),
    "evt_idle": ("_poll_idle",),
    "evt_temperature": ("_poll_temp",),
    "evt_log": ("_poll_log",),
    "evt_command": ("_poll_command", "_cond_command"),
    "evt_clipboard": ("_poll_clipboard",),
    "evt_screenshot": ("_poll_screenshot", "_shot_dir"),
    "evt_schedule": ("_poll_schedule", "_poll_cron"),
    "evt_hotkey": ("_rearm", "_on_combo"),
    "evt_webhook": ("_webhook_routes", "_webhook_sync"),
    "evt_startup": ("_fire_startup",),
    "evt_manual": (),
    "act_script": ("_act_script",),
    "act_ai": ("_act_ai",),
    # _act_cond copies its whole cfg into _act_ai for "ai" mode, so its model /
    # turbo keys are read there rather than in its own body.
    "act_cond": ("_act_cond", "_act_ai"),
    "act_loop": ("_act_loop", "_loop_items"),
    "act_subflow": ("_act_subflow",),
    "act_notify": ("_act_notify",),
    "act_email": ("_act_email",),
    "act_http": ("_act_http",),
    "act_file": ("_act_file",),
    "act_app": ("_act_app",),
    "act_sound": ("_act_sound",),
    "act_wait": ("_act_wait",),
    "act_power": ("_act_power",),
}
# Read by _handle(cfg), not in any executor: the block's own value prefix.
_INDIRECT = {"varName"}

for _kind, _fns in sorted(_HANDLERS.items()):
    _ghost = sorted(set(gen._WORKFLOW_KINDS[_kind]) - _INDIRECT - _cfg_keys(_fns))
    check("%s: the catalogue names only fields the daemon reads" % _kind,
          not _ghost, "nothing reads " + ", ".join(repr(g) for g in _ghost))

# The panel is the third speller of the same names.
_panel = (_PKG / "monitor/AutomationConfigPanel.qml").read_text(encoding="utf-8")
_section, _panel_keys, _order = None, {}, []
for _line in _panel.split("\n"):
    _m = _re.search(r"//\s*[-─]+\s*(evt_\w+|act_\w+)\s*[-─]+", _line)
    if _m:
        _section = _m.group(1)
        if _section not in _panel_keys:
            _panel_keys[_section] = set()
            _order.append(_section)
        continue
    if _section:
        for _k in _re.findall(r'setConfig\("(\w+)"', _line):
            _panel_keys[_section].add(_k)
# All but the LAST section: nothing closes it, so every stray setConfig further
# down the file (the shared Fire-when row, the JS helpers) lands in it.
for _kind in _order[:-1]:
    if _kind not in _HANDLERS:
        continue
    _ghost = sorted(_panel_keys[_kind] - _cfg_keys(_HANDLERS[_kind]) - _INDIRECT)
    check("%s: the panel writes only fields the daemon reads" % _kind,
          not _ghost, "nothing reads " + ", ".join(repr(g) for g in _ghost))

print("\nevery value the panel offers actually exists at run time")
# "Values you can use here" listed {{process.name}}, {{command.output}},
# {{file.dest}} and {{app.name}} for blocks that never published them, so
# writing one into the next block rendered it as its own braces -- the exact
# shape of the {{ai.reply}} report, one layer down.
for _kind, _fields in sorted(gen.NODE_OUTPUTS.items()):
    _fns = _HANDLERS.get(_kind)
    if not _fns:
        continue
    _missing = [f for f, _d in _fields
                if not f.startswith("<") and f not in _published(_fns)]
    check("%s publishes everything it advertises" % _kind, not _missing,
          "promised but never published: " + ", ".join(_missing))

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
