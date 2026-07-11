/*
 * Genesi Forge — embedded console. Runs commands in the project directory via
 * the backend (line-streamed, not a full PTY — interactive TUI apps won't run)
 * and mirrors their output. Prompt at the bottom, monospace scrollback above.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Rectangle {
    id: root
    property var theme
    property string workdir: ""
    property bool showHeader: true

    radius: 12
    color: "#0c0d10"
    border.width: 1
    border.color: theme.line
    clip: true

    ListModel { id: lines }
    property bool running: false

    function runCmd(cmd) {
        if (!cmd || running) return
        lines.append({ text: "$ " + cmd, kind: "cmd" })
        running = true
        backend.runCommand(workdir, cmd)
        scrollDown()
    }
    function scrollDown() { Qt.callLater(function() { out.positionViewAtEnd() }) }

    Connections {
        target: backend
        function onConsoleOut(line) {
            lines.append({ text: line, kind: "out" })
            if (lines.count > 800) lines.remove(0, lines.count - 800)
            root.scrollDown()
        }
        function onConsoleDone(code) {
            root.running = false
            if (code !== 0) lines.append({ text: "exit " + code, kind: "err" })
            root.scrollDown()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            visible: root.showHeader
            Layout.fillWidth: true
            spacing: 8
            FIcon { name: "terminal"; size: 14; color: root.theme.greenBright }
            QQC2.Label { text: "Terminal"; color: root.theme.textHi; font.pixelSize: 12; font.bold: true }
            QQC2.Label { text: root.workdir; color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Rectangle {
                width: 24; height: 24; radius: 6
                color: clearMa.containsMouse ? root.theme.cardHi : "transparent"
                FIcon { anchors.centerIn: parent; name: "trash"; size: 12; color: root.theme.textLo }
                MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: lines.clear() }
            }
        }

        ListView {
            id: out
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            model: lines
            spacing: 1
            delegate: QQC2.Label {
                width: out.width
                text: model.text
                color: model.kind === "cmd" ? root.theme.greenBright
                     : model.kind === "err" ? root.theme.red : root.theme.textMid
                font.family: root.theme.mono
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            QQC2.Label { text: "$"; color: root.theme.greenBright; font.family: root.theme.mono; font.pixelSize: 13; font.bold: true }
            QQC2.TextField {
                id: input
                Layout.fillWidth: true
                background: Rectangle { radius: 7; color: root.theme.card; border.width: 1; border.color: root.theme.line }
                color: root.theme.textHi
                font.family: root.theme.mono; font.pixelSize: 12
                placeholderText: root.running ? "running..." : "git status, npm test, ..."
                placeholderTextColor: root.theme.textLo
                enabled: !root.running
                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                onAccepted: { root.runCmd(text); text = "" }
            }
        }
    }
}
