/*
 * Genesi Forge — embedded console. Runs commands in the project directory via
 * the backend (line-streamed, not a full PTY — interactive TUI apps won't run)
 * and mirrors their output. Scrollback is a read-only rich-text area so text is
 * selectable/copyable (Ctrl+C or right-click); the prompt supports ↑/↓ history.
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

    property string buffer: ""
    property var hist: []
    property int histIdx: 0
    property bool running: false

    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;")
    }
    function append(text, colr) {
        buffer += '<span style="color:' + colr + '">' + esc(text) + '</span><br>'
        // Cap the scrollback so it never grows unbounded.
        if (buffer.length > 120000) buffer = buffer.substring(buffer.length - 100000)
        out.text = buffer
        scrollDown()
    }
    function scrollDown() {
        Qt.callLater(function() { outFlick.contentY = Math.max(0, out.contentHeight - outFlick.height) })
    }
    function runCmd(cmd) {
        if (!cmd || running) return
        append("$ " + cmd, "#34D989")
        hist.push(cmd); histIdx = hist.length
        running = true
        backend.runCommand(workdir, cmd)
    }

    Connections {
        target: backend
        function onConsoleOut(line) { root.append(line, "#9AA3B2") }
        function onConsoleDone(code) {
            root.running = false
            if (code !== 0) root.append("exit " + code, "#E74C3C")
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
                color: copyMa.containsMouse ? root.theme.cardHi : "transparent"
                FIcon { anchors.centerIn: parent; name: "copy"; size: 12; color: root.theme.textLo }
                MouseArea { id: copyMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { out.selectAll(); out.copy(); out.deselect() } }
                QQC2.ToolTip.text: "Copy all"; QQC2.ToolTip.visible: copyMa.containsMouse; QQC2.ToolTip.delay: 500
            }
            Rectangle {
                width: 24; height: 24; radius: 6
                color: clearMa.containsMouse ? root.theme.cardHi : "transparent"
                FIcon { anchors.centerIn: parent; name: "trash"; size: 12; color: root.theme.textLo }
                MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: { root.buffer = ""; out.text = "" } }
            }
        }

        Flickable {
            id: outFlick
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: out.contentHeight
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            QQC2.TextArea.flickable: QQC2.TextArea {
                id: out
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                color: root.theme.textMid
                selectionColor: root.theme.a(root.theme.green, 0.35)
                selectedTextColor: root.theme.textHi
                background: null
                font.family: root.theme.mono
                font.pixelSize: 12
                text: ""
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
                placeholderText: root.running ? "running..." : "git status, npm test, ... (↑/↓ for history)"
                placeholderTextColor: root.theme.textLo
                enabled: !root.running
                selectByMouse: true
                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                Keys.onUpPressed: {
                    if (root.hist.length === 0) return
                    root.histIdx = Math.max(0, root.histIdx - 1)
                    text = root.hist[root.histIdx]; cursorPosition = text.length
                }
                Keys.onDownPressed: {
                    if (root.histIdx < root.hist.length - 1) { root.histIdx++; text = root.hist[root.histIdx]; cursorPosition = text.length }
                    else { root.histIdx = root.hist.length; text = "" }
                }
                onAccepted: { root.runCmd(text); text = "" }
            }
        }
    }
}
