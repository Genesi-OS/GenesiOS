#!/usr/bin/env python3
"""
installer-graphics-test.py — no install path ships a driver that blanks the screen.

── Why this exists ──────────────────────────────────────────────────────────

A user installed Genesi on a Core Ultra 7 155H (Meteor Lake, Arc graphics).
The install finished, GRUB came up, and then the screen stayed black, on the
laptop panel and on HDMI alike. The same ISO worked on an older i7.

The SDDM greeter runs on Xorg, and both netinstall groups shipped
xf86-video-intel. Arch's Xorg picks that driver for every Intel GPU whenever
it is installed. It has been unmaintained for years and does not handle
Meteor Lake and newer, so the login screen never appeared. Older Intel
chips worked, which is why nobody saw it. Xorg's built-in modesetting
driver covers every Intel GPU, so nothing is lost by not shipping it.

The package names are matched as list entries (`- name`), never as text, so
a comment explaining why a package is gone cannot satisfy or trip the check.
"""
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# package -> why it must never be installed
FORBIDDEN = {
    "xf86-video-intel": "Xorg picks it for every Intel GPU and it blanks the "
                        "SDDM greeter on Meteor Lake and newer (Core Ultra)",
}

SOURCES = (
    os.path.join("genesi-calamares-config-full", "etc", "calamares",
                 "modules", "netinstall.yaml"),
    os.path.join("genesi-calamares-config-full", "etc", "calamares",
                 "modules", "pacstrap.conf"),
    os.path.join("genesi-arch", "archiso", "packages_desktop.x86_64"),
)

ENTRY = re.compile(r"^\s*(?:-\s*)?([A-Za-z0-9][A-Za-z0-9._+-]*)\s*$")


def entries(path):
    with io.open(path, encoding="utf-8-sig", errors="replace") as fh:
        for no, line in enumerate(fh, 1):
            line = line.split("#", 1)[0]
            m = ENTRY.match(line)
            if m:
                yield no, m.group(1)


def main():
    missing, bad = [], []
    for rel in SOURCES:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            missing.append(rel)
            continue
        for no, name in entries(p):
            if name in FORBIDDEN:
                bad.append("%s:%d  %s  (%s)" % (rel, no, name, FORBIDDEN[name]))
    if missing:
        # Refuse rather than pass: without the Calamares submodule the two
        # install paths that shipped the bug are not being looked at.
        print("FAIL: cannot check, missing: " + ", ".join(missing))
        print("      (check out with submodules)")
        return 1
    if bad:
        print("FAIL: an install path ships a package that must not be installed:")
        for b in bad:
            print("  " + b)
        return 1
    print("OK: no install path ships %s" % ", ".join(sorted(FORBIDDEN)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
