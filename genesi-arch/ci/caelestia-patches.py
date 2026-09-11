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
  * the launcher's action search, which raced its own index and showed
    everything whenever it lost
  * a wall clock on the DDC/CI probe, which otherwise hammers a monitor that
    does not implement it until the DisplayPort link drops

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


def patch_actions_query(launcher_dir):
    """
    Filter the launcher's actions directly, instead of through a prebuilt index.

    This is NOT what made ">" stop filtering -- patch_applist_live_model is,
    and the note there has the evidence. Three diagnoses were written here
    before that one, each plausible and each wrong, because query() was never
    reached a second time and so could not be observed. It is kept for the one
    thing it does earn on its own merits, below.

    Filtering the live `list` also costs nothing: Searcher builds its fzf index
    once from `list`, and Actions' list is `variants.instances`, which a
    Variants block fills in asynchronously. Reading `list` at the moment of the
    search means there is no index to be too early for -- if instances are
    still arriving, the next keystroke simply sees more of them.

    Substring, not subsequence, and that is a deliberate downgrade from fzf.
    These are twenty-odd curated entries with names we choose. fzf's
    subsequence matching on this list is what returned "Scale 125%" for "girar"
    and "Make this screen primary" for "parede" -- confident and wrong, which is
    worse than nothing. Substring also means the Portuguese half of each name
    behaves exactly like the English half.

    It also gives actions GROUPS, because sixteen shaders in a list of forty
    drowned everything else: opening ">" was mostly shader rows. An action
    carrying `"group": "shader"` is hidden from the top level and reached by
    typing ">shader", exactly as ">scheme" reaches the colour schemes, and text
    after the group name filters inside it. Everything ungrouped behaves as it
    did.

    Doing this in query() rather than as a new AppList state is the small
    version on purpose: ">shader" leaves the state as "actions", so there is no
    new state, no new service and no new delegate -- the rows are the same
    actions they always were, merely addressed. The cost is that the group name
    is matched from the search text rather than declared to the state machine,
    which is fine while groups are ours and few.
    """
    actions = os.path.join(launcher_dir, "services", "Actions.qml")
    if not os.path.exists(actions):
        fail(f"{actions} is gone -- the launcher services moved or were renamed.")

    s = io.open(actions, encoding="utf-8").read()
    if "function query" in s:
        fail("Actions.qml now defines its own query() -- upstream changed how "
             "actions are searched. Drop this patch and read theirs.")

    anchor = "    function transformSearch(search: string): string {"
    if anchor not in s:
        fail("Actions.qml's transformSearch is not where the patch expects it.")

    block = (
        "    // Filter the live list rather than a prebuilt fzf index, and keep\n"
        "    // grouped entries out of the top level. Substring, not fzf: on\n"
        "    // twenty curated entries, subsequence matching returned\n"
        "    // \"Scale 125%\" for \"girar\". (Genesi)\n"
        "    function query(search: string): list<var> {\n"
        "        const raw = transformSearch(search.trim().replace(/\\s+/g, \" \"));\n"
        "        const all = [...list];\n"
        "\n"
        "        // A group name typed first opens that group, the way\n"
        "        // \">scheme\" opens the schemes; whatever follows filters\n"
        "        // inside it.\n"
        "        const space = raw.indexOf(\" \");\n"
        "        const head = (space < 0 ? raw : raw.slice(0, space)).toLowerCase();\n"
        "        const groups = all.map(a => a.group ?? \"\").filter(g => g);\n"
        "        if (groups.indexOf(head) >= 0) {\n"
        "            const rest = (space < 0 ? \"\" : raw.slice(space + 1)).toLowerCase();\n"
        "            const inGroup = all.filter(a => (a.group ?? \"\") === head);\n"
        "            if (!rest)\n"
        "                return inGroup;\n"
        "            return inGroup.filter(a => (a.name ?? \"\").toLowerCase().includes(rest));\n"
        "        }\n"
        "\n"
        "        // Otherwise a group shows only through its own entry, instead\n"
        "        // of spilling every row it holds into the top level.\n"
        "        const top = all.filter(a => !(a.group ?? \"\"));\n"
        "        const q = raw.toLowerCase();\n"
        "        if (!q)\n"
        "            return top;\n"
        "        return top.filter(a => (a.name ?? \"\").toLowerCase().includes(q));\n"
        "    }\n"
        "\n")
    s = s.replace(anchor, block + anchor, 1)

    # The group has to survive the trip from shell.json to the row. Action
    # exposes a fixed set of fields and drops everything else, so without this
    # every entry reads back as ungrouped and the grouping silently does
    # nothing -- the failure would look exactly like forgetting to edit
    # shell.json.
    name_prop = ('        readonly property string name: modelData.name ?? '
                 'qsTr("Unnamed")\n')
    if name_prop not in s:
        fail("Actions.qml's Action component does not expose `name` where the "
             "patch expects it.")
    s = s.replace(
        name_prop,
        name_prop + '        readonly property string group: modelData.group ?? ""\n',
        1)

    io.open(actions, "w", encoding="utf-8", newline="\n").write(s)
    print("Actions.qml: query() filters the live list, and groups fold away")


def patch_applist_live_model(launcher_dir):
    """
    Let the launcher's result list follow what is typed.

    Reported four times, in the same words each time: type ">", every action
    appears, and typing more changes nothing at all.

    AppList picks its results through a state machine. The state comes from the
    search text -- "apps", or "actions" for a ">" prefix, or "calc"/"scheme"/
    "variant" -- and each State carries the results with it:

        State {
            name: "actions"
            PropertyChanges {
                model.values: Actions.query(search.text)
                root.delegate: actionItem
            }
        }

    while the Transition that fades one mode into the next writes those same
    two properties at its midpoint:

        PropertyAction {
            targets: [model, root]
            properties: "values,delegate"
        }

    That imperative write lands ON the bound property and destroys the binding.
    So `values` is computed once, on the keystroke that ENTERS the state -- the
    ">" itself -- and then never again, because typing after ">" does not change
    the state. Everything you type is searched against a list that stopped
    listening.

    Reproduced under Qt 6.11 with this file's own structure reduced to its
    bones: query() logged one call, at the ">", and none for any of the five
    keystrokes after it, while the displayed list stayed whole. The same
    reduction with the fix below filters on every keystroke.

    The fix is to stop expressing data as a state change. `values` and
    `delegate` become ordinary bindings on `state` and `search.text`, the
    States keep only their names so the fade still runs, and the PropertyAction
    that clobbered them is gone. Both are bound to the same `state`, so they
    change together and a delegate never meets a row of the wrong kind.

    This is why ">scheme" and ">variant" did not filter either: same States,
    same PropertyAction, same frozen binding. Only "calc" was unaffected, and
    only because its value is the constant [0].

    One deliberate cosmetic change: the results used to swap invisibly at the
    midpoint of the crossfade, and now they swap as it starts. A mode switch
    fades out the new list rather than the old one for about 100ms. Correctness
    is worth more than that, and the alternative -- leaving `delegate` in the
    PropertyAction -- would hand an AppItem a row of actions for that same
    100ms.
    """
    path = os.path.join(launcher_dir, "AppList.qml")
    if not os.path.exists(path):
        fail(f"{path} is gone -- the launcher list moved or was renamed.")

    s = io.open(path, encoding="utf-8").read()

    old_model = (
        "    model: ScriptModel {\n"
        "        id: model\n"
        "\n"
        "        onValuesChanged: root.currentIndex = 0\n"
        "    }\n")
    if old_model not in s:
        fail("AppList.qml's ScriptModel is not where the patch expects it -- "
             "upstream changed how the launcher feeds its list.")

    new_model = (
        "    // Genesi: the results are a binding, not a state change. Carrying\n"
        "    // them in PropertyChanges meant the Transition's PropertyAction\n"
        "    // wrote over the bound property and killed the binding, so the\n"
        "    // list was computed once -- on the keystroke that entered the\n"
        "    // state -- and never followed anything typed after it.\n"
        "    model: ScriptModel {\n"
        "        id: model\n"
        "\n"
        "        values: {\n"
        "            switch (root.state) {\n"
        "            case \"actions\":\n"
        "                return Actions.query(root.search.text);\n"
        "            case \"calc\":\n"
        "                return [0];\n"
        "            case \"scheme\":\n"
        "                return Schemes.query(root.search.text);\n"
        "            case \"variant\":\n"
        "                return M3Variants.query(root.search.text);\n"
        "            default:\n"
        "                return Apps.search(root.search.text);\n"
        "            }\n"
        "        }\n"
        "\n"
        "        onValuesChanged: root.currentIndex = 0\n"
        "    }\n"
        "\n"
        "    // Bound to the same state as the rows above, so the two always\n"
        "    // change in the same turn and a delegate never meets a row of a\n"
        "    // kind it cannot read.\n"
        "    delegate: {\n"
        "        switch (root.state) {\n"
        "        case \"actions\":\n"
        "            return actionItem;\n"
        "        case \"calc\":\n"
        "            return calcItem;\n"
        "        case \"scheme\":\n"
        "            return schemeItem;\n"
        "        case \"variant\":\n"
        "            return variantItem;\n"
        "        default:\n"
        "            return appItem;\n"
        "        }\n"
        "    }\n")
    s = s.replace(old_model, new_model, 1)

    start = s.find("    states: [")
    end = s.find("    transitions: Transition {")
    if start < 0 or end < 0 or end < start:
        fail("AppList.qml's states/transitions block is not where the patch "
             "expects it.")
    new_states = (
        "    // Names only. What each mode SHOWS is bound above; these exist so\n"
        "    // the crossfade below still has two states to move between.\n"
        "    states: [\n"
        "        State {\n"
        "            name: \"apps\"\n"
        "        },\n"
        "        State {\n"
        "            name: \"actions\"\n"
        "        },\n"
        "        State {\n"
        "            name: \"calc\"\n"
        "        },\n"
        "        State {\n"
        "            name: \"scheme\"\n"
        "        },\n"
        "        State {\n"
        "            name: \"variant\"\n"
        "        }\n"
        "    ]\n"
        "\n")
    s = s[:start] + new_states + s[end:]

    clobber = (
        "            PropertyAction {\n"
        "                targets: [model, root]\n"
        "                properties: \"values,delegate\"\n"
        "            }\n")
    if clobber not in s:
        fail("AppList.qml no longer has the PropertyAction that overwrote "
             "values/delegate -- check whether upstream fixed this itself.")
    s = s.replace(clobber, "", 1)

    # Comments stripped first. The explanation written in just above names
    # PropertyChanges, and a guard that reads its own note reports a problem it
    # created -- the same shape as the hyprland.conf marker that matched the
    # line the tool itself wrote.
    code = re.sub(r"//.*", "", s)
    if "PropertyChanges" in code:
        fail("AppList.qml still has a PropertyChanges block -- upstream added "
             "one this patch does not know about.")

    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("AppList.qml: results follow the search text")


def patch_wallpaper_transition(release):
    """
    Let the wallpaper change be an animation you can choose.

    Upstream is not missing a transition -- it crossfades already: a new
    CachingImage is created at opacity 0 and animated to 1 when it loads, and
    the old one is destroyed a duration later. What it is missing is any say in
    the matter. One curve, one length, no movement, nothing to set.

    So this adds two config properties next to the ones that are already there,

        background.transition          "fade" | "zoom" | "grow" | "none"
        background.transitionDuration  ms, 0 = the theme's own slow duration

    and teaches Wallpaper.qml to honour them. "zoom" settles in from slightly
    too large, "grow" opens out from slightly too small, both alongside the
    fade; "fade" is upstream's behaviour exactly, and "none" is instant for
    people who find any of it a distraction.

    Every option is a plain item property -- opacity and scale. No effects
    module, nothing that can be missing at runtime, and `scale` is a transform
    so it does not fight `anchors.fill`. A name nobody recognises falls back to
    the plain fade, which means a typo in shell.json costs the animation and
    never the wallpaper.

    The C++ edit is one macro line per property in the same style as its
    neighbours, and both edits assert their anchor first: a config property
    added without the QML to read it is a setting that silently does nothing,
    which is the failure this repository keeps meeting from the other side.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    qml = os.path.join(release, "modules", "background", "Wallpaper.qml")
    for p in (hpp, qml):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the background module moved or was renamed.")

    # ── the config properties ────────────────────────────────────────────────
    s = io.open(hpp, encoding="utf-8").read()
    if "transition" in s:
        fail("backgroundconfig.hpp already mentions a transition -- upstream "
             "added one. Read theirs and drop this patch.")

    anchor = (
        "    CONFIG_PROPERTY(bool, enabled, true)\n"
        "    CONFIG_PROPERTY(bool, wallpaperEnabled, true)\n")
    if anchor not in s:
        fail("BackgroundConfig's own properties are not where the patch "
             "expects them.")
    s = s.replace(
        anchor,
        anchor +
        "    // Genesi: how the wallpaper arrives. See patch_wallpaper_transition.\n"
        '    CONFIG_PROPERTY(QString, transition, QStringLiteral("fade"))\n'
        "    CONFIG_PROPERTY(int, transitionDuration, 0)\n",
        1)
    io.open(hpp, "w", encoding="utf-8", newline="\n").write(s)

    # ── the animation ────────────────────────────────────────────────────────
    s = io.open(qml, encoding="utf-8").read()
    old = """        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
"""
    if old not in s:
        fail("Wallpaper.qml's crossfade is not where the patch expects it -- "
             "upstream changed how the wallpaper appears.")

    new = """        CachingImage {
            id: img

            anchors.fill: parent

            // Genesi: the transition is chosen rather than fixed. Upstream
            // animates opacity alone; "zoom" and "grow" add the movement half.
            // Both are `scale`, which is a transform and so does not fight
            // anchors.fill, and an unrecognised name falls back to the plain
            // fade -- a typo in shell.json costs the animation, never the
            // wallpaper.
            readonly property string transition: Config.background.transition
            readonly property int dur: Config.background.transitionDuration > 0 ? Config.background.transitionDuration : Tokens.anim.durations.expressiveSlowEffects
            readonly property real fromScale: transition === "zoom" ? 1.06 : transition === "grow" ? 0.94 : 1

            opacity: 0
            transformOrigin: Item.Center

            onStatusChanged: {
                if (status !== Image.Ready)
                    return;
                if (transition === "none") {
                    opacity = 1;
                    return;
                }
                fadeIn.start();
                if (fromScale !== 1)
                    scaleIn.start();
            }

            NumberAnimation {
                id: fadeIn

                target: img
                property: "opacity"
                running: false
                from: 0
                to: 1
                duration: img.dur
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: scaleIn

                target: img
                property: "scale"
                running: false
                from: img.fromScale
                to: 1
                duration: img.dur
                easing.type: Easing.OutCubic
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: img.dur
                onTriggered: img.destroy()
            }
        }
