#!/usr/bin/env python3
"""
Genesi Automations — turning a sentence into a workflow graph.

Deliberately Qt-free, the same way genesi_turbo_ctl.py is: the interesting part
of "generate my workflow" is the CATALOGUE and the validation, and both have to
be testable without a display server, a model or PySide6 installed.

The catalogue is the contract the model writes against. It is spelled out in
full — every kind, every field — because a graph is a program: a node kind the
model invented would draw perfectly on the canvas and then never run, and the
user would have no way to tell which of the two had happened.
"""

import json
import re

# ── Building a workflow from a sentence ─────────────────────────────────────
#
# The catalogue below is the contract the model writes against. It is spelled
# out in full — every kind, every field — because a graph is a program: a node
# kind the model invented would draw perfectly on the canvas and then never run,
# and the user would have no way to tell which of the two happened.

_WORKFLOW_KINDS = {
    # trigger kind        -> the config fields it understands
    "evt_manual":      [],
    "evt_schedule":    ["interval", "time", "cron"],
    "evt_fs":          ["path", "pattern", "change", "recursive"],
    "evt_resource":    ["metric", "op", "threshold"],
    "evt_temperature": ["threshold", "sensor"],
    # varName: this block's own prefix for the values it publishes, so two App
    # blocks on one sheet do not overwrite each other's {{app.name}}.
    "evt_app":         ["app", "transition", "varName", "waitSeconds"],
    "evt_process":     ["app", "metric", "threshold"],
    "evt_power":       ["event", "level"],
    "evt_disk":        ["event", "path", "threshold"],
    "evt_usb":         ["action"],
    "evt_network":     ["event", "iface"],
    "evt_bluetooth":   ["action", "name"],
    "evt_idle":        ["event", "minutes"],
    "evt_hotkey":      ["combo"],
    "evt_startup":     [],
    "evt_log":         ["path", "pattern"],
    "evt_command":     ["command", "on", "pattern"],
    "evt_clipboard":   ["contains", "onlyUrl"],
    "evt_screenshot":  ["path"],
    "evt_webhook":     ["path", "port", "token", "bindAll"],
    # action kind
    "act_script":      ["command", "terminal"],
    "act_ai":          ["prompt", "model", "exec", "outputs", "turbo", "aiMode"],
    "act_cond":        ["mode", "expr", "prompt", "model"],
    "act_loop":        ["source", "list", "from", "to", "max"],
    "act_subflow":     ["workflow"],
    "act_notify":      ["title", "body"],
    "act_email":       ["mode", "account", "host", "port", "user", "to",
                        "subject", "body", "folder", "limit"],
    "act_http":        ["url", "method", "body"],
    # src/dest, NOT source: these are the keys the panel writes and the
    # daemon reads. A generated block using "source" had the key dropped by
    # the validator below and copied nothing, silently.
    "act_file":        ["op", "src", "dest"],
    "act_app":         ["app", "op"],
    "act_sound":       ["sound"],
    "act_wait":        ["seconds"],
    "act_power":       ["op"],
}


