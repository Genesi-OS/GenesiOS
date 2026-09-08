// GENESI — the desktop's own menu.
//
// Right-click the wallpaper: every widget with a tick beside the ones that are
// on, a switch for arrange mode, and the two things people go looking for right
// after ("where do I change this properly" and "give me another wallpaper").
//
// It exists because the alternative is that a desktop widget can only be turned
// on from a settings app, and nobody opens a settings app to try something out.
// Genesi Center is still where the details live -- position, size, the lot --
// and this menu says so by having an entry that opens it.
//
// ── It closes on anything ───────────────────────────────────────────────────
//
// Escape, a click outside, and picking an item all close it. A menu on the
// desktop that needs to be dismissed a particular way is a menu somebody leaves
// open by accident and then finds under their windows.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var defs
    property bool arranging: false

    signal toggle(string name)
    signal arrange

    // Names for the menu. The widget's config key is not a label: "analogClock"
    // is a fine identifier and a poor thing to read at four in the afternoon.
    readonly property var labels: ({
            "weather": qsTr("Weather"),
            "forecast": qsTr("Forecast"),
            "media": qsTr("Now playing"),
            "cpu": qsTr("Processor"),
            "memory": qsTr("Memory"),
            "storage": qsTr("Storage"),
            "network": qsTr("Network"),
            "battery": qsTr("Battery"),
            "calendar": qsTr("Calendar"),
            "analogClock": qsTr("Analogue clock"),
            "workspaces": qsTr("Workspaces"),
            "notifications": qsTr("Notifications"),
            "uptime": qsTr("Uptime"),
            "greeting": qsTr("Greeting")
        })

    anchors.fill: parent
    visible: card.opacity > 0

    function openAt(x: real, y: real): void {
        // Kept inside the screen. A menu opened near the right edge that runs
        // off it is a menu whose last three items do not exist.
        card.x = Math.max(8, Math.min(x, root.width - card.width - 8));
        card.y = Math.max(8, Math.min(y, root.height - card.height - 8));
        card.opacity = 1;
        card.forceActiveFocus();
    }

    function close(): void {
        card.opacity = 0;
    }

    // Anywhere else closes it. Declared BEFORE the card so the card is on top
    // of it -- otherwise this eats the clicks meant for the menu's own items.
    MouseArea {
        anchors.fill: parent
        enabled: card.opacity > 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.close()
    }

    StyledRect {
        id: card

        implicitWidth: 236
        implicitHeight: col.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

        opacity: 0
        focus: true

        Behavior on opacity {
            Anim {}
        }

        Keys.onEscapePressed: root.close()

        // The card swallows its own clicks so the dismisser behind it does not
        // see them. Without this, every pick closes the menu twice: once by the
        // item and once by the background, and the second one wins.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        Column {
            id: col

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.small

            StyledText {
                x: Tokens.padding.medium
                height: 26
                verticalAlignment: Text.AlignVCenter
                text: qsTr("WIDGETS")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }

            Repeater {
                model: root.defs

                Row {
                    id: entry

                    required property var modelData

                    readonly property bool on: Config.background.widgets[entry.modelData.name]?.enabled ?? false

                    width: col.width
                    height: 26
                    spacing: Tokens.spacing.small

                    StyledRect {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: entry.width
                        implicitHeight: entry.height
                        radius: Tokens.rounding.small
                        color: hover.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        MaterialIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.padding.small
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.on ? "check_box" : "check_box_outline_blank"
                            color: entry.on ? Colours.palette.m3primary : Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.medium
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 36
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.padding.small
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labels[entry.modelData.name] ?? entry.modelData.name
                            font: Tokens.font.body.medium
                            color: entry.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.toggle(entry.modelData.name);
                                root.close();
                            }
                        }
                    }
                }
            }

            Rectangle {
                x: Tokens.padding.small
                width: col.width - Tokens.padding.small * 2
                height: 1
                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)
            }

            Item {
                width: col.width
                height: Tokens.spacing.extraSmall
            }

            Action {
                label: root.arranging ? qsTr("Done arranging") : qsTr("Arrange widgets")
                icon: root.arranging ? "check" : "drag_pan"
                highlight: root.arranging
                onTriggered: {
                    root.arrange();
                    root.close();
                }
            }

            Action {
                label: qsTr("Genesi Center")
                icon: "tune"
                onTriggered: {
                    Quickshell.execDetached(["genesi-center"]);
                    root.close();
                }
            }

            Action {
                label: qsTr("Another wallpaper")
                icon: "wallpaper"
                onTriggered: {
                    // caelestia's own command, so this changes the wallpaper
                    // the same way every other route through the shell does --
                    // including retinting the scheme when it is dynamic.
                    Quickshell.execDetached(["caelestia", "wallpaper", "-r"]);
                    root.close();
                }
            }
        }
    }

    component Action: StyledRect {
        id: action

        required property string label
        required property string icon
        property bool highlight: false

        signal triggered

        implicitWidth: col.width
        implicitHeight: 30
        radius: Tokens.rounding.small
        color: area.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

        Behavior on color {
            CAnim {}
        }

        MaterialIcon {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small
            anchors.verticalCenter: parent.verticalCenter
            text: action.icon
            color: action.highlight ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 36
            anchors.verticalCenter: parent.verticalCenter
            text: action.label
            font: Tokens.font.body.medium
            color: action.highlight ? Colours.palette.m3primary : Colours.palette.m3onSurface
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.triggered()
        }
    }
}
