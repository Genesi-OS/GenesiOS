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
    "hyprshade": "genesi-hyprshade",
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
    required_ours = ["Scale 100%", "Scale 150%", "Rotate screen", "Reset display",
                     "Make this screen primary", "Mouse faster", "Mouse slower"]
    # Matched as a PREFIX, not for equality. Genesi's own entries carry a
    # Portuguese half after a "·" -- the launcher searches the action NAME and
    # nothing else, so an English-only name is unfindable to someone typing
    # "escala" or "girar", which is most of this distro's users. Upstream's
    # entries are checked for equality further down and must stay exact; these
    # are ours to name. A prefix still catches the thing this guard is for:
    # an action being deleted or renamed away.
    missing_ours = [n for n in required_ours
                    if not any(o == n or o.startswith(n + " ") for o in ours)]
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

    # ── Findable in the language people type ────────────────────────────────
    #
    # The launcher searches the action NAME and nothing else -- not the
    # description (verified against upstream's Searcher: `key: "name"`, and
    # Actions.qml overrides neither `key` nor `keys`). So an English-only name
    # is unreachable to someone typing "escala", "girar" or "principal", which
    # is most of this distro's users. Measured against upstream's own fzf.js:
    # every Portuguese term returned ZERO results before this.
    #
    # Searching the description instead was tried and is WORSE: fzf matches a
    # subsequence, so long haystacks return nonsense -- "girar" matched
    # "Scale 125%" and "parede" matched "Make this screen primary".
    #
    # Upstream's entries are not ours to rename, and the drift check below
    # requires them verbatim. Ours carry both halves, separated by "·".
    # An action is ours when it runs something upstream does not: not one of
    # the launcher's pseudo-commands, and not a binary the base system
    # guarantees. Checking for a "genesi-" prefix instead let the hyprshade
    # entries slip past this untranslated.
    genesi_actions = [
        a for a in cfg.get("launcher", {}).get("actions", [])
        if (a.get("command") or [""])[0] not in PSEUDO
        and (a.get("command") or [""])[0] not in ALWAYS_PRESENT
    ]
    english_only = [a.get("name", "?") for a in genesi_actions
                    if "·" not in a.get("name", "")]
    if english_only:
        print("  FAIL  these Genesi actions have no Portuguese half, so they "
              "cannot be found")
        print("        by anyone searching in Portuguese:")
        for n in english_only:
            print(f"          - {n}")
        print("        Name them \"English · Português\". Do NOT make the search "
              "cover the")
        print("        description instead -- fzf is subsequence-based and that "
              "returns noise.")
        return 1
    if genesi_actions:
        print(f"  PASS  all {len(genesi_actions)} Genesi actions are findable "
              "in both languages")

    # ── Every shader an action names must exist ─────────────────────────────
    #
    # Hyprland leaves the screen untouched when a shader is missing or fails to
    # compile, and reports it nowhere the user looks. So `hyprshade on <name>`
    # pointing at a file nobody ships is another launcher entry that appears to
    # do nothing -- the same shape as an action calling an uninstalled binary,
    # one level down.
    # Flat beside the PKGBUILD: makepkg takes no directory in source=().
    ours_dir = os.path.join(ROOT, "genesi-arch", "packages", "genesi-shaders")
    have = set()
    if os.path.isdir(ours_dir):
        have = {f[:-5] for f in os.listdir(ours_dir) if f.endswith(".glsl")}
    # The two hyprshade ships itself.
    have |= {"blue-light-filter", "vibrance"}

    missing_shaders = []
    for a in cfg.get("launcher", {}).get("actions", []):
        c = a.get("command") or []
        if len(c) == 3 and c[0] == "hyprshade" and c[1] == "on"                 and c[2] not in have:
            missing_shaders.append((a.get("name", "?"), c[2]))
    if missing_shaders:
        print("  FAIL  action(s) turn on a shader that nothing ships:")
        for name, sh in missing_shaders:
            print(f"          - {name} -> {sh}.glsl")
        return 1
    shader_actions = [a for a in cfg.get("launcher", {}).get("actions", [])
                      if (a.get("command") or [""])[0] == "hyprshade"]
    if shader_actions:
        print(f"  PASS  all {len(shader_actions)} shader action(s) name a "
              "shader that exists")

    # ── A group must have a way in ──────────────────────────────────────────
    #
    # An action carrying "group" is hidden from the top level of ">" and
    # reached by typing the group's name, the way ">scheme" reaches the colour
    # schemes. That is what stopped sixteen shader rows from drowning the other
    # twenty-four.
    #
    # It also means a group whose name nothing autocompletes is UNREACHABLE:
    # the rows are installed, correct, and invisible, with no error anywhere --
    # the exact failure mode of the launcher entry that ran a binary nobody
    # installed. So every group must be named by some action's
    # ["autocomplete", <group>], which is the row a person clicks to get there.
    grouped = {}
    for a in cfg.get("launcher", {}).get("actions", []):
        g = a.get("group")
        if g:
            grouped.setdefault(g, []).append(a.get("name", "?"))

    entries = {(a.get("command") or ["", ""])[1]
               for a in cfg.get("launcher", {}).get("actions", [])
               if (a.get("command") or [""])[0] == "autocomplete"}

    orphans = sorted(g for g in grouped if g not in entries)
    if orphans:
        print("  FAIL  action group(s) with nothing to open them:")
        for g in orphans:
            print(f"          \"{g}\" holds {len(grouped[g])} action(s), and no "
                  f"action autocompletes to it")
        print("        Grouped actions are hidden from the top level, so a")
        print("        group with no entry row cannot be reached at all.")
        return 1
    elif grouped:
        print(f"  PASS  all {len(grouped)} action group(s) have an entry row "
              f"({', '.join(sorted(grouped))})")

    # ── The wallpaper transition we ship must be one that exists ────────────
    #
    # background.transition is a string, and Wallpaper.qml falls back to the
    # plain fade for anything it does not recognise. That fallback is right at
    # runtime -- a typo should cost the animation, not the wallpaper -- and it
    # is exactly why a typo HERE would never be noticed: shipping "zoon" would
    # look like a fade forever and report no error anywhere.
    #
    # The names are checked against the QML that reads them, not against a list
    # written here, and against code-shaped anchors rather than the prose that
    # explains them -- the patch script's own docstring spells all four out,
    # and a check that reads it would pass on its own writing.
    TRANSITIONS = {"fade", "zoom", "grow", "none"}
    want = (cfg.get("background") or {}).get("transition")
    if want is not None:
        patches = os.path.join(ROOT, "genesi-arch", "ci",
                               "caelestia-patches.py")
        anchors = {
            "zoom": 'transition === "zoom"',
            "grow": 'transition === "grow"',
            "none": 'transition === "none"',
            "fade": 'QStringLiteral("fade")',
        }
        src = ""
        if os.path.exists(patches):
            with io.open(patches, encoding="utf-8") as fh:
                src = fh.read()
        implemented = {n for n, a in anchors.items() if a in src}

        if want not in TRANSITIONS:
            print(f"  FAIL  shell.json asks for the {want!r} wallpaper "
                  "transition, which is not one of: "
                  + ", ".join(sorted(TRANSITIONS)))
            print("        Wallpaper.qml falls back to a plain fade for an")
            print("        unknown name, so this ships as a setting that")
            print("        silently does nothing.")
            return 1
        if src and want not in implemented:
            print(f"  FAIL  shell.json asks for the {want!r} wallpaper "
                  "transition and caelestia-patches.py does not implement it")
            print("        (looked for the code, not the comments)")
            return 1
        print(f"  PASS  the {want!r} wallpaper transition is implemented "
              f"({len(implemented)} of {len(TRANSITIONS)} available)")

    # ── The migration must MERGE, not seed once ─────────────────────────────
    #
    # shell.json reaches new accounts through /etc/skel and existing ones
    # through _migrate_shell_json. The first version of that merge wrote the
    # action list only when the key was absent, so a user was served once and
    # then frozen: everything added afterwards reached new installs and nobody
    # else, silently. Sixteen shader entries went missing that way, and the
    # symptom was "the shaders are not in `>`" with the package installed.
    #
    # This is the same shape as the /etc/skel gap one level down, so it gets
    # the same treatment: checked, not remembered.
    install = os.path.join(PKG, "genesi-caelestia-settings.install")
    if os.path.exists(install):
        with io.open(install, encoding="utf-8") as fh:
            inst = fh.read()
        if 'if not launcher.get("actions"):' in inst:
            print("  FAIL  the shell.json migration only seeds actions when the")
            print("        key is absent, so an existing user never receives an")
            print("        action added later. Merge by name instead.")
            return 1
        if "shipped_actions" not in inst:
            print("  FAIL  the shell.json migration no longer reads the shipped")
            print("        action list; existing users would get nothing.")
            return 1

        # Appending is not enough either, and that took a second release to
        # learn. A merge that only adds MISSING names never updates an action
        # we already ship, so a correction to one reaches nobody: grouping the
        # shaders changed sixteen existing entries, the merge added the one new
        # row beside them, and ">" went on listing all forty. The first version
        # never wrote twice; the second never rewrote.
        #
        # An action whose name we ship is ours and gets replaced. Anything else
        # is the user's and is kept. Comments stripped before looking, because
        # the paragraph above says "current + added" in prose.
        code = "\n".join(l for l in inst.splitlines()
                          if not l.lstrip().startswith("#"))
        if "current + added" in code:
            print("  FAIL  the shell.json migration only APPENDS actions whose")
            print("        name is missing, so a change to an action we already")
            print("        ship never reaches an existing user.")
            return 1
        if "shipped_actions + theirs" not in code:
            print("  FAIL  the shell.json migration no longer rebuilds the list")
            print("        as ours-then-theirs; changes to shipped actions would")
            print("        stop being delivered.")
            return 1
        print("  PASS  the migration replaces our actions and keeps the user's")

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
