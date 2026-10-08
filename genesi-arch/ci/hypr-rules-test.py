#!/usr/bin/env python3
"""
hypr-rules-test.py -- every Hyprland rule Genesi writes is one Hyprland applies.

Since Hyprland 0.53 a rule is `windowrule = match:PROP RE, EFFECT VALUE, ...`
(and `layerrule = ..., match:namespace RE`). A rule with no `match:` is not an
error on screen: it is silently discarded. Genesi shipped three generations of
rules that way -- `float, class:...`, then `float class:...`, then Frost's
`blur,NAMESPACE` -- and each looked fixed, because nothing complained. What it
cost: the Quick Chat opened TILED, a transparent workspace-high slab, and the
bar's Frost switch did nothing.

So: every `windowrule =` / `layerrule =` line in a shipped config or install
script, and every `hyprctl keyword windowrule|layerrule` argument in shipped
code, must carry `match:`. Comments are stripped first, so a comment that
QUOTES the old form (as the fixes do) cannot make this pass or fail.
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.normpath(os.path.join(HERE, "..", "packages"))
fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


def strip_comments(path, text):
    if path.endswith((".qml", ".js")):
        return re.sub(r"(?m)^\s*//[^\n]*", "", text)
    # conf, shell, python: whole-line # comments
    return re.sub(r"(?m)^\s*#[^\n]*", "", text)


print("== Hyprland rules ==")
bad = []
seen = 0
for base, dirs, files in os.walk(PKG):
    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__", "node_modules", "src", "pkg")]
    for name in files:
        if not (name.endswith((".conf", ".install", ".sh", ".py", ".qml"))
                or name.startswith("genesi-")):
            continue
        path = os.path.join(base, name)
        try:
            text = io.open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        body = strip_comments(path, text)
        rel = os.path.relpath(path, PKG)
        # Config lines.
        for m in re.finditer(r"(?m)^\s*(windowrule|layerrule)\s*=\s*(.+)$", body):
            seen += 1
            if "match:" not in m.group(2):
                bad.append(f"{rel}: {m.group(0).strip()}")
        # Runtime: hyprctl keyword windowrule|layerrule "<rule>"
        for m in re.finditer(r"""keyword["']?\s*,\s*["'](windowrule|layerrule)["']\s*,\s*(?:r?["'`]|\n\s*r?["'`])([^"'`]+)""", body):
            seen += 1
            if "match:" not in m.group(2):
                bad.append(f"{rel}: hyprctl keyword {m.group(1)} {m.group(2).strip()}")

check("Genesi writes Hyprland rules at all (the scan found them)", seen >= 4, seen)
check("every Hyprland rule Genesi writes has a match: (one without is discarded)",
      not bad, "\n         ".join(bad))

# The guard has to fail on the bug it exists for.
probe = strip_comments("x.conf", "# windowrule = float class:^(x)$\nwindowrule = float class:^(x)$\n")
check("...and it would have caught the old form",
      any("match:" not in m.group(2) for m in re.finditer(r"(?m)^\s*(windowrule|layerrule)\s*=\s*(.+)$", probe)))

print()
if fails:
    print(f"hypr rules: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("hypr rules: OK")
