/*
 * BarButton — one hit target on the bar.
 *
 * Square, because a bar is a row of equal things and a button that sizes to its
 * glyph makes the row ripple. `mark` draws the Genesi leaf instead of a glyph.
 */
import QtQuick
import ".."

Rectangle {
    id: root
    property string glyph: ""
    property bool mark: false
    signal activated

    width: 24; height: 24
    radius: BarTokens.radius
    color: hov.hovered ? BarTokens.panel : "transparent"
    Behavior on color { ColorAnimation { duration: BarTokens.quick } }

    Image {
        anchors.centerIn: parent
        visible: root.mark
        source: root.mark ? "../art/genesi-leaf.svg" : ""
        sourceSize: Qt.size(16, 16)
        width: 16; height: 16
    }
    Text {
        anchors.centerIn: parent
        visible: !root.mark
        text: root.glyph
        color: hov.hovered ? BarTokens.accent : BarTokens.text
        font.family: BarTokens.mono
        font.pixelSize: 12
        Behavior on color { ColorAnimation { duration: BarTokens.quick } }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated() }
}
