#!/usr/bin/env python3
"""
systemd-unit-refs-test.py — a unit may not point at a unit that does not exist.

Genesi rebrands CachyOS material by running, in more than one package():

    find "$pkgdir" -type f -exec sed -i 's/cachyos/genesi/g' {} +

That is right for user-visible text and wrong for identifiers, and systemd unit
names are identifiers. The sed edits file CONTENTS and never filenames, so
cachyos-iw-set-regdomain.path had its trigger rewritten to
`Unit=genesi-iw-set-regdomain.service` while the service file kept its real
name. Every boot since logged:

    cachyos-iw-set-regdomain.path: Refusing to start, unit
    genesi-iw-set-regdomain.service to trigger not loaded.
    Failed to start Monitor Timezone Changes to Set Wireless Regulatory Domain.

Two checks, because the mistake has two halves:

  * the units Genesi ships must reference units that exist, and
  * a package that rebrands by sed must leave systemd paths alone, which is
    what stops the first check from being quietly undone at build time.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

# Directives that make systemd REFUSE to start the unit when the target is
# missing. After= and Before= are ordering only -- a missing target there is
# legal and common, so they are not checked.
HARD_REFS = ("Unit", "Requires", "BindsTo", "PartOf", "Requisite")

UNIT_SUFFIXES = (".service", ".path", ".timer", ".socket", ".mount", ".target")

# Shipped by systemd itself or by other packages; not ours to account for.
WELL_KNOWN = {
    "multi-user.target", "graphical.target", "graphical-session.target",
    "basic.target", "sysinit.target", "network.target",
    "network-online.target", "local-fs.target", "sockets.target",
    "default.target", "shutdown.target", "dbus.service", "dbus.socket",
    "systemd-udevd.service", "NetworkManager.service", "polkit.service",
}


def unit_files():
    """Every systemd unit in the tree, keyed by the directory it lives in."""
    by_dir = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "node_modules", "__pycache__")]
        if "systemd" not in dirpath.replace("\\", "/"):
            continue
        units = [f for f in filenames if f.endswith(UNIT_SUFFIXES)]
        if units:
            by_dir.setdefault(dirpath, set()).update(units)
    return by_dir


def check_refs():
    bad = []
    n = 0
    for dirpath, units in sorted(unit_files().items()):
        for fn in sorted(units):
            n += 1
            path = os.path.join(dirpath, fn)
            try:
                with io.open(path, encoding="utf-8", errors="replace") as fh:
                    src = fh.read()
            except OSError:
                continue
            for line in src.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                m = re.match(r"(%s)\s*=\s*(.+)$" % "|".join(HARD_REFS), line)
                if not m:
                    continue
                for target in m.group(2).split():
                    if not target.endswith(UNIT_SUFFIXES):
                        continue
                    if target in WELL_KNOWN or target in units:
                        continue
                    # A template or an instance is not resolvable from here.
                    if "@" in target or "%" in target:
                        continue
                    bad.append((os.path.relpath(path, ROOT).replace("\\", "/"),
                                m.group(1), target))
    return n, bad


def check_rebrand_excludes():
    """No package may rewrite `cachyos` across systemd units."""
    offenders = []
    pkgdir = os.path.join(ROOT, "genesi-arch", "packages")
    if not os.path.isdir(pkgdir):
        return offenders
    for name in sorted(os.listdir(pkgdir)):
        p = os.path.join(pkgdir, name, "PKGBUILD")
        if not os.path.exists(p):
            continue
        with io.open(p, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for line in src.splitlines():
            if "sed" not in line or "cachyos/genesi" not in line:
                continue
            if line.lstrip().startswith("#"):
                continue
            # A sed already restricted to source/config extensions can never
            # reach a unit file, so it is not an offender. Only an
            # unrestricted sweep over the whole package is.
            block = src[max(0, src.find(line) - 300):src.find(line) + len(line)]
            restricted = "-name" in block and ".service" not in block
            if "systemd" not in line and not restricted:
                offenders.append((name, line.strip()[:80]))
    return offenders


def main():
    print("== systemd unit references ==")
    n, bad = check_refs()
    print(f"  units: {n}")

    failed = False
    if bad:
        failed = True
        print("  FAIL  unit(s) point at a unit that is not shipped beside them:")
        for path, key, target in bad:
            print(f"          - {path}: {key}={target}")
        print("        systemd refuses to start a unit whose hard reference is")
        print("        missing, and says so only in the journal.")
    else:
        print("  PASS  every hard reference names a unit that exists")

    offenders = check_rebrand_excludes()
    if offenders:
        failed = True
        print("  FAIL  package(s) rewrite 'cachyos' without excluding systemd:")
        for name, line in offenders:
            print(f"          - {name}: {line}")
        print("        The sed edits contents and not filenames, so it renames")
        print("        the REFERENCE and leaves the unit file where it was.")
        print("        Add -not -path \"*/systemd/*\".")
    else:
        print("  PASS  no rebrand sed touches systemd units")

    if failed:
        return 1
    print("\nsystemd unit references: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
