// GENESI — one desktop widget, wrapped.
//
// Builds the widget by name, scales it, and in arrange mode gives it the two
// things a widget needs to be moved: an outline saying it can be, and a way to
// move it.
//
// ── Anchored widgets are unpinned, not dragged ──────────────────────────────
//
// A widget in a corner lives inside a Column, and a Column SETS the x and y of
// everything in it. A drag handler writing x and y to the same item is two
// things assigning one property every frame, and what that looks like is not a
// widget being dragged -- it is a widget vibrating.
//
// So there are two gestures, not one. An anchored widget shows UNPIN, which
// makes it free exactly where it already stands; a free widget is dragged. Both
// end in the same place, and neither fights a positioner.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: host

    required property string widget
    // Which corner it is anchored in, or "free". Only used to scale from the
    // right edge, so growing a widget does not push it off the screen.
    property string corner: "top-left"
    property bool arranging: false
    // The item the drag moves. Free widgets pass their own wrapper; anchored
    // ones pass nothing, and get UNPIN instead.
    property Item dragTarget: null

    signal dropped

    readonly property var cfg: Config.background.widgets[host.widget]
    readonly property real factor: Math.max(0.5, Math.min(2, host.cfg?.scale ?? 1))

    implicitWidth: body.implicitWidth * host.factor
    implicitHeight: body.implicitHeight * host.factor

    Loader {
        id: body

        // Built by name. The file, the config key and this string are one
        // identifier, so a widget that exists is reachable and one that is not
        // fails visibly at its own Loader instead of quietly not being drawn.
        source: Qt.resolvedUrl("GenesiWidget" + host.widget.charAt(0).toUpperCase() + host.widget.slice(1) + ".qml")
        asynchronous: true

        transformOrigin: Item.TopLeft
        scale: host.factor

        opacity: status === Loader.Ready ? 1 : 0

        Behavior on opacity {
            Anim {}
        }
    }

    // ── Arrange mode ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        visible: host.arranging
        color: "transparent"
        radius: Tokens.rounding.large
        border.width: 1
        border.color: drag.active ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.5)

        Behavior on border.color {
            CAnim {}
        }
    }

    DragHandler {
        id: drag

        // A free widget only. `target` null on an anchored one means the
        // gesture exists and moves nothing, which is worse than not existing;
        // `enabled` is what keeps it off.
        enabled: host.arranging && host.dragTarget !== null
        target: host.dragTarget
        cursorShape: Qt.ClosedHandCursor

        onActiveChanged: if (!active)
            host.dropped()
    }

    // UNPIN, for the ones in a corner. It reads as the opposite of what it is
    // -- you are not detaching it from anything, you are saying "this one I
    // will place myself" -- and no shorter word says that.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 4
        visible: host.arranging && host.dragTarget === null
        implicitWidth: unpinText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: unpinText.implicitHeight + Tokens.padding.extraSmall * 2
        radius: Tokens.rounding.full
        color: unpinArea.containsMouse ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

        Behavior on color {
            CAnim {}
        }

        StyledText {
            id: unpinText

            anchors.centerIn: parent
            text: qsTr("UNPIN")
            font: Tokens.font.label.small
            color: unpinArea.containsMouse ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
        }

        MouseArea {
            id: unpinArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: host.dropped()
        }
    }
}
