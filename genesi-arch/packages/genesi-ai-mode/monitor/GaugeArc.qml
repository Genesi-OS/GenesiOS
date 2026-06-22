/*
 * Genesi AI Mode Monitor — animated circular gauge.
 * A rounded-cap ring with a soft glow underlay; `value` is 0..1 and animates.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: g

    // Follow the system scheme (see genesi-ui-kit/Theme.qml). No fixed brand blue.
    readonly property color _bg: Kirigami.Theme.backgroundColor
    readonly property color _txt: Kirigami.Theme.textColor
    readonly property bool _dark: !((0.299 * _bg.r + 0.587 * _bg.g + 0.114 * _bg.b) >= 0.5)
    readonly property color _white: "#ffffff"
    readonly property color _black: "#000000"
    function _mix(c, o, p) { return Qt.rgba(c.r + (o.r - c.r) * p, c.g + (o.g - c.g) * p, c.b + (o.b - c.b) * p, 1) }

    property real value: 0            // 0..1
    property color stroke: Kirigami.Theme.highlightColor
    property color track: _dark ? _mix(_bg, _white, 0.14) : _mix(_bg, _black, 0.12)
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
        // Render through a CPU image rather than a GPU framebuffer object. The
        // FBO path needs a live GL context and is a common crash point on the
        // flaky guest GL stacks in VMs; the Image path is driver-independent and
        // works identically under the software scene-graph backend.
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative
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
            color: g._txt
        }
        QQC2.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: g.small.length > 0
            text: g.small
            font.pixelSize: 9
            color: g._mix(g._txt, g._bg, 0.42)
        }
    }
}
