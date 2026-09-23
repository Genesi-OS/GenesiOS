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
import urllib.parse

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


def read_bytes(path):
    with io.open(path, "rb") as fh:
        return fh.read()


def load(path, name):
    """Import one of the store's scripts, extension or not, and run it here.

    Reading a guard and agreeing with it is not the same as watching it
    refuse, and the two files this imports -- the helper and the catalogue
    builder -- are the ones where being wrong costs somebody a login.
    """
    import importlib.util
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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



# ── Half three: the downloaded login screens ───────────────────────────────
#
# These are the riskiest thing in the store by a wide margin. A wallpaper that
# fails leaves a grey rectangle; a greeter that fails leaves a machine whose
# only way in is Ctrl+Alt+F2, and it fails at boot, after the person has
# already picked it and gone to bed. So the catalogue's claims are checked
# here, and the helper's guards are RUN.
print()
print("== the downloaded login screens ==")

greeters = data.get("greeters") or {}
asked_keys = {a.get("key") for i in items for a in i.get("actions", [])
              if a.get("action") == "greeter"}

ck("every card names a login screen the catalogue describes",
   asked_keys <= set(greeters), sorted(asked_keys - set(greeters)))
ck("every login screen described is used by a card",
   set(greeters) <= asked_keys, sorted(set(greeters) - asked_keys))

bad_greeters = []
for key, spec in greeters.items():
    # Two shapes. A repository holding ONE theme is an archive with one
    # checksum. A repository holding forty is described file by file, because
    # qylock is 604 MB of tarball for a 200 KB login screen. Both answer to
    # the same rules -- https, a host on the list, a digest on every byte
    # that will be written, and a content digest over the result.
    if spec.get("files"):
        base = spec.get("base", "")
        host = base.split("/")[2] if base.startswith("https://") else ""
        if not base.startswith("https://"):
            bad_greeters.append((key, "base not https"))
        elif host not in hosts:
            bad_greeters.append((key, "base host %s" % host))
        elif not re.search(r"/[0-9a-f]{40}/", base):
            bad_greeters.append((key, "base not pinned to a commit"))
        if spec.get("url"):
            bad_greeters.append((key, "has both an archive and a file list"))
        for entry in spec["files"]:
            path = entry.get("path", "")
            if not path or path.startswith("/") or ".." in path.split("/"):
                bad_greeters.append((key, "path %r" % path))
            if not re.fullmatch(r"[0-9a-f]{64}", entry.get("sha256", "")):
                bad_greeters.append((key, "%s has no checksum" % path))
            if not isinstance(entry.get("bytes"), int) or entry["bytes"] < 0:
                bad_greeters.append((key, "%s has no size" % path))
        # A theme is QML and pictures. If it lists no Main.qml the install
        # would fail at the last moment, as root, after a password prompt.
        if not any(e.get("path") == "Main.qml" for e in spec["files"]):
            bad_greeters.append((key, "no Main.qml in the file list"))
    else:
        url = spec.get("url", "")
        host = url.split("/")[2] if url.startswith("https://") else ""
        if not url.startswith("https://"):
            bad_greeters.append((key, "not https"))
        elif host not in hosts:
            bad_greeters.append((key, "host %s" % host))
        if not re.fullmatch(r"[0-9a-f]{64}", spec.get("sha256", "")):
            bad_greeters.append((key, "no archive checksum"))
    if not re.fullmatch(r"[0-9a-f]{64}", spec.get("tree", "")):
        bad_greeters.append((key, "no content digest"))
    if not isinstance(spec.get("bytes"), int) or spec["bytes"] <= 0:
        bad_greeters.append((key, "no size"))
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,47}",
                        spec.get("install_as", "")):
        bad_greeters.append((key, "install_as %r" % spec.get("install_as")))
    sub = spec.get("subpath", "")
    if sub.startswith("/") or ".." in sub.split("/"):
        bad_greeters.append((key, "subpath %r" % sub))
ck("every login screen is https, allow-listed, checksummed and digested",
   not bad_greeters, bad_greeters)

# A greeter is pinned to a COMMIT. A branch is whatever somebody pushed this
# morning, and this one runs as root before anybody has logged in.
# A file-based theme pins its `base` instead, checked with the rest of its
# shape above; this is the archive ones.
unpinned = [k for k, s in greeters.items()
            if not s.get("files")
            and not re.search(r"/tar\.gz/[0-9a-f]{40}$", s.get("url", ""))]
ck("every login screen is pinned to a commit", not unpinned, unpinned)

# Same list on both sides of pkexec. A package the CLI believes it may ask for
# and the helper does not is a card that takes a password and then fails.
cli_installable = set(re.findall(r'"([a-z0-9-]+)"', "".join(
    re.findall(r'^INSTALLABLE = \((.*?)\)', cli_src, re.M | re.S))))
