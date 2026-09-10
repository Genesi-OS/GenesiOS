#!/usr/bin/env python3
"""
theme-sync-test.py — prove genesi-caelestia-theme-sync themes what it claims to.

Three toolkits read three different files and none of them agree on a format:
qt6ct wants a palette of 21 ARGB roles per group, KDE wants seven colour groups
of twelve decimal triples each, and both live next to settings that are not
ours. The failure modes are all silent — a missing key falls back to Breeze, a
dropped section takes somebody's icon theme with it, and either way the app just
looks slightly wrong rather than broken.

So this drives the real script against a temporary HOME and checks what came
out, with the emphasis on what must SURVIVE rather than on what was written.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "packages", "genesi-caelestia-settings",
                   "genesi-caelestia-theme-sync")

fails = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def ini(path):
    """Parse an INI into {section: {key: value}} without configparser, which
    lowercases keys -- and KDE's keys are camelCase."""
    out, cur = {}, None
    for line in io.open(path, encoding="utf-8"):
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            out.setdefault(cur, {})
        elif cur and "=" in line:
            k, _, v = line.partition("=")
            out[cur][k.strip()] = v.strip()
    return out


home = tempfile.mkdtemp()
os.environ["XDG_CONFIG_HOME"] = os.path.join(home, "config")
os.environ["XDG_STATE_HOME"] = os.path.join(home, "state")
os.environ["XDG_DATA_HOME"] = os.path.join(home, "data")

spec = importlib.util.spec_from_loader(
    "sync", importlib.machinery.SourceFileLoader("sync", SRC))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

# caelestia's active scheme, in the shape it really writes.
os.makedirs(os.path.dirname(str(sync.SCHEME)), exist_ok=True)
io.open(str(sync.SCHEME), "w", encoding="utf-8").write(json.dumps({
    "name": "dracula",
    "flavour": "medium",
    "mode": "dark",
    "colours": {
        "surface": "343746",
        "surfaceContainer": "3e4153",
        "surfaceContainerHigh": "4d4f66",
        "surfaceContainerHighest": "565970",
        "surfaceContainerLow": "3c3f4e",
        "surfaceContainerLowest": "191a21",
        "surfaceBright": "4d4f66",
        "onSurface": "f8f8f2",
        "onSurfaceVariant": "c8c8c2",
        "primary": "bd93f9",
        "onPrimary": "282a36",
        "secondary": "50fa7b",
        "tertiary": "ff79c6",
        "error": "ff5555",
        "outline": "6272a4",
        "shadow": "000000",
    },
}))

# Something already in kdeglobals that is NOT ours, and must survive.
kde = str(sync.KDEGLOBALS)
os.makedirs(os.path.dirname(kde), exist_ok=True)
io.open(kde, "w", encoding="utf-8").write(
    "[Icons]\nTheme=Papirus-Dark\n\n"
    "[KDE]\nSingleClick=false\n\n"
    "[Colors:Window]\nBackgroundNormal=1,2,3\nSomethingElse=keep-me\n")

print("== theme sync ==")
check(sync.apply() is True, "apply() reports success with a scheme present")

g = ini(kde)

# ── What must survive ────────────────────────────────────────────────────────
check(g.get("Icons", {}).get("Theme") == "Papirus-Dark",
      "the icon theme survived (this file is not ours to rewrite)")
check(g.get("KDE", {}).get("SingleClick") == "false",
      "an unrelated section survived")
check(g.get("Colors:Window", {}).get("SomethingElse") == "keep-me",
      "an unrelated KEY inside a section we own survived")

# ── What must be written ─────────────────────────────────────────────────────
check(g.get("Colors:Window", {}).get("BackgroundNormal") == "52,55,70",
      "the window background is the scheme's surface, as a decimal triple")
check(g.get("Colors:View", {}).get("BackgroundNormal") == "25,26,33",
      "views use the lowest container, not the window colour")
