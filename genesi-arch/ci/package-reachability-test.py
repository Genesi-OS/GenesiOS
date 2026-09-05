#!/usr/bin/env python3
"""
package-reachability-test.py — every package we build must reach a machine.

── Why this exists ──────────────────────────────────────────────────────────

Twice now a package has been written, built, published and signed, and then
installed on nobody, because the one line that pulls it in was never added:

  * genesi-display — six launcher actions and three keybinds called it. The
    entries appeared and did nothing at all when clicked. Nothing depended on
    it. Found only because a user said "clicking does nothing".

  * genesi-update-kcm — the update page inside Plasma System Settings. Written,
    published, signed, and absent from every install path, so KDE users had no
    update page while Hyprland users did. Found only by going to look.

Publishing is not shipping. A package in the repository that no install path
names is invisible: no error anywhere, no failed build, no missing file. It
just quietly is not there. That is the worst shape a bug can take, and it is
purely mechanical to detect.

── What counts as reachable ─────────────────────────────────────────────────

  1. a dependency (or optdepend) of genesi-desktop, the shared meta-package
  2. named in a Calamares netinstall group
  3. named in an ISO package list
  4. a dependency of anything already reachable, transitively
  5. listed in NOT_INSTALLED below, with a reason

(4) matters: genesi-update-center is reachable through genesi-desktop, and
genesi-display is reachable through genesi-caelestia-settings. Only the roots
need naming.

(5) is deliberate, not an escape hatch. A package nobody installs may be
perfectly correct -- a build tool, something staged for a future release --
but that has to be a decision somebody wrote down, not an oversight nobody
noticed for months.
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKGDIR = os.path.join(ROOT, "genesi-arch", "packages")

# Deliberately not installed by anything. Each needs a reason: the point is
# that somebody decided, not that somebody forgot.
NOT_INSTALLED = {
    # ── Installed on demand, by size ─────────────────────────────────────────
    # These are hosted on a GitHub Release rather than in [genesi] because they
    # exceed what the repository can carry, and a user asks for them from
    # Welcome or Package Installer. Absent from install paths on purpose.
    "genesi-code":
        "~172 MB; release-hosted, installed from Welcome / Package Installer.",
    "genesi-llama-cpp-cuda":
        "~122 MB and CUDA-only; pulled in by AI Mode Turbo when asked for.",
    "genesi-gaming":
        "large bundle; installed from Welcome / Package Installer "
        "(see the note in genesi-desktop's PKGBUILD).",

    # ── Installed before any package list is read ────────────────────────────
    "genesi-keyring":
        "also a genesi-desktop dependency, but it has to reach a machine "
        "BEFORE that: the ISO ships it and the installer populates it, which "
        "is what makes the signed repository usable at all.",

    # ── Not built at all ─────────────────────────────────────────────────────
    # Absent from publish-packages.yml, so nothing is published and nothing can
    # install them. Listed so the check stays quiet without pretending they are
    # shipping.
    "genesi-hello":
        "superseded by genesi-welcome, which builds from the same repo at a "
        "higher pkgrel and IS installed. Build disabled in 9569af79 and never "
        "re-enabled. Dead source, kept only as history.",
    # ── Discontinued ────────────────────────────────────────────────────────
    "genesi-sandboxes":
        "discontinued. Out of every install path on purpose; still built so "
        "machines that already have it can receive an update.",

    "libpamac-dummy":
        "an escape hatch that was never needed: it CONFLICTS with pamac-aur, "
        "which the KDE-Desktop group installs, so putting it on an install "
        "path would break that install. Not built, not published.",
}


def pkgbuild_field(src, field):
    m = re.search(r"^%s=\((.*?)^\)" % field, src, re.M | re.S)
    if not m:
        m = re.search(r"^%s=\((.*?)\)" % field, src, re.M | re.S)
    if not m:
        return set()
    body = re.sub(r"#.*", "", m.group(1))
    out = set()
    for tok in body.split():
        tok = tok.strip("'\"")
        # optdepends entries are "name: description" -- keep the name.
        tok = tok.split(":")[0]
        name = re.split(r"[<>=]", tok)[0].strip()
        if name:
            out.add(name)
    return out


def read_pkgbuild(pkg):
    p = os.path.join(PKGDIR, pkg, "PKGBUILD")
    if not os.path.exists(p):
        return None
    with io.open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def built_packages():
    """
    Package NAMES we build, mapped to the directory that builds them.

    Keyed on pkgname, not on the directory: genesi-settings-full builds
    `genesi-settings`, and comparing directory names would have reported a
    package that every machine has as installed on nobody. A check that cries
    wolf gets switched off, which would cost more than the bug it looks for.
    """
    out = {}
    for d in sorted(os.listdir(PKGDIR)):
        src = read_pkgbuild(d)
        if src is None:
            continue
        m = re.search(r"^pkgname=\((.*?)\)", src, re.M | re.S)
        names = ([n.strip("'\"") for n in re.sub(r"#.*", "", m.group(1)).split()]
                 if m else None)
        if not names:
            m = re.search(r"^pkgname=([^\s#]+)", src, re.M)
            names = [m.group(1).strip("'\"")] if m else [d]
        for n in names:
            out[n] = d
    return out


def roots():
    """Package names any install path mentions, before dependency expansion."""
    found = {}
    missing = []

    def note(name, where):
        found.setdefault(name, set()).add(where)

    # 1. the shared meta-package
    src = read_pkgbuild("genesi-desktop")
    if src:
        for n in pkgbuild_field(src, "depends") | pkgbuild_field(src, "optdepends"):
            note(n, "genesi-desktop")

    # 2. Calamares netinstall groups. Matched by line rather than parsed: the
    #    file is a submodule and may be absent from a shallow checkout, and a
    #    YAML parser would be a dependency this check does not need.
    for rel in (
        os.path.join("genesi-calamares-config-full", "etc", "calamares",
                     "modules", "netinstall.yaml"),
        os.path.join("genesi-calamares-config-full", "etc", "calamares",
                     "modules", "pacstrap.conf"),
    ):
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            # Refuse to answer rather than answer wrongly. Without the
            # Calamares submodule an entire install path is invisible, and
            # every package reachable only through it reads as installed on
            # nobody -- a false failure, which is how a check earns its way
            # into being switched off.
            missing.append(rel)
            continue
        with io.open(p, encoding="utf-8-sig", errors="replace") as fh:
            for line in fh:
                m = re.match(r"\s*-\s*([A-Za-z0-9][A-Za-z0-9._+-]*)\s*$", line)
                if m:
                    note(m.group(1), os.path.basename(p))

    # 3. ISO package lists
    for sub in ("archiso", "iso"):
        d = os.path.join(ROOT, "genesi-arch", sub)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".x86_64"):
                continue
            with io.open(os.path.join(d, fn), encoding="utf-8",
                         errors="replace") as fh:
                for line in fh:
                    line = line.split("#")[0].strip()
                    if line:
                        note(line, fn)

    return found, missing


def check_unpublished_deps(built):
    """
    A dependency on a package that does not exist yet has to be handed over.

    makepkg refuses to start when a runtime dependency cannot be resolved, and
    a package built earlier in the same CI run is not resolvable: it is not in
    any repository, because this run is what would publish it. Run #480 failed
    exactly there -- genesi-shaders depends on genesi-hyprshade, both new, both
    built minutes apart, neither able to see the other.

    publish-packages.yml already carries the fix as a list of packages to
    `pacman -U` into the build container after building them. This makes the
    list keep up: any Genesi package that depends on another Genesi package
    which is NOT yet published must appear in it.

    Keyed on "not yet published" rather than on every inter-package edge,
    because once a package is in the repo the dependency resolves from there
    and the requirement lapses on its own. Checking every edge would demand
    entries that do nothing.
    """
    # Asked of git, not of the filesystem. genesi-arch/repo/ is in .gitignore
    # while also being tracked -- CI force-adds the built packages -- so a
    # working tree can know the repository's contents perfectly well while
    # having none of the files on disk. Reading the directory reported every
    # published package as missing.
    published = set()
    try:
        out = subprocess.run(
            ["git", "-C", ROOT, "ls-files", "genesi-arch/repo/x86_64"],
            capture_output=True, text=True, timeout=60)
        listing = out.stdout.splitlines()
    except (OSError, subprocess.SubprocessError):
        listing = []
    if not listing:
        d = os.path.join(ROOT, "genesi-arch", "repo", "x86_64")
        listing = [os.path.join(d, f) for f in os.listdir(d)]             if os.path.isdir(d) else []
    for path in listing:
        fn = os.path.basename(path)
        if fn.endswith(".pkg.tar.zst"):
            # name-version-rel-arch.pkg.tar.zst
            published.add(fn.rsplit("-", 3)[0])
    if not published:
        print("  NOTE  no published packages visible; unpublished-dependency "
              "check skipped")
        return True

    wf = os.path.join(ROOT, ".github", "workflows", "publish-packages.yml")
    if not os.path.exists(wf):
        print("  NOTE  publish-packages.yml missing; container-install list "
              "not checked")
        return True
    with io.open(wf, encoding="utf-8") as fh:
        wf_src = fh.read()
    # Anchored on the pacman -U block. The workflow has more than one `case`
    # over package names, and matching the first one found picked the wrong
    # list entirely.
    installed = set()
    anchor = wf_src.find("pacman -U --noconfirm")
    if anchor > 0:
        window = wf_src[max(0, anchor - 2000):anchor]
        for m in re.finditer(r"^\s*(genesi-[\w-]+(?:\|genesi-[\w-]+)+)\)\s*$",
                             window, re.M):
            installed = set(m.group(1).split("|"))   # the last one before it

    # Only packages this pipeline actually builds. genesi-code and
    # genesi-sandboxes are not in its list -- one is release-hosted, the other
    # discontinued -- so an edge between them can never fail a build here.
    pipeline = {p for p in built if f'"{p}"' in wf_src}

    bad = []
    for pkg, directory in sorted(built.items()):
        if pkg not in pipeline:
            continue
        src = read_pkgbuild(directory)
        if not src:
            continue
        for dep in sorted(pkgbuild_field(src, "depends")):
            if dep not in pipeline:
                continue                      # not built by this pipeline
            if dep in published:
                continue                      # resolvable from the repo
            if dep in installed:
                continue                      # handed over in the container
            bad.append((pkg, dep))

    if bad:
        print("  FAIL  dependency on a package that does not exist yet:")
        for pkg, dep in bad:
            print(f"          - {pkg} needs {dep}, which is unpublished")
        print()
        print("        makepkg will not start on a dependency it cannot")
        print("        resolve, and a package built earlier in the same run is")
        print("        in no repository. Add it to the pacman -U list in")
        print("        publish-packages.yml; the entry can go once it has been")
        print("        published once.")
        return False

    print("  PASS  no dependency points at an unpublished package")
    return True


# Package directories CI deliberately does NOT build. Same rule as
# NOT_INSTALLED: a decision somebody wrote down, not an oversight nobody
# noticed. Both of these were checked against the tree rather than assumed.
NOT_BUILT = {
    "genesi-sandboxes":
        "dropped from genesi-desktop at pkgrel 11 -- its UI was broken and the "
        "feature was withdrawn. The PKGBUILD is kept for whoever picks it up.",
    "libpamac-dummy":
        "a stub that only satisfies libpamac-aur's provides during an ISO "
        "install; it carries no code and nothing in [genesi] needs it.",
}


def check_is_built():
    """
    A package directory that CI never builds.

    The other half of this file asks whether a BUILT package reaches a machine.
    This asks the question pointed the other way: does a package that exists,
    and that something depends on, actually get built?

    It did not. genesi-center was written, committed, added to genesi-desktop's
    depends and covered by the reachability check above -- and the list of
    packages CI builds is maintained BY HAND, so it was never in it. The build
    got as far as genesi-desktop and stopped with "dependency was not built:
    genesi-center", forty-five minutes in, having produced nothing.

    That is the same shape as a package nobody installs, which this file already
    catches, so it belongs here rather than in a file of its own.
    """
    wf = os.path.join(ROOT, ".github", "workflows", "publish-packages.yml")
    if not os.path.exists(wf):
        return None
    with io.open(wf, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    m = re.search(r"^\s*PACKAGES=\((.*?)^\s*\)", src, re.M | re.S)
    if not m:
        return None
    # Comments stripped: the block is heavily commented and several package
    # names appear in the prose explaining why a neighbour is where it is.
    body = "\n".join(l for l in m.group(1).splitlines()
                     if not l.lstrip().startswith("#"))
    return set(re.findall(r'"([^"]+)"', body))


def main():
    built = built_packages()   # pkgname -> directory

    # Every package directory must be in the list CI actually builds.
    ci = check_is_built()
    if ci is not None:
        unbuilt = sorted(d for name, d in built.items()
                         if d not in ci and name not in ci
                         and d not in NOT_BUILT and name not in NOT_BUILT
                         # A package whose ABSENCE from every install path is
                         # already a written decision does not need the reason
                         # written twice: genesi-code and genesi-llama-cpp-cuda
                         # are built by publish-apps.yml because of their size,
                         # and genesi-hello was superseded. Not shipped from
                         # here and not built here is coherent.
                         and d not in NOT_INSTALLED and name not in NOT_INSTALLED)
        if unbuilt:
            print("== package reachability ==")
            print("  FAIL  package(s) with a PKGBUILD that CI never builds:")
            for d in unbuilt:
                print(f"          - {d}")
            print("        PACKAGES in .github/workflows/publish-packages.yml is")
            print("        maintained by hand. A package missing from it is not")
            print("        skipped quietly -- anything depending on it fails the")
            print("        whole run, after every other package has been built.")
            print("        If a package is not meant to be built, say so in")
            print("        NOT_BUILT here with the reason.")
            return 1
    found, missing = roots()
    if missing:
        print("== package reachability ==")
        print("  FAIL  an install path is not on disk, so this check cannot")
        print("        tell a shipping package from an orphaned one:")
        for rel in missing:
            print(f"          - {rel}")
        print("        Check out the submodules (actions/checkout with")
        print("        submodules: true) and run again.")
        return 1

    # 4. expand transitively through the depends of everything reachable
    reachable = {n: sorted(w) for n, w in found.items()}
    frontier = [n for n in found if n in built]
    seen = set(frontier)
    while frontier:
        pkg = frontier.pop()
        src = read_pkgbuild(pkg)
        if not src:
            continue
        for dep in pkgbuild_field(src, "depends"):
            if dep not in reachable:
                reachable[dep] = [f"dependency of {pkg}"]
            if dep in built and dep not in seen:
                seen.add(dep)
                frontier.append(dep)

    print("== package reachability ==")
    print(f"  built:     {len(built)}")

    orphans = []
    for pkg in sorted(built):
        if pkg in reachable or pkg in NOT_INSTALLED:
            continue
        orphans.append(pkg)

    # A stale exemption is its own bug: it says "we decided not to install
    # this" about something that is, in fact, installed.
    # genesi-keyring is legitimately both -- see its reason -- so it is not
    # a stale exemption.
    stale = [p for p in NOT_INSTALLED
             if p in reachable and p != "genesi-keyring"]
    for p in stale:
        print(f"  NOTE  {p} is listed as deliberately not installed, but "
              f"{reachable[p][0]} installs it -- drop the exemption.")

    if orphans:
        print(f"  FAIL  {len(orphans)} package(s) are built and published, and "
              "no install path names them:")
        for p in orphans:
            d = built[p]
            print(f"          - {p}" + (f"  (packages/{d})" if d != p else ""))
        print()
        print("        They will be signed, uploaded, and installed on nobody.")
        print("        Add each to an install path (genesi-desktop's depends,")
        print("        a netinstall group, an ISO package list, or the depends")
        print("        of something already installed), or to NOT_INSTALLED in")
        print("        this file with the reason it stays out.")
        return 1

    print(f"  PASS  every built package reaches a machine "
          f"({len(NOT_INSTALLED)} exempt, by decision)")

    if not check_unpublished_deps(built):
        return 1

    print("\npackage reachability: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
