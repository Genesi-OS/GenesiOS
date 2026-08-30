#!/usr/bin/env python3
"""
caelestia-actions-test.py — our launcher action list must not fall behind theirs.

── The trap ─────────────────────────────────────────────────────────────────

caelestia's launcher reads its `>` actions from `GlobalConfig.launcher.actions`.
That is configuration, not code, which is why Genesi can add entries without
overriding a single QML file — a much better deal than the page overrides.

The catch is that `actions` is ONE property:

    CONFIG_GLOBAL_PROPERTY(QVariantList, actions, { …fourteen defaults… })

Setting it in shell.json REPLACES upstream's list wholesale. It does not merge.
So our file has to carry every default of theirs plus ours, and the day
upstream adds a fifteenth, Genesi users silently stop getting it — no error, no
warning, just an action that exists everywhere except here.

Nobody would notice that for months. This notices immediately.

Run with the upstream source available (the caelestia tarball, extracted):

    caelestia-actions-test.py <path/to/launcherconfig.hpp> [shell.json]

genesi-caelestia-shell's prepare() calls it, because that is where the upstream
source is on disk. Without an argument it self-checks what it can and says so.
"""
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKG = os.path.join(ROOT, "genesi-arch", "packages", "genesi-caelestia-settings")
DEFAULT_SHELL_JSON = os.path.join(PKG, "shell.json")
PKGBUILD = os.path.join(PKG, "PKGBUILD")
HYPRCONF = os.path.join(PKG, "hyprland.conf")

# Binaries that are on the machine because something else already guarantees
# them: base, systemd, and the shell this config belongs to. Everything NOT on
# this list has to be a declared dependency -- see check_commands_resolve.
ALWAYS_PRESENT = {
    "sh", "systemctl", "loginctl",   # base / systemd
    "hyprctl", "caelestia",          # hyprland + the shell itself
}

# Not commands at all: the launcher interprets these itself.
PSEUDO = {"autocomplete", "setMode"}

# Binaries whose package is named something else. Kept explicit rather than
# guessed: a wrong guess here would make the check pass while the key still
# does nothing, which defeats the entire point of the file.
BINARY_PACKAGE = {
    "wpctl": "wireplumber",
    "wl-copy": "wl-clipboard",
    "wl-paste": "wl-clipboard",
}


def providers(binary):
    """Package names that would put `binary` on the machine."""
    return {binary, BINARY_PACKAGE.get(binary, binary)}


def declared_deps(path):
    """Names in depends=() -- enough for this, no need to parse PKGBUILD fully."""
    with io.open(path, encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r"^depends=\((.*?)^\)", src, re.M | re.S)
    if not m:
        return None
    body = re.sub(r"#.*", "", m.group(1))
    return {re.split(r"[<>=]", n.strip("'\""))[0] for n in body.split()}


def check_commands_resolve(cfg):
    """
    Every command an action runs must be INSTALLED when the action exists.

    This check exists because it already went wrong. genesi-display was built,
    published, and referenced by six launcher entries -- and nothing depended on
    it, so it was never installed on anybody's machine. The entries showed up in
    the launcher and clicking them did nothing whatsoever: Quickshell's
    execDetached does not report a missing binary anywhere the user can see.

    An action that silently does nothing is worse than no action: it is the
    feature appearing to be broken rather than absent. Shipping the entry and
    the dependency is one decision, so make the build enforce it as one.
    """
    deps = declared_deps(PKGBUILD)
    if deps is None:
        print("  FAIL  could not read depends=() from the PKGBUILD")
        return False

    needed = {}
    for a in cfg.get("launcher", {}).get("actions", []):
        cmd = a.get("command") or []
        if not cmd or cmd[0] in PSEUDO:
            continue
        needed.setdefault(cmd[0], []).append(a.get("name", "?"))

    bad = False
    for binary, users in sorted(needed.items()):
        if binary in ALWAYS_PRESENT or providers(binary) & deps:
            continue
        bad = True
        print(f"  FAIL  {len(users)} launcher action(s) run {binary!r}, and "
              "nothing installs it:")
        for n in users:
            print(f"          - {n}")
        print(f"        Add {binary!r} to depends=() in the PKGBUILD, or drop")
        print("        the actions. Shipped as-is they appear in the launcher")
        print("        and do nothing at all when clicked.")
    if not bad:
        print(f"  PASS  all {len(needed)} command(s) the actions run are installed")

    # The keybinds are the same actions on the keyboard, and fail the same
    # silent way -- a bind to a missing binary is a key that does nothing.
    if os.path.exists(HYPRCONF):
        with io.open(HYPRCONF, encoding="utf-8") as fh:
            conf = fh.read()
        bound = set(re.findall(r"^\s*bind[a-z]*\s*=.*?,\s*exec\s*,\s*(\S+)",
                               conf, re.M))
        unmet = sorted(b for b in bound
                       if b not in ALWAYS_PRESENT and not providers(b) & deps
                       and not b.startswith("$"))
        if unmet:
            print("  FAIL  keybinds run binaries nothing installs: "
                  + ", ".join(unmet))
            print("        Add the providing package to depends=(), or map the")
            print("        binary to its package name in BINARY_PACKAGE here.")
            bad = True
        else:
            print(f"  PASS  all {len(bound)} keybind target(s) are installed")

    return not bad


