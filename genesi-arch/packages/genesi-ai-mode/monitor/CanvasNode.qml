/*
 * Genesi AI Mode Monitor — a node on the Automations canvas sheet (copied from
 * Forge). Accent-bordered card with an icon header, step lines and a status
 * pill. Draggable within the sheet bounds; the output port (right) wires links
 * in sheet-space coordinates (the node's parent IS the sheet).
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
    signal linkBegin(real sx, real sy, string port)
    signal linkMove(real sx, real sy)
    signal linkEnd(real sx, real sy)

    // Result ports ({port, label, color}); empty = single always-port. Set by
    // the canvas from portsFor(kind) — layout must match portPoint() there
    // (16px dots, 10px spacing, vertically centered).
    property var outPorts: []

    // The reference canvas labels every card with WHAT KIND of step it is and
    // WHERE it sits in the graph, in a coloured strip across the top. Reading a
    // sheet of a dozen cards, that is the difference between scanning and
    // deciphering: the title tells you what this one does, the strip tells you
    // whether it is a trigger, a decision or something that touches the machine.
    property int stepNumber: 0
    readonly property string kindLabel: {
        var k = "" + (root.node.kind || "")
        if (k.indexOf("evt_") === 0) return "TRIGGER"
        if (k === "act_ai")      return "AI"
        if (k === "act_cond")    return "CONDITION"
        if (k === "act_loop")    return "LOOP"
        if (k === "act_subflow") return "SUB-WORKFLOW"
        if (k.indexOf("act_") === 0) return "ACTION"
        return "STEP"
    }
    // Dark text on a saturated strip. Mixing toward black rather than picking a
    // constant keeps it legible whatever accent a node kind carries.
    readonly property color stripText: root.theme.mix(root.accent, root.theme.black, 0.72)

    width: 214
    implicitHeight: strip.height + body.implicitHeight + 28
    height: implicitHeight

    readonly property color accent: node.accent

    readonly property string pillText: runState === "waiting" ? "Waiting for event"
        : runState === "running" ? "Running…"
        : runState === "done" ? "Done" : runState === "failed" ? "Failed"
        : runState === "skipped" ? "Not taken"
        : (node.status !== undefined ? node.status : "")
    readonly property color pillColor: runState === "waiting" ? theme.turbo
        : runState === "running" ? theme.blue
        : runState === "done" ? theme.greenBright : runState === "failed" ? theme.red
        : runState === "skipped" ? theme.textLo
        : (node.statusKind === "success" ? theme.greenBright
           : node.statusKind === "auto" ? theme.blue : theme.green)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 14
        color: root.theme.mix(root.theme.card, root.accent, root.selected ? 0.13 : 0.05)
        border.width: root.selected ? 2 : 1.5
        border.color: root.runState === "running" ? root.theme.blue
                    : root.runState === "failed" ? root.theme.red
                    : root.runState === "done" ? root.theme.greenBright
                    : root.selected ? root.accent : root.theme.a(root.accent, 0.5)
        // A branch the flow did not take dims out, so the path that actually
        // ran reads at a glance.
        opacity: root.runState === "skipped" ? 0.45 : 1.0
    }
    Rectangle {
        visible: root.selected
        anchors.fill: parent; anchors.margins: -2.5
        radius: bg.radius + 2.5; color: "transparent"
        border.width: 2; border.color: root.theme.a(root.accent, 0.28)
    }

    Rectangle {
        id: strip
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 22
        radius: bg.radius
        color: root.theme.a(root.accent, root.runState === "skipped" ? 0.45 : 0.92)
        // Square off the bottom two corners so the strip meets the body flush.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: parent.radius
            color: parent.color
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 10
            spacing: 6
            QQC2.Label {
                text: root.kindLabel
                color: root.stripText
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.1
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            QQC2.Label {
                // The delete button takes this corner when the node is
                // selected; two things in one 24px square is neither.
                visible: root.stepNumber > 0 && !root.selected
                text: root.stepNumber < 10 ? "0" + root.stepNumber : "" + root.stepNumber
                color: root.stripText
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.6
            }
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: strip.bottom
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
                        : root.runState === "failed" ? "x"
                        : root.runState === "skipped" ? "minus" : "check"
                    size: 11; color: root.pillColor
                    RotationAnimation on rotation { running: root.runState === "running"; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                }
                QQC2.Label { text: root.pillText; color: root.pillColor; font.pixelSize: 11; font.bold: true }
            }
        }
    }

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

    Rectangle {
        width: 13; height: 13; radius: 7
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.left; anchors.rightMargin: -7
        color: root.theme.card
        border.width: 2; border.color: root.theme.a(root.accent, 0.7)
    }
    Rectangle {
        id: outPort
        visible: (root.outPorts || []).length === 0
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
            onPressed: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkBegin(s.x, s.y, "") }
            onPositionChanged: function(m) { if (pressed) { var s = mapToItem(root.parent, m.x, m.y); root.linkMove(s.x, s.y) } }
            onReleased: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkEnd(s.x, s.y) }
        }
    }

    // Result ports: on ok / on error / on output. Drag a link from a dot and
    // the chain only follows it when the node ends with that result.
    Column {
        visible: (root.outPorts || []).length > 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.right; anchors.leftMargin: -9
        spacing: 10
        Repeater {
            model: root.outPorts
            delegate: Rectangle {
                required property var modelData
                width: 16; height: 16; radius: 8
                color: pMa.containsMouse || pMa.pressed ? modelData.color : root.theme.card
                border.width: 2; border.color: modelData.color
                scale: pMa.containsMouse || pMa.pressed ? 1.25 : 1.0
                Behavior on scale { NumberAnimation { duration: 110 } }
                QQC2.Label {
                    anchors.right: parent.left; anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.selected || pMa.containsMouse
                    text: modelData.label
                    color: modelData.color
                    font.pixelSize: 9; font.bold: true
                }
                MouseArea {
                    id: pMa
                    anchors.fill: parent; anchors.margins: -8
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.CrossCursor
                    onPressed: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkBegin(s.x, s.y, modelData.port) }
                    onPositionChanged: function(m) { if (pressed) { var s = mapToItem(root.parent, m.x, m.y); root.linkMove(s.x, s.y) } }
                    onReleased: function(m) { var s = mapToItem(root.parent, m.x, m.y); root.linkEnd(s.x, s.y) }
                }
            }
        }
    }

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
