"""Exercise the drop-in writer: create, list, replace, delete.

The interesting part is drop_bind_block's skip counts. An override is three
lines and a created shortcut is two, and skipping the wrong number past a block
does not fail -- it silently eats the line after it, which is somebody else's
shortcut. So the test puts a neighbour under every block and checks it survived.
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile

# Resolved from THIS file, not from the working directory: CI runs the guards
# from the repo root and a person runs them from genesi-arch, and a test that
# only passes from one of those is a test that gets skipped.
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "packages", "genesi-center", "genesi-center-set")

spec = importlib.util.spec_from_loader(
    "gcs", importlib.machinery.SourceFileLoader("gcs", SRC))
gcs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gcs)

tmp = tempfile.mkdtemp()
gcs.DROPIN = os.path.join(tmp, "genesi-center.conf")
# No compositor here, so the reload must be a no-op rather than an exception.
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

fails = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def dropin():
    try:
        return io.open(gcs.DROPIN, encoding="utf-8").read().splitlines()
    except OSError:
        return []


def binds():
    out = io.StringIO()
    real, sys.stdout = sys.stdout, out
    try:
        gcs.cmd_binds()
    finally:
        sys.stdout = real
    return json.loads(out.getvalue())


print("== drop-in writer ==")

# A shortcut of somebody's own, and a neighbour that must never be touched.
gcs.cmd_newbind("SUPER SHIFT,T", "exec", "kitty")
io.open(gcs.DROPIN, "a", encoding="utf-8").write("bind = SUPER, Y, exec, foot\n")

d = dropin()
check("bind = SUPER SHIFT, T, exec, kitty" in d, "newbind writes the bind")
check(not any(l.startswith("unbind") for l in d),
      "newbind writes NO unbind (nothing shipped that combination)")

b = binds()
check(len(b["created"]) == 1, "cmd_binds reports one created shortcut")
check(b["created"][0]["key"] == "T" and b["created"][0]["arg"] == "kitty",
      "and reports its key and argument")
check(b["overrides"] == [], "and calls it created, not an override")

# Writing the same combination again replaces its block rather than stacking.
gcs.cmd_newbind("SUPER SHIFT,T", "exec", "alacritty")
d = dropin()
check(len([l for l in d if l.startswith("bind = SUPER SHIFT, T")]) == 1,
      "rebinding the same combination replaces its block")
check("bind = SUPER, Y, exec, foot" in d, "the neighbour survived the replace")

# An override alongside it, to prove the two kinds do not eat each other.
gcs.cmd_bind("SUPER,V", "SUPER ALT,V", "exec", "clipse")
b = binds()
check(len(b["overrides"]) == 1 and len(b["created"]) == 1,
      "an override and a created shortcut coexist")

gcs.cmd_delbind("SUPER SHIFT,T")
d = dropin()
check(not any("SUPER SHIFT, T" in l for l in d), "delbind removes the block")
check("bind = SUPER, Y, exec, foot" in d, "the neighbour survived the delete")
check("unbind = SUPER, V" in d, "and the override was left alone")
check(len(binds()["created"]) == 0, "nothing created is reported any more")

gcs.cmd_delbind("SUPER SHIFT,T")
check(True, "deleting one that is already gone does not raise")

print()
if fails:
    print("FAILED: %d" % len(fails))
    sys.exit(1)
print("drop-in writer: OK")
