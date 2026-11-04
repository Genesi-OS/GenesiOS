#!/usr/bin/env python3
"""
installer-copy-overlap-test.py — the installer never copies the live ISO's
files over what a Genesi package installed.

shellprocess@copy_genesi copies directories from the live ISO into the target,
and it runs AFTER packages@online has installed the Genesi packages. Whatever
it copies wins. It copied /usr/share/sddm/themes/genesi, which genesi-store
installs: the live ISO's older theme (no QtVersion=6) replaced the package's,
SDDM started it with the Qt 5 greeter Arch no longer ships, and a user who
picked "Genesi" as their login screen got a black screen on logout.

Each `cp ... /usr/share/<path> ${ROOT}/...` line is checked against every
path a Genesi PKGBUILD installs under /usr/share: the copy must not be that
path, contain it, or sit inside it.
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
COPY_CONF = os.path.join(ROOT, "genesi-calamares-config-full/etc/calamares/modules/shellprocess_copy_genesi.conf")
PKGS = os.path.join(ROOT, "genesi-arch/packages")

if not os.path.exists(COPY_CONF):
    print("FAIL: genesi-calamares-config-full is missing (check out with submodules)")
    sys.exit(1)

# Paths packages install: `install ... "${pkgdir}/usr/share/..."` and
# `cp ... "${pkgdir}/usr/share/..."` destinations, per package.
DEST = re.compile(r'(?:\$\{pkgdir\}|\$pkgdir)(/usr/share/[^"\'\s]+)')
installed = {}
for pkg in sorted(os.listdir(PKGS)):
    pb = os.path.join(PKGS, pkg, "PKGBUILD")
    if not os.path.isfile(pb):
        continue
    for line in open(pb, encoding="utf-8", errors="replace"):
        if line.lstrip().startswith("#"):
            continue
        for m in DEST.finditer(line):
            path = m.group(1).rstrip("/")
            if "$" in path:                       # a loop variable: keep the fixed prefix
                path = path.split("$", 1)[0].rstrip("/")
            if path.count("/") >= 4:              # /usr/share/x/y at least: specific
                installed.setdefault(path, set()).add(pkg)

script = yaml.safe_load(open(COPY_CONF, encoding="utf-8-sig"))["script"]
lines = [s if isinstance(s, str) else s.get("command", "") for s in script]
COPY = re.compile(r"\bcp\s+-\w+\s+(/usr/share/\S+?)/?\s+\$\{ROOT\}")

fails = []
copies = 0
for line in lines:
    m = COPY.search(line)
    if not m:
        continue
    copies += 1
    src = m.group(1).rstrip("/").rstrip(".").rstrip("/")
    prefix = src.split("*", 1)[0]
    for path, pkgs in installed.items():
        hit = (path == src or path.startswith(src + "/") or src.startswith(path + "/")
               or ("*" in src and path.startswith(prefix)))
        if hit:
            fails.append("%s  overwrites  %s  (installed by %s)" % (src, path, ", ".join(sorted(pkgs))))

# Overlaps that predate this check. Each one is the same risk (a live ISO
# older than the package downloaded during the install puts the old file back)
# but none has broken a machine yet, and removing a copy blind can drop a file
# only the live ISO has. Listed so they cannot grow: a NEW overlap fails, and
# an entry here that no longer overlaps fails too, so the list only shrinks.
KNOWN = {
    "/usr/share/applications/genesi-*",
    "/usr/share/color-schemes/Genesi*",
    "/usr/share/genesi",
    "/usr/share/plasma/desktoptheme/Ant-Dark",
    "/usr/share/plasma/desktoptheme/genesi-plasma",
    "/usr/share/plymouth/themes/genesi",
}
seen = {f.split("  overwrites  ", 1)[0] for f in fails}
stale = sorted(KNOWN - seen)
fails = [f for f in fails if f.split("  overwrites  ", 1)[0] not in KNOWN]

print("  checked %d copies against %d package paths" % (copies, len(installed)))
if copies == 0:
    print("FAIL: found no copy lines; the pattern no longer matches the module")
    sys.exit(1)
if stale:
    print("FAIL: KNOWN lists copies that no longer overlap a package; remove them:")
    for s in stale:
        print("  " + s)
    sys.exit(1)
if fails:
    print("FAIL: copy_genesi copies the live ISO's files over a package's:")
    for f in sorted(set(fails)):
        print("  " + f)
    sys.exit(1)
print("installer copy overlap: OK")
