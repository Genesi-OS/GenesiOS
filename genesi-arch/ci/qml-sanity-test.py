"""Static sanity checks for every Genesi QML file, aimed at the errors that only
surface when QQmlApplicationEngine actually loads the UI — i.e. the ones a build
on a machine without Plasma/Kirigami cannot catch.

Primary check: ATTACHED-TYPE QUALIFICATION. In QML an attached property must be
written with the same qualifier as its module import. With

    import QtQuick.Controls as QQC2

a bare `ScrollBar.vertical:` is not a warning — it is a hard
"Non-existent attached object" load error that takes the whole app down. With a
plain `import QtQuick.Controls` the bare form is the correct one. This shipped
once (genesi-ai-mode pkgrel 135, AdvisorPage.qml) and blanked the Monitor.

Also checks brace/paren/bracket balance (which catches a truncated edit).
"""

import re
import sys
from pathlib import Path

PACKAGES = Path(__file__).resolve().parents[1] / "packages"

# Attached types provided by each module. Only types that are REALLY attachable
# belong here — listing a plain type would cause false positives.
ATTACHED_TYPES = {
    "QtQuick.Controls": {"ScrollBar", "ScrollIndicator", "ToolTip", "SplitView",
                         "StackView", "SwipeView", "Overlay"},
    "QtQuick.Layouts": {"Layout"},
    "QtQuick.Templates": {"ScrollBar", "ScrollIndicator", "ToolTip", "SplitView",
                          "StackView", "SwipeView", "Overlay"},
}

IMPORT = re.compile(r"^\s*import\s+([\w.]+)(?:\s+[\d.]+)?(?:\s+as\s+(\w+))?\s*$",
                    re.M)


def strip(src):
    """Blank out comments and string literals, preserving line numbers.

    This has to be a single pass. Doing it with separate regexes in sequence is
    wrong in both orders: strip comments first and the `//` inside a string like
    "https://x" eats the rest of the line (including its closing brace), strip
    strings first and a quote inside a comment desynchronises the scanner.
    """
    out = []
    i, n = 0, len(src)
    # Last significant character emitted, to tell a REGEX LITERAL from division.
    # `replace(/^file:\/\//, "")` would otherwise be read as a line comment at
    # the escaped slashes and swallow the rest of the line (and its brackets).
    prev = ""
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt not in ("/", "*") and prev in "(,=:[!&|?{;+-*%~^<>":
            out.append(" ")
            i += 1
            while i < n and src[i] != "\n":
                if src[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                done = src[i] == "/"
                out.append(" ")
                i += 1
                if done:
                    break
            prev = "/"
            continue
        if c == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and nxt == "*":
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i = min(i + 2, n)
        elif c in "\"'`":
            quote = c
            out.append(" ")
            i += 1
            while i < n:
                if src[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if src[i] == quote:
                    out.append(" ")
                    i += 1
                    break
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
        else:
            out.append(c)
            if not c.isspace():
                prev = c
            i += 1
    return "".join(out)


failures = []
checked = 0

for path in sorted(PACKAGES.rglob("*.qml")):
    raw = path.read_text(encoding="utf-8", errors="replace")
    code = strip(raw)
    rel = path.relative_to(PACKAGES)
    checked += 1

    # How is each module imported here: qualified (as X) or plain?
    qualifier = {}
    for module, alias in IMPORT.findall(raw):
        qualifier[module] = alias or ""

    # An attached type must carry its module's qualifier — no more, no less.
    for module, types in ATTACHED_TYPES.items():
        if module not in qualifier:
            continue
        alias = qualifier[module]
        for typ in types:
            # A bare `Type.property:` binding at the start of a line.
            for m in re.finditer(rf"^[ \t]*({typ})\.\w+\s*:", code, re.M):
                line = code[:m.start()].count("\n") + 1
                if alias:
                    failures.append(
                        f"{rel}:{line}: `{typ}....` is unqualified but {module} is "
                        f"imported as `{alias}` -> write `{alias}.{typ}....` "
                        f"(would fail at load with 'Non-existent attached object')")
            if alias:
                continue
            # Inverse: qualified use of a module imported plainly.
            for m in re.finditer(rf"^[ \t]*(\w+)\.({typ})\.\w+\s*:", code, re.M):
                if m.group(1) in qualifier.values():
                    line = code[:m.start()].count("\n") + 1
                    failures.append(
                        f"{rel}:{line}: `{m.group(1)}.{typ}....` is qualified but "
                        f"{module} is imported plainly -> write `{typ}....`")

    for op, cl, label in (("{", "}", "braces"), ("(", ")", "parens"),
                          ("[", "]", "brackets")):
        delta = code.count(op) - code.count(cl)
        if delta:
            failures.append(f"{rel}: unbalanced {label} (delta={delta})")

    # NOTE: deliberately NOT checking id uniqueness per file. QML ids only have
    # to be unique within a COMPONENT scope, so two delegates may legitimately
    # both use `id: lbl` (genesi-netinspect does), and a JS object literal like
    # `{ id: id, name: … }` is not an id declaration at all (AutomationCanvas
    # does). Getting that right needs a real parser; a naive rule only cries wolf.

print(f"checked {checked} QML files")
if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  FAIL " + f)
else:
    print("ALL CHECKS PASSED")
sys.exit(1 if failures else 0)
