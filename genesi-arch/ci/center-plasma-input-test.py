#!/usr/bin/env python3
"""
The Hub's Input page on KDE Plasma: what it writes, and what it reads back.

The page sends Hyprland's option names (`input:sensitivity` ...). On Plasma
genesi-center-set routes them to where KWin keeps them -- kcminputrc, kwinrc,
kxkbrc, and per-device properties on KWin's D-Bus (org.kde.KWin.InputDevice,
the interface Plasma's own Mouse/Touchpad settings use). genesi-center-data
reads the same places back in the same keys the Hyprland path reports.

Both scripts run for real against a fake KWin with a keyboard, a mouse and a
touchpad. And a Hyprland session must never take any of this path.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..", "packages", "genesi-center")

DEVICES = {"event0": {"name": "AT Keyboard", "alphaNumericKeyboard": True,
                      "pointer": False, "touchpad": False},
           "event1": {"name": "USB Mouse", "pointer": True, "touchpad": False,
                      "pointerAcceleration": 0.2, "pointerAccelerationProfileFlat": True,
                      "naturalScroll": False},
           "event2": {"name": "ELAN Touchpad", "pointer": True, "touchpad": True,
                      "tapToClick": True, "naturalScroll": True,
                      "disableWhileTyping": True, "scrollFactor": 0.5}}
KCONF = {("kcminputrc", "Keyboard", "RepeatRate"): "30",
         ("kcminputrc", "Keyboard", "RepeatDelay"): "400",
         ("kwinrc", "Windows", "FocusPolicy"): "FocusFollowsMouse",
         ("kxkbrc", "Layout", "LayoutList"): "br,us"}

fails = []


def check(ok, what):
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        fails.append(what)


def load(name, path):
    spec = importlib.util.spec_from_loader(
        name, importlib.machinery.SourceFileLoader(name, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def busctl_answer(args):
    """args after `busctl --user --json=short`."""
    verb, _, path, iface, prop = args[:5]
    if verb == "get-property":
        if path.endswith("/InputDevice") and prop == "devicesSysNames":
            return {"type": "as", "data": list(DEVICES)}
        dev = DEVICES.get(path.rsplit("/", 1)[-1], {})
        if prop in dev:
            return {"type": "x", "data": dev[prop]}
        return None
    return {}


calls = []


class P:
    def __init__(self, out="", code=0):
        self.stdout, self.stderr, self.returncode = out, "", code


def fake_run(argv, **kw):
    calls.append(list(argv))
    if argv[:3] == ["busctl", "--user", "--json=short"]:
        ans = busctl_answer(argv[3:])
        if ans is None:
            return P("", 1)
        return P(json.dumps(ans) if ans else "")
    if argv[0] == "kreadconfig6":
        f, g, k = argv[2], argv[4], argv[6]
        return P(KCONF.get((f, g, k), "") + "\n")
    return P()


os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
os.environ["XDG_CURRENT_DESKTOP"] = "KDE"

# ── the writer ──────────────────────────────────────────────────────────────
cs = load("genesi_center_set", os.path.join(PKG, "genesi-center-set"))
cs.subprocess.run = fake_run
hypr_writes = []
cs.hypr_write = lambda o, v: hypr_writes.append((o, v))


def setopt(option, value):
    calls.clear()
    out = io.StringIO()
    code = 0
    with redirect_stdout(out):
        try:
            cs.cmd_hypr(option, value)
        except SystemExit as e:
            code = e.code or 1
    return code


def sent_set(path_end, prop, val):
    return any(c[:4] == ["busctl", "--user", "--json=short", "set-property"]
               and c[5].endswith(path_end) and c[7] == prop and c[-1] == val
               for c in calls)


def wrote(file, group, key, val):
    return any(c[:1] == ["kwriteconfig6"] and "--notify" in c and file in c
               and group in c and key in c and c[-1] == val for c in calls)


check(setopt("input:sensitivity", "0.5") == 0
      and sent_set("event1", "pointerAcceleration", "0.5")
      and not sent_set("event2", "pointerAcceleration", "0.5"),
      "sensitivity -> the mouse's pointerAcceleration, not the touchpad's")
check(setopt("input:accel_profile", "flat") == 0
      and sent_set("event1", "pointerAccelerationProfileFlat", "true")
      and sent_set("event1", "pointerAccelerationProfileAdaptive", "false"),
      "accel profile flat -> Flat on, Adaptive off")
check(setopt("input:natural_scroll", "1") == 0 and sent_set("event1", "naturalScroll", "true"),
      "mouse natural scroll")
check(setopt("input:touchpad:tap-to-click", "0") == 0
      and sent_set("event2", "tapToClick", "false"),
      "touchpad tap-to-click")
check(setopt("input:touchpad:disable_while_typing", "1") == 0
      and sent_set("event2", "disableWhileTyping", "true"),
      "touchpad disable while typing")
check(setopt("input:touchpad:scroll_factor", "1.5") == 0
      and sent_set("event2", "scrollFactor", "1.5"),
      "touchpad scroll factor")
check(setopt("input:repeat_rate", "40") == 0 and wrote("kcminputrc", "Keyboard", "RepeatRate", "40"),
      "repeat rate -> kcminputrc, with --notify so KWin picks it up")
check(setopt("input:repeat_delay", "300") == 0 and wrote("kcminputrc", "Keyboard", "RepeatDelay", "300"),
      "repeat delay -> kcminputrc")
check(setopt("input:follow_mouse", "0") == 0
      and wrote("kwinrc", "Windows", "FocusPolicy", "ClickToFocus")
      and any("org.kde.KWin.reconfigure" in c for c in calls),
      "focus follows mouse off -> ClickToFocus, and KWin reconfigures")
check(setopt("input:kb_layout", "br") == 0 and wrote("kxkbrc", "Layout", "LayoutList", "br"),
      "keyboard layout -> kxkbrc")
check(setopt("input:sensitivity", "7") == 0 and sent_set("event1", "pointerAcceleration", "1.0"),
      "an out-of-range value is clamped to Hyprland's own limit before it is sent")
check(setopt("input:sensitivity", "fast") != 0
      and not any(c[0] == "busctl" and "set-property" in c for c in calls),
      "a value that is not a number is refused, nothing sent")
check(not hypr_writes, "Plasma never writes the Hyprland drop-in")

os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "x"
os.environ["XDG_CURRENT_DESKTOP"] = "Hyprland"
calls.clear()
check(setopt("input:sensitivity", "0.5") == 0 and hypr_writes
      and not any(c[0] in ("busctl", "kwriteconfig6") for c in calls),
      "Hyprland still writes its own drop-in and never touches KWin")
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
os.environ["XDG_CURRENT_DESKTOP"] = "KDE"

# ── the reader ──────────────────────────────────────────────────────────────
cd = load("genesi_center_data", os.path.join(PKG, "genesi-center-data"))
cd.subprocess.run = fake_run
d = cd.input_devices()
o = d.get("options", {})
check(d.get("available") and d.get("desktop") == "plasma", "Plasma input is available")
check(o.get("sensitivity") == 0.2 and o.get("accel_profile") == "flat"
      and o.get("natural_scroll") == 0, "mouse values read from KWin")
check(o.get("tp_tap") == 1 and o.get("tp_dwt") == 1 and o.get("tp_scroll_factor") == 0.5
      and d.get("has_touchpad"), "touchpad values read from KWin")
check(o.get("repeat_rate") == 30 and o.get("repeat_delay") == 400
      and o.get("follow_mouse") == 1 and o.get("kb_layout") == "br",
      "keyboard and focus read from kcminputrc / kwinrc / kxkbrc")
hypr_keys = {"kb_layout", "repeat_rate", "repeat_delay", "sensitivity", "accel_profile",
             "natural_scroll", "follow_mouse", "tp_natural_scroll", "tp_tap", "tp_dwt",
             "tp_scroll_factor"}
check(set(o) <= hypr_keys, "only keys the Hyprland path also reports: %s" % sorted(set(o) - hypr_keys))
caps = cd.session()
check(caps.get("input") and caps.get("displays") and not caps.get("hyprland"),
      "the Hub is told Input and Displays work here")

if fails:
    print("\n%d failure(s)" % len(fails))
    sys.exit(1)
print("\nHub input on Plasma: OK")
