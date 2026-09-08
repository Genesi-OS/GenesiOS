#!/usr/bin/env python3
"""
eol-test.py — every script with a shebang must be pinned to LF.

A CRLF shebang is `bad interpreter: /usr/bin/env python3^M` on the installed
system. The package builds, it installs, the file is on disk, and the program
does not start. Nothing upstream of that says a word about it.

Git only produces one if a committer has core.autocrlf on and the file has no
eol attribute -- so the fix is an attribute per file, and this is the thing that
notices when one is missing.

It cannot be a pattern in .gitattributes. Most of these files have no extension
at all, and gitattributes has no way to say "a file with no extension"; the
list has to be explicit, which means it has to be checked.

Two failures, and the second one matters more:

  * a shebang file with no eol rule -- the next person with autocrlf breaks it
  * a shebang file already committed WITH a CRLF in it -- already broken
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True,
                          text=True).stdout


def main():
    files = [f for f in git("ls-files").splitlines() if f]

    shebang = []
    for rel in files:
        path = os.path.join(ROOT, rel)
        try:
            with open(path, "rb") as fh:
                if fh.read(2) == b"#!":
                    shebang.append(rel)
        except OSError:
            continue

    if not shebang:
        print("no scripts found -- this test is looking in the wrong place")
        return 1

    # `git check-attr` in ONE call: one process per file over a repo this size
    # is slow enough that people stop running the guard.
    #
    # BYTES, not text=True. On Windows text mode translates the newlines in the
    # INPUT as well as the output, so every path reaches git with a trailing
    # \r, matches nothing, and comes back "unspecified" -- which reads exactly
    # like "nothing is pinned" and would have had somebody pin 135 files that
    # were already fine. It would also have passed on Linux, where text mode
    # changes nothing, so the guard would have been wrong only where it was run.
    proc = subprocess.run(["git", "check-attr", "eol", "--stdin"], cwd=ROOT,
                          input=("\n".join(shebang) + "\n").encode("utf-8"),
                          capture_output=True)
    attrs = {}
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        # "<path>: eol: <value>", and a path may contain ": " -- so split from
        # the right, twice.
        rest, _, value = line.rpartition(": ")
        path, _, _ = rest.rpartition(": ")
        attrs[path] = value.strip()

    unpinned = [f for f in shebang if attrs.get(f) != "lf"]

    # The COMMITTED blob, not the working copy.
    #
    # A checkout on Windows can hold CRLF for a file whose blob is LF -- an old
    # checkout from before the attribute existed, or core.autocrlf. Checking the
    # working copy makes this fail on every Windows clone while the repository
    # is perfectly fine, and a guard that cries wolf on a whole platform is a
    # guard people learn to skip. What ships is the blob; the blob is what this
    # reads.
    crlf = []
    for rel in shebang:
        blob = subprocess.run(["git", "show", "HEAD:" + rel], cwd=ROOT,
                              capture_output=True)
        if b"\r\n" in blob.stdout:
            crlf.append(rel)

    print("== end of line ==")
    print("  scripts with a shebang: %d" % len(shebang))

    if crlf:
        print("  FAIL  %d already carry a CRLF:" % len(crlf))
        for f in crlf:
            print("          " + f)
    if unpinned:
        print("  FAIL  %d have no `eol=lf` rule in .gitattributes:"
              % len(unpinned))
        for f in unpinned:
            print("          " + f)

    if crlf or unpinned:
        print()
        print("        A CRLF shebang installs fine and then refuses to run:")
        print("        `bad interpreter: /usr/bin/env python3^M`. Add the path")
        print("        to .gitattributes with `text eol=lf`.")
        return 1

    print("  PASS  every one is pinned to LF")
    print()
    print("end of line: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
