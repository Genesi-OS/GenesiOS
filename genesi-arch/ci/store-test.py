#!/usr/bin/env python3
"""
store-test.py — the Genesi Store catalogue is data that changes a desktop, and
this is what stands between a typo in it and somebody's session.

Two halves.

FIRST, the catalogue is read the way the store reads it, offline, and checked
for the things that would only show up on a real machine:

  * every item has an id, a section that exists, a name and a blurb;
  * every action is one genesi-store implements -- an item asking for
    "run" or "shell" must fail here, loudly, because an item is DATA and the
    day it can carry a command is the day a catalogue is a root shell;
  * every asset is https, from a host on the store's own list, with a size
    and a sha256 -- a download without a checksum is a file that can change
    under us between the build and the install;
  * every `includes` names an item that exists, so a rice cannot promise a
    wallpaper nobody shipped;
  * no item writes outside $HOME except through the two actions that are
    supposed to (`login`, `package`), and those name a fixed vocabulary.

SECOND, apply and revert are RUN -- in process, against a throwaway HOME, with
the one function that reaches outside replaced by a recorder -- for the item
kinds that need no network: a theme, a bar preset, a config file and a session
lock. What is asserted is not that they ran but what revert PUTS BACK,
including the case that matters most: where there was nothing there before,
and "back" means the file is gone again.

Usage: python3 genesi-arch/ci/store-test.py
"""
import importlib.machinery
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PKG = os.path.join(ROOT, "genesi-arch", "packages", "genesi-store")
CLI = os.path.join(PKG, "genesi-store")
CATALOG = os.path.join(PKG, "catalog", "catalog.json")
HELPER = os.path.join(PKG, "genesi-store-helper")

fails = []


def ck(name, ok, detail=""):
    if ok:
        print("  PASS  %s" % name)
    else:
        fails.append(name)
        print("  FAIL  %s%s" % (name, ("\n        " + str(detail)) if detail else ""))


def read(path):
    with io.open(path, encoding="utf-8") as fh:
        return fh.read()


# ── Half one: the catalogue ────────────────────────────────────────────────
print("== the catalogue ==")

cli_src = read(CLI)
# The vocabulary, read out of the CLI rather than repeated here: a test with
# its own copy of the list passes the day the two disagree.
vocab = set(re.findall(r'^\s+"(\w+)": act_\w+,', cli_src, re.M))
hosts = set(re.findall(r'^\s+"([a-z0-9.\-]+)",\s*(?:#.*)?$', cli_src, re.M))
ck("the CLI declares an action vocabulary", len(vocab) >= 5, sorted(vocab))

data = json.loads(read(CATALOG))
items = data.get("items", [])
sections = {s["id"] for s in data.get("sections", [])}
ids = [i.get("id") for i in items]