ck("the store and its helper allow the same packages",
   cli_installable == allowed_pkgs,
   sorted(cli_installable ^ allowed_pkgs))

needed = {p for s in greeters.values() for p in (s.get("needs") or [])}
ck("every module a login screen needs is one the helper installs",
   needed <= allowed_pkgs, sorted(needed - allowed_pkgs))

conf_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}"
                     r"(/[A-Za-z0-9][A-Za-z0-9._-]{0,63})?$")
bad_confs = []
for item in items:
    for action in item.get("actions", []):
        if action.get("action") != "greeter":
            continue
        conf = action.get("conf")
        if conf is None:
            continue
        spec = greeters.get(action.get("key")) or {}
        if conf not in (spec.get("confs") or []):
            bad_confs.append((item["id"], conf, "not one of the theme's own"))
        elif not conf_re.match(conf):
            bad_confs.append((item["id"], conf, "the helper would refuse it"))
ck("every variant is one the theme itself ships", not bad_confs, bad_confs)

# Every call through pkexec has to carry the long timeout. The default is two
# minutes, which is right for asking caelestia a question and wrong for a call
# that waits on a person reading a password dialog and then on pacman fetching
# a Qt module. A timeout there does not stop the work -- it makes the store
# report a failure while the install carries on without it.
# Per FUNCTION, not per call: act_greeter builds its argv in a variable and
# passes `run(argv, ...)`, so a check that only looked for the literal
# `run(["pkexec"` would have missed the one call that can take longest.
hasty = []
for chunk in re.split(r"^def ", cli_src, flags=re.M)[1:]:
    name = chunk.split("(")[0]
    if '"pkexec"' not in chunk:
        continue
    if "PKEXEC_TIMEOUT" not in chunk:
        hasty.append(name)
ck("every call through pkexec waits as long as a password takes",
   not hasty, hasty)
ck("...and that wait is longer than the ordinary one",
   int(re.search(r"^PKEXEC_TIMEOUT = (\d+)", cli_src, re.M).group(1)) >= 900)


# A card that needs root has to SAY so, because the one thing a person should
# never meet unannounced is a password prompt.
quiet = [i["id"] for i in items
         if any(a.get("action") in ("greeter", "login")
                for a in i.get("actions", []))
         and not i.get("needs_root")]
ck("every login card says it needs root", not quiet, quiet)

# The host list, read from the CLI rather than copied, so this cannot pass
# while the store allows something else.
ALLOWED_HOSTS = tuple(
    re.findall(r'"([a-z0-9.\-]+)"',
               re.search(r"ALLOWED_HOSTS = \((.*?)\)", cli_src, re.S).group(1)))

# And it has to have a picture, because the whole point of a shelf of login
# screens is seeing them before you are looking at one. Not a SHIPPED picture:
# those screenshots belong to the people who made the themes, and some of what
# is inside them -- a cartoon frame, a still from a commercial game, wallpapers
# the upstream README itself says it cannot trace -- was never theirs to
# license onward. So the card names its picture and the store fetches it, and
# what is checked here is that every card names one.
greeter_items = [i for i in items
                 if any(a.get("action") == "greeter"
                        for a in i.get("actions", []))]
blind = [i["id"] for i in greeter_items
         if not (i.get("preview") or {}).get("shot")]
ck("every downloaded login screen has a preview", not blind, blind)

# A fetched picture is a download like any other download, so it answers to
# the same rules: https, a host on the list, pinned to a commit rather than a
# branch, and a digest to check the bytes against. A screenshot URL on a
# branch would be a picture that can change under the catalogue.
loose = []
for i in greeter_items:
    shot = i["preview"]["shot"]
    url = shot.get("url", "")
    host = url.split("/", 3)[2].lower() if url.startswith("https://") else ""
    if not url.startswith("https://"):
        loose.append(i["id"] + ": not https")
    elif host not in ALLOWED_HOSTS:
        loose.append(i["id"] + ": " + host)
    elif not re.search(r"/[0-9a-f]{40}/", url) and "user-attachments" not in url:
        loose.append(i["id"] + ": not pinned to a commit")
    elif len(shot.get("sha256", "")) != 64 or not shot.get("bytes"):
        loose.append(i["id"] + ": no digest")
ck("every login screen's picture is pinned and checksummed", not loose, loose)

# Nothing third-party is left in the package. greeter-genesi is ours -- it is
# rendered from our own greeter's QML by ci/sddm-shot.py.
thumbs = os.path.join(PKG, "catalog", "thumbs")
shipped = set(os.listdir(thumbs) if os.path.isdir(thumbs) else [])
strays = sorted(n for n in shipped
                if n.startswith("greeter-") and n != "greeter-genesi.jpg")
ck("no downloaded theme's screenshot is shipped in the package",
   not strays, strays)