check(g.get("Colors:Selection", {}).get("BackgroundNormal") == "189,147,249",
      "selection is the scheme's primary")
check(g.get("General", {}).get("ColorScheme") == sync.SCHEME_NAME,
      "the scheme has a name")

# ── And that something answers to that name ──────────────────────────────────
#
# kdeglobals naming a scheme is only half of it. A KDE or Kirigami app resolves
# that name to a .colors file at startup, and a name nothing answers to does
# not leave the palette alone -- it falls back to Breeze, which is light. That
# was the bug: Dolphin opened white, setting its colours to Default fixed it
# for that run (Default reads the groups), and restarting undid it (startup
# resolves the name).
want = sync.SCHEME_NAME
check(" " not in want,
      "the scheme name is a single token (KDE matches this file by its Name "
      "in some code paths and by its base name in others)")
scheme_file = str(sync.COLOR_SCHEME)
check(os.path.exists(scheme_file),
      "the .colors file the name points at was written")
sc = ini(scheme_file)
check(sc.get("General", {}).get("Name") == want,
      "its Name is the name kdeglobals asks for")
check(os.path.basename(scheme_file) == want + ".colors",
      "and so is its file name")
check(sc.get("Colors:Window", {}).get("BackgroundNormal") == "52,55,70",
      "it carries the same window colour as kdeglobals (two files describing "
      "one scheme that disagree is worse than one file)")
check(sc.get("Colors:Selection", {}).get("BackgroundNormal") == "189,147,249",
      "and the same selection colour")
for eff in ("ColorEffects:Disabled", "ColorEffects:Inactive"):
    check(eff in sc,
          f"[{eff}] is present (KDE derives greyed-out text from these rather "
          "than from colours)")

WANT = ("Colors:Window", "Colors:View", "Colors:Button", "Colors:Selection",
        "Colors:Tooltip", "Colors:Complementary", "Colors:Header", "WM")
missing = [s for s in WANT if s not in g]
check(not missing, "every group KF6 reads is present (missing: %r)" % missing)

KEYS = ("BackgroundNormal", "BackgroundAlternate", "ForegroundNormal",
        "ForegroundInactive", "ForegroundActive", "ForegroundLink",
        "ForegroundVisited", "ForegroundNegative", "ForegroundNeutral",
        "ForegroundPositive", "DecorationFocus", "DecorationHover")
short = [s for s in WANT if s != "WM"
         for k in KEYS if k not in g.get(s, {})]
check(not short,
      "no group is missing a key (a missing key falls back to Breeze, "
      "which is one stray blue link on every page)")

# ── Idempotence ──────────────────────────────────────────────────────────────
before = io.open(kde, encoding="utf-8").read()
sync.apply()
check(io.open(kde, encoding="utf-8").read() == before,
      "running twice changes nothing (no duplicated keys)")

# ── qt6ct is still written ───────────────────────────────────────────────────
q = ini(str(sync.QT6CT_CONF))
check(q.get("Appearance", {}).get("custom_palette") == "true",
      "qt6ct still gets its palette")
check(os.path.exists(str(sync.COLORS)), "and its colour file exists")

# ── qt5ct: colours always, conf only when it is already there ────────────────
check(os.path.exists(str(sync.QT5CT_COLORS)), "qt5ct colours are written")
check(not os.path.exists(str(sync.QT5CT_DIR / "qt5ct.conf")),
      "but no qt5ct.conf is invented for a machine that has none")

conf5 = sync.QT5CT_DIR / "qt5ct.conf"
io.open(str(conf5), "w", encoding="utf-8").write("[Appearance]\nstyle=Fusion\n")
sync.apply()
q5 = ini(str(conf5))
check(q5.get("Appearance", {}).get("custom_palette") == "true",
      "an existing qt5ct.conf is picked up")
check(q5.get("Appearance", {}).get("style") == "Fusion",
      "and its own settings are kept")

print()
if fails:
    print("FAILED: %d" % len(fails))
    sys.exit(1)
print("theme sync: OK")
