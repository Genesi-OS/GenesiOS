#!/usr/bin/env python3
"""A precondition must not name something the patch itself adds.

caelestia-patches.py is written as pairs: a string describing what upstream
says today, and a string describing what it will say once we are done. The
first is asserted before the second is written, so an override whose
assumptions have expired fails the BUILD with a specific message instead of
producing a silently wrong shell.

That only works while the two halves stay on their own sides. A `.replace()`
meant for the replacement landed on the precondition once, and the patch then
asserted that upstream's Regions.qml already mentioned `leftPad` -- a property
that patch adds. It cannot, so every build stopped there with a message about
upstream having changed, when upstream had not.

The test: for each patch function, collect the property names DECLARED in its
replacement strings and check that none of them appear in its precondition
strings. A name we are inventing cannot already be in the file we are about to
invent it in.

This is not a substitute for running the patcher against a real caelestia
release -- only the build can do that. It is the half that can be checked in
seconds, on the class of mistake that otherwise costs twenty minutes to
discover and points at the wrong culprit when it does.
"""
import ast
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHER = os.path.join(HERE, "caelestia-patches.py")

# The variables each half is conventionally held in. Everything a patch
# asserts BEFORE writing goes in the first set; everything it writes goes in
# the second. Anything named otherwise is skipped rather than guessed at.
PRECONDITION = {"old", "anchor", "fwd", "member", "init", "prop", "getter",
                "impl", "imp", "inc", "line", "tail", "wrapper_old"}
REPLACEMENT = {"new", "block"}

DECLARES = re.compile(r"(?:readonly\s+)?property\s+[\w.<>]+\s+(\w+)")

src = io.open(PATCHER, encoding="utf-8").read()
tree = ast.parse(src)

failures = []
checked = 0


def literals(node):
    """Every string constant under a node, joined. Covers the implicit
    concatenation these strings are all written with."""
    out = []
    for sub in ast.walk(node):
        if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
            out.append(sub.value)
    return "".join(out)


for fn in tree.body:
    if not isinstance(fn, ast.FunctionDef) or not fn.name.startswith("patch_"):
        continue
    checked += 1
    pre, rep = [], []
    for node in ast.walk(fn):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if not isinstance(target, ast.Name):
                continue
            if target.id in PRECONDITION:
                pre.append(literals(node.value))
            elif target.id in REPLACEMENT:
                rep.append(literals(node.value))
    if not pre or not rep:
        continue

    pre_text = "\n".join(pre)
    introduced = set()
    for chunk in rep:
        introduced |= set(DECLARES.findall(chunk))
    # Only the ones that are NOT also declared in the precondition itself: a
    # patch may legitimately assert that an earlier patch's property is there.
    introduced -= set(DECLARES.findall(pre_text))

    for name in sorted(introduced):
        # Not preceded by a dot. Upstream's Bar.qml reads
        # `Tokens.sizes.bar.innerWidth` and the patch declares a local
        # `innerWidth` beside it -- two different things that share a
        # word, and flagging that would be a guard nobody can satisfy.
        if re.search(r"(?<![.\w])%s\b" % re.escape(name), pre_text):
            failures.append(
                f"{fn.name}: its precondition mentions `{name}`, which the "
                f"patch itself declares -- upstream cannot already contain a "
                f"name we are about to add, so the assertion can never pass")

print(f"== caelestia-patches.py: {checked} patch function(s) ==")
if failures:
    print(f"\n{len(failures)} problem(s):")
    for f in failures:
        print("  FAIL " + f)
    print()
    print("        The two halves of a patch have swapped: a `.replace()`")
    print("        meant for the replacement has landed on the precondition.")
    print("        The build fails on a claim about upstream that was never")
    print("        true, with a message blaming upstream for it.")
    sys.exit(1)

print("  PASS  every precondition describes upstream, not us")
print("\npatcher sanity: OK")
