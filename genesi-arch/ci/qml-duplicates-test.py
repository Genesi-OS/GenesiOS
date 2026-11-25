#!/usr/bin/env python3
"""The same property set twice on one QML object.

`Component.onCompleted` written twice on one object -- or `width`, or
`anchors.fill` -- is not a warning. It is "Property value set multiple times",
a LOAD error, and the file that has it does not exist at run time: for a
window, the whole window is gone. It was nearly shipped in Quick Chat, added
by a fix while the object already had one further down, and qml-sanity passed
it, because nothing checked for it.

Read per object: braces are tracked, and only blocks that open a QML object
(`Type {`, `prop: Type {`, `Behavior on x {`) are checked -- a function body
or a JavaScript object literal is not an object whose properties QML assigns.
Comments and string contents are blanked first, so a `:` in a string or a
comment is never read as an assignment.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "packages"))

OBJECT_OPEN = re.compile(
    r"^\s*(?:[\w.]+\s*:\s*)?(?:[A-Z][\w.]*|Behavior\s+on\s+[\w.]+|"
    r"[A-Z][\w.]*\s+on\s+[\w.]+)\s*\{\s*$")
ASSIGN = re.compile(r"^\s*([A-Za-z_][\w.]*)\s*:(?!:)")
NOT_ASSIGN = {"case", "default", "return", "else", "property", "readonly",
              "required", "signal", "function", "import", "id"}


def blank(text):
    """Comments and string contents replaced by spaces; newlines kept."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(c + "".join(ch if ch == "\n" else " "
                                   for ch in text[i + 1:j]) + c)
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


failures = []
checked = 0
for base, dirs, files in os.walk(ROOT):
    if "build" in dirs:
        dirs.remove("build")
    for name in files:
        if not name.endswith(".qml"):
            continue
        path = os.path.join(base, name)
        text = blank(io.open(path, encoding="utf-8", errors="replace").read())
        checked += 1
        # stack of (is_qml_object, {name: line})
        stack = []
        for lineno, line in enumerate(text.split("\n"), 1):
            stripped = line.strip()
            if stack and stack[-1][0] and stripped and "{" not in stripped:
                m = ASSIGN.match(line)
                if m and m.group(1) not in NOT_ASSIGN:
                    seen = stack[-1][1]
                    key = m.group(1)
                    if key in seen:
                        failures.append(
                            f"{os.path.relpath(path, ROOT)}:{lineno}: `{key}` "
                            f"is already set on this object at line "
                            f"{seen[key]}")
                    else:
                        seen[key] = lineno
            elif stack and stack[-1][0] and "{" in stripped:
                # `onX: {` or `prop: Type {` -- still an assignment on THIS
                # object, made before the new block opens.
                m = ASSIGN.match(line)
                if m and m.group(1) not in NOT_ASSIGN:
                    seen = stack[-1][1]
                    key = m.group(1)
                    if key in seen:
                        failures.append(
                            f"{os.path.relpath(path, ROOT)}:{lineno}: `{key}` "
                            f"is already set on this object at line "
                            f"{seen[key]}")
                    else:
                        seen[key] = lineno
            for ch in line:
                if ch == "{":
                    stack.append((bool(OBJECT_OPEN.match(line)), {}))
                elif ch == "}" and stack:
                    stack.pop()

print("== one value per property, per QML object ==")
print(f"  checked {checked} QML files")
if failures:
    print(f"  FAIL  {len(failures)} property set twice on one object:")
    for f in failures:
        print("          " + f)
    print("\n        Each of these is 'Property value set multiple times' --")
    print("        a load error, and the file does not exist at run time.")
    sys.exit(1)
print("  PASS")
print("\nqml duplicates: OK")
