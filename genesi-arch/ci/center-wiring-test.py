#!/usr/bin/env python3
"""
center-wiring-test.py — every page must ask for something that exists.

Genesi Center is three programs that only meet at run time: QML pages, a data
plane that prints JSON, and a writer that touches configs. Nothing checks that
they agree, and each way they can disagree fails in silence:

  * a page asking for a section the data plane does not have gets "{}" back.
    Every field reads undefined, the page draws em-dashes, and it looks like a
    machine with nothing to report rather than a typo.
  * a page running a binary the backend does not allow is refused on stderr.
    Nobody is looking at stderr; the control simply does nothing.
  * a page writing an option the writer does not accept dies inside a
    subprocess whose output is discarded. The slider snaps back on the next
    read and reads as a bug in the slider.
  * a page listening for a signal the backend does not emit never updates at
    all. `ignoreUnknownSignals: true` is on every one of these Connections --
    it has to be, so the pages still render in the offscreen harness -- and it
    means a renamed signal is silently ignored.

All four are the shape this project keeps meeting: something that appears to
work and changes nothing. They are cheap to check statically, so they are.
"""
import ast
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKG = os.path.join(ROOT, "genesi-arch", "packages", "genesi-center")
PAGES = os.path.join(PKG, "app", "pages")
DATA = os.path.join(PKG, "genesi-center-data")
SETTER = os.path.join(PKG, "genesi-center-set")
BACKEND = os.path.join(PKG, "app", "genesi_center.py")


def read(path):
    with io.open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def strip_qml_comments(src):
    """
    QML with its comments gone.

    Three guards in this repository have already passed on the very bug they
    existed to catch, because the fix's own comment contained the string being
    searched for. A page's comments talk about sections and commands
    constantly, so this is not hypothetical here.
    """
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"^\s*//.*$", "", src, flags=re.M)


