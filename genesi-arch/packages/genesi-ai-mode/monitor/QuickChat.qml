import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: root
    width: 720
    height: expanded ? Math.min(620, Math.max(182, body.implicitHeight + 42)) : 92
    minimumWidth: 520
    maximumWidth: 820
    visible: false
    color: "transparent"
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: "Genesi AI Quick Chat"

    property bool expanded: conversation.length > 0 || thinking || pendingApproval !== null
    property bool thinking: false
    property bool technicalOpen: false
    property var pendingApproval: null
    property var conversation: []
    property string modelName: backend.quickModel()
    readonly property color textHi: "#f3f7fb"
    readonly property color textMid: "#b1bdc9"
    readonly property color textLo: "#738196"

    palette.window: "#040b17"
    palette.windowText: textHi
    palette.base: "#0d1623"
    palette.text: textHi
    palette.button: "#16223a"
    palette.buttonText: textHi
    palette.highlight: "#1FBE6A"
    palette.highlightedText: "#ffffff"

    function reposition() {
        x = Math.round((Screen.desktopAvailableWidth - width) / 2)
        y = Math.max(24, Math.round(Screen.desktopAvailableHeight * 0.07))
    }
    function showQuick() {
        backend.refreshModel()
        reposition()
        show()
        raise()
        requestActivate()
        prompt.forceActiveFocus()
    }
    function hideQuick() {
        if (pendingApproval !== null) return
        hide()
        prompt.text = ""
    }
    function toggleQuick() { visible ? hideQuick() : showQuick() }
    function addMessage(role, content) {
        var next = conversation.slice(0)
        next.push({"role": role, "content": content})
        conversation = next
    }
    function sendPrompt() {
        var text = prompt.text.trim()
        if (!text || thinking || pendingApproval !== null) return
        if (!modelName) {
            addMessage("assistant", "No local model is ready. Install a model in AI Mode first.")
            return
        }
        addMessage("user", text)
        prompt.text = ""
        thinking = true
        backend.sendAgentPrompt(modelName, JSON.stringify(conversation), "approval")
    }
    function resolveApproval(approved) {
        if (!pendingApproval) return
        backend.resolveApproval(pendingApproval.id || "", approved)
        pendingApproval = null
        technicalOpen = false
        thinking = true
    }

    onClosing: function(close) {
        close.accepted = false
        hideQuick()
    }
    onVisibleChanged: if (visible) reposition()

    Theme { id: theme }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 8
        color: theme.bgTop
        border.width: 1
        border.color: root.pendingApproval ? theme.green : theme.lineHi

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 2; radius: 1
            color: theme.green
            opacity: root.thinking ? pulse.opacity : 0.8
            Rectangle {
                id: pulse
                width: parent.width * 0.24; height: parent.height; radius: 1
                color: theme.greenBright
                SequentialAnimation on x {
                    running: root.thinking
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: parent.width - pulse.width; duration: 900; easing.type: Easing.InOutCubic }
                    NumberAnimation { from: parent.width - pulse.width; to: 0; duration: 900; easing.type: Easing.InOutCubic }
                }
            }
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    radius: 7
                    color: theme.a(theme.green, 0.15)
                    Kirigami.Icon {
                        anchors.centerIn: parent; width: 24; height: 24
                        source: "icons/logo.svg"; color: theme.greenBright
                    }
                }
                QQC2.TextField {
                    id: prompt
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: root.thinking ? "Genesi is working..." : "What can I help you with?"
                    color: root.textHi
                    placeholderTextColor: root.textLo
                    enabled: !root.thinking && root.pendingApproval === null
                    font.pixelSize: 16
                    background: Rectangle {
                        radius: 7; color: theme.card
                        border.width: prompt.activeFocus ? 1 : 0
                        border.color: theme.green
                    }
                    Keys.onReturnPressed: root.sendPrompt()
                    Keys.onEscapePressed: root.hideQuick()
                }
                Rectangle {
                    Layout.preferredWidth: 34; Layout.preferredHeight: 26
                    radius: 6; color: theme.a(theme.green, 0.15)
                    QQC2.Label {
                        anchors.centerIn: parent; text: "ASK"
                        color: "#a7f3cf"; font.bold: true; font.pixelSize: 9
                    }
                }
                QQC2.ToolButton {
                    icon.name: "window-close"
                    onClicked: root.hideQuick()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Close"
                }
            }

            Rectangle {
                visible: root.expanded
                Layout.fillWidth: true
                implicitHeight: 1
                color: theme.line
            }

            QQC2.ScrollView {
                visible: root.expanded && root.pendingApproval === null
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(330, messages.implicitHeight)
                clip: true
                ColumnLayout {
                    id: messages
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: root.conversation
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: modelData.role === "user" }
                            Rectangle {
                                Layout.maximumWidth: messages.width * 0.82
                                implicitWidth: Math.min(messageText.implicitWidth + 24, messages.width * 0.82)
                                implicitHeight: messageText.implicitHeight + 18
                                radius: 7
                                color: modelData.role === "user" ? theme.a(theme.green, 0.25) : theme.card
                                QQC2.Label {
                                    id: messageText
                                    anchors.fill: parent; anchors.margins: 9
                                    text: modelData.content
                                    color: root.textHi
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    font.pixelSize: 13
                                }
                            }
                            Item { Layout.fillWidth: modelData.role !== "user" }
                        }
                    }
                    RowLayout {
                        visible: root.thinking
                        spacing: 8
                        QQC2.BusyIndicator { running: visible; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                        QQC2.Label { text: "Thinking"; color: root.textMid; font.bold: true }
                    }
                }
            }

            ColumnLayout {
                visible: root.pendingApproval !== null
                Layout.fillWidth: true
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Kirigami.Icon {
                        source: root.pendingApproval ? root.pendingApproval.icon : "security-high"
                        color: theme.greenBright
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: root.pendingApproval ? root.pendingApproval.title : "Allow this action?"
                            color: root.textHi; font.bold: true; font.pixelSize: 17
                        }
                        QQC2.Label {
                            text: root.pendingApproval ? root.pendingApproval.risk_label : ""
                            color: root.pendingApproval && root.pendingApproval.risk === "system-change" ? theme.red : "#a7f3cf"
                            font.bold: true; font.pixelSize: 10
                        }
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: root.pendingApproval ? root.pendingApproval.description : ""
                    color: root.textMid; wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.pendingApproval ? (root.pendingApproval.details || []) : []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 2
                        QQC2.Label { text: modelData.label; color: root.textLo; font.pixelSize: 10; font.bold: true }
                        QQC2.Label { Layout.fillWidth: true; text: modelData.value; color: root.textHi; wrapMode: Text.WrapAnywhere }
                    }
                }
                QQC2.Button {
                    flat: true
                    text: root.technicalOpen ? "Hide technical details" : "Technical details"
                    icon.name: root.technicalOpen ? "go-up" : "go-down"
                    onClicked: root.technicalOpen = !root.technicalOpen
                }
                Rectangle {
                    visible: root.technicalOpen
                    Layout.fillWidth: true
                    implicitHeight: technical.implicitHeight + 16
                    radius: 6; color: theme.bgBottom; border.width: 1; border.color: theme.line
                    QQC2.Label {
                        id: technical
                        anchors.fill: parent; anchors.margins: 8
                        text: root.pendingApproval ? (root.pendingApproval.tool + "\n" + JSON.stringify(root.pendingApproval.arguments || {}, null, 2)) : ""
                        color: root.textMid; font.family: theme.mono; font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    QQC2.Button { text: "Deny"; icon.name: "dialog-cancel"; onClicked: root.resolveApproval(false) }
                    QQC2.Button {
                        text: root.pendingApproval ? (root.pendingApproval.approve_label || "Allow") : "Allow"
                        icon.name: "dialog-ok-apply"; highlighted: true
                        onClicked: root.resolveApproval(true)
                    }
                }
            }

            RowLayout {
                visible: root.expanded
                Layout.fillWidth: true
                QQC2.Label {
                    text: root.modelName ? (root.modelName === "turbo" ? "Turbo ready" : root.modelName) : "No model available"
                    color: root.modelName ? theme.greenBright : theme.red
                    font.pixelSize: 10; elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true }
                QQC2.Label { text: "Approval mode"; color: root.textLo; font.pixelSize: 10 }
                QQC2.Button {
                    visible: root.conversation.length > 0 && !root.thinking && root.pendingApproval === null
                    flat: true; text: "New chat"; icon.name: "document-new"
                    onClicked: { root.conversation = []; prompt.forceActiveFocus() }
                }
            }
        }
    }

    Connections {
        target: backend
        function onModelChanged(model) { root.modelName = model }
        function onChatToken(token) {
            if (!token) return
            root.addMessage("assistant", token)
        }
        function onChatDone(stats) { root.thinking = false; prompt.forceActiveFocus() }
        function onChatError(message) {
            root.thinking = false
            root.addMessage("assistant", message)
        }
        function onApprovalRequested(payload) {
            root.pendingApproval = JSON.parse(payload)
            root.thinking = false
            root.showQuick()
        }
        function onAgentActivity(payload) {
            var activity = JSON.parse(payload)
            root.thinking = ["thinking", "repairing-action", "running"].indexOf(activity.state) >= 0
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.hideQuick() }
}
