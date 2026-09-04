#!/usr/bin/env python3
"""
shader-sanity-test.py — a screen shader must be in the shape Hyprland accepts.

Hyprland compiles `decoration:screen_shader` at load time. A shader that does
not compile leaves the screen untouched and says so nowhere the user will look,
so a broken one ships as a launcher entry that appears to do nothing -- the
failure this repository has already met more than once.

Two checks exist for that, at different depths:

  * This one is structural, runs anywhere, and catches the mistakes that come
    from writing the wrong dialect: desktop GLSL instead of GLSL ES, `varying`
    and `gl_FragColor` from the old pipeline, or a different uniform name than
    the compositor binds.

  * genesi-shaders' PKGBUILD runs glslangValidator over every file at build
    time, which is the real compile. That needs a toolchain, so it lives in the
    build rather than here.

Structural first because it is the half that can run on every commit.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# Flat beside the PKGBUILD: makepkg takes files and URLs in source=(), not a
# directory, and does not follow a subpath either.
SHADERS = os.path.join(ROOT, "genesi-arch", "packages", "genesi-shaders")
PKGBUILD = os.path.join(SHADERS, "PKGBUILD")

# What Hyprland binds, taken from the two shaders hyprshade ships upstream
# rather than from documentation.
REQUIRED = [
    ("#version 300 es", "the GLSL ES 3.00 version directive"),
    ("precision highp float;", "a float precision qualifier (required in ES)"),
    ("in vec2 v_texcoord;", "the texture coordinate Hyprland binds"),
    ("uniform sampler2D tex;", "the screen texture Hyprland binds"),
    ("out vec4 fragColor;", "the fragment output"),
]

# Constructs from desktop GLSL or the fixed pipeline. Each compiles fine
# somewhere else, which is exactly why they are easy to write by mistake.
FORBIDDEN = [
    (r"\bgl_FragColor\b", "gl_FragColor -- removed in ES 3.00; write to fragColor"),
    (r"\bvarying\b", "varying -- ES 3.00 uses in/out"),
    (r"\btexture2D\s*\(", "texture2D() -- ES 3.00 uses texture()"),
    (r"\battribute\b", "attribute -- ES 3.00 uses in"),
]


def main():
    print("== screen shaders ==")
    if not os.path.isdir(SHADERS):
        print(f"  FAIL  {SHADERS} does not exist")
        return 1

    files = sorted(f for f in os.listdir(SHADERS) if f.endswith(".glsl"))
    if not files:
        print("  FAIL  no shaders found")
        return 1

    bad = []
    for fn in files:
        path = os.path.join(SHADERS, fn)
        with io.open(path, encoding="utf-8") as fh:
            src = fh.read()
        problems = []

        for needle, what in REQUIRED:
            if needle not in src:
                problems.append(f"missing {what}")

        # Comments do not count: several of these words appear in the prose
        # explaining why they are not used.
        code = re.sub(r"//.*", "", src)
        for pattern, what in FORBIDDEN:
            if re.search(pattern, code):
                problems.append(f"uses {what}")

        if "void main(" not in code:
            problems.append("has no main()")

        # #version has to come before any code. Comments and blank lines above
        # it are allowed, and upstream's own shaders use that.
        before = code.split("#version", 1)[0]
        if before.strip():
            problems.append("has code before #version")

        # A shader that never reads the screen is a solid colour, which is
        # always a mistake rather than an effect.
        if "texture(tex," not in code.replace(" ", "").replace("texture(tex,",
                                                               "texture(tex,"):
            if not re.search(r"texture\s*\(\s*tex\s*,", code):
                problems.append("never samples tex")

        if problems:
            bad.append((fn, problems))

    # Listing the files by hand in source=() is what makepkg requires, and
    # "add it in two places" is how a shader goes missing without a word: the
    # file is committed, nothing packages it, and the launcher entry turns on
    # something that is not installed. Make the two agree or fail.
    listed = set()
    if os.path.exists(PKGBUILD):
        with io.open(PKGBUILD, encoding="utf-8") as fh:
            pkg_src = fh.read()
        m = re.search(r"^source=\((.*?)^\)", pkg_src, re.M | re.S)
        if m:
            listed = set(re.findall(r"'([^']+\.glsl)'", m.group(1)))
        n_sums = 0
        ms = re.search(r"^sha256sums=\((.*?)^\)", pkg_src, re.M | re.S)
        if ms:
            n_sums = len(re.findall(r"'[^']+'", ms.group(1)))
        if listed and n_sums != len(listed):
            bad.append(("PKGBUILD", [
                f"source=() lists {len(listed)} files but sha256sums=() has "
                f"{n_sums} entries"]))

    on_disk = set(files)
    if listed or on_disk:
        for missing in sorted(on_disk - listed):
            bad.append((missing, ["is not listed in the PKGBUILD's source=(), "
                                  "so it is never packaged"]))
        for ghost in sorted(listed - on_disk):
            bad.append((ghost, ["is listed in source=() but does not exist"]))

    print(f"  shaders: {len(files)}")
    if bad:
        print(f"  FAIL  {len(bad)} shader(s) are not in the shape Hyprland "
              "accepts:")
        for fn, problems in bad:
            print(f"          {fn}")
            for p in problems:
                print(f"            - {p}")
        print()
        print("        Hyprland silently leaves the screen untouched when a")
        print("        shader fails to compile, so this ships as a launcher")
        print("        entry that appears to do nothing.")
        return 1

    print("  PASS  every shader declares what Hyprland binds and nothing older")
    print("\nscreen shaders: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