absent = sorted({(i.get("preview") or {}).get("thumb") for i in items
                 if (i.get("preview") or {}).get("thumb")} - shipped)
ck("every preview the catalogue names is shipped", not absent, absent)


# A config that names a downloaded file writes {{asset:name}} and the store
# substitutes the real path. An item that asks for an asset it does not
# declare would write that placeholder into somebody's config verbatim --
# fastfetch would then look for a file called "{{asset:picture}}".
placeheld = []
for item in items:
    have = set((item.get("assets") or {}).keys())
    for action in item.get("actions", []):
        for want in re.findall(r"\{\{asset:([A-Za-z0-9_-]+)\}\}",
                               action.get("text") or ""):
            if want not in have:
                placeheld.append((item["id"], want))
ck("every {{asset}} an item writes is one it actually carries",
   not placeheld, placeheld)


# ── Somebody has to READ what the store writes ─────────────────────────────
#
# Twice now a shelf has shipped that applied perfectly and changed nothing:
# the lock screens wrote a config for a program nobody started, and the
# fastfetch cards wrote ~/.config/fastfetch/config.jsonc while both terminal
# greetings ran `fastfetch --config /usr/share/...`, which never looks there.
# Writing the file is the easy half. Being read is the half that shows.
fetch_targets = {a.get("path") for i in items for a in i.get("actions", [])
                 if a.get("action") == "file"
                 and "fastfetch" in (a.get("path") or "")}
ck("the fastfetch shelf writes one path", len(fetch_targets) == 1, fetch_targets)

greetings = [os.path.join(ROOT, "genesi-arch", "packages", "genesi-fastfetch", n)
             for n in ("genesi-fastfetch.fish", "genesi-greeting.sh")]
target_tail = "fastfetch/config.jsonc"
unread = [os.path.basename(g) for g in greetings
          if not os.path.exists(g) or target_tail not in read(g)]
ck("...and the terminal greeting actually reads it", not unread, unread)

# The packaged default has to stay reachable too, for the machine where
# nobody has ever opened the store.
no_fallback = [os.path.basename(g) for g in greetings
               if os.path.exists(g)
               and "/usr/share/genesi/fastfetch/genesi.jsonc" not in read(g)]
ck("...and still falls back to the one the package ships",
   not no_fallback, no_fallback)


# ── The PKGBUILD's own check() has to agree with this file ─────────────────
#
# package() carries a second copy of several of these rules, because makepkg
# has to be able to refuse a bad catalogue on a builder with none of this
# repository around it. Two copies of a rule is two things to update, and the
# day one of them learns something the other has not, everything here passes
# and the package build fails -- twenty minutes into CI, after every other
# package has been built.
#
# That has now happened: store-test learned that a theme can be described
# file by file, the PKGBUILD did not, and the build died on "qylock-minecraft
# is not pinned to a commit". So the embedded check is extracted and RUN here,
# against the real catalogue, in about a second.
embedded = re.findall(r"<<'CHECKCATALOG'\n(.*?)\nCHECKCATALOG",
                      read(os.path.join(PKG, "PKGBUILD")), re.S)
ck("the PKGBUILD carries its own catalogue check", len(embedded) == 1,
   len(embedded))
if embedded:
    proc = subprocess.run([sys.executable, "-", PKG], input=embedded[0],
                          text=True, capture_output=True, cwd=PKG)
    detail = ((proc.stderr or "") + (proc.stdout or "")).strip().splitlines()
    ck("...and it passes on this catalogue, the same as makepkg will run it",
       proc.returncode == 0, detail[-3:] if detail else "")


# ── A fastfetch config runs on every terminal you open ─────────────────────
#
# Which makes a broken one uniquely annoying: not one error, an error every
# single time, forever, until somebody works out where it came from. So every
# config this shelf can write is parsed here.
broken = []
for item in items:
    if item.get("section") != "fastfetch":
        continue
    for action in item.get("actions", []):
        text = action.get("text")
        if not text:
            continue
        try:
            conf = json.loads(text)
        except ValueError as exc:
            broken.append((item["id"], str(exc)[:50]))
            continue
        if not conf.get("modules"):
            broken.append((item["id"], "no modules"))
        for mod in conf.get("modules", []):
            # A module is either the name of one or an object saying which.
            if not isinstance(mod, str) and not (isinstance(mod, dict)
                                                 and mod.get("type")):
                broken.append((item["id"], "a module with no type"))
ck("every fastfetch config parses and has modules", not broken, broken)

# The factory card has to leave the machine reading the packaged config, and
# the packaged config has to be the one with the Genesi logo in it. That is
# the whole promise of the words "como vem de fábrica".
factory = [i for i in items if i["id"] == "default-fastfetch"]
ck("the fastfetch shelf has a way back", len(factory) == 1)
if factory:
    acts = factory[0].get("actions", [])
    ck("...and it clears the override rather than writing another one",
       all(a.get("action") == "restore" and not a.get("from") for a in acts),
       acts)

