/*
 * Genesi Forge — a workflow node on the Forge Canvas sheet. Accent-bordered
 * card with an icon header, step lines and a status pill (live run-state).
 * Draggable within the sheet bounds (preventStealing so the Flickable pan
 * never hijacks a node drag). Output port (right) wires links: it reports
 * sheet-space coordinates — the node's parent IS the sheet.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property var node
    property bool selected: false
    property string runState: ""   // "", "waiting", "running", "done", "failed"
    property real boundW: 4000
    property real boundH: 4000
    signal moved()
    signal moveBegin()
    signal picked()
    signal deleteRequested()
    signal linkBegin(real sx, real sy)
    signal linkMove(real sx, real sy)
    signal linkEnd(real sx, real sy)

    width: 214
    implicitHeight: body.implicitHeight + 28
    height: implicitHeight

    readonly property color accent: node.accent

    readonly property string pillText: runState === "waiting" ? "Waiting for event"
        : runState === "running" ? "Running…"
        : runState === "done" ? "Done" : runState === "failed" ? "Failed"
        : (node.status !== undefined ? node.status : "")
    readonly property color pillColor: runState === "waiting" ? theme.turbo
        : runState === "running" ? theme.blue
        : runState === "done" ? theme.greenBright : runState === "failed" ? theme.red
        : (node.statusKind === "success" ? theme.greenBright
           : node.statusKind === "auto" ? theme.blue : theme.green)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 14
        color: root.theme.mix(root.theme.card, root.accent, root.selected ? 0.13 : 0.05)
        border.width: root.selected ? 2 : 1.5
        border.color: root.runState === "running" ? root.theme.blue
                    : root.selected ? root.accent : root.theme.a(root.accent, 0.5)
    }
    Rectangle {
        visible: root.selected
        anchors.fill: parent; anchors.margins: -2.5
        radius: bg.radius + 2.5; color: "transparent"
        border.width: 2; border.color: root.theme.a(root.accent, 0.28)
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                width: 32; height: 32; radius: 9
                color: root.theme.a(root.accent, 0.17)
                border.width: 1; border.color: root.theme.a(root.accent, 0.36)
                FIcon { anchors.centerIn: parent; name: root.node.icon; size: 17; color: root.accent }
            }
            QQC2.Label {
                text: root.node.title; color: root.theme.textHi
                font.family: root.theme.display; font.pixelSize: 14; font.bold: true
                Layout.fillWidth: true; elide: Text.ElideRight
            }
        }

        Repeater {
            model: root.node.lines
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: 7
                Rectangle { width: 5; height: 5; radius: 2.5; color: root.theme.a(root.accent, 0.8); Layout.alignment: Qt.AlignVCenter }
                QQC2.Label { text: modelData; color: root.theme.textMid; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }

        Rectangle {
            id: statusPill
            visible: root.pillText !== ""
            Layout.topMargin: 2
            Layout.preferredWidth: statusRow.implicitWidth + 18
            Layout.preferredHeight: 24
            radius: 7
            color: root.theme.a(root.pillColor, 0.14)
            border.width: 1; border.color: root.theme.a(root.pillColor, 0.32)
            RowLayout {
                id: statusRow
                anchors.centerIn: parent; spacing: 5
                FIcon {
                    name: root.runState === "waiting" ? "clock"
                        : root.runState === "running" ? "refresh-cw"
                        : root.runState === "failed" ? "x" : "check"
                    size: 11; color: root.pillColor
                    RotationAnimation on rotation { running: root.runState === "running"; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                }
                QQC2.Label { text: root.pillText; color: root.pillColor; font.pixelSize: 11; font.bold: true }
            }
        }
    }

    // Node body drag (move) — preventStealing so the Flickable never pans.
    MouseArea {
        anchors.fill: parent
        drag.target: root
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 0
        drag.minimumY: 0
        drag.maximumX: root.boundW - root.width
        drag.maximumY: root.boundH - root.height
        preventStealing: true
        cursorShape: Qt.OpenHandCursor
        onPressed: { root.picked(); root.moveBegin() }
        onPositionChanged: root.moved()
        onReleased: root.moved()
    }
    onXChanged: root.moved()
    onYChanged: root.moved()

    // Input port (left) — link drop target marker.
    Rectangle {
        width: 13; height: 13; radius: 7
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.left; anchors.rightMargin: -7
        color: root.theme.card
        border.width: 2; border.color: root.theme.a(root.accent, 0.7)
    }
    // Output port (right) — drag from here to another node to wire a link.
    Rectangle {
        id: outPort
        width: 16; height: 16; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.right; anchors.leftMargin: -9
        color: outMa.containsMouse || outMa.pressed ? root.accent : root.theme.card
        border.width: 2; border.color: root.theme.a(root.accent, 0.9)
        scale: outMa.containsMouse || outMa.pressed ? 1.25 : 1.0
        Behavior on scale { NumberAnimation { duration: 110 } }
        MouseArea {
            id: outMa
            anchors.fill: parent; anchors.margins: -10
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.CrossCursor
            onPressed: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkBegin(s.x, s.y) }
            onPositionChanged: function(m) { if (pressed) { var s = mapToItem(root.parent, m.x, m.y); root.linkMove(s.x, s.y) } }
            onReleased: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkEnd(s.x, s.y) }
        }
    }

    // Delete affordance (selected only).
    Rectangle {
        visible: root.selected
        width: 24; height: 24; radius: 12
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: -6; anchors.topMargin: -6
        color: delMa.containsMouse ? root.theme.red : root.theme.card
        border.width: 1.5; border.color: root.theme.a(root.theme.red, 0.8)
        FIcon { anchors.centerIn: parent; name: "trash"; size: 11
            color: delMa.containsMouse ? "#FFFFFF" : root.theme.red }
        MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.deleteRequested() }
    }
}
