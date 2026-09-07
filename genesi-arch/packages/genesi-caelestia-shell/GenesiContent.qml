// GENESI — an alternative body for the launcher panel.
//
// caelestia's launcher is a search field with a list stacked on top of it, sized
// to its content and slid up from the bottom edge. That is a good launcher and it
// stays the default. This is the other shape: a wide slab that lands in the
// middle of the screen carrying the wallpaper behind it, with the clock and the
// weather in its corners, the selection called out in a card of its own, and the
// results in two numbered columns.
//
// It is a WHOLE FILE Genesi owns rather than a patch against upstream's
// Content.qml, and that is deliberate. A layout this different expressed as a
// diff would rewrite almost every line of the file it applies to -- it would
// break on any upstream edit, and the break would be a build failure at best and
// a silently mangled launcher at worst. Wrapper.qml chooses between the two by
// `launcher.layout`, which is one assertable line in the patcher, and upstream's
// Content.qml is left exactly as it ships.
//
// ── What this file does NOT do ──────────────────────────────────────────────
//
// The launcher is not only an app list. `>` opens the action list, `>calc `
// evaluates, `>scheme ` and `>variant ` retint the desktop, `>wallpaper ` opens
// the picker. Those are five more state machines with their own delegates, and
// reimplementing them here to get two columns would be five more things to keep
// in step with upstream forever.
//
// So the grid below is for applications, which is the state a grid is actually
// for, and every other mode hands off to upstream's own ContentList, unchanged,
// in one column. A wallpaper picker is a row of thumbnails and a calculator is
// one line; neither wants two columns.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property var panels
    required property real maxHeight
    // The screen's width, handed down by Wrapper. This item cannot read it off
    // its parent: the parent is the Loader that sizes itself FROM this item, so
    // asking it how wide it is would be a binding loop with extra steps.
    required property real maxWidth

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge
    readonly property string prefix: GlobalConfig.launcher.actionPrefix

    // The grid is for APPLICATIONS. Everything behind the action prefix -- the
    // action list, the calculator, the scheme and variant pickers, the wallpaper
    // picker -- goes to upstream's ContentList untouched.
    //
    // The action list was in the grid for a while and came back out. An action's
    // `onClicked` is declared `function onClicked(list: AppList)` and reaches
    // into `list.search.text` and `list.visibilities`: it wants upstream's own
    // list object, by type. Handing it something else means either a type error
    // at the moment somebody presses Enter, or reimplementing its three branches
    // here and owning that copy forever. Neither is worth two columns on the one
    // mode that has twenty curated entries in it.
    readonly property bool gridMode: !search.text.startsWith(root.prefix)

    readonly property var currentEntry: gridMode ? (grid.currentEntry ?? null) : (fallback.item?.currentList?.currentItem?.modelData ?? null)

    readonly property int columns: root.gridMode ? Math.max(1, Math.min(3, Config.launcher.columns)) : 1
    readonly property int total: root.gridMode ? grid.count : (fallback.item?.currentList?.count ?? 0)
    readonly property int hidden: root.gridMode ? Math.max(0, grid.count - grid.shown) : 0

    // Where the picture stops: the header, plus the panel's padding above
    // it and the same again as breathing room below.
    readonly property real headerHeight: head.height + root.padding * 2

    implicitWidth: Math.max(560, Math.min(1180, root.maxWidth * 0.62))
    implicitHeight: body.implicitHeight + root.padding * 2

    // ── The wallpaper behind it ──────────────────────────────────────────────
    //
    // Clipped to the panel's own rounding, so the image stops where the blob
    // behind it does. Without the clip the picture is a hard rectangle sitting
    // inside a rounded panel, which is the one thing that makes a floating
    // window look pasted on.
    StyledClippingRect {
        id: art

        anchors.fill: parent
        radius: root.rounding
        color: "transparent"
        visible: Config.launcher.background !== ""

        // The picture is behind the HEADER by default, not behind the whole
        // panel. Behind everything it competes with the results -- twenty app
        // names over a photograph, each of them needing to stay readable, which
        // is what forces the scrim so dark that the picture stops being worth
        // having. Behind the prompt only, it is the thing you look at while you
        // type and the list below stays a list.
        //
        // The CLIP still covers the whole panel: it is what rounds the top
        // corners. Only the image and its scrim are the band, and their bottom
        // edge is a straight line, which is exactly the join this wants.
        //
        // The children below say `art.band`, not `parent.band`. A clipping
        // container is entitled to reparent what it is handed, and when one
        // does, `parent` is no longer the object holding the property: the
        // binding evaluates to undefined, an Image with no height falls back to
        // the size of the picture, and you get the wallpaper across the whole
        // panel with the rule drawn at the top. That is not hypothetical -- it
        // is what the first render of this showed.
        readonly property bool wholePanel: Config.launcher.backgroundExtent === "panel"
        readonly property real band: wholePanel ? height : root.headerHeight

        Image {
            id: bg

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: art.band
            // The live wallpaper when asked for it by name, a file path when
            // given one. Anything else -- including a path that does not
            // exist -- draws nothing rather than a broken-image glyph.
            source: {
                const b = Config.launcher.background;
                if (b === "")
                    return "";
                if (b === "wallpaper")
                    return Wallpapers.actualCurrent ? "file://" + Wallpapers.actualCurrent : "";
                return b.startsWith("/") ? "file://" + b : b;
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            // A launcher is opened and closed dozens of times an hour. Decoding
            // a 4K wallpaper at full size each time is the difference between
            // the panel appearing and the panel appearing eventually.
            sourceSize.width: root.implicitWidth
            visible: status === Image.Ready
        }

        // The scrim. Text over a photograph is unreadable at any single opacity
        // that also lets the photograph show, so this is the panel's own surface
        // colour at a configurable strength -- the picture reads as the panel's
        // ground, not as a picture with words on it.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: art.band
            color: Qt.alpha(Colours.palette.m3surface, Math.max(0, Math.min(100, Config.launcher.backgroundDim)) / 100)
        }

        // Where the picture stops. A photograph that simply ends is a seam;
        // a rule makes it an edge, and the dot at the end is the mark that
        // says the edge was drawn on purpose.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            y: art.band - 1
            height: 1
            visible: !art.wholePanel && bg.status === Image.Ready

            Rectangle {
                anchors.fill: parent
                color: Colours.palette.m3outlineVariant
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width * 0.82
                width: 5
                height: 5
                radius: 2.5
                color: Colours.palette.m3primary
            }
        }
    }

    Column {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: Tokens.spacing.medium

        // ── The header ───────────────────────────────────────────────────────
        //
        // Grouped rather than three siblings of the Column, because the picture
        // behind the panel has to know where it ends, and "the height of the
        // header" is a thing this Column can answer while three separate items
        // and the spacing between them is arithmetic somebody has to keep in
        // step by hand.
        Column {
            id: head

            width: parent.width
            spacing: parent.spacing

            // ── Clock and weather ────────────────────────────────────────────────
            Item {
                width: parent.width
                height: visible ? Math.max(clock.implicitHeight, weather.implicitHeight) : 0
                visible: Config.launcher.showClock || Config.launcher.showWeather

                StyledText {
                    id: clock

                    anchors.left: parent.left
                    anchors.top: parent.top
                    visible: Config.launcher.showClock

                    text: Time.format(GlobalConfig.services.useTwelveHourClock ? "h:mm A" : "hh:mm")
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                Column {
                    id: weather

                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 2
                    visible: Config.launcher.showWeather

                    Row {
                        anchors.right: parent.right
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.icon
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.temp
                            font: Tokens.font.body.large
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledText {
                        anchors.right: parent.right
                        text: Time.format("ddd, MMM d")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            // ── The prompt ───────────────────────────────────────────────────────
            //
            // An underline, not a filled pill. The pill is upstream's, and it is the
            // right shape for a field at the bottom of a small panel; on a slab this
            // wide it becomes a very long lozenge that reads as the main event. The
            // rule under the text says "type here" just as clearly and lets the card
            // below it be the thing you look at.
            Item {
                width: parent.width
                height: searchRow.implicitHeight + Tokens.padding.small * 2 + 2

                Row {
                    id: searchRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: root.padding
                    anchors.rightMargin: root.padding
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        id: searchIcon

                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: search.text ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium

                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StyledTextField {
                        id: search

                        width: parent.width - parent.spacing - searchIcon.implicitWidth
                        topPadding: Tokens.padding.small
                        bottomPadding: Tokens.padding.small

                        font: Tokens.font.body.large
                        placeholderText: qsTr("Search, or type \"%1\" for commands").arg(root.prefix)

                        onAccepted: root.activate()

                        Keys.onUpPressed: root.move(-root.columns)
                        Keys.onDownPressed: root.move(root.columns)
                        Keys.onLeftPressed: event => {
                            // Only steal Left/Right when there is more than one
                            // column to move between. In one column they are what
                            // moves the caret, and taking that away from a text
                            // field is the kind of thing nobody reports and
                            // everybody hates.
                            if (root.columns > 1 && root.gridMode) {
                                root.move(-1);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                        Keys.onRightPressed: event => {
                            if (root.columns > 1 && root.gridMode) {
                                root.move(1);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                        Keys.onEscapePressed: root.visibilities.launcher = false

                        Keys.onPressed: event => {
                            if (!GlobalConfig.launcher.vimKeybinds)
                                return;
                            if (event.modifiers & Qt.ControlModifier) {
                                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                                    root.move(root.columns);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                                    root.move(-root.columns);
                                    event.accepted = true;
                                }
                            } else if (event.key === Qt.Key_Tab) {
                                root.move(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Backtab) {
                                root.move(-1);
                                event.accepted = true;
                            }
                        }

                        Component.onCompleted: forceActiveFocus()

                        Connections {
                            function onLauncherChanged(): void {
                                if (!root.visibilities.launcher)
                                    search.text = "";
                            }

                            function onSessionChanged(): void {
                                if (!root.visibilities.session)
                                    search.forceActiveFocus();
                            }

                            target: root.visibilities
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: root.padding
                    anchors.rightMargin: root.padding
                    height: 2
                    radius: 1
                    color: search.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            // ── The filters ──────────────────────────────────────────────────────
            //
            // Not a taxonomy of results -- the launcher has no categories to filter
            // by. These are the modes it already has, which you otherwise reach only
            // by knowing that ">" and ">wallpaper " are things you can type. A row
            // of buttons is how you find out.
            Item {
                width: parent.width
                height: visible ? chips.implicitHeight : 0
                visible: Config.launcher.showChips

                Row {
                    id: chips

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { name: qsTr("APPS"), text: "" },
                            { name: qsTr("ACTIONS"), text: root.prefix },
                            { name: qsTr("SCHEMES"), text: root.prefix + "scheme " },
                            { name: qsTr("WALLPAPERS"), text: root.prefix + "wallpaper " }
                        ]

                        StyledRect {
                            id: chip

                            required property var modelData

                            // "In this mode" is not "the text is exactly this": with
                            // "chromium" typed you are still in APPS, and having no
                            // chip lit while you type is what makes a row of filters
                            // look broken.
                            readonly property bool on: modelData.text === "" ? !search.text.startsWith(root.prefix) : search.text.startsWith(modelData.text)

                            implicitWidth: chipText.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: chipText.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: chip.on ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainer

                            Behavior on color {
                                CAnim {}
                            }

                            StyledText {
                                id: chipText

                                anchors.centerIn: parent
                                text: chip.modelData.name
                                font: Tokens.font.label.medium
                                color: chip.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            }

                            StateLayer {
                                radius: parent.radius
                                onClicked: {
                                    search.text = chip.modelData.text;
                                    search.cursorPosition = search.text.length;
                                    search.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── The selection, called out ────────────────────────────────────────
        //
        // The row you are about to launch is also a row in the list, which means
        // the only thing telling you what Enter does is a faint highlight behind
        // one line of twenty. This says it in full: the icon at a size you can
        // actually recognise, the name, what kind of thing it is, and the key.
        StyledRect {
            id: hero

            width: parent.width
            implicitHeight: visible ? Math.max(heroIcon.implicitSize, heroText.implicitHeight) + root.padding * 2 : 0
            visible: Config.launcher.showHero && root.currentEntry !== null
            radius: Tokens.rounding.large
            color: Colours.palette.m3primaryContainer

            IconImage {
                id: heroIcon

                anchors.left: parent.left
                anchors.leftMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter

                asynchronous: true
                implicitSize: 44
                // Applications carry an icon THEME name and want a path lookup;
                // everything upstream's list holds carries a Material Symbols
                // name and wants a glyph. Which one this is comes from the mode,
                // not from poking at the model: a DesktopEntry has a `command`
                // too, so "does it have a command" answers the wrong question.
                source: root.gridMode && root.currentEntry ? Quickshell.iconPath(root.currentEntry.icon, "image-missing") : ""
                visible: root.gridMode && source !== ""
            }

            MaterialIcon {
                anchors.centerIn: heroIcon
                visible: !heroIcon.visible && root.currentEntry !== null
                text: root.currentEntry?.icon ?? "help"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.extraLarge
            }

            Column {
                id: heroText

                anchors.left: heroIcon.right
                anchors.leftMargin: root.padding
                anchors.right: heroKeys.left
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    width: parent.width
                    text: root.currentEntry?.name ?? ""
                    font: Tokens.font.title.medium
                    color: Colours.palette.m3onPrimaryContainer
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: {
                        const e = root.currentEntry;
                        if (!e)
                            return "";
                        const kind = root.gridMode ? qsTr("APP") : qsTr("COMMAND");
                        const what = e.comment || e.genericName || e.desc || e.description || "";
                        return what ? kind + "  /  " + what : kind;
                    }
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onPrimaryContainer
                    opacity: 0.75
                    elide: Text.ElideRight
                }
            }

            Column {
                id: heroKeys

                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    anchors.right: parent.right
                    text: qsTr("LAUNCH")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onPrimaryContainer
                }
                StyledText {
                    anchors.right: parent.right
                    text: qsTr("↵ ENTER")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onPrimaryContainer
                    opacity: 0.7
                }
                StyledText {
                    anchors.right: parent.right
                    // The honest version of "+2 more": the number of results
                    // that did not fit. An invented keyboard shortcut printed on
                    // a card is a promise the launcher does not keep.
                    text: root.hidden > 0 ? qsTr("+%1 MORE").arg(root.hidden) : qsTr("%1 RESULTS").arg(root.total)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onPrimaryContainer
                    opacity: 0.5
                    visible: root.total > 0
                }
            }
        }

        // ── The results ──────────────────────────────────────────────────────
        Item {
            id: results

            width: parent.width
            implicitHeight: root.gridMode ? grid.implicitHeight : (fallback.item?.implicitHeight ?? 0)

            GenesiAppGrid {
                id: grid

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                visible: root.gridMode
                enabled: visible
                search: search
                visibilities: root.visibilities
                columns: root.columns
                rounding: Tokens.rounding.large
            }

            Loader {
                id: fallback

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                // Loaded the first time a mode that needs it is entered, and
                // kept afterwards. `active: !root.gridMode` alone would rebuild
                // upstream's whole list every time you delete the ">".
                active: false
                visible: !root.gridMode

                sourceComponent: ContentList {
                    content: root
                    visibilities: root.visibilities
                    panels: root.panels
                    maxHeight: root.maxHeight * 0.7
                    search: search
                    padding: root.padding
                    rounding: root.rounding
                }
            }
        }
    }

    onGridModeChanged: if (!gridMode)
        fallback.active = true

    // ── Selection plumbing ───────────────────────────────────────────────────
    function move(by: int): void {
        if (root.gridMode) {
            grid.moveBy(by);
            return;
        }

        const list = fallback.item?.currentList;
        if (!list)
            return;
        if (by > 0)
            list.incrementCurrentIndex();
        else
            list.decrementCurrentIndex();
    }

    function activate(): void {
        if (root.gridMode) {
            grid.activateCurrent();
            return;
        }

        // Upstream's own accept path, kept identical: these modes are its code
        // and its expectations about what Enter does in them.
        const list = fallback.item?.currentList;
        const currentItem = list?.currentItem;
        if (!currentItem)
            return;

        if (fallback.item?.showWallpapers) {
            if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                Wallpapers.previewColourLock = true;
            Wallpapers.setWallpaper(currentItem.modelData.path);
            root.visibilities.launcher = false;
        } else if (search.text.startsWith(root.prefix + "calc ")) {
            currentItem.onClicked();
        } else {
            currentItem.modelData.onClicked(list);
        }
    }
}