"""
    s = s.replace(old, new, 1)
    io.open(qml, "w", encoding="utf-8", newline="\n").write(s)
    print("Wallpaper.qml: the transition is configurable (fade/zoom/grow/none)")


def patch_bar_proportions(release):
    """
    Let a bar preset change the bar's PROPORTIONS, not just its contents.

    caelestia exposes what the bar contains and almost nothing about how it is
    drawn: the width comes from `Tokens.sizes.bar.innerWidth` and the gap
    between entries from `Tokens.spacing.medium`, both constants. So ten
    presets could only ever differ by which modules were in them and in what
    order -- reported, fairly, as "the customisation is very simple".

    Two properties change that, and they are the two that actually alter the
    silhouette:

        bar.width     px, 0 = the theme's own
        bar.spacing   px, -1 = the theme's own

    Zero and minus one mean "unset" rather than "zero", because a preset that
    does not mention a property must inherit the theme rather than collapse the
    bar to nothing. Both are clamped in the QML: a width of 4px is not a look,
    it is a bar nobody can hit with a pointer.

    This does NOT make the bar horizontal. Bar.qml is a ColumnLayout anchored
    to the screen edge with exclusiveZone = contentWidth, and Clock, Tray,
    StatusIcons and Workspaces each stack vertically inside themselves -- a top
    bar is six upstream files rewritten, not a property.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "barconfig.hpp")
    wrapper = os.path.join(release, "modules", "bar", "BarWrapper.qml")
    bar = os.path.join(release, "modules", "bar", "Bar.qml")
    for p in (hpp, wrapper, bar):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the bar module moved or was renamed.")

    s = io.open(hpp, encoding="utf-8").read()
    if "CONFIG_PROPERTY(int, width" in s:
        fail("barconfig.hpp already declares a width -- upstream added one. "
             "Read theirs and drop this patch.")
    anchor = "    CONFIG_PROPERTY(bool, persistent, true)\n"
    if anchor not in s:
        fail("BarConfig's own properties are not where the patch expects them.")
    s = s.replace(
        anchor,
        anchor +
        "    // Genesi: the bar's proportions. 0 / -1 mean \"use the theme's\".\n"
        "    CONFIG_PROPERTY(int, width, 0)\n"
        "    CONFIG_PROPERTY(int, spacing, -1)\n",
        1)
    io.open(hpp, "w", encoding="utf-8", newline="\n").write(s)

    s = io.open(wrapper, encoding="utf-8").read()
    old = ("    readonly property int contentWidth: Tokens.sizes.bar.innerWidth "
           "+ padding * 2\n")
    if old not in s:
        fail("BarWrapper's contentWidth is not where the patch expects it.")
    new = ('    // Genesi: a preset may set the width. Clamped, because a bar\n'
           '    // narrow enough to be a line is one a pointer cannot hit, and\n'
           '    // one wider than a third of the screen is a panel.\n'
           '    readonly property int innerWidth: Config.bar.width > 0\n'
           '        ? Math.max(24, Math.min(Config.bar.width, screen.width / 3))\n'
           '        : Tokens.sizes.bar.innerWidth\n'
           '    readonly property int contentWidth: innerWidth + padding * 2\n')
    s = s.replace(old, new, 1)
    io.open(wrapper, "w", encoding="utf-8", newline="\n").write(s)

    s = io.open(bar, encoding="utf-8").read()
    old_sp = "    spacing: Tokens.spacing.medium\n"
    if old_sp not in s:
        fail("Bar.qml's spacing is not where the patch expects it.")
    s = s.replace(
        old_sp,
        "    // Genesi: a preset may set the gap between entries. -1 inherits.\n"
        "    spacing: Config.bar.spacing >= 0 ? Math.min(Config.bar.spacing, 40)\n"
        "                                     : Tokens.spacing.medium\n",
        1)
    io.open(bar, "w", encoding="utf-8", newline="\n").write(s)
    print("bar: width and spacing are configurable")


def patch_frame_opacity(release):
    """
    Let the desktop frame -- and with it the bar -- be see-through.

    This was asked for as "bar opacity", and looking for it is what settled
    what it actually is: caelestia's rail has NO background of its own. One
    Item in ContentWindow.qml carries `opacity: surfaceColour.a` and wraps the
    BlobGroup that paints the frame around the desktop AND the ground the bar
    sits on. They are one surface.

    So this is `border.opacity`, on the Appearance page beside the frame's
    thickness and rounding, rather than a bar setting that quietly also fades
    the frame. Naming a control for what it really does is the difference
    between a feature and a surprise.

        border.opacity   0-100, 100 = solid (upstream)

    An integer rather than a fraction: it is a percentage on a slider, and
    0.85 in a config file is a number people mistype as 85.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "borderconfig.hpp")
    win = os.path.join(release, "modules", "drawers", "ContentWindow.qml")
    for p in (hpp, win):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the drawer surface moved or was renamed.")

    src = {p: io.open(p, encoding="utf-8").read() for p in (hpp, win)}

    if "opacity" in src[hpp]:
        fail("borderconfig.hpp already has an opacity -- upstream added one, "
             "or this ran twice. Read theirs and drop this patch.")

    anchor = "    CONFIG_PROPERTY(int, smoothing, 20)\n"
    if anchor not in src[hpp]:
        fail("BorderConfig's properties are not where the patch expects them.")
    out = {hpp: src[hpp].replace(anchor, anchor + (
        "    // Genesi: how see-through the frame -- and the bar riding on it --\n"
        "    // is. 0-100; 100 is upstream's solid surface.\n"
        "    CONFIG_PROPERTY(int, opacity, 100)\n"), 1)}

    s = src[win]
    old = "        opacity: root.surfaceColour.a\n"
    if s.count(old) != 1:
        fail("ContentWindow.qml's surface opacity is not where the patch "
             f"expects it (found {s.count(old)}).")
    s = s.replace(old, (
        "        // Genesi: the scheme's own alpha, scaled by border.opacity.\n"
        "        // Clamped so a config holding 0 does not make the whole shell\n"
        "        // invisible with no way to reach the settings that did it.\n"
        "        opacity: root.surfaceColour.a\n"
        "                 * Math.max(0.15, Math.min(1,\n"
        "                     root.contentItem.Config.border.opacity / 100))\n"), 1)
    out[win] = s

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("frame: opacity is configurable")


def patch_launcher_position(release):
    """
    Let the launcher sit in the middle of the screen, and set its width.

        launcher.position   "bottom" (upstream) or "centre"
        launcher.width      px, 0 = whatever the content wants

    ── Two files, because the first attempt only did one ────────────────────

    The first version moved the panel and nothing else, and left a slab at the
    BOTTOM of the screen. The cause was a single override in Regions.qml:

        R { panel: root.panels.launcher
            y: root.win.height - height }

    `component R` already derives x and y from `panel.x` / `panel.y`. The
    launcher is the only one of the seven regions that overrides `y`, because
    upstream knew where it was. That region is the drawer window's input mask,
    so the leftover was a strip at the bottom that swallowed clicks while the
    real launcher sat outside the mask. Deleting the override makes it follow
    the panel, which is what the component was written to do.

    The VISIBLE half needed nothing: the launcher's PanelBg blob takes
    `panel: panels.launcher` with no position of its own, and follows it
    already.

    Interactions.qml is deliberately untouched. Its `inBottomPanel` is the
    drag-up-from-the-edge gesture, and swiping up from the bottom to raise a
    panel in the middle is still the right gesture -- moving it would take the
    gesture away from the edge people already use.

    ── The position is a MARGIN, not a second anchor ────────────────────────

    Flipping `anchors.bottom` between `parent.bottom` and `undefined` is the
    documented way to do this and also exactly how a QML item ends up anchored
    to nothing and invisible. This is somebody's launcher, on a desktop where
    the launcher is how you open a terminal to fix it, so it stays one anchor
    that never changes plus an offset that moves it up the screen. The open
    animation survives because Wrapper.qml slides by driving that same margin.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "launcherconfig.hpp")
    wrapper = os.path.join(release, "modules", "launcher", "Wrapper.qml")
    regions = os.path.join(release, "modules", "drawers", "Regions.qml")
    for p in (hpp, wrapper, regions):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the launcher moved or was renamed.")

    src = {p: io.open(p, encoding="utf-8").read()
           for p in (hpp, wrapper, regions)}

    if "CONFIG_PROPERTY(int, width" in src[hpp]:
        fail("launcherconfig.hpp already has a width -- upstream added one, "
             "or this ran twice. Read theirs and drop this patch.")

    anchor = "    CONFIG_PROPERTY(int, maxShown, 7)\n"
    if anchor not in src[hpp]:
        fail("LauncherConfig's properties are not where the patch expects them.")
    out = {hpp: src[hpp].replace(anchor, anchor + (
        "    // Genesi: where the launcher sits, and how wide it is.\n"
        "    // \"bottom\" is upstream's; \"centre\" floats it mid-screen.\n"
        "    CONFIG_PROPERTY(QString, position, u\"bottom\"_s)\n"
        "    CONFIG_PROPERTY(int, width, 0)\n"), 1)}

    # The input mask has to follow the panel, or a centred launcher leaves a
    # click-swallowing strip at the bottom and sits outside its own mask.
    s = src[regions]
    old_r = ("    R {\n"
             "        panel: root.panels.launcher\n"
             "        y: root.win.height - height\n"
             "        height: panel.height * (1 - root.panels.launcher.offsetScale)"
             " + root.borderThickness\n"
             "    }\n")
    if old_r not in s:
        fail("the launcher's region in Regions.qml is not what the patch "
             "expects -- it is the piece that has to follow the panel.")
    # TWO regions, because upstream's one was doing two jobs: the panel's
    # input area when open, and the strip at the bottom edge that notices the
    # drag or hover that opens it when closed. Following the panel fixes the
    # first and silently removes the second -- with the panel off screen there
    # would be nothing at the edge left to open it with.
    new_r = ("    R {\n"
             "        // The panel itself, wherever it is. `component R` already\n"
             "        // takes x and y from the panel; upstream pinned this one\n"
             "        // to the bottom because that is where it knew it was.\n"
             "        panel: root.panels.launcher\n"
             "        height: panel.height * (1 - root.panels.launcher.offsetScale)"
             " + root.borderThickness\n"
             "    }\n"
             "\n"
             "    R {\n"
             "        // The gesture strip, which stays at the screen edge even\n"
             "        // when the panel is in the middle. This is what a drag up\n"
             "        // or a hover at the bottom lands on.\n"
             "        panel: root.panels.launcher\n"
             "        y: root.win.height - height\n"
             "        height: root.borderThickness\n"
             "    }\n")
    out[regions] = s.replace(old_r, new_r, 1)

    s = src[wrapper]
    old_slide = "    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale\n"
    if old_slide not in s:
        fail("Wrapper.qml's slide is not where the patch expects it.")
    s = s.replace(old_slide, (
        '    // Genesi: how far up the screen the launcher rests. ADDED to the\n'
        '    // slide rather than replacing an anchor, so there is no state in\n'
        '    // which this item is anchored to nothing.\n'
        '    readonly property real restingOffset: {\n'
        '        if (Config.launcher.position !== "centre")\n'
        '            return 0;\n'
        '        const h = parent ? parent.height : 0;\n'
        '        return Math.max(0, (h - implicitHeight) / 2);\n'
        '    }\n'
        '\n'
        '    // The offset applies at the OPEN end only. Added to both,\n'
        '    // the closed position stops restingOffset short of the\n'
        '    // screen edge and leaves a band of the panel showing --\n'
        '    // half the leftover screen, for a centred launcher.\n'
        '    anchors.bottomMargin: restingOffset\n'
        '        - (restingOffset + implicitHeight + 5) * offsetScale\n'), 1)

    # The slide has to reach the screen edge. This is arithmetic, and it is the
    # bug that shipped: adding the resting offset to BOTH ends left the panel
    # `restingOffset` pixels short of gone, which for a centred launcher is
    # half the leftover screen still showing. Evaluated here rather than
    # trusted, because the expression is one sign away from wrong and nothing
    # downstream can tell.
    m = re.search(r"anchors\.bottomMargin:\s*(.+?)\n\s*implicitHeight:", s, re.S)
    if not m:
        fail("cannot find the slide expression to check it reaches the edge.")
    expr = " ".join(m.group(1).split())
    for resting in (0.0, 230.0):
        env = {"restingOffset": resting, "implicitHeight": 600.0}
        opened = eval(expr, {"__builtins__": {}}, dict(env, offsetScale=0.0))
        closed = eval(expr, {"__builtins__": {}}, dict(env, offsetScale=1.0))
        if abs(opened - resting) > 0.001:
            fail(f"the launcher does not rest where it should: open margin "
                 f"{opened} with a resting offset of {resting}.")
        if abs(closed - (-605.0)) > 0.001:
            fail(f"the launcher does not close off the screen: closed margin "
                 f"{closed}, upstream's is -605. With a resting offset of "
                 f"{resting} that leaves {605.0 + closed:.0f}px of it showing.")

    old_w = ("    implicitWidth: content.implicitWidth || 630 "
             "// Hard coded fallback for first open\n")
    if old_w not in s:
        fail("Wrapper.qml's width is not where the patch expects it.")
    new_w = (
        '    // Genesi: a preset width, clamped. 630 is upstream\'s fallback for\n'
        '    // the first open, before the content has measured itself.\n'
        '    implicitWidth: Config.launcher.width > 0\n'
        '        ? Math.max(320, Math.min(Config.launcher.width,\n'
        '                                 screen.width - 80))\n'
        '        : (content.implicitWidth || 630)\n')
    s = s.replace(old_w, new_w, 1)
    out[wrapper] = s

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("launcher: position and width are configurable")


