/*
 * Genesi Forge — a workflow node on the Forge Canvas. Accent-bordered card with
 * an icon header, the step's actions, and a status pill. Draggable; reports
 * moves (so links repaint) and selection. Has input/output ports for wiring
 * links, a delete affordance when selected, and a live run-state pill.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property var node
    property bool selected: false
    property string runState: ""   // "", "running", "done", "failed"
    signal moved()
    signal picked()
    signal deleteRequested()
    signal linkBegin(real sx, real sy)
    signal linkMove(real sx, real sy)
    signal linkEnd(real sx, real sy)

    width: 214
    implicitHeight: body.implicitHeight + 28
    height: implicitHeight

    readonly property color accent: node.accent

    // Live run-state overrides the static status pill.
    readonly property string pillText: runState === "running" ? "Running…"
        : runState === "done" ? "Done" : runState === "failed" ? "Failed"
        : (node.status !== undefined ? node.status : "")
    readonly property color pillColor: runState === "running" ? theme.blue
        : runState === "done" ? theme.greenBright : runState === "failed" ? theme.red
        : (node.statusKind === "success" ? theme.greenBright
           : node.statusKind === "auto" ? theme.blue : theme.green)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 15
        color: root.theme.mix(root.theme.card, root.accent, root.selected ? 0.14 : 0.06)
        border.width: root.selected ? 2 : 1.5
        border.color: root.runState === "running" ? root.theme.blue
                    : root.selected ? root.accent : root.theme.a(root.accent, 0.5)
    }
    Rectangle {
        visible: root.selected
        anchors.fill: parent; anchors.margins: -2.5
        radius: bg.radius + 2.5; color: "transparent"
        border.width: 2; border.color: root.theme.a(root.accent, 0.3)
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
                color: root.theme.a(root.accent, 0.18)
                border.width: 1; border.color: root.theme.a(root.accent, 0.38)
                Kirigami.Icon { anchors.centerIn: parent; source: root.node.icon; width: 18; height: 18; color: root.accent }
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
                Kirigami.Icon {
                    source: root.runState === "running" ? "view-refresh"
                          : root.runState === "failed" ? "dialog-error" : "checkmark"
                    width: 12; height: 12; color: root.pillColor
                    RotationAnimation on rotation { running: root.runState === "running"; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                }
                QQC2.Label { text: root.pillText; color: root.pillColor; font.pixelSize: 11; font.bold: true }
            }
        }
    }

    // Node body drag (move).
    MouseArea {
        anchors.fill: parent
        drag.target: root
        drag.axis: Drag.XAndYAxis
        cursorShape: Qt.OpenHandCursor
        onPressed: root.picked()
        onPositionChanged: root.moved()
        onReleased: root.moved()
    }
    onXChanged: root.moved()
    onYChanged: root.moved()

    // Input port (left).
    Rectangle {
        width: 12; height: 12; radius: 6
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.left; anchors.rightMargin: -6
        color: root.theme.card; border.width: 2; border.color: root.theme.a(root.accent, 0.7)
    }
    // Output port (right) — drag to wire a link.
    Rectangle {
        id: outPort
        width: 14; height: 14; radius: 7
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.right; anchors.leftMargin: -8
        color: outMa.containsMouse || outMa.pressed ? root.accent : root.theme.card
        border.width: 2; border.color: root.theme.a(root.accent, 0.9)
        MouseArea {
            id: outMa
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            onPressed: function(m) { var s = mapToItem(null, m.x, m.y); root.linkBegin(s.x, s.y) }
            onPositionChanged: function(m) { var s = mapToItem(null, m.x, m.y); root.linkMove(s.x, s.y) }
            onReleased: function(m) { var s = mapToItem(null, m.x, m.y); root.linkEnd(s.x, s.y) }
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
        Kirigami.Icon { anchors.centerIn: parent; source: "edit-delete"; width: 12; height: 12
            color: delMa.containsMouse ? root.theme.white : root.theme.red }
        MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.deleteRequested() }
    }
}
