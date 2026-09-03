#!/usr/bin/env python3
"""
caelestia-nexus-pages.py — register Genesi's Nexus pages in caelestia's registries.

Called from genesi-caelestia-shell's prepare():

    caelestia-nexus-pages.py <path/to/release/modules/nexus> <dir holding our .qml>

It does the CHECK and the COPY, in that order, because separating them is how
the first attempt broke the build: prepare() installed our pages and then ran
this, and the "does upstream ship this page?" test found the file we had just
written and refused. The local test had exercised the script against a pristine
tree, so it never saw the order the build actually used. One script owning both
halves makes that mistake unrepresentable rather than merely fixed.

── What this has to do, and why it is more than a file copy ─────────────────

The Updates page needed only a file: upstream already REGISTERS Updates and
points it at PlaceholderComp. Display and Mouse are different:

  * Display is registered only as a COMMENT — PageRegistry has the entry
    commented out under a `// TODO`. The menu item has to be enabled as well as
    the page supplied.

  * Mouse does not exist upstream in any form. Both the entry and the page are
    ours.

── The alignment that makes this dangerous ──────────────────────────────────

`PageRegistry.pages` and `PageCompRegistry.pageComps` are two flat lists
matched BY INDEX. Nothing connects an entry to its component except position.
Insert into one and not the other, or at a different offset, and every page
after that point opens the wrong screen — with no error anywhere, because both
lists are still perfectly valid QML.

So both edits happen here, in one place, from one ordered description, and
every precondition is asserted first. A failure fails the BUILD: the correct
outcome for an override whose assumptions have expired is a red build with a
specific message, not a silently wrong settings app.
"""
import io
import os
import re
import shutil
import sys

# In the order they are inserted, immediately after the "// Connectivity"
# marker in both files. Upstream's own Display entry is commented out at
# exactly that spot, so this is where it was always meant to go.
PAGES = [
    {
        "name": "Display",
        "label": "Display",
        "icon": "monitor",
        "description": "Scale, rotation, arrangement",
        "comp": "DisplayPage",
    },
    {
        "name": "Mouse",
        "label": "Mouse",
        "icon": "mouse",
        "description": "Pointer speed and acceleration",
        "comp": "MousePage",
    },
]


def fail(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def patch_page_registry(path):
    s = io.open(path, encoding="utf-8").read()

    if "// Connectivity" not in s:
        fail(f"the '// Connectivity' section is gone from {path} -- upstream "
             "restructured the registry and this patch is now blind.")

    # Comment lines are stripped before looking for a real entry: upstream's
    # own Display entry IS a comment, and matching it would make this refuse to
    # run on precisely the tree it is written for.
    live = "\n".join(l for l in s.splitlines()
                     if not l.lstrip().startswith("//"))

    for p in PAGES:
        # An entry upstream has since added for REAL must not be duplicated:
        # two entries, one component, and everything after shifts.
        if re.search(r'label:\s*qsTr\("%s"\)' % p["name"], live):
            fail(f"upstream now registers a '{p['name']}' page of its own. "
                 "Adding ours would duplicate the entry and shift every page "
                 "after it onto the wrong component. Decide by hand.")

    # Upstream's commented-out Display entry is removed rather than uncommented:
    # ours carries a different description, and leaving theirs would put two
    # Display entries in the list the moment they uncomment it.
    todo = re.search(
        r"[ \t]*// TODO\n(?:[ \t]*//[^\n]*\n)+", s)
    if todo and "Display" in todo.group(0):
        s = s[:todo.start()] + s[todo.end():]
    else:
        fail("the commented-out Display entry is no longer where it was in "
             "PageRegistry.qml. It is the anchor this patch inserts at.")

    block = ""
    for p in PAGES:
        block += (
            "        {\n"
            '            label: qsTr("%s"),\n'
            '            icon: "%s",\n'
            '            description: qsTr("%s"),\n'
            '            category: "connectivity"\n'
            "        },\n" % (p["label"], p["icon"], p["description"]))

    anchor = "        // Connectivity\n"
    if anchor not in s:
        fail("the '// Connectivity' marker lost its indentation in "
             "PageRegistry.qml; refusing to guess where to insert.")
    s = s.replace(anchor, anchor + block, 1)
    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("PageRegistry: + " + ", ".join(p["name"] for p in PAGES))


def patch_comp_registry(path):
    s = io.open(path, encoding="utf-8").read()

    for p in PAGES:
        if p["comp"] in s:
            fail(f"{p['comp']} is already referenced in PageCompRegistry.qml.")

    # The component list is anchored on the same marker, so the two lists stay
    # in step by construction rather than by counting.
    anchor = "        // Connectivity\n"
    if anchor not in s:
        fail("the '// Connectivity' marker is gone from PageCompRegistry.qml, "
             "so the two registries can no longer be kept in step.")

    block = ""
    for p in PAGES:
        block += (
            "        Component {\n"
            "            // %s (Genesi)\n"
            "            StackPage {\n"
            "                Component {\n"
            "                    %s {}\n"
            "                }\n"
            "            }\n"
            "        },\n" % (p["name"], p["comp"]))

    s = s.replace(anchor, anchor + block, 1)
    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("PageCompRegistry: + " + ", ".join(p["comp"] for p in PAGES))


def verify_alignment(nexus_dir):
    """
    The two lists must still have the same length after the edit.

    Counting is crude, but the failure it catches -- every page after the
    insertion point opening the wrong screen -- has no other symptom. Both
    lists remain valid QML either way, so nothing else would notice.
    """
    reg = io.open(os.path.join(nexus_dir, "PageRegistry.qml"),
                  encoding="utf-8").read()
    comp = io.open(os.path.join(nexus_dir, "PageCompRegistry.qml"),
                   encoding="utf-8").read()
    n_pages = len(re.findall(r"^\s{8}\{$", reg, re.M))
    n_comps = len(re.findall(r"^\s{8}Component \{$", comp, re.M))
    if n_pages != n_comps:
        fail(f"the registries are out of step: {n_pages} entries against "
             f"{n_comps} components. Every page after the mismatch would open "
             "the wrong screen, with no error anywhere.")
    print(f"registries aligned: {n_pages} entries, {n_comps} components")


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip())
        return 1
    nexus, ours = sys.argv[1], sys.argv[2]
    reg = os.path.join(nexus, "PageRegistry.qml")
    comp = os.path.join(nexus, "PageCompRegistry.qml")
    for p in (reg, comp):
        if not os.path.exists(p):
            fail(f"{p} does not exist -- the Nexus registries moved or were "
                 "renamed.")
    for p in PAGES:
        shipped = os.path.join(nexus, "pages", p["comp"] + ".qml")
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {p['comp']}.qml. Ours would "
                 "silently replace it. Decide by hand: keep theirs (drop this "
                 "page), or keep ours and record why.")
    patch_page_registry(reg)
    patch_comp_registry(comp)
    verify_alignment(nexus)

    # Only now are our pages written in. Doing this before the checks above is
    # what broke the build: the "upstream ships this" test cannot tell a file
    # upstream shipped from one we had just installed ourselves.
    dest = os.path.join(nexus, "pages")
    for p in PAGES:
        src = os.path.join(ours, p["comp"] + ".qml")
        if not os.path.exists(src):
            fail(f"{src} is missing -- the page this registers has no file.")
        shutil.copyfile(src, os.path.join(dest, p["comp"] + ".qml"))
        print(f"installed {p['comp']}.qml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