# ── What each block HANDS TO the blocks after it ────────────────────────────
#
# The flow of control was never the hard part: a link says what runs next, and
# that worked. The hard part is the flow of DATA, and until now there was one
# channel for it — {input}, the previous block's entire output as a single
# string. That is enough to pipe a script into a notification and nothing more.
# You could not take the number out of it, and with three blocks on a canvas
# there was no way to even find out what a block had to offer.
#
# So every kind now publishes NAMED values, and this table is the single place
# that says which. It is read by three things that would otherwise drift apart:
#   * the daemon, which publishes them at run time,
#   * the config panel, which shows the user what is available to use, and
#   * the workflow generator's prompt, so a generated graph wires real names
#     instead of names a model imagined.
#
# Values are published twice: bare ({{text}}) and namespaced ({{clipboard.text}}).
# The bare form is what a person writes when there is one obvious source, which
# is most graphs; the namespaced form is how you disambiguate when there are two
# scripts and you mean the first one's exit code. When two blocks publish the
# same bare name, the most recent one along the path wins — "the one that just
# ran" is the only reading of {{stdout}} that is ever surprising to nobody.
NODE_OUTPUTS = {
    # ── triggers ──
    "evt_clipboard":   [("clipboard.text", "the text that was copied")],
    "evt_screenshot":  [("screenshot.path", "full path of the new image"),
                        ("screenshot.name", "just the file name")],
    "evt_fs":          [("file.path", "the file that changed"),
                        ("file.name", "just the file name"),
                        ("file.change", "created, modified or deleted")],
    "evt_resource":    [("resource.metric", "cpu or ram"),
                        ("resource.value", "the reading, as a number")],
    "evt_temperature": [("temp.value", "degrees Celsius, as a number"),
                        ("temp.sensor", "which sensor reported it")],
    "evt_app":         [("app.name", "the application"),
                        ("app.transition", "opened or closed")],
    "evt_process":     [("process.name", "the process"),
                        ("process.metric", "cpu or mem"),
                        ("process.value", "the reading, as a number")],
    "evt_power":       [("power.event", "what happened"),
                        ("power.level", "battery percentage, as a number")],
    "evt_disk":        [("disk.path", "the mount point or device"),
                        ("disk.value", "percent used, as a number")],
    "evt_usb":         [("usb.action", "added or removed"),
                        ("usb.device", "what was plugged in")],
    "evt_network":     [("network.event", "what happened"),
                        ("network.iface", "the interface")],
    "evt_bluetooth":   [("bt.action", "connected or disconnected"),
                        ("bt.device", "the device")],
    "evt_idle":        [("idle.minutes", "how long you were idle, as a number")],
    "evt_hotkey":      [("hotkey.combo", "the keys you pressed")],
    "evt_schedule":    [("schedule.at", "the time it fired")],
    "evt_startup":     [],
    "evt_log":         [("log.line", "the matching line"),
                        ("log.path", "the file it came from")],
    "evt_command":     [("command.output", "what the command printed")],
    "evt_webhook":     [("webhook.body", "the request body"),
                        ("webhook.path", "the endpoint that was called")],
    "evt_manual":      [],
    # ── actions ──
    "act_script":      [("script.stdout", "everything it printed"),
                        ("script.stderr", "everything it printed to stderr"),
                        ("script.exit", "the exit code, as a number")],
    "act_ai":          [("ai.reply", "the model's answer in full"),
                        ("<your outputs>", "one value per field you declare below")],
    "act_cond":        [("cond.answer", "true or false")],
    "act_loop":        [("item", "the current item, inside the loop body"),
                        ("index", "its position, starting at 0"),
                        ("count", "how many items there are")],
    "act_subflow":     [("<the sub-workflow's values>",
                         "everything the workflow you called published")],
    "act_notify":      [],
    "act_email":       [("mail.from", "sender of the newest message"),
                        ("mail.subject", "its subject"),
                        ("mail.body", "its text"),
                        ("mail.count", "how many were read")],
    "act_http":        [("http.status", "the HTTP status code, as a number"),
                        ("http.body", "the response body")],
    "act_file":        [("file.dest", "where the file ended up")],
    "act_app":         [("app.name", "the application acted on")],
    "act_sound":       [],
    "act_wait":        [],
    "act_power":       [],
}


def outputs_for(kind):
    """The named values a kind publishes, as [(name, description)]."""
    return list(NODE_OUTPUTS.get(kind, []))


def outputs_catalogue_text():
    """The same table, for the generator's prompt."""
    lines = []
    for kind in sorted(NODE_OUTPUTS):
        fields = NODE_OUTPUTS[kind]
        if not fields:
            continue
        lines.append("  %-16s %s" % (kind, ", ".join(name for name, _ in fields)))
    return chr(10).join(lines)

_WORKFLOW_SYSTEM = """You design automation workflows for Genesi OS and reply with ONE JSON object, nothing else. No prose, no markdown fence.

{"name": "short title", "cannot": "", "nodes": [...], "links": [...]}

A node: {"id": "n1", "kind": "<kind>", "title": "Short label", "config": {...}}
A link: {"from": "n1", "to": "n2", "fromPort": ""}

RULES
1. Exactly one trigger (a kind starting with evt_), and it must be the first node. Everything else is an action (act_).
2. Use ONLY the kinds and config fields listed below. Never invent a kind or a field. If the request needs something not on the list, build the closest workflow you can AND explain the gap in "cannot".
3. Values flow forward. {input} is the previous block's whole output. To pass named values, give act_ai an "outputs" list like [{"name":"cpu","desc":"cpu load %"}] — later blocks then use {{cpu}} in any text field.
4. act_cond has two ports: fromPort "true" and fromPort "false". Its "mode" is "expr" (with "expr", e.g. "{{cpu}} > 80") or "ai" (with "prompt", a yes/no question).
5. act_script, act_ai, act_http and act_file have ports "ok" and "err". act_loop has "each" (the body, once per item) and "done" (afterwards). Everything else uses fromPort "".
6. Lay the nodes out left to right in the order they run. Do not include x/y.
7. Prefer few blocks. Three that work beat eight that look thorough.

KINDS AND THEIR CONFIG FIELDS
__KINDS__

VALUES EACH KIND PUBLISHES, usable as {{name}} in any later block
__OUTPUTS__

If the request is impossible or unclear, still return valid JSON: put your explanation in "cannot" and give the nearest workflow you CAN build. An empty "nodes" list is only for a request that is not an automation at all."""


def _first_json_object(text):
    """The first balanced {...} in a model reply, parsed, or None."""
    text = (text or "").strip()
    fence = re.match(r"^```[a-zA-Z]*\s*(.*?)\s*```$", text, re.S)
    if fence:
        text = fence.group(1).strip()
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                try:
                    obj = json.loads(text[start:i + 1])
                except ValueError:
                    return None
                return obj if isinstance(obj, dict) else None
    return None


