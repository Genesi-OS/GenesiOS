#!/usr/bin/env python3
"""
os-logo-test.py — the logo os-release names is an icon an installed system has.

KDE's "About this System" (and GNOME's About) draw the icon named by LOGO= in
/etc/os-release. Genesi says LOGO=genesi, and the only `genesi` icon lived in
the live ISO's airootfs. Installs are built by pacstrap from packages, so the
icon never reached them and About showed a grey "?" where the logo goes. A
user on a Core Ultra laptop sent the screenshot.

The icon now ships in genesi-settings, which every install gets. This checks:
  * every LOGO= Genesi writes names an icon in a package's hicolor tree,
    at the sizes About asks for;
  * the live ISO's airootfs does not carry its own copy too: mkarchiso copies
    airootfs before installing packages, so a duplicate file makes pacman
    stop with "exists in filesystem" and the ISO does not build.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

OS_RELEASE_WRITERS = (
    "genesi-calamares-config-full/etc/calamares/scripts/genesi-write-branding.sh",
    "genesi-arch/archiso/airootfs/etc/os-release",
    "genesi-arch/packages/genesi-settings-full/os-release",
)
PACKAGE_ICON_ROOT = "genesi-settings-full/usr/share/icons/hicolor"
AIROOTFS_ICON_ROOT = "genesi-arch/archiso/airootfs/usr/share/icons/hicolor"
SIZES = ("48x48", "64x64", "128x128", "256x256")

fails = []


def check(name, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + name + (("  -- " + detail) if detail and not ok else ""))
    if not ok:
        fails.append(name)


if not os.path.isdir(os.path.join(ROOT, "genesi-settings-full", "usr")):
    print("FAIL: genesi-settings-full is missing (check out with submodules)")
    sys.exit(1)

logos = set()
for rel in OS_RELEASE_WRITERS:
    p = os.path.join(ROOT, rel)
    if os.path.exists(p):
        for m in re.finditer(r"^LOGO=\"?([A-Za-z0-9._-]+)\"?\s*$", open(p, encoding="utf-8").read(), re.M):
            logos.add(m.group(1))
check("os-release names a logo", bool(logos))

for logo in sorted(logos):
    missing = [s for s in SIZES
               if not os.path.isfile(os.path.join(ROOT, PACKAGE_ICON_ROOT, s, "apps", logo + ".png"))]
    check("LOGO=%s ships in genesi-settings at %s" % (logo, ", ".join(SIZES)), not missing,
          "missing " + ", ".join(missing))
    dup = [s for s in os.listdir(os.path.join(ROOT, AIROOTFS_ICON_ROOT))
           if os.path.isfile(os.path.join(ROOT, AIROOTFS_ICON_ROOT, s, "apps", logo + ".png"))] \
        if os.path.isdir(os.path.join(ROOT, AIROOTFS_ICON_ROOT)) else []
    check("the live ISO does not carry a second %s icon (pacman file conflict)" % logo, not dup,
          "airootfs has " + ", ".join(dup))

print()
if fails:
    print("os logo: %d failure(s)" % len(fails))
    sys.exit(1)
print("os logo: OK")
