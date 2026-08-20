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

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