def our_actions(path):
    with io.open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    return [a.get("name", "") for a in cfg.get("launcher", {}).get("actions", [])]


def upstream_actions(hpp_path):
    """
    The default names, read out of the C++ initialiser list.

    Deliberately name-only. Matching the commands too would fail every time
    upstream tweaks a flag, and the question here is narrower: did a whole
    action appear that we do not carry?
    """
    with io.open(hpp_path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    idx = src.find("actions,")
    if idx < 0:
        return None
    return re.findall(r'u"name"_s,\s*u"([^"]+)"_s', src[idx:])


def main():
    args = [a for a in sys.argv[1:]]
    shell_json = DEFAULT_SHELL_JSON
    hpp = None
    if args:
        hpp = args[0]
    if len(args) > 1:
        shell_json = args[1]

    if not os.path.exists(shell_json):
        print(f"missing {shell_json}")
        return 1
    ours = our_actions(shell_json)

    print("== caelestia launcher actions ==")
    print(f"  ours:     {len(ours)}")

    # Genesi's own entries must survive any edit to this file. If someone
    # regenerates shell.json from upstream's defaults and forgets these, the
    # features go away silently — the same failure this file exists to stop,
    # pointed the other way.
    required_ours = ["Scale 100%", "Scale 150%", "Rotate screen", "Reset display"]
    missing_ours = [n for n in required_ours if n not in ours]
    if missing_ours:
        print("  FAIL  Genesi's own actions are gone from shell.json:")
        for n in missing_ours:
            print(f"          - {n}")
        return 1
    print(f"  PASS  Genesi's own actions are present")

    # The Logout action is a correctness fix, not a preference. caelestia's
    # default is `loginctl terminate-user ""`, which kills every user process
    # at once (sddm-helper included, mid-teardown) and leaves an infinite black
    # screen on real hardware -- fixed for the session drawer in
    # genesi-caelestia-settings pkgrel 17, but the LAUNCHER has its own copy of
    # that command and was never covered.
    with io.open(shell_json, encoding="utf-8") as fh:
        cfg = json.load(fh)
    for a in cfg.get("launcher", {}).get("actions", []):
        if a.get("name") == "Logout":
            if a.get("command") == ["hyprctl", "dispatch", "exit"]:
                print("  PASS  the launcher's Logout uses the clean session exit")
            else:
                print("  FAIL  the launcher's Logout is back to "
                      f"{a.get('command')!r} -- that is the infinite black "
                      "screen fixed in settings pkgrel 17, through the other door")
                return 1
            break

    if not check_commands_resolve(cfg):
        return 1

    if not hpp:
        print("  SKIP  no upstream launcherconfig.hpp given; drift not checked")
        print("\ncaelestia launcher actions: OK (partial)")
        return 0

    up = upstream_actions(hpp)
    if up is None:
        print(f"  FAIL  could not find the actions defaults in {hpp} --")
        print("        upstream restructured the config and this check is blind")
        return 1

    print(f"  upstream: {len(up)}")
    missing = [n for n in up if n not in ours]
    if missing:
        print("  FAIL  caelestia has launcher actions our shell.json does not:")
        for n in missing:
            print(f"          - {n}")
        print("        launcher.actions REPLACES upstream's list rather than")
        print("        merging, so Genesi users would silently lose these.")
        print("        Add them to genesi-caelestia-settings/shell.json, or")
        print("        decide against one and record why.")
        return 1

    print(f"  PASS  all {len(up)} upstream defaults are carried")
    print("\ncaelestia launcher actions: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
