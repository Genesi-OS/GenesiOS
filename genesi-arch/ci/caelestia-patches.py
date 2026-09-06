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
    return 0


if __name__ == "__main__":
    sys.exit(main())
