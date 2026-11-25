#!/usr/bin/env python3
"""Does every backend call in the Monitor's QML name something that exists?

The Monitor's pages talk to Python through one context object, `backend`, and
QML resolves both directions BY NAME at run time:

  * `backend.loadCloud()` on a slot that does not exist is a TypeError in the
    log and a button that does nothing;
  * `function onCloudLoaded(json)` inside a Connections on a signal that does
    not exist is not even that -- Connections has `ignoreUnknownSignals`
    semantics for handlers, so the page simply never hears it.

Neither shows up in qml-sanity, which cannot know what Python exposes, and the
Monitor needs Kirigami to load, so no offscreen harness here can load it
either. This reads both sides as text: the @Slot methods and Signal
attributes on the Backend classes, and the `backend.x(` calls and `onX`
handlers in the QML.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MON = os.path.join(HERE, "..", "packages", "genesi-ai-mode", "monitor")

failures = []


def ok(what):
    print(f"  ok   {what}")


def bad(what, why):
    print(f"  FAIL {what}")
    print(f"         {why}")
    failures.append(what)


print("== the Monitor's backend, by name ==")

slots, signals = set(), set()
for py in ("genesi_ai_monitor.py", "genesi_ai_quick.py"):
    src = io.open(os.path.join(MON, py), encoding="utf-8").read()
    # A slot is a def directly under an @Slot(...) decorator.
    for m in re.finditer(r"@Slot\([^)]*\)\s*\n\s*def (\w+)\(", src):
        slots.add(m.group(1))
    for m in re.finditer(r"^\s+(\w+)\s*=\s*Signal\(", src, re.M):
        signals.add(m.group(1))

if not slots or not signals:
    bad("the backend's slots and signals were found",
        f"{len(slots)} slot(s), {len(signals)} signal(s) -- the pattern no "
        "longer matches how the backend declares them, so nothing below "
        "would be checked")

# QML-side names that are not backend members even though they follow a
# backend. word: none today; kept explicit so an exception is a decision.
NOT_SLOTS = set()

handlers_seen = set()
for qml in sorted(f for f in os.listdir(MON) if f.endswith(".qml")):
    text = io.open(os.path.join(MON, qml), encoding="utf-8").read()
    body = re.sub(r"//[^\n]*", "", text)
    called = set(re.findall(r"\bbackend\.(\w+)\s*\(", body))
    missing = sorted(called - slots - NOT_SLOTS)
    if missing:
        bad(f"{qml} calls only slots that exist",
            f"{missing} {'is' if len(missing) == 1 else 'are'} not a @Slot "
            "on the backend -- the call is a TypeError and the control does "
            "nothing")
    elif called:
        ok(f"{qml}: {len(called)} backend call(s), all real")

    # Handlers inside a Connections whose target is the backend. Braces are
    # matched by counting: the first version used a lazy regex that stopped at
    # the first closing brace of the first handler's body, so it never saw a
    # single handler -- and reported every one of them as fine.
    for m in re.finditer(r"\bConnections\s*\{", body):
        depth, i = 1, m.end()
        while i < len(body) and depth:
            depth += {"{": 1, "}": -1}.get(body[i], 0)
            i += 1
        inner = body[m.end():i - 1]
        if not re.search(r"target:\s*backend\b", inner):
            continue
        for h in re.findall(r"function\s+on([A-Z]\w*)\s*\(", inner):
            name = h[0].lower() + h[1:]
            handlers_seen.add(qml)
            if name not in signals:
                bad(f"{qml} listens only for signals that exist",
                    f"on{h} handles `{name}`, which the backend does not "
                    "emit -- the page never hears it, silently")

for must in ("ChatPage.qml", "QuickChat.qml"):
    if must not in handlers_seen:
        bad(f"the handler check reads {must}",
            "no `on...` handler was found in its backend Connections, and it "
            "has several -- the check has stopped seeing them, so it would "
            "pass on a misspelled one")
if handlers_seen:
    ok("backend signal handlers checked in: " + ", ".join(sorted(handlers_seen)))

print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("monitor backend names: OK")