def patch_window_icons(release):
    """
    Draw the real application icon for each open window, when a preset asks.

    caelestia already puts a mark per open window inside its workspace, but
    the mark is `Icons.getAppCategoryIcon(class, "terminal")` -- a Material
    Symbols glyph for the app's CATEGORY. Every browser is the same globe and
    every editor the same page, so a workspace holding Firefox, Chromium and a
    terminal shows two identical circles and a third. That is not what "the
    bar shows the icons of the open apps" means to anyone looking at one.

    The machinery for the real thing is already in the tree and already used
    one module over: `Icons.getAppIcon` resolves a window class through
    DesktopEntries, and the active-window popout draws the result. This puts
    the same lookup in the bar, behind a property, because it is a real trade:
    the glyphs are one colour and follow the scheme, while real icons are
    full-colour and will not.

        bar.workspaces.realWindowIcons   false = the category glyph

    Three things are patched, and skipping any one of them ships something
    worse than not doing it at all:

      * Icons.qml gains a lookup that CHECKS the icon exists. getAppIcon does
        not: handed a class no desktop entry matches, it returns a path to
        nothing, and the bar would draw a column of broken-image icons instead
        of falling back.
      * both files that draw window marks. Patching only Workspace.qml gives a
        bar whose ordinary workspaces show app icons and whose special
        workspaces show glyphs -- which reads as a bug, not a look.
      * the glyph stays loaded and keeps sizing the row, so a workspace does
        not change height depending on how many of its windows were found in
        the desktop database.
    """
    icons = os.path.join(release, "utils", "Icons.qml")
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "barconfig.hpp")
    marks = [
        os.path.join(release, "modules", "bar", "components", "workspaces",
                     "Workspace.qml"),
        os.path.join(release, "modules", "bar", "components", "workspaces",
                     "SpecialWorkspaces.qml"),
    ]
    for p in [icons, hpp] + marks:
        if not os.path.exists(p):
            fail(f"{p} is gone -- the bar's workspaces moved or were renamed.")

    # Everything is checked before anything is written. A patch that writes as
    # it goes and refuses halfway leaves the tree half-patched, and the second
    # run then refuses on the half it already did -- which is how a rerun of
    # this function ended up with the lookup declared twice in Icons.qml.
    src = {p: io.open(p, encoding="utf-8").read() for p in [icons, hpp] + marks}

    if "realWindowIcons" in src[hpp]:
        fail("barconfig.hpp already knows realWindowIcons -- upstream added "
             "one, or this ran twice. Read theirs and drop this patch.")

    # ── the lookup ───────────────────────────────────────────────────────────
    s = src[icons]
    anchor = '    function getAppCategoryIcon(name: string, fallback: string): string {\n'
    if anchor not in s:
        fail("Icons.qml no longer has getAppCategoryIcon where the patch "
             "expects it.")
    s = s.replace(anchor, (
        '    // Genesi: the real icon for a window class, or "" when there is\n'
        '    // none. iconPath(name, true) CHECKS that the icon resolves --\n'
        '    // getAppIcon does not, and a path to a missing icon draws as the\n'
        '    // broken-image glyph rather than falling back to the category one.\n'
        '    function getRealAppIcon(name: string): string {\n'
        '        const icon = DesktopEntries.heuristicLookup(name)?.icon;\n'
        '        return icon ? Quickshell.iconPath(icon, true) : "";\n'
        '    }\n'
        '\n'
    ) + anchor, 1)
    out = {icons: s}

    # ── the property ─────────────────────────────────────────────────────────
    s = src[hpp]
    ws_anchor = "    CONFIG_PROPERTY(int, maxWindowIcons, 5)\n"
    if ws_anchor not in s:
        fail("BarWorkspaces' window-icon properties are not where the patch "
             "expects them.")
    s = s.replace(ws_anchor, ws_anchor + (
        "    // Genesi: draw each open window as its own app icon instead of a\n"
        "    // glyph for its category. Off by default: the glyphs recolour\n"
        "    // with the scheme and real icons do not.\n"
        "    CONFIG_PROPERTY(bool, realWindowIcons, false)\n"
    ), 1)
    out[hpp] = s

    # ── the marks ────────────────────────────────────────────────────────────
    for path in marks:
        s = src[path]

        m = re.search(r"^([ \t]+)MaterialIcon \{\n"
                      r"[ \t]+required property var modelData\n"
                      r"\n"
                      r"[ \t]+grade: 0\n"
                      r"[ \t]+text: Icons\.getAppCategoryIcon\(modelData\."
                      r"lastIpcObject\.class, \"terminal\"\)\n"
                      r"[ \t]+color: Colours\.palette\.m3onSurfaceVariant\n"
                      r"[ \t]+\}\n", s, re.M)
        if not m:
            fail(f"{os.path.basename(path)} no longer draws its window marks "
                 "the way the patch expects.")
        i = m.group(1)
        if "import Quickshell\n" not in s:
            fail(f"{os.path.basename(path)} does not import Quickshell.")

        new = (
            f'{i}// Genesi: the real app icon when the preset asks for it, the\n'
            f'{i}// category glyph otherwise. The glyph stays loaded either way\n'
            f'{i}// -- it is what gives the column its height, so a workspace\n'
            f'{i}// does not resize depending on which of its windows resolved.\n'
            f'{i}Item {{\n'
            f'{i}    id: winMark\n'
            f'{i}\n'
            f'{i}    required property var modelData\n'
            f'{i}\n'
            f'{i}    implicitWidth: glyph.implicitWidth\n'
            f'{i}    implicitHeight: glyph.implicitHeight\n'
            f'{i}\n'
            f'{i}    MaterialIcon {{\n'
            f'{i}        id: glyph\n'
            f'{i}\n'
            f'{i}        anchors.centerIn: parent\n'
            f'{i}        grade: 0\n'
            f'{i}        opacity: appIcon.visible ? 0 : 1\n'
            f'{i}        text: Icons.getAppCategoryIcon(winMark.modelData.'
            f'lastIpcObject.class, "terminal")\n'
            f'{i}        color: Colours.palette.m3onSurfaceVariant\n'
            f'{i}    }}\n'
            f'{i}\n'
            f'{i}    IconImage {{\n'
            f'{i}        id: appIcon\n'
            f'{i}\n'
            f'{i}        anchors.centerIn: parent\n'
            f'{i}        asynchronous: true\n'
            f'{i}        implicitSize: glyph.implicitHeight\n'
            f'{i}        source: root.Config.bar.workspaces.realWindowIcons '
            f'? Icons.getRealAppIcon(winMark.modelData.lastIpcObject.class) '
            f': ""\n'
            f'{i}        visible: source != ""\n'
            f'{i}    }}\n'
            f'{i}}}\n'
        )
        # The splice FIRST: m's offsets are into the string as it was searched,
        # and adding the import above would shift everything after it by the
        # length of that line -- which is exactly how an earlier version of
        # this cut the replacement into the middle of the line above.
        # A blank line built as indent + newline is a line of trailing spaces.
        # Harmless to Qt, but this is generated code that ships in a package.
        new = "".join(l.rstrip() + "\n" for l in new.splitlines())

        s = s[:m.start()] + new + s[m.end():]

        # IconImage lives in Quickshell.Widgets, which neither file imports.
        if "import Quickshell.Widgets\n" not in s:
            s = s.replace("import Quickshell\n",
                          "import Quickshell\nimport Quickshell.Widgets\n", 1)
        out[path] = s

    for path, s in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("bar: open windows can be drawn as real app icons")


def patch_ddc_timeout(services_dir):
    """
    Bound the DDC/CI probe so it cannot hammer a monitor that never answers.

    Reported from hardware: a DisplayPort screen that flickers and then blanks
    until the cable is replugged. The journal says why, at length:

        ddcutil[1625]: busno=1 ... DDCRC_RETRIES ... DDCRC_DDC_DATA(10)
        ddcutil[1625]: Turning off dynamic sleep and retrying
        ...

    One ddcutil process logged from 13:07:43 to 15:30:44 -- two and a half
    hours of I2C traffic on a monitor that does not implement DDC/CI. Sustained
    I2C on a DisplayPort link is a known way to upset the link, and NVIDIA is
    where it shows up most. The flickering is not the cable; it is us.

    caelestia runs `ddcutil detect --brief` unconditionally at startup to find
    external monitors it can set brightness on. On hardware that answers, that
    takes a second or two. On hardware that does not, ddcutil escalates its
    sleep multiplier and retries essentially forever.

    So the probe gets a wall clock. Ten seconds is generous for a monitor that
    works and decisive for one that does not: a display that has not identified
    itself in ten seconds is not going to, and the only thing further retries
    buy is the flicker.

    A monitor that genuinely supports DDC/CI is unaffected -- detect finishes
    long before the limit, and every getvcp/setvcp after it is per-monitor and
    only runs for displays detect actually found.
    """
    brightness = os.path.join(services_dir, "Brightness.qml")
    if not os.path.exists(brightness):
        fail(f"{brightness} is gone -- the brightness service moved or was renamed.")

    s = io.open(brightness, encoding="utf-8").read()
    old = 'command: ["ddcutil", "detect", "--brief"]'
    if old not in s:
        if '"timeout"' in s and "ddcutil" in s:
            fail("Brightness.qml already bounds the ddcutil probe -- upstream "
                 "fixed this. Drop the patch and keep theirs.")
        fail("Brightness.qml's `ddcutil detect` command is not where the patch "
             "expects it; refusing to guess.")

    new = ('// Wall-clocked (Genesi). On a monitor without DDC/CI, ddcutil\n'
           '        // escalates its sleep multiplier and retries for hours --\n'
           '        // one process was measured logging I2C failures for 2h22m --\n'
           '        // and sustained I2C traffic is what makes a DisplayPort link\n'
           '        // flicker and drop. A display that has not answered in ten\n'
           '        // seconds is not going to.\n'
           '        command: ["timeout", "10", "ddcutil", "detect", "--brief"]')
    s = s.replace(old, new, 1)
    io.open(brightness, "w", encoding="utf-8", newline="\n").write(s)
    print("Brightness.qml: ddcutil detect is wall-clocked")


# The two files Genesi adds to the launcher. Copied in like the Nexus pages --
# after every "does upstream already ship this?" test has run, never before.
LAUNCHER_FILES = ("GenesiContent.qml", "GenesiAppGrid.qml",
                   "GenesiSchemeFlow.qml", "GenesiSchemeState.qml",
                   "GenesiTopBarState.qml", "GenesiEdges.qml",
                   "GenesiSidePanelState.qml")

# The full-screen colour-scheme picker. Its WINDOW goes in modules/background,
# which is the one Genesi directory shell.qml already imports -- so putting it
# there costs no new import line up there. Its state singleton goes beside the
# fan in modules/launcher, where the launcher body and the window both see it.
SCHEME_FILES = ("GenesiSchemeScreen.qml",)

# The top bar and its own settings panel. Both are WINDOWS inside caelestia,
# which is the whole point of this second attempt: the first one was a separate
# Quickshell process, and switching to it ran `pkill -f caelestia`.
TOPBAR_FILES = ("GenesiTopBar.qml", "GenesiStudio.qml", "GenesiMark.qml")

# The quick settings down the left edge, and the thin strip that opens
# them on hover. Both windows are in one file because they are one
# feature: a hover point with nothing behind it is not a thing.
SIDEPANEL_FILES = ("GenesiSidePanel.qml",)

# The wallpaper's subject, drawn over the clock and the widgets. The
# cutting is done by genesi-depth, a CLI in this same package; this file
# is the layer that draws what it produced.
DEPTH_FILES = ("GenesiDepth.qml",)


