// GENESI STORE — a filter, or a label that can be pressed.
import QtQuick
import ".."

Rectangle {
    id: root

    property string text: ""
    property bool selected: false
    property bool interactive: true
    property color tint: Tokens.accent
    signal activated

    implicitWidth: label.implicitWidth + 26
    implicitHeight: 30
    radius: height / 2
    color: root.selected ? Tokens.a(root.tint, 0.18)
                         : (hover.hovered && root.interactive ? Tokens.cardHi : Tokens.a(Tokens.card, 0.9))
    border.width: 1
    border.color: root.selected ? Tokens.a(root.tint, 0.55) : Tokens.line

    Behavior on color {
        ColorAnimation {
            duration: Tokens.quick
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Tokens.textHi : Tokens.text
        font.family: Tokens.sans
        font.pixelSize: Tokens.fsLabel
    }

    HoverHandler {
        id: hover

        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: root.interactive
        onTapped: root.activated()
    }
}