packaged = os.path.join(ROOT, "genesi-arch", "packages", "genesi-fastfetch",
                        "genesi.jsonc")
logo = os.path.join(ROOT, "genesi-arch", "packages", "genesi-fastfetch",
                    "genesi-logo.txt")
ck("...and what it falls back to draws the Genesi logo",
   os.path.exists(packaged) and os.path.exists(logo)
   and "genesi-logo.txt" in read(packaged))


# ── Two languages, and neither of them half-done ───────────────────────────
#
# The store leads with English because Genesi is installed from anywhere, and
# follows the machine's own language when it has one. The failure mode worth
# guarding is not "a wrong translation" -- it is a shelf that is half one
# language and half the other, which is where every half-internationalised
# app permanently lives.
untranslated = []
for item in items:
    for field in ("name", "blurb"):
        if not item.get(field):
            untranslated.append("%s: no %s" % (item["id"], field))
        elif field + "_pt" not in item:
            untranslated.append("%s: no %s_pt" % (item["id"], field))
    if item.get("tags") and "tags_pt" not in item:
        untranslated.append("%s: no tags_pt" % item["id"])
    if len(item.get("tags", [])) != len(item.get("tags_pt", [])):
        untranslated.append("%s: tags and tags_pt differ in length" % item["id"])
ck("every card carries both languages", not untranslated, untranslated[:6])

half_shelf = [s_["id"] for s_ in data.get("sections", [])
              if not s_.get("label") or not s_.get("label_pt")]
ck("every shelf carries both languages", not half_shelf, half_shelf)

# The app's own words live in Lang.t(english, portuguese). A qsTr() left
# behind is a string that will show in whatever language it was typed in,
# whatever the machine asked for.
app_dir = os.path.join(PKG, "app")
stragglers = []
for base, _dirs, names in os.walk(app_dir):
    for name in names:
        if not name.endswith(".qml"):
            continue
        path = os.path.join(base, name)
        for hit in re.findall(r'qsTr\(\s*"((?:[^"\\]|\\.)*)"', read(path)):
            stragglers.append("%s: %s" % (name, hit[:40]))
ck("no window text is left outside the two-language helper",
   not stragglers, stragglers[:6])

# ...and the helper has to exist and be registered, or every string in the
# window resolves to undefined.
ck("the window has its language helper",
   os.path.exists(os.path.join(app_dir, "Lang.qml"))
   and "singleton Lang" in read(os.path.join(app_dir, "qmldir")))


# ── The URL the store builds has to BE a URL ───────────────────────────────
#
# build-catalog escaped these paths when it recorded them and the store did
# not when it fetched them, and five themes shipped broken because of it --
# one of them carries "font/The Last Shuriken.ttf", and a space in a request
# line is not a URL at all. Python refuses it before the request is sent, so
# the theme died on its fourth file after the first three had downloaded.
#
# Checked by building exactly what the store builds and handing it to the
# same parser that rejected it.
import http.client as _http  # noqa: E402

unfetchable = []
for key, spec in greeters.items():
    base = spec.get("base")
    if not base:
        continue
    for entry in spec.get("files", []):
        url = base + "/" + urllib.parse.quote(entry["path"])
        try:
            _http.HTTPConnection("x")._validate_path(url.split("//", 1)[-1])
        except Exception as exc:
            unfetchable.append("%s: %s (%s)" % (key, entry["path"], exc))
ck("every per-file URL the store builds is a legal URL",
   not unfetchable, unfetchable[:4])

# ...and the two sides have to agree about the escaping, not merely both be
# legal: the digest was recorded against one spelling of the path.
build_src = read(os.path.join(PKG, "build-catalog.py"))
ck("...and the builder and the store escape it the same way",
   "urllib.parse.quote" in build_src and "urllib.parse.quote" in cli_src)


# ── A bar preset may only set keys the bar actually has ────────────────────
#
# The presets carried `width` and `spacing` for months. caelestia has neither
# -- there is no such key in BarConfig and the bar's thickness comes from the
# appearance tokens -- so two presets that differed only in those produced an
# identical bar, and the cards drawn from them drew a difference that could
# never appear on screen.
#
# This is the same failure as writing a config nobody reads, one level down:
# a key nobody reads.
BAR_KEYS = {
    "entries", "persistent", "showOnHover", "dragThreshold",
    "scrollActions", "popouts", "workspaces", "activeWindow", "tray",
    "status", "clock",
}
BORDER_KEYS = {"thickness", "rounding", "smoothing", "opacity"}

preset_dir = os.path.join(ROOT, "genesi-arch", "packages",
                          "genesi-caelestia-settings", "bar-presets")
