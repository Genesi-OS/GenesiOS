#!/usr/bin/env python3
"""
Every Genesi QML file the patcher installs is in the shell's source=().

Two lists have to agree and nothing checks that they do:

  * ci/caelestia-patches.py names the files it copies into the extracted
    upstream release (LAUNCHER_FILES, WIDGET_FILES, DOCK_FILES, SCHEME_FILES
    and the Nexus PAGES);
  * genesi-caelestia-shell/PKGBUILD names the files makepkg copies into
    $srcdir, which is where the patcher looks for them.

Add a file to the first and not the second and the package builds Calamares,
materialyoucolor and half of Qt first, then dies in prepare() thirteen minutes
in with "GenesiSchemeState.qml is missing". Add it to the second and not the
first and it is a file that is fetched, checksummed and never used.

The reverse direction matters too, and less obviously: a checksums array one
entry shorter than the sources array is not an error makepkg reports clearly.

This is the same shape as ci/package-reachability-test.py -- a package in the
repository that no install path names reaches nobody, and a QML file no
source=() names reaches no build.
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
PATCHER = os.path.join(HERE, "caelestia-patches.py")
PKGBUILD = os.path.join(HERE, "..", "packages", "genesi-caelestia-shell",
                        "PKGBUILD")

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (
        "" if cond else "\n         " + detail))
    if not cond:
        fails.append(name)


print("== caelestia shell sources ==")

patcher = io.open(PATCHER, encoding="utf-8").read()
pkgbuild = io.open(PKGBUILD, encoding="utf-8").read()

# What the patcher copies. Read from the source rather than imported, because
# importing it would run its argument parsing -- and because the point is to
# read the same text a person reads.
wanted = set()

# The plain tuples. `WIDGET_FILES` is built with a comprehension over WIDGETS
# plus a literal tail, so it is handled separately below.
for name in ("LAUNCHER_FILES", "DOCK_FILES", "SCHEME_FILES"):
    m = re.search(r"^%s = \((.*?)\)\n" % name, patcher, re.S | re.M)
    if not m:
        check(f"{name} is where this expects it", False,
              "the patcher's file lists moved or were renamed")
        continue
    wanted |= set(re.findall(r'"([^"]+\.qml)"', m.group(1)))

# WIDGET_FILES: one GenesiWidget<Name>.qml per entry in WIDGETS, plus the
# handful of files listed after it.
m = re.search(r"^WIDGETS = \[(.*?)\]\n", patcher, re.S | re.M)
if m:
    for n in re.findall(r'"([^"]+)"', m.group(1)):
        wanted.add("GenesiWidget" + n[0].upper() + n[1:] + ".qml")
else:
    check("WIDGETS is where this expects it", False, "the widget list moved")
m = re.search(r"^WIDGET_FILES = tuple\((.*?)\n\n", patcher, re.S | re.M)
if m:
    wanted |= set(re.findall(r'"([^"]+\.qml)"', m.group(1)))

# The Nexus pages are named by their component, without the extension.
m = re.search(r"^PAGES = \[(.*?)\n\]\n", patcher, re.S | re.M)
if m:
    wanted |= {c + ".qml" for c in re.findall(r'"comp":\s*"(\w+)"', m.group(1))}

# And the whole-file overrides of upstream, which are copied by name.
wanted |= set(re.findall(r'ours,\s*"([A-Za-z]+\.qml)"', patcher))

m = re.search(r"^source=\((.*?)\)\n", pkgbuild, re.S | re.M)
if not m:
    check("the PKGBUILD has a source array", False, "")
    sys.exit(1)
src_body = m.group(1)
shipped = set(re.findall(r'"([^"]+\.qml)"', src_body))

print(f"  patcher installs: {len(wanted)}   source=() carries: {len(shipped)}")

missing = sorted(wanted - shipped)
check("every file the patcher installs is fetched by the PKGBUILD",
      not missing,
      "not in source=(): " + ", ".join(missing) + "\n         "
      "prepare() dies on the first one, after the whole build")

# Not everything in source=() goes through the patcher: prepare() installs a
# couple of whole-file overrides itself (ContentList.qml, UpdatesPage.qml). So
# the rule is "used SOMEWHERE", not "used by the patcher" -- a file that is
# fetched, checksummed and named nowhere is dead weight in the build.
body = pkgbuild[m.end():]
extra = sorted(f for f in shipped - wanted if f not in body)
check("and nothing is fetched that nothing ever uses",
      not extra,
      "in source=() and referenced neither by the patcher nor by prepare(): "
      + ", ".join(extra))

# One checksum per source entry. makepkg is not loud about a short array.
n_src = len(re.findall(r'"[^"]+"|\$url\S*', src_body))
m2 = re.search(r"^sha256sums=\((.*?)\)\n", pkgbuild, re.S | re.M)
n_sum = len(re.findall(r"'[^']*'", m2.group(1))) if m2 else 0
check("sha256sums has one entry per source entry", n_src == n_sum,
      f"{n_src} sources, {n_sum} checksums")

print()
if fails:
    print(f"{len(fails)} check(s) failed:")
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("caelestia shell sources: OK")
