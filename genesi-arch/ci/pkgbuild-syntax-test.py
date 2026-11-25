#!/usr/bin/env python3
"""Every PKGBUILD and .install has to be valid bash.

A PKGBUILD that does not PARSE fails at the very start of the build with
"Failed to source PKGBUILD" -- after the runner has installed a hundred
dependencies and built whatever came before it in the queue.

The failure that prompted this was one apostrophe:

    optdepends=('python-rembg: ... for Depth's Fine tier')

The apostrophe in "Depth's" closes the single-quoted string. Bash then reads
the rest of the file in the wrong quoting context and reports a syntax error a
hundred and forty lines further down, in a line that is perfectly fine -- so
the error message points at the wrong place as well as arriving late.

`bash -n` reads a file and parses it without running a single command, which
is exactly the check this needs: no side effects, no dependencies, no network,
and it takes milliseconds per file.

With `-O extglob`, because makepkg runs with it on and a vendored CachyOS
PKGBUILD uses `rm -r !(test)`. Checking under stricter rules than the real
build uses would fail a file that works.
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

targets = []
for base, dirs, files in os.walk(ROOT):
    if ".git" in dirs:
        dirs.remove(".git")
    for f in files:
        if f == "PKGBUILD" or f.endswith(".install"):
            targets.append(os.path.join(base, f))
targets.sort()

if not targets:
    print("no PKGBUILDs found -- this test is looking in the wrong place")
    sys.exit(1)

bad = []
for path in targets:
    r = subprocess.run(["bash", "-O", "extglob", "-n", path],
                       capture_output=True, text=True)
    if r.returncode != 0:
        bad.append((os.path.relpath(path, ROOT), r.stderr.strip()))

# ── ...and a source=() entry is a FILENAME, never a path ───────────────────
#
# makepkg strips the directory from every source entry: given
# "catalog/catalog.json" it looks for `catalog.json` in the build directory,
# does not find it, and stops with "catalog.json was not found in the build
# directory and is not a URL". That is how genesi-store failed its first
# build, thirty-three minutes in, after everything before it had been built.
#
# A local file in a subdirectory is installed from ${startdir} in package()
# instead, which is what every other Genesi package does.
SOURCE_BLOCK = re.compile(r"^source=\((.*?)\)\s*$", re.M | re.S)
QUOTED = re.compile(r"""['"]([^'"]+)['"]""")

slashed = []
for path in targets:
    if os.path.basename(path) != "PKGBUILD":
        continue
    text = io.open(path, encoding="utf-8", errors="replace").read()
    block = SOURCE_BLOCK.search(text)
    if not block:
        continue
    for entry in QUOTED.findall(block.group(1)):
        # A url has a scheme, `name::url` renames one, and `$url/archive/...`
        # is a url whose scheme is inside the variable -- all three are
        # downloads, and makepkg is happy with a path in a download. What
        # cannot work is a LOCAL file named with a directory, which is a
        # literal string with a slash and no variable in it.
        if "://" in entry or "::" in entry or "$" in entry:
            continue
        if "/" in entry:
            slashed.append((os.path.relpath(path, ROOT), entry))

print(f"== bash -n over {len(targets)} PKGBUILD/.install file(s) ==")
if bad:
    print(f"\n{len(bad)} do(es) not parse:")
    for rel, why in bad:
        print(f"  FAIL {rel}")
        for line in why.splitlines():
            print(f"         {line}")
    print()
    print("        A PKGBUILD that does not parse fails the build at the")
    print("        moment makepkg sources it, and bash reports the error")
    print("        wherever its quoting finally goes wrong -- which is")
    print("        usually nowhere near the line that broke it.")
    sys.exit(1)

print("  PASS  every one of them parses")

if slashed:
    print(f"\n{len(slashed)} source entry/entries name a path:")
    for rel, entry in slashed:
        print(f"  FAIL {rel}: source=(... \"{entry}\" ...)")
    print()
    print("        makepkg takes the FILENAME out of a source entry and looks")
    print("        for it in the build directory, so a path never resolves:")
    print("        the build stops with \"<file> was not found in the build")
    print("        directory and is not a URL\". Install it from ${startdir}")
    print("        in package() instead, the way genesi-center does.")
    sys.exit(1)

print(f"  PASS  no source entry names a path")
print("\npkgbuild syntax: OK")
