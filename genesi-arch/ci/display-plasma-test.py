#!/usr/bin/env python3
"""
genesi-display on KDE Plasma: every verb the Displays page sends.

On Plasma the tool goes through kscreen-doctor, the same backend Plasma's own
Display settings use. This loads the real tool against a fake kscreen-doctor
(a laptop panel plus an external screen, side by side) and checks two things:

  * `list` prints the SAME record the Hyprland path prints -- same keys -- so
    the Displays page, written for Hyprland, reads Plasma without a change;
  * each verb reaches kscreen-doctor with the right words, and none of them
    exits cleanly while telling it nothing.

And that a Hyprland session never takes this path.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "packages", "genesi-display", "genesi-display")

FAKE = {"outputs": [
    {"id": 1, "name": "eDP-1", "connected": True, "enabled": True, "priority": 1,
     "pos": {"x": 0, "y": 0}, "scale": 1.25, "rotation": 1, "currentModeId": "2",
     "vendor": "BOE", "model": "0x0A1B",
     "modes": [{"id": "1", "size": {"width": 2560, "height": 1600}, "refreshRate": 165.0},
               {"id": "2", "size": {"width": 1920, "height": 1200}, "refreshRate": 60.0}]},
    {"id": 2, "name": "HDMI-A-1", "connected": True, "enabled": True, "priority": 2,
     "pos": {"x": 1536, "y": 0}, "scale": 1.0, "rotation": 2, "currentModeId": "5",
     "modes": [{"id": "5", "size": {"width": 1920, "height": 1080}, "refreshRate": 60.0},
               {"id": "6", "size": {"width": 1280, "height": 720}, "refreshRate": 60.0}]},
    {"id": 3, "name": "DP-2", "connected": False, "enabled": False, "modes": []},
]}

failures = []


def check(ok, what):
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)


def load():
    spec = importlib.util.spec_from_loader(
        "genesi_display", importlib.machinery.SourceFileLoader("genesi_display", TOOL))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sent = []

    class P:
        def __init__(self, out=""):
            self.stdout, self.stderr, self.returncode = out, "", 0

    def kscreen(*args, check=True):
        if args == ("-j",):
            return P(json.dumps(FAKE))
        sent.append(list(args))
        return P()

    def hypr(*args, check=True):
        sent.append(["HYPRCTL"] + list(args))
        return P("[]")

    mod.kscreen, mod.hypr = kscreen, hypr
    return mod, sent


def run(mod, argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            mod.main_argv = argv
            sys.argv = ["genesi-display"] + argv
            code = mod.main() or 0
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
    return code, out.getvalue(), err.getvalue()


os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
os.environ["XDG_CURRENT_DESKTOP"] = "KDE"

mod, sent = load()
check(mod.on_plasma(), "a KDE session is detected as Plasma")
check(not mod.on_plasma({"XDG_CURRENT_DESKTOP": "Hyprland",
                         "HYPRLAND_INSTANCE_SIGNATURE": "x"}),
      "a Hyprland session never takes the Plasma path")
check(not mod.on_plasma({"XDG_CURRENT_DESKTOP": "KDE",
                         "HYPRLAND_INSTANCE_SIGNATURE": "x"}),
      "...not even with a stray KDE in XDG_CURRENT_DESKTOP")

code, out, err = run(mod, ["list"])
mons = json.loads(out) if code == 0 else []
check(code == 0 and [m["name"] for m in mons] == ["eDP-1", "HDMI-A-1"],
      "list: connected screens only (%s)" % (err.strip()[:80] or "ok"))
# The record the Hyprland path prints, from its own monitors().
hypr_keys = {"name", "description", "width", "height", "refresh", "x", "y", "scale",
             "transform", "rotation", "focused", "disabled", "primary", "modes", "mode"}
check(mons and all(set(m) == hypr_keys for m in mons),
      "list: the same keys as on Hyprland, so the page reads it unchanged")
edp = mons[0] if mons else {}
check(edp.get("mode") == "1920x1200@60.0" and edp.get("primary") and edp.get("scale") == 1.25,
      "list: current mode, main screen and scale come from kscreen-doctor")
check(mons and mons[1]["rotation"] == 90 and mons[1]["transform"] == 1,
      "list: KScreen 'left' is 90 degrees, Hyprland's transform 1")
check(edp.get("modes") and edp["modes"][0]["id"] == "2560x1600@165.0"
      and "kscreen" not in edp["modes"][0],
      "list: modes in the same WxH@Hz form the page sends back")

for argv, want, what in (
        (["scale", "eDP-1", "1.5"], ["output.eDP-1.scale.1.5"], "scale"),
        (["scale", "-", "up"], ["output.eDP-1.scale.1.5"], "scale up on the screen in use"),
        (["rotate", "HDMI-A-1", "180"], ["output.HDMI-A-1.rotation.inverted"], "rotation"),
        (["rotate", "eDP-1", "cycle"], ["output.eDP-1.rotation.left"], "rotation cycle"),
        (["mode", "eDP-1", "2560x1600@165.0"], ["output.eDP-1.mode.1"], "resolution, as listed"),
        (["mode", "HDMI-A-1", "1280x720"], ["output.HDMI-A-1.mode.6"], "resolution, WxH only"),
        (["place", "HDMI-A-1", "0", "1200"], ["output.HDMI-A-1.position.0,1200"], "dragging a screen"),
        (["position", "HDMI-A-1", "right-of", "eDP-1"],
         ["output.HDMI-A-1.position.1536,0"], "right of the scaled panel"),
        (["primary", "HDMI-A-1"], ["output.HDMI-A-1.priority.1"], "main screen"),
        (["reset", "eDP-1"], ["output.eDP-1.scale.1", "output.eDP-1.rotation.normal"], "reset")):
    sent.clear()
    code, _, err = run(mod, argv)
    check(code == 0 and sent == [want],
          f"{what}: `{' '.join(argv)}` -> kscreen-doctor {' '.join(want)}"
          + ("" if code == 0 else f" (exit {code}: {err.strip()[:100]})")
          + ("" if sent == [want] or code else f" (sent {sent})"))

sent.clear()
code, _, _ = run(mod, ["mode", "eDP-1", "800x600"])
check(code != 0 and not sent, "a mode the screen does not offer is refused, nothing sent")
code, _, _ = run(mod, ["scale", "nope", "1"])
check(code != 0 and not sent, "an unknown screen is refused, nothing sent")
check(not any(c and c[0] == "HYPRCTL" for c in sent), "Plasma never calls hyprctl")

if failures:
    print(f"\n{len(failures)} failure(s)")
    sys.exit(1)
print("\ngenesi-display on Plasma: all good")
