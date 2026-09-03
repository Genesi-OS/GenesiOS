#!/usr/bin/env python3
"""
gtk-init-order-test.py — a GTK widget must not be built before GTK exists.

── Why ──────────────────────────────────────────────────────────────────────

All four Genesi tray applets segfaulted at login within a second of each other,
with the same stack every time:

    libgtk-3 ...                 <- crash, inside GTK's own instance init
    g_type_create_instance
    g_object_new                 <- GTK constructing a sub-widget
    libgtk-3 ...
    g_type_create_instance
    g_object_new_with_properties
    _gi.cpython-314              <- PyGObject constructing the widget

Nothing was wrong with the widgets. The order was: every tray builds its whole
menu inside `Tray.__init__`, and only afterwards calls `Gtk.main()` -- which is
what used to initialise GTK. PyGObject initialised Gtk implicitly on import for
years and stopped, so the menus were being built against uninitialised GTK and
crashing in the first sub-object GTK tried to make for itself.

The symptom is the worst kind: three tray icons that simply are not there, on a
desktop that otherwise starts fine, with the reason only in a coredump.

── What this checks ─────────────────────────────────────────────────────────

For every Python file that constructs a GTK widget: `Gtk.init` or
`Gtk.init_check` must appear before the first widget constructor. Line order in
the file is a crude proxy for execution order, but it is the right one here --
these are module-level guards, and a tray that inits inside main() after
building the menu is exactly the bug.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

# Directories worth walking. The submodules carry trays too -- genesi-update's
# is one of the four that crashed -- so they are not skipped.
ROOTS = [
    os.path.join(ROOT, "genesi-arch", "packages"),
    os.path.join(ROOT, "genesi-update-full", "src"),
]

WIDGET = re.compile(r"\bGtk\.(Menu|MenuItem|Window|Label|Box|Button|"
                    r"CheckMenuItem|SeparatorMenuItem|Image|ApplicationWindow)\s*\(")
INIT = re.compile(r"\bGtk\.init(_check)?\s*\(")
IMPORTS_GTK = re.compile(r"from\s+gi\.repository\s+import\s+[^\n]*\bGtk\b")


def python_files():
    for base in ROOTS:
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__")]
            for fn in filenames:
                p = os.path.join(dirpath, fn)
                if fn.endswith(".py"):
                    yield p
                    continue
                # Genesi's CLIs are extensionless; sniff the shebang.
                try:
                    with io.open(p, "rb") as fh:
                        if fh.read(2) != b"#!":
                            continue
                    with io.open(p, encoding="utf-8", errors="replace") as fh:
                        if "python" in fh.readline():
                            yield p
                except OSError:
                    continue


def main():
    print("== GTK init order ==")
    checked = 0
    bad = []
    for path in sorted(python_files()):
        try:
            with io.open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        src = "".join(lines)
        if not IMPORTS_GTK.search(src):
            continue
        checked += 1

        first_widget = None
        first_init = None
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if first_init is None and INIT.search(line):
                first_init = i + 1
            if first_widget is None and WIDGET.search(line):
                first_widget = i + 1
        if first_widget is None:
            continue
        if first_init is None or first_init > first_widget:
            bad.append((path, first_init, first_widget))

    print(f"  files using Gtk: {checked}")
    if bad:
        print(f"  FAIL  {len(bad)} file(s) build a GTK widget before GTK is "
              "initialised:")
        for path, init, widget in bad:
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            where = f"init at line {init}" if init else "no Gtk.init at all"
            print(f"          - {rel}: first widget at line {widget}, {where}")
        print()
        print("        PyGObject no longer initialises Gtk on import, and")
        print("        Gtk.main() is too late -- the menu is already built.")
        print("        Call Gtk.init_check() at module level, before the first")
        print("        widget. init_check rather than init: a tray started")
        print("        before the display is up should exit, not abort.")
        return 1

    print("  PASS  every file initialises GTK before its first widget")
    print("\nGTK init order: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