ck("the catalogue has items", len(items) > 40, len(items))
ck("every id is unique", len(ids) == len(set(ids)))
ck("every id is a safe name",
   all(re.fullmatch(r"[a-z0-9][a-z0-9-]{2,63}", i or "") for i in ids),
   [i for i in ids if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,63}", i or "")])

bad_section = [i["id"] for i in items if i.get("section") not in sections]
ck("every item is on a shelf that exists", not bad_section, bad_section)

missing_copy = [i["id"] for i in items
                if not i.get("name") or not i.get("blurb")]
ck("every item has a name and a line about it", not missing_copy, missing_copy)

unknown = sorted({a.get("action") for i in items for a in i.get("actions", [])}
                 - vocab)
ck("every action is one the store implements", not unknown, unknown)

# An item may not carry anything that looks like a command.
shellish = [i["id"] for i in items
            if re.search(r'"(cmd|command|run|shell|exec|script)"',
                         json.dumps(i))]
ck("no item carries a command", not shellish, shellish)

bad_assets = []
for item in items:
    for name, asset in (item.get("assets") or {}).items():
        url = asset.get("url", "")
        host = url.split("/")[2] if url.startswith("https://") else ""
        if not url.startswith("https://"):
            bad_assets.append((item["id"], name, "not https"))
        elif host not in hosts:
            bad_assets.append((item["id"], name, "host %s" % host))
        elif not re.fullmatch(r"[0-9a-f]{64}", asset.get("sha256", "")):
            bad_assets.append((item["id"], name, "no checksum"))
        elif not isinstance(asset.get("bytes"), int) or asset["bytes"] <= 0:
            bad_assets.append((item["id"], name, "no size"))
ck("every download is https, allow-listed and checksummed",
   not bad_assets, bad_assets)

known = set(ids)
dangling = [(i["id"], ref) for i in items for ref in (i.get("includes") or [])
            if ref not in known]
ck("every collection names items that exist", not dangling, dangling)

outside = []
for item in items:
    for action in item.get("actions", []):
        if action.get("action") == "file":
            path = action.get("path", "")
            if not path.startswith("~/.config/") and not path.startswith("~/.local/"):
                outside.append((item["id"], path))
ck("every file written is inside the user's own config", not outside, outside)

# The two that need root name a fixed vocabulary, and the helper is the one
# that decides -- not the catalogue.
helper_src = read(HELPER)
installable = set(re.findall(r'^INSTALLABLE = \((.*?)\)', helper_src, re.M | re.S))
allowed_pkgs = set(re.findall(r'"([a-z0-9-]+)"', "".join(installable)))
asked = {a.get("name") for i in items for a in i.get("actions", [])
         if a.get("action") == "package"}
ck("the store only installs packages its helper allows",
   asked <= allowed_pkgs, sorted(asked - allowed_pkgs))

themes = {a.get("theme") for i in items for a in i.get("actions", [])
          if a.get("action") == "login"}
ck("every login theme is a plain name",
   all(re.fullmatch(r"[a-z0-9-]{1,48}", t or "") for t in themes), sorted(themes))

# Sections a person can actually reach something in. `plugins` is empty on
# purpose -- it is announced as coming -- and `discover` is a view over the
# others, so those two are allowed to be empty and nothing else is.
empty = [s for s in sections
         if s not in ("plugins", "discover")
         and not any(i.get("section") == s for i in items)]
ck("no shelf is empty except the two that are meant to be", not empty, empty)


# Every file the PKGBUILD installs has to BE there. makepkg discovers this
# thirty minutes into a run, after everything before it has been built, and
# says only that a file was not found -- so it is answered here, in a second,
# against the same paths package() names.
missing = []
for match in re.findall(r'\$\{startdir\}/([A-Za-z0-9_./-]+)', read(os.path.join(PKG, "PKGBUILD"))):
    if "*" in match:
        continue
    if not os.path.exists(os.path.join(PKG, match)):
        missing.append(match)
ck("every file the PKGBUILD installs exists", not missing, missing)

components = os.path.join(PKG, "app", "components")
ck("the components directory has the card, the rail and the leaf",
   os.path.isdir(components)
   and {"ItemCard.qml", "RailButton.qml", "Leaf.qml"} <= set(os.listdir(components)))


# ── Half two: apply and revert, for real ───────────────────────────────────
#
# In-process, not through the shell. The store's job here is not "did it call
# caelestia" -- that is one line -- it is what it RECORDS so that revert can
# undo it, which is the part a person notices when it is wrong. So the CLI is
# imported, the one function that reaches outside (`run`) is replaced by a
# recorder with canned answers, and everything else is the shipped code: the
# real actions, the real state file, the real backups.
#
# It also means this runs anywhere, including where `caelestia` and a
# /bin/sh stub do not exist.
print()
print("== applying and reverting ==")

home = tempfile.mkdtemp(prefix="genesi-store-test-")
os.environ["HOME"] = home
os.environ["USERPROFILE"] = home
os.environ["XDG_DATA_HOME"] = os.path.join(home, ".local", "share")
os.environ["XDG_CONFIG_HOME"] = os.path.join(home, ".config")

import importlib.util
spec = importlib.util.spec_from_loader(
    "genesi_store", importlib.machinery.SourceFileLoader("genesi_store", CLI))
store = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(store)
except Exception as exc:  # pragma: no cover - a broken CLI fails the test
    print("  FAIL  the CLI does not import: %s" % exc)
    sys.exit(1)

calls = []
ANSWERS = {
    ("caelestia", "scheme", "get"): "gruvbox medium dark\n",
    ("genesi-bar", "current"): "10-padrao\n",
}


def fake_run(argv, check=True):
    calls.append(list(argv))
    for prefix, answer in ANSWERS.items():
        if tuple(argv[:len(prefix)]) == prefix:
            return 0, answer
    return 0, ""


store.run = fake_run
cat = store.load_catalog()


def fresh_state():
    return store.read_state()


def ran(*prefix):
    return any(tuple(c[:len(prefix)]) == prefix for c in calls)


# A theme: one action, and one that has to remember what it replaced.
state = fresh_state()
store.do_apply(cat, "theme-everforest-medium-dark", state)
ck("a theme is applied through caelestia",
   ran("caelestia", "scheme", "set", "-n", "everforest"), calls[-1:])
undo = state["applied"]["theme-everforest-medium-dark"]["undo"]
ck("...and the scheme that was there is remembered",
   undo and undo[0].get("name") == "gruvbox", undo)
calls.clear()
store.do_revert(cat, "theme-everforest-medium-dark", state)
ck("...and reverting sets that one back",
   ran("caelestia", "scheme", "set", "-n", "gruvbox")
   and "theme-everforest-medium-dark" not in state["applied"], calls)

# A config file where there was none: reverting must DELETE it, not leave an
# empty one behind.
target = os.path.join(os.environ["XDG_CONFIG_HOME"], "fastfetch", "config.jsonc")
state = fresh_state()
store.do_apply(cat, "fetch-compact", state)
ck("a fastfetch config is written", os.path.exists(target), target)
store.do_revert(cat, "fetch-compact", state)
ck("...and reverting leaves nothing, because nothing was there",
   not os.path.exists(target))

# ...and where there WAS one, the old bytes come back.
os.makedirs(os.path.dirname(target), exist_ok=True)
io.open(target, "w", encoding="utf-8", newline=chr(10)).write("{ /* meu */ }" + chr(10))
state = fresh_state()
store.do_apply(cat, "fetch-full", state)
changed = read(target)
store.do_revert(cat, "fetch-full", state)
ck("an existing config is restored exactly",
   read(target) == "{ /* meu */ }" + chr(10) and changed != "{ /* meu */ }" + chr(10),
   repr(read(target))[:80])

# The bar goes through the tool that owns it, both ways.
calls.clear()
state = fresh_state()
store.do_apply(cat, "bar-ilha", state)
ck("a bar preset is applied through genesi-bar",
   ran("genesi-bar", "apply", "30-ilha"), calls)
calls.clear()
store.do_revert(cat, "bar-ilha", state)
ck("...and reverting goes back to the one that was current",
   ran("genesi-bar", "apply", "10-padrao"), calls)

# A lock screen asks for its locker BEFORE writing a config that needs it.
calls.clear()
state = fresh_state()
store.shutil.which = lambda name: None          # nothing installed
pkexec = []
store.run = lambda argv, check=True: (pkexec.append(list(argv)) or (0, ""))
store.helper_path = lambda: "/usr/lib/genesi-store/genesi-store-helper"
store.do_apply(cat, "lock-night", state)
ck("a session lock installs the locker first, under pkexec",
   pkexec and pkexec[0][0] == "pkexec" and "hyprlock" in pkexec[0],
   pkexec[:1])
ck("...and then writes hyprlock's own config",
   os.path.exists(os.path.join(os.environ["XDG_CONFIG_HOME"], "hypr",
                               "hyprlock.conf")))
store.run = fake_run

# A url the catalogue is not allowed to name.
try:
    store.check_url("https://example.com/x.png")
    ck("a download from an unlisted host is refused", False, "it was allowed")
except SystemExit:
    ck("a download from an unlisted host is refused", True)
try:
    store.check_url("http://raw.githubusercontent.com/x.png")
    ck("plain http is refused", False, "it was allowed")
except SystemExit:
    ck("plain http is refused", True)

shutil.rmtree(home, ignore_errors=True)

print()
if fails:
    print("genesi store: %d failure(s)" % len(fails))
    sys.exit(1)
print("genesi store: OK")
