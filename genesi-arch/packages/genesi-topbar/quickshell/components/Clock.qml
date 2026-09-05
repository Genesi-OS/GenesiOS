/*
 * Clock — the time, with the date under it when there is room.
 *
 * Two lines in a 34px bar is tight, so the date only appears when it has been
 * given one; the bar's own presets decide, not this file.
 */
import QtQuick
import ".."

Item {
    id: root
    property string time: "--:--"
    property string date: ""
    signal activated

    implicitWidth: Math.max(t.implicitWidth, d.implicitWidth) + 14
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: BarTokens.radius
        color: hov.hovered ? BarTokens.panel : "transparent"
        Behavior on color { ColorAnimation { duration: BarTokens.quick } }
    }

    Column {
        anchors.centerIn: parent
        spacing: -1

        Text {
            id: t
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.time
            color: BarTokens.textHi
            font.family: BarTokens.mono
            font.pixelSize: root.date === "" ? 12 : 11
        }
        Text {
            id: d
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.date !== ""
            text: root.date
            color: BarTokens.textDim
            font.family: BarTokens.mono
            font.pixelSize: 8
        }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated() }
}
