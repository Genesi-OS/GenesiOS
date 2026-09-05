/*
 * Workspaces — horizontal, which is the whole reason this bar exists.
 *
 * A pill per workspace: a dot when empty, wider with the window count when
 * occupied, widest and accented when active. The width carrying the occupancy
 * means the row reads at a glance without any of them being labelled.
 */
import QtQuick
import ".."

Row {
    id: root
    property var workspaces: []
    signal picked(int id)

    spacing: 5

    Repeater {
        model: root.workspaces
        delegate: Rectangle {
            id: ws
            required property var modelData

            readonly property bool active: modelData.active === true
            readonly property bool occupied: modelData.occupied === true

            width: active ? 26 : (occupied ? 16 : 8)
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: active ? BarTokens.accent
                          : (occupied ? BarTokens.accentDim : BarTokens.line)

            Behavior on width {
                NumberAnimation { duration: BarTokens.normal; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: BarTokens.quick } }

            scale: hov.hovered && !ws.active ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: BarTokens.quick } }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(ws.modelData.id) }
        }
    }
}
