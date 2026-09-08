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
        readonly property var apps: {
            const seen = {};
            const out = [];
            for (const t of (Hypr.toplevels?.values ?? [])) {
                const o = t.lastIpcObject;
                if (!o || !o.class)
                    continue;
                const found = seen[o.class];
                if (found) {
                    found.count += 1;
                    continue;
                }
                const entry = {
                    "cls": o.class,
                    "count": 1,
                    "address": o.address ?? "",
                    "title": o.title ?? o.class
                };
                seen[o.class] = entry;
                out.push(entry);
            }
            return out;
        }

        readonly property bool shown: Config.dock.enabled && (win.apps.length > 0 || !Config.dock.hideWhenEmpty)

        screen: modelData
        name: "genesi-dock"
        visible: Config.dock.enabled

        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"

        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        implicitHeight: Config.dock.iconSize + Config.dock.padding * 2 + Tokens.padding.medium * 2

        // Only the bar itself takes input. Without this the window is a strip
        // across the bottom of every screen that swallows clicks meant for the
        // window underneath it -- which is the bottom edge of every maximised
        // window there is.
        mask: Region {
            item: bar
        }

        StyledRect {
            id: bar

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.padding.medium

            implicitWidth: row.implicitWidth + Config.dock.padding * 2
            implicitHeight: Config.dock.iconSize + Config.dock.padding * 2

            radius: Config.dock.radius
            // No bar is not the same as a bar at zero opacity: it also means no
            // border, which is the difference between icons floating on the
            // wallpaper and icons inside an invisible box with a lit edge.
            color: Config.dock.background ? Qt.alpha(Colours.palette.m3surfaceContainer, Math.max(0, Math.min(100, Config.dock.backgroundOpacity)) / 100) : "transparent"
            border.width: Config.dock.background ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            opacity: win.shown ? 1 : 0
            // Slid down as well as faded, so an empty dock leaves rather than
            // dissolves. It also means nothing is drawn under the pointer at
            // 1% opacity, waiting to be clicked by accident.
            y: win.shown ? 0 : Tokens.padding.medium + implicitHeight

            Behavior on opacity {
                Anim {}
            }
            Behavior on y {
                Anim {}
            }

            Row {
                id: row

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

                            width: Config.dock.iconSize + Tokens.padding.small * 2
                            height: Config.dock.iconSize

                            StyledRect {
                                anchors.fill: parent
                                radius: Math.min(Config.dock.iconRadius, height / 2)
                                color: area.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.1) : "transparent"

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

                                scale: area.containsMouse ? 1.12 : 1

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
                                onClicked: {
                                    if (slot.modelData.address)
                                        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", `address:${slot.modelData.address}`]);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
