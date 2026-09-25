#!/usr/bin/env python3
"""
Every command the Displays page sends, run through the real genesi-display.

`genesi-display mode` shipped unable to run at all: it counted its own name
among its arguments, so the usage check always failed, and past that it
called a `persist()` that was never written. The Displays page runs the tool
in the background and throws the output away, so picking a resolution simply
did nothing -- for as long as the page existed -- and nothing said so.

So this loads the tool against a fake Hyprland (two screens, side by side)
and runs each verb the page can send, the way the page sends it. A verb that
dies, or that exits cleanly without telling the compositor anything, fails.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import types
from contextlib import redirect_stderr, redirect_stdout

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "packages", "genesi-display", "genesi-display")
PAGE = os.path.join(ROOT, "packages", "genesi-center", "app", "pages",
                    "DisplaysPage.qml")

MONITORS = [
    {"name": "DP-1", "description": "Big one", "width": 2560, "height": 1440,
     "refreshRate": 143.97, "x": 0, "y": 0, "scale": 1.0, "transform": 0,
     "focused": True, "disabled": False,
     "availableModes": ["2560x1440@143.97Hz", "2560x1440@59.95Hz",
                        "1920x1080@60.00Hz", "1280x720@60.00Hz"]},
    {"name": "HDMI-A-1", "description": "Small one", "width": 1920,
     "height": 1080, "refreshRate": 60.0, "x": 2560, "y": 0, "scale": 1.0,
     "transform": 0, "focused": False, "disabled": False,
     "availableModes": ["1920x1080@60.00Hz", "1280x720@60.00Hz"]},
]

failures = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        failures.append(what)


def load(conf_dir):
    os.environ["XDG_CONFIG_HOME"] = conf_dir
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "test"
    loader = importlib.machinery.SourceFileLoader("genesi_display", TOOL)
    spec = importlib.util.spec_from_loader("genesi_display", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)

    sent = []

    def hypr(*args, check=True):
        if args[:2] == ("monitors", "-j"):
            return types.SimpleNamespace(returncode=0, stdout=json.dumps(MONITORS),
                                         stderr="")
        sent.append(args)
        return types.SimpleNamespace(returncode=0, stdout="ok", stderr="")

    mod.hypr = hypr
    mod.shutil = types.SimpleNamespace(which=lambda n: "/usr/bin/" + n)
    return mod, sent


def run(mod, argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    sys.argv = ["genesi-display"] + argv
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = mod.main() or 0
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
        except Exception as e:  # noqa: BLE001 -- a crash is a finding here
            code = 99
            err.write(f"{type(e).__name__}: {e}")
    return code, out.getvalue(), err.getvalue()


def fresh():
    d = tempfile.mkdtemp(prefix="genesi-display-test-")
    os.makedirs(os.path.join(d, "hypr"))
    with open(os.path.join(d, "hypr", "hyprland.conf"), "w") as fh:
        fh.write("monitor = , preferred, auto, 1\n")
    return (d,) + load(d)


def overrides(d):
    p = os.path.join(d, "hypr", "genesi-display.conf")
    return open(p).read() if os.path.exists(p) else ""


# The verbs the page actually sends, read from the page itself, so a new
# control that calls a verb this file has never heard of fails here.
page = open(PAGE, encoding="utf-8").read()
verbs = sorted(set(re.findall(r'page\.run\(\["(\w+)"', page)))
known = {"mode", "scale", "rotate", "place", "primary", "reset"}
print("verbs the Displays page sends: " + ", ".join(verbs))
check(set(verbs) <= known,
      "every verb the page sends is exercised below"
      + ("" if set(verbs) <= known else f" (untested: {set(verbs) - known})"))

print("resolution")
d, mod, sent = fresh()
listing = json.loads(run(mod, ["list"])[1])
picked = next(m for m in listing[0]["modes"] if m["width"] == 1920)["id"]
code, out, err = run(mod, ["mode", "DP-1", picked])
check(code == 0, f"`mode DP-1 {picked}` exits 0 (got {code}: {err.strip()[:120]})")
lines = [a[2] for a in sent if a[:2] == ("keyword", "monitor")]
check(any(l.startswith(f"DP-1,{picked},") for l in lines),
      "the new mode reaches the compositor")
check(any(l.startswith("HDMI-A-1,") and ",1920x0," in l for l in lines),
      "the screen to its right moves in by the width it lost")
check(f"monitor = DP-1,{picked}," in overrides(d),
      "the new mode is kept for the next session")

d, mod, sent = fresh()
code, _, _ = run(mod, ["mode", "DP-1", "1920x1080"])
check(code == 0 and any("DP-1,1920x1080@60.0," in a[2] for a in sent
                        if a[:2] == ("keyword", "monitor")),
      "a bare WxH means its highest refresh")

d, mod, sent = fresh()
code, _, err = run(mod, ["mode", "DP-1", "800x600@60.0"])
check(code != 0 and not sent, "a mode the panel does not offer is refused, untouched")

d, mod, _ = fresh()
code, out, _ = run(mod, ["modes", "HDMI-A-1"])
check(code == 0 and len(json.loads(out)) == 2, "`modes` lists one screen's modes")

print("the rest of the page")
for argv, what in ((["scale", "DP-1", "1.25"], "scale"),
                   (["rotate", "HDMI-A-1", "90"], "rotation"),
                   (["place", "HDMI-A-1", "0", "1440"], "dragging a screen"),
                   (["primary", "HDMI-A-1"], "main screen"),
                   (["reset"], "reset")):
    d, mod, sent = fresh()
    code, _, err = run(mod, argv)
    check(code == 0 and sent, f"{what}: `{' '.join(argv)}` runs and tells Hyprland"
          + ("" if code == 0 else f" (exit {code}: {err.strip()[:120]})"))

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\nall good")
