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
    // Genesi Find: when on, the next message searches the user's FILES instead
    // of going to the model. A mode rather than a separate box, because "find
    // my tax pdf" and "what is in my tax pdf" are the same sentence to a person
    // and they should be typed in the same place.
    property bool findMode: false
    property int findIndex: -1
    // One breakpoint. Below it the hero stacks to a single column and the file
    // cards drop the folder from their meta line.
    readonly property bool narrow: page.width < 720
    // The shell owns which tab is showing; the hero's pills ask for one.
    signal navigate(int tab)
    function goTab(t) { page.navigate(t) }
    function prefill(t) {
        input.text = t
        input.forceActiveFocus()
        input.cursorPosition = input.text.length
    }

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
        if (page.busy || q.length === 0)
            return
        // Find needs no model loaded; the chat does.
        if (!page.findMode && modelCombo.currentText.length === 0)
            return
        if (page.findMode) {
            chatModel.append({ "role": "user", "body": q, "stats": "" })
            chatModel.append({ "role": "files", "stats": "",
                               "body": JSON.stringify({ "query": q, "results": [] }) })
            page.findIndex = chatModel.count - 1
            page.busy = true
            statsLabel.text = i18n.t("find.searching")
            backend.findFiles(q)
            input.text = ""
            chatList.positionViewAtEnd()
            return
        }
        chatModel.append({ "role": "user", "body": q, "stats": "" })
        // Send the WHOLE thread (not just this line) so the model has context —
        // this is what makes it remember earlier turns in the same conversation.
        var msgs = []
        for (var i = 0; i < chatModel.count; i++) {
            var m = chatModel.get(i)
            if (m.role === "error" || m.role === "files"
                || !m.body || m.body.length === 0) continue
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
        function onFindStatus(q) { statsLabel.text = i18n.t("find.searching") }
        function onFindResults(jsonStr) {
            if (page.findIndex >= 0 && page.findIndex < chatModel.count)
                chatModel.setProperty(page.findIndex, "body", jsonStr)
            page.findIndex = -1
            page.busy = false
            statsLabel.text = ""
            chatList.positionViewAtEnd()
            page.persist()
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

        // ── Top bar ──
        //
        // Deliberately thin. The model picker used to live here, next to a
        // "Model" label and a reload button, which made the first thing you saw
        // on opening a chat a piece of configuration. It now sits in the
        // composer, an arm's length from the message it applies to, and this
        // bar carries only what the page IS and what it is doing right now.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            color: "transparent"
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: theme.hairline
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.sp5
                anchors.rightMargin: theme.sp4
                spacing: theme.sp3

                QQC2.Label {
                    text: page.title
                    color: theme.textHi
                    font.pixelSize: theme.fsHead
                    font.bold: true
                }
                Rectangle {
                    Layout.preferredWidth: localTag.implicitWidth + theme.sp3
                    Layout.preferredHeight: 20
                    radius: theme.rSm - 2
                    color: theme.a(theme.green, 0.14)
                    border.width: 1
                    border.color: theme.a(theme.green, 0.30)
                    QQC2.Label {
                        id: localTag
                        anchors.centerIn: parent
                        text: "Local"
                        color: theme.accentText
                        font.pixelSize: theme.fsMicro
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                QQC2.Label {
                    id: statsLabel
                    text: ""
                    color: theme.greenBright
                    font.bold: true
                    font.pixelSize: theme.fsSmall
                    elide: Text.ElideRight
                    Layout.maximumWidth: Math.max(0, page.width * 0.28)
                }

                // How much of the computer the AI may touch. Three states, so a
                // segmented control rather than a switch: "approval" is a real
                // middle position, not a half-on version of automatic.
                Rectangle {
                    implicitWidth: agentModeRow.implicitWidth + 6
                    implicitHeight: 30
                    radius: theme.rSm
                    color: theme.surface
                    border.width: 1
                    border.color: theme.hairline
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
                                height: 24
                                width: agentModeLabel.implicitWidth + 18
                                radius: theme.rSm - 2
                                color: selected ? theme.green
                                     : (agentModeMouse.containsMouse ? theme.hover : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                                QQC2.Label {
                                    id: agentModeLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.selected ? "#08130E" : theme.textMid
                                    font.bold: parent.selected
                                    font.pixelSize: theme.fsSmall
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

            // ── Empty state: a hero, not an apology ──
            //
            // The old one was an icon and two lines that said the chat was
            // empty, which the empty chat had already made clear. This says
            // what the thing can DO, in three cards the user can click into,
            // and the row of pills underneath reaches the rest of Genesi from
            // the same place.
            Flickable {
                id: heroFlick
                anchors.fill: parent
                visible: chatModel.count === 0
                contentWidth: width
                // Centred while it fits, scrollable once it does not -- which is
                // what happens on a short window, and the reason this is a
                // Flickable rather than a centred ColumnLayout.
                contentHeight: Math.max(height, hero.implicitHeight + theme.sp6 * 2)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                ColumnLayout {
                    id: hero
                    // heroFlick.height, NOT parent.height: a Flickable reparents
                    // its children into contentItem, whose height is
                    // contentHeight. Measuring against that centres the block
                    // inside itself and lands it at the top of the viewport.
                    y: Math.max(theme.sp5, (heroFlick.height - implicitHeight) / 2)
                    x: Math.max(theme.sp4, (heroFlick.width - width) / 2)
                    width: Math.min(heroFlick.width - theme.sp5 * 2, 860)
                    spacing: theme.sp4

                    // The orb. Concentric translucent circles rather than a
                    // radial-gradient shader: this has to render identically on
                    // the software backend a VM falls back to, where shader
                    // effects are unsupported and crash-prone.
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 96
                        Repeater {
                            model: [
                                { "d": 96, "o": 0.07 },
                                { "d": 76, "o": 0.10 },
                                { "d": 58, "o": 0.16 },
                                { "d": 42, "o": 0.26 },
                                { "d": 28, "o": 0.55 }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                anchors.centerIn: parent
                                width: modelData.d
                                height: modelData.d
                                radius: width / 2
                                color: theme.a(theme.greenBright, modelData.o)
                            }
                        }
                        FIcon {
                            anchors.centerIn: parent
                            name: "zap"
                            size: 18
                            color: "#ffffff"
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: i18n.t("chat.hero")
                        color: theme.textHi
                        font.pixelSize: page.narrow ? theme.fsTitle + 3 : theme.fsDisplay
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.bottomMargin: theme.sp2
                        horizontalAlignment: Text.AlignHCenter
                        text: i18n.t("chat.heroSub")
                        color: theme.textLo
                        font.pixelSize: theme.fsBody
                        wrapMode: Text.WordWrap
                    }

                    // One column when there is not room for three. Anything in
                    // between would squeeze the body text into a column two
                    // words wide, which is worse than stacking.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: page.narrow ? 1 : 3
                        rowSpacing: theme.sp3
                        columnSpacing: theme.sp3

                        SuggestCard {
                            icon: "bot"; tint: theme.green
                            title: i18n.t("chat.sug1Title")
                            body: i18n.t("chat.sug1Body")
                            tag: i18n.t("chat.sug1Tag")
                            onPicked: page.prefill(i18n.t("chat.sug1Body"))
                        }
                        SuggestCard {
                            icon: "layers"; tint: theme.blue
                            title: i18n.t("chat.sug2Title")
                            body: i18n.t("chat.sug2Body")
                            tag: i18n.t("chat.sug2Tag")
                            onPicked: page.prefill(i18n.t("chat.sug2Body"))
                        }
                        SuggestCard {
                            icon: "search"; tint: theme.purple
                            title: i18n.t("chat.sug3Title")
                            body: i18n.t("chat.sug3Body")
                            tag: i18n.t("chat.sug3Tag")
                            onPicked: { page.findMode = true; input.forceActiveFocus() }
                        }
                    }

                    // Flow, not RowLayout: these wrap onto a second line on a
                    // narrow window instead of being elided into stubs.
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: theme.sp2
                        spacing: theme.sp2
                        GPill {
                            icon: "search"
                            label: i18n.t("find.name")
                            active: page.findMode
                            tooltip: i18n.t("find.on")
                            onClicked: { page.findMode = !page.findMode; input.forceActiveFocus() }
                        }
                        GPill {
                            icon: "layers"; label: "Models"
                            onClicked: page.goTab(2)
                        }
                        GPill {
                            icon: "zap"; label: "Automations"
                            onClicked: page.goTab(3)
                        }
                        GPill {
                            icon: "layout-grid"; label: "Dashboard"
                            onClicked: page.goTab(0)
                        }
                    }
                }
            }

            ListView {
                id: chatList
                anchors.fill: parent
                anchors.leftMargin: theme.sp5
                anchors.rightMargin: theme.sp5
                anchors.topMargin: theme.sp4
                anchors.bottomMargin: theme.sp2
                visible: chatModel.count > 0
                clip: true
                spacing: theme.sp2
                model: chatModel
                cacheBuffer: 4000
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                // One delegate, two shapes. A Loader would need the model row
                // copied across a scope boundary; keeping both here and toggling
                // `visible` is duller and cannot get that wrong.
                delegate: Item {
                    id: convRow
                    width: ListView.view.width
                    readonly property bool isFiles: model.role === "files"
                    implicitHeight: isFiles ? fileBlock.implicitHeight : bubble.implicitHeight
                    height: implicitHeight

                    ChatBubble {
                        id: bubble
                        width: convRow.width
                        visible: !convRow.isFiles
                        role: model.role
                        body: model.body
                        stats: model.stats
                        thinking: page.busy && index === page.currentAi && model.body.length === 0
                    }

                    // ── Genesi Find results, in the conversation ──
                    ColumnLayout {
                        id: fileBlock
                        width: convRow.width
                        visible: convRow.isFiles
                        spacing: theme.sp2

                        readonly property var payload: {
                            try { return JSON.parse(model.body) } catch (e) { return ({}) }
                        }
                        readonly property var rows: payload.results || []

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 2
                            spacing: theme.sp2
                            FIcon { name: "search"; size: 13; color: theme.greenBright }
                            QQC2.Label {
                                text: i18n.t("find.name")
                                color: theme.greenBright
                                font.pixelSize: theme.fsSmall
                                font.bold: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: fileBlock.payload.error
                                      ? fileBlock.payload.error
                                      : (fileBlock.rows.length === 0
                                         ? i18n.t("find.none")
                                         : fileBlock.rows.length + " " + i18n.t("find.count"))
                                color: theme.textLo
                                font.pixelSize: theme.fsSmall
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            model: fileBlock.rows
                            delegate: FileCard {
                                required property var modelData
                                i18n: page.i18n
                                path: modelData.path || ""
                                name: modelData.name || ""
                                dir: modelData.dir || ""
                                age: modelData.age || ""
                                hsize: modelData.hsize || ""
                            }
                        }
                    }
                }
            }
        }

        // ── Composer ──
        //
        // One surface holding the message and everything that applies to it:
        // which model will answer, whether Genesi Find runs first, and what is
        // attached. The model picker used to live in the top bar, two thirds of
        // a window away from the text it governed.
        Item {
            Layout.fillWidth: true
            implicitHeight: composer.implicitHeight + theme.sp5

            Rectangle {
                id: composer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width - theme.sp5 * 2, 980)
                implicitHeight: composerCol.implicitHeight + theme.sp3 * 2
                radius: theme.rXl
                color: theme.surface
                border.width: 1
                border.color: input.activeFocus ? theme.a(theme.green, 0.55) : theme.hairline
                Behavior on border.color { ColorAnimation { duration: 150 } }

                ColumnLayout {
                    id: composerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: theme.sp4
                    anchors.rightMargin: theme.sp3
                    anchors.topMargin: theme.sp3
                    spacing: theme.sp2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: theme.sp3

                        FIcon {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 7
                            name: page.findMode ? "search" : "zap"
                            size: 15
                            color: page.findMode ? theme.greenBright : theme.textLo
                        }

                        // A TextArea, not a TextField: an answer worth asking
                        // for is often longer than one line, and the box grows
                        // to five before it starts scrolling. Enter sends,
                        // Shift+Enter breaks the line -- the convention every
                        // chat uses, and the reason the key handling is
                        // explicit rather than onAccepted.
                        QQC2.TextArea {
                            id: input
                            Layout.fillWidth: true
                            Layout.minimumHeight: 30
                            Layout.maximumHeight: 132
                            background: null
                            color: theme.textHi
                            font.pixelSize: theme.fsBody
                            wrapMode: Text.Wrap
                            placeholderText: page.findMode ? i18n.t("find.placeholder")
                                                           : i18n.t("chat.placeholder")
                            placeholderTextColor: theme.textLo
                            enabled: !page.busy
                            // Prefill-as-you-type: debounce keystrokes and warm
                            // the KV cache for the prompt-so-far so send() is
                            // near-instant. onTextEdited fires only on USER
                            // edits, so clearing after send() will not warm.
                            onTextEdited: warmTimer.restart()
                            Keys.onPressed: function (event) {
                                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                                    return
                                if (event.modifiers & Qt.ShiftModifier)
                                    return          // let it insert a newline
                                event.accepted = true
                                page.send()
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 2
                            visible: page.busy
                            width: 34; height: 34; radius: theme.rMd
                            color: stopMa.containsMouse ? theme.a(theme.red, 0.28)
                                                        : theme.a(theme.red, 0.16)
                            border.color: theme.a(theme.red, 0.55); border.width: 1
                            FIcon { anchors.centerIn: parent; name: "square"; size: 13; color: theme.red }
                            MouseArea {
                                id: stopMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.stopChat()
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.text: i18n.t("chat.stop")
                            }
                        }

                        Rectangle {
                            id: sendBtn
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 2
                            visible: !page.busy
                            readonly property bool canSend: input.text.trim().length > 0
                            width: sendRow.implicitWidth + theme.sp4
                            height: 34
                            radius: theme.rMd
                            color: canSend ? theme.green : theme.a(theme.textHi, 0.07)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            RowLayout {
                                id: sendRow
                                anchors.centerIn: parent
                                spacing: theme.sp1 + 2
                                QQC2.Label {
                                    text: i18n.t("chat.send")
                                    color: sendBtn.canSend ? "#08130E" : theme.textLo
                                    font.pixelSize: theme.fsSmall
                                    font.bold: true
                                }
                                FIcon {
                                    name: "arrow-up"
                                    size: 12
                                    color: sendBtn.canSend ? "#08130E" : theme.textLo
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: sendBtn.canSend
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.send()
                            }
                        }
                    }

                    // What applies to the message. Flow so it wraps rather than
                    // eliding on a narrow window.
                    Flow {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        spacing: theme.sp2

                        // The model chip. The combo underneath is invisible and
                        // does the work: writing a popup list from scratch to
                        // get a chip-shaped button would be a lot of surface
                        // area for a rounded corner.
                        Rectangle {
                            width: modelChipRow.implicitWidth + theme.sp3
                            height: 26
                            radius: theme.rPill
                            color: modelMa.containsMouse ? theme.hover : "transparent"
                            border.width: 1
                            border.color: theme.hairline
                            RowLayout {
                                id: modelChipRow
                                anchors.centerIn: parent
                                spacing: theme.sp1 + 1
                                FIcon { name: "layers"; size: 12; color: theme.textLo }
                                QQC2.Label {
                                    text: backend.modelLabel(modelCombo.currentText)
                                          || i18n.t("chat.model")
                                    color: theme.textMid
                                    font.pixelSize: theme.fsMicro
                                }
                                FIcon { name: "chevron-down"; size: 10; color: theme.textLo }
                            }
                            MouseArea {
                                id: modelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelCombo.popup.open()
                            }
                            QQC2.ComboBox {
                                id: modelCombo
                                anchors.fill: parent
                                opacity: 0
                                enabled: false          // the chip above drives it
                                // The model holds raw references (Ollama tags
                                // and `gguf:<stem>`), so currentText stays the
                                // value the backend needs; only the rendering
                                // is prettified.
                                displayText: backend.modelLabel(currentText)
                                delegate: QQC2.ItemDelegate {
                                    width: modelCombo.width
                                    text: backend.modelLabel(modelData)
                                    highlighted: modelCombo.highlightedIndex === index
                                }
                            }
                        }

                        GPill {
                            icon: "search"
                            label: i18n.t("find.name")
                            active: page.findMode
                            tooltip: i18n.t("find.on")
                            onClicked: page.findMode = !page.findMode
                        }
                        GPill {
                            icon: "refresh-cw"
                            label: i18n.t("chat.reload")
                            onClicked: backend.loadModels()
                        }

                        Item { width: 1; height: 1 }
                    }
                }
            }
        }
    }
}
