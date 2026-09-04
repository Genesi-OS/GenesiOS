/*
 * StatTile — one telemetry reading: icon, label, value, history.
 *
 * The sparkline is optional. A reading with no meaningful history (uptime, the
 * user list) shows a second line of context instead, so the tiles stay the same
 * size and the grid does not develop holes.
 */
import QtQuick
import ".."

Item {
    id: root

    property string label: ""
    property string value: "—"
    property string sub: ""
    property string glyph: ""
    property bool showGraph: true
    property alias graph: spark

    implicitHeight: 58

    Row {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            width: 34; height: 34; radius: Tokens.radiusSm
            anchors.verticalCenter: parent.verticalCenter
            color: Tokens.cardHi
            border.width: 1
            border.color: Tokens.lineSoft
            Text {
                anchors.centerIn: parent
                text: root.glyph
                color: Tokens.accent
                font.family: Tokens.mono
                font.pixelSize: 13
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: 96

            Text {
                text: root.label.toUpperCase()
                color: Tokens.textDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
                font.letterSpacing: 1.2
            }
            Text {
                text: root.value
                color: Tokens.textHi
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsValue
            }
            Text {
                text: root.sub
                visible: root.sub !== ""
                color: Tokens.textFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
        }

        Sparkline {
            id: spark
            visible: root.showGraph
            width: Math.max(0, parent.width - 34 - 96 - 24)
            height: 30
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
