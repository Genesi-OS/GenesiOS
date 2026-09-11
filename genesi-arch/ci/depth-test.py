#!/usr/bin/env python3
"""genesi-depth: does it parse, do the three lists agree, and does it cut?

Depth's settings are spelled out in three places -- the tiers in genesi-depth,
the enums genesi-center-set accepts, and the switch statements in
GenesiDepth.qml that turn a name into an opacity or a blur. Every one of them
is a list of the same words, and a word that appears in two of the three is a
setting that saves, applies to nothing, and produces no error anywhere. That
is this repository's oldest failure and it has a guard now.

The cut itself is checked when OpenCV is importable, which it is in the build
container and may not be on a laptop. Two pictures: one with an obvious
subject, which must come back with a cut-out roughly where the subject is; and
a flat gradient, which must come back with nothing rather than with a speck
that the shell would then draw over the clock.
"""
import ast
import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SHELL = os.path.join(ROOT, "packages", "genesi-caelestia-shell")
DEPTH = os.path.join(SHELL, "genesi-depth")
LAYER = os.path.join(SHELL, "GenesiDepth.qml")
SETTER = os.path.join(ROOT, "packages", "genesi-center", "genesi-center-set")

failures = []


def ok(what):
    print(f"  ok   {what}")


def bad(what, why):
    print(f"  FAIL {what}")
    print(f"         {why}")
    failures.append(what)


print("== genesi-depth ==")

src = io.open(DEPTH, encoding="utf-8").read()
try:
    ast.parse(src)
    ok("genesi-depth parses")
except SyntaxError as e:
    bad("genesi-depth parses", str(e))

# ── The three lists ────────────────────────────────────────────────────────
tiers = set(re.findall(r'^    "(\w+)": \{"side"', src, re.M))
setter = io.open(SETTER, encoding="utf-8").read()


def enum_for(key):
    m = re.search(r'"%s": \("enum", \(([^)]*)\)\)' % re.escape(key), setter)
    return set(re.findall(r'"(\w*)"', m.group(1))) if m else None


quality = enum_for("background.depth.quality")
if quality is None:
    bad("the writer accepts background.depth.quality",
        "genesi-center-set has no enum for it, so the studio's cards write a "
        "key nothing validates")
elif quality != tiers:
    bad("the tiers and the writer agree on quality",
        f"genesi-depth has {sorted(tiers)}, the writer takes {sorted(quality)}")
else:
    ok(f"quality is {sorted(tiers)} in both the tool and the writer")

layer = io.open(LAYER, encoding="utf-8").read()
# Comment-stripped: every one of these names is also in a comment nearby
# explaining what it does, and a guard that matches its own prose is a guard
# that passes on the bug it exists to catch.
layer = re.sub(r"//[^\n]*", "", layer)

# edgeFade is the TOOL's list: the shell passes the name straight through and
# genesi-depth owns what it means in pixels. So it is checked against FADES,
# the way quality is checked against TIERS -- there is no switch in the layer
# to compare against any more, and that is the improvement.
fades = set(re.findall(r'^FADES = \{([^}]*)\}', src, re.M))
fade_names = set(re.findall(r'"(\w+)":', "".join(fades)))
want = enum_for("background.depth.edgeFade")
if want is None:
    bad("the writer accepts background.depth.edgeFade", "there is no enum")
elif want != fade_names:
    bad("the tool and the writer agree on edgeFade",
        f"genesi-depth has {sorted(fade_names)}, the writer takes "
        f"{sorted(want)}")
else:
    ok(f"edgeFade is {sorted(fade_names)} in both the tool and the writer")

for key, prop in (("background.depth.strength", "strength"),
                  ("background.depth.shadow", "shadow")):
    want = enum_for(key)
    if want is None:
        bad(f"the writer accepts {key}", "there is no enum for it")
        continue
    # The switch in the layer names every value but the default one, which is
    # the `return` at the end. So the cases have to be a subset, and what is
    # missing has to be exactly one name.
    block = re.search(r"switch \(root\.cfg\.%s\) \{(.*?)\n    \}" % prop,
                      layer, re.S)
    if not block:
        bad(f"GenesiDepth.qml reads {prop}",
            "no switch over it, so the setting is stored and drawn by nothing")
        continue
    cases = set(re.findall(r'case "(\w+)":', block.group(1)))
    unknown = cases - want
    if unknown:
        bad(f"{prop}'s cases exist",
            f"the layer handles {sorted(unknown)}, which the writer refuses")
    elif len(want - cases) != 1:
        bad(f"{prop} has one default",
            f"the layer names {sorted(cases)} of {sorted(want)}; the ones it "
            "does not name all fall through to the same answer")
    else:
        ok(f"{prop}: {sorted(want)}, one of them the fallthrough")

# ── Does it cut? ───────────────────────────────────────────────────────────
try:
    import cv2
    import numpy as np