invented = []
presets_seen = 0
if os.path.isdir(preset_dir):
    for name in sorted(os.listdir(preset_dir)):
        if not name.endswith(".json"):
            continue
        presets_seen += 1
        data = json.loads(read(os.path.join(preset_dir, name)))
        for key in (data.get("bar") or {}):
            if key not in BAR_KEYS:
                invented.append("%s: bar.%s" % (name, key))
        for key in (data.get("border") or {}):
            if key not in BORDER_KEYS:
                invented.append("%s: border.%s" % (name, key))
ck("every bar preset sets only keys caelestia has", not invented, invented)
ck("...and there were presets to check", presets_seen >= 10, presets_seen)

# The factory preset is the one that has to be complete: it is what "como vem
# de fábrica" applies, and if it leaves a key out, whatever the last preset
# set stays behind. That is what happened -- the auto-hiding bar stayed
# hidden, and the borders it had flattened did not come back.
factory_path = os.path.join(preset_dir, "10-padrao.json")
if os.path.exists(factory_path):
    factory = json.loads(read(factory_path))
    others = set()
    for name in sorted(os.listdir(preset_dir)):
        if not name.endswith(".json") or name == "10-padrao.json":
            continue
        data = json.loads(read(os.path.join(preset_dir, name)))
        others |= {"bar." + k for k in (data.get("bar") or {})}
        others |= {"border." + k for k in (data.get("border") or {})}
    have = {"bar." + k for k in (factory.get("bar") or {})}
    have |= {"border." + k for k in (factory.get("border") or {})}
    ck("the factory preset states everything the others can change",
       others <= have, sorted(others - have))


# ── One session locker, and it is caelestia's ─────────────────────────────
#
# This block used to REQUIRE the opposite: that every lock card install
# hypridle and wire it to the logind Lock signal, on the premise that nothing
# else answered `loginctl lock-session`. The premise was wrong. caelestia's
# IdleMonitors.qml has a LogindManager connected straight to the session's
# Lock and Unlock, so every lock request started caelestia's WlSessionLock AND
# hyprlock -- two clients on the Wayland ext-session-lock protocol, which one
# client may hold -- and the shell crashed on unlock. Every rice included a
# lock card, so applying any rice did it too.
#
# A guard that encodes a wrong belief protects the bug. This one encodes what
# is true: nothing the store can do may start a second locker.
LOCKER_PACKAGES = {"hypridle", "hyprlock", "swaylock"}
second = []
for item in items:
    for action in item.get("actions", []):
        kind = action.get("action")
        path = os.path.basename(action.get("path") or "")
        if kind == "locker":
            second.append((item["id"], "locker"))
        elif kind == "package" and action.get("name") in LOCKER_PACKAGES:
            second.append((item["id"], action.get("name")))
        elif kind in ("file", "restore") and path in ("hypridle.conf",
                                                      "hyprlock.conf"):
            second.append((item["id"], path))
ck("nothing in the catalogue starts a second session locker",
   not second, second)

cli_installable = set(re.findall(
    r'"([a-z0-9-]+)"',
    "".join(re.findall(r'^INSTALLABLE = \((.*?)\)', cli_src, re.M | re.S))))
ck("...and neither the store nor its helper will install one",
   not (LOCKER_PACKAGES & (allowed_pkgs | cli_installable)),
   sorted(LOCKER_PACKAGES & (allowed_pkgs | cli_installable)))
ck("...and the store has no action left that could wire one up",
   "locker" not in vocab, sorted(vocab))

back = [i for i in items if i["id"] == "default-lockscreens"]
ck("the lock shelf has a way back", len(back) == 1)
if back:
    ck("...and it retires the old watcher rather than adding anything",
       [a.get("action") for a in back[0]["actions"]] == ["unlocker"],
       back[0]["actions"])

# Machines that applied a lock card before this have hypridle in a user unit.
# The store removes it when it runs; this drop-in keeps it from starting on a
# machine where the store is never opened again.
dropin = os.path.join(PKG, "systemd", "genesi-lock.service.d", "10-retired.conf")
pkgbuild_src = read(os.path.join(PKG, "PKGBUILD"))
cond = re.search(r"^ConditionPathExists=(/\S+)", read(dropin), re.M) \
    if os.path.exists(dropin) else None
ck("the package retires the old watcher even where the store never runs",
   bool(cond) and "usr/lib/systemd/user/genesi-lock.service.d/10-retired.conf"
   in pkgbuild_src, dropin)
if cond:
    # The whole trick is a path that is never there. If anything ever
    # installed it, the retired unit would quietly start working again.
    ck("...and the path its condition names is one nothing installs",
       cond.group(1).lstrip("/") not in pkgbuild_src, cond.group(1))


