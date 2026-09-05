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

    // A numeric reading counts TO its value instead of snapping to it. Five
    // seconds between ticks means a dashboard that snaps looks like a table
    // being rewritten; a dashboard that moves looks like it is measuring.
    // `n` undefined leaves `value` in charge, for readings that are not a
    // number -- uptime, a rate, a user list.
    property var n: undefined
    property string unit: ""

    readonly property bool numeric: n !== undefined && n !== null && !isNaN(n)
    property real shown: root.numeric ? Number(n) : 0
    Behavior on shown {
        NumberAnimation { duration: Tokens.slow; easing.type: Easing.OutCubic }
    }
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
                text: root.numeric ? Math.round(root.shown) + root.unit
                                   : root.value
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