def strip_prose(src):
    """
    Python with its comments AND docstrings gone.

    String literals stay: the declaration this looks for is inside one, since
    that is how a patch injects it into a C++ header.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return src
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                             ast.ClassDef)) and ast.get_docstring(node):
            node.body = node.body[1:]
    return ast.unparse(tree)


def strip_py_comments(src):
    return re.sub(r"^\s*#.*$", "", src, flags=re.M)


def main():
    print("== genesi center wiring ==")
    for p in (PAGES, DATA, SETTER, BACKEND):
        if not os.path.exists(p):
            print(f"  FAIL  {p} does not exist")
            return 1

    data_src = strip_py_comments(read(DATA))
    m = re.search(r"SECTIONS = \{(.*?)\n\}", data_src, re.S)
    if not m:
        print("  FAIL  genesi-center-data no longer declares SECTIONS")
        return 1
    sections = set(re.findall(r'"([^"]+)":', m.group(1)))

    backend_src = strip_py_comments(read(BACKEND))
    m = re.search(r"ALLOWED = \{(.*?)\}", backend_src, re.S)
    if not m:
        print("  FAIL  the backend no longer declares ALLOWED")
        return 1
    allowed = set(re.findall(r'"([^"]+)"', m.group(1)))

    # Signals the backend emits, so a page cannot listen for one that is gone.
    signals = set(re.findall(r"^\s*(\w+)\s*=\s*Signal\(", backend_src, re.M))
    # Slots a page may call.
    slots = set(re.findall(r"@Slot\([^)]*\)\s*\n\s*def\s+(\w+)", backend_src))

    setter_src = strip_py_comments(read(SETTER))
    hypr_opts = set(re.findall(r'^\s*"([^"]+)":\s*\(',
                               re.search(r"HYPR = \{(.*?)\n\}", setter_src,
                                         re.S).group(1), re.M))
    cael_opts = set(re.findall(r'^\s*"([^"]+)":\s*\(',
                               re.search(r"CAELESTIA_PATHS = \{(.*?)\n\}",
                                         setter_src, re.S).group(1), re.M))

    # Settings the writer accepts that exist only because a Genesi patch adds
    # them. Each names the declaration to look for.
    m = re.search(r"GENESI_ONLY = \{(.*?)\n\}", setter_src, re.S)
    genesi_only = {}
    if m:
        genesi_only = dict(re.findall(
            r'"([^"]+)":\s*\n?\s*[\'"](.+?)[\'"],', m.group(1)))

    bad = []
    files = sorted(f for f in os.listdir(PAGES) if f.endswith(".qml"))
    asked, ran, wrote = set(), set(), set()

    for fn in files:
        src = strip_qml_comments(read(os.path.join(PAGES, fn)))

        for sec in re.findall(r"\.ask\(\s*\"([^\"]+)\"", src):
            asked.add(sec)
            if sec not in sections:
                bad.append((fn, f'asks for the section "{sec}", which '
                                "genesi-center-data does not have -- it would "
                                "get {} and draw dashes for ever"))

        # Every command a page names, wherever it names it.
        #
        # NOT `\.act\(` -- almost every page wraps act() in a local helper
        # (`page.act([...])`, `function set(...)`), so a receiver-anchored
        # pattern matched almost nothing. The first version of this check
        # passed on a page calling `pactl` instead of `wpctl`, which is
        # precisely the bug it was written for.
        for first in re.findall(r"\b(?:act|launch)\(\s*\[\s*\"([^\"]+)\"",
                                src):
            ran.add(first)
            if first not in allowed:
                bad.append((fn, f"runs {first!r}, which the backend's ALLOWED "
                                "list refuses -- the control would do nothing"))

        # `act([...], "section")` re-reads afterwards; that name has to exist.
        for then in re.findall(r"\bact\(\s*\[.*?\]\s*,\s*\"([^\"]+)\"",
                               src, re.S):
            if then not in sections:
                bad.append((fn, f're-reads "{then}" after acting, which is not '
                                "a section"))
        for then in re.findall(r"\bact\(\s*\w+\s*,\s*\"([^\"]+)\"", src):
            if then not in sections:
                bad.append((fn, f're-reads "{then}" after acting, which is not '
                                "a section"))

        # Every option written through the setter must be one it accepts.
        for kind, opt in re.findall(
                r'"genesi-center-set"\s*,\s*"(hypr|caelestia)"\s*,\s*"([^"]+)"',
                src):
            wrote.add(opt)
            table = hypr_opts if kind == "hypr" else cael_opts
            if opt not in table:
                bad.append((fn, f"writes {kind} {opt!r}, which "
                                "genesi-center-set refuses"))
        # ...including the ones passed as a variable through a page helper.
        for kind, var in re.findall(
                r'"genesi-center-set"\s*,\s*"(hypr|caelestia)"\s*,\s*(\w+)\s*,',
                src):
            table = hypr_opts if kind == "hypr" else cael_opts
            for opt in re.findall(r'\b%s\(\s*"([^"]+)"' % re.escape("set"), src):
                wrote.add(opt)
                if opt not in table:
                    bad.append((fn, f"writes {kind} {opt!r} through set(), "
                                    "which genesi-center-set refuses"))

        for sig in re.findall(r"function on([A-Z]\w*)\s*\(", src):
            name = sig[0].lower() + sig[1:]
            if name not in signals:
                bad.append((fn, f"handles the signal {name!r}, which the "
                                "backend does not emit -- with "
                                "ignoreUnknownSignals the page would simply "
                                "never update"))

        for call in re.findall(r"backend\.(\w+)\(", src):
            if call not in slots:
                bad.append((fn, f"calls backend.{call}(), which is not a Slot"))

    # A Genesi-only setting must still be created by the patch that claims to
    # create it. Read from the patcher with its prose stripped: three guards in
    # this repository have passed on the bug they existed to catch because the
    # fix's own comment held the string being searched for, and the docstring
    # above a patch is exactly where someone explains the property it adds.
    patcher = os.path.join(ROOT, "genesi-arch", "ci", "caelestia-patches.py")
    if genesi_only and os.path.exists(patcher):
        psrc = strip_prose(read(patcher))
        for path, decl in sorted(genesi_only.items()):
            if decl not in psrc:
                bad.append(("caelestia-patches.py",
                            f"no patch declares {path!r}, but genesi-center-set "
                            "writes it -- the value would land in shell.json "
                            "and nothing would read it"))

    print(f"  pages: {len(files)}   sections asked: {len(asked)}/{len(sections)}")
    print(f"  genesi-only settings: {len(genesi_only)}")
    print(f"  tools run: {len(ran)}   options written: {len(wrote)}")

    # A section nobody asks for is dead weight, not a failure -- `all` and the
    # tick use several of these. Reported, not failed.
    unused = sorted(sections - asked - {"session", "telemetry", "core",
                                        "storage", "activity"})
    if unused:
        print(f"  note  no page asks for: {', '.join(unused)}")

    if bad:
        print(f"  FAIL  {len(bad)} problem(s):")
        for fn, why in bad:
            print(f"          {fn}: {why}")
        print()
        print("        Every one of these fails in SILENCE at run time: the")
        print("        page renders, the control responds, and nothing")
        print("        happens. That is the failure this app was written to")
        print("        stop repeating.")
        return 1

    print("  PASS  every page asks, runs and writes only what exists")
    print("\ngenesi center wiring: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
