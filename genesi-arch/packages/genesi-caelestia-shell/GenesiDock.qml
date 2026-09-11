// GENESI — the dock.
//
// What is open, as icons, along the bottom edge. caelestia has a bar and it is
// a vertical rail showing workspaces; this is the other thing, in the place
// Windows and macOS have taught everyone to look for it.
//
// ── The flow ────────────────────────────────────────────────────────────────
//
// Between one icon and the next there is a track with three lights running
// along it. It is decoration and it is the point: a row of icons on a black
// strip is a row of icons, and the thing that makes a dock feel like part of a
// desktop rather than a list of processes is that it moves.
//
// They are staggered, and the stagger is per GAP rather than per light --
// every gap pulsing in unison reads as a progress bar, and a progress bar that
// never finishes is a worse thing to put on somebody's screen than nothing.
//
// ── Grouped by application, not one icon per window ─────────────────────────
//
// Six terminals are one icon with a six on it. A dock that grows an icon per
// window is a dock that is unusable on the day you need it most.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        // One entry per application class, in the order they were opened.
        // `lastIpcObject` is where Hyprland's own fields live -- the class and
        // the address are both there, and the address is what focuses it.
        // Pinned applications FIRST and always, then everything else that is
        // running. Pinned order is the order they were pinned in, because for
        // a dock the arrangement is the setting -- a pinned list that sorted
        // itself would move the icon you aim at without being asked.
        //
        // A pinned application that IS running is one entry, not two: it keeps
        // its place in the pinned order and gains the running mark and the
        // window count.
        readonly property var apps: {
            const seen = {};
            const out = [];
            for (const cls of (win.cfg.pinned ?? [])) {
                if (seen[cls])
                    continue;
                const entry = {
                    "cls": cls,
                    "count": 0,
                    "address": "",
                    "title": cls,
                    "pinned": true
                };
                seen[cls] = entry;
                out.push(entry);
            }
            for (const t of (Hypr.toplevels?.values ?? [])) {
                const o = t.lastIpcObject;
                if (!o || !o.class)
                    continue;
                const found = seen[o.class];
                if (found) {
                    found.count += 1;
                    // The first window found is the one a click focuses. A
                    // pinned entry starts with no address, so this is also
                    // what turns it from "launch" into "focus".
                    if (!found.address)
                        found.address = o.address ?? "";
                    continue;
                }
                const entry = {
                    "cls": o.class,
                    "count": 1,
                    "address": o.address ?? "",
                    "title": o.title ?? o.class,
                    "pinned": false
                };
                seen[o.class] = entry;
                out.push(entry);
            }
            return out;
        }

        readonly property var cfg: contentItem.Config.dock
        readonly property bool atBottom: win.cfg.edge !== "top"

        // ── How it is drawn ─────────────────────────────────────────────
        //
        //   bar      one rounded surface behind every icon (the default)
        //   islands  each icon on a surface of its own, no shared bar
        //   rail     a strip the width of the screen, flush to its edge
        //   seal     one surface with fully round ends
        //
        // A style is a NAME rather than three more switches, because "bar" and
        // "islands" and "rail" are mutually exclusive and three booleans can
        // be set to a combination that means nothing.
        readonly property string style: win.cfg.style
        readonly property bool tiles: win.style === "islands"
        readonly property bool rail: win.style === "rail"
        readonly property bool seal: win.style === "seal"

        // ── Frost ───────────────────────────────────────────────────────
        //
        // Blur behind the dock, which Hyprland does and Qt cannot: a layer
        // surface has no way to read what is under it. Same mechanism as the
        // bar's, on this window's own namespace, and `unset` is the way back
        // because there is no negative form of a layerrule.
        readonly property string ns: "caelestia-genesi-dock"
        readonly property bool frost: win.cfg.frost

        function applyFrost(): void {
            if (win.frost) {
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `blur,${win.ns}`]);
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `ignorezero,${win.ns}`]);
            } else {
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `unset,${win.ns}`]);
            }
        }

        onFrostChanged: win.applyFrost()
        Component.onCompleted: win.applyFrost()

        property bool peek: false

        // The media chip's player card. On the window rather than on the chip
        // because the input mask has to know about it, and the mask is a
        // property of the window.
        property bool playerOpen: false

        // Three separate reasons to be out of view, and they are not the same
        // thing: nothing is open, auto-hide is on and the pointer is elsewhere,
        // or the dock is off entirely.
        onShownChanged: if (!win.shown)
            win.playerOpen = false

        readonly property bool shown: win.cfg.enabled
            && (win.apps.length > 0 || !win.cfg.hideWhenEmpty)
            && (!win.cfg.autoHide || win.peek)

        screen: modelData
        name: "genesi-dock"
        visible: Config.dock.enabled

        // Normal, not Ignore, with a zone of zero: it RESPECTS what other
        // surfaces have reserved -- which is how a dock on the top edge ends
        // up below the bar instead of underneath it -- while reserving
        // nothing itself, because a dock is something you point at and a
        // window should be allowed to go behind it.
        //
        // `exclusiveZone: 0` is not optional here. Left unset, Normal derives
        // a zone from the anchors and the dock would reserve its own height.
        WlrLayershell.exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"

        anchors.bottom: win.atBottom
        anchors.top: !win.atBottom
        anchors.left: true
        anchors.right: true
        // Room ABOVE the dock for what is drawn above it: the hover label
        // and the media chip's player card. A layer surface clips its own
        // contents, and everything outside this height is simply gone -- the
        // label came back with its top half missing, and the card lost its
        // whole transport row, which is why none of it could be clicked.
        //
        // Sized from the card rather than chosen: the card's height is a
        // column of text and a picture, and a number picked by eye is a
        // number that stops being right the first time a font changes.
        readonly property int headroom: card.implicitHeight
            + contentItem.Tokens.spacing.large * 2

        implicitHeight: win.cfg.iconSize + win.cfg.padding * 2 + contentItem.Tokens.padding.medium * 2 + win.headroom

        // Only the bar itself takes input. Without this the window is a strip
        // across the bottom of every screen that swallows clicks meant for the
        // window underneath it -- which is the bottom edge of every maximised
        // window there is.
        //
        // GEOMETRY, not `item: bar`. Every Region in caelestia is written this
        // way and not one of them names an item, which is the only evidence
        // available for what this Quickshell accepts -- and a property that
        // does not exist does not fail quietly here: the whole file fails to
        // load, and the dock never appears at all. That is what shipped.
        // The strip the pointer has to reach to bring an auto-hidden dock
        // back: the dock's own thickness at its edge, and not a pixel more.
        // `win.height` would have been right when the window was exactly as
        // tall as the dock; with headroom above it for hover labels it is a
        // 220-pixel-deep bite out of every window along that edge.
        readonly property int revealBand: win.cfg.iconSize + win.cfg.padding * 2
            + contentItem.Tokens.padding.medium * 2

        mask: Region {
            // With the player open the whole window takes input: the card is
            // drawn in the headroom above the dock and a click anywhere else
            // in here is how you dismiss it. Working out the card's rectangle
            // from the window would mean naming a geometry that lives four
            // items deep, and the window is only as wide as the screen and as
            // tall as the dock plus its headroom.
            x: win.playerOpen ? 0 : (win.cfg.autoHide ? 0 : bar.x)
            y: win.playerOpen ? 0 : (win.cfg.autoHide
                ? (win.atBottom ? win.height - win.revealBand : 0)
                : bar.y)
            width: win.playerOpen ? win.width
                : (win.cfg.autoHide ? win.width : bar.width)
            height: win.playerOpen ? win.height
                : (win.cfg.autoHide ? win.revealBand : bar.height)
        }

        // Under the card, over everything else: a click that misses the card
        // puts it away.
        MouseArea {
            anchors.fill: parent
            enabled: win.playerOpen
            onClicked: win.playerOpen = false
        }

        // ── Auto-hide ────────────────────────────────────────────────────
        //
        // A HoverHandler, not a MouseArea, for the reason the bar's is: a
        // MouseArea reports the pointer has LEFT as soon as it moves onto a
        // child that takes hover, and every icon does. Reaching for one hid
        // the dock, which moved it away, which brought the dock back.
        HoverHandler {
            enabled: win.cfg.autoHide
            onHoveredChanged: win.peek = hovered
        }

        StyledRect {
            id: bar

            // A rail spans the screen; every other style is as wide as
            // what is in it. `undefined` on the centre anchor rather than
            // false: an anchor that is set and an anchor that is not are
            // different states, and setting both a centre and two edges is
            // how an item ends up with a width nobody asked for.
            anchors.horizontalCenter: win.rail ? undefined : parent.horizontalCenter
            anchors.left: win.rail ? parent.left : undefined
            anchors.right: win.rail ? parent.right : undefined
            anchors.bottom: win.atBottom ? parent.bottom : undefined
            anchors.top: win.atBottom ? undefined : parent.top
            // The slide rides the MARGIN, not y. An item anchored to its
            // parent's bottom has its y set by that anchor, so a `y:` binding
            // on the same item is a second thing assigning one property -- the
            // anchor wins and the animation silently does nothing. Same shape
            // the launcher's Wrapper uses.
            // A rail is flush to its edge, so the margin it rests at is
            // zero rather than a padding.
            readonly property real restMargin: win.rail ? 0 : Tokens.padding.medium

            anchors.bottomMargin: win.shown
                ? bar.restMargin
                : -(implicitHeight + Tokens.padding.medium)
            anchors.topMargin: win.shown
                ? bar.restMargin
                : -(implicitHeight + Tokens.padding.medium)

            Behavior on anchors.bottomMargin {
                Anim {}
            }
            Behavior on anchors.topMargin {
                Anim {}
            }

            implicitWidth: row.implicitWidth + Config.dock.padding * 2
            implicitHeight: Config.dock.iconSize + Config.dock.padding * 2

            // `seal` is round ends whatever the corner setting says -- that is
            // what the style IS -- and a rail flush to the edge has nothing to
            // round on the side it is flush with.
            radius: win.seal ? implicitHeight / 2
                             : (win.rail ? 0 : Config.dock.radius)

            // No bar is not the same as a bar at zero opacity: it also means no
            // border, which is the difference between icons floating on the
            // wallpaper and icons inside an invisible box with a lit edge.
            //
            // The `islands` style has no shared surface at all: each icon
            // carries its own, so this one steps out of the way rather than
            // being drawn behind them at a lower opacity.
            color: (Config.dock.background && !win.tiles) ? Qt.alpha(Colours.palette.m3surfaceContainer, Math.max(0, Math.min(100, Config.dock.backgroundOpacity)) / 100) : "transparent"
            border.width: (win.cfg.background && !win.tiles) ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            // Slid down as well as faded, so an empty dock leaves rather than
            // dissolves. It also means nothing is drawn under the pointer at
            // 1% opacity, waiting to be clicked by accident.
            opacity: win.shown ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            // Where the pointer is along the row, which is what magnification
            // is a function of. hoverEnabled with NoButton: it reports
            // position and takes nothing, so every click still reaches the
            // icon underneath.
            MouseArea {
                anchors.fill: row
                enabled: win.cfg.magnify
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onPositionChanged: e => row.pointerX = e.x
                onContainsMouseChanged: row.hovering = containsMouse
            }

            Row {
                id: row

                property real pointerX: 0
                property bool hovering: false

                anchors.centerIn: parent
                spacing: 0

                Repeater {
                    model: win.apps

                    Row {
                        id: slot

                        required property var modelData
                        required property int index

                        spacing: 0

                        // The gap before every icon but the first. Putting it
                        // here rather than between two Repeaters is what keeps
                        // the flow in step with the icons when one closes.
                        Item {
                            width: slot.index === 0 ? 0 : Config.dock.spacing
                            height: Config.dock.iconSize
                            visible: slot.index > 0

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 2
                                height: 2
                                radius: 1
                                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
                            }

                            Repeater {
                                model: Config.dock.flow ? 3 : 0

                                Rectangle {
                                    id: light

                                    required property int index

                                    width: 4
                                    height: 4
                                    radius: 2
                                    y: (parent.height - height) / 2
                                    color: Colours.palette.m3primary

                                    SequentialAnimation {
                                        running: true
                                        loops: Animation.Infinite

                                        // Per GAP, not per light: every gap
                                        // pulsing together reads as one bar
                                        // filling, which is a progress bar that
                                        // never finishes.
                                        PauseAnimation {
                                            duration: slot.index * 260 + light.index * 340
                                        }
                                        ParallelAnimation {
                                            NumberAnimation {
                                                target: light
                                                property: "x"
                                                from: 0
                                                to: Math.max(0, light.parent.width - light.width)
                                                duration: 1400
                                                easing.type: Easing.InOutSine
                                            }
                                            SequentialAnimation {
                                                NumberAnimation {
                                                    target: light
                                                    property: "opacity"
                                                    from: 0
                                                    to: 1
                                                    duration: 300
                                                }
                                                NumberAnimation {
                                                    target: light
                                                    property: "opacity"
                                                    from: 1
                                                    to: 0
                                                    duration: 1100
                                                }
                                            }
                                        }
                                        PauseAnimation {
                                            duration: 900
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: tile

                            // How near the pointer is, 0 at two icons away and
                            // 1 under it. The neighbours grow too, less --
                            // magnification that only lifts the icon under the
                            // cursor reads as a click, not as a dock.
                            readonly property real nearness: {
                                if (!win.cfg.magnify || !row.hovering)
                                    return 0;
                                const mine = tile.x + tile.width / 2
                                    + slot.x + row.x;
                                const d = Math.abs(row.pointerX - mine);
                                const reach = win.cfg.iconSize * 2.2;
                                return d > reach ? 0 : 1 - d / reach;
                            }

                            width: Config.dock.iconSize + Tokens.padding.small * 2
                            height: Config.dock.iconSize

                            // The tile's own surface. Transparent under
                            // every style but `islands`, where it is the only
                            // surface there is -- the shared bar has stepped
                            // out of the way for exactly this.
                            StyledRect {
                                anchors.fill: parent
                                radius: Math.min(Config.dock.iconRadius, height / 2)
                                color: area.containsMouse
                                    ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                                    : ((win.tiles && Config.dock.background)
                                       ? Qt.alpha(Colours.palette.m3surfaceContainer, Math.max(0, Math.min(100, Config.dock.backgroundOpacity)) / 100)
                                       : "transparent")
                                border.width: (win.tiles && Config.dock.background) ? 1 : 0
                                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

                                Behavior on color {
                                    CAnim {}
                                }
                            }

                            ClippingRectangle {
                                id: icon

                                anchors.centerIn: parent
                                implicitWidth: Config.dock.iconSize - Tokens.padding.small
                                implicitHeight: implicitWidth
                                color: "transparent"
                                // Clamped to a circle at most: a radius larger
                                // than half the icon is not rounder, it is the
                                // same circle with a number nobody can explain.
                                radius: Math.min(Config.dock.iconRadius, implicitWidth / 2)

                                // Magnification when it is on, a plain hover
                                // lift when it is not.
                                scale: win.cfg.magnify
                                       ? 1 + tile.nearness * 0.45
                                       : (area.containsMouse ? 1.12 : 1)
                                transformOrigin: win.atBottom ? Item.Bottom : Item.Top

                                Behavior on scale {
                                    Anim {}
                                }

                                IconImage {
                                    anchors.fill: parent
                                    asynchronous: true
                                    implicitSize: parent.implicitWidth
                                    source: Quickshell.iconPath(slot.modelData.cls.toLowerCase(), "application-x-executable")
                                }
                            }

                            // The application's name while the pointer is on
                            // it. Drawn OUTSIDE the tile, so it is not clipped
                            // by an icon-sized box, and on the side away from
                            // the screen edge.
                            StyledRect {
                                id: hoverLabel

                                visible: win.cfg.hoverLabels && area.containsMouse
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: win.atBottom ? parent.top : undefined
                                anchors.top: win.atBottom ? undefined : parent.bottom
                                anchors.margins: Tokens.spacing.small
                                z: 10
                                implicitWidth: hoverText.implicitWidth + Tokens.padding.large * 2
                                implicitHeight: hoverText.implicitHeight + Tokens.padding.small * 2
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3surfaceContainerHighest
                                border.width: 1
                                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                                StyledText {
                                    id: hoverText

                                    anchors.centerIn: parent
                                    text: slot.modelData.cls
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurface
                                }
                            }

                            // A dot under a pinned application that is running.
                            // Pinned and running look identical otherwise, and
                            // "is this thing open" is the question a dock is
                            // most often asked.
                            StyledRect {
                                visible: slot.modelData.pinned && slot.modelData.count > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: win.atBottom ? parent.bottom : undefined
                                anchors.top: win.atBottom ? undefined : parent.top
                                implicitWidth: 4
                                implicitHeight: 4
                                radius: 2
                                color: Colours.palette.m3primary
                            }

                            // How many windows this application has. Only from
                            // two: a "1" on every icon is a row of ones.
                            StyledRect {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                visible: slot.modelData.count > 1
                                implicitWidth: countText.implicitWidth + 8
                                implicitHeight: 14
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary

                                StyledText {
                                    id: countText

                                    anchors.centerIn: parent
                                    text: slot.modelData.count
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onPrimary
                                }
                            }

                            MouseArea {
                                id: area

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Focus it if it is running, start it if it
                                // is only pinned. A pinned icon that did
                                // nothing until you had already opened the app
                                // by other means would be a bookmark, not a
                                // dock.
                                onClicked: {
                                    if (slot.modelData.address) {
                                        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", `address:${slot.modelData.address}`]);
                                        return;
                                    }
                                    Quickshell.execDetached(
                                        ["app2unit", "--", slot.modelData.cls]);
                                }
                            }
                        }
                    }
                }

                // ── What is playing ─────────────────────────────────────
                //
                // A dock is where you go to get back to something, and for
                // the last hour of most days that something is whatever is
                // making noise. The chip is part of the ROW rather than a
                // separate window: it moves with the dock, hides with it and
                // is magnified by the same pointer.
                //
                // Off when nothing has a title, which is not the same as no
                // player -- a browser tab that once played something keeps an
                // MPRIS object with an empty track for as long as it is open,
                // and a dock chip reading nothing is a hole in the dock.
                Row {
                    id: media

                    readonly property var player: Players.active
                    readonly property bool playing: media.player?.isPlaying ?? false
                    readonly property string title: media.player?.trackTitle ?? ""

                    spacing: 0
                    visible: win.cfg.media && media.title !== ""
                        && (!win.cfg.mediaOnlyWhenPlaying || media.playing)

                    Item {
                        width: Config.dock.spacing
                        height: Config.dock.iconSize

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 2
                            height: 2
                            radius: 1
                            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
                        }
                    }

                    StyledRect {
                        id: chip

                        implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: Config.dock.iconSize
                        radius: Math.min(Config.dock.iconRadius, implicitHeight / 2)
                        color: chipArea.containsMouse
                            ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                            : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)

                        Behavior on color {
                            CAnim {}
                        }

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            ClippingRectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Config.dock.mediaArt
                                implicitWidth: Config.dock.iconSize - Tokens.padding.medium
                                implicitHeight: implicitWidth
                                radius: Math.min(Config.dock.iconRadius, implicitWidth / 2)
                                color: Colours.palette.m3surfaceContainerHigh

                                Image {
                                    id: art

                                    anchors.fill: parent
                                    source: media.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: !art.visible
                                    text: "music_note"
                                    color: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.small
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                // Capped rather than sized to the title: a
                                // dock that changes width with the song is a
                                // dock whose icons move while you aim at one.
                                width: Math.min(implicitWidth, 150)
                                text: media.title
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: media.playing ? "pause" : "play_arrow"
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.small
                            }
                        }

                        // ── The player ──────────────────────────────
                        //
                        // A child of the chip, so it follows the chip along
                        // the row without anchoring across parents, and drawn
                        // outside it -- which works because nothing here
                        // clips until the window, and the window was given
                        // headroom for exactly this and the hover labels.
                        StyledRect {
                            id: card

                            z: 100
                            visible: win.playerOpen && media.title !== ""
                            opacity: win.playerOpen ? 1 : 0

                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: win.atBottom ? parent.top : undefined
                            anchors.top: win.atBottom ? undefined : parent.bottom
                            anchors.margins: Tokens.spacing.medium

                            implicitWidth: 250
                            implicitHeight: cardCol.implicitHeight
                                + Tokens.padding.large * 2
                            radius: Tokens.rounding.large
                            color: Colours.palette.m3surfaceContainer
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                            Behavior on opacity {
                                Anim {}
                            }

                            // Its own, so a click on the card does not reach
                            // the dismiss area underneath it.
                            MouseArea {
                                anchors.fill: parent
                            }

                            Column {
                                id: cardCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.padding.large
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: qsTr("NOW PLAYING")
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3outline
                                }

                                ClippingRectangle {
                                    width: parent.width
                                    // Capped: the card is 250 wide and the
                                    // art at its natural ratio is most of
                                    // the height, which pushed the controls
                                    // out of the window.
                                    implicitHeight: Math.min(width * 0.62, 120)
                                    radius: Tokens.rounding.small
                                    color: Colours.palette.m3surfaceContainerHigh

                                    Image {
                                        id: cardArt

                                        anchors.fill: parent
                                        source: media.player?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: !cardArt.visible
                                        text: "music_note"
                                        color: Colours.palette.m3onSurfaceVariant
                                        fontStyle: Tokens.font.icon.large
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: media.title
                                    font: Tokens.font.body.large
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    visible: text !== ""
                                    text: media.player?.trackArtist ?? ""
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }

                                // How far through, as a line. A slider here
                                // would be a control that has to be dragged
                                // accurately on a card 250 wide.
                                Rectangle {
                                    width: parent.width
                                    height: 3
                                    radius: 2
                                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

                                    Rectangle {
                                        readonly property real len:
                                            media.player?.length ?? 0

                                        anchors.left: parent.left
                                        height: parent.height
                                        radius: parent.radius
                                        width: parent.width * (len > 0
                                            ? Math.max(0, Math.min(1,
                                                (media.player?.position ?? 0) / len))
                                            : 0)
                                        color: Colours.palette.m3primary
                                    }
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Tokens.spacing.large
                                    topPadding: Tokens.spacing.extraSmall

                                    Control {
                                        icon: "skip_previous"
                                        onTriggered: media.player?.previous()
                                    }

                                    Control {
                                        icon: media.playing ? "pause" : "play_arrow"
                                        accent: true
                                        onTriggered: media.player?.togglePlaying()
                                    }

                                    Control {
                                        icon: "skip_next"
                                        onTriggered: media.player?.next()
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // Left plays or pauses, right opens the dashboard
                            // where the whole player is. A chip this size can
                            // carry one control honestly; the rest belongs
                            // somewhere with room for it.
                            // Left opens the player, right plays or pauses
                            // without opening anything. A chip this size can
                            // carry one control honestly; the rest of them go
                            // on the card.
                            onClicked: e => {
                                if (e.button === Qt.RightButton) {
                                    media.player?.togglePlaying();
                                    return;
                                }
                                win.playerOpen = !win.playerOpen;
                            }
                        }
                    }
                }
            }
        }

        // A round transport button. Declared at window level so the card can
        // use it three times without three copies of the same twenty lines.
        component Control: StyledRect {
            id: control

            property string icon: ""
            property bool accent: false

            signal triggered

            implicitWidth: 32
            implicitHeight: 32
            radius: Tokens.rounding.full
            color: control.accent
                ? Colours.palette.m3primary
                : (controlHover.containsMouse
                   ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                   : "transparent")

            Behavior on color {
                CAnim {}
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: control.icon
                color: control.accent ? Colours.palette.m3onPrimary
                                      : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.small
            }

            MouseArea {
                id: controlHover

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: control.triggered()
            }
        }
    }
}
