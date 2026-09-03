#!/usr/bin/env python3
"""
caelestia-patches.py — every edit Genesi makes to caelestia's own QML.

Called from genesi-caelestia-shell's prepare():

    caelestia-patches.py <path/to/release> <dir holding our .qml>

It owns three things, together, because they share one rule: an override is a
bet that upstream still looks the way it did when the override was written, and
the bet has to be checked before it is placed.

  * the Display and Mouse pages, and their entries in the two registries
  * the Nexus settings search, which upstream ships as a box with nothing
    behind it
  * the launcher's action selector, without which typing after ">" narrows
    nothing

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

# Descriptions carry both languages. The settings search matches on label plus
# description as a plain SUBSTRING, so a Portuguese term costs nothing here --
# unlike the launcher, where fzf's subsequence matching turned long haystacks
# into noise. Upstream's own entries are left alone; they are not ours to name.
#
# In the order they are inserted, immediately after the "// Connectivity"
# marker in both files. Upstream's own Display entry is commented out at
# exactly that spot, so this is where it was always meant to go.
PAGES = [
    {
        "name": "Display",
        "label": "Display",
        "icon": "monitor",
        "description": "Scale, rotation, arrangement · Escala, rotação e posição dos monitores (telas)",
        "comp": "DisplayPage",
    },
    {
        "name": "Mouse",
        "label": "Mouse",
        "icon": "mouse",
        "description": "Pointer speed and acceleration · Velocidade e aceleração do mouse",
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


def patch_nav_search(nexus_dir):
    """
    Make the Nexus settings search actually search.

    Upstream ships the box and nothing behind it: SearchBar binds
    `nState.searchOpen = searchField.text.length > 0`, and that boolean is read
    by nobody. NavLocations lists `PageRegistry.pages` unfiltered. So typing in
    it does exactly nothing, which is what was reported.

    Three small edits rather than three file overrides, so upstream finishing
    this feature shows up as a failed precondition instead of us quietly
    replacing their version with ours.

    The list is filtered by VISIBILITY, not by model. `item.index` is compared
    against `nState.currentPageIdx` and drives navigation, so filtering the
    model would shift every index and open the wrong page -- the same hazard as
    the two registries, one level down. QtQuick.Layouts already excludes
    invisible items from the column, so the effect is identical and the indices
    stay put.

    Matching is a plain case-insensitive substring, not fzf. These are ten short
    labels; subsequence matching would return "Wallpaper & style" for "tela" and
    call it a hit.
    """
    state = os.path.join(nexus_dir, "NexusState.qml")
    bar = os.path.join(nexus_dir, "navpane", "SearchBar.qml")
    nav = os.path.join(nexus_dir, "navpane", "NavLocations.qml")
    for p in (state, bar, nav):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the Nexus nav pane was restructured.")

    # 1. Somewhere to keep what was typed.
    s = io.open(state, encoding="utf-8").read()
    if "searchText" in s:
        fail("NexusState already has a searchText -- upstream implemented the "
             "settings search. Drop this patch and keep theirs.")
    if "property bool searchOpen" not in s:
        fail("NexusState no longer declares searchOpen; the search patch is "
             "anchored on it.")
    s = s.replace("property bool searchOpen",
                  "property bool searchOpen\n"
                  "    // What was typed. Upstream keeps only the boolean, so the\n"
                  "    // text had nowhere to go and the box did nothing.\n"
                  "    property string searchText", 1)
    io.open(state, "w", encoding="utf-8", newline="\n").write(s)

    # 2. Put the text there.
    s = io.open(bar, encoding="utf-8").read()
    old = ('            Binding {\n'
           '                target: root.nState\n'
           '                property: "searchOpen"\n'
           '                value: searchField.text.length > 0\n'
           '            }')
    if old not in s:
        fail("SearchBar's searchOpen Binding is not where the patch expects it.")
    s = s.replace(old, old + '\n\n'
                  '            Binding {\n'
                  '                target: root.nState\n'
                  '                property: "searchText"\n'
                  '                value: searchField.text\n'
                  '            }', 1)
    io.open(bar, "w", encoding="utf-8", newline="\n").write(s)

    # 3. Read it.
    s = io.open(nav, encoding="utf-8").read()
    anchor = ("                readonly property bool isCurrentPage: "
              "index === root.nState.currentPageIdx")
    if anchor not in s:
        fail("NavLocations' isCurrentPage line is not where the patch expects "
             "it; refusing to guess where the filter goes.")
    s = s.replace(anchor, anchor + '\n'
                  '                // Hidden rather than filtered out of the model:\n'
                  '                // `index` drives navigation, so a shorter model\n'
                  '                // would open the wrong page. Layouts already skip\n'
                  '                // invisible items.\n'
                  '                readonly property string haystack: '
                  '`${modelData.label} ${modelData.description ?? ""}`.toLowerCase()\n'
                  '                readonly property bool matchesSearch: '
                  '!root.nState.searchText || '
                  'haystack.includes(root.nState.searchText.toLowerCase())', 1)

    old_vis = "                Layout.fillWidth: true\n"
    if old_vis not in s:
        fail("NavLocations' item layout line moved; the visible binding has no "
             "anchor.")
    s = s.replace(old_vis,
                  "                visible: item.matchesSearch\n" + old_vis, 1)
    io.open(nav, "w", encoding="utf-8", newline="\n").write(s)
    print("Nexus settings search: NexusState + SearchBar + NavLocations")


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


def patch_actions_selector(launcher_dir):
    """
    Give the launcher's action list a selector of its own.

    Reported from hardware: typing after ">" does not narrow the list -- every
    action stays on screen. Searching for an app filters correctly, so the
    machinery works; only the action path is broken.

    Comparing the four services that use Searcher shows exactly one difference:

        Apps      overrides selector()  ->  keys.map(k => item[k]).join(" ")
        Schemes   overrides selector()  ->  `${item.name} ${item.flavour}`
        Variants  overrides selector()
        Actions   does NOT              ->  falls back to `item[key]`

    Actions is the only one relying on the base class's dynamic bracket lookup,
    and it is the only one that does not filter. When the selector yields
    nothing usable, fzf has no text to score against and every entry survives --
    which is precisely "the options stay, typing changes nothing".

    So Actions gets the same explicit property read the two working services
    use. Cheap, and it removes the one thing that made this list different.
    """
    actions = os.path.join(launcher_dir, "services", "Actions.qml")
    if not os.path.exists(actions):
        fail(f"{actions} is gone -- the launcher services moved or were renamed.")

    s = io.open(actions, encoding="utf-8").read()
    if "function selector" in s:
        fail("Actions.qml now defines its own selector -- upstream fixed this. "
             "Drop the patch and keep theirs.")

    anchor = "    function transformSearch(search: string): string {"
    if anchor not in s:
        fail("Actions.qml's transformSearch is not where the patch expects it.")

    s = s.replace(anchor,
                  "    // Read the property by name instead of by bracket lookup, the way\n"
                  "    // Apps and Schemes both do. The inherited `item[key]` yielded nothing\n"
                  "    // to score against, so fzf kept every action and typing narrowed\n"
                  "    // nothing. (Genesi)\n"
                  "    function selector(item: var): string {\n"
                  "        return item.name;\n"
                  "    }\n"
                  "\n" + anchor, 1)
    io.open(actions, "w", encoding="utf-8", newline="\n").write(s)
    print("Actions.qml: explicit selector")


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip())
        return 1
    release, ours = sys.argv[1], sys.argv[2]
    nexus = os.path.join(release, "modules", "nexus")
    launcher = os.path.join(release, "modules", "launcher")
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
    patch_nav_search(nexus)
    patch_actions_selector(launcher)

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
