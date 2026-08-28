/*
 * Genesi AI Mode Monitor — a pill: small, round-ended, one word and one icon.
 *
 * Used for the row of quick actions under the chat hero and for the toggles in
 * the composer. `active` is a STATE, not a hover: a pill that is on stays
 * filled after the pointer leaves, because "is Genesi Find on right now?" has
 * to be answerable without touching anything.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Rectangle {
    id: root

    // Its own Theme, like every page in this app, rather than one passed in.
    // Theme is a stateless Item holding constants, so an instance costs
    // nothing -- and a property assigned from OUTSIDE is not set yet while the
    // object's own children are being created, which a delegate built by a
    // Repeater hits every time ("Cannot read property of undefined").
    Theme { id: theme }
    property string icon: ""
    property string label: ""
    property bool active: false
    property color tint: theme.green
    property string tooltip: ""
    signal clicked()

    implicitHeight: 30
    implicitWidth: row.implicitWidth + theme.sp4
    radius: theme.rPill
    color: root.active ? theme.a(root.tint, 0.20)
         : (ma.containsMouse ? theme.hover : "transparent")
    border.width: 1
    border.color: root.active ? theme.a(root.tint, 0.55) : theme.hairline
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: theme.sp2 - 2
        FIcon {
            visible: root.icon !== ""
            name: root.icon
            size: 13
            color: root.active ? theme.accentText : theme.textLo
        }
        QQC2.Label {
            text: root.label
            color: root.active ? theme.accentText : theme.textMid
            font.pixelSize: theme.fsSmall
            font.bold: root.active
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        QQC2.ToolTip.visible: containsMouse && root.tooltip !== ""
        QQC2.ToolTip.text: root.tooltip
    }
}
