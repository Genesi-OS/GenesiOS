/*
 * Segmented — a small set of exclusive choices, all visible at once.
 *
 * For anything with four options or fewer. A dropdown hides the alternatives
 * behind a click, and for a choice like rotation the whole point is seeing that
 * there are exactly four.
 */
import QtQuick
import ".."

Row {
    id: root
    property var options: []       // [{ id, label }]
    property string current: ""
    signal picked(string id)

    spacing: 4

    Repeater {
        model: root.options
        delegate: Rectangle {
            required property var modelData
            readonly property bool on: modelData.id === root.current

            width: Math.max(44, txt.implicitWidth + 18)
            height: 26
            radius: Tokens.radiusSm
            color: on ? Tokens.accentDeep : (hov.hovered ? Tokens.cardHi : "transparent")
            border.width: 1
            border.color: on ? Tokens.accentDim : Tokens.line
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
            Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

            Text {
                id: txt
                anchors.centerIn: parent
                text: modelData.label
                color: parent.on ? Tokens.textHi : Tokens.text
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(modelData.id) }
        }
    }
}
