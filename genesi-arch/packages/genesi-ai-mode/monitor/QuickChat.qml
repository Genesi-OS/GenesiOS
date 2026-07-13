import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import QtCore as QtCore
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

    property bool expanded: settingsOpen || conversation.length > 0 || thinking || pendingApproval !== null
    property bool thinking: false
    property bool settingsOpen: false
    property bool technicalOpen: false
    property var pendingApproval: null
    property var conversation: []
    property var timeline: []
    property string activityText: "Thinking"
    property var availableModels: []
    property string modelName: backend.quickModel()
    property bool aiActive: false
    property string forceMode: "auto"
    property string profileMode: "auto"
    property bool turboRequested: backend.quickTurboActive()
    property bool turboStarting: false
    property bool turboSpec: false
    property bool turboNeedsInstall: false
    property string turboStatusText: ""
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
    function pollState() {
        try {
            var state = JSON.parse(backend.state())
            aiActive = state.ai_mode_active || false
            forceMode = state.force_mode || "auto"
            profileMode = state.profile_mode || "auto"
        } catch (error) {}
    }
    function chooseModel(name) {
        if (!name || name === modelName) return
        modelName = name
        if (turboRequested) {
            turboStarting = true
            backend.setTurbo(true, modelName, turboSpec)
        }
    }
    function setTurboWanted(on) {
        if (on && !modelName) return
        turboRequested = on
        turboStarting = on
        if (on) backend.setTurbo(true, modelName, turboSpec)
        else {
            turboStarting = false
            backend.setTurbo(false, "", false)
        }
    }
    function addMessage(role, content) {
        var next = conversation.slice(0)
        next.push({"role": role, "content": content})
        conversation = next
        var visual = timeline.slice(0)
        visual.push({"kind": "message", "role": role, "content": content,
                     "id": "message-" + Date.now() + "-" + visual.length})
        timeline = visual
        scrollToBottom()
    }
    function scrollToBottom() {
        Qt.callLater(function() {
            if (chatScroll.visible && chatScroll.contentItem)
                chatScroll.contentItem.contentY = Math.max(0, chatScroll.contentItem.contentHeight - chatScroll.availableHeight)
        })
    }
    function rememberAction(activity) {
        if (!activity || (!activity.id && !activity.tool)) return
        var id = activity.id || activity.tool
        var next = timeline.slice(0)
        var index = -1
        for (var i = 0; i < next.length; ++i) {
            if (next[i].kind === "action" && next[i].id === id) { index = i; break }
        }
        var previous = index >= 0 ? next[index] : {}
        var item = {
            "kind": "action",
            "id": id,
            "tool": activity.tool || previous.tool || "action",
            "title": activity.title || previous.title || "System action",
            "icon": activity.icon || previous.icon || "system-run",
            "state": activity.state || previous.state || "waiting-approval",
            "message": activity.message || activity.reason || previous.message || ""
        }
        if (index >= 0) next[index] = item
        else next.push(item)
        timeline = next
        scrollToBottom()
    }
    function consumeActivity(activity) {
        var state = activity.state || "thinking"
        if (["waiting-approval", "running", "action-complete", "action-error", "denied"].indexOf(state) >= 0)
            rememberAction(activity)
        if (state === "running") activityText = activity.reason || "Running an action"
        else if (state === "repairing-action") activityText = "Preparing the action"
        else if (state === "action-complete") activityText = "Reviewing the result"
        else if (state === "action-error") activityText = "Checking what went wrong"
        else if (state === "waiting-approval") activityText = "Waiting for your approval"
        else if (state === "thinking") activityText = activity.message || "Thinking"
        var terminal = ["complete", "error", "stopped", "limit-reached", "repeat-blocked"].indexOf(state) >= 0
        thinking = !terminal
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
        settingsOpen = false
        activityText = "Thinking"
        thinking = true
        backend.sendAgentPrompt(modelName, JSON.stringify(conversation), "approval")
    }
    function resolveApproval(approved) {
        if (!pendingApproval) return
        rememberAction({"id": pendingApproval.id, "tool": pendingApproval.tool,
                        "title": pendingApproval.title, "icon": pendingApproval.icon,
                        "state": approved ? "approved" : "denied",
                        "message": approved ? "Approved" : "Denied"})
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
    QtCore.Settings {
        category: "QuickChat"
        property alias selectedModel: root.modelName
        property alias speculative: root.turboSpec
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.pollState() }
    Component.onCompleted: {
        backend.loadModels()
        backend.backendInfo()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 8
        color: theme.bgTop
        border.width: 1
        border.color: root.pendingApproval ? theme.green : theme.lineHi

        Rectangle {
            visible: root.thinking
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 2; radius: 1
            color: "transparent"
            Rectangle {
                id: pulse
                width: parent.width * 0.24; height: parent.height; radius: 1
                color: theme.greenBright
                SequentialAnimation on x {
                    running: root.thinking
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: Math.max(0, root.width - 16 - pulse.width); duration: 900; easing.type: Easing.InOutCubic }
                    NumberAnimation { from: Math.max(0, root.width - 16 - pulse.width); to: 0; duration: 900; easing.type: Easing.InOutCubic }
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
                        source: Qt.resolvedUrl("icons/logo.svg")
                        isMask: true
                        color: theme.greenBright
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
                    icon.name: "settings-configure"
                    checked: root.settingsOpen
                    onClicked: {
                        root.settingsOpen = !root.settingsOpen
                        if (root.settingsOpen) backend.loadModels()
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "AI controls"
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

            Rectangle {
                visible: root.thinking && root.pendingApproval === null && !root.settingsOpen
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 7
                color: theme.a(theme.green, 0.08)
                border.width: 1
                border.color: theme.a(theme.green, 0.25)
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    QQC2.BusyIndicator {
                        running: parent.parent.visible
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: root.activityText
                        color: root.textMid; font.bold: true
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        text: "WORKING"
                        color: theme.greenBright; font.bold: true; font.pixelSize: 9
                    }
                }
            }

            ColumnLayout {
                visible: root.settingsOpen && root.pendingApproval === null
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        QQC2.Label { text: "AI controls"; color: root.textHi; font.bold: true; font.pixelSize: 16 }
                        QQC2.Label { text: "The same local engine and performance controls used by AI Mode Monitor"; color: root.textLo; font.pixelSize: 10 }
                    }
                    Rectangle {
                        implicitWidth: approvalLabel.implicitWidth + 16; implicitHeight: 22
                        radius: 6; color: theme.a(theme.green, 0.14); border.width: 1; border.color: theme.a(theme.green, 0.38)
                        QQC2.Label { id: approvalLabel; anchors.centerIn: parent; text: "APPROVAL"; color: "#a7f3cf"; font.bold: true; font.pixelSize: 9 }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 16; rowSpacing: 10

                    QQC2.Label { text: "Model"; color: root.textMid; font.bold: true }
                    QQC2.ComboBox {
                        id: modelPicker
                        Layout.fillWidth: true
                        model: root.availableModels
                        currentIndex: Math.max(0, root.availableModels.indexOf(root.modelName))
                        onActivated: root.chooseModel(currentText)
                    }

                    QQC2.Label { text: "AI Mode"; color: root.textMid; font.bold: true }
                    RowLayout {
                        spacing: 4
                        Repeater {
                            model: [
                                { "value": "on", "label": "Force ON" },
                                { "value": "auto", "label": "Auto" },
                                { "value": "off", "label": "Force OFF" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: root.forceMode === modelData.value
                                implicitWidth: modeText.implicitWidth + 20; implicitHeight: 30
                                radius: 7
                                color: selected ? (modelData.value === "off" ? theme.red : theme.green) : theme.card
                                border.width: 1; border.color: selected ? color : theme.line
                                QQC2.Label {
                                    id: modeText; anchors.centerIn: parent; text: modelData.label
                                    color: selected ? "#ffffff" : root.textMid; font.bold: selected; font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.forceMode = modelData.value; backend.setMode(modelData.value) }
                                }
                            }
                        }
                    }

                    QQC2.Label { text: "Performance"; color: root.textMid; font.bold: true }
                    RowLayout {
                        spacing: 4
                        Repeater {
                            model: [
                                { "value": "max", "label": "Maximum" },
                                { "value": "balanced", "label": "Balanced" },
                                { "value": "battery", "label": "Battery" },
                                { "value": "auto", "label": "Auto" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: root.profileMode === modelData.value
                                implicitWidth: profileText.implicitWidth + 18; implicitHeight: 30
                                radius: 7; color: selected ? theme.green : theme.card
                                border.width: 1; border.color: selected ? theme.green : theme.line
                                QQC2.Label {
                                    id: profileText; anchors.centerIn: parent; text: modelData.label
                                    color: selected ? "#ffffff" : root.textMid; font.bold: selected; font.pixelSize: 10
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.profileMode = modelData.value; backend.setProfile(modelData.value) }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: turboControls.implicitHeight + 20
                    radius: 7; color: theme.card; border.width: 1
                    border.color: root.turboRequested ? theme.turbo : theme.line
                    ColumnLayout {
                        id: turboControls
                        anchors.fill: parent; anchors.margins: 10; spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            Kirigami.Icon { source: Qt.resolvedUrl("icons/bolt.svg"); isMask: true; color: theme.turboBright; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                QQC2.Label { text: "Turbo"; color: root.textHi; font.bold: true }
                                QQC2.Label { text: root.modelName || "Choose a model first"; color: root.textLo; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            QQC2.Switch { checked: root.turboRequested; enabled: !!root.modelName; onClicked: root.setTurboWanted(!root.turboRequested) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                QQC2.Label { text: "Speculative decoding"; color: root.textHi; font.bold: true; font.pixelSize: 11 }
                                QQC2.Label { text: "Draft model acceleration; best with the CUDA backend"; color: root.textLo; font.pixelSize: 9 }
                            }
                            QQC2.Switch {
                                checked: root.turboSpec
                                onClicked: {
                                    root.turboSpec = !root.turboSpec
                                    if (root.turboRequested) {
                                        root.turboStarting = true
                                        backend.setTurbo(true, root.modelName, root.turboSpec)
                                    }
                                }
                            }
                        }
                        QQC2.Label {
                            visible: root.turboStatusText.length > 0
                            Layout.fillWidth: true; text: root.turboStatusText
                            color: root.turboRequested ? theme.turboBright : root.textLo
                            font.pixelSize: 9; wrapMode: Text.WordWrap
                        }
                        QQC2.Button {
                            visible: root.turboNeedsInstall
                            text: "Install Vulkan backend"; icon.name: "system-software-install"
                            onClicked: backend.installTurboBackend("vulkan")
                        }
                    }
                }
            }

            QQC2.ScrollView {
                id: chatScroll
                visible: root.expanded && !root.settingsOpen && root.pendingApproval === null
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(330, messages.implicitHeight)
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    id: messages
                    width: chatScroll.availableWidth
                    spacing: 10
                    Repeater {
                        model: root.timeline
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: messages.width
                            implicitHeight: modelData.kind === "message" ? messageRow.implicitHeight : actionCard.implicitHeight
                            RowLayout {
                                id: messageRow
                                visible: modelData.kind === "message"
                                width: parent.width
                                Item { Layout.fillWidth: modelData.role === "user" }
                                Rectangle {
                                    Layout.maximumWidth: messages.width * 0.82
                                    Layout.preferredWidth: Math.min(messages.width * 0.82,
                                                                    Math.max(180, messageText.implicitWidth + 24))
                                    implicitHeight: messageText.implicitHeight + 18
                                    radius: 7
                                    color: modelData.role === "user" ? theme.a(theme.green, 0.25) : theme.card
                                    QQC2.Label {
                                        id: messageText
                                        anchors.fill: parent; anchors.margins: 9
                                        text: modelData.content || ""
                                        color: root.textHi
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        font.pixelSize: 13
                                    }
                                }
                                Item { Layout.fillWidth: modelData.role !== "user" }
                            }
                            Rectangle {
                                id: actionCard
                                visible: modelData.kind === "action"
                                width: parent.width
                                implicitHeight: actionRow.implicitHeight + 18
                                radius: 7
                                color: theme.a(theme.green, 0.07)
                                border.width: 1
                                border.color: modelData.state === "action-error" || modelData.state === "denied"
                                              ? theme.a(theme.red, 0.55) : theme.a(theme.green, 0.3)
                                RowLayout {
                                    id: actionRow
                                    anchors.fill: parent; anchors.margins: 9
                                    spacing: 9
                                    Kirigami.Icon {
                                        source: modelData.icon || "system-run"
                                        color: modelData.state === "action-error" || modelData.state === "denied"
                                               ? theme.red : theme.greenBright
                                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: modelData.title || "System action"
                                            color: root.textHi; font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: modelData.message || ""
                                            visible: text.length > 0
                                            color: root.textMid; font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                    QQC2.Label {
                                        text: ({"waiting-approval": "WAITING", "approved": "APPROVED",
                                                "running": "RUNNING", "action-complete": "DONE",
                                                "action-error": "FAILED", "denied": "DENIED"})[modelData.state] || "WORKING"
                                        color: modelData.state === "action-error" || modelData.state === "denied"
                                               ? theme.red : theme.greenBright
                                        font.bold: true; font.pixelSize: 9
                                    }
                                }
                            }
                        }
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
                    onClicked: { root.conversation = []; root.timeline = []; prompt.forceActiveFocus() }
                }
            }
        }
    }

    Connections {
        target: backend
        function onModelChanged(model) { if (!root.modelName) root.modelName = model }
        function onModelsLoaded(payload) {
            var models = []
            try { models = JSON.parse(payload) } catch (error) {}
            root.availableModels = models
            if ((!root.modelName || models.indexOf(root.modelName) < 0) && models.length > 0)
                root.modelName = models[0]
        }
        function onTurboReady(ready) {
            if (ready) {
                root.turboRequested = true
                root.turboStarting = false
            } else if (!root.turboStarting) {
                root.turboRequested = false
            }
        }
        function onTurboStatus(status) {
            root.turboStatusText = status
            if (status.indexOf("failed") >= 0 || status.indexOf("not found") >= 0
                    || status.indexOf("took too long") >= 0 || status.indexOf("error") === 0) {
                root.turboStarting = false
                root.turboRequested = false
            }
        }
        function onTurboNeedsInstall(needed) {
            root.turboNeedsInstall = needed
            if (needed) { root.turboStarting = false; root.turboRequested = false }
        }
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
            root.rememberAction(root.pendingApproval)
            root.settingsOpen = false
            root.thinking = false
            root.showQuick()
        }
        function onAgentActivity(payload) {
            var activity = JSON.parse(payload)
            root.consumeActivity(activity)
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.hideQuick() }
}