# ── Everything the window loads is something the package installs ─────────
#
# The PKGBUILD listed the app's root QML files one by one, and Lang.qml was
# added and registered in qmldir without being added there. On the machine
# that is a qmldir naming a file that does not exist: the window does not
# open at all, and nothing in this repository would have said so, because
# every file the PKGBUILD names DID exist -- it was the other direction that
# was missing.
import fnmatch  # noqa: E402

literal = set(re.findall(r'\$\{startdir\}/(app/[A-Za-z0-9_./-]+)', pkgbuild_src))
globbed = re.findall(r'"\$\{startdir\}"/(app/[^\s;"]+)', pkgbuild_src)
app_root = os.path.join(PKG, "app")
not_shipped = []
for base, _dirs, names in os.walk(app_root):
    if "__pycache__" in base:
        continue
    for name in names:
        rel = os.path.relpath(os.path.join(base, name), PKG).replace(os.sep, "/")
        if not (name.endswith((".qml", ".py", ".svg")) or name == "qmldir"):
            continue
        if rel in literal or any(fnmatch.fnmatch(rel, g) for g in globbed):
            continue
        not_shipped.append(rel)
ck("every file the window loads is one the package installs",
   not not_shipped, not_shipped)

registered = re.findall(r"^\s*(?:singleton\s+)?\w+\s+[\d.]+\s+(\S+\.qml)",
                        read(os.path.join(app_root, "qmldir")), re.M)
ck("...including everything qmldir registers",
   all(os.path.exists(os.path.join(app_root, f)) for f in registered)
   and registered, registered)


# ── The window and its backend have to agree ───────────────────────────────
#
# QML does not fail when it calls something that is not there. A `store.foo()`
# that does not exist throws at the moment of the click, into a log nobody is
# reading; a `Connections { target: store; function onBar() }` whose signal
# does not exist is worse, because it warns once at load and then simply never
# fires -- which is a feature that silently does nothing, the exact shape of
# bug that has cost this project a day more than once.
#
# So: every name the QML reaches for on `store` has to exist on the Python
# object that gets handed to it.
app_dir = os.path.join(PKG, "app")
qml_files = []
for base, _dirs, names in os.walk(app_dir):
    qml_files += [os.path.join(base, n) for n in names if n.endswith(".qml")]

backend = read(os.path.join(app_dir, "genesi_store_app.py"))
slots = set(re.findall(r"@Slot\([^)]*\)\s*\n\s*def (\w+)", backend))
signals = set(re.findall(r"^\s{4}(\w+) = Signal\(", backend, re.M))

called, handled = set(), set()
for path in qml_files:
    text = read(path)
    called |= set(re.findall(r"\bstore\.(\w+)\s*\(", text))
    # Handlers only count when the Connections block they are in targets store.
    for chunk in text.split("Connections")[1:]:
        head = chunk[:400]
        if re.search(r"target:\s*store\b", head):
            body = chunk[:chunk.find("\n    }")] if "\n    }" in chunk else chunk
            for name in re.findall(r"function on([A-Z]\w*)\s*\(", body):
                handled.add(name[0].lower() + name[1:])

ck("the window calls only slots its backend has",
   called <= slots, sorted(called - slots))
ck("the window listens only for signals its backend emits",
   handled <= signals, sorted(handled - signals))
# And it is worth knowing the parsing found anything at all, because a guard
# that silently matches nothing passes forever.
ck("...and that check actually looked at something",
   len(called) >= 5 and len(handled) >= 1,
   "%d calls, %d handlers, %d qml files" % (len(called), len(handled),
                                            len(qml_files)))


# ── ...and the helper's guards, run ────────────────────────────────────────
#
# The helper is imported and its unpacker driven over tarballs built here.
# Reading the code and agreeing with it is not the same as watching it refuse.

helper = load(HELPER, "genesi_store_helper")


def tarball(entries, path):
    """entries: list of (name, bytes) or (name, tarfile.TarInfo-mutator)."""
    import tarfile as tf
    with tf.open(path, "w:gz") as tar:
        for name, payload in entries:
            if callable(payload):
                tar.addfile(payload(tf.TarInfo(name)))
                continue
            info = tf.TarInfo(name)
            info.size = len(payload)
            tar.addfile(info, io.BytesIO(payload))
    return path


def refuses(fn, *args):
    try:
        fn(*args)
    except SystemExit:
        return True
    return False


