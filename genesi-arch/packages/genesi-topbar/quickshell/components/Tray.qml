/*
 * Tray — the StatusNotifierItem icons.
 *
 * Genesi's own trays are appindicator/Gtk, never Qt's QSystemTrayIcon, so their
 * icons come through as themed names rather than pixmaps. Both are handled by
 * shell.qml before they reach here; this file only draws.
 */
import QtQuick
import ".."

Row {
    id: root
    property var items: []
    signal picked(string id)

    spacing: 6

    Repeater {
        model: root.items
        delegate: Rectangle {
            id: cell
            required property var modelData

            width: 22; height: 22
            radius: BarTokens.radius
            color: hov.hovered ? BarTokens.panel : "transparent"
            Behavior on color { ColorAnimation { duration: BarTokens.quick } }

            Image {
                anchors.centerIn: parent
                width: 15; height: 15
                sourceSize: Qt.size(15, 15)
                source: cell.modelData.icon || ""
                visible: source != ""
            }
            // A tray item whose icon will not resolve is still a running
            // program the person may want to click. A dot says it is there.
            Rectangle {
                anchors.centerIn: parent
                visible: !(cell.modelData.icon || "")
                width: 6; height: 6; radius: 3
                color: BarTokens.accentDim
            }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(cell.modelData.id) }
        }
    }
}
