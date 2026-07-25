/*
 * Genesi AI Mode Monitor — Chat page.
 * Renders the conversation as styled bubbles (user / AI / error). Talks to the
 * Python backend, which routes to Ollama (/api/generate) or the Turbo server
 * (llama-server /completion) and streams tokens back with verbose stats.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page
    title: "AI Chat"
    padding: 0

    Theme { id: theme }
    // The shared I18n instance is passed in from Main so the language switch
    // stays in sync across pages (a per-page instance wouldn't update live).
    property var i18n

    property bool busy: false
    property int currentAi: -1
    property string agentMode: "chat"
    property var pendingApproval: ({})
    property bool approvalTechnical: false
    // Persisted-session id ("" = a fresh, not-yet-saved chat). Set by the sidebar
    // HISTORY rail when reopening a chat, and by persist() after the first save.
    property string sessionId: ""

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
        }
    }

    Component.onCompleted: {
        backend.loadModels()
        page.agentMode = backend.agentMode()
    }

    // Debounce for prefill-as-you-type: fires ~450ms after the user stops typing
    // and warms the KV cache for the current text (Turbo only; the backend
    // no-ops otherwise). Cheap and best-effort — makes the next send() instant.
    Timer {
        id: warmTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (!page.busy && input.text.trim().length >= 12)
                backend.warmPrefix(input.text)
        }
    }

    // Short one-line summary for the top status label (full data lives in the
    // bubble's stats panel). `s` is the JSON stats string from the backend.
    function shortStats(s) {
        if (!s || s.length === 0) return i18n.t("chat.ready")
        try {
            var d = JSON.parse(s)
            return (d.mode === "turbo" ? "⚡ " : "") + d.rate + " tok/s  ·  " + d.eval + " tokens"
        } catch (e) {
            return s
        }
    }

    function send() {
        var q = input.text.trim()
        if (page.busy || q.length === 0 || modelCombo.currentText.length === 0)
            return
        chatModel.append({ "role": "user", "body": q, "stats": "" })
        // Send the WHOLE thread (not just this line) so the model has context —
        // this is what makes it remember earlier turns in the same conversation.
        var msgs = []
        for (var i = 0; i < chatModel.count; i++) {
            var m = chatModel.get(i)
            if (m.role === "error" || !m.body || m.body.length === 0) continue
            msgs.push({ "role": m.role === "ai" ? "assistant" : "user", "content": m.body })
        }
        chatModel.append({ "role": "ai", "body": "", "stats": "" })
        page.currentAi = chatModel.count - 1
        page.busy = true
        statsLabel.text = i18n.t("chat.generating")
        if (page.agentMode === "chat")
            backend.sendPrompt(modelCombo.currentText, JSON.stringify(msgs))
        else
            backend.sendAgentPrompt(modelCombo.currentText, JSON.stringify(msgs), page.agentMode)
        input.text = ""
        chatList.positionViewAtEnd()
    }

    // ── session persistence (feeds the sidebar HISTORY rail; swept by MemPalace
    //    once the user turns on "remember"). Local JSON, cheap, always on. ──
    function _serialize() {
        var arr = []
        for (var i = 0; i < chatModel.count; i++) {
            var m = chatModel.get(i)
            if (m.role === "error") continue
            arr.push({ "role": m.role, "body": m.body, "stats": m.stats || "" })
        }
        return JSON.stringify(arr)
    }
    function persist() {
        if (chatModel.count === 0) return
        page.sessionId = backend.saveSession(page.sessionId, modelCombo.currentText, _serialize())
    }
    function loadSessionInto(sid) {
        var s = {}
        try { s = JSON.parse(backend.loadSession(sid)) } catch (e) { return }
        chatModel.clear()
        var msgs = s.messages || []
        for (var i = 0; i < msgs.length; i++)
            chatModel.append({ "role": msgs[i].role, "body": msgs[i].body, "stats": msgs[i].stats || "" })
        page.sessionId = s.id || sid
        page.currentAi = -1
        page.busy = false
        chatList.positionViewAtEnd()
    }
    function newChat() {
        chatModel.clear()
        page.sessionId = ""
        page.currentAi = -1
        input.text = ""
    }

    Connections {
        target: backend
        function onAgentModeChanged(mode) { page.agentMode = mode }
        function onApprovalRequested(jsonStr) {
            try { page.pendingApproval = JSON.parse(jsonStr) } catch (e) { return }
            page.approvalTechnical = false
            approvalDialog.open()
        }
        function onAgentActivity(jsonStr) {
            var activity = ({})
            try { activity = JSON.parse(jsonStr) } catch (e) { return }
            if (activity.state === "thinking") statsLabel.text = "Planning actions..."
            else if (activity.state === "waiting-approval") statsLabel.text = "Waiting for approval"
            else if (activity.state === "running") statsLabel.text = "Running " + (activity.tool || "action") + "..."
            else if (activity.state === "action-error") statsLabel.text = "Action failed"
        }
        function onTurboStatus(s) { statsLabel.text = s }
        function onTurboNeedsInstall(need) { /* handled in Main.qml */ }
        function onModelsLoaded(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            modelCombo.model = arr
            if (arr.length > 0 && modelCombo.currentIndex < 0)
                modelCombo.currentIndex = 0
            noModels.visible = arr.length === 0
        }
        function onChatToken(t) {
            if (page.currentAi < 0) return
            chatModel.setProperty(page.currentAi, "body", chatModel.get(page.currentAi).body + t)
            chatList.positionViewAtEnd()
        }
        function onChatDone(stats) {
            if (page.currentAi >= 0) {
                if (chatModel.get(page.currentAi).body.length === 0)
                    chatModel.remove(page.currentAi)
                else if (stats.length > 0)
                    chatModel.setProperty(page.currentAi, "stats", stats)
            }
            statsLabel.text = page.shortStats(stats)
            page.busy = false
            page.currentAi = -1
            chatList.positionViewAtEnd()
            page.persist()          // save the conversation into the HISTORY rail
        }
        function onChatError(e) {
            if (page.currentAi >= 0 && chatModel.get(page.currentAi).body.length === 0)
                chatModel.remove(page.currentAi)   // drop the empty AI placeholder
            chatModel.append({ "role": "error", "body": e + i18n.t("chat.ollamaRunning"), "stats": "" })
            statsLabel.text = i18n.t("chat.error")
            page.busy = false
            page.currentAi = -1
            chatList.positionViewAtEnd()
        }
    }

    ListModel { id: chatModel }

    QQC2.Dialog {
        id: approvalDialog
        modal: true
        focus: true
        closePolicy: QQC2.Popup.NoAutoClose
        width: Math.min(page.width - 48, 520)
        x: (page.width - width) / 2
        y: Math.max(24, (page.height - implicitHeight) / 2)
        padding: 20

        background: Rectangle {
            radius: 8
            color: theme.card
            border.width: 1
            border.color: theme.a(theme.green, 0.55)
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Icon {
                    source: page.pendingApproval.icon || "security-high"
                    color: theme.greenBright
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: page.pendingApproval.title || "Allow this action?"
                        color: theme.textHi
                        font.bold: true
                        font.pixelSize: 17
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        implicitWidth: riskText.implicitWidth + 16
                        implicitHeight: 22
                        radius: 6
                        color: page.pendingApproval.risk === "system-change"
                               ? theme.a(theme.red, 0.16) : theme.a(theme.green, 0.14)
                        border.width: 1
                        border.color: page.pendingApproval.risk === "system-change"
                                      ? theme.a(theme.red, 0.48) : theme.a(theme.green, 0.38)
                        QQC2.Label {
                            id: riskText
                            anchors.centerIn: parent
                            text: page.pendingApproval.risk_label || "Changes your session"
                            color: page.pendingApproval.risk === "system-change" ? theme.red : theme.greenBright
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: page.pendingApproval.description || page.pendingApproval.reason
                      || "Genesi AI wants to perform an action."
                color: theme.textMid
                wrapMode: Text.WordWrap
                font.pixelSize: 13
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: page.pendingApproval.details || []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        QQC2.Label {
                            text: modelData.label
                            color: theme.textLo
                            font.pixelSize: 10
                            font.bold: true
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: theme.textHi
                            font.pixelSize: 13
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.line }

            QQC2.Button {
                flat: true
                text: page.approvalTechnical ? "Hide technical details" : "Technical details"
                icon.name: page.approvalTechnical ? "go-up" : "go-down"
                onClicked: page.approvalTechnical = !page.approvalTechnical
            }

            Rectangle {
                visible: page.approvalTechnical
                Layout.fillWidth: true
                implicitHeight: technicalDetails.implicitHeight + 20
                radius: 6
                color: theme.a(theme.bgBottom, 0.72)
                border.width: 1
                border.color: theme.line
                ColumnLayout {
                    id: technicalDetails
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: "Tool: " + (page.pendingApproval.tool || "action")
                        color: theme.textMid
                        font.bold: true
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: JSON.stringify(page.pendingApproval.arguments || {}, null, 2)
                        color: theme.textMid
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                QQC2.Button {
                    text: "Cancel"
                    onClicked: {
                        backend.resolveApproval(page.pendingApproval.id || "", false)
                        approvalDialog.close()
                    }
                }
                QQC2.Button {
                    text: page.pendingApproval.approve_label || "Allow"
                    highlighted: true
                    onClicked: {
                        backend.resolveApproval(page.pendingApproval.id || "", true)
                        approvalDialog.close()
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top bar: model picker + live status ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: theme.a(theme.bgTop, 0.6)
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label { text: i18n.t("chat.model"); color: theme.textMid; font.pixelSize: 12 }
                QQC2.ComboBox {
                    id: modelCombo
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    // The model holds raw references (Ollama tags and
                    // `gguf:<stem>`), so currentText stays the value the backend
                    // needs; only the rendering is prettified here.
                    displayText: backend.modelLabel(currentText)
                    delegate: QQC2.ItemDelegate {
                        width: modelCombo.width
                        text: backend.modelLabel(modelData)
                        highlighted: modelCombo.highlightedIndex === index
                    }
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: backend.loadModels()
                    QQC2.ToolTip.text: i18n.t("chat.reload")
                    QQC2.ToolTip.visible: hovered
                }
                Rectangle {
                    implicitWidth: agentModeRow.implicitWidth + 6
                    implicitHeight: 34
                    radius: 8
                    color: theme.card
                    border.width: 1
                    border.color: theme.line
                    Row {
                        id: agentModeRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [
                                { "mode": "chat", "label": "Chat" },
                                { "mode": "approval", "label": "Approval" },
                                { "mode": "automatic", "label": "Automatic" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: page.agentMode === modelData.mode
                                height: 28
                                width: agentModeLabel.implicitWidth + 18
                                radius: 6
                                color: selected ? theme.a(theme.green, 0.9)
                                     : (agentModeMouse.containsMouse ? theme.a(theme.textHi, 0.06) : "transparent")
                                QQC2.Label {
                                    id: agentModeLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.selected ? "#ffffff" : theme.textMid
                                    font.bold: parent.selected
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: agentModeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !page.busy
                                    onClicked: backend.setAgentMode(modelData.mode)
                                    QQC2.ToolTip.visible: containsMouse
                                    QQC2.ToolTip.text: modelData.mode === "chat"
                                        ? "Fast conversation without computer access"
                                        : (modelData.mode === "approval"
                                           ? "Ask before every computer action"
                                           : "Run allowed actions automatically")
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    id: statsLabel
                    text: ""
                    color: theme.greenBright
                    font.bold: true
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                }
            }
        }

        Kirigami.InlineMessage {
            id: noModels
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: false
            type: Kirigami.MessageType.Warning
            text: i18n.t("chat.noModels")
        }

        // ── Conversation ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // empty-state
            ColumnLayout {
                anchors.centerIn: parent
                visible: chatModel.count === 0
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72; height: 72; radius: 20
                    color: theme.a(theme.green, 0.10)
                    border.color: theme.a(theme.green, 0.35); border.width: 1
                    Image {
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("icons/chat.svg")
                        sourceSize.width: 38; sourceSize.height: 38
                        width: 38; height: 38
                        smooth: true
                    }
                }
                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n.t("chat.emptyTitle")
                    font.bold: true; font.pixelSize: 16; color: theme.textHi
                }
                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n.t("chat.emptySub")
                    color: theme.textLo
                }
            }

            ListView {
                id: chatList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                clip: true
                spacing: 6
                model: chatModel
                cacheBuffer: 4000
                boundsBehavior: Flickable.StopAtBounds
                delegate: ChatBubble {
                    width: ListView.view.width
                    role: model.role
                    body: model.body
                    stats: model.stats
                    thinking: page.busy && index === page.currentAi && model.body.length === 0
                }
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            }
        }

        // ── Input bar ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: inputRow.implicitHeight + Kirigami.Units.largeSpacing
            color: theme.a(theme.bgTop, 0.6)
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.line }

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                anchors.topMargin: Kirigami.Units.smallSpacing
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 21
                    color: theme.card
                    border.width: 1
                    border.color: input.activeFocus ? theme.green : theme.line
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    QQC2.TextField {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        verticalAlignment: TextInput.AlignVCenter
                        background: null
                        color: theme.textHi
                        placeholderText: i18n.t("chat.placeholder")
                        placeholderTextColor: theme.textLo
                        enabled: !page.busy
                        onAccepted: page.send()
                        // Prefill-as-you-type: debounce keystrokes and warm the
                        // KV cache for the prompt-so-far, so send() is near-instant
                        // (TTFT ≈ 0). onTextEdited fires only on USER edits, so
                        // clearing the field after send() won't trigger a warm.
                        onTextEdited: warmTimer.restart()
                    }
                }

                // stop (while generating)
                Rectangle {
                    visible: page.busy
                    width: 42; height: 42; radius: 21
                    color: stopMa.containsMouse ? theme.a(theme.red, 0.25) : theme.a(theme.red, 0.15)
                    border.color: theme.red; border.width: 1
                    Kirigami.Icon { anchors.centerIn: parent; source: "media-playback-stop"; width: 18; height: 18; color: theme.red }
                    MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: backend.stopChat() }
                }

                // send
                Rectangle {
                    width: 42; height: 42; radius: 21
                    readonly property bool canSend: !page.busy && input.text.trim().length > 0
                    color: canSend ? theme.green : theme.a(theme.textHi, 0.10)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: "document-send"
                        width: 18; height: 18
                        color: parent.canSend ? "#08130E" : theme.textLo
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.canSend
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.send()
                    }
                }
            }
        }
    }
}
