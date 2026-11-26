#!/usr/bin/env python3
"""
frameless-drag-test.py — a frameless window that drags itself asks the
compositor to do it.

On Wayland a window cannot move itself: its x and y belong to the compositor,
and assigning them does nothing. The Hub moved its frameless window that way,
so on KDE Plasma dragging its header did nothing and the window could only be
moved with Super held (a Hyprland habit that hid the bug there). The fix is
Window.startSystemMove(), which KWin, Hyprland and X11 all honour.

Every QML file under genesi-arch/packages that builds a frameless window and
moves it by writing x/y must also call startSystemMove().
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "packages"))
MOVES_ITSELF = re.compile(r"\b\w+\.(x|y)\s*\+=\s*mouse\.")

bad, seen = [], 0
for dirpath, _, files in os.walk(ROOT):
    for name in files:
        if not name.endswith(".qml"):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf-8", errors="replace").read()
        code = "\n".join(l.split("//", 1)[0] for l in text.splitlines())
        if "FramelessWindowHint" not in code or not MOVES_ITSELF.search(code):
            continue
        seen += 1
        if "startSystemMove()" not in code:
            bad.append(os.path.relpath(path, ROOT))

print("  frameless windows that drag themselves: %d" % seen)
if bad:
    print("FAIL: these move themselves by writing x/y, which Wayland ignores;")
    print("      call startSystemMove() when the drag starts:")
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("frameless drag: OK")
