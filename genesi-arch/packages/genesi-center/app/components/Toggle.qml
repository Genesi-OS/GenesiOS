/*
 * Toggle — on or off.
 */
import QtQuick
import ".."

Rectangle {
    id: root
    property bool checked: false
    signal toggled(bool value)

    width: 42; height: 22; radius: 11
    color: checked ? Tokens.accentDeep : Tokens.card
    border.width: 1
    border.color: checked ? Tokens.accentDim : Tokens.line
    Behavior on color { ColorAnimation { duration: Tokens.quick } }

    Rectangle {
        width: 16; height: 16; radius: 8
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        color: root.checked ? Tokens.accent : Tokens.textFaint
        Behavior on x { NumberAnimation { duration: Tokens.quick; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Tokens.quick } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.toggled(!root.checked) }
}