def patch_launcher_layout(release):
    """
    A second body for the launcher panel, chosen by `launcher.layout`.

        launcher.layout        "caelestia" (upstream) or "genesi"
        launcher.background    "" | "wallpaper" | an absolute path
        launcher.backgroundExtent
                               "header" puts that picture behind the prompt
                               only, which is where it belongs; "panel" puts
                               it behind the results as well
        launcher.backgroundDim 0-100, how much of the panel's own surface
                               colour is laid over that picture
        launcher.showClock     the time, top left
        launcher.showWeather   the conditions and the date, top right
        launcher.showHero      the card naming what Enter will open
        launcher.showChips     the row of mode buttons
        launcher.columns       1-3 columns of results

    ── Why a whole file and not a patch ─────────────────────────────────────

    The Genesi layout is not a variation on upstream's Content.qml, it is a
    different shape: a wide slab carrying the wallpaper, the clock and the
    weather in its corners, the selection in a card of its own, and the results
    in numbered columns. Expressed as a patch that would be a diff touching
    nearly every line of a file we do not own -- fragile against any upstream
    edit, and the failure mode of a fuzzy match here is a launcher that loads
    and is subtly wrong rather than a build that stops.

    So upstream's Content.qml is not touched at all. Genesi ships two files of
    its own next to it, and the ONLY edit to upstream is the line in Wrapper.qml
    that decides which of the two the Loader builds. That line is asserted here,
    and it is small enough to re-read by eye on a version bump.

    ── The Components are siblings of the Loader, not children of it ────────

    `sourceComponent: cond ? a : b` needs `a` and `b` to be Components with ids,
    and the obvious place to put them is inside the Loader. They go outside it
    instead. A Loader's children are its `data`, which is not where a loaded
    item lives, and mixing declared children with a loaded item inside one
    Loader is the sort of thing that works until a Qt release decides otherwise.
    As siblings they are ordinary objects in the same scope, which is all the
    ids need.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "launcherconfig.hpp")
    wrapper = os.path.join(release, "modules", "launcher", "Wrapper.qml")
    for p in (hpp, wrapper):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the launcher moved or was renamed.")

    for name in LAUNCHER_FILES:
        shipped = os.path.join(release, "modules", "launcher", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Ours would silently "
                 "replace it. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read() for p in (hpp, wrapper)}

    if "CONFIG_PROPERTY(QString, layout" in src[hpp]:
        fail("launcherconfig.hpp already has a layout -- upstream added one, "
             "or this ran twice.")

    # Anchored on the width property patch_launcher_position adds, which is why
    # that one has to have run first: if it has not, this fails here rather than
    # writing a config the shell would read and half understand.
    anchor = '    CONFIG_PROPERTY(int, width, 0)\n'
    if anchor not in src[hpp]:
        fail("launcherconfig.hpp has no Genesi width property -- "
             "patch_launcher_position did not run, or its anchor moved.")
    out = {hpp: src[hpp].replace(anchor, anchor + (
        '    // Genesi: the second body for this panel, and what it shows.\n'
        '    // "caelestia" is upstream\'s; "genesi" is the wide slab.\n'
        '    CONFIG_PROPERTY(QString, layout, u"caelestia"_s)\n'
        '    CONFIG_PROPERTY(QString, background, u""_s)\n'
        '    CONFIG_PROPERTY(QString, backgroundExtent, u"header"_s)\n'
        '    CONFIG_PROPERTY(int, backgroundDim, 78)\n'
        '    CONFIG_PROPERTY(bool, showClock, true)\n'
        '    CONFIG_PROPERTY(bool, showWeather, true)\n'
        '    CONFIG_PROPERTY(bool, showHero, true)\n'
        '    CONFIG_PROPERTY(bool, showChips, true)\n'
        '    CONFIG_PROPERTY(int, columns, 2)\n'
        '    // Genesi: where the colour schemes are shown. "launcher" fans\n'
        '    // them out inside this panel; "fullscreen" hands them to a\n'
        '    // layer-shell surface of their own covering the screen.\n'
        '    CONFIG_PROPERTY(QString, schemePicker, u"launcher"_s)\n'), 1)}

    old_loader = (
        '        sourceComponent: Content {\n'
        '            visibilities: root.visibilities\n'
        '            panels: root.panels\n'
        '            maxHeight: root.maxHeight\n'
        '        }\n'
        '    }\n')
    if old_loader not in src[wrapper]:
        fail("Wrapper.qml's Loader is not what the patch expects -- it is the "
             "one line that chooses which body the launcher builds.")
    new_loader = (
        '        // Genesi: two bodies for one panel.\n'
        '        sourceComponent: Config.launcher.layout === "genesi"\n'
        '            ? genesiBody\n'
        '            : caelestiaBody\n'
        '    }\n'
        '\n'
        '    Component {\n'
        '        id: caelestiaBody\n'
        '\n'
        '        Content {\n'
        '            visibilities: root.visibilities\n'
        '            panels: root.panels\n'
        '            maxHeight: root.maxHeight\n'
        '        }\n'
        '    }\n'
        '\n'
        '    Component {\n'
        '        id: genesiBody\n'
        '\n'
        '        GenesiContent {\n'
        '            visibilities: root.visibilities\n'
        '            panels: root.panels\n'
        '            maxHeight: root.maxHeight\n'
        '            // The screen, not the parent: the parent is the Loader\n'
        '            // that sizes itself from this item.\n'
        '            maxWidth: root.screen.width\n'
        '        }\n'
        '    }\n')
    out[wrapper] = src[wrapper].replace(old_loader, new_loader, 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("launcher: the Genesi layout is selectable")


# The desktop widgets Genesi adds. The name is the config key, the QML file and
# the id the host switches on -- one list, so adding a widget cannot half-happen.
WIDGETS = ["weather", "forecast", "media", "cpu", "memory", "storage",
           "network", "battery", "calendar", "analogClock", "workspaces",
           "notifications", "uptime", "greeting"]

WIDGET_FILES = tuple(
    "GenesiWidget" + n[0].upper() + n[1:] + ".qml" for n in WIDGETS
) + ("GenesiWidgets.qml", "GenesiWidgetCard.qml", "GenesiWidgetHost.qml",
     "GenesiDesktopMenu.qml")


def patch_desktop_widgets(release):
    """
    Fourteen more things that can be drawn on the wallpaper.

        background.widgets.<name>.enabled   off by default, every one of them
        background.widgets.<name>.position  one of nine anchors, "" = the
                                            widget's own sensible corner
        background.widgets.<name>.scale     0.5 - 2.0
        background.widgets.cards            draw a card behind them, or not

    caelestia ships two -- a clock and an audio visualiser -- and both are good.
    This is the rest of what a desktop is usually asked to show: the weather and
    its forecast, what is playing, CPU, memory, storage, network, battery, a
    calendar, an analogue clock, the workspaces, recent notifications, uptime,
    and a greeting.

    ── Why fourteen subobjects and not one list ─────────────────────────────

    A QVariantList would be one property instead of fourteen. It would also
    REPLACE wholesale rather than merge -- which is what `launcher.actions`
    does, and what forces Genesi to carry every one of upstream's defaults in
    shell.json forever, silently losing any they add. Fourteen subobjects merge
    per key: a user who turns the weather on has a config saying exactly that,
    and everything else keeps following our default even when we change it.

    ── One class, and the default position lives in QML ─────────────────────

    Every widget asks the same three questions -- on, where, how big -- so they
    share ONE config class. The first draft gave each one a subclass so it could
    carry its own default corner, which does not compile: CONFIG_PROPERTY puts
    the member behind `private:`, so a subclass cannot set m_position. So the
    default is the empty string, meaning "the corner this widget prefers", and
    the host supplies that. It is the better shape anyway -- the preferred
    corner is a layout decision and it now lives with the layout.

    ── Placement is an anchor, not a coordinate ─────────────────────────────

    Nine named positions, the same vocabulary upstream's desktopClock uses. Free
    coordinates would need a drag surface to be usable, and a widget dragged
    half off the screen is invisible with no way back except editing JSON.
    Widgets sharing an anchor stack in a column instead of piling on top of each
    other, which is the failure that makes nine anchors feel like two.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    background = os.path.join(release, "modules", "background", "Background.qml")
    for p in (hpp, background):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the desktop background moved or was renamed.")

    for name in WIDGET_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Ours would silently "
                 "replace it. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read() for p in (hpp, background)}

    if "GenesiWidgetConfig" in src[hpp]:
        fail("backgroundconfig.hpp already has the Genesi widgets -- this ran "
             "twice, or upstream took the name.")

    anchor = "class BackgroundConfig : public ConfigObject {"
    if anchor not in src[hpp]:
        fail("BackgroundConfig is not where the patch expects it.")

    block = (
        "// Genesi: one desktop widget. On, where, and how big -- the same three\n"
        "// questions for all fourteen, so they share one class.\n"
        "//\n"
        "// `position` defaults to the EMPTY STRING rather than to a corner:\n"
        "// empty means \"wherever this widget prefers\", and the host knows that.\n"
        "// A shared default corner would pile every widget somebody turns on\n"
        "// into the same one, and a per-widget default would need a subclass\n"
        "// per widget -- which cannot work, because CONFIG_PROPERTY puts the\n"
        "// member behind private:.\n"
        "class GenesiWidgetConfig : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    CONFIG_PROPERTY(bool, enabled, false)\n"
        "    CONFIG_PROPERTY(QString, position, QStringLiteral(\"\"))\n"
        "    CONFIG_PROPERTY(qreal, scale, 1.0)\n"
        "    // Where a DRAGGED widget landed, as a fraction of the screen.\n"
        "    // Fractions and not pixels, because the config outlives the\n"
        "    // monitor: a widget dropped at x=1700 on a 1920 screen is off\n"
        "    // the edge of a 1366 one. Only read when position is \"free\".\n"
        "    CONFIG_PROPERTY(qreal, x, 0.05)\n"
        "    CONFIG_PROPERTY(qreal, y, 0.05)\n"
        "\n"
        "public:\n"
        "    explicit GenesiWidgetConfig(QObject* parent = nullptr)\n"
        "        : ConfigObject(parent) {}\n"
        "};\n"
        "\n"
        "class GenesiWidgets : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    // A card behind each widget. Off, they float on the wallpaper the\n"
        "    // way the clock does; on, they stay readable on a busy picture,\n"
        "    // which is most pictures.\n"
        "    CONFIG_PROPERTY(bool, cards, true)\n")
    # Written out rather than looped, so each declaration EXISTS as text in
    # this file. ci/center-wiring-test.py greps here to prove the shell declares
    # every setting the Center writes, and a line built at run time is a line
    # that guard cannot see -- a guard that cannot see the thing it checks is
    # theatre. The loop is kept below to assert the two lists agree.
    block += (
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, weather)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, forecast)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, media)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, cpu)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, memory)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, storage)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, network)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, battery)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, calendar)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, analogClock)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, workspaces)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, notifications)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, uptime)\n"
        "    CONFIG_SUBOBJECT(GenesiWidgetConfig, greeting)\n")
    for name in WIDGETS:
        if "CONFIG_SUBOBJECT(GenesiWidgetConfig, %s)" % name not in block:
            fail(f"WIDGETS lists {name!r} but the declaration block above does "
                 "not carry it. The list and the block are written separately "
                 "so the guard can read the block; they have drifted.")
    block += ("\npublic:\n"
              "    explicit GenesiWidgets(QObject* parent = nullptr)\n"
              "        : ConfigObject(parent)\n")
    block += "".join("        , m_%s(new GenesiWidgetConfig(this))\n" % n
                     for n in WIDGETS)
    block += "    {}\n};\n\n"

    out = {hpp: src[hpp].replace(anchor, block + anchor, 1)}

    member = "    CONFIG_SUBOBJECT(BackgroundVisualiser, visualiser)\n"
    if member not in out[hpp]:
        fail("BackgroundConfig's members are not where the patch expects them.")
    out[hpp] = out[hpp].replace(
        member, member + "    CONFIG_SUBOBJECT(GenesiWidgets, widgets)\n", 1)

    init = "        , m_visualiser(new BackgroundVisualiser(this)) {}\n"
    if init not in out[hpp]:
        fail("BackgroundConfig's constructor is not what the patch expects.")
    out[hpp] = out[hpp].replace(
        init,
        "        , m_visualiser(new BackgroundVisualiser(this))\n"
        "        , m_widgets(new GenesiWidgets(this)) {}\n", 1)

    # The host goes in beside the visualiser, inside the same window, so it
    # inherits the layer, the screen and the exclusion rules decided there.
    s = src[background]
    old = ("            Visualiser {\n"
           "                anchors.fill: parent\n"
           "                screen: win.modelData\n"
           "                wallpaper: wallpaper\n"
           "            }\n")
    if old not in s:
        fail("Background.qml's Visualiser is not where the patch expects it -- "
             "it is what the widget layer is inserted beside.")
    new = (old +
           "\n"
           "            // Genesi: everything else drawn on the wallpaper.\n"
           "            GenesiWidgets {\n"
           "                anchors.fill: parent\n"
           "            }\n")
    out[background] = s.replace(old, new, 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("background: %d Genesi desktop widgets" % len(WIDGETS))



DOCK_FILES = ("GenesiDock.qml",)


HEADER_DEPS = [
    # what the header USES            what it must SAY to be allowed to
    (r'u"[^"]*"_s', 'using Qt::StringLiterals::operator""_s;'),
    (r"\bQStringList\b", "#include <qstringlist.h>"),
    (r"\bQVariantList\b|\bQVariantMap\b", "#include <qvariant.h>"),
]


def ensure_header_deps(text):
    """
    Give a header what the properties just written into it need to compile.

    The counterpart of verify_string_literals: that one is the post-condition,
    this is the fix. Both read one table, so a new kind of default is described
    in a single place rather than in a check and, separately, in whichever
    patch happened to add it first.

    Placed the way upstream places them -- the using-declaration immediately
    after the namespace opens, the includes beside <qstring.h> -- so a patched
    header still reads like the seven upstream ones that already do this.
    """
    for pattern, required in HEADER_DEPS:
        if not re.search(pattern, text) or required in text:
            continue
        if required.startswith("#include"):
            anchor = "#include <qstring.h>\n"
            if anchor not in text:
                fail("a header needs %s and does not include <qstring.h>, so "
                     "there is nowhere obvious to put it." % required)
            text = text.replace(anchor, anchor + required + "\n", 1)
        else:
            anchor = "namespace caelestia::config {\n"
            if anchor not in text:
                fail("a header needs %s and does not open the config "
                     "namespace where this expects it." % required)
            text = text.replace(anchor, anchor + "\n" + required + "\n", 1)
    return text


def verify_string_literals(path, text):
    """
    A header can compile what this patcher just wrote into it.

    C++ headers only see what they include, and a config header includes the
    bare minimum for what WAS in it. Every time a patch puts a new kind of
    default into one, it can land in a file with no declaration for that kind
    -- and the failure is always the same shape: every precondition in this
    file passes, the build compiles Calamares and most of Qt, and then dies at
    the far end on something one line long.

    That has happened twice on the same header now.

      * `u"top"_s` is a user-defined literal whose operator is not in scope by
        default. Seven of upstream's config headers open with
        `using Qt::StringLiterals::operator""_s;`; backgroundconfig.hpp does
        not, because the dock's config is all bools and ints. The top bar's
        `position` was the first QString default in it, and the build died on
        `unable to find string literal operator` fifteen minutes in.

      * `QStringList` needs <qstringlist.h>. Same header, same reason, the
        very next property.

    So it is a table rather than a special case: what a header USES, and what
    it must SAY to be allowed to use it. Checked per file, because both of
    these are per-file facts and a patch that writes two headers can easily get
    one of them right.
    """
    name = os.path.basename(path)
    for pattern, required in HEADER_DEPS:
        if not re.search(pattern, text):
            continue
        if required in text:
            continue
        fail(f"{name} now uses {pattern!r} and does not carry `{required}`. "
             "That is not a warning -- it is a compile error, and it surfaces "
             "at the END of a twenty-minute build. ensure_header_deps() adds "
             "it; whichever patch wrote this property did not call it.")


def verify_config_reachable(cfg_text, att_text, attc_text):
    """
    Every config section reaches QML, or the build stops here instead of there.

    Two post-conditions, for two different silences.

    The first is a compile error. config.hpp FORWARD-DECLARES every class it
    uses and includes none of their headers, so a member whose class is not
    declared is `does not name a type` -- twenty minutes into the build, which
    is exactly where the dock's first version died.

    The second is worse, because it compiles. `Config` in QML is not
    GlobalConfig; it is an attached type that mirrors it property by property
    so a window can inherit a per-monitor override. A section added to the one
    and not the other builds, links, loads, and is simply undefined when QML
    asks for it -- `Config.dock` was undefined for an entire release and the
    only symptom was a dock that would not appear.

    Called by every patch that adds a section, on the text it is about to
    write. A patcher that asserts its anchors and not its output is checking
    that it found the right place to write the bug.
    """
    for m in re.finditer(r"CONFIG_SUBOBJECT\((\w+), (\w+)\)", cfg_text):
        cls, name = m.group(1), m.group(2)
        if "class %s;" % cls not in cfg_text:
            fail(f"config.hpp uses {cls} without forward-declaring it. That is "
                 "a compile error, and this is the last place to catch it "
                 "before a twenty-minute build does.")
        if f"* {name} READ {name} " not in att_text:
            fail(f"config.hpp has a {name} section that configattached.hpp "
                 "does not mirror. It will compile, and QML asking for "
                 f"Config.{name} will get undefined -- which is a feature that "
                 "silently does nothing, not a build failure.")
        if f"CONFIG_ATTACHED_GETTER({cls}, {name})" not in attc_text:
            fail(f"configattached.hpp declares {name} but configattached.cpp "
                 "does not define it. That is a link error at the very end of "
                 "the build.")


def patch_dock(release):
    """
    A dock: the open applications, along the bottom edge.

        dock.enabled        off by default
        dock.iconSize       px
        dock.flow           the animated line running between the icons
        dock.hideWhenEmpty  no windows, no dock
        dock.background     draw a bar behind the icons at all
        dock.backgroundOpacity  0-100
        dock.radius         the bar's corners
        dock.iconRadius     the icons' corners
        dock.spacing        the gap the flow runs across
        dock.padding        the bar's inner padding

    caelestia has a bar and no dock, and the bar is a vertical rail that shows
    workspaces rather than applications. This is the other thing: what is open,
    as icons, where Windows and macOS have taught everyone to look for it.

    ── Its own window, on the Top layer ─────────────────────────────────────

    Not part of the background layer, which sits UNDER windows -- a dock you
    cannot see because Firefox is in front of it is not a dock. Its own
    layer-shell surface, above windows, with an input mask that covers the bar
    and nothing else: the rest of that strip has to keep belonging to whatever
    is underneath it, or the bottom of every maximised window stops responding.

    ── The one edit to upstream is one line in shell.qml ────────────────────

    `GenesiDock {}` beside `Background {}`. The file lives in modules/background
    so the import list at the top of shell.qml does not change either -- the
    window it opens decides its own layer, so where the file sits costs nothing
    and buying a second import line costs a second thing to assert.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    cfg = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "config.hpp")
    # The members are DECLARED in config.hpp and INITIALISED in config.cpp --
    # where there are two constructors, both listing every one. Patching only
    # the header compiles and leaves m_dock null in whichever constructor was
    # missed, which is a crash on the first read of Config.dock.
    ccpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "config.cpp")
    # And a THIRD place, which is the one the first version of this patch
    # missed. `Config` in QML is not GlobalConfig -- it is an ATTACHED type
    # (configattached.hpp) that mirrors GlobalConfig property by property so a
    # window can inherit a per-monitor override. A section added to
    # GlobalConfig and not to the mirror compiles, loads, and is simply not
    # there when QML asks for it: `Config.dock` is undefined, every binding
    # that touches it throws, and the dock is enabled and invisible. That is
    # what shipped, and it is why patch_dock ends by checking the mirror.
    att = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "configattached.hpp")
    attc = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "configattached.cpp")
    shell = os.path.join(release, "shell.qml")
    for p in (hpp, cfg, ccpp, att, attc, shell):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the shell's layout moved.")

    for name in DOCK_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read()
           for p in (hpp, cfg, ccpp, att, attc, shell)}

    if "GenesiDockConfig" in src[hpp] or "GenesiDockConfig" in src[cfg]:
        fail("the dock config is already there -- this ran twice, or upstream "
             "took the name.")

    anchor = "class BackgroundConfig : public ConfigObject {"
    if anchor not in src[hpp]:
        fail("BackgroundConfig is not where the dock patch expects it.")
    block = (
        "// Genesi: the dock. It lives in this header rather than one of its own\n"
        "// because config.hpp already includes this one, and a new header would\n"
        "// be a second file to add to the build for one class.\n"
        "class GenesiDockConfig : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    CONFIG_PROPERTY(bool, enabled, false)\n"
        "    CONFIG_PROPERTY(int, iconSize, 44)\n"
        "    CONFIG_PROPERTY(bool, flow, true)\n"
        "    CONFIG_PROPERTY(bool, hideWhenEmpty, true)\n"
        "    // The look. `background` off leaves the icons floating on the\n"
        "    // desktop with nothing behind them, which is a different thing\n"
        "    // from an opacity of zero: no bar means no border either.\n"
        "    CONFIG_PROPERTY(bool, background, true)\n"
        "    CONFIG_PROPERTY(int, backgroundOpacity, 82)\n"
        "    CONFIG_PROPERTY(int, radius, 28)\n"
        "    CONFIG_PROPERTY(int, iconRadius, 16)\n"
        "    CONFIG_PROPERTY(int, spacing, 28)\n"
        "    CONFIG_PROPERTY(int, padding, 16)\n"
        "\n"
        "    // Which edge. Only the two horizontal ones: a vertical dock is a\n"
        "    // different LAYOUT, not a different anchor, and offering it as a\n"
        "    // fifth value of this property would be a setting that half\n"
        "    // works.\n"
        "    CONFIG_PROPERTY(QString, edge, u\"bottom\"_s)\n"
        "    CONFIG_PROPERTY(bool, autoHide, false)\n"
        "    // The icon under the pointer grows, its neighbours grow less.\n"
        "    CONFIG_PROPERTY(bool, magnify, true)\n"
        "    CONFIG_PROPERTY(bool, hoverLabels, true)\n"
        "    // How the dock is DRAWN, the same idea as the bar's form.\n"
        "    //\n"
        "    //   bar      one rounded surface behind every icon\n"
        "    //   islands  each icon on a surface of its own\n"
        "    //   rail     a strip the width of the screen, flush\n"
        "    //   seal     one surface with fully round ends\n"
        "    CONFIG_PROPERTY(QString, style, u\"bar\"_s)\n"
        "    CONFIG_PROPERTY(bool, frost, false)\n"
        "    // What is playing, at the end of the dock. `mediaOnlyWhen\n"
        "    // Playing` keeps it out of the way of a paused player,\n"
        "    // which is most of them most of the time.\n"
        "    CONFIG_PROPERTY(bool, media, true)\n"
        "    CONFIG_PROPERTY(bool, mediaOnlyWhenPlaying, false)\n"
        "    CONFIG_PROPERTY(bool, mediaArt, true)\n"
        "    // Applications that are in the dock whether or not they are\n"
        "    // running, as desktop entry ids, in the order they are shown --\n"
        "    // the order IS the setting, which is why it is a list.\n"
        "    CONFIG_PROPERTY(QStringList, pinned, {})\n"
        "\n"
        "public:\n"
        "    explicit GenesiDockConfig(QObject* parent = nullptr)\n"
        "        : ConfigObject(parent) {}\n"
        "};\n"
        "\n")
    out = {hpp: src[hpp].replace(anchor, block + anchor, 1)}

    # `pinned` is a QStringList and this header includes <qstring.h> and
    # nothing else -- it had no list in it before. Upstream's launcherconfig
    # carries the same include for the same reason.
    inc = "#include <qstring.h>\n"
    if inc not in out[hpp]:
        fail("backgroundconfig.hpp no longer includes <qstring.h>, so there is "
             "nowhere obvious to put the list include the dock's pinned apps "
             "need.")
    if "#include <qstringlist.h>" not in out[hpp]:
        out[hpp] = out[hpp].replace(inc, inc + "#include <qstringlist.h>\n", 1)

    member = "    CONFIG_SUBOBJECT(BackgroundConfig, background)\n"
    if member not in src[cfg]:
        fail("config.hpp's members are not where the dock patch expects them.")

    # config.hpp does NOT include the headers its members come from -- it
    # FORWARD-DECLARES every one of them. Adding the member without adding the
    # declaration is `'GenesiDockConfig' does not name a type`, which is a
    # compiler error twenty minutes into the build, and is exactly what shipped.
    fwd = "class BackgroundConfig;\n"
    if fwd not in src[cfg]:
        fail("config.hpp no longer forward-declares its config classes -- the "
             "dock's declaration has to go wherever they went.")
    out[cfg] = src[cfg].replace(fwd, fwd + "class GenesiDockConfig;\n", 1)
    out[cfg] = out[cfg].replace(
        member, member + "    CONFIG_SUBOBJECT(GenesiDockConfig, dock)\n", 1)

    init = "    , m_background(new BackgroundConfig(this))\n"
    n = src[ccpp].count(init)
    if n != 2:
        fail(f"config.cpp initialises m_background {n} times, not 2 -- the "
             "constructors changed, and a member added to only some of them "
             "is null in the rest.")
    out[ccpp] = src[ccpp].replace(
        init, init + "    , m_dock(new GenesiDockConfig(this))\n")

    # ── The mirror, which is what QML actually reads ─────────────────────────
    #
    # Three edits, all keyed off `background` because GenesiDockConfig lives in
    # backgroundconfig.hpp -- which configattached.hpp already names in a
    # Q_MOC_INCLUDE, so moc can see the type and no include line is needed.
    moc = 'Q_MOC_INCLUDE("backgroundconfig.hpp")'
    if moc not in src[att]:
        fail("configattached.hpp no longer Q_MOC_INCLUDEs backgroundconfig.hpp "
             "-- the dock's class lives there, and moc cannot see a type it "
             "was not told about.")

    prop = ("    Q_PROPERTY(const caelestia::config::BackgroundConfig* background "
            "READ background NOTIFY sourceChanged)\n")
    getter = "    [[nodiscard]] const BackgroundConfig* background() const;\n"
    for needle, what in ((prop, "the background Q_PROPERTY"),
                         (getter, "the background getter")):
        if needle not in src[att]:
            fail(f"configattached.hpp does not carry {what} where the dock "
                 "patch expects it.")
    out[att] = src[att].replace(prop, prop + (
        "    Q_PROPERTY(const caelestia::config::GenesiDockConfig* dock "
        "READ dock NOTIFY sourceChanged)\n"), 1)
    out[att] = out[att].replace(getter, getter + (
        "    [[nodiscard]] const GenesiDockConfig* dock() const;\n"), 1)

    impl = "CONFIG_ATTACHED_GETTER(BackgroundConfig, background)\n"
    if impl not in src[attc]:
        fail("configattached.cpp does not define the background getter with "
             "CONFIG_ATTACHED_GETTER -- the dock's getter is written the same "
             "way, and there is nowhere else to put it.")
    out[attc] = src[attc].replace(
        impl, impl + "CONFIG_ATTACHED_GETTER(GenesiDockConfig, dock)\n", 1)

    line = "    Background {}\n"
    if line not in src[shell]:
        fail("shell.qml does not instantiate Background where the dock patch "
             "expects it -- that is the line the dock goes beside.")
    out[shell] = src[shell].replace(
        line, line + "    GenesiDock {}\n", 1)

    # ── The post-condition, because there is no compiler here ────────────────
    #
    # Every CONFIG_SUBOBJECT in config.hpp names a type that must be either
    # forward-declared in that file or defined in something it includes. It
    # includes none of them, so "declared here" is the whole rule -- and
    # checking it is as close as this can get to compiling the result.
    #
    # The first version of this patch did not check, added the member, and the
    # build failed on `does not name a type` after twenty minutes. A patcher
    # that asserts its anchors and not its output is checking that it found the
    # right place to write the bug.
    verify_config_reachable(out[cfg], out[att], out[attc])
    for _path in list(out):
        if _path.endswith(".hpp"):
            out[_path] = ensure_header_deps(out[_path])
            verify_string_literals(_path, out[_path])

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("dock: a dock, on its own layer")



def patch_topbar(release):
    """
    A bar across the top, without taking caelestia away.

        topbar.enabled            off by default
        topbar.position           "top" or "bottom"
        topbar.height, gap, radius
        topbar.islands            three surfaces, or one continuous bar
        topbar.background, backgroundOpacity
        topbar.show*              what each island carries

    ── Why this is a patch and not a package ────────────────────────────────

    Genesi shipped a top bar once, as its OWN Quickshell process with its own
    shell.qml, and switching to it ran `pkill -f caelestia`. That does not
    disable a bar. It kills the shell: the launcher, every drawer, the
    notification daemon, the wallpaper, the theme bridge and the CLI all go
    with it, and what is left cannot be undone by any setting. It was
    withdrawn, and the withdrawal note asked what the two shells fight over.

    The answer is that they should never have been two. This is a window
    inside caelestia -- same process, same config, same colours -- exactly
    like the dock.

    ── The one line that hides the side rail ────────────────────────────────

    BarWrapper already has `disabled`, for excludedScreens, and everything
    about the rail keys off it: its width collapses to the border thickness,
    its exclusive zone goes with it, and Panels.qml anchors every drawer to
    `bar.implicitWidth`, so the whole layout reflows on its own.

    So turning the top bar on sets that same flag. Nothing is killed, nothing
    is restarted, and turning it off puts the rail back. One switch, and it
    cannot leave a machine with two bars or with none.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    cfg = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "config.hpp")
    ccpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "config.cpp")
    att = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "configattached.hpp")
    attc = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "configattached.cpp")
    wrapper = os.path.join(release, "modules", "bar", "BarWrapper.qml")
    shell = os.path.join(release, "shell.qml")
    for p in (hpp, cfg, ccpp, att, attc, wrapper, shell):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the shell's layout moved.")

    for name in TOPBAR_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read()
           for p in (hpp, cfg, ccpp, att, attc, wrapper, shell)}

    if "GenesiTopBarConfig" in src[hpp] or "GenesiTopBarConfig" in src[cfg]:
        fail("the top bar config is already there -- this ran twice, or "
             "upstream took the name.")

    # Beside the dock's, in backgroundconfig.hpp, for the same reason: that
    # header is already Q_MOC_INCLUDEd by configattached.hpp, so moc can see
    # the type and no new file joins the build for one class.
    anchor = "class GenesiDockConfig : public ConfigObject {"
    if anchor not in src[hpp]:
        fail("GenesiDockConfig is not in backgroundconfig.hpp -- patch_dock "
             "did not run, or its class moved. The top bar's config goes "
             "beside it.")
    block = (
        "// Genesi: the bar across the top. Beside the dock's config for the\n"
        "// same reason -- configattached.hpp already Q_MOC_INCLUDEs this\n"
        "// header, so a new one would be a second file in the build for one\n"
        "// class.\n"
        "class GenesiTopBarConfig : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    CONFIG_PROPERTY(bool, enabled, false)\n"
        "    // \"top\" or \"bottom\". A string rather than a bool because a\n"
        "    // setting called topbar.atBottom is a name that argues with\n"
        "    // itself the first time somebody reads the config.\n"
        "    CONFIG_PROPERTY(QString, position, u\"top\"_s)\n"
        "    CONFIG_PROPERTY(int, height, 34)\n"
        "    CONFIG_PROPERTY(int, gap, 6)\n"
        "    // How far the bar sits from the screen edge. Separate\n"
        "    // from `gap`, which is the space around the ISLANDS\n"
        "    // inside the strip -- one moves the bar off the edge,\n"
        "    // the other changes how tall the bar is.\n"
        "    CONFIG_PROPERTY(int, margin, 0)\n"
        "    CONFIG_PROPERTY(int, radius, 14)\n"
        "    // A bar has a SHAPE, and it is not a yes-or-no. `islands`\n"
        "    // was a bool, so the only two bars on offer were three\n"
        "    // pills and one inset slab -- and a switch labelled\n"
        "    // \"islands rather than one bar\" cannot grow a third\n"
        "    // answer without becoming a switch that lies.\n"
        "    //\n"
        "    //   islands  three surfaces, one per group\n"
        "    //   full     one slab, edge to edge, square to the corners\n"
        "    //   fit      one slab, inset all round, rounded\n"
        "    //   dock     one slab flush to its edge, rounded away\n"
        "    //   notch    the centre flush to the edge with shoulders\n"
        "    //            curving back into it; the sides ride bare\n"
        "    CONFIG_PROPERTY(QString, form, u\"islands\"_s)\n"
        "    // Blur behind the bar. Hyprland does this, not Qt -- a\n"
        "    // layer surface cannot blur what is under it from inside\n"
        "    // QML -- so it drives a layerrule on our namespace.\n"
        "    CONFIG_PROPERTY(bool, frost, false)\n"
        "    CONFIG_PROPERTY(bool, background, true)\n"
        "    CONFIG_PROPERTY(int, backgroundOpacity, 85)\n"
        "\n"
        "    CONFIG_PROPERTY(bool, showLogo, true)\n"
        "    // What the mark button DRAWS. Empty is the Genesi mark,\n"
        "    // which is a Shape and follows the scheme. Anything else\n"
        "    // is a Material Symbols ligature -- the same names the\n"
        "    // rest of the shell's icons use, so a person who wants\n"
        "    // 'apps' or their own distro glyph there can have it\n"
        "    // without a file to install.\n"
        "    CONFIG_PROPERTY(QString, markIcon, u\"\"_s)\n"
        "    CONFIG_PROPERTY(bool, showSidebarButton, true)\n"
        "    CONFIG_PROPERTY(bool, showWorkspaces, true)\n"
        "    CONFIG_PROPERTY(bool, showActiveWindow, true)\n"
        "    CONFIG_PROPERTY(bool, showClock, true)\n"
        "    CONFIG_PROPERTY(bool, showDate, true)\n"
        "    CONFIG_PROPERTY(bool, showResources, true)\n"
        "    CONFIG_PROPERTY(bool, showStatus, true)\n"
        "    CONFIG_PROPERTY(bool, showPower, true)\n"
        "    CONFIG_PROPERTY(bool, showConfigButton, true)\n"
        "\n"
        "    // The animated connector between the islands -- the same idea as\n"
        "    // the dock's flow. Three separate pills read as three unrelated\n"
        "    // things until something ties them together.\n"
        "    CONFIG_PROPERTY(bool, flow, true)\n"
        "    CONFIG_PROPERTY(bool, autoHide, false)\n"
        "    CONFIG_PROPERTY(bool, border, true)\n"
        "    CONFIG_PROPERTY(bool, shadow, false)\n"
        "\n"
        "public:\n"
        "    explicit GenesiTopBarConfig(QObject* parent = nullptr)\n"
        "        : ConfigObject(parent) {}\n"
        "};\n"
        "\n")
    out = {hpp: src[hpp].replace(anchor, block + anchor, 1)}

    fwd = "class GenesiDockConfig;\n"
    if fwd not in src[cfg]:
        fail("config.hpp does not forward-declare GenesiDockConfig -- "
             "patch_dock did not run.")
    out[cfg] = src[cfg].replace(fwd, fwd + "class GenesiTopBarConfig;\n", 1)

    member = "    CONFIG_SUBOBJECT(GenesiDockConfig, dock)\n"
    if member not in src[cfg]:
        fail("config.hpp has no dock member -- patch_dock did not run.")
    out[cfg] = out[cfg].replace(
        member, member + "    CONFIG_SUBOBJECT(GenesiTopBarConfig, topbar)\n", 1)

    init = "    , m_dock(new GenesiDockConfig(this))\n"
    n = src[ccpp].count(init)
    if n != 2:
        fail(f"config.cpp initialises m_dock {n} times, not 2 -- a member "
             "added to only some of the constructors is null in the rest.")
    out[ccpp] = src[ccpp].replace(
        init, init + "    , m_topbar(new GenesiTopBarConfig(this))\n")

    # The mirror. Everything QML reads goes through the attached type, and a
    # section missing from it compiles, links, loads and is undefined -- which
    # is how the dock shipped enabled and invisible.
    prop = ("    Q_PROPERTY(const caelestia::config::GenesiDockConfig* dock "
            "READ dock NOTIFY sourceChanged)\n")
    getter = "    [[nodiscard]] const GenesiDockConfig* dock() const;\n"
    for needle, what in ((prop, "the dock Q_PROPERTY"),
                         (getter, "the dock getter")):
        if needle not in src[att]:
            fail(f"configattached.hpp does not carry {what} -- patch_dock did "
                 "not run.")
    out[att] = src[att].replace(prop, prop + (
        "    Q_PROPERTY(const caelestia::config::GenesiTopBarConfig* topbar "
        "READ topbar NOTIFY sourceChanged)\n"), 1)
    out[att] = out[att].replace(getter, getter + (
        "    [[nodiscard]] const GenesiTopBarConfig* topbar() const;\n"), 1)

    impl = "CONFIG_ATTACHED_GETTER(GenesiDockConfig, dock)\n"
    if impl not in src[attc]:
        fail("configattached.cpp has no dock getter -- patch_dock did not run.")
    out[attc] = src[attc].replace(
        impl, impl + "CONFIG_ATTACHED_GETTER(GenesiTopBarConfig, topbar)\n", 1)

    verify_config_reachable(out[cfg], out[att], out[attc])
    for _path in list(out):
        if _path.endswith(".hpp"):
            out[_path] = ensure_header_deps(out[_path])
            verify_string_literals(_path, out[_path])

    # ── The one line in upstream's bar ───────────────────────────────────────
    old = ("    readonly property bool disabled: "
           "Strings.testRegexList(Config.bar.excludedScreens, screen.name)\n")
    if old not in src[wrapper]:
        fail("BarWrapper.qml's `disabled` is not what the top bar patch "
             "expects. That one property is what collapses the rail's width "
             "and its exclusive zone, and every drawer reflows off it.")
    out[wrapper] = src[wrapper].replace(old, (
        "    // Genesi: the top bar takes the rail's place rather than\n"
        "    // caelestia's process. Everything about the rail already keys\n"
        "    // off this one flag -- its width collapses to the border\n"
        "    // thickness, its exclusive zone goes with it, and Panels.qml\n"
        "    // anchors every drawer to bar.implicitWidth -- so one switch\n"
        "    // moves the whole layout and nothing has to be restarted.\n"
        "    readonly property bool disabled: Config.topbar.enabled || "
        "Strings.testRegexList(Config.bar.excludedScreens, screen.name)\n"), 1)

    line = "    GenesiSchemeScreen {}\n"
    if line not in src[shell]:
        fail("shell.qml does not build the scheme picker, which is the line "
             "the top bar goes beside -- patch_scheme_screen did not run.")
    out[shell] = src[shell].replace(line, line + (
        "    GenesiTopBar {}\n"
        "    GenesiStudio {}\n"), 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("topbar: a bar across the top, inside caelestia")


def patch_depth(release):
    """
    The wallpaper's subject, in front of the clock.

        background.depth.enabled
        background.depth.quality    draft | standard | fine
        background.depth.edgeFade   none | soft | strong
        background.depth.strength   subtle | medium | full
        background.depth.shadow     none | soft | strong

    ── What it actually is ─────────────────────────────────────────────────

    Background.qml draws the wallpaper, the visualiser, the Genesi widgets and
    the desktop clock, in that order. This adds a fifth layer on top holding
    the SUBJECT of the wallpaper and nothing else, cut out with an alpha
    channel -- so the subject is drawn twice, once as part of the picture
    underneath and once here, with the clock and the widgets in between.

    There is no depth map and nothing moves. It is one cut-out and a stacking
    order, and it is worth saying because the effect is usually sold as 3D.

    ── Why the layer goes after the clock's Loader ─────────────────────────

    Because in front of the clock is the whole point. Inside `behindClock`,
    where the Genesi widgets live, it would be under the clock and under
    nothing else -- which is a layer that costs a segmentation pass to move a
    subject in front of a visualiser.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    background = os.path.join(release, "modules", "background",
                              "Background.qml")
    for p in (hpp, background):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the desktop layer moved.")

    for name in DEPTH_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read() for p in (hpp, background)}

    if "GenesiDepthConfig" in src[hpp]:
        fail("the depth config is already there -- this ran twice.")

    # A sub-object of background, not a section of its own: it is a property
    # of the wallpaper, it is meaningless without one, and background.depth.*
    # is where somebody would look for it.
    anchor = "class GenesiDockConfig : public ConfigObject {"
    if anchor not in src[hpp]:
        fail("GenesiDockConfig is not in backgroundconfig.hpp -- patch_dock "
             "did not run.")
    block = (
        "// Genesi: the wallpaper's subject, drawn again over the clock and\n"
        "// the widgets so it appears to stand in front of them. genesi-depth\n"
        "// does the cutting; the shell draws what it produced.\n"
        "class GenesiDepthConfig : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    CONFIG_PROPERTY(bool, enabled, false)\n"
        "    // How carefully the edge is TRACED. Higher tiers work at a\n"
        "    // larger size and run GrabCut for longer -- better on hair and\n"
        "    // foliage, slower the first time a wallpaper is seen.\n"
        "    CONFIG_PROPERTY(QString, quality, u\"standard\"_s)\n"
        "    // ...and how sharply it is DRAWN, which is a different\n"
        "    // question. A hard edge suits a poster and reads as a sticker\n"
        "    // on a photograph.\n"
        "    CONFIG_PROPERTY(QString, edgeFade, u\"soft\"_s)\n"
        "    // How much the subject stands out in front: the layer's own\n"
        "    // opacity. Below full, the clock shows faintly through it.\n"
        "    CONFIG_PROPERTY(QString, strength, u\"full\"_s)\n"
        "    CONFIG_PROPERTY(QString, shadow, u\"soft\"_s)\n"
        "\n"
        "public:\n"
        "    explicit GenesiDepthConfig(QObject* parent = nullptr)\n"
        "        : ConfigObject(parent) {}\n"
        "};\n"
        "\n")
    out = {hpp: src[hpp].replace(anchor, block + anchor, 1)}

    member = "    CONFIG_SUBOBJECT(GenesiWidgets, widgets)\n"
    if member not in out[hpp]:
        fail("BackgroundConfig has no widgets member -- patch_desktop_widgets "
             "did not run, and depth goes beside it.")
    out[hpp] = out[hpp].replace(
        member, member + "    CONFIG_SUBOBJECT(GenesiDepthConfig, depth)\n", 1)

    # The widgets initialiser is the LAST one, so it carries the constructor's
    # empty body on the same line. Inserting after it would put a member
    # initialiser after the body; the new one goes in front of the `{}`.
    init = "        , m_widgets(new GenesiWidgets(this)) {}\n"
    n = out[hpp].count(init)
    if n != 1:
        fail(f"BackgroundConfig initialises m_widgets {n} times, not 1 -- a "
             "member added to only some of the constructors is null in the "
             "rest.")
    out[hpp] = out[hpp].replace(init, (
        "        , m_widgets(new GenesiWidgets(this))\n"
        "        , m_depth(new GenesiDepthConfig(this)) {}\n"), 1)

    out[hpp] = ensure_header_deps(out[hpp])
    verify_string_literals(hpp, out[hpp])

    # ── The layer, after the clock ──────────────────────────────────────────
    tail = ("            sourceComponent: DesktopClock {\n"
            "                wallpaper: behindClock\n"
            "                absX: clockLoader.x\n"
            "                absY: clockLoader.y\n"
            "            }\n"
            "        }\n")
    if tail not in src[background]:
        fail("Background.qml's clock Loader is not what the depth patch "
             "expects. The depth layer has to go AFTER it -- in front of the "
             "clock is the entire point of the feature -- and there is no "
             "other landmark for 'after the clock' in that file.")
    out[background] = src[background].replace(tail, tail + (
        "\n"
        "        // Genesi: the wallpaper's subject again, over everything\n"
        "        // else on the desktop. Last child, so the stacking order is\n"
        "        // wallpaper, visualiser, widgets, clock, subject.\n"
        "        GenesiDepth {}\n"), 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("depth: the wallpaper's subject, in front of the clock")


def patch_side_panel(release):
    """
    Quick settings down the left edge, when the Genesi bar is on.

        sidepanel.enabled          the panel exists at all
        sidepanel.edgeHover        the strip on the left that opens it
        sidepanel.width
        sidepanel.show*            which of its five blocks are drawn
        sidepanel.nightTemperature what hyprsunset is asked for

    ── Why the left edge is free ────────────────────────────────────────────

    caelestia's rail lives there, and its popouts with it. With the Genesi bar
    on, BarWrapper.disabled collapses that rail to the border thickness and
    drops its exclusive zone -- so the left edge is the one edge of the screen
    nothing is using. That is why the panel exists exactly when the bar does:
    with the rail back, a second panel arriving from underneath it would be
    two things answering one gesture.

    ── The edge has to be yielded as well as free ──────────────────────────

    Regions.qml insets its interior by the drag margin on every side, so on an
    empty workspace the drawers window owns the left ninety pixels the same
    way it owned the top -- see patch_edge_regions. GenesiEdges reports the
    left now, and the panel's hover strip is four pixels of screen that
    actually receive a pointer.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "backgroundconfig.hpp")
    cfg = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "config.hpp")
    ccpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "config.cpp")
    att = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "configattached.hpp")
    attc = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                        "configattached.cpp")
    shell = os.path.join(release, "shell.qml")
    for p in (hpp, cfg, ccpp, att, attc, shell):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the shell's layout moved.")

    for name in SIDEPANEL_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Decide by hand.")

    src = {p: io.open(p, encoding="utf-8").read()
           for p in (hpp, cfg, ccpp, att, attc, shell)}

    if "GenesiSidePanelConfig" in src[hpp]:
        fail("the side panel config is already there -- this ran twice.")

    anchor = "class GenesiTopBarConfig : public ConfigObject {"
    if anchor not in src[hpp]:
        fail("GenesiTopBarConfig is not in backgroundconfig.hpp -- "
             "patch_topbar did not run. The side panel only exists when the "
             "top bar does, so its config goes beside it.")
    block = (
        "// Genesi: the quick settings down the left edge. Beside the bar's\n"
        "// config because it only exists when the bar does -- without it\n"
        "// caelestia's rail is on that edge and this would be a second panel\n"
        "// answering the same gesture.\n"
        "class GenesiSidePanelConfig : public ConfigObject {\n"
        "    Q_OBJECT\n"
        "    QML_ANONYMOUS\n"
        "\n"
        "    CONFIG_PROPERTY(bool, enabled, true)\n"
        "    // The four-pixel strip on the left that opens it on hover. Off\n"
        "    // leaves the mark on the bar as the only way in, which is what\n"
        "    // somebody who keeps hitting it by accident will want.\n"
        "    CONFIG_PROPERTY(bool, edgeHover, true)\n"
        "    CONFIG_PROPERTY(int, width, 360)\n"
        "\n"
        "    CONFIG_PROPERTY(bool, showSession, true)\n"
        "    CONFIG_PROPERTY(bool, showToggles, true)\n"
        "    CONFIG_PROPERTY(bool, showSliders, true)\n"
        "    CONFIG_PROPERTY(bool, showCalendar, true)\n"
        "    CONFIG_PROPERTY(bool, showPower, true)\n"
        "\n"
        "    // What hyprsunset is asked for. 4000K is the warm end of what\n"
        "    // still reads as white; below about 3000 a screen looks broken\n"
        "    // rather than warm.\n"
        "    CONFIG_PROPERTY(int, nightTemperature, 4000)\n"
        "\n"
        "public:\n"
        "    explicit GenesiSidePanelConfig(QObject* parent = nullptr)\n"
        "        : ConfigObject(parent) {}\n"
        "};\n"
        "\n")
    out = {hpp: src[hpp].replace(anchor, block + anchor, 1)}

    fwd = "class GenesiTopBarConfig;\n"
    if fwd not in src[cfg]:
        fail("config.hpp does not forward-declare GenesiTopBarConfig.")
    out[cfg] = src[cfg].replace(fwd, fwd + "class GenesiSidePanelConfig;\n", 1)

    member = "    CONFIG_SUBOBJECT(GenesiTopBarConfig, topbar)\n"
    if member not in out[cfg]:
        fail("config.hpp has no topbar member.")
    out[cfg] = out[cfg].replace(
        member,
        member + "    CONFIG_SUBOBJECT(GenesiSidePanelConfig, sidepanel)\n", 1)

    init = "    , m_topbar(new GenesiTopBarConfig(this))\n"
    n = src[ccpp].count(init)
    if n != 2:
        fail(f"config.cpp initialises m_topbar {n} times, not 2 -- a member "
             "added to only some of the constructors is null in the rest.")
    out[ccpp] = src[ccpp].replace(
        init, init + "    , m_sidepanel(new GenesiSidePanelConfig(this))\n")

    prop = ("    Q_PROPERTY(const caelestia::config::GenesiTopBarConfig* topbar "
            "READ topbar NOTIFY sourceChanged)\n")
    getter = "    [[nodiscard]] const GenesiTopBarConfig* topbar() const;\n"
    for needle, what in ((prop, "the topbar Q_PROPERTY"),
                         (getter, "the topbar getter")):
        if needle not in src[att]:
            fail(f"configattached.hpp does not carry {what}.")
    out[att] = src[att].replace(prop, prop + (
        "    Q_PROPERTY(const caelestia::config::GenesiSidePanelConfig* "
        "sidepanel READ sidepanel NOTIFY sourceChanged)\n"), 1)
    out[att] = out[att].replace(getter, getter + (
        "    [[nodiscard]] const GenesiSidePanelConfig* sidepanel() const;\n"), 1)

    impl = "CONFIG_ATTACHED_GETTER(GenesiTopBarConfig, topbar)\n"
    if impl not in src[attc]:
        fail("configattached.cpp has no topbar getter.")
    out[attc] = src[attc].replace(
        impl, impl + "CONFIG_ATTACHED_GETTER(GenesiSidePanelConfig, sidepanel)\n",
        1)

    verify_config_reachable(out[cfg], out[att], out[attc])
    for _path in list(out):
        if _path.endswith(".hpp"):
            out[_path] = ensure_header_deps(out[_path])
            verify_string_literals(_path, out[_path])

    line = "    GenesiTopBar {}\n"
    if line not in src[shell]:
        fail("shell.qml does not build the top bar -- patch_topbar did not "
             "run, and the panel only exists beside it.")
    out[shell] = src[shell].replace(line, line + "    GenesiSidePanel {}\n", 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("side panel: quick settings on the edge the bar freed")


def patch_edge_layout(release):
    """
    The Genesi bar reserves its edge, and caelestia lays out below it.

    ── Two bugs, one cause ─────────────────────────────────────────────────

    caelestia reserves the screen edges with four one-pixel windows
    (Exclusions.qml), each claiming `border.thickness`. The Genesi bar claims
    its own strip on the same edge. Layer-shell hands out exclusive zones in
    the order surfaces are mapped, so on a cold start the border's window went
    first and the bar was placed ten pixels down -- inside the border, which is
    drawn over it. Toggling the bar remapped it and it jumped into place, which
    is why this only ever showed up after a reboot.

    And everything caelestia opens -- the dashboard, the launcher, the session
    menu, the notifications in the top right -- is laid out inside Panels.qml,
    which insets itself by `borderThickness` and nothing else. With a bar
    across the top, a notification arrives UNDERNEATH it.

    So: the border stops reserving an edge the bar has reserved, and Panels
    insets by the bar as well as by the border. Both read the same number from
    GenesiEdges, which owns the one expression for how tall the bar is.

    ── Why not just let the bar ignore exclusion zones ─────────────────────

    Because then nothing reserves the space and a maximised window opens
    underneath the bar. The bar is somewhere you READ; a bar you have to move
    a window off to read is not doing its job. The edge has to be reserved by
    exactly one of the two, and it should be the one that is actually there.
    """
    exclusions = os.path.join(release, "modules", "drawers", "Exclusions.qml")
    panels = os.path.join(release, "modules", "drawers", "Panels.qml")
    content = os.path.join(release, "modules", "drawers", "ContentWindow.qml")
    for p in (exclusions, panels, content):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the drawers' layout moved.")

    src = {p: io.open(p, encoding="utf-8").read()
           for p in (exclusions, panels, content)}
    for p in (exclusions, panels, content):
        if "GenesiEdges" in src[p]:
            fail(f"{os.path.basename(p)} already mentions GenesiEdges -- this "
                 "ran twice.")

    # ── The border stops reserving the bar's edge ──────────────────────────
    old = ("    ExclusionZone {\n"
           "        anchors.top: true\n"
           "    }\n"
           "\n"
           "    ExclusionZone {\n"
           "        anchors.right: true\n"
           "    }\n"
           "\n"
           "    ExclusionZone {\n"
           "        anchors.bottom: true\n"
           "    }\n")
    if old not in src[exclusions]:
        fail("Exclusions.qml's four border windows are not what the edge "
             "layout patch expects. Those windows are what reserves each "
             "screen edge, and the Genesi bar reserves one of the same ones.")
    new = ("    ExclusionZone {\n"
           "        anchors.top: true\n"
           "        // Genesi: not when the bar is up there. Two surfaces\n"
           "        // reserving one edge are handed their zones in the order\n"
           "        // they mapped, and on a cold start the border won -- which\n"
           "        // put the bar ten pixels down, inside the border that is\n"
           "        // drawn over it.\n"
           "        exclusiveZone: Launcher.GenesiEdges.top > 0"
           " ? 0 : contentItem.Config.border.thickness\n"
           "    }\n"
           "\n"
           "    ExclusionZone {\n"
           "        anchors.right: true\n"
           "    }\n"
           "\n"
           "    ExclusionZone {\n"
           "        anchors.bottom: true\n"
           "        exclusiveZone: Launcher.GenesiEdges.bottom > 0"
           " ? 0 : contentItem.Config.border.thickness\n"
           "    }\n")
    out = {exclusions: src[exclusions].replace(old, new, 1)}

    imp = "import qs.modules.bar as Bar\n"
    if imp not in out[exclusions]:
        fail("Exclusions.qml does not import qs.modules.bar -- there is no "
             "import block where this expects one.")
    out[exclusions] = out[exclusions].replace(
        imp, imp + "import qs.modules.launcher as Launcher\n", 1)

    # ── The panels open below it ───────────────────────────────────────────
    old = ("    anchors.fill: parent\n"
           "    anchors.margins: borderThickness\n"
           "    anchors.leftMargin: bar.implicitWidth\n")
    if old not in src[panels]:
        fail("Panels.qml's root anchors are not what the edge layout patch "
             "expects. Every drawer caelestia opens is laid out inside that "
             "one inset, and with a bar across the top they open underneath "
             "it.")
    new = ("    anchors.fill: parent\n"
           "    anchors.margins: borderThickness\n"
           "    anchors.leftMargin: bar.implicitWidth\n"
           "    // Genesi: and clear of the bar. Everything below this line --\n"
           "    // the dashboard, the launcher, the session menu, the\n"
           "    // notifications in the top right -- is positioned inside this\n"
           "    // inset, so without it a notification arrives underneath the\n"
           "    // bar rather than below it.\n"
           "    anchors.topMargin: borderThickness + Launcher.GenesiEdges.top\n"
           "    anchors.bottomMargin: borderThickness"
           " + Launcher.GenesiEdges.bottom\n")
    out[panels] = src[panels].replace(old, new, 1)

    # Panels.qml already imports the launcher, QUALIFIED. Reusing that
    # qualifier rather than adding a second unqualified import of the same
    # module: one module imported twice under two names is two ways to spell
    # the same singleton, and the day they disagree nobody will look here.
    if "import qs.modules.launcher as Launcher\n" not in out[panels]:
        fail("Panels.qml no longer imports qs.modules.launcher as Launcher -- "
             "the depth of that qualifier is what this patch writes against.")

    # ── ...and so does everything that draws them ─────────────────────────
    #
    # PanelBg turns a Panels-relative position into a window-relative one by
    # adding `borderThickness`, which was the entire offset until the line
    # above added the bar to it. Left alone, every blob background is drawn
    # one bar-height above the panel it belongs to -- a surface sticking out
    # over the top of a notification, which is exactly how it looked.
    old = ("        x: panel.x + bar.implicitWidth\n"
           "        y: panel.y + root.borderThickness\n")
    if old not in src[content]:
        fail("ContentWindow.qml's PanelBg does not offset by the border the "
             "way the edge layout patch expects. That offset and Panels' own "
             "top margin have to be the same number, or every drawer's "
             "background is drawn somewhere its drawer is not.")
    out[content] = src[content].replace(old, (
        "        x: panel.x + bar.implicitWidth\n"
        "        // Genesi: the same inset Panels uses. These two are one\n"
        "        // number -- the offset from this window to that item -- and\n"
        "        // they disagreed for a release.\n"
        "        y: panel.y + root.borderThickness + Launcher.GenesiEdges.top\n"), 1)

    old = ("        y: panels.notifications.y + root.borderThickness\n")
    if old not in out[content]:
        fail("ContentWindow.qml's fullscreen region does not offset by the "
             "border -- it converts a Panels position the same way PanelBg "
             "does and has to move with it.")
    out[content] = out[content].replace(old, (
        "        y: panels.notifications.y + root.borderThickness"
        " + Launcher.GenesiEdges.top\n"), 1)

    imp = "import qs.modules.bar\n"
    if imp not in out[content]:
        fail("ContentWindow.qml does not import qs.modules.bar -- there is no "
             "import block where this expects one.")
    out[content] = out[content].replace(
        imp, imp + "import qs.modules.launcher as Launcher\n", 1)

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("drawers: caelestia reserves and lays out around the Genesi bar")


# The singletons Genesi installs into modules/launcher. Every one of them is
# reached through `import qs.modules.launcher`, INCLUDING from a file that
# lives in that same directory -- Quickshell exposes a directory's singletons
# through its module, not by proximity.
GENESI_SINGLETONS = ("GenesiEdges", "GenesiSchemeState", "GenesiTopBarState",
                     "GenesiSidePanelState")


def verify_genesi_imports(release):
    """A name the patcher writes has to resolve in the file it writes it into.

    This is the failure that cost a release: patch_hidden_panels put
    `GenesiEdges.bottom` into the launcher's own Wrapper.qml and then removed
    the import again, reasoning that a file does not import its own directory.
    Quickshell does not work that way. `GenesiEdges` became an unresolved
    name, Wrapper.qml failed to load, Panels.qml failed with it, the drawers
    never came up, and the shell was a wallpaper and a spinner.

    Nothing could have caught it earlier. Every offscreen harness renders
    Genesi's own QML; this is a file the PATCHER writes, in a tree no test
    loads. So the check belongs here, at the end of the patching, against the
    tree that is about to be built.
    """
    bad = []
    for base, dirs, files in os.walk(release):
        if "build" in dirs:
            dirs.remove("build")
        for name in files:
            if not name.endswith(".qml"):
                continue
            path = os.path.join(base, name)
            text = io.open(path, encoding="utf-8", errors="replace").read()
            # Comments explain these by name constantly.
            body = re.sub(r"//[^\n]*", "", text)
            has_import = re.search(r"^import qs\.modules\.launcher\s*$",
                                   body, re.M) is not None
            has_qual = re.search(
                r"^import qs\.modules\.launcher as Launcher\s*$",
                body, re.M) is not None
            for singleton in GENESI_SINGLETONS:
                if name == singleton + ".qml":
                    continue
                rel = os.path.relpath(path, release)
                # `Launcher.GenesiEdges` needs the qualified import, and
                # nothing else does.
                if re.search(r"(?<![.\w])Launcher\.%s\s*\." % singleton,
                             body) and not has_qual:
                    bad.append((rel, "Launcher." + singleton))
                if not re.search(r"(?<![.\w])%s\s*\." % singleton, body):
                    continue
                if not has_import:
                    bad.append((rel, singleton))

    if bad:
        lines = "\n".join(f"      {f} uses {n}" for f, n in sorted(bad))
        fail("a Genesi singleton is used in a file that cannot see it:\n"
             + lines + "\n"
             "    Every one of them is reached through `import qs.modules."
             "launcher`, including from a file in that same directory --\n"
             "    Quickshell exposes a directory's singletons through its "
             "module, not by proximity. Without the import the name is\n"
             "    unresolved, that file fails to load, and everything that "
             "builds it fails with it.")
    print(f"imports: {len(GENESI_SINGLETONS)} Genesi singletons all reachable "
          "where they are used")


def verify_no_shadowed_types(release):
    """An unqualified import of another module outranks the file's own directory.

    This is the failure that cost the release after the one the check above
    was written for, and it came from the same line. patch_hidden_panels put
    a plain `import qs.modules.launcher` into modules/dashboard/Wrapper.qml to
    reach GenesiEdges. modules/launcher has a Content.qml; so does
    modules/dashboard. An explicit module import wins, so `Content { ... }`
    thirty lines further down stopped meaning the dashboard's Content and
    started meaning the launcher's -- which has no `facePicker`:

        Wrapper.qml[59:13]: Cannot assign to non-existent property "facePicker"

    and the file failed, and Panels failed, and the drawers never came up, and
    the shell sat on its loading screen. An import that was meant to add one
    name had quietly taken another away.

    So: for every unqualified `import qs.x.y` in a file, if that module and
    the file's OWN directory both define a type, and the file builds that
    type, the import has changed which one it means. Qualifying the import
    fixes it and is what every Genesi injection does now; this is here to
    catch the next one that does not, including one caused by upstream adding
    a file rather than by anything written here.
    """
    types = {}
    for base, dirs, files in os.walk(release):
        if "build" in dirs:
            dirs.remove("build")
        rel = os.path.relpath(base, release).replace(os.sep, "/")
        types[rel] = {f[:-4] for f in files
                      if f.endswith(".qml") and f[:1].isupper()}

    bad = []
    for base, dirs, files in os.walk(release):
        if "build" in dirs:
            dirs.remove("build")
        here = os.path.relpath(base, release).replace(os.sep, "/")
        for name in files:
            if not name.endswith(".qml"):
                continue
            path = os.path.join(base, name)
            body = re.sub(r"//[^\n]*", "", io.open(
                path, encoding="utf-8", errors="replace").read())
            for m in re.finditer(r"^import qs\.([\w.]+)\s*$", body, re.M):
                mod = m.group(1).replace(".", "/")
                # Importing the module you live in resolves to the files
                # beside you; there is nothing there to shadow.
                if mod == here:
                    continue
                for t in sorted(types.get(mod, set()) & types.get(here, set())):
                    if re.search(r"(?<![.\w])%s\s*\{" % t, body):
                        bad.append((os.path.relpath(path, release),
                                    m.group(1), t))

    if bad:
        lines = "\n".join(f"      {f} builds {t}, and `import qs.{mod}` "
                           f"replaces it" for f, mod, t in sorted(bad))
        fail("an unqualified import takes a type away from the file that "
             "declared it:\n" + lines + "\n"
             "    Both that module and this file's own directory define that "
             "type, and an explicit module import outranks the\n"
             "    directory -- so the name now means the other one, and the "
             "first property it does not have fails the whole file.\n"
             "    Import it `as Something` and reach the singleton through "
             "that.")
    print("imports: no import replaces a type its file declares")


def patch_hidden_panels(release):
    """
    A closed drawer tucks out of sight past the BAR, not past the border.

    The panels are laid out inside Panels.qml, which patch_edge_layout insets
    by the height of the Genesi bar so nothing opens underneath it. A closed
    drawer hides by moving up by its own height plus five -- relative to that
    inset area. Upstream that put its bottom edge five pixels above the
    Panels' top, which is inside the ten-pixel border and therefore invisible.

    With the bar in the inset, "five pixels above the Panels' top" is forty-
    five pixels down the screen. So the dashboard's closed blob hung visibly
    below the bar as a tab, permanently, in the middle of the top edge.

    Each closed panel tucks an extra bar-height now, which puts its edge back
    where upstream had it: five pixels above the top of the screen.

    Only the two that hide against a horizontal edge need it. The session,
    sidebar and OSD hide sideways, and the bar is never on that edge.
    """
    dash = os.path.join(release, "modules", "dashboard", "Wrapper.qml")
    launcher = os.path.join(release, "modules", "launcher", "Wrapper.qml")
    for p in (dash, launcher):
        if not os.path.exists(p):
            fail(f"{p} is gone -- a drawer moved.")

    src = {p: io.open(p, encoding="utf-8").read() for p in (dash, launcher)}
    for p in (dash, launcher):
        if "GenesiEdges" in src[p]:
            fail(f"{os.path.basename(p)} already mentions GenesiEdges -- this "
                 "ran twice.")

    out = {}

    old = "    anchors.topMargin: (-implicitHeight - 5) * offsetScale\n"
    if old not in src[dash]:
        fail("the dashboard's closed position is not what this expects. That "
             "one line is what puts it out of sight, and it measures from the "
             "top of the panel area -- which the Genesi bar has moved.")
    out[dash] = src[dash].replace(old, (
        "    // Genesi: plus the bar. This measures from the top of the panel\n"
        "    // AREA, and that area now starts below the bar -- so hiding by\n"
        "    // its own height left the closed blob hanging in view as a tab.\n"
        "    anchors.topMargin: (-implicitHeight - 5 - Launcher.GenesiEdges.top)"
        " * offsetScale\n"), 1)

    # patch_launcher_position has already rewritten this line, so the
    # shape to match is its output rather than upstream's. The closed
    # end of the slide is the `* offsetScale` term; the resting end is
    # left alone.
    old = "        - (restingOffset + implicitHeight + 5) * offsetScale\n"
    if old not in src[launcher]:
        fail("the launcher's slide is not what this expects. "
             "patch_launcher_position rewrites that line first, and "
             "this adds the bar to the closed end of it.")
    out[launcher] = src[launcher].replace(old, (
        "        // Genesi: plus the bar, when the bar is on this edge.\n"
        "        - (restingOffset + implicitHeight + 5 + GenesiEdges.bottom)"
        " * offsetScale\n"), 1)

    for path, text in out.items():
        m = re.search(r"^import [\w.]+( as \w+)?\n(?!import)", text, re.M)
        if not m:
            fail(f"{os.path.basename(path)} has no import block for the "
                 "GenesiEdges import to join.")
        # The dashboard's takes it QUALIFIED. modules/launcher has a
        # Content.qml and so does modules/dashboard, and an explicit module
        # import beats the file's own directory -- so the plain form made
        # `Content` in dashboard/Wrapper.qml mean the LAUNCHER's Content,
        # which has no facePicker, which failed the file, which failed Panels
        # and the drawers and the shell. Qualified, the name cannot be
        # reached by accident.
        #
        # The launcher's own Wrapper keeps the plain form: importing the
        # module you live in resolves to the files beside you, so there is
        # nothing there to shadow. That is what GenesiContent.qml runs.
        line = ("import qs.modules.launcher\n" if path == launcher
                else "import qs.modules.launcher as Launcher\n")
        out[path] = text[:m.end()] + line + text[m.end():]

    # The launcher's Wrapper keeps it too, even though it lives in that very
    # directory. Quickshell exposes a directory's singletons through its
    # MODULE, and a file beside them still has to import it -- caelestia's own
    # GenesiContent.qml sits in modules/launcher and carries the same import
    # with a comment saying why. Removing it here made `GenesiEdges` an
    # unresolved name, which failed the launcher, which failed Panels, which
    # failed the drawers, which left the shell as a wallpaper and a spinner.

    for path, text in out.items():
        io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("drawers: a closed one hides past the bar, not past the border")


def patch_edge_regions(release):
    """
    caelestia stops claiming the edge a Genesi surface is standing on.

    ── The bug ──────────────────────────────────────────────────────────────

    The drawers window covers the whole screen and takes input on a frame
    around it: the border, plus a drag margin so each panel can be pulled in
    from its own edge. Regions.qml sizes that margin as the largest
    dragThreshold of the four panels -- 80, the sidebar's -- and applies it on
    every edge whenever the active workspace has no windows on it.

    So on an empty desktop the drawers window owns the top and bottom NINETY
    pixels of the screen. The Genesi top bar is 46 tall and the dock about 76.
    Both sit entirely inside that, the drawers window is above them, and
    neither takes a single click.

    An empty workspace is exactly the state a session starts in, which is why
    this read as a bug in the bar's own startup: log in and the bar is dead;
    open any window and the margin collapses to zero and the bar works.
    Toggling the bar off and on also "fixed" it, by remapping its surface
    above the drawers -- which is how it survived every test that did not
    begin with a fresh login.

    ── The edit ─────────────────────────────────────────────────────────────

    On an edge a Genesi surface owns, the drag margin is dropped and the
    border strip is kept. That is the smallest change that works -- 10 pixels
    against the bar's 46 and the dock's 76 -- and it leaves every caelestia
    hover point where it was, at the size it was. Yielding the whole edge
    would have taken the dashboard's top hover and the launcher's drag-up with
    it.

    GenesiEdges answers only yes or no, deliberately: a version that published
    each surface's HEIGHT would have put the bar's geometry in two files, and
    two expressions for one number is the failure this project keeps meeting.
    """
    regions = os.path.join(release, "modules", "drawers", "Regions.qml")
    if not os.path.exists(regions):
        fail(f"{regions} is gone -- the drawers' input mask moved.")
    src = io.open(regions, encoding="utf-8").read()

    if "GenesiEdges" in src:
        fail("Regions.qml already mentions GenesiEdges -- this ran twice.")

    # Upstream's four lines, exactly as upstream writes them. Nothing
    # this patch introduces belongs in here: a precondition naming a
    # property the patch has not added yet can never match.
    old = ("    x: bar.clampedWidth + win.dragMaskPadding\n"
           "    y: clampedThickness + win.dragMaskPadding\n"
           "    width: win.width - bar.clampedWidth - clampedThickness"
           " - win.dragMaskPadding * 2\n"
           "    height: win.height - clampedThickness * 2"
           " - win.dragMaskPadding * 2\n")
    if old not in src:
        fail("Regions.qml's root geometry is not what the edge patch expects. "
             "Those four lines decide how much of each screen edge the drawers "
             "window takes input on, and the Genesi bar and dock both stand "
             "inside it.")
    new = ("    // Genesi: the drag margin, only on the edges nothing of ours\n"
           "    // is standing on. See GenesiEdges.qml -- on an empty\n"
           "    // workspace that margin is 80 pixels, and it was taking every\n"
           "    // click meant for the top bar or the dock. The border strip\n"
           "    // stays, so caelestia's own hover points are untouched.\n"
           "    readonly property real topPad: Launcher.GenesiEdges.claimsTop"
           " ? 0 : win.dragMaskPadding\n"
           "    readonly property real bottomPad:"
           " Launcher.GenesiEdges.claimsBottom ? 0 : win.dragMaskPadding\n"
           "    readonly property real leftPad: Launcher.GenesiEdges.left"
           " ? 0 : win.dragMaskPadding\n"
           "\n"
           "    x: bar.clampedWidth + leftPad\n"
           "    y: clampedThickness + topPad\n"
           "    width: win.width - bar.clampedWidth - clampedThickness"
           " - leftPad - win.dragMaskPadding\n"
           "    height: win.height - clampedThickness * 2 - topPad"
           " - bottomPad\n")
    src = src.replace(old, new, 1)

    # The same Panels-to-window conversion PanelBg does, for input rather
    # than for drawing. It has to move with the panels for the same reason.
    old = ("        x: panel.x + root.bar.implicitWidth\n"
           "        y: panel.y + root.borderThickness\n")
    if old not in src:
        fail("Regions.qml's R component does not offset by the border -- that "
             "offset and Panels' top margin are one number, and a region that "
             "keeps the old one answers where its panel is not.")
    src = src.replace(old, (
        "        x: panel.x + root.bar.implicitWidth\n"
        "        y: panel.y + root.borderThickness + Launcher.GenesiEdges.top\n"), 1)

    imp = "import qs.modules.bar as Bar\n"
    if imp not in src:
        fail("Regions.qml does not import qs.modules.bar -- there is no "
             "import block where this expects one.")
    src = src.replace(
        imp, imp + "import qs.modules.launcher as Launcher\n", 1)

    io.open(regions, "w", encoding="utf-8", newline="\n").write(src)
    print("drawers: the edges a Genesi surface owns are its own")


def patch_scheme_screen(release):
    """
    The colour schemes, on a surface of their own covering the screen.

        launcher.schemePicker  "launcher" (the fan inside the panel) or
                               "fullscreen" (a window of its own)

    The fan of painted cards already existed inside the launcher, and the
    launcher is the wrong frame for it: a fixed-width slab with a rounded edge,
    so the cards must stay inside it, stay small enough that nine fit, and stop
    short of both ends. Those are compromises made for a list of applications.

    Given a screen, the same fan runs off both sides and the middle card is big
    enough to judge a colour scheme from. Which one you get is a setting,
    because for somebody who arrived by typing `>scheme` the panel is still the
    right answer.

    One line in shell.qml, exactly like the dock: the window decides its own
    layer, so the only thing upstream has to be told is that it exists. The
    property itself is added by patch_launcher_layout, which is why this runs
    after it and checks for it rather than adding it again.
    """
    hpp = os.path.join(release, "plugin", "src", "Caelestia", "Config",
                       "launcherconfig.hpp")
    shell = os.path.join(release, "shell.qml")
    for p in (hpp, shell):
        if not os.path.exists(p):
            fail(f"{p} is gone -- the shell's layout moved.")

    for name in SCHEME_FILES:
        shipped = os.path.join(release, "modules", "background", name)
        if os.path.exists(shipped):
            fail(f"upstream now ships its own {name}. Decide by hand.")

    src = io.open(hpp, encoding="utf-8").read()
    if "CONFIG_PROPERTY(QString, schemePicker" not in src:
        fail("launcherconfig.hpp has no schemePicker -- patch_launcher_layout "
             "did not run, or its property block moved. The window would load "
             "and nothing would ever open it.")

    text = io.open(shell, encoding="utf-8").read()
    if "GenesiSchemeScreen" in text:
        fail("shell.qml already builds the scheme picker -- this ran twice.")
    line = "    GenesiDock {}\n"
    if line not in text:
        fail("shell.qml does not build the dock, which is the line the scheme "
             "picker goes beside -- patch_dock did not run.")
    io.open(shell, "w", encoding="utf-8", newline="\n").write(
        text.replace(line, line + "    GenesiSchemeScreen {}\n", 1))
    print("schemes: a full-screen picker, on its own layer")


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
    patch_actions_query(launcher)
    patch_applist_live_model(launcher)
    patch_wallpaper_transition(release)
    patch_bar_proportions(release)
    patch_frame_opacity(release)
    patch_launcher_position(release)
    patch_launcher_layout(release)
    patch_desktop_widgets(release)
    patch_dock(release)
    patch_scheme_screen(release)
    patch_topbar(release)
    patch_side_panel(release)
    patch_depth(release)
    patch_edge_regions(release)
    patch_edge_layout(release)
    patch_hidden_panels(release)
    patch_window_icons(release)
    patch_ddc_timeout(os.path.join(release, "services"))

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

    launcher_dest = os.path.join(release, "modules", "launcher")
    for name in LAUNCHER_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- the Genesi launcher layout has no file, "
                 "and Wrapper.qml has already been told to build it.")
        shutil.copyfile(src, os.path.join(launcher_dest, name))
        print(f"installed {name}")

    widget_dest = os.path.join(release, "modules", "background")
    for name in WIDGET_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- Background.qml has already been told to "
                 "build the widget layer.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(WIDGET_FILES)} widget files")

    for name in DOCK_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- shell.qml has already been told to "
                 "build the dock.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(DOCK_FILES)} dock file(s)")

    for name in SCHEME_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- shell.qml has already been told to "
                 "build the full-screen scheme picker.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(SCHEME_FILES)} scheme-picker file(s)")

    for name in TOPBAR_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- shell.qml has already been told to "
                 "build the top bar.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(TOPBAR_FILES)} top-bar file(s)")

    for name in SIDEPANEL_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- shell.qml has already been told to "
                 "build the side panel.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(SIDEPANEL_FILES)} side-panel file(s)")

    for name in DEPTH_FILES:
        src = os.path.join(ours, name)
        if not os.path.exists(src):
            fail(f"{src} is missing -- Background.qml has already been told "
                 "to build the depth layer.")
        shutil.copyfile(src, os.path.join(widget_dest, name))
    print(f"installed {len(DEPTH_FILES)} depth file(s)")

    verify_genesi_imports(release)
    verify_no_shadowed_types(release)
    return 0


if __name__ == "__main__":
    sys.exit(main())