except ImportError:
    print("  note OpenCV is not importable here; the cut itself is unchecked")
else:
    tmp = tempfile.mkdtemp(prefix="genesi-depth-test-")
    env = dict(os.environ, XDG_CACHE_HOME=os.path.join(tmp, "cache"))

    # One clear subject on a quiet background: a bright disc, off centre.
    subject = np.zeros((600, 900, 3), np.uint8)
    for y in range(600):
        subject[y, :] = (30 + y // 12, 22 + y // 16, 40 + y // 20)
    cv2.circle(subject, (560, 300), 130, (240, 230, 205), -1)
    sub_path = os.path.join(tmp, "subject.png")
    cv2.imwrite(sub_path, subject)

    # A DARK subject on a bright, busy background -- the case that shipped
    # broken. Spectral-residual saliency looks for unusual texture, so on a
    # wallpaper of a hooded figure against an ember-filled sky it picked the
    # embers and left the figure, which is the largest, flattest, darkest
    # thing in the frame. The suite had only the opposite case, so it could
    # not have caught it.
    dark = np.zeros((600, 900, 3), np.uint8)
    for y in range(600):
        dark[y, :] = (40 + y // 6, 110 + y // 9, 210 - y // 12)
    rng = np.random.default_rng(11)
    for _ in range(500):
        x, y = int(rng.integers(0, 900)), int(rng.integers(0, 600))
        cv2.circle(dark, (x, y), int(rng.integers(1, 4)),
                   (180, 230, 255), -1)
    # The figure: a dark column with a hood, centred.
    cv2.rectangle(dark, (400, 250), (500, 520), (28, 24, 22), -1)
    cv2.ellipse(dark, (450, 250), (55, 70), 0, 180, 360, (28, 24, 22), -1)
    dark_path = os.path.join(tmp, "dark.png")
    cv2.imwrite(dark_path, dark)

    # ...and a picture with nothing in it at all.
    flat = np.zeros((600, 900, 3), np.uint8)
    for y in range(600):
        flat[y, :] = (40 + y // 20, 40 + y // 20, 40 + y // 20)
    flat_path = os.path.join(tmp, "flat.png")
    cv2.imwrite(flat_path, flat)

    def run(path):
        return subprocess.run(
            [sys.executable, DEPTH, "cutout", path, "--quality", "standard",
             "--edge-fade", "soft"],
            capture_output=True, text=True, env=env)

    r = run(sub_path)
    if r.returncode != 0:
        bad("a picture with a subject produces a cut-out",
            f"exit {r.returncode}: {r.stderr.strip()}")
    else:
        out = r.stdout.strip()
        cut = cv2.imread(out, cv2.IMREAD_UNCHANGED)
        if cut is None or cut.shape[2] != 4:
            bad("the cut-out has an alpha channel", f"{out} is not RGBA")
        else:
            a = cut[:, :, 3]
            covered = (a > 128).mean()
            # The disc is about 9% of the frame. Anything under a couple of
            # per cent is a speck and anything over half is the whole picture
            # with a bite out of it -- both are the failures that make this
            # look broken rather than subtle.
            if not 0.02 < covered < 0.5:
                bad("the cut-out is about the size of the subject",
                    f"it covers {covered:.1%} of the frame")
            elif a[300, 560] < 128:
                bad("the cut-out covers the subject",
                    "the middle of the disc is transparent")
            elif a[30, 30] > 128:
                bad("the cut-out leaves the background",
                    "the top-left corner is opaque")
            else:
                ok(f"a subject is cut out, covering {covered:.1%} of the frame")

        # ...and the second run is the cache, not a second segmentation.
        again = run(sub_path)
        if again.stdout.strip() != out:
            bad("the cut-out is cached",
                "a second run produced a different path")
        else:
            ok("the second run comes from the cache")

    r = run(dark_path)
    if r.returncode != 0:
        bad("a dark subject on a bright background is found",
            f"exit {r.returncode}: {r.stderr.strip()}")
    else:
        cut = cv2.imread(r.stdout.strip(), cv2.IMREAD_UNCHANGED)
        a = cut[:, :, 3]
        covered = (a > 128).mean()
        # The figure is about 6% of the frame.
        if not 0.015 < covered < 0.35:
            bad("the dark subject's cut-out is about its size",
                f"it covers {covered:.1%} of the frame")
        elif a[400, 450] < 128:
            bad("the cut-out covers the dark subject",
                "the middle of the figure is transparent")
        elif a[60, 80] > 128:
            bad("the cut-out leaves the bright background",
                "a corner of the sky is opaque")
        else:
            ok(f"a dark subject on a bright field is cut out, {covered:.1%}")

    r = run(flat_path)
    if r.returncode == 0:
        bad("a picture with no subject produces nothing",
            "it returned a cut-out, which the shell would draw over the clock")
    else:
        ok("a picture with no subject is refused rather than guessed at")

print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("depth: OK")
