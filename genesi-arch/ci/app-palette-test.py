#!/usr/bin/env python3
"""
Every Genesi Qt app follows the desktop's scheme, or keeps Genesi's, coherently.

A Genesi app paints two kinds of pixel from two different places, and the bug
this guards was that only one of them was ever set:

  * what the app draws itself -- cards, separators, the sidebar -- comes from
    the shared UI kit's Theme.qml;
  * what Qt draws -- popups, scrollbars, menus, Fusion buttons -- comes from
    the application's QPalette, which no Genesi app ever set.

With no QPalette, Qt uses Fusion's default, which is LIGHT. The result is a
dark navy window with a handful of white controls in it: not an app half
following the scheme, an app following nothing while Qt filled in the gaps.

So this checks three things that are cheap and were all wrong:

  1. genesi_palette resolves to a COMPLETE set of colours in every case --
     scheme present or absent, following or not. A caller that has to handle
     "half the keys are missing" is a caller that gets it wrong somewhere.
  2. The QPalette it builds is dark and complete, including the Disabled group
     -- Qt draws greyed-out text from that, and the default is dark grey on a
     dark window, which is not disabled-looking, it is gone.
  3. Every app that bundles the module actually calls it, and every app that
     calls it actually bundles it. One without the other is a file that is
     installed and never imported, or an import that fails on every launch.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
PKGS = os.path.join(HERE, "..", "packages")
SRC = os.path.join(PKGS, "genesi-ui-kit", "components", "genesi_palette.py")

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (
        "" if cond else "\n         " + detail))
    if not cond:
        fails.append(name)


spec = importlib.util.spec_from_loader(
    "gp", importlib.machinery.SourceFileLoader("gp", SRC))
gp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gp)

# Every colour the kit's Theme.qml and GlassCard.qml ask for by name. If one of
# these is ever missing, the QML silently falls back to a pinned hex and the app
# is themed except for one surface -- which reads as a rendering bug.
NEEDED = ("surface", "surfaceContainerLow", "surfaceContainer",
          "surfaceContainerHigh", "surfaceContainerHighest", "outline",
          "onSurface", "onSurfaceVariant", "primary", "onPrimary", "secondary")

print("== the app palette bridge ==")

home = tempfile.mkdtemp()
gp.SCHEME = os.path.join(home, "scheme.json")
gp.CENTER_SETTINGS = os.path.join(home, "settings.json")

print()
print("-- no scheme, no switch: the Genesi look " + "-" * 24)
colours, following = gp.resolve()
check("it does not follow", following is False)
missing = [k for k in NEEDED if k not in colours]
check("and still returns every colour the kit asks for", not missing,
      "missing: " + ", ".join(missing))
check("which are Genesi's", colours["surface"] == "#040b17"
      and colours["primary"] == "#1FBE6A", repr(colours.get("surface")))

print()
print("-- a scheme and NO settings file: the fresh install " + "-" * 14)
io.open(gp.SCHEME, "w", encoding="utf-8").write(json.dumps({
    "mode": "dark",
    "colours": {"surface": "1e1e2e", "surfaceContainer": "313244",
                "onSurface": "cdd6f4", "primary": "89b4fa",
                "onPrimary": "11111b", "outline": "6c7086"},
}))
colours, following = gp.resolve()
# The default was the other way round, on the reasoning that an identity
# should not leave in an update. That reasoning was about the identity and not
# about the desktop: "every window follows the theme" cannot be true by default
# in an OS where the default is that six windows do not.
check("a fresh install FOLLOWS the desktop", following is True,
      "the emerald is one switch away; it is no longer the assumption")
check("and paints from the scheme", colours["surface"] == "#1e1e2e",
      repr(colours.get("surface")))

print()
print("-- a scheme, switch off " + "-" * 41)
io.open(gp.SCHEME, "w", encoding="utf-8").write(json.dumps({
    "mode": "dark",
    "colours": {"surface": "1e1e2e", "surfaceContainer": "313244",
                "onSurface": "cdd6f4", "primary": "89b4fa",
                "onPrimary": "11111b", "outline": "6c7086"},
}))
io.open(gp.CENTER_SETTINGS, "w", encoding="utf-8").write(
    json.dumps({"followSystemTheme": False}))
colours, following = gp.resolve()
check("turning the switch OFF keeps Genesi's palette", following is False,
      "the emerald has to stay reachable, it is just not the default")
check("so the colours are Genesi's", colours["surface"] == "#040b17")

print()
print("-- a scheme, switch on " + "-" * 42)
io.open(gp.CENTER_SETTINGS, "w", encoding="utf-8").write(
    json.dumps({"followSystemTheme": True}))
colours, following = gp.resolve()
check("it follows", following is True)
check("the scheme's colours won", colours["surface"] == "#1e1e2e"
      and colours["primary"] == "#89b4fa", repr(colours.get("surface")))
missing = [k for k in NEEDED if k not in colours]
check("and the keys the scheme did NOT carry fell back rather than vanishing",
      not missing, "missing: " + ", ".join(missing))
check("that fallback is Genesi's, not empty",
      colours["surfaceContainerHigh"] == "#16223a",
      repr(colours.get("surfaceContainerHigh")))

print()
print("-- the switch on with no scheme at all " + "-" * 26)
os.unlink(gp.SCHEME)
colours, following = gp.resolve()
check("following is off when there is nothing to follow", following is False,
      "a scheme file that is not there must not produce a half-empty palette")

print()
print("-- the QPalette Qt draws its own widgets from " + "-" * 19)
try:
    from PySide6.QtGui import QPalette  # noqa: F401
    have_qt = True
except ImportError:
    have_qt = False

if not have_qt:
    print("  skip  PySide6 is not installed here")
else:
    from PySide6.QtGui import QGuiApplication, QPalette
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    _app = QGuiApplication.instance() or QGuiApplication([])
    pal = gp.qpalette(dict(gp.GENESI))

    def lum(col):
        return 0.299 * col.redF() + 0.587 * col.greenF() + 0.114 * col.blueF()

    window = pal.color(QPalette.ColorGroup.Active, QPalette.ColorRole.Window)
    text = pal.color(QPalette.ColorGroup.Active, QPalette.ColorRole.WindowText)
    button = pal.color(QPalette.ColorGroup.Active, QPalette.ColorRole.Button)
    check("the window colour is dark", lum(window) < 0.3, window.name())
    check("the text on it is light", lum(text) > 0.6, text.name())
    # This is the actual reported symptom: a dark window with light buttons.
    check("and a BUTTON is dark too, not Fusion's default light one",
          lum(button) < 0.35, button.name())

    dis = pal.color(QPalette.ColorGroup.Disabled,
                    QPalette.ColorRole.WindowText)
    check("disabled text is set, and readable against the window",
          abs(lum(dis) - lum(window)) > 0.15,
          f"disabled {dis.name()} vs window {window.name()} -- Qt's default "
          "here is dark grey on a dark window, which is not disabled-looking, "
          "it is invisible")

print()
print("-- every app both bundles it and calls it " + "-" * 23)
APPS = {
    "genesi-ai-mode": "monitor/genesi_ai_monitor.py",
    "genesi-netinspect": "app/genesi_netinspect.py",
    "genesi-ports": "app/genesi_ports.py",
    "genesi-sandboxes": "app/genesi_sandboxes.py",
    "genesi-snapshots": "app/genesi_snapshots.py",
}
for pkg, rel in sorted(APPS.items()):
    main = io.open(os.path.join(PKGS, pkg, rel), encoding="utf-8").read()
    build = io.open(os.path.join(PKGS, pkg, "PKGBUILD"), encoding="utf-8").read()
    calls = "from genesi_palette import install" in main
    bundles = "genesi_palette.py" in build
    check(f"{pkg} calls it", calls,
          "the module would be installed and never imported")
    check(f"{pkg} bundles it", bundles,
          "the import would fail on every launch, and the app would silently "
          "keep the palette it had")
    if bundles:
        # It has to land in the SAME directory as the module that imports it:
        # the app puts its own directory on sys.path and nothing else.
        want = os.path.dirname(rel).split("/")[-1]
        m = re.search(r'genesi_palette\.py"\s*\\\s*\n\s*"\$pkgdir/([^"]+)"',
                      build)
        got = os.path.dirname(m.group(1)).split("/")[-1] if m else "?"
        check(f"{pkg} installs it beside the app's own module", got == want,
              f"installed into .../{got}, imported from .../{want}")

print()
if fails:
    print(f"{len(fails)} check(s) failed:")
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("app palette: OK")
