#!/usr/bin/env python3
"""
pkgrel-bump-test.py — changing a package without changing its version ships
nothing.

pacman decides whether to upgrade by comparing VERSIONS, never contents. A
package rebuilt at the same pkgver-pkgrel is published, signed, uploaded, and
then skipped on every machine that already has that version: `genesi update`
says the system is current and it is, by the only measure pacman has.

That is what happened to genesi-center. It was written, published at 0.1.0-1,
and then rewritten three times -- the grouped rail, the animations, the
artwork -- with the pkgrel left at 1 each time. The repository ended up holding
the newest code under a version number the reporter's machine already had, so
"I updated and the app did not change" was exactly true.

It is the same family as the two failures this repository already guards:
built-but-installed-by-nobody, and published-but-never-built. The package
exists, it is correct, and it reaches no one.

The check: for every package whose files changed since the last publish, the
version in its PKGBUILD must differ from the version of the artifact currently
in repo/x86_64. Comparing against the PUBLISHED artifact rather than against
the previous commit is what makes it right -- several commits can touch a
package between two publishes, and only one bump is needed for all of them.
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKGDIR = os.path.join(ROOT, "genesi-arch", "packages")
REPODIR = "genesi-arch/repo/x86_64"


def git(*args):
    try:
        p = subprocess.run(("git",) + args, cwd=ROOT, capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        return p.stdout if p.returncode == 0 else ""
    except OSError:
        return ""


def last_publish():
    """
    The commit whose contents produced what is in repo/x86_64 right now.

    publish-packages.yml records it in its own commit message ("publish
    packages from <sha>"), which is more honest than using the publish commit
    itself: the publish lands AFTER the build, so the tree it describes is the
    one that was actually built.
    """
    log = git("log", "--grep=publish packages from", "-1", "--format=%s")
    m = re.search(r"publish packages from ([0-9a-f]{7,40})", log)
    return m.group(1) if m else None


def pkg_meta(d):
    """(pkgname, pkgver, pkgrel) declared by a package directory."""
    p = os.path.join(PKGDIR, d, "PKGBUILD")
    if not os.path.exists(p):
        return None
    with io.open(p, encoding="utf-8", errors="replace") as fh:
        src = fh.read()

    def field(name):
        m = re.search(r"^%s=([^\s#]+)" % name, src, re.M)
        return m.group(1).strip("'\"") if m else None

    name = field("pkgname")
    ver = field("pkgver")
    rel = field("pkgrel")
    if not name or not ver or not rel:
        return None
    # A pkgver computed by pkgver() cannot be compared textually; those
    # packages get a fresh version from git on every build anyway.
    if not re.fullmatch(r"[0-9A-Za-z._:+~-]+", ver):
        return None
    return name, ver, rel


def published():
    """pkgname -> "pkgver-pkgrel" currently in the repo directory."""
    out = {}
    listing = git("ls-tree", "--name-only", "HEAD", REPODIR + "/")
    for line in listing.splitlines():
        fn = os.path.basename(line)
        if not fn.endswith(".pkg.tar.zst"):
            continue
        m = re.fullmatch(r"(.+)-([^-]+)-([^-]+)-(any|x86_64)\.pkg\.tar\.zst", fn)
        if not m:
            continue
        out[m.group(1)] = f"{m.group(2)}-{m.group(3)}"
    return out


def main():
    print("== pkgrel bumps ==")
    base = last_publish()
    if not base:
        print("  SKIP  no publish commit found; nothing to compare against")
        return 0
    if not git("cat-file", "-e", base + "^{commit}") and not git(
            "rev-parse", "--verify", base + "^{commit}"):
        print(f"  SKIP  {base} is not in this checkout (shallow clone?)")
        return 0

    have = published()
    stale = []
    checked = 0

    for d in sorted(os.listdir(PKGDIR)):
        meta = pkg_meta(d)
        if meta is None:
            continue
        name, ver, rel = meta
        if name not in have:
            continue          # never published; nothing to be stale against
        rel_path = f"genesi-arch/packages/{d}"
        # base..HEAD compares COMMITS and ignores the working tree, so running
        # this before committing reported nothing changed -- which is exactly
        # when a person wants to be told. Diffing base against the tree covers
        # both: in CI the tree is HEAD.
        changed = git("diff", "--name-only", base, "--", rel_path)
        if not changed.strip():
            continue
        checked += 1
        if f"{ver}-{rel}" == have[name]:
            stale.append((d, name, have[name],
                          [l for l in changed.splitlines()][:4]))

    print(f"  compared against {base[:8]}; {checked} package(s) changed since")

    if stale:
        print("  FAIL  package(s) changed without a new version:")
        for d, name, v, files in stale:
            print(f"          {d}: still {v}")
            for f in files:
                print(f"            - {f}")
        print()
        print("        pacman compares VERSIONS, not contents. Republished at")
        print("        the same pkgver-pkgrel, this reaches every machine that")
        print("        already has it as 'nothing to do' -- the newest code")
        print("        sitting in the repository under a version they have.")
        print("        Bump pkgrel.")
        return 1

    print("  PASS  every changed package carries a new version")
    print("\npkgrel bumps: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
