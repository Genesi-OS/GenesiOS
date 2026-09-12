#!/usr/bin/env python3
"""genesi-depth: does it parse, do the three lists agree, and does it cut?

Depth's settings are spelled out in three places -- the tiers in genesi-depth,
the enums genesi-center-set accepts, and the switch statements in
GenesiDepth.qml that turn a name into an opacity or a blur. Every one of them
is a list of the same words, and a word that appears in two of the three is a
setting that saves, applies to nothing, and produces no error anywhere. That
is this repository's oldest failure and it has a guard now.

The cut itself is checked when OpenCV is importable, which it is in the build
container and may not be on a laptop.

── What these pictures are for, and what they cannot do ─────────────────────

The fixtures are drawn, and a drawn picture has a property no wallpaper has:
its background has almost no saliency. The accept/reject threshold was once
calibrated on three of them -- a disc on a gradient, a planet on a starfield,
a plain gradient -- and the number that separated those (inside saliency four
times outside) turned out to separate nothing on a photograph: measured on
eight, it lands between 2.7 and 6.0, refusing a cat on a lawn and a Porsche in
daylight while accepting a photograph of a concrete wall.

So the honest division of labour:

  * these fixtures are REGRESSION cover. A subject on a quiet field, a dark
    subject on a bright busy one, the same two with a photograph's grain over
    the whole frame, and three pictures with no subject in them -- a flat
    gradient, a busy texture, and a ground region that is salient and is
    still not a thing in the picture. The last two are new: the only negative
    this suite used to have was a flat gradient, which every version of the
    code has always refused.

  * the THRESHOLDS are checked against the photographs they were measured on,
    which are recorded here as numbers. Nothing drawn can stand in for that,
    so instead: change a threshold and this test fails, pointing at the table
    it was measured from.

  * real pictures, when there are some. Point GENESI_DEPTH_PHOTOS at a folder
    of `subject-*.jpg` / `nosubject-*.jpg` and each one is checked too. That
    is how the thresholds below were arrived at, and it is how to check them
    against your own wallpapers:

        GENESI_DEPTH_PHOTOS=~/pics python ci/depth-test.py
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

# ── The thresholds, and the photographs they were measured on ─────────────
#
# Eight photographs, at the standard tier. `edge` is the gradient along the
# cut over the gradient everywhere; `colour` is the mask's mean Lab distance
# from the picture's average colour; `area` is the share of the frame.
#
#   picture                      area    edge  colour   should be
#   Porsche 911, on a track     38.2%    4.54    69.7   subject
#   Porsche 718, forecourt      22.2%    4.25    65.2   subject
#   flower, macro               17.9%   12.01    99.5   subject
#   cat on a lawn               56.0%    1.56    38.8   no subject
#   city at night               57.2%    2.18    48.9   no subject
#   mountain panorama           62.2%    1.42    44.1   no subject
#   concrete wall               57.8%    1.37     1.4   no subject
#   sand dune                  100.0%    0.00    34.2   no subject
#
# Every subject clears all three; every non-subject fails at least one by a
# factor of two. The constants are pinned here so that moving one without
# re-measuring fails the build -- the previous threshold was moved on a
# reading of three drawn pictures, and that is the whole reason this table
# exists.
WANT = {"MIN_EDGE": "3.0", "MIN_COLOUR": "18.0",
        "MIN_AREA": "0.005", "MAX_AREA": "0.50"}
for const, value in sorted(WANT.items()):
    m = re.search(r"^%s = (\S+)$" % const, src, re.M)
    if not m:
        bad(f"genesi-depth defines {const}",
            "the verdict's thresholds are what this test is pinning; a "
            "missing one means the judgement moved somewhere else")
    elif m.group(1) != value:
        bad(f"{const} is still {value}",
            f"it is {m.group(1)}. The table above is the evidence for "
            f"{value}; if {m.group(1)} is right, re-measure on photographs "
            "and rewrite the table with the new numbers.")
    else:
        ok(f"{const} = {value}, as measured")

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

    def grain(h, w, seed, scale=5, amp=15):
        """Low-frequency noise, the way a photograph's surfaces vary."""
        rng = np.random.default_rng(seed)
        small = rng.normal(0, 1, (h // scale + 2, w // scale + 2))
        up = cv2.resize(small.astype(np.float32), (w, h),
                        interpolation=cv2.INTER_CUBIC)
        return cv2.GaussianBlur(up, (0, 0), 1.5) * amp

    def grainy(img, seed=7):
        out = img.astype(np.float32)
        for c in range(3):
            out[:, :, c] += grain(img.shape[0], img.shape[1], seed + c)
        return np.clip(out, 0, 255).astype(np.uint8)

    # The same two subjects with a photograph's grain over the WHOLE frame,
    # background included. The subject is exactly where it was; the
    # background stops being empty. A saliency stack that only works on clean
    # gradients passes the two above and fails these.
    grain_paths = {}
    for label, base in (("subject", subject), ("dark", dark)):
        p = os.path.join(tmp, label + "-grain.png")
        cv2.imwrite(p, grainy(base))
        grain_paths[label] = p

    # Two pictures that ARE salient and are still not subjects. The only
    # negative this suite had was a flat gradient, which no version of the
    # code has ever accepted -- so it never tested the judgement, only the
    # absence of one.
    wall = np.zeros((620, 980, 3), np.float32)
    wall[:, :] = (96, 92, 104)
    for i, (sc, amp) in enumerate(((3, 26), (7, 20), (14, 14), (28, 10))):
        g = grain(620, 980, 20 + i, sc, amp)
        for c in range(3):
            wall[:, :, c] += g * (1.0 + 0.1 * c)
    wall_path = os.path.join(tmp, "wall.png")
    cv2.imwrite(wall_path, np.clip(wall, 0, 255).astype(np.uint8))

    ground = np.zeros((620, 980, 3), np.float32)
    for y in range(620):
        ground[y, :] = (150, 146, 142) if y < 210 else (60, 104, 66)
    for c in range(3):
        ground[:, :, c] += grain(620, 980, 40 + c, 4, 16)
    ground_path = os.path.join(tmp, "ground.png")
    cv2.imwrite(ground_path, np.clip(ground, 0, 255).astype(np.uint8))

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

    for label, path, hint in (
            ("subject", grain_paths["subject"], "a bright disc"),
            ("dark", grain_paths["dark"], "a dark figure")):
        r = run(path)
        if r.returncode != 0:
            bad(f"{hint} is still found with grain over the whole frame",
                f"exit {r.returncode}: {r.stderr.strip()}\n"
                "         This is the property a photograph has and a drawn "
                "fixture does not: a background that is not empty.")
            continue
        cut = cv2.imread(r.stdout.strip(), cv2.IMREAD_UNCHANGED)
        covered = (cut[:, :, 3] > 128).mean()
        if not 0.015 < covered < 0.45:
            bad(f"{hint}'s cut-out is about its size, with grain",
                f"it covers {covered:.1%} of the frame")
        else:
            ok(f"{hint} survives a grainy background, {covered:.1%}")

    for label, path, why in (
            ("flat", flat_path, "a gradient with nothing in it"),
            ("wall", wall_path, "a busy texture, salient everywhere"),
            ("ground", ground_path, "a ground region: salient, not a thing")):
        r = run(path)
        if r.returncode == 0:
            bad(f"{why} produces nothing",
                "it returned a cut-out, which the shell would draw over the "
                "clock")
        elif "no subject here" not in (r.stderr or ""):
            # The reason is the feature: `genesi-depth probe` exists because
            # two of these were diagnosed from a screenshot and both
            # diagnoses were wrong.
            bad(f"{why} is refused WITH a reason",
                f"it said {r.stderr.strip()[:90]!r}, which does not say "
                "which measure failed")
        else:
            ok(f"{why} is refused, and says why")

    # ── Real pictures, when there are any ─────────────────────────────────
    #
    # Nothing drawn can stand in for a photograph -- that is the lesson this
    # whole section is a record of. So the suite takes them when they are
    # offered and says nothing when they are not.
    photos = os.environ.get("GENESI_DEPTH_PHOTOS", "").strip()
    if photos and os.path.isdir(photos):
        seen = 0
        for name in sorted(os.listdir(photos)):
            want = (True if name.startswith("subject-")
                    else False if name.startswith("nosubject-") else None)
            if want is None:
                continue
            seen += 1
            r = run(os.path.join(photos, name))
            got = r.returncode == 0
            if got != want:
                bad(f"{name} is {'a subject' if want else 'not a subject'}",
                    (r.stderr.strip() or "it produced a cut-out")[:160])
            else:
                ok(f"{name}: {'cut' if got else 'refused'}, as named")
        if seen == 0:
            print(f"  note {photos} has no subject-* / nosubject-* pictures")
    else:
        print("  note no GENESI_DEPTH_PHOTOS folder; the thresholds are "
              "checked against the recorded table, not re-measured")

print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("depth: OK")
