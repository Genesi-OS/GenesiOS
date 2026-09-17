// GENESI — the small tinted square an icon sits in, at the head of a widget.
import QtQuick

Rectangle {
    id: root

    property real s: 1
    property string icon: ""
    property color tint: "white"
    property real size: 30

    implicitWidth: root.size * root.s
    implicitHeight: root.size * root.s
    radius: 9 * root.s
    color: Qt.alpha(root.tint, 0.16)

    GenesiWIcon {
        anchors.centerIn: parent
        s: root.s
        size: root.size * 0.6
        fill: 1
        text: root.icon
        color: root.tint
    }
}
