#!/usr/bin/env python3
"""
bar-presets-test.py — a bar preset must describe a bar that can exist.

caelestia's bar is built by a DelegateChooser keyed on each entry's `id`. An id
it does not recognise matches no DelegateChoice, so the entry renders as
nothing: no error, no gap, no warning anywhere. A preset with one typo is a
launcher row that visibly does something -- the bar redraws -- while quietly
dropping a component.

That is the same silent shape as the shader that did not compile and the
launcher action whose binary was never installed, and it gets the same
treatment: checked at build time rather than noticed on a desk.

Four things have to line up, and each has already gone wrong somewhere in this
repository:

  * every entry id is one Bar.qml answers to
  * every preset is valid JSON with the fields genesi-bar reads
  * every preset has a launcher action, and every bar action names a preset
    that exists -- an action pointing at a missing preset fails at the CLI,
    and a preset with no action is invisible
  * the ids genesi-bar accepts match the ids listed here
"""
import ast
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKG = os.path.join(ROOT, "genesi-arch", "packages", "genesi-caelestia-settings")
PRESETS = os.path.join(PKG, "bar-presets")
SHELL_JSON = os.path.join(PKG, "shell.json")
CLI = os.path.join(PKG, "genesi-bar")

# Read from Bar.qml's DelegateChooser, not from documentation:
#   DelegateChoice { roleValue: "workspaces" ... }
VALID = {"spacer", "logo", "workspaces", "activeWindow", "tray", "clock",
         "statusIcons", "power"}

# Config keys the bar actually has, from barconfig.hpp. A preset may only set
# these; anything else is ignored in silence exactly like a bad entry id.
BAR_KEYS = {
    "entries", "persistent", "showOnHover", "dragThreshold", "excludedScreens",
    "scrollActions", "popouts", "workspaces", "activeWindow", "tray", "status",
    "clock",
}

# Ours, not upstream's: caelestia exposes what the bar CONTAINS and nothing
# about how it is drawn, so ten presets could only ever differ by module order.
# patch_bar_proportions adds these two, and they are checked against the code
# that adds them -- a preset setting a property no patch implements is silently
# ignored by the config parser, which is the same shape as an entry id the bar
# does not know.
GENESI_BAR_KEYS = {
    "width": 'CONFIG_PROPERTY(int, width, 0)',
    "spacing": 'CONFIG_PROPERTY(int, spacing, -1)',
}

# The sub-objects, also from barconfig.hpp. Checking only the top level would
# have missed every interesting mistake: a preset is a look, and a look is made
# almost entirely of these -- `showWindows`, `occupiedBg`, `activeTrail`,
# `showDate`. A typo in one of them is dropped by the config parser in exactly
# the same silence as an entry id the bar does not know, except that here the
# bar still redraws and looks nearly right.
SUB_KEYS = {
    "scrollActions": {"workspaces", "volume", "brightness"},
    "popouts": {"activeWindow", "tray", "statusIcons"},
    "workspaces": {"shown", "activeIndicator", "occupiedBg", "showWindows",
                   "showWindowsOnSpecialWorkspaces", "maxWindowIcons",
                   "activeTrail", "perMonitorWorkspaces", "label",
                   "occupiedLabel", "activeLabel", "capitalisation",
                   "specialWorkspaceIcons", "windowIcons"},
    "activeWindow": {"compact", "inverted", "showOnHover"},
    "tray": {"background", "recolour", "compact", "iconSubs", "hiddenIcons"},
    "status": {"showAudio", "showMicrophone", "showKbLayout", "showNetwork",
               "showWifi", "showBluetooth", "showBattery", "showLockStatus"},
    "clock": {"background", "showDate", "showIcon"},
}

GENESI_SUB_KEYS = {
    ("workspaces", "realWindowIcons"):
        'CONFIG_PROPERTY(bool, realWindowIcons, false)',
}

