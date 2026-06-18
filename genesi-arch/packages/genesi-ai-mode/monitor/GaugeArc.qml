/*
 * Genesi AI Mode Monitor — animated circular gauge.
 * A rounded-cap ring with a soft glow underlay; `value` is 0..1 and animates.
 */
import QtQuick
import QtQuick.Controls as QQC2

Item {
    id: g

    property real value: 0            // 0..1
    property color stroke: "#1D9E75"
    property color track: "#1E382E"
    property string big: ""           // centre big label (e.g. "42")
    property string small: ""         // centre small label (e.g. "%")
    property string icon: ""          // centre icon (SVG path); overrides `big`

    implicitWidth: 62
    implicitHeight: 62

    Behavior on value { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    onValueChanged: cv.requestPaint()
    onStrokeChanged: cv.requestPaint()
    onTrackChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - 5
            ctx.lineCap = "round"

            // track
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.lineWidth = 6
            ctx.strokeStyle = g.track
            ctx.stroke()

            var v = Math.max(0, Math.min(1, g.value))
            if (v > 0.001) {
                var start = -Math.PI / 2
                var end = start + 2 * Math.PI * v
                // glow underlay
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.lineWidth = 11
                ctx.strokeStyle = Qt.rgba(g.stroke.r, g.stroke.g, g.stroke.b, 0.18)
                ctx.stroke()
                // sharp arc
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.lineWidth = 6
                ctx.strokeStyle = g.stroke
                ctx.stroke()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -1
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: g.icon.length > 0
            source: g.icon.length > 0 ? Qt.resolvedUrl(g.icon) : ""
            sourceSize.width: 24; sourceSize.height: 24
            width: 24; height: 24
            smooth: true
        }
        QQC2.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: g.icon.length === 0
            text: g.big
            font.bold: true
            font.pixelSize: 15
            color: "#EAF3EF"
        }
        QQC2.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: g.small.length > 0
            text: g.small
            font.pixelSize: 9
            color: "#9DB3AB"
        }
    }
}
