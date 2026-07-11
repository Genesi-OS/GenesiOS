/*
 * Genesi Forge — a node type in the Canvas palette. Drag onto the canvas to
 * place it (shared ghost owned by CanvasView), or click to add at the default
 * spot.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property string label: ""
    property string icon: ""
    property string kind: ""
    property color accent: theme ? theme.green : "#1FBE6A"
    property Item dragGhost: null
    signal add()

    Layout.fillWidth: true
    implicitHeight: 44

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: ma.containsMouse ? root.theme.cardHi : root.theme.card
        border.width: 1
        border.color: ma.containsMouse ? root.theme.a(root.accent, 0.4) : root.theme.line
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 10
            Rectangle {
                width: 28; height: 28; radius: 8
                color: root.theme.a(root.accent, 0.16)
                FIcon { anchors.centerIn: parent; name: root.icon; size: 15; color: root.accent }
            }
            QQC2.Label { text: root.label; color: root.theme.textHi; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
            FIcon {
                name: "plus"; size: 13
                color: root.theme.textLo; opacity: ma.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: root.dragGhost
        drag.threshold: 6
        preventStealing: true
        onPressed: function(mouse) {
            if (!root.dragGhost) return
            root.dragGhost.def = { label: root.label, icon: root.icon, accent: root.accent, kind: root.kind }
            var gp = mapToItem(root.dragGhost.parent, mouse.x, mouse.y)
            root.dragGhost.x = gp.x - root.dragGhost.width / 2
            root.dragGhost.y = gp.y - root.dragGhost.height / 2
        }
        onPositionChanged: {
            if (root.dragGhost && ma.drag.active && !root.dragGhost.dragging)
                root.dragGhost.dragging = true
        }
        onReleased: {
            if (root.dragGhost && root.dragGhost.dragging) {
                root.dragGhost.Drag.drop()
                root.dragGhost.dragging = false
            }
        }
        onClicked: root.add()
    }
}