_ICON_FOR_KIND = {
    "evt_manual": "play", "evt_schedule": "clock", "evt_fs": "folder",
    "evt_resource": "cpu", "evt_temperature": "alert", "evt_app": "box",
    "evt_process": "sliders", "evt_power": "bolt", "evt_disk": "database",
    "evt_usb": "archive", "evt_network": "globe", "evt_bluetooth": "link",
    "evt_idle": "user", "evt_hotkey": "terminal", "evt_startup": "rocket",
    "evt_log": "file-text", "evt_command": "search", "evt_clipboard": "copy",
    "evt_screenshot": "image", "evt_webhook": "cloud",
    "act_script": "terminal", "act_ai": "bot", "act_cond": "git-branch",
    "act_loop": "refresh-cw", "act_subflow": "layers", "act_notify": "alert",
    "act_email": "mail", "act_http": "cloud", "act_file": "copy",
    "act_app": "external-link", "act_sound": "bolt", "act_wait": "clock",
    "act_power": "lock",
}
_ACCENT_FOR_KIND = {
    "act_ai": "turbo", "act_cond": "turbo", "act_loop": "purple",
    "act_subflow": "blue", "act_script": "purple", "act_http": "blue",
    "act_power": "red", "act_email": "green",
}


def _sanitise_graph(obj):
    """Keep only what is really a node, a field and a link.

    Returns (graph, dropped_kind_names). Everything the model invented is
    reported rather than silently discarded, so the user is told what was left
    out instead of finding a hole in their workflow next week.
    """
    dropped = set()
    nodes, ids = [], {}
    raw_nodes = obj.get("nodes")
    if not isinstance(raw_nodes, list):
        return {"nodes": [], "links": []}, dropped

    col, row = 120, 120
    for raw in raw_nodes[:24]:
        if not isinstance(raw, dict):
            continue
        kind = str(raw.get("kind") or "").strip()
        if kind not in _WORKFLOW_KINDS:
            if kind:
                dropped.add(kind)
            continue
        nid = str(raw.get("id") or "").strip() or ("n%d" % (len(nodes) + 1))
        if nid in ids:
            continue
        allowed = _WORKFLOW_KINDS[kind]
        cfg_in = raw.get("config") if isinstance(raw.get("config"), dict) else {}
        cfg = {}
        for key, value in cfg_in.items():
            if key not in allowed:
                continue
            if key == "outputs":
                rows = []
                for item in (value if isinstance(value, list) else [])[:6]:
                    if isinstance(item, dict) and str(item.get("name") or "").strip():
                        rows.append({"name": str(item["name"]).strip(),
                                     "desc": str(item.get("desc") or "").strip()})
                if rows:
                    cfg["outputs"] = rows
                continue
            if isinstance(value, bool):
                cfg[key] = value
            elif isinstance(value, (int, float, str)):
                cfg[key] = value if isinstance(value, bool) else str(value)
        ids[nid] = True
        nodes.append({
            "id": nid, "kind": kind,
            "title": str(raw.get("title") or kind)[:40],
            "icon": _ICON_FOR_KIND.get(kind, "box"),
            "accentKey": _ACCENT_FOR_KIND.get(kind, "green"),
            # Laid out here, not by the model: asking a language model for pixel
            # coordinates produces overlapping cards, and the canvas is the only
            # thing that knows how big a node is.
            "x": col, "y": row,
            "lines": [], "config": cfg,
        })
        col += 300
        if col > 1900:
            col, row = 120, row + 220

    links = []
    seen = set()
    for raw in (obj.get("links") if isinstance(obj.get("links"), list) else [])[:48]:
        if not isinstance(raw, dict):
            continue
        src, dst = str(raw.get("from") or ""), str(raw.get("to") or "")
        if src not in ids or dst not in ids or src == dst:
            continue
        port = str(raw.get("fromPort") or "")
        if port not in ("", "ok", "err", "true", "false", "each", "done"):
            port = ""
        key = (src, dst, port)
        if key in seen:
            continue
        seen.add(key)
        links.append({"from": src, "to": dst, "fromPort": port})
    return {"nodes": nodes, "links": links}, dropped


# Rendered with replace(), not %-formatting: the prompt itself contains a "%"
# (in the "cpu load %" example) and %-formatting chokes on it.
_WORKFLOW_SYSTEM = _WORKFLOW_SYSTEM.replace("__OUTPUTS__",
                                            outputs_catalogue_text())
_WORKFLOW_SYSTEM = _WORKFLOW_SYSTEM.replace("__KINDS__", chr(10).join(
    "  %-16s %s" % (kind, ", ".join(fields) if fields else "(no settings)")
    for kind, fields in sorted(_WORKFLOW_KINDS.items())))
