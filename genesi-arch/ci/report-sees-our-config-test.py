#!/usr/bin/env python3
"""
report-sees-our-config-test.py — the report must look where the fix installs.

genesi-report exists so that "it broke" becomes something someone can act on.
That only holds while the report can SEE what Genesi ships.

It could not. genesi-audio installs its WirePlumber drop-in into
/usr/share/wireplumber/wireplumber.conf.d/, and the report's Audio section
tested that directory and then searched /etc and ~/.config:

    if [ -d /usr/share/wireplumber ] || [ -d /etc/wireplumber ]; then
        find /etc/wireplumber ~/.config/wireplumber -type f ...

so the single drop-in Genesi ships was the one file it could not find. Worse
than the blind spot was the wording: not "nothing found here" but

    none (stock configuration — hardware mixer)

a CONCLUSION. It was read twice as proof that the audio fix was not installed,
and sent the diagnosis down the wrong path both times.

So: every config directory a Genesi package installs a drop-in into must be
named in genesi-report. A file nobody can see is a fix nobody can confirm.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKGS = os.path.join(ROOT, "genesi-arch", "packages")
REPORT = os.path.join(PKGS, "genesi-report", "genesi-report")

# A drop-in directory: somewhere a daemon reads every file it finds. These are
# the ones whose CONTENTS decide behaviour, which is what a report needs to
# show. Matched on the destination path a PKGBUILD writes to.
DROPIN = re.compile(r"\$\{?pkgdir\}?(/[^\"'\s]*?\.conf\.d)/")


def dropin_dirs():
    """Every .conf.d directory a Genesi package installs into, with its owner."""
    found = {}
    for name in sorted(os.listdir(PKGS)):
        p = os.path.join(PKGS, name, "PKGBUILD")
        if not os.path.exists(p):
            continue
        with io.open(p, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for m in DROPIN.finditer(src):
            found.setdefault(m.group(1), set()).add(name)
    return found


def main():
    print("== genesi-report sees what Genesi installs ==")
    if not os.path.exists(REPORT):
        print(f"  FAIL  {REPORT} does not exist")
        return 1

    with io.open(REPORT, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()

    # Comments do not count as looking. The report EXPLAINS this bug in a
    # comment that names the very directory it must search, so a check over the
    # whole file passes while the `find` searches nowhere near it -- the guard
    # certifying its own prose, which is how the last two guards in this
    # directory first shipped broken. Only code is evidence.
    report = "\n".join(l for l in raw.splitlines()
                       if not l.lstrip().startswith("#"))

    dirs = dropin_dirs()
    if not dirs:
        print("  note  no package installs a .conf.d drop-in; nothing to check")
        print("\ngenesi-report coverage: OK")
        return 0

    missing = []
    for d, owners in sorted(dirs.items()):
        seen = d in report
        print(f"  {d}  ({', '.join(sorted(owners))}): "
              f"{'searched' if seen else 'NOT SEARCHED'}")
        if not seen:
            missing.append((d, owners))

    if missing:
        print()
        print("  FAIL  genesi-report never looks in:")
        for d, owners in missing:
            print(f"          {d}  installed by {', '.join(sorted(owners))}")
        print("        The report is how a fix gets confirmed from a user's")
        print("        machine. A drop-in it cannot list reads, in the output,")
        print("        exactly like one that was never installed.")
        return 1

    print("  PASS  every drop-in directory Genesi writes to is searched")
    print("\ngenesi-report coverage: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
