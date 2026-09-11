// GENESI — the shell's own studio.
//
// Everything about how the shell is DRAWN, in one surface, reachable from the
// thing being drawn. The bar, the dock, the desktop and the shell's own
// actions, each a page behind a rail.
//
// ── Why it is here and not in Genesi Center ─────────────────────────────────
//
// You change a bar while looking at it, or you change it twice: once in a
// settings window, and again after seeing what it did. Every control in here
// is one whose result is on screen the moment it is used, which is exactly the
// set that does not belong in an application across the desktop.
//
// Genesi Center keeps one switch per surface -- the one that turns it on --
// and nothing else, so there is never a second copy of these forty settings to
// disagree with this one.
//
// ── A card over the desktop, not a screen ──────────────────────────────────
//
// The window covers the display so a click anywhere outside dismisses it, but
// it paints a card. A settings surface that blacks out the desktop hides the
// thing being configured, which for a shell is the entire point.
//
// ── Every control writes through genesi-center-set ─────────────────────────
//
// The same writer Genesi Center and the desktop menu use: it validates the key
// and the value and owns the file format. It takes several keys per call, and
// this uses that -- a page that wrote its rows one process at a time is the
// widget-drop race again with more rows.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property var bar: contentItem.Config.topbar
        readonly property var dock: contentItem.Config.dock
        readonly property var tok: contentItem.Tokens

        // One screen, the focused one. Two monitors would otherwise get two
        // studios, both holding the keyboard.
        readonly property bool mine: GenesiTopBarState.open
            && Hypr.monitorFor(win.modelData)?.id === Hypr.focusedMonitor?.id

        function set(section: string, key: string, value: var): void {
            Quickshell.execDetached(["genesi-center-set", "caelestia",
                                     `${section}.${key}`, String(value)]);
        }

        // The live value behind a row, by the same section-and-key pair the
        // row writes with. Dotted, because caelestia's config is nested three
        // deep in places -- appearance.rounding.scale, and every widget under
        // background.widgets.<name>.<leaf>.
        //
        // Reading it here rather than binding each row to a literal path is
        // what lets the table be a table: a row names its key once and both
        // halves use it, so a row cannot read one setting and write another.
        function get(section: string, key: string): var {
            let node = win.sectionOf(section);
            for (const part of key.split(".")) {
                if (node === null || node === undefined)
                    return undefined;
                node = node[part];
            }
            return node;
        }

        function sectionOf(section: string): var {
            const c = contentItem.Config;
            switch (section) {
            case "topbar":
                return c.topbar;
            case "sidepanel":
                return c.sidepanel;
            case "dock":
                return c.dock;
            case "appearance":
                return c.appearance;
            case "border":
                return c.border;
            case "launcher":
                return c.launcher;
            case "background":
                return c.background;
            }
            return null;
        }

        function act(what: string): void {
            switch (what) {
            case "center":
                win.run(["genesi-center"]);
                return;
            case "wallpaper":
                win.run(["caelestia", "wallpaper", "-r"]);
                return;
            case "reload":
                win.run(["caelestia", "shell", "-d"]);
                return;
            case "schemes":
                GenesiTopBarState.hide();
                GenesiSchemeState.show();
                return;
            case "session":
                const v = Visibilities.getForActive();
                if (v)
                    v.session = true;
                GenesiTopBarState.hide();
                return;
            }
        }

        function run(argv: var): void {
            Quickshell.execDetached(argv);
            GenesiTopBarState.hide();
        }

        screen: modelData
        name: "genesi-studio"
        visible: win.mine

        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.mine ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // Declared first, so the card is drawn over it and takes its own
        // clicks. Without that every toggle would close the studio.
        MouseArea {
            anchors.fill: parent
            onClicked: GenesiTopBarState.hide()
        }

        StyledRect {
            id: card

            // Under the bar, on the side the bar's button is. A panel that
            // opens at the top while the bar is at the bottom makes you look
            // for the connection between the two.
            anchors.left: parent.left
            anchors.leftMargin: win.bar.gap * 3
            anchors.top: win.bar.position !== "bottom" ? parent.top : undefined
            anchors.bottom: win.bar.position === "bottom" ? parent.bottom : undefined
            anchors.topMargin: win.bar.height + win.bar.gap * 3
            anchors.bottomMargin: win.bar.height + win.bar.gap * 3

            implicitWidth: Math.min(win.width - win.bar.gap * 6, 860)
            implicitHeight: Math.min(win.height * 0.78, 620)

            radius: win.tok.rounding.large
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            opacity: win.mine ? 1 : 0
            scale: win.mine ? 1 : 0.97

            Behavior on opacity {
                Anim {}
            }
            Behavior on scale {
                Anim {}
            }

            MouseArea {
                anchors.fill: parent
            }

            focus: true
            Keys.onEscapePressed: GenesiTopBarState.hide()

            // ── The rail ─────────────────────────────────────────────────────
            //
            // Grouped, because eight flat entries read as a list and three
            // groups of two or three read as a shape. The groups are the three
            // things a shell is: what is along an edge, what is on the
            // wallpaper, and what the shell itself does.
            Item {
                id: rail

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: win.tok.padding.large
                width: 178

                readonly property var groups: [
                    {
                        title: qsTr("START"),
                        items: [
                            {
                                id: "home",
                                label: qsTr("Everything"),
                                icon: "grid_view",
                                blurb: qsTr("Search every setting in the shell, or pick a page to work through.")
                            }
                        ]
                    },
                    {
                        title: qsTr("EDGES"),
                        items: [
                            {
                                id: "bar",
                                label: qsTr("Bar"),
                                icon: "toolbar",
                                blurb: qsTr("Where it sits, what shape it takes, how its surface reads.")
                            },
                            {
                                id: "dock",
                                label: qsTr("Dock"),
                                icon: "dock",
                                blurb: qsTr("The applications along the opposite edge.")
                            },
                            {
                                id: "panel",
                                label: qsTr("Panel"),
                                icon: "left_panel_open",
                                blurb: qsTr("The quick settings on the left edge, and the mark that opens them.")
                            },
                            {
                                id: "launcher",
                                label: qsTr("Launcher"),
                                icon: "search",
                                blurb: qsTr("The panel that opens on SUPER, and what it carries.")
                            }
                        ]
                    },
                    {
                        title: qsTr("DESKTOP"),
                        items: [
                            {
                                id: "widgets",
                                label: qsTr("Widgets"),
                                icon: "widgets",
                                blurb: qsTr("Fifteen things that can be drawn on the wallpaper.")
                            },
                            {
                                id: "desktop",
                                label: qsTr("Desktop"),
                                icon: "wallpaper",
                                blurb: qsTr("The wallpaper, the clock on it, and the visualiser.")
                            }
                        ]
                    },
                    {
                        title: qsTr("SHELL"),
                        items: [
                            {
                                id: "shape",
                                label: qsTr("Shape"),
                                icon: "shapes",
                                blurb: qsTr("Four scales that change the character of every surface at once.")
                            },
                            {
                                id: "system",
                                label: qsTr("System"),
                                icon: "tune",
                                blurb: qsTr("The shell's own actions, and where the rest of the settings are.")
                            }
                        ]
                    }
                ]

                // Scrolls, because the rail is nine entries now and the
                // card is a fixed height. It ran under the ON NOW block, which
                // is anchored to the bottom -- the last page in the list was
                // drawn behind two lines of text and could not be clicked.
                StyledFlickable {
                    id: railScroll

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: onNow.top
                    anchors.bottomMargin: win.tok.spacing.small
                    contentHeight: railCol.implicitHeight
                    clip: true

                Column {
                    id: railCol

                    width: railScroll.width
                    spacing: win.tok.spacing.small

                    Row {
                        spacing: win.tok.spacing.small
                        bottomPadding: win.tok.spacing.medium

                        GenesiMark {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("SHELL STUDIO")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    Repeater {
                        model: rail.groups

                        Column {
                            id: group

                            required property var modelData

                            width: rail.width
                            spacing: win.tok.spacing.extraSmall
                            topPadding: win.tok.spacing.small

                            StyledText {
                                leftPadding: win.tok.padding.small
                                bottomPadding: win.tok.spacing.extraSmall
                                text: group.modelData.title
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }

                            Repeater {
                                model: group.modelData.items

                                StyledRect {
                                    id: entry

                                    required property var modelData

                                    readonly property bool on: entry.modelData.id === GenesiTopBarState.section

                                    width: rail.width
                                    implicitHeight: 34
                                    radius: win.tok.rounding.large
                                    color: entry.on ? Colours.palette.m3surfaceContainerHighest
                                                    : (entryHover.containsMouse
                                                       ? Qt.alpha(Colours.palette.m3onSurface, 0.06)
                                                       : "transparent")

                                    Behavior on color {
                                        CAnim {}
                                    }

                                    MaterialIcon {
                                        anchors.left: parent.left
                                        anchors.leftMargin: win.tok.padding.medium
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: entry.modelData.icon
                                        color: entry.on ? Colours.palette.m3primary
                                                        : Colours.palette.m3onSurfaceVariant
                                        fontStyle: Tokens.font.icon.small
                                    }

                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 44
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: entry.modelData.label
                                        font: Tokens.font.body.medium
                                        color: entry.on ? Colours.palette.m3onSurface
                                                        : Colours.palette.m3onSurfaceVariant
                                    }

                                    MouseArea {
                                        id: entryHover

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: GenesiTopBarState.section = entry.modelData.id
                                    }
                                }
                            }
                        }
                    }
                }
                }

                // What is on, at a glance, without opening a page for it.
                Column {
                    id: onNow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: win.tok.spacing.extraSmall

                    StyledText {
                        text: qsTr("ON NOW")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }

                    StyledText {
                        width: parent.width
                        text: [
                            win.bar.enabled ? qsTr("top bar") : qsTr("side rail"),
                            win.dock.enabled ? qsTr("dock") : ""
                        ].filter(s => s !== "").join(" · ")
                        font: Tokens.font.mono.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                anchors.left: rail.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: win.tok.padding.large
                anchors.topMargin: win.tok.padding.large
                anchors.bottomMargin: win.tok.padding.large
                width: 1
                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
            }

            // ── The page ─────────────────────────────────────────────────────
            Item {
                id: pane

                anchors.left: rail.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: win.tok.padding.large
                anchors.leftMargin: win.tok.padding.extraLarge

                readonly property var current: {
                    for (const g of rail.groups)
                        for (const it of g.items)
                            if (it.id === GenesiTopBarState.section)
                                return it;
                    return rail.groups[0].items[0];
                }

                // ── Every page, as data ──────────────────────────────────────
                //
                // A row names the section and the key it reads AND writes, once
                // -- so a row cannot show one setting and change another, and
                // ci/center-wiring-test.py can check every one of them against
                // the writer's own list of what exists.
                //
                // Hand-written rows came to forty settings out of the hundred
                // and sixty-two the writer accepts. The rest as QML would be
                // two thousand lines in which every row is the same four lines
                // with different words, and the row that came out subtly
                // different would be the one nobody noticed.
                readonly property var tables: ({
                    "bar": [
                        { kind: "preview", of: "bar" },
                        { kind: "head", label: qsTr("PLACE") },
                        { kind: "choice", section: "topbar", key: "position", label: qsTr("Edge"), options: [{ id: "top", label: qsTr("TOP") }, { id: "bottom", label: qsTr("BOTTOM") }] },
                        { kind: "switch", section: "topbar", key: "autoHide", label: qsTr("Auto-hide"), blurb: qsTr("Reveal it by putting the pointer on the edge.") },
                        { kind: "amount", section: "topbar", key: "margin", label: qsTr("Margin"), from: 0, to: 40 },
                        { kind: "note", label: qsTr("How far the bar sits from the edge of the screen. The gap below is the space around the islands inside it.") },
                        { kind: "head", label: qsTr("FORM") },
                        { kind: "cards", section: "topbar", key: "form", label: qsTr("Form"), options: [
                            { id: "islands", label: qsTr("ISLANDS"), blurb: qsTr("Three pills") },
                            { id: "full", label: qsTr("FULL"), blurb: qsTr("Edge to edge") },
                            { id: "fit", label: qsTr("FIT"), blurb: qsTr("Inset frame") },
                            { id: "dock", label: qsTr("DOCK"), blurb: qsTr("Open edge") },
                            { id: "notch", label: qsTr("NOTCH"), blurb: qsTr("Flowing shoulders") }
                        ] },
                        { kind: "switch", section: "topbar", key: "flow", label: qsTr("Flow"), blurb: qsTr("A light running between the islands. Only where there is a gap for it to cross.") },
                        { kind: "head", label: qsTr("SURFACE") },
                        { kind: "switch", section: "topbar", key: "background", label: qsTr("Background") },
                        { kind: "amount", section: "topbar", key: "backgroundOpacity", label: qsTr("Opacity"), from: 0, to: 100 },
                        { kind: "switch", section: "topbar", key: "border", label: qsTr("Border") },
                        { kind: "switch", section: "topbar", key: "frost", label: qsTr("Frost"), blurb: qsTr("Blur whatever is behind it. Hyprland does this, not the shell.") },
                        { kind: "switch", section: "topbar", key: "shadow", label: qsTr("Shadow") },
                        { kind: "amount", section: "topbar", key: "radius", label: qsTr("Corners"), from: 0, to: 30 },
                        { kind: "head", label: qsTr("SIZE") },
                        { kind: "amount", section: "topbar", key: "height", label: qsTr("Height"), from: 24, to: 72 },
                        { kind: "amount", section: "topbar", key: "gap", label: qsTr("Margin"), from: 0, to: 24 },
                        { kind: "head", label: qsTr("CONTENTS") },
                        { kind: "switch", section: "topbar", key: "showLogo", label: qsTr("Genesi mark") },
                        { kind: "switch", section: "topbar", key: "showSidebarButton", label: qsTr("Search") },
                        { kind: "switch", section: "topbar", key: "showWorkspaces", label: qsTr("Workspaces") },
                        { kind: "switch", section: "topbar", key: "showActiveWindow", label: qsTr("Window title") },
                        { kind: "switch", section: "topbar", key: "showClock", label: qsTr("Clock") },
                        { kind: "switch", section: "topbar", key: "showDate", label: qsTr("Date") },
                        { kind: "switch", section: "topbar", key: "showResources", label: qsTr("Processor and memory") },
                        { kind: "switch", section: "topbar", key: "showStatus", label: qsTr("Network and battery") },
                        { kind: "switch", section: "topbar", key: "showPower", label: qsTr("Power") },
                        { kind: "switch", section: "topbar", key: "showConfigButton", label: qsTr("This studio's button") },
                        { kind: "note", label: qsTr("With the studio's button off, this opens from Genesi Center → Bar.") }
                    ],
                    "panel": [
                        { kind: "note", label: qsTr("Wi-Fi, Bluetooth, the volume and the screen, down the left edge. It exists only while the top bar does: without the bar, caelestia's rail is on that edge and its own popouts with it.") },
                        { kind: "head", label: qsTr("PANEL") },
                        { kind: "switch", section: "sidepanel", key: "enabled", label: qsTr("A quick settings panel") },
                        { kind: "switch", section: "sidepanel", key: "edgeHover", label: qsTr("Open on the left edge"), blurb: qsTr("A four-pixel strip that notices the pointer. The panel it opens closes again when you leave it; the one the mark opens stays.") },
                        { kind: "amount", section: "sidepanel", key: "width", label: qsTr("Width"), from: 280, to: 640 },
                        { kind: "head", label: qsTr("WHAT IS ON IT") },
                        { kind: "switch", section: "sidepanel", key: "showSession", label: qsTr("Log out, lock, restart, power") },
                        { kind: "switch", section: "sidepanel", key: "showToggles", label: qsTr("Connect"), blurb: qsTr("Wi-Fi, Bluetooth, Airplane, Night light, Keep awake, Do not disturb, Gaming.") },
                        { kind: "switch", section: "sidepanel", key: "showSliders", label: qsTr("Sound and display") },
                        { kind: "switch", section: "sidepanel", key: "showCalendar", label: qsTr("Calendar") },
                        { kind: "switch", section: "sidepanel", key: "showPower", label: qsTr("Power profile"), blurb: qsTr("Hidden anyway on a machine whose firmware offers no profiles to choose between.") },
                        { kind: "head", label: qsTr("NIGHT LIGHT") },
                        { kind: "amount", section: "sidepanel", key: "nightTemperature", label: qsTr("Temperature"), from: 1000, to: 6500, step: 100 },
                        { kind: "note", label: qsTr("4000K is the warm end of what still reads as white. Below about 3000 a screen looks broken rather than warm.") },
                        { kind: "head", label: qsTr("THE MARK") },
                        { kind: "cards", section: "topbar", key: "markIcon", label: qsTr("Button icon"), options: [
                            { id: "", label: qsTr("GENESI"), blurb: qsTr("The mark") },
                            { id: "apps", label: qsTr("APPS"), blurb: qsTr("Nine dots") },
                            { id: "grid_view", label: qsTr("GRID"), blurb: qsTr("Four panes") },
                            { id: "menu", label: qsTr("MENU"), blurb: qsTr("Three lines") },
                            { id: "widgets", label: qsTr("WIDGETS"), blurb: qsTr("Four tiles") },
                            { id: "blur_on", label: qsTr("BLOOM"), blurb: qsTr("A soft field") }
                        ] },
                        { kind: "note", label: qsTr("Any Material Symbols name works here; these are the six that suit a bar. The mark itself is drawn rather than loaded, so it takes the scheme's colours like everything else.") }
                    ],
                    "dock": [
                        { kind: "preview", of: "dock" },
                        { kind: "head", label: qsTr("DOCK") },
                        { kind: "switch", section: "dock", key: "enabled", label: qsTr("An application dock") },
                        { kind: "choice", section: "dock", key: "edge", label: qsTr("Edge"), options: [{ id: "bottom", label: qsTr("BOTTOM") }, { id: "top", label: qsTr("TOP") }] },
                        { kind: "switch", section: "dock", key: "autoHide", label: qsTr("Auto-hide"), blurb: qsTr("Reveal it by putting the pointer on the edge.") },
                        { kind: "switch", section: "dock", key: "hideWhenEmpty", label: qsTr("No windows, no dock"), blurb: qsTr("Pinned applications still count as something to show.") },
                        { kind: "head", label: qsTr("STYLE") },
                        { kind: "cards", section: "dock", key: "style", label: qsTr("Style"), options: [
                            { id: "bar", label: qsTr("BAR"), blurb: qsTr("One surface") },
                            { id: "islands", label: qsTr("ISLANDS"), blurb: qsTr("One each") },
                            { id: "rail", label: qsTr("RAIL"), blurb: qsTr("Full width") },
                            { id: "seal", label: qsTr("SEAL"), blurb: qsTr("Round ends") }
                        ] },
                        { kind: "head", label: qsTr("BEHAVIOUR") },
                        { kind: "switch", section: "dock", key: "magnify", label: qsTr("Magnify"), blurb: qsTr("The icon under the pointer grows, and its neighbours grow less.") },
                        { kind: "switch", section: "dock", key: "hoverLabels", label: qsTr("Hover labels"), blurb: qsTr("The application's name, on the side away from the edge.") },
                        { kind: "switch", section: "dock", key: "flow", label: qsTr("Flow"), blurb: qsTr("A light running between the icons.") },
                        { kind: "head", label: qsTr("NOW PLAYING") },
                        { kind: "switch", section: "dock", key: "media", label: qsTr("Media chip"), blurb: qsTr("What is playing, at the end of the dock. Click to play or pause, right-click for the whole player.") },
                        { kind: "switch", section: "dock", key: "mediaOnlyWhenPlaying", label: qsTr("Only while it plays"), blurb: qsTr("Otherwise a paused player keeps its place in the dock.") },
                        { kind: "switch", section: "dock", key: "mediaArt", label: qsTr("Album art") },
                        { kind: "head", label: qsTr("SURFACE") },
                        { kind: "switch", section: "dock", key: "background", label: qsTr("Background") },
                        { kind: "switch", section: "dock", key: "frost", label: qsTr("Frost"), blurb: qsTr("Blur whatever is behind it. Hyprland does this, not the shell.") },
                        { kind: "amount", section: "dock", key: "backgroundOpacity", label: qsTr("Opacity"), from: 0, to: 100 },
                        { kind: "amount", section: "dock", key: "radius", label: qsTr("Corners"), from: 0, to: 40 },
                        { kind: "amount", section: "dock", key: "iconRadius", label: qsTr("Icon corners"), from: 0, to: 30 },
                        { kind: "amount", section: "dock", key: "iconSize", label: qsTr("Icon size"), from: 28, to: 72 },
                        { kind: "amount", section: "dock", key: "spacing", label: qsTr("Gap between icons"), from: 0, to: 60 },
                        { kind: "amount", section: "dock", key: "padding", label: qsTr("Padding"), from: 0, to: 40 },
                        { kind: "head", label: qsTr("PINNED") },
                        { kind: "note", label: qsTr("A pinned application is in the dock whether or not it is running. These are what is open now, plus what is already pinned.") }
                    ],
                    "launcher": [
                        { kind: "head", label: qsTr("PLACE") },
                        { kind: "choice", section: "launcher", key: "position", label: qsTr("Where it opens"), options: [{ id: "bottom", label: qsTr("BOTTOM") }, { id: "centre", label: qsTr("CENTRE") }] },
                        { kind: "amount", section: "launcher", key: "width", label: qsTr("Width (0 fits the contents)"), from: 0, to: 1400 },
                        { kind: "switch", section: "launcher", key: "showOnHover", label: qsTr("Open when the pointer reaches the edge") },
                        { kind: "head", label: qsTr("BODY") },
                        { kind: "choice", section: "launcher", key: "layout", label: qsTr("Layout"), options: [{ id: "caelestia", label: qsTr("CAELESTIA") }, { id: "genesi", label: qsTr("GENESI") }] },
                        { kind: "amount", section: "launcher", key: "columns", label: qsTr("Columns"), from: 1, to: 3 },
                        { kind: "amount", section: "launcher", key: "maxShown", label: qsTr("Rows shown"), from: 3, to: 20 },
                        { kind: "amount", section: "launcher", key: "maxWallpapers", label: qsTr("Wallpapers shown"), from: 3, to: 30 },
                        { kind: "head", label: qsTr("THE GENESI BODY") },
                        { kind: "note", label: qsTr("Everything under here applies to the Genesi layout only.") },
                        { kind: "choice", section: "launcher", key: "background", label: qsTr("Picture behind it"), options: [{ id: "", label: qsTr("NONE") }, { id: "wallpaper", label: qsTr("WALLPAPER") }, { id: "/usr/share/wallpapers/genesi/wallpaper.png", label: qsTr("GENESI") }] },
                        { kind: "choice", section: "launcher", key: "backgroundExtent", label: qsTr("How much it covers"), options: [{ id: "header", label: qsTr("THE PROMPT") }, { id: "panel", label: qsTr("ALL OF IT") }] },
                        { kind: "amount", section: "launcher", key: "backgroundDim", label: qsTr("Dim"), from: 0, to: 100 },
                        { kind: "switch", section: "launcher", key: "showClock", label: qsTr("Clock") },
                        { kind: "switch", section: "launcher", key: "showWeather", label: qsTr("Weather") },
                        { kind: "switch", section: "launcher", key: "showHero", label: qsTr("The selection card") },
                        { kind: "switch", section: "launcher", key: "showChips", label: qsTr("The mode buttons") },
                        { kind: "head", label: qsTr("COLOUR SCHEMES") },
                        { kind: "choice", section: "launcher", key: "schemePicker", label: qsTr("Where the schemes are shown"), options: [{ id: "launcher", label: qsTr("IN THE LAUNCHER") }, { id: "fullscreen", label: qsTr("FULL SCREEN") }] },
                        { kind: "head", label: qsTr("KEYS") },
                        { kind: "switch", section: "launcher", key: "vimKeybinds", label: qsTr("Vim keys") },
                        { kind: "switch", section: "launcher", key: "enableDangerousActions", label: qsTr("Allow the dangerous actions") }
                    ],
                    "shape": [
                        { kind: "head", label: qsTr("SCALES") },
                        { kind: "note", label: qsTr("Each one multiplies a whole family of values rather than setting one, so four sliders change the character of the desktop.") },
                        { kind: "amount", section: "appearance", key: "rounding.scale", label: qsTr("Corners"), from: 0.0, to: 2.0, step: 0.05 },
                        { kind: "amount", section: "appearance", key: "spacing.scale", label: qsTr("Spacing"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "amount", section: "appearance", key: "padding.scale", label: qsTr("Padding"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "amount", section: "appearance", key: "font.scale", label: qsTr("Type"), from: 0.8, to: 1.4, step: 0.02 },
                        { kind: "amount", section: "appearance", key: "anim.durations.scale", label: qsTr("Animation speed"), from: 0.0, to: 2.5, step: 0.05 },
                        { kind: "head", label: qsTr("TRANSPARENCY") },
                        { kind: "switch", section: "appearance", key: "transparency.enabled", label: qsTr("Translucent surfaces") },
                        { kind: "amount", section: "appearance", key: "transparency.base", label: qsTr("Base"), from: 0.3, to: 1.0, step: 0.02 },
                        { kind: "amount", section: "appearance", key: "transparency.layers", label: qsTr("Layers"), from: 0.0, to: 1.0, step: 0.02 },
                        { kind: "head", label: qsTr("THE FRAME") },
                        { kind: "note", label: qsTr("The border the desktop sits inside. The bar takes its padding from the same value, so the two move together.") },
                        { kind: "amount", section: "border", key: "thickness", label: qsTr("Thickness"), from: 0, to: 40 },
                        { kind: "amount", section: "border", key: "rounding", label: qsTr("Corners"), from: 0, to: 60 },
                        { kind: "amount", section: "border", key: "smoothing", label: qsTr("Smoothing"), from: 0, to: 40 },
                        { kind: "amount", section: "border", key: "opacity", label: qsTr("Opacity"), from: 15, to: 100 }
                    ],
                    "desktop": [
                        { kind: "head", label: qsTr("WALLPAPER") },
                        { kind: "switch", section: "background", key: "wallpaperEnabled", label: qsTr("Draw a wallpaper") },
                        { kind: "amount", section: "background", key: "transitionDuration", label: qsTr("Transition (ms)"), from: 0, to: 3000 },
                        { kind: "action", label: qsTr("Another wallpaper"), blurb: qsTr("Retints the whole scheme when it is dynamic."), button: qsTr("SWITCH"), act: "wallpaper" },
                        { kind: "head", label: qsTr("THE CLOCK ON IT") },
                        { kind: "switch", section: "background", key: "desktopClock.enabled", label: qsTr("caelestia's desktop clock") },
                        { kind: "amount", section: "background", key: "desktopClock.scale", label: qsTr("Size"), from: 0.4, to: 2.5, step: 0.05 },
                        { kind: "choice", section: "background", key: "desktopClock.position", label: qsTr("Where"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-center", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "middle-center", label: qsTr("C") }, { id: "bottom-center", label: qsTr("B") }] },
                        { kind: "switch", section: "background", key: "desktopClock.invertColors", label: qsTr("Invert its colours") },
                        { kind: "switch", section: "background", key: "desktopClock.background.enabled", label: qsTr("A card behind it") },
                        { kind: "switch", section: "background", key: "desktopClock.shadow.enabled", label: qsTr("Shadow") },
                        { kind: "head", label: qsTr("THE VISUALISER") },
                        { kind: "switch", section: "background", key: "visualiser.enabled", label: qsTr("Audio visualiser") },
                        { kind: "switch", section: "background", key: "visualiser.autoHide", label: qsTr("Only while something plays") },
                        { kind: "switch", section: "background", key: "visualiser.blur", label: qsTr("Blur behind it") },
                        { kind: "amount", section: "background", key: "visualiser.rounding", label: qsTr("Bar corners"), from: 0.0, to: 3.0, step: 0.1 },
                        { kind: "amount", section: "background", key: "visualiser.spacing", label: qsTr("Bar spacing"), from: 0.0, to: 3.0, step: 0.1 }
                    ],
                    "widgets": [
                        { kind: "head", label: qsTr("ALL OF THEM") },
                        { kind: "switch", section: "background", key: "widgets.cards", label: qsTr("Cards behind them") },
                        { kind: "note", label: qsTr("Off, they float on the wallpaper the way the clock does. On, they stay readable over a busy picture -- which is most pictures.") },
                        { kind: "head", label: qsTr("EACH ONE") },
                        { kind: "note", label: qsTr("Drag them where you want from the desktop itself: right-click the wallpaper, then Arrange widgets.") },
                        { kind: "head", label: qsTr("WEATHER") },
                        { kind: "switch", section: "background", key: "widgets.weather.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.weather.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.weather.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("FORECAST") },
                        { kind: "switch", section: "background", key: "widgets.forecast.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.forecast.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.forecast.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("NOW PLAYING") },
                        { kind: "switch", section: "background", key: "widgets.media.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.media.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.media.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("PROCESSOR") },
                        { kind: "switch", section: "background", key: "widgets.cpu.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.cpu.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.cpu.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("MEMORY") },
                        { kind: "switch", section: "background", key: "widgets.memory.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.memory.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.memory.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("STORAGE") },
                        { kind: "switch", section: "background", key: "widgets.storage.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.storage.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.storage.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("NETWORK") },
                        { kind: "switch", section: "background", key: "widgets.network.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.network.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.network.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("BATTERY") },
                        { kind: "switch", section: "background", key: "widgets.battery.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.battery.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.battery.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("CALENDAR") },
                        { kind: "switch", section: "background", key: "widgets.calendar.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.calendar.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.calendar.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("ANALOGUE CLOCK") },
                        { kind: "switch", section: "background", key: "widgets.analogClock.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.analogClock.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.analogClock.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("WORKSPACES") },
                        { kind: "switch", section: "background", key: "widgets.workspaces.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.workspaces.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.workspaces.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("NOTIFICATIONS") },
                        { kind: "switch", section: "background", key: "widgets.notifications.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.notifications.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.notifications.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("UPTIME") },
                        { kind: "switch", section: "background", key: "widgets.uptime.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.uptime.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.uptime.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 },
                        { kind: "head", label: qsTr("GREETING") },
                        { kind: "switch", section: "background", key: "widgets.greeting.enabled", label: qsTr("On") },
                        { kind: "choice", section: "background", key: "widgets.greeting.position", label: qsTr("Corner"), options: [{ id: "top-left", label: qsTr("TL") }, { id: "top-centre", label: qsTr("T") }, { id: "top-right", label: qsTr("TR") }, { id: "mid-left", label: qsTr("L") }, { id: "centre", label: qsTr("C") }, { id: "mid-right", label: qsTr("R") }, { id: "bottom-left", label: qsTr("BL") }, { id: "bottom-centre", label: qsTr("B") }, { id: "bottom-right", label: qsTr("BR") }] },
                        { kind: "amount", section: "background", key: "widgets.greeting.scale", label: qsTr("Size"), from: 0.5, to: 2.0, step: 0.05 }
                    ],
                    "system": [
                        { kind: "head", label: qsTr("ACTIONS") },
                        { kind: "action", label: qsTr("Colour scheme"), blurb: qsTr("The schemes, fanned out across the screen."), button: qsTr("PICK"), act: "schemes" },
                        { kind: "action", label: qsTr("Genesi Center"), blurb: qsTr("Every setting, not just the ones you can see."), button: qsTr("OPEN"), act: "center" },
                        { kind: "action", label: qsTr("Reload the shell"), blurb: qsTr("Redraws every surface. Nothing is lost."), button: qsTr("RELOAD"), act: "reload" },
                        { kind: "head", label: qsTr("SESSION") },
                        { kind: "action", label: qsTr("Lock, log out, restart"), blurb: qsTr("caelestia's own session drawer."), button: qsTr("OPEN"), act: "session" }
                    ]
                })

                readonly property bool home: GenesiTopBarState.section === "home"

                // The label a page is known by, for the trail above a search
                // result. Read off the rail rather than kept in a second list:
                // a page renamed in one place and not the other is how a
                // result ends up filed under a name that is not on the rail.
                function pageLabel(id: string): string {
                    for (const g of rail.groups)
                        for (const it of g.items)
                            if (it.id === id)
                                return it.label;
                    return id;
                }

                // ── The front door ──────────────────────────────────────────
                //
                // Seven pages and a hundred and eighty rows is more than a
                // rail can answer for. With nothing typed this is the map --
                // one card per page, saying what is on it. With something
                // typed it is every row in the studio whose name contains it,
                // each under the page and the group it lives in, and each one
                // the REAL row: the same delegate, reading and writing the
                // same key. A search that shows you a copy of a control is a
                // search that can disagree with the page it came from.
                readonly property var homeRows: {
                    const q = home.query.trim().toLowerCase();
                    if (q === "") {
                        const out = [];
                        for (const g of rail.groups)
                            for (const it of g.items)
                                if (it.id !== "home")
                                    out.push({
                                        "kind": "page",
                                        "id": it.id,
                                        "label": it.label,
                                        "blurb": it.blurb,
                                        "icon": it.icon
                                    });
                        return out;
                    }

                    const out = [];
                    for (const id of Object.keys(pane.tables)) {
                        let head = "";
                        for (const r of pane.tables[id]) {
                            if (r.kind === "head") {
                                head = r.label;
                                continue;
                            }
                            if (r.kind === "note" || r.kind === "preview")
                                continue;
                            const label = r.label ?? "";
                            const blurb = r.blurb ?? "";
                            if (!label)
                                continue;
                            if (label.toLowerCase().indexOf(q) === -1
                                && blurb.toLowerCase().indexOf(q) === -1)
                                continue;
                            out.push({
                                "kind": "head",
                                "label": head === ""
                                    ? pane.pageLabel(id)
                                    : `${pane.pageLabel(id)} · ${head}`
                            });
                            out.push(r);
                        }
                    }
                    if (out.length === 0)
                        out.push({
                            "kind": "note",
                            "label": qsTr("Nothing in the studio is called that.")
                        });
                    return out;
                }

                readonly property var rows: {
                    if (pane.home)
                        return pane.homeRows;
                    const base = pane.tables[GenesiTopBarState.section] ?? [];
                    if (GenesiTopBarState.section !== "dock")
                        return base;
                    // The dock's pinnable applications are not a fixed list --
                    // they are what is running right now, plus what is already
                    // pinned. So that one page is the table plus a tail.
                    const out = base.slice();
                    const seen = {};
                    for (const cls of (win.dock.pinned ?? [])) {
                        if (seen[cls])
                            continue;
                        seen[cls] = true;
                        out.push({
                            "kind": "pin",
                            "label": cls
                        });
                    }
                    for (const t of (Hypr.toplevels?.values ?? [])) {
                        const c = t.lastIpcObject?.class;
                        if (!c || seen[c])
                            continue;
                        seen[c] = true;
                        out.push({
                            "kind": "pin",
                            "label": c
                        });
                    }
                    return out;
                }

                Column {
                    id: pageHead

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 2

                    StyledText {
                        text: pane.current.label
                        font: Tokens.font.title.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        width: parent.width
                        text: pane.current.blurb
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                // ── The search ──────────────────────────────────────────
                StyledRect {
                    id: home

                    property string query: ""

                    visible: pane.home
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: pageHead.bottom
                    anchors.topMargin: win.tok.spacing.medium
                    implicitHeight: 40
                    radius: win.tok.rounding.large
                    color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                    MaterialIcon {
                        id: searchIcon

                        anchors.left: parent.left
                        anchors.leftMargin: win.tok.padding.large
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledTextField {
                        id: searchField

                        anchors.left: searchIcon.right
                        anchors.right: clearButton.left
                        anchors.leftMargin: win.tok.spacing.small
                        anchors.rightMargin: win.tok.spacing.small
                        anchors.verticalCenter: parent.verticalCenter
                        placeholderText: qsTr("Search every setting")
                        // The field is the only thing on this page that wants
                        // the keyboard, so it takes focus when the page opens
                        // rather than waiting to be clicked.
                        focus: pane.home && win.mine
                        onTextChanged: home.query = text
                        Keys.onEscapePressed: {
                            if (text === "")
                                GenesiTopBarState.hide();
                            else
                                text = "";
                        }
                    }

                    MaterialIcon {
                        id: clearButton

                        anchors.right: parent.right
                        anchors.rightMargin: win.tok.padding.large
                        anchors.verticalCenter: parent.verticalCenter
                        visible: home.query !== ""
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchField.text = ""
                        }
                    }
                }

                StyledFlickable {
                    id: flick

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: pane.home ? home.bottom : pageHead.bottom
                    anchors.bottom: parent.bottom
                    anchors.topMargin: win.tok.spacing.medium
                    contentHeight: pages.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: pages

                        width: flick.width
                        spacing: win.tok.spacing.small

                        Repeater {
                            model: pane.rows

                            // One delegate per KIND, chosen by the row itself.
                            // A switch statement over five Components inside
                            // one delegate is a sixth place to forget.
                            delegate: DelegateChooser {
                                role: "kind"

                                DelegateChoice {
                                    roleValue: "head"

                                    Head {
                                        required property var modelData

                                        text: modelData.label
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "note"

                                    StyledText {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "switch"

                                    // Not caelestia's SwitchRow: a row here
                                    // often needs a second line saying what
                                    // the switch actually does, and a label
                                    // that has to carry the explanation is a
                                    // label nobody finishes reading.
                                    Toggle {
                                        required property var modelData

                                        label: modelData.label
                                        blurb: modelData.blurb ?? ""
                                        checked: win.get(modelData.section,
                                                         modelData.key) === true
                                        onToggled: v => win.set(modelData.section,
                                                                modelData.key, v)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "cards"

                                    Cards {
                                        required property var modelData

                                        label: modelData.label ?? ""
                                        blurb: modelData.blurb ?? ""
                                        options: modelData.options
                                        current: String(win.get(modelData.section,
                                                                modelData.key) ?? "")
                                        onPicked: id => win.set(modelData.section,
                                                                modelData.key, id)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "preview"

                                    Preview {
                                        required property var modelData

                                        of: modelData.of
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "page"

                                    PageCard {
                                        required property var modelData

                                        label: modelData.label
                                        blurb: modelData.blurb
                                        icon: modelData.icon
                                        onTriggered: GenesiTopBarState.section = modelData.id
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "amount"

                                    Amount {
                                        required property var modelData

                                        label: modelData.label
                                        from: modelData.from
                                        to: modelData.to
                                        // A scale is 0.5 to 2.0 and a corner
                                        // radius is 0 to 40, so the slider
                                        // works in whole STEPS and the row
                                        // converts. Without that every scale
                                        // would snap to 1.
                                        step: modelData.step ?? 1
                                        value: win.get(modelData.section,
                                                       modelData.key) ?? modelData.from
                                        onCommitted: v => win.set(modelData.section,
                                                                  modelData.key, v)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "choice"

                                    Choice {
                                        required property var modelData

                                        label: modelData.label
                                        options: modelData.options
                                        current: String(win.get(modelData.section,
                                                                modelData.key) ?? "")
                                        onPicked: id => win.set(modelData.section,
                                                                modelData.key, id)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "action"

                                    Action {
                                        required property var modelData

                                        label: modelData.label
                                        blurb: modelData.blurb ?? ""
                                        button: modelData.button ?? qsTr("OPEN")
                                        onTriggered: win.act(modelData.act)
                                    }
                                }

                                DelegateChoice {
                                    roleValue: "pin"

                                    PinRow {
                                        required property var modelData

                                        app: modelData.label
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── The rows every page is built from ────────────────────────────

            // A switch with room to say what it does. caelestia's SwitchRow
            // has a label and nothing else, and half the settings in here need
            // a sentence -- "Auto-hide" alone does not tell you the pointer is
            // what brings it back.
            component Toggle: StyledRect {
                id: toggle

                property string label: ""
                property string blurb: ""
                property bool checked: false

                signal toggled(bool v)

                Layout.fillWidth: true
                implicitHeight: toggleCol.implicitHeight + win.tok.padding.large * 2
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: win.tok.padding.large
                    spacing: win.tok.spacing.medium

                    ColumnLayout {
                        id: toggleCol

                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: toggle.label
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: toggle.blurb !== ""
                            text: toggle.blurb
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledSwitch {
                        checked: toggle.checked
                        onToggled: toggle.toggled(checked)
                    }
                }
            }

            // A choice whose values have SHAPES. The bar's form and the dock's
            // style are not two-state answers and they are not list entries
            // either -- each one is a different bar, and the fastest way to
            // say so is a card per answer with its name and one line about it,
            // read next to the preview above them.
            component Cards: ColumnLayout {
                id: cards

                property string label: ""
                property string blurb: ""
                property var options: []
                property string current: ""

                signal picked(string id)

                Layout.fillWidth: true
                spacing: win.tok.spacing.extraSmall

                // Named, because three rows of cards under one heading read
                // as one control with nine answers. The heading says what
                // KIND of thing this page is about; each row still has to say
                // which question it is.
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: win.tok.padding.small
                    visible: cards.label !== ""
                    text: cards.label
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: win.tok.padding.small
                    Layout.bottomMargin: 2
                    visible: cards.blurb !== ""
                    text: cards.blurb
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                Flow {
                    id: cardFlow

                    Layout.fillWidth: true
                    spacing: win.tok.spacing.small

                Repeater {
                    model: cards.options

                    StyledRect {
                        id: card

                        required property var modelData

                        readonly property bool on: card.modelData.id === cards.current

                        implicitWidth: Math.max(96, cardCol.implicitWidth
                                                + win.tok.padding.large * 2)
                        implicitHeight: cardCol.implicitHeight + win.tok.padding.large * 2
                        radius: win.tok.rounding.large

                        color: card.on
                            ? Colours.palette.m3primaryContainer
                            : (cardHover.containsMouse
                               ? Colours.layer(Colours.palette.m3surfaceContainer, 3)
                               : Colours.layer(Colours.palette.m3surfaceContainer, 2))
                        border.width: card.on ? 0 : 1
                        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                        Behavior on color {
                            CAnim {}
                        }

                        Column {
                            id: cardCol

                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                text: card.modelData.label
                                font: Tokens.font.label.medium
                                color: card.on ? Colours.palette.m3onPrimaryContainer
                                               : Colours.palette.m3onSurface
                            }

                            StyledText {
                                visible: (card.modelData.blurb ?? "") !== ""
                                text: card.modelData.blurb ?? ""
                                font: Tokens.font.body.small
                                color: card.on
                                    ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.8)
                                    : Colours.palette.m3onSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: cardHover

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cards.picked(card.modelData.id)
                        }
                    }
                }
                }
            }

            // ── The viewfinder ───────────────────────────────────────────────
            //
            // A small screen with the bar or the dock drawn on it as it is set
            // right now. Five named forms and four styles are nine words, and
            // a word for a shape is a thing you have to try before you know
            // whether you wanted it -- which for a bar means changing it,
            // looking up, and changing it back.
            //
            // Drawn from the same config the real surface reads, at a size
            // that cannot be mistaken for the real surface. It is deliberately
            // not a screenshot: what matters is the SHAPE and where it sits,
            // and a thumbnail of the actual bar at this scale is a grey smear.
            component Preview: StyledRect {
                id: preview

                property string of: "bar"

                readonly property bool bar: preview.of === "bar"
                readonly property bool atTop: preview.bar
                    ? win.bar.position !== "bottom"
                    : win.dock.edge === "top"
                readonly property string form: preview.bar ? win.bar.form : win.dock.style

                Layout.fillWidth: true
                Layout.topMargin: win.tok.spacing.small
                implicitHeight: 108
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                clip: true

                // The screen the miniature sits on. Inset, so the surface
                // being previewed can be flush against ITS edge and still be
                // seen to be flush -- against the card's own border there
                // would be nothing to be flush with.
                Item {
                    id: screen

                    anchors.fill: parent
                    anchors.margins: win.tok.padding.large

                    Rectangle {
                        anchors.fill: parent
                        radius: win.tok.rounding.small
                        // The darkest surface there is, so what is drawn on it
                        // reads as a bar rather than as a slightly different
                        // shade of the card it is inside.
                        color: Colours.palette.m3surface
                    }

                    // ── The bar ──────────────────────────────────────────
                    Item {
                        id: mini

                        readonly property real thickness: 16
                        readonly property real inset: preview.form === "fit" ? 5 : 0

                        visible: preview.bar
                        width: parent.width
                        height: mini.thickness + mini.inset * 2
                        y: preview.atTop ? 0 : parent.height - height

                        // One surface, for every form but islands and notch.
                        Rectangle {
                            visible: preview.form === "full" || preview.form === "fit"
                                || preview.form === "dock"
                            x: mini.inset
                            y: mini.inset
                            width: parent.width - mini.inset * 2
                            height: mini.thickness
                            color: Colours.palette.m3surfaceContainerHighest

                            readonly property real r: preview.form === "full" ? 0 : 6
                            readonly property real edgeR: preview.form === "dock" ? 0 : r

                            topLeftRadius: preview.atTop ? edgeR : r
                            topRightRadius: preview.atTop ? edgeR : r
                            bottomLeftRadius: preview.atTop ? r : edgeR
                            bottomRightRadius: preview.atTop ? r : edgeR
                        }

                        // The notch: the centre alone, flush to the edge.
                        Rectangle {
                            visible: preview.form === "notch"
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: preview.atTop ? 0 : parent.height - height
                            width: 74
                            height: mini.thickness
                            color: Colours.palette.m3surfaceContainerHighest
                            topLeftRadius: preview.atTop ? 0 : 6
                            topRightRadius: preview.atTop ? 0 : 6
                            bottomLeftRadius: preview.atTop ? 6 : 0
                            bottomRightRadius: preview.atTop ? 6 : 0
                        }

                        // The three groups. Always drawn, whatever is under
                        // them: a bar is what is written on it, and a preview
                        // showing only the surface would say nothing about
                        // where the clock ends up.
                        Repeater {
                            model: 3

                            Item {
                                id: group

                                required property int index

                                readonly property int dots: [3, 4, 5][group.index]

                                y: mini.inset
                                height: mini.thickness
                                width: group.dots * 7 + 10
                                x: group.index === 0 ? mini.inset + 6
                                    : (group.index === 1
                                       ? (mini.width - width) / 2
                                       : mini.width - width - mini.inset - 6)

                                Rectangle {
                                    anchors.fill: parent
                                    visible: preview.form === "islands"
                                    radius: 6
                                    color: Colours.palette.m3surfaceContainerHighest
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Repeater {
                                        model: group.dots

                                        Rectangle {
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: Colours.palette.m3onSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── The dock ─────────────────────────────────────────
                    Item {
                        id: miniDock

                        readonly property real thickness: 20

                        visible: !preview.bar
                        width: parent.width
                        height: miniDock.thickness + 6
                        y: preview.atTop ? 0 : parent.height - height

                        Rectangle {
                            id: dockSurface

                            visible: preview.form !== "islands"
                            anchors.horizontalCenter: preview.form === "rail"
                                ? undefined : parent.horizontalCenter
                            anchors.left: preview.form === "rail" ? parent.left : undefined
                            anchors.right: preview.form === "rail" ? parent.right : undefined
                            y: preview.form === "rail"
                                ? (preview.atTop ? 0 : parent.height - height)
                                : (preview.atTop ? 6 : 0)
                            width: preview.form === "rail" ? parent.width : dockRow.width + 14
                            height: miniDock.thickness
                            radius: preview.form === "seal" ? height / 2
                                : (preview.form === "rail" ? 0 : 7)
                            color: Colours.palette.m3surfaceContainerHighest
                        }

                        Row {
                            id: dockRow

                            anchors.centerIn: dockSurface
                            spacing: 5

                            Repeater {
                                model: 5

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: preview.form === "seal" ? 6 : 3
                                    color: Colours.palette.m3primary
                                    opacity: 0.75

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        visible: preview.form === "islands"
                                        z: -1
                                        radius: 6
                                        color: Colours.palette.m3surfaceContainerHighest
                                    }
                                }
                            }
                        }
                    }
                }

                // What it is, in words, for the two things a picture of a
                // shape cannot say.
                // What it is, in words, for the two things a picture of a
                // shape cannot say. On the edge the surface is NOT: a caption
                // printed across the group it describes is worse than no
                // caption.
                StyledText {
                    anchors.right: parent.right
                    anchors.top: preview.atTop ? undefined : parent.top
                    anchors.bottom: preview.atTop ? parent.bottom : undefined
                    anchors.margins: win.tok.padding.medium
                    text: [preview.form.toUpperCase(),
                           preview.atTop ? qsTr("TOP") : qsTr("BOTTOM")].join(" · ")
                    font: Tokens.font.mono.small
                    color: Colours.palette.m3outline
                }
            }

            // One page, on the front door.
            component PageCard: StyledRect {
                id: pageCard

                property string label: ""
                property string blurb: ""
                property string icon: ""

                signal triggered

                Layout.fillWidth: true
                implicitHeight: pageCardCol.implicitHeight + win.tok.padding.large * 2
                radius: win.tok.rounding.large
                color: pageHover.containsMouse
                    ? Colours.layer(Colours.palette.m3surfaceContainer, 3)
                    : Colours.layer(Colours.palette.m3surfaceContainer, 2)

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    id: pageIcon

                    anchors.left: parent.left
                    anchors.leftMargin: win.tok.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    text: pageCard.icon
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                Column {
                    id: pageCardCol

                    anchors.left: pageIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: win.tok.spacing.large
                    anchors.rightMargin: win.tok.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: pageCard.label
                        font: Tokens.font.body.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        width: parent.width
                        text: pageCard.blurb
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                MouseArea {
                    id: pageHover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pageCard.triggered()
                }
            }

            component Head: StyledText {
                Layout.fillWidth: true
                Layout.topMargin: win.tok.spacing.medium
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }

            // A labelled slider that writes when you LET GO, not while you
            // drag. Writing on every frame is sixty processes a second
            // rewriting shell.json.
            component Amount: StyledRect {
                id: amount

                property string label: ""
                property real from: 0
                property real to: 100
                property real value: 0
                // A whole number for a pixel count, a fraction for a scale.
                // Without this every scale on the Shape page would snap to 1
                // and four of the most useful sliders in the studio would be
                // three-position switches.
                property real step: 1

                signal committed(real v)

                // What the row shows. The config is the source of it, except
                // for the moment between letting go and the write landing:
                // genesi-center-set is a process and the new config arrives
                // back through a file watcher, which is easily long enough to
                // watch the handle snap to the old number and then forward
                // again. `pending` holds what was committed until the config
                // agrees, and a fresh grab drops it -- so a write that was
                // rejected shows the truth the next time the slider is
                // touched rather than lying until the shell reloads.
                property real pending: NaN
                readonly property real shown: isNaN(amount.pending)
                    ? amount.value : amount.pending

                onValueChanged: amount.pending = NaN

                function snap(v: real): real {
                    const stepped = Math.round((v - amount.from) / amount.step)
                        * amount.step + amount.from;
                    const clamped = Math.max(amount.from,
                                             Math.min(amount.to, stepped));
                    return amount.step >= 1 ? Math.round(clamped)
                                            : Number(clamped.toFixed(3));
                }

                function commit(v: real): void {
                    amount.pending = v;
                    amount.committed(v);
                }

                Layout.fillWidth: true
                implicitHeight: amountCol.implicitHeight + win.tok.padding.large * 2
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
                opacity: amount.enabled ? 1 : 0.45

                ColumnLayout {
                    id: amountCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: win.tok.padding.large
                    spacing: win.tok.spacing.small

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: amount.label
                        }

                        StyledText {
                            // Reads `pos`, not `value`, so it follows the
                            // handle during the drag -- see below for why
                            // those are not the same thing here. Shown at the
                            // precision it is set at, so a scale does not read
                            // as "1" across its whole range.
                            text: {
                                const v = amount.snap(amount.from
                                    + slider.pos * (amount.to - amount.from));
                                return amount.step >= 1 ? String(v)
                                                        : v.toFixed(2);
                            }
                            font: Tokens.font.mono.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    StyledSlider {
                        id: slider

                        Layout.fillWidth: true
                        enabled: amount.enabled
                        from: amount.from
                        to: amount.to
                        value: amount.shown

                        // ── Why this is not `onPressedChanged` and `value` ──
                        //
                        // caelestia's slider never moves its own `value`. The
                        // handle rides `pos`, a 0-to-1 position its own
                        // MouseArea drives through a Binding, and letting go
                        // hands that position back through `interaction`;
                        // turning it into a value and storing it somewhere is
                        // the caller's job. All three uses upstream are
                        // written that way.
                        //
                        // This row watched `pressed` and read `value`, and the
                        // drag touches neither: the template's `pressed` stays
                        // false because the template is not what is handling
                        // the mouse. So the handle moved, `pos` fell back to
                        // `visualPosition` on release, and the slider slid
                        // back to where it started having written nothing --
                        // every slider in the studio, exactly as reported, and
                        // silently, because a signal handler for a property
                        // that never changes is not an error.
                        //
                        // `interactionOnMove` off so `interaction` arrives
                        // once, on release, carrying the final position. A
                        // slider that wrote on every frame would be sixty
                        // processes a second rewriting shell.json.
                        interactionOnMove: false
                        onInteraction: v => amount.commit(amount.snap(
                            amount.from + v * (amount.to - amount.from)))
                        onDraggingChanged: if (dragging)
                            amount.pending = NaN
                    }
                }
            }

            component Choice: StyledRect {
                id: choice

                property string label: ""
                property var options: []
                property string current: ""

                signal picked(string id)

                Layout.fillWidth: true
                implicitHeight: choiceRow.implicitHeight + win.tok.padding.large * 2
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                RowLayout {
                    id: choiceRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: win.tok.padding.large
                    spacing: win.tok.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: choice.label
                    }

                    Repeater {
                        model: choice.options

                        StyledRect {
                            id: opt

                            required property var modelData

                            readonly property bool on: opt.modelData.id === choice.current

                            implicitWidth: optText.implicitWidth + win.tok.padding.large * 2
                            implicitHeight: 26
                            radius: Tokens.rounding.full
                            color: opt.on ? Colours.palette.m3primary
                                          : Colours.palette.m3surfaceContainerHighest

                            Behavior on color {
                                CAnim {}
                            }

                            StyledText {
                                id: optText

                                anchors.centerIn: parent
                                text: opt.modelData.label
                                font: Tokens.font.label.small
                                color: opt.on ? Colours.palette.m3onPrimary
                                              : Colours.palette.m3onSurfaceVariant
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: choice.picked(opt.modelData.id)
                            }
                        }
                    }
                }
            }

            // One application, pinned or not. The list it belongs to is
            // built from what is running plus what is already pinned, because
            // pinning what you have open is how anybody has ever built a dock
            // and it needs no application browser to do.
            component PinRow: StyledRect {
                id: pin

                property string app: ""

                readonly property bool on:
                    (win.dock.pinned ?? []).indexOf(pin.app) >= 0

                Layout.fillWidth: true
                implicitHeight: 44
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                IconImage {
                    id: pinIcon

                    anchors.left: parent.left
                    anchors.leftMargin: win.tok.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 22
                    asynchronous: true
                    source: Quickshell.iconPath(pin.app.toLowerCase(),
                                                "application-x-executable")
                }

                StyledText {
                    anchors.left: pinIcon.right
                    anchors.leftMargin: win.tok.spacing.medium
                    anchors.right: pinButton.left
                    anchors.rightMargin: win.tok.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: pin.app
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledRect {
                    id: pinButton

                    anchors.right: parent.right
                    anchors.rightMargin: win.tok.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: pinLabel.implicitWidth + win.tok.padding.large * 2
                    implicitHeight: 24
                    radius: Tokens.rounding.full
                    color: pin.on ? Colours.palette.m3primary
                                  : Colours.palette.m3surfaceContainerHighest

                    Behavior on color {
                        CAnim {}
                    }

                    StyledText {
                        id: pinLabel

                        anchors.centerIn: parent
                        text: pin.on ? qsTr("PINNED") : qsTr("PIN")
                        font: Tokens.font.label.small
                        color: pin.on ? Colours.palette.m3onPrimary
                                      : Colours.palette.m3onSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // The whole list, every time. The writer takes a
                            // list and replaces it; there is no add-one
                            // operation, because a list whose ORDER is the
                            // setting cannot have one.
                            const cur = (win.dock.pinned ?? []).slice();
                            const at = cur.indexOf(pin.app);
                            if (at >= 0)
                                cur.splice(at, 1);
                            else
                                cur.push(pin.app);
                            win.set("dock", "pinned", cur.join(","));
                        }
                    }
                }
            }

            component Action: StyledRect {
                id: action

                property string label: ""
                property string blurb: ""
                property string button: qsTr("OPEN")

                signal triggered

                Layout.fillWidth: true
                implicitHeight: actionCol.implicitHeight + win.tok.padding.large * 2
                radius: win.tok.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                Column {
                    id: actionCol

                    anchors.left: parent.left
                    anchors.right: actionButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: win.tok.padding.large
                    anchors.rightMargin: win.tok.spacing.medium
                    spacing: 2

                    StyledText {
                        text: action.label
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        width: parent.width
                        text: action.blurb
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                        elide: Text.ElideRight
                    }
                }

                StyledRect {
                    id: actionButton

                    anchors.right: parent.right
                    anchors.rightMargin: win.tok.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: actionLabel.implicitWidth + win.tok.padding.large * 2
                    implicitHeight: 26
                    radius: Tokens.rounding.full
                    color: actionHover.containsMouse ? Colours.palette.m3primary
                                                     : Colours.palette.m3surfaceContainerHighest

                    Behavior on color {
                        CAnim {}
                    }

                    StyledText {
                        id: actionLabel

                        anchors.centerIn: parent
                        text: action.button
                        font: Tokens.font.label.small
                        color: actionHover.containsMouse ? Colours.palette.m3onPrimary
                                                         : Colours.palette.m3onSurfaceVariant
                    }

                    MouseArea {
                        id: actionHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: action.triggered()
                    }
                }
            }
        }
    }
}