work = tempfile.mkdtemp(prefix="genesi-greeter-")
try:
    plain = tarball([("t/Main.qml", b"import QtQuick\nItem {}\n"),
                     ("t/metadata.desktop", b"[SddmGreeterTheme]\nQtVersion=6\n"),
                     ("t/assets/bg.png", b"\x89PNG not really"),
                     ("elsewhere/ignored", b"x")],
                    os.path.join(work, "plain.tar.gz"))

    out = os.path.join(work, "out")
    os.makedirs(out)
    helper.unpack(plain, "t", out)
    ck("the helper unpacks only the subtree it was told to",
       sorted(os.listdir(out)) == ["Main.qml", "assets", "metadata.desktop"],
       sorted(os.listdir(out)))

    # THE check that matters: the digest recorded at build time and the digest
    # computed by root after extraction have to be the same function. They are
    # written twice, in two files, in two languages of comment -- so they are
    # compared here over a real tree rather than trusted to stay in step.
    sys.path.insert(0, PKG)
    builder = load(os.path.join(PKG, "build-catalog.py"), "genesi_build_catalog")
    sys.path.pop(0)
    builder._ARCHIVES["fake"] = ("file://local", read_bytes(plain))
    builder.GREETER_REPOS["fake"] = ("x/t", "0" * 40)
    builder.archive_root = lambda key: "t"
    by_build, _ = builder.tree_digest_of("fake", "")
    by_helper = helper.tree_digest(out)
    ck("the build and the helper compute the same content digest",
       by_build == by_helper, (by_build[:16], by_helper[:16]))

    # ...and the same question for the OTHER shape. A theme from a collection
    # is described file by file, and the two digests are computed by two
    # different code paths: build-catalog hashes bytes it downloaded, the
    # helper hashes files it wrote. If those ever drift, every collection
    # theme fails to install with a message about the catalogue lying.
    per_file = [
        ("Main.qml", b"import QtQuick\nItem {}\n"),
        ("metadata.desktop", b"[SddmGreeterTheme]\nQtVersion=6\n"),
        ("assets/bg.png", b"\x89PNG not really"),
        ("font/Sans.ttf", b"\x00\x01ttf"),
    ]
    import hashlib
    listed = [{"path": name, "bytes": len(data),
               "sha256": hashlib.sha256(data).hexdigest()}
              for name, data in per_file]

    # What build-catalog would record, computed its way.
    build_side = hashlib.sha256()
    lookup = dict(per_file)
    for entry in sorted(listed, key=lambda f: f["path"]):
        build_side.update(entry["path"].encode("utf-8"))
        build_side.update(b"\0")
        build_side.update(lookup[entry["path"]])
        build_side.update(b"\0")

    # What the helper computes, after writing the same files itself.
    staged = os.path.join(work, "staged")
    for name, data in per_file:
        full = os.path.join(staged, name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(data)
    ck("...and they agree for a theme described file by file",
       build_side.hexdigest() == helper.tree_digest(staged))

    # place_files has to refuse a file whose bytes are not what was promised:
    # those files sit in the caller's home and the caller can swap them.
    swapped = os.path.join(work, "swapped")
    caller = os.path.join(work, "callerhome")
    for name, data in per_file:
        full = os.path.join(caller, ".local", "share", "genesi", "store",
                            "assets", "greeter-fake.d", name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(b"swapped" if name == "assets/bg.png" else data)
    os.makedirs(swapped, exist_ok=True)
    helper.caller_home = lambda: caller
    refused = False
    try:
        helper.place_files("fake", listed, swapped)
    except SystemExit:
        refused = True
    ck("the helper refuses a file that is not what the catalogue describes",
       refused)

    # ...and a path that climbs out is refused before anything is written.
    climbed = False
    try:
        helper.place_files("fake", [{"path": "../escape", "bytes": 1,
                                     "sha256": "0" * 64}], swapped)
    except SystemExit:
        climbed = True
    ck("the helper refuses a file list that climbs out of the theme", climbed)


    # A file changed after the catalogue was built must not match.
    with io.open(os.path.join(out, "Main.qml"), "a", encoding="utf-8") as fh:
        fh.write("// one more line\n")
    ck("one altered byte changes the digest",
       helper.tree_digest(out) != by_helper)

    # Paths that climb out, and entries that are not plain files. Both are how
    # an archive turns an unpacker running as root into something else.
    climbing = tarball([("t/../../etc/passwd", b"root:x:0:0")],
                       os.path.join(work, "climb.tar.gz"))
    ck("the helper refuses a path that climbs out of the archive",
       refuses(helper.unpack, climbing, "t", os.path.join(work, "c")))

    def as_symlink(info):
        info.type = __import__("tarfile").SYMTYPE
        info.linkname = "/etc/shadow"
        return info

    linked = tarball([("t/Main.qml", b"x"), ("t/evil", as_symlink)],
                     os.path.join(work, "link.tar.gz"))
    ck("the helper refuses a symlink",
       refuses(helper.unpack, linked, "t", os.path.join(work, "l")))

    # An archive that holds nothing under the subtree the catalogue named.
    ck("the helper refuses an archive missing the theme",
       refuses(helper.unpack, plain, "nothing-here", os.path.join(work, "n")))

    # The variant line, which is the one thing the helper edits inside a theme.
    helper.set_config_file(out, "metadata.desktop")
    meta = read(os.path.join(out, "metadata.desktop"))
    ck("the helper writes exactly one ConfigFile line",
       meta.count("ConfigFile=") == 1, meta.strip().splitlines())
    ck("the helper refuses a variant the theme does not have",
       refuses(helper.set_config_file, out, "no-such.conf"))
finally:
    shutil.rmtree(work, ignore_errors=True)


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


def fake_run(argv, check=True, timeout=None):
    calls.append(list(argv))
    for prefix, answer in ANSWERS.items():
        if tuple(argv[:len(prefix)]) == prefix:
            return 0, answer
    return 0, ""


store.run = fake_run
cat = store.CATALOG = store.load_catalog()


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

# The watcher an older store installed is removed -- and only what it wrote.
store.shutil.which = lambda name: None          # later tests rely on these
store.helper_path = lambda: "/usr/lib/genesi-store/genesi-store-helper"
store.run = fake_run
cfg = os.environ["XDG_CONFIG_HOME"]
unit = os.path.join(cfg, "systemd", "user", "genesi-lock.service")
idle = os.path.join(cfg, "hypr", "hypridle.conf")
for path in (unit, idle):
    os.makedirs(os.path.dirname(path), exist_ok=True)
io.open(unit, "w", encoding="utf-8").write(
    "[Unit]\nDescription=Genesi -- run the lock screen\n")
io.open(idle, "w", encoding="utf-8").write(
    "# Written by Genesi Store, so that locking the session locks the screen.\n"
    "general {\n    lock_cmd = pidof hyprlock || hyprlock\n}\n")
calls.clear()
did = store.retire_lock_watcher({"applied": {}})
ck("the store removes the lock watcher an older version installed",
   did and not os.path.exists(unit) and not os.path.exists(idle))
ck("...and stops it now, rather than leaving it running until logout",
   ran("systemctl", "--user", "disable", "--now", "genesi-lock.service"), calls)

io.open(idle, "w", encoding="utf-8").write(
    "general {\n    lock_cmd = swaylock\n}\n")
calls.clear()
store.retire_lock_watcher({"applied": {}})
ck("...but a hypridle.conf somebody wrote by hand is left exactly as it was",
   os.path.exists(idle) and "swaylock" in read(idle) and not calls, calls)
os.remove(idle)

backup = os.path.join(cfg, "hypridle.before-genesi-store")
io.open(backup, "w", encoding="utf-8").write("general { lock_cmd = mine }\n")
io.open(idle, "w", encoding="utf-8").write(
    "# Written by Genesi Store, so that locking the session locks the screen.\n")
store.retire_lock_watcher({"applied": {"lock-night": {"undo": [
    {"action": "unlocker", "conf_from": backup}]}}})
ck("...and a file it overwrote comes back",
   os.path.exists(idle) and "mine" in read(idle))
os.remove(idle)

calls.clear()
ck("...and it costs nothing when there is nothing to clean",
   store.retire_lock_watcher({"applied": {}}) is False and not calls, calls)

# A downloaded login screen: what it asks root for, and in what order.
# Nothing is fetched -- the archive is faked into place -- because what is
# being checked is the CONVERSATION with the helper, which is the part that
# decides whether a person can log in tomorrow.
state = fresh_state()
key = sorted(cat["greeters"])[0]
card = next(i["id"] for i in cat["items"]
            if any(a.get("action") == "greeter" and a.get("key") == key
                   for a in i.get("actions", [])))
conf = next(a.get("conf") for i in cat["items"] if i["id"] == card
            for a in i["actions"] if a.get("action") == "greeter")
archive = store.greeter_archive(key)
os.makedirs(os.path.dirname(archive), exist_ok=True)
io.open(archive, "wb").write(b"pretend this is the tarball")

calls[:] = []
undo = store.do_apply(cat, card, state)
expected = ["pkexec", store.helper_path(), "greeter", key] + ([conf] if conf else [])
ck("a downloaded login screen goes through the helper, by key",
   calls and calls[-1] == expected, calls[-1:])
ck("...and reverting puts the system's own screen back",
   undo == [{"action": "login", "theme": "breeze"}], undo)

# The key is a key. An item that tried to smuggle a path or a name that is not
# in the map has to be refused before anybody types a password.
try:
    store.act_greeter({"id": "x"}, {"key": "../../etc"}, {})
    ck("a login screen key that is not a key is refused", False, "it was allowed")
except SystemExit:
    ck("a login screen key that is not a key is refused", True)
try:
    store.act_greeter({"id": "x"}, {"key": key, "conf": "/etc/shadow"}, {})
    ck("a variant the theme does not have is refused", False, "it was allowed")
except SystemExit:
    ck("a variant the theme does not have is refused", True)


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
