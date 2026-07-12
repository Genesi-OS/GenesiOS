/*
 * Genesi Forge — commit/branch graph (a "canvas" of the project history).
 * Assigns each commit to a lane, draws coloured bezier edges to its parents,
 * and lists subject / refs / author beside each node. Data comes from
 * backend.gitGraph (all branches, topo-ordered, with parents + decorations).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property var commits: []

    readonly property real rowH: 48
    readonly property real laneW: 20
    readonly property real gutterPad: 20
    // Every entry MUST be a color object (a bare "#rrggbb" string has no
    // .r/.g/.b, so Canvas Qt.rgba(col.r,…) would be NaN → invisible edges).
    readonly property color _c4: "#E06C9F"
    readonly property color _c5: "#5FD0C0"
    readonly property color _c6: "#C0C86A"
    readonly property color _c7: "#7C9CFF"
    readonly property var laneColors: [
        theme.greenBright, theme.blue, theme.purpleBright, theme.turboBright,
        _c4, _c5, _c6, _c7
    ]

    property var laneOf: []
    property int maxLane: 1
    property var indexOf: ({})

    function laneColor(l) { return laneColors[((l % laneColors.length) + laneColors.length) % laneColors.length] }

    function recompute() {
        var idx = {}
        for (var i = 0; i < commits.length; i++) idx[commits[i].hash] = i
        indexOf = idx

        var lanes = []          // expected next hash per column
        var out = []
        var mx = 1
        function firstFree() {
            for (var k = 0; k < lanes.length; k++) if (lanes[k] === null) return k
            lanes.push(null); return lanes.length - 1
        }
        for (i = 0; i < commits.length; i++) {
            var c = commits[i]
            var col = lanes.indexOf(c.hash)
            if (col < 0) col = firstFree()
            // merge: free any other columns also waiting on this hash
            for (var k2 = 0; k2 < lanes.length; k2++)
                if (k2 !== col && lanes[k2] === c.hash) lanes[k2] = null
            // this column now expects the first parent; extra parents branch off
            if (c.parents.length > 0) {
                lanes[col] = c.parents[0]
                for (var pi = 1; pi < c.parents.length; pi++) {
                    var fl = lanes.indexOf(c.parents[pi])
                    if (fl < 0) fl = firstFree()
                    lanes[fl] = c.parents[pi]
                }
            } else {
                lanes[col] = null
            }
            out.push(col)
            if (lanes.length > mx) mx = lanes.length
        }
        laneOf = out
        maxLane = mx
    }
    onCommitsChanged: recompute()
    Component.onCompleted: recompute()

    readonly property real gutterW: gutterPad * 2 + maxLane * laneW

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label { text: "History Graph"; color: root.theme.textHi
                font.family: root.theme.display; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
            QQC2.Label { text: root.commits.length + " commits"; color: root.theme.textMid; font.pixelSize: 12 }
        }

        FCard {
            theme: root.theme
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true

            QQC2.ScrollView {
                id: sv
                anchors.fill: parent
                anchors.margins: 4
                contentWidth: availableWidth
                clip: true

                Item {
                    width: sv.availableWidth
                    implicitHeight: root.commits.length * root.rowH + 12

                    // Edges + dots (gutter).
                    Canvas {
                        id: graphCanvas
                        width: root.gutterW
                        height: parent.implicitHeight
                        Connections { target: root; function onLaneOfChanged() { graphCanvas.requestPaint() } }
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                            if (root.commits.length === 0) return
                            ctx.lineWidth = 2
                            function cx(l) { return root.gutterPad + l * root.laneW }
                            function cy(i) { return i * root.rowH + root.rowH / 2 }
                            // edges commit -> parents
                            for (var i = 0; i < root.commits.length; i++) {
                                var L = root.laneOf[i]
                                var ps = root.commits[i].parents
                                for (var p = 0; p < ps.length; p++) {
                                    var j = root.indexOf[ps[p]]
                                    if (j === undefined) continue
                                    var M = root.laneOf[j]
                                    var col = root.laneColor(Math.max(L, M))
                                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85)
                                    ctx.beginPath(); ctx.moveTo(cx(L), cy(i))
                                    var midY = (cy(i) + cy(j)) / 2
                                    ctx.bezierCurveTo(cx(L), midY, cx(M), midY, cx(M), cy(j))
                                    ctx.stroke()
                                }
                            }
                            // dots
                            for (i = 0; i < root.commits.length; i++) {
                                var lc = root.laneColor(root.laneOf[i])
                                var merge = root.commits[i].parents.length > 1
                                ctx.fillStyle = "#0c0d10"
                                ctx.beginPath(); ctx.arc(cx(root.laneOf[i]), cy(i), merge ? 6.5 : 5.5, 0, 6.283); ctx.fill()
                                ctx.strokeStyle = Qt.rgba(lc.r, lc.g, lc.b, 1)
                                ctx.lineWidth = 2.5
                                ctx.beginPath(); ctx.arc(cx(root.laneOf[i]), cy(i), merge ? 6.5 : 5.5, 0, 6.283); ctx.stroke()
                                ctx.lineWidth = 2
                            }
                        }
                    }

                    // Commit rows (text beside the gutter).
                    Column {
                        x: root.gutterW
                        width: parent.width - root.gutterW
                        Repeater {
                            model: root.commits
                            delegate: Rectangle {
                                width: parent.width
                                height: root.rowH
                                color: rowMa.containsMouse ? root.theme.a(root.theme.green, 0.06) : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.rightMargin: 12
                                    spacing: 8
                                    // ref chips
                                    Repeater {
                                        model: modelData.refs
                                        delegate: Rectangle {
                                            readonly property bool isHead: modelData.indexOf("HEAD") >= 0
                                            readonly property bool isTag: modelData.indexOf("tag:") >= 0
                                            readonly property color rc: isHead ? root.theme.greenBright : isTag ? root.theme.turboBright : root.theme.blue
                                            Layout.preferredHeight: 18
                                            Layout.preferredWidth: refLbl.implicitWidth + 14
                                            radius: 5
                                            color: root.theme.a(rc, 0.15)
                                            border.width: 1; border.color: root.theme.a(rc, 0.4)
                                            QQC2.Label { id: refLbl; anchors.centerIn: parent
                                                text: modelData.replace("tag: ", "").replace("HEAD -> ", "")
                                                color: parent.rc; font.pixelSize: 9; font.bold: true }
                                        }
                                    }
                                    QQC2.Label {
                                        text: modelData.subject; color: root.theme.textHi; font.pixelSize: 13
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                    }
                                    QQC2.Label { text: modelData.author; color: root.theme.textMid; font.pixelSize: 11 }
                                    QQC2.Label { text: modelData.ago; color: root.theme.textLo; font.pixelSize: 11 }
                                    QQC2.Label { text: modelData.short; color: root.theme.greenBright; font.family: root.theme.mono; font.pixelSize: 11 }
                                }
                                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: backend.copyText(modelData.hash) }
                            }
                        }
                    }
                }
            }
        }
    }
}