# A preset is a LOOK: the bar, plus the frame the whole desktop sits inside.
# Nothing else -- a preset that could rewrite the launcher or the session
# commands is one nobody should try. genesi-bar refuses those at apply time;
# this refuses them at build time, when there is someone to tell.
LOOK_SECTIONS = ("bar", "border")
BORDER_KEYS = {"thickness", "rounding", "smoothing"}  # borderconfig.hpp


def without_prose(src):
    """
    caelestia-patches.py with its comments and docstrings removed.

    This check asks "does a patch actually add this property", and it asks by
    looking for the declaration in the patch's source. Three guards in this
    repository have already passed on the exact bug they existed to catch,
    because the fix's own comment contained the string being searched for --
    the docstring above a patch is precisely where someone would write
    CONFIG_PROPERTY(bool, realWindowIcons, false) while explaining it.

    String LITERALS stay: the declaration this looks for is inside one, since
    that is how the patch injects it. Only prose goes.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        # Better to check the raw file than to check nothing. A syntax error in
        # the patcher is a build failure of its own, one file over.
        return src
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                             ast.ClassDef)) and ast.get_docstring(node):
            node.body = node.body[1:]
    return ast.unparse(tree)


def main():
    print("== caelestia bar presets ==")
    if not os.path.isdir(PRESETS):
        print(f"  FAIL  {PRESETS} does not exist")
        return 1

    files = sorted(f for f in os.listdir(PRESETS) if f.endswith(".json"))
    if not files:
        print("  FAIL  no presets found")
        return 1

    bad = []
    ids = []
    for fn in files:
        pid = fn[:-5]
        ids.append(pid)
        path = os.path.join(PRESETS, fn)
        try:
            with io.open(path, encoding="utf-8") as fh:
                p = json.load(fh)
        except (OSError, json.JSONDecodeError) as e:
            bad.append((pid, f"is not valid JSON: {e}"))
            continue

        for field in ("name", "description", "bar"):
            if not p.get(field):
                bad.append((pid, f"has no {field!r}"))

        bar = p.get("bar")
        if not isinstance(bar, dict):
            continue

        for k in sorted(set(p) - {"name", "description"} - set(LOOK_SECTIONS)):
            bad.append((pid, f"sets {k!r}, which is not part of a bar look"))

        border = p.get("border")
        if border is not None:
            if not isinstance(border, dict):
                bad.append((pid, "has a border that is not an object"))
            else:
                for k in sorted(set(border) - BORDER_KEYS):
                    bad.append((pid, f"sets border.{k}, which the frame does "
                                     "not have"))

        for k in sorted(set(bar) - BAR_KEYS - set(GENESI_BAR_KEYS)):
            bad.append((pid, f"sets bar.{k}, which the bar does not have"))

        for sub, keys in SUB_KEYS.items():
            got = bar.get(sub)
            if got is None:
                continue
            if not isinstance(got, dict):
                bad.append((pid, f"has a bar.{sub} that is not an object"))
                continue
            ours = {k for (s, k) in GENESI_SUB_KEYS if s == sub}
            for k in sorted(set(got) - keys - ours):
                bad.append((pid, f"sets bar.{sub}.{k}, which the bar does not "
                                 "have -- it is dropped in silence"))

        entries = bar.get("entries")
        if not isinstance(entries, list) or not entries:
            bad.append((pid, "has no entries, so the bar would be empty"))
            continue
        for e in entries:
            if not isinstance(e, dict) or "id" not in e:
                bad.append((pid, f"has a malformed entry: {e!r}"))
                continue
            if e["id"] not in VALID:
                bad.append((pid, f"names the entry {e['id']!r}, which Bar.qml "
                                 "does not know -- it would render as nothing"))
        if not any(e.get("enabled") for e in entries if isinstance(e, dict)):
            bad.append((pid, "enables nothing, so the bar would be blank"))

    print(f"  presets: {len(files)}")

    # A Genesi-only property must be implemented by the patch that claims to
    # add it. Read from the code, not from the comments explaining it.
    patches = os.path.join(ROOT, "genesi-arch", "ci", "caelestia-patches.py")
    psrc = ""
    if os.path.exists(patches):
        with io.open(patches, encoding="utf-8") as fh:
            psrc = fh.read()
        psrc = without_prose(psrc)
    used = set()
    for fn in files:
        try:
            with io.open(os.path.join(PRESETS, fn), encoding="utf-8") as fh:
                used |= set((json.load(fh).get("bar") or {}))
        except (OSError, json.JSONDecodeError):
            pass
    used_sub = set()
    for fn in files:
        try:
            with io.open(os.path.join(PRESETS, fn), encoding="utf-8") as fh:
                b = json.load(fh).get("bar") or {}
        except (OSError, json.JSONDecodeError):
            continue
        for sub, got in b.items():
            if isinstance(got, dict):
                used_sub |= {(sub, k) for k in got}

    for k in sorted(used & set(GENESI_BAR_KEYS)):
        if psrc and GENESI_BAR_KEYS[k] not in psrc:
            bad.append(("caelestia-patches.py",
                        f"no patch adds bar.{k}, but a preset sets it"))
    for key in sorted(used_sub & set(GENESI_SUB_KEYS)):
        if psrc and GENESI_SUB_KEYS[key] not in psrc:
            bad.append(("caelestia-patches.py",
                        f"no patch adds bar.{key[0]}.{key[1]}, but a preset "
                        "sets it"))

    # genesi-bar decides which sections it will write. If it stops writing
    # `border`, every preset here that leans on the frame becomes a preset that
    # changes the bar and leaves the desktop looking like the last one.
    if os.path.exists(CLI):
        with io.open(CLI, encoding="utf-8") as fh:
            cli = fh.read()
        m = re.search(r"LOOK_SECTIONS = \((.*?)\)", cli, re.S)
        if not m:
            bad.append(("genesi-bar", "no longer declares LOOK_SECTIONS"))
        elif set(re.findall(r'"([^"]+)"', m.group(1))) != set(LOOK_SECTIONS):
            bad.append(("genesi-bar",
                        f"applies {m.group(1).strip()}, this checks "
                        f"{list(LOOK_SECTIONS)}"))

    # The CLI's own list of valid ids must agree with this one, or it will
    # accept a preset the bar then drops.
    if os.path.exists(CLI):
        with io.open(CLI, encoding="utf-8") as fh:
            src = fh.read()
        m = re.search(r"VALID_ENTRIES = \{(.*?)\}", src, re.S)
        if not m:
            bad.append(("genesi-bar", "no longer declares VALID_ENTRIES"))
        else:
            cli_ids = set(re.findall(r'"([^"]+)"', m.group(1)))
            if cli_ids != VALID:
                bad.append(("genesi-bar",
                            f"accepts {sorted(cli_ids)}, this checks "
                            f"{sorted(VALID)}"))

    # Every preset needs a way in, and every way in needs a preset.
    if os.path.exists(SHELL_JSON):
        with io.open(SHELL_JSON, encoding="utf-8") as fh:
            cfg = json.load(fh)
        actions = cfg.get("launcher", {}).get("actions", []) or []
        applied = [a.get("command", []) for a in actions
                   if (a.get("command") or [""])[0] == "genesi-bar"]
        named = {c[2] for c in applied if len(c) > 2}

        for pid in ids:
            if pid not in named:
                bad.append((pid, "has no launcher action, so nothing reaches it"))
        for n in sorted(named - set(ids)):
            bad.append((n, "is named by a launcher action but no preset exists"))

    if bad:
        print(f"  FAIL  {len(bad)} problem(s):")
        for pid, why in bad:
            print(f"          {pid}: {why}")
        print()
        print("        The bar drops an entry it does not recognise without")
        print("        saying anything, so this ships as a preset that looks")
        print("        applied and is missing a piece.")
        return 1

    print(f"  PASS  every preset names only entries the bar renders, and every")
    print(f"        one is reachable from the launcher")
    print("\ncaelestia bar presets: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
