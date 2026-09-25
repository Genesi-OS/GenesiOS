#!/usr/bin/env python3
"""
The Nexus Updates page knows about an update it did not start.

The page used to run the update in a Process it owned. Close the Nexus
window and the page went with it -- the update did not, pacman runs as root
-- and the page that opened next knew nothing, ran `checkupdates` and offered
"Update now" again beside the transaction still running. Reported as "close
it, reopen it, and it checks again instead of knowing it is updating".

So:
  * the update is started detached, never by a Process the page owns;
  * checkupdates does not start on its own -- the page first asks whether an
    update is running, and only checks when nothing is;
  * "running" means our helper, or a pacman holding the database LOCK -- a
    bare `pgrep pacman` also catches checkupdates, which the tray and the
    leaf run by themselves.

Comments are stripped before anything is matched: the page's own comments
describe the old code, and a guard that matches its fix's prose passes on
the very bug it exists to catch.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "packages", "genesi-caelestia-shell", "UpdatesPage.qml")

failures = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        failures.append(what)


def code_of(text):
    # Line comments only -- QML strings here never contain "//" except in
    # URLs, and this page has none.
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


code = code_of(open(PAGE, encoding="utf-8").read())


def blocks(kind):
    """Every `kind { ... }` block, brace-matched."""
    out = []
    for m in re.finditer(r"\b%s\s*\{" % kind, code):
        depth, i = 0, m.end() - 1
        while i < len(code):
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    out.append(code[m.start():i + 1])
                    break
            i += 1
    return out


procs = blocks("Process")
check(not any("genesi-update-center-apply" in b and "command:" in b and "pgrep" not in b for b in procs),
      "no Process the page owns runs the update")
check(re.search(r"Quickshell\.execDetached\(\s*\[\s*\"pkexec\",\s*\"/usr/bin/genesi-update-center-apply\"", code) is not None,
      "the update is started detached")
check(re.search(r"^\s*import Quickshell\s*$", code, re.M) is not None,
      "the page imports Quickshell, which execDetached needs")

check_proc = [b for b in procs if "checkupdates" in b]
check(len(check_proc) == 1 and not re.search(r"\brunning:\s*true", check_proc[0]),
      "checkupdates waits for the probe instead of starting on its own")
check(re.search(r"Component\.onCompleted:\s*root\.probe\(\)", code) is not None,
      "opening the page asks whether an update is running first")

busy = [b for b in procs if "pgrep" in b]
check(len(busy) == 1, "there is one probe for a running update")
if busy:
    b = busy[0]
    check("genesi-update-center-appl[y]" in b,
          "the probe finds the helper without matching its own command line")
    check("db.lck" in b and "pgrep -x pacman" in b,
          "a pacman only counts while it holds the database lock")

timers = blocks("Timer")
check(any(re.search(r"running:\s*root\.applying", t) and "probe()" in t for t in timers),
      "a running update is followed until it ends")

if failures:
    print("\n%d failure(s)" % len(failures))
    sys.exit(1)
print("\nupdates page: OK")
