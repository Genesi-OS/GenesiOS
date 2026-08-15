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


# Built-in properties per root type. Deliberately small: a component whose root
# is not listed here is skipped entirely rather than half-checked.
ITEM_PROPS = {
    "id", "objectName", "parent", "data", "children", "resources", "states",
    "transitions", "transform", "anchors", "x", "y", "z", "width", "height",
    "implicitWidth", "implicitHeight", "visible", "opacity", "enabled", "clip",
    "scale", "rotation", "transformOrigin", "smooth", "antialiasing", "focus",
    "activeFocus", "state", "layer", "baselineOffset", "containmentMask",
    "childrenRect", "rotation",
}
ROOT_PROPS = {
    "Item": ITEM_PROPS,
    "Rectangle": ITEM_PROPS | {"color", "radius", "border", "gradient"},
    "MouseArea": ITEM_PROPS | {"hoverEnabled", "acceptedButtons", "cursorShape",
                               "propagateComposedEvents", "preventStealing",
                               "containsMouse", "pressed", "drag", "scrollGestureEnabled"},
}

_API_CACHE = {}


def component_api(comp_path):
    """Property/handler names a local component legitimately accepts, or None
    when its root type is not one we model."""
    key = str(comp_path)
    if key in _API_CACHE:
        return _API_CACHE[key]
    src = strip(comp_path.read_text(encoding="utf-8", errors="replace"))
    # Root type = first `TypeName {` after the import block.
    root = re.search(r"^\s*([A-Z]\w*(?:\.[A-Z]\w*)?)\s*\{", src, re.M)
    base = ROOT_PROPS.get(root.group(1)) if root else None
    if base is None:
        _API_CACHE[key] = None
        return None
    names = set(base)
    for m in re.finditer(r"\bproperty\s+(?:alias\s+|[\w.<>]+\s+)(\w+)", src):
        names.add(m.group(1))
    for m in re.finditer(r"\bsignal\s+(\w+)", src):
        names.add("on" + m.group(1)[0].upper() + m.group(1)[1:])
    # Any `onFoo` handler is allowed: signals can come from the base type too.
    _API_CACHE[key] = names
    return names


def block_body(code, brace_index):
    """Text between a `{` and its matching `}`, or None if unbalanced."""
    depth = 0
    for i in range(brace_index, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[brace_index + 1:i]
    return None


def direct_bindings(body):
    """`name:` bindings at the block's OWN level — never inside a nested block,
    which would belong to a child element, and never dotted (attached
    properties like Layout.fillWidth are resolved by a different mechanism).

    Names DECLARED in the block are excluded. `property string icon: ""` is a
    declaration whose default value happens to look exactly like a binding, and
    a component extending another (StatTile's root is FCard) legitimately adds
    its own properties that way."""
    declared = {m.group(1) for m in
                re.finditer(r"\bproperty\s+(?:alias\s+|[\w.<>]+\s+)(\w+)", body)}
    declared |= {m.group(1) for m in re.finditer(r"\bsignal\s+(\w+)", body)}

    out, depth = [], 0
    for m in re.finditer(r"[{}()\[\]]|(?<![\w.])([A-Za-z_]\w*)\s*:(?!:)", body):
        tok = m.group(0)
        if tok in "{([":
            depth += 1
        elif tok in "})]":
            depth -= 1
        elif depth == 0 and m.group(1):
            name = m.group(1)
            if not name.startswith("on") and name not in declared:
                out.append((name, m.start(1)))
    return out


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

    # ── Unknown property assigned to a LOCAL component ──────────────────────
    # QML resolves properties at LOAD time, so `FIcon { theme: ... }` on a
    # component that has no `theme` is not a warning — it aborts the whole
    # component tree with "Cannot assign to non-existent property", and the app
    # does not open at all. That is exactly how a broken Genesi Forge shipped
    # (SecretsPanel passed `theme` to FIcon, which only has name/color/size).
    #
    # Only components defined in the SAME directory are checked, and only when
    # their root type is one whose built-in properties we actually know. Anything
    # else is skipped rather than guessed at — a false positive here would block
    # CI on correct code, which is worse than the bug it catches.
    siblings = {p.stem: p for p in path.parent.glob("*.qml")}
    for comp_name, comp_path in siblings.items():
        if comp_name == path.stem:
            continue
        known = component_api(comp_path)
        if known is None:
            continue                      # unknown root type: do not guess
        for m in re.finditer(rf"\b{comp_name}\s*{{", code):
            body = block_body(code, m.end() - 1)
            if body is None:
                continue
            for prop, offset in direct_bindings(body):
                if prop in known:
                    continue
                line = code[:m.end() + offset].count("\n") + 1
                failures.append(
                    f"{rel}:{line}: `{comp_name}` has no property `{prop}` "
                    f"(would abort at load with 'Cannot assign to non-existent "
                    f"property \"{prop}\"' and the app would not open)")

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
