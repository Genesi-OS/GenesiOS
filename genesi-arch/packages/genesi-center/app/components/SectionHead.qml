/*
 * SectionHead — the numbered rule above every block.
 *
 * The numbering is the ornament. It costs one line and gives the page a spine,
 * which is the whole trick behind instrument panels reading as designed rather
 * than as a grid of widgets.
 */
import QtQuick
import ".."

Row {
    id: root
    property string index: "01"
    property string text: ""

    spacing: 8

    Text {
        text: root.index
        color: Tokens.accentDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: "//"
        visible: root.index !== "//"
        color: Tokens.textFaint
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: root.text.toUpperCase()
        color: Tokens.textDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        font.letterSpacing: 1.6
        anchors.verticalCenter: parent.verticalCenter
    }
}
