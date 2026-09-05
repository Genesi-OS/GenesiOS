/*
 * GroupHead — the numbered divider between rail groups.
 *
 * Nine sections in one flat list is a menu. Three groups of three, each
 * announced by a number and a word, is a contents page -- and it costs one
 * small line per group.
 */
import QtQuick
import ".."

Item {
    id: root
    property string index: "01"
    property string text: ""

    implicitHeight: 26

    Row {
        anchors { left: parent.left; leftMargin: 14; bottom: parent.bottom; bottomMargin: 5 }
        spacing: 7

        Text {
            text: "#" + root.index
            color: Tokens.accentDim
            font.family: Tokens.mono
            font.pixelSize: 9
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.text.toUpperCase()
            color: Tokens.textFaint
            font.family: Tokens.mono
            font.pixelSize: 9
            font.letterSpacing: 1.8
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 9 }
        width: 42; height: 1
        color: Tokens.lineSoft
    }
}
