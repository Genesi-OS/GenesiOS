#!/usr/bin/env python3
"""
qmldir-complete-test.py — every component in a folder with a qmldir is in it.

A folder that has a qmldir is a module, and a module exposes the types its
qmldir lists -- nothing else. genesi-topbar's qmldir listed only its BarTokens
singleton, so `BarContent { }` in shell.qml was "not a type" and the whole
Genesi top bar failed to load (seen on Qt 6.12.1; older Qt was lenient and
let the unlisted file through, which is how it shipped).

For every qmldir under genesi-arch/packages: each capitalised .qml beside it
must be listed, except an entry point the app loads by path (shell.qml,
Main.qml), which is never referenced as a type.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "packages"))
ENTRY_POINTS = {"shell", "Main"}

bad, checked = [], 0
for dirpath, _, files in os.walk(ROOT):
    if "qmldir" not in files:
        continue
    text = open(os.path.join(dirpath, "qmldir"), encoding="utf-8", errors="replace").read()
    listed = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        m = re.match(r"^(?:singleton\s+)?([A-Z]\w*)\s+[\d.]+\s+\S+\.qml$", line)
        if m:
            listed.add(m.group(1))
    for name in files:
        stem, ext = os.path.splitext(name)
        if ext != ".qml" or not stem[:1].isupper() or stem in ENTRY_POINTS:
            continue
        checked += 1
        if stem not in listed:
            bad.append(os.path.relpath(os.path.join(dirpath, name), ROOT))

print("  components checked against their qmldir: %d" % checked)
if bad:
    print("FAIL: in a folder with a qmldir, these are not types until listed:")
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("qmldir complete: OK")
