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

        for k in sorted(set(bar) - BAR_KEYS):
            bad.append((pid, f"sets bar.{k}, which the bar does not have"))

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
