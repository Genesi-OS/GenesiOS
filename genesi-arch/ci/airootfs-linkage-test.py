#!/usr/bin/env python3
"""
airootfs-linkage-test.py — does every binary we ship still have its libraries?

── Why this exists ───────────────────────────────────────────────────────────

On 2026-08-29 an ISO was built, boot-tested, published, and could not install
anything:

    calamares: error while loading shared libraries:
    libboost_python314.so.1.91.0: cannot open shared object file

boost had gone 1.91 -> 1.92 and cachyos-calamares-next was still linked against
the old soname. Every check in the pipeline passed. They had to: a dependency
dry-run asks whether package NAMES resolve, and they did — `boost-libs` was
installed, just a different build of it. The boot test asks whether the image
starts, and it did, perfectly. Nothing anywhere asked the one question that
mattered, which is whether the binaries inside can actually run.

An ISO that boots and cannot install is the worst shape a release can take: it
looks fine right up to the click the whole thing exists for.

This reads the ELF headers directly — no chroot, no ldd, no emulation. For every
binary and shared object of interest it collects DT_NEEDED and checks that a
file with that soname exists somewhere in the image's library paths. It is a
few seconds over a few hundred files and it catches the entire class.

── Exit codes ────────────────────────────────────────────────────────────────

    0  every checked binary has its libraries
    1  something would fail to start  -> do not publish
    2  could not be checked (no airootfs to look at)

Usage:
    airootfs-linkage-test.py <airootfs-dir> [--all]

Without --all it checks the binaries whose failure would be visible to a user:
the installer, everything Genesi ships, and the libraries those pull in.
"""
import os
import struct
import sys

# ── A very small ELF reader ───────────────────────────────────────────────────
#
# Only what is needed: the dynamic section's DT_NEEDED and DT_SONAME strings.
# Using a library here would mean installing one in the build container for a
# check whose whole appeal is that it is cheap and has no moving parts.

DT_NEEDED, DT_STRTAB, DT_SONAME, DT_STRSZ, DT_NULL = 1, 5, 14, 10, 0


def _read_elf(path):
    """Return (needed[], soname) or None when the file is not a 64-bit ELF."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2:
        return None                      # not ELF, or not 64-bit
    little = data[5] == 1
    end = "<" if little else ">"

    e_phoff, = struct.unpack_from(end + "Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from(end + "HH", data, 0x36)

    # Find PT_DYNAMIC (2) and remember the LOAD segments so a virtual address
    # can be turned back into a file offset.
    dyn = None
    loads = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if off + 56 > len(data):
            return None
        p_type, = struct.unpack_from(end + "I", data, off)
        p_offset, p_vaddr = struct.unpack_from(end + "QQ", data, off + 0x08)
        p_filesz, = struct.unpack_from(end + "Q", data, off + 0x20)
        if p_type == 2:
            dyn = (p_offset, p_filesz)
        elif p_type == 1:
            loads.append((p_vaddr, p_offset, p_filesz))
    if dyn is None:
        return ([], None)                # statically linked: nothing to resolve

    def vaddr_to_off(v):
        for p_vaddr, p_offset, p_filesz in loads:
            if p_vaddr <= v < p_vaddr + p_filesz:
                return p_offset + (v - p_vaddr)
        return None

    d_off, d_size = dyn
    entries = []
    strtab_v = strsz = None
    for i in range(d_size // 16):
        off = d_off + i * 16
        if off + 16 > len(data):
            break
        tag, val = struct.unpack_from(end + "qQ", data, off)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            strtab_v = val
        elif tag == DT_STRSZ:
            strsz = val
        entries.append((tag, val))

    if strtab_v is None:
        return ([], None)
    s_off = vaddr_to_off(strtab_v)
    if s_off is None:
        return ([], None)
    strtab = data[s_off:s_off + (strsz or 4096)]

    def s(idx):
        e = strtab.find(b"\x00", idx)
        return strtab[idx:e if e != -1 else None].decode("utf-8", "replace")

    needed = [s(v) for tag, v in entries if tag == DT_NEEDED]
    soname = next((s(v) for tag, v in entries if tag == DT_SONAME), None)
    return (needed, soname)


def main():
    args = [a for a in sys.argv[1:]]
    check_all = "--all" in args
    args = [a for a in args if not a.startswith("--")]
    if not args:
        print("::warning::airootfs-linkage-test: no airootfs directory given")
        print("Binary linkage was NOT verified.")
        return 2
    root = args[0]
    if not os.path.isdir(root):
        print(f"::warning::airootfs-linkage-test: {root} does not exist")
        print("Binary linkage was NOT verified (mkarchiso may have cleaned it).")
        return 2

    # ── Everything the image can offer a linker ──────────────────────────────
    # Indexed by BASENAME. The real loader walks a search path; a soname present
    # anywhere under a lib dir is, for our purposes, present. Being slightly
    # generous here is deliberate: a false alarm would block a good ISO, which
    # is a failure this project has already paid for twice today.
    available = set()
    for libdir in ("usr/lib", "usr/lib32", "lib", "lib64", "usr/local/lib"):
        base = os.path.join(root, libdir)
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in filenames:
                if ".so" in fn:
                    available.add(fn)

    if not available:
        print(f"::warning::no libraries found under {root} — is this an airootfs?")
        return 2

    # ── What to check ────────────────────────────────────────────────────────
    targets = []
    for bindir in ("usr/bin", "usr/lib/calamares", "usr/lib/calamares/modules"):
        base = os.path.join(root, bindir)
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                if os.path.islink(full):
                    continue
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                if check_all:
                    targets.append(rel)
                # The installer, everything Genesi ships, and calamares' own
                # libraries. A missing library in any of these is something the
                # user meets on their first click.
                elif (fn.startswith("genesi") or fn == "calamares"
                      or "calamares" in rel or fn == "calamares-online.sh"):
                    targets.append(rel)

    if not targets:
        print("::warning::found no binaries to check")
        return 2

    print(f"== shared-library linkage ==")
    print(f"root:      {root}")
    print(f"libraries: {len(available)} available")
    print(f"checking:  {len(targets)} binaries")
    print()

    broken = {}
    checked = 0
    for rel in sorted(targets):
        info = _read_elf(os.path.join(root, rel))
        if info is None:
            continue                      # script, data, not an ELF
        needed, _soname = info
        checked += 1
        missing = [n for n in needed if n not in available]
        if missing:
            broken[rel] = missing

    print(f"{checked} ELF binaries read")
    if not broken:
        print()
        print("shared-library linkage: OK")
        return 0

    print()
    for rel, missing in sorted(broken.items()):
        print(f"  BROKEN  {rel}")
        for m in missing:
            print(f"            needs {m} — not in the image")
    print()
    print("::error::binaries in this ISO cannot start: a library they link "
          "against is not in the image.")
    print("::error::This is what an ISO that boots perfectly and installs "
          "nothing looks like. Usually a package built against an older "
          "soname than the one the image now carries — rebuild it, or ship "
          "a build of our own.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
