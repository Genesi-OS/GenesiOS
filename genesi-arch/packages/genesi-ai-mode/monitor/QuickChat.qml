import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import QtCore as QtCore
import org.kde.kirigami as Kirigami

// Genesi AI Quick Chat — Ctrl+Alt+Space from anywhere.
//
// One window, three faces: a bare composer (the leaf and a field), the
// conversation once there is one, and the settings. It talks to the AI
// island at the top of the screen in both directions: it publishes what it
// is doing for the island to show, and it answers what is asked ON the
// island (askFromIsland) without opening at all -- the answer goes back up
// to the island.
QQC2.ApplicationWindow {
    id: root
    width: 720
    // What the content needs. Not bound to `height` directly -- see below.
    readonly property int wantedHeight: Math.min(640, Math.max(92, body.implicitHeight + 40))
    height: 92
    // Minimum and maximum are the SAME number, and that number is the height
    // the content needs.
    //
    // The first fix told the compositor a range -- 92 to 620 high, 520 to 820
    // wide -- on the reasoning that a compositor given bounds stays inside
    // them. It did: Hyprland picked the top of both, 820 by 620, and the card
    // drew in the top 90 pixels of it. Everything below was transparent
    // surface, and Hyprland blurs what is behind a transparent window, so what
    // anyone saw was a small bar on top of a large frosted rectangle that ate
    // every click. A range is a choice, and the compositor made it.
    //
    // A single legal size is not a choice. Qt forwards these as the
    // xdg_toplevel min and max, and when they are equal the window is that
    // size -- and when the content grows they both move, so the window grows
    // with it rather than being told it may.
    //
    // ...and they have to move in the right ORDER. Growing moves the maximum
    // first, then the height, then the minimum; shrinking does the reverse.
    // Whichever way it goes, the height being set is always inside the bounds
    // at that moment. (All three as bindings once locked the window at the
    // size of the bare prompt bar, with the settings laid out out of sight.)
    minimumWidth: 720
    maximumWidth: 720
    minimumHeight: 92
    maximumHeight: 92
    function applyHeight() {
        const h = wantedHeight
        if (h > height) {
            maximumHeight = h
            height = h
            minimumHeight = h
        } else if (h < height) {
            minimumHeight = h
            height = h
            maximumHeight = h
        }
    }
    onWantedHeightChanged: applyHeight()

    // What the compositor did with the size we asked for: a TILED Hyprland
    // window ignores it. If the window is not the size it asked for, ask
    // Hyprland to float it -- twice at most, never in a loop.
    property int fitAttempts: 0
    function checkSize() {
        if (!visible || fitAttempts >= 2)
            return;
        if (Math.abs(width - 720) < 2)
            return;
        fitAttempts += 1;
        backend.fitWindow(720, wantedHeight, Screen.devicePixelRatio);
    }
    onWidthChanged: fitTimer.restart()
    Timer {
        id: fitTimer
        interval: 250
        onTriggered: root.checkSize()
    }
    visible: false
    color: "transparent"
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: "Genesi AI Quick Chat"

    readonly property bool pt: Qt.locale().name.startsWith("pt")
    function t(en, ptText) { return pt ? ptText : en }
    // The agent's own activity words are English; shown in the person's.
    function say(text) {
        if (!pt) return text
        var map = {"Thinking": "Pensando", "Running an action": "Executando uma ação",
                   "Preparing the action": "Preparando a ação", "Reviewing the result": "Revisando o resultado",
                   "Checking what went wrong": "Vendo o que deu errado",
                   "Waiting for your approval": "Esperando sua aprovação",
                   "Stopped": "Parado", "Stopping": "Parando"}
        return map[text] || text
    }

    property bool expanded: settingsOpen || conversation.length > 0 || thinking || pendingApproval !== null
                            || attachments.length > 0
    readonly property bool starters: !expanded && prompt.text.length === 0
    property bool thinking: false
    property bool settingsOpen: false
    property bool technicalOpen: false
    property var pendingApproval: null
    property var conversation: []
    property var timeline: []
    property string activityText: "Thinking"
    // Files the person attached (dropped here or on the AI island): what the
    // backend read from each, shown as chips until the message goes out.
    property var attachments: []
    // For the AI island: the last agent state, how the last request ended
    // ("done", "error" or ""), and where in the timeline it began.
    property string activityState: ""
    property string lastOutcome: ""
    property int turnStart: 0
    property string lastPrompt: ""
    // The request was asked ON the island: its answer is shown there whole,
    // and the window stays where it is.
    property bool islandTurn: false
    property double turnStartedAt: 0
    property double turnTook: 0
    // Smart Copy: what the island should offer about the clipboard.
    property var clipHint: null
    property var islandPrefs: ({})
    property string actionMode: backend.agentMode() === "automatic" ? "automatic" : "approval"
    property var availableModels: []
    property string modelName: backend.quickModel()
    property bool aiActive: false
    property bool voiceReady: backend.voiceReady()
    property bool speakAnswers: backend.speakAnswers()
    // Local or API -- the same switch, and the same remembered choice, as the
    // Monitor's chat. The API side is a provider and a model typed the way
    // that provider names it.
    property string source: backend.chatSource()
    property var cloudProviders: []         // the ones with a key: [{provider, model, ref}]
    property var cloudKnown: []             // every provider Genesi knows, key or not
    property string cloudProvider: ""
    property var cloudSuggestions: []
    property string cloudKeyDraft: ""
    readonly property string cloudModel: {
        for (var i = 0; i < cloudProviders.length; ++i)
            if (cloudProviders[i].provider === cloudProvider)
                return cloudProviders[i].model
        return ""
    }
    readonly property bool cloudReady: {
        for (var i = 0; i < cloudProviders.length; ++i)
            if (cloudProviders[i].provider === cloudProvider)
                return true
        return false
    }
    readonly property var cloudInfo: {
        for (var i = 0; i < cloudKnown.length; ++i)
            if (cloudKnown[i].provider === cloudProvider)
                return cloudKnown[i]
        return ({ "provider": cloudProvider, "label": cloudProvider, "suggested": [], "keyUrl": "" })
    }
    // What to pick from: the provider's own list once it answered, after the
    // ones Genesi suggests -- each name once.
    readonly property var cloudChoices: {
        var out = []
        // The model in use first: a list without it shows another name.
        var all = [cloudModel].concat(cloudInfo.suggested || [], cloudSuggestions || [])
        for (var i = 0; i < all.length; ++i)
            if (all[i] && out.indexOf(all[i]) < 0) out.push(all[i])
        return out
    }
    readonly property string currentRef: source === "api"
        ? (cloudReady ? "cloud:" + cloudProvider : "") : modelName
    // What the footer says. Built here from the provider and its model, not
    // asked of the backend: a slot call in a binding only re-runs when its
    // ARGUMENT changes, and "cloud:gemini" stays "cloud:gemini" when the
    // model under it changes -- so the footer kept naming the old model.
    readonly property string currentLabel: source === "api"
        ? (cloudReady ? (cloudInfo.label || cloudProvider) + " · " + cloudModel : "")
        : (modelName ? backend.modelLabel(modelName) : "")
    function pickCloudModel(name) {
        name = String(name || "").trim()
        if (!name || !cloudProvider) return
        // Shown at once; the file follows (backend.setCloudModel re-reads it).
        var next = []
        for (var i = 0; i < cloudProviders.length; ++i) {
            var p = cloudProviders[i]
            next.push(p.provider === cloudProvider ? {"provider": p.provider, "model": name, "ref": p.ref} : p)
        }
        cloudProviders = next
        backend.setCloudModel(cloudProvider, name)
        publishIsland()
    }
    function pickCloudProvider(id) {
        cloudProvider = id
        cloudSuggestions = []
        cloudKeyDraft = ""
        for (var i = 0; i < cloudProviders.length; ++i)
            if (cloudProviders[i].provider === id) {
                backend.useCloudProvider(id)
                backend.listCloudModels(id)
            }
    }
    property var voiceLanguages: []
    property string voiceLanguage: ""
    property string forceMode: "auto"
    property string profileMode: "auto"
    property bool turboRequested: backend.quickTurboActive()
    property bool turboStarting: false
    property bool turboSpec: false
    property bool turboNeedsInstall: false
    property string turboStatusText: ""
    readonly property color textHi: theme.textHi
    readonly property color textMid: theme.textMid
    readonly property color textLo: theme.textLo
    readonly property color amber: "#F0A43A"

    palette.window: theme.bgBottom
    palette.windowText: textHi
    palette.base: theme.card
    palette.text: textHi
    palette.button: theme.cardHi
    palette.buttonText: textHi
    palette.highlight: theme.green
    palette.highlightedText: "#ffffff"

    // The leaf's mood is the chat's state, the same as on the island.
    readonly property string leafMood: pendingApproval !== null ? "hot"
        : lastOutcome === "error" && !thinking ? "sick"
        : thinking && activityState === "running" ? "dancing"
        : lastOutcome === "done" && !thinking ? "happy"
        : "normal"

    function reposition() {
        x = Math.round((Screen.desktopAvailableWidth - width) / 2)
        y = Math.max(24, Math.round(Screen.desktopAvailableHeight * 0.07))
    }
    function showQuick() {
        backend.refreshModel()
        reposition()
        show()
        fitTimer.restart()
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

    // ── The AI island ───────────────────────────────────────────────────────
    // What this window is doing, written for the island to show. Throttled:
    // tokens stream in many times a second, the island needs a few.
    function publishIsland() { if (!islandTimer.running) islandTimer.start() }
    function islandState() {
        var steps = []
        for (var i = turnStart; i < timeline.length; ++i)
            if (timeline[i].kind === "action")
                steps.push({"title": timeline[i].title, "state": timeline[i].state,
                            "message": timeline[i].message})
        var answer = ""
        for (var j = conversation.length - 1; j >= 0; --j) {
            if (conversation[j].role !== "assistant") break
            answer = conversation[j].content + answer
        }
        var phase = "idle"
        if (pendingApproval !== null) phase = "approval"
        else if (thinking) phase = activityState === "running" ? "running" : "thinking"
        else if (lastOutcome) phase = lastOutcome
        var approval = null
        if (pendingApproval !== null) {
            var args = pendingApproval.arguments || {}
            var details = pendingApproval.details || []
            approval = {
                "id": pendingApproval.id || "",
                "title": pendingApproval.title || "",
                "description": pendingApproval.description || "",
                "risk": pendingApproval.risk_label || "",
                "approve": pendingApproval.approve_label || "Allow",
                "detail": String(args.command || (details.length ? details[0].value : "")
                                 || pendingApproval.reason || "")
            }
        }
        // Asked on the island: the whole answer goes up (it is read there).
        // Asked here: its start, for a glance.
        answer = answer.trim()
        answer = islandTurn ? answer.slice(0, 4000) : answer.slice(-320)
        return {
            "v": 2, "open": visible, "phase": phase, "activity": say(activityText), "turn": turnStart,
            "steps": steps.slice(-4), "total": steps.length,
            "approval": approval, "answer": answer,
            "prompt": lastPrompt.slice(0, 160), "model": currentLabel || currentRef,
            "attachments": attachments.length,
            "inline": islandTurn, "elapsed": Math.round(turnTook),
            "actionMode": actionMode, "hint": clipHint
        }
    }
    // An answer given on the island. The id is checked: an approval that
    // timed out and was replaced must not be answered by a stale click.
    function islandAnswer(id, approved) {
        if (pendingApproval === null) return
        if (id && pendingApproval.id && id !== pendingApproval.id) return
        resolveApproval(approved)
    }
    // A question asked ON the island (or from caelestia's launcher, >ai).
    // The window stays where it is -- the island shows the answer -- unless
    // no island is there to show it.
    function askFromIsland(text, withClip) {
        if (thinking || pendingApproval !== null) return
        var question = String(text || "").trim()
        if (!question) return
        clipHint = null
        var full = question
        var shown = question
        if (withClip) {
            var clip = backend.clipboardText()
            if (!clip || !clip.trim()) {
                islandTurn = true
                lastPrompt = question
                turnStart = timeline.length
                addMessage("assistant", t("There is nothing copied to look at. Copy some text and ask again.",
                                          "Não tem nada copiado para eu ver. Copie um texto e pergunte de novo."))
                lastOutcome = "error"
                publishIsland()
                return
            }
            full = backend.clipPrompt(question, clip)
            shown = "📋 " + question
        }
        if (!backend.islandShowsApprovals())
            showQuick()
        sendText(full, shown, true)
    }
    function islandSetting(key, value) {
        if (key === "actions") setActionMode(value)
        else if (key === "smartClip") backend.setSmartClip(value === "on")
        islandPrefs = JSON.parse(backend.islandPrefs())
        publishIsland()
    }
    function showClipHint(kind, preview) {
        if (thinking || pendingApproval !== null) return
        clipHint = {"id": "clip-" + Date.now(), "kind": kind, "preview": preview}
        hintExpiry.restart()
        publishIsland()
    }
    Timer {
        id: hintExpiry
        interval: 15000
        onTriggered: { root.clipHint = null; root.publishIsland() }
    }
    function setIslandPref(key, value) {
        islandPrefs = JSON.parse(backend.setIslandPref(key, value))
        publishIsland()
    }
    function addAttachment(source) {
        var info = {}
        try { info = JSON.parse(backend.attachFile(source)) } catch (e) { return }
        if (info.error === "not-found" || info.error === "unreadable") return
        for (var i = 0; i < attachments.length; ++i)
            if (attachments[i].path === info.path) return
        var next = attachments.slice(0)
        next.push(info)
        attachments = next
    }
    function removeAttachment(path) {
        backend.detachFile(path)
        attachments = attachments.filter(function(a) { return a.path !== path })
    }
    // A file dropped on the island: attach it, open, and -- when the island's
    // button said what to do with it -- ask right away.
    function attachAndShow(path, request) {
        addAttachment(path)
        showQuick()
        if (request && !thinking && pendingApproval === null) {
            prompt.text = request
            sendPrompt()
        }
    }
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
    function setActionMode(mode) {
        if (thinking || pendingApproval !== null || (mode !== "approval" && mode !== "automatic")) return
        actionMode = mode
        backend.setAgentMode(mode)
        publishIsland()
    }
    function stopWork() {
        if (!thinking && pendingApproval === null) return
        activityText = "Stopping"
        pendingApproval = null
        technicalOpen = false
        backend.stopChat()
    }
    // `shown` is what the window prints when it differs from what the model
    // is given -- a message with files carries their text, and nobody needs
    // to scroll past a whole PDF to read their own question.
    function addMessage(role, content, shown) {
        var next = conversation.slice(0)
        next.push({"role": role, "content": content})
        conversation = next
        var visual = timeline.slice(0)
        visual.push({"kind": "message", "role": role, "content": shown !== undefined ? shown : content,
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
        activityState = state
        if (state === "complete") lastOutcome = "done"
        else if (["error", "limit-reached", "repeat-blocked"].indexOf(state) >= 0) lastOutcome = "error"
        else if (state === "stopped") lastOutcome = ""
        if (["waiting-approval", "running", "action-complete", "action-error", "denied", "stopped"].indexOf(state) >= 0)
            rememberAction(activity)
        if (state === "running") activityText = activity.reason || "Running an action"
        else if (state === "repairing-action") activityText = "Preparing the action"
        else if (state === "action-complete") activityText = "Reviewing the result"
        else if (state === "action-error") activityText = "Checking what went wrong"
        else if (state === "waiting-approval") activityText = "Waiting for your approval"
        else if (state === "stopped") activityText = "Stopped"
        else if (state === "thinking") activityText = activity.message || "Thinking"
        var terminal = ["complete", "error", "stopped", "limit-reached", "repeat-blocked"].indexOf(state) >= 0
        thinking = !terminal
        if (terminal) markTurnEnd()
    }
    function markTurnEnd() {
        if (turnStartedAt > 0) turnTook = Date.now() - turnStartedAt
    }
    function sendPrompt() {
        var text = prompt.text.trim()
        if (!text) return
        if (attachments.length > 0) {
            var paths = attachments.map(function(a) { return a.path })
            var names = attachments.map(function(a) { return "📎 " + a.name }).join("  ")
            var context = backend.attachmentContext(JSON.stringify(paths))
            attachments = []
            sendText(context ? context + "\n\n" + text : text, names + "\n" + text, false)
        } else {
            sendText(text, text, false)
        }
    }
    // Every question goes out through here: typed in the window, a starter
    // chip, or asked on the island.
    function sendText(full, shown, fromIsland) {
        if (!full || thinking || pendingApproval !== null) return
        if (!currentRef) {
            islandTurn = fromIsland
            addMessage("assistant", source === "api"
                ? t("No API key for this provider yet. Paste one in the settings (the sliders button).",
                    "Ainda não tem chave para esse provedor. Cole uma nas configurações (o botão de ajustes).")
                : t("No local model is ready. Install a model in AI Mode first.",
                    "Nenhum modelo local pronto. Instale um modelo no Modo IA primeiro."))
            lastOutcome = "error"
            return
        }
        islandTurn = fromIsland
        turnStart = timeline.length
        turnStartedAt = Date.now()
        turnTook = 0
        lastPrompt = shown.replace(/^📋 /, "").split("\n").pop()
        lastOutcome = ""
        activityState = "thinking"
        addMessage("user", full, shown)
        prompt.text = ""
        settingsOpen = false
        activityText = "Thinking"
        thinking = true
        // The agent loop runs on this machine and asks the chosen model --
        // local or a provider's -- what to do next, so an API model can open
        // apps and run commands too.
        backend.sendAgentPrompt(currentRef, JSON.stringify(conversation), actionMode)
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
    function newChat() {
        conversation = []
        timeline = []
        lastOutcome = ""
        islandTurn = false
        publishIsland()
        prompt.forceActiveFocus()
    }

    onClosing: function(close) {
        close.accepted = false
        hideQuick()
    }
    onVisibleChanged: {
        if (visible) reposition()
        publishIsland()
    }
    onThinkingChanged: publishIsland()
    onPendingApprovalChanged: publishIsland()
    onTimelineChanged: publishIsland()
    onActivityTextChanged: publishIsland()
    onLastOutcomeChanged: publishIsland()
    onAttachmentsChanged: publishIsland()
    Timer {
        id: islandTimer
        interval: 150
        onTriggered: backend.publishIsland(JSON.stringify(root.islandState()))
    }

    Theme { id: theme }
    QtCore.Settings {
        category: "QuickChat"
        property alias selectedModel: root.modelName
        property alias speculative: root.turboSpec
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.pollState() }
    Component.onCompleted: {
        // One onCompleted per object: a second one is a load error that
        // takes the whole window with it.
        applyHeight()
        backend.loadModels()
        backend.loadCloud()
        backend.loadVoiceLanguages()
        backend.backendInfo()
        islandPrefs = JSON.parse(backend.islandPrefs())
        publishIsland()
    }

    FileDialog {
        id: attachDialog
        title: root.t("Attach a file", "Anexar um arquivo")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; ++i)
                root.addAttachment(selectedFiles[i].toString())
            prompt.forceActiveFocus()
        }
    }

    // ── Small pieces ────────────────────────────────────────────────────────
    // A round icon button.
    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property string tip: ""
        property bool active: false
        property color tone: theme.textMid
        property color hoverFill: theme.hover
        signal clicked
        implicitWidth: 34; implicitHeight: 34
        radius: 17
        color: rb.active ? theme.a(theme.green, 0.18) : (rbMa.containsMouse ? rb.hoverFill : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        FIcon {
            anchors.centerIn: parent
            name: rb.icon; size: 15
            color: rb.active ? theme.accentText : rb.tone
        }
        MouseArea {
            id: rbMa
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
            QQC2.ToolTip.visible: containsMouse && rb.tip !== ""
            QQC2.ToolTip.text: rb.tip
            QQC2.ToolTip.delay: 500
        }
    }
    // A segmented choice: one of a few values, the chosen one filled.
    component Seg: Rectangle {
        id: seg
        property var options: []        // [{value, label}]
        property var current
        property color fillOn: theme.green
        signal picked(var value)
        implicitWidth: segRow.implicitWidth + 6
        implicitHeight: 30
        radius: 15
        color: theme.a(theme.textHi, 0.05)
        border.width: 1
        border.color: theme.hairline
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: seg.current === modelData.value
                    width: segLabel.implicitWidth + 22; height: 24
                    radius: 12
                    color: on ? seg.fillOn : (segMa.containsMouse ? theme.hover : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                    QQC2.Label {
                        id: segLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.on ? "#ffffff" : root.textMid
                        font.pixelSize: 11; font.bold: parent.on
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.value)
                    }
                }
            }
        }
    }
    component SectionTitle: QQC2.Label {
        color: root.textLo
        font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.2
        Layout.topMargin: 4
    }
    component RowLabel: QQC2.Label {
        color: root.textMid
        font.pixelSize: 12
        Layout.preferredWidth: 120
    }

    Rectangle {
        id: card
        // Sized and centred, NOT filled: when a windowrule fails to match,
        // the surface is the whole workspace, and a filled card stretched
        // across it was the "giant frosted rectangle" bug. Sized this way the
        // card looks right wherever it is put, and fitWindow() asks Hyprland
        // for the window back.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        width: Math.min(704, parent.width - 16)
        height: Math.min(parent.height - 16, body.implicitHeight + 24)
        radius: 24
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
        }
        border.width: 1
        border.color: root.pendingApproval ? theme.a(root.amber, 0.6)
                    : prompt.activeFocus ? theme.a(theme.green, 0.35) : theme.hairline
        Behavior on border.color { ColorAnimation { duration: 200 } }
        clip: true

        // Drag-to-move from any non-interactive spot (no titlebar needed).
        // Only past the drag threshold, and never stealing the pointer from
        // the field, the buttons or the chat once they own the press.
        DragHandler {
            target: null
            grabPermissions: PointerHandler.TakeOverForbidden
            onActiveChanged: if (active) root.startSystemMove()
        }

        // Working: a light running along the top edge.
        Item {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: 24; anchors.rightMargin: 24
            height: 2
            visible: root.thinking
            clip: true
            Rectangle {
                id: pulse
                width: parent.width * 0.3; height: 2; radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: theme.greenBright }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on x {
                    running: root.thinking
                    loops: Animation.Infinite
                    NumberAnimation { from: -pulse.width; to: pulse.parent.width; duration: 1300; easing.type: Easing.InOutSine }
                }
            }
        }

        DropArea {
            id: dropZone
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: function(drop) {
                for (var i = 0; i < drop.urls.length; ++i)
                    root.addAttachment(drop.urls[i].toString())
                drop.accept()
            }
        }
        Rectangle {
            // Dropping: the whole card says so.
            anchors.fill: parent; anchors.margins: 6
            radius: 20
            visible: dropZone.containsDrag
            color: theme.a(theme.green, 0.10)
            border.width: 1.5; border.color: theme.a(theme.green, 0.6)
            QQC2.Label {
                anchors.centerIn: parent
                text: root.t("Drop to attach", "Solte para anexar")
                color: root.textHi; font.pixelSize: 14; font.bold: true
            }
        }

        ColumnLayout {
            id: body
            // Anchored on three sides, NOT filled: the window's height reads
            // body.implicitHeight, and a filled layout would read the window
            // back -- a loop that settles at the cap.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // ── The composer ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    radius: 22
                    color: theme.a(root.leafMood === "hot" ? root.amber
                                   : root.leafMood === "sick" ? theme.red : theme.green, 0.14)
                    Behavior on color { ColorAnimation { duration: 250 } }
                    GenesiLeaf {
                        id: leaf
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1
                        size: 30
                        mood: root.leafMood
                        talking: root.thinking
                        pal: ({ "m3primary": theme.green })
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 22
                    color: theme.a(theme.textHi, 0.05)
                    border.width: 1
                    border.color: prompt.activeFocus ? theme.a(theme.green, 0.5) : theme.hairline
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    QQC2.TextField {
                        id: prompt
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        placeholderText: root.thinking ? root.t("Genesi is working…", "O Genesi está trabalhando…")
                                       : root.pendingApproval ? root.t("Waiting for your answer above", "Esperando sua resposta abaixo")
                                       : root.t("Ask anything, or tell me what to do…", "Pergunte algo, ou me diga o que fazer…")
                        color: root.textHi
                        placeholderTextColor: root.textLo
                        enabled: !root.thinking && root.pendingApproval === null
                        font.pixelSize: 16
                        background: Item {}
                        Keys.onReturnPressed: root.sendPrompt()
                        Keys.onEnterPressed: root.sendPrompt()
                        Keys.onEscapePressed: root.hideQuick()
                    }
                }
                RoundButton {
                    icon: "plus"
                    tip: root.t("Attach a file", "Anexar um arquivo")
                    visible: !root.thinking && root.pendingApproval === null
                    onClicked: attachDialog.open()
                }
                Rectangle {
                    // Send, or Stop while it works.
                    id: sendBtn
                    readonly property bool busy: root.thinking || root.pendingApproval !== null
                    readonly property bool ready: prompt.text.trim().length > 0
                    Layout.preferredWidth: 38; Layout.preferredHeight: 38
                    radius: 19
                    color: busy ? theme.a(theme.red, sendMa.containsMouse ? 0.35 : 0.22)
                         : ready ? (sendMa.containsMouse ? theme.greenBright : theme.green)
                         : theme.a(theme.textHi, 0.07)
                    Behavior on color { ColorAnimation { duration: 140 } }
                    FIcon {
                        anchors.centerIn: parent
                        visible: !sendBtn.busy
                        name: "arrow-up"; size: 16
                        color: sendBtn.ready ? "#06130c" : root.textLo
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: sendBtn.busy
                        width: 11; height: 11; radius: 3
                        color: theme.red
                    }
                    MouseArea {
                        id: sendMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sendBtn.busy ? root.stopWork() : root.sendPrompt()
                        QQC2.ToolTip.visible: containsMouse
                        QQC2.ToolTip.text: sendBtn.busy ? root.t("Stop", "Parar") : root.t("Ask", "Perguntar")
                        QQC2.ToolTip.delay: 500
                    }
                }
                RoundButton {
                    icon: "sliders"
                    tip: root.t("Settings", "Configurações")
                    active: root.settingsOpen
                    onClicked: {
                        root.settingsOpen = !root.settingsOpen
                        if (root.settingsOpen) {
                            backend.loadModels()
                            backend.loadCloud()
                            // Kokoro installed since this process started
                            // should show up without restarting anything.
                            backend.recheckVoice()
                            backend.loadVoiceLanguages()
                            root.islandPrefs = JSON.parse(backend.islandPrefs())
                        }
                    }
                }
                RoundButton {
                    icon: "x"
                    tip: root.t("Close", "Fechar")
                    hoverFill: theme.a(theme.red, 0.18)
                    onClicked: root.hideQuick()
                }
            }

            // ── Starters: what to ask, before anything is asked ─────────
            Flow {
                visible: root.starters
                Layout.fillWidth: true
                Layout.leftMargin: 54
                spacing: 6
                Repeater {
                    model: [
                        { "label": root.t("Explain what I copied", "Explicar o que copiei"), "ask": "clip",
                          "text": root.t("Explain this clearly and briefly.", "Explique isto de forma clara e curta.") },
                        { "label": root.t("How much RAM is free?", "Quanta RAM está livre?"), "ask": "text",
                          "text": root.t("How much RAM is free right now, and what is using the most?",
                                         "Quanta RAM está livre agora, e o que está usando mais?") },
                        { "label": root.t("Tidy my Downloads", "Organizar meus Downloads"), "ask": "text",
                          "text": root.t("Look at my Downloads folder and suggest how to organize it.",
                                         "Olhe minha pasta Downloads e sugira como organizar.") },
                        { "label": root.t("Open the browser", "Abrir o navegador"), "ask": "text",
                          "text": root.t("Open the web browser.", "Abra o navegador.") }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: starterText.implicitWidth + 24; height: 28
                        radius: 14
                        color: starterMa.containsMouse ? theme.a(theme.green, 0.2) : theme.a(theme.green, 0.08)
                        border.width: 1
                        border.color: theme.a(theme.green, starterMa.containsMouse ? 0.5 : 0.25)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        QQC2.Label {
                            id: starterText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.textHi; font.pixelSize: 12
                        }
                        MouseArea {
                            id: starterMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.ask === "clip") {
                                    var clip = backend.clipboardText()
                                    if (clip && clip.trim())
                                        root.sendText(backend.clipPrompt(modelData.text, clip), "📋 " + modelData.text, false)
                                    else
                                        prompt.text = modelData.text
                                } else {
                                    root.sendText(modelData.text, modelData.text, false)
                                }
                            }
                        }
                    }
                }
            }

            // ── Attached files ──────────────────────────────────────────
            Flow {
                visible: root.attachments.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 54
                spacing: 6
                Repeater {
                    model: root.attachments
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool warn: !!chip.modelData.error
                        height: 28
                        width: chipRow.implicitWidth + 18
                        radius: 14
                        color: chip.warn ? theme.a(theme.turbo, 0.16) : theme.a(theme.green, 0.12)
                        border.width: 1
                        border.color: chip.warn ? theme.a(theme.turbo, 0.4) : theme.a(theme.green, 0.35)
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            FIcon { name: chip.modelData.kind === "image" ? "image" : "file-text"; size: 12; color: root.textMid }
                            QQC2.Label {
                                text: chip.modelData.name
                                      + (chip.modelData.error === "image" ? root.t(" · only its path", " · só o caminho")
                                         : chip.modelData.error === "no-text" ? root.t(" · no text in it", " · sem texto")
                                         : chip.modelData.error === "no-pdf-reader" ? root.t(" · install poppler to read PDFs", " · instale o poppler para ler PDFs")
                                         : chip.modelData.error ? root.t(" · not readable", " · ilegível") : "")
                                color: root.textHi; font.pixelSize: 11
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 420
                            }
                            QQC2.Label {
                                text: "✕"; color: root.textLo; font.pixelSize: 11
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeAttachment(chip.modelData.path)
                                }
                            }
                        }
                    }
                }
            }

            // ── Settings ────────────────────────────────────────────────
            // Scrolls: with the providers, the island and Turbo it is taller
            // than the window may grow, and the bottom used to be cut off.
            QQC2.ScrollView {
                id: settingsScroll
                visible: root.settingsOpen && root.pendingApproval === null
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(470, settingsCol.implicitHeight)
                contentWidth: availableWidth
                clip: true
            ColumnLayout {
                id: settingsCol
                width: settingsScroll.availableWidth - 8
                x: 4
                spacing: 10

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.hairline }

                SectionTitle { text: root.t("MODEL", "MODELO") }
                RowLayout {
                    Layout.fillWidth: true
                    RowLabel { text: root.t("Source", "Fonte") }
                    Seg {
                        options: [{ "value": "local", "label": root.t("This PC", "Este PC") },
                                  { "value": "api", "label": "API" }]
                        current: root.source
                        onPicked: function(v) { backend.setChatSource(v) }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.source === "local"
                    RowLabel { text: root.t("Model", "Modelo") }
                    QQC2.ComboBox {
                        id: modelPicker
                        Layout.fillWidth: true
                        // The VALUE stays the raw reference (an Ollama tag or a
                        // `gguf:<stem>`); only the display is prettified, so
                        // picking never rewrites the model into its label.
                        model: root.availableModels
                        currentIndex: Math.max(0, root.availableModels.indexOf(root.modelName))
                        displayText: backend.modelLabel(root.modelName)
                        delegate: QQC2.ItemDelegate {
                            width: modelPicker.width
                            text: backend.modelLabel(modelData)
                            highlighted: modelPicker.highlightedIndex === index
                        }
                        onActivated: root.chooseModel(root.availableModels[currentIndex])
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.source === "api"
                    RowLabel { text: root.t("Provider", "Provedor") }
                    // Every provider Genesi knows: the ones with a key marked,
                    // the free tiers said so -- picking one without a key
                    // opens the key field below instead of an error.
                    QQC2.ComboBox {
                        id: quickProvider
                        Layout.fillWidth: true
                        model: root.cloudKnown
                        textRole: "label"
                        currentIndex: {
                            for (var i = 0; i < root.cloudKnown.length; ++i)
                                if (root.cloudKnown[i].provider === root.cloudProvider) return i
                            return -1
                        }
                        displayText: root.cloudInfo.label || root.t("Choose a provider", "Escolha um provedor")
                        delegate: QQC2.ItemDelegate {
                            required property var modelData
                            required property int index
                            width: quickProvider.width
                            highlighted: quickProvider.highlightedIndex === index
                            contentItem: RowLayout {
                                spacing: 8
                                QQC2.Label { text: modelData.label; color: root.textHi; Layout.fillWidth: true }
                                QQC2.Label {
                                    visible: modelData.tier === "free"
                                    text: root.t("free tier", "plano grátis")
                                    color: theme.greenBright; font.pixelSize: 10
                                }
                                QQC2.Label {
                                    visible: modelData.configured
                                    text: "✓"
                                    color: theme.greenBright; font.bold: true
                                }
                            }
                        }
                        onActivated: root.pickCloudProvider(root.cloudKnown[currentIndex].provider)
                    }
                }
                RowLayout {
                    // No key for this provider yet: paste it here.
                    Layout.fillWidth: true
                    visible: root.source === "api" && root.cloudProvider !== "" && !root.cloudReady
                    RowLabel { text: root.t("API key", "Chave da API") }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 16
                        color: theme.a(theme.textHi, 0.05)
                        border.width: 1
                        border.color: keyField.activeFocus ? theme.a(theme.green, 0.5) : theme.hairline
                        QQC2.TextField {
                            id: keyField
                            anchors.fill: parent
                            anchors.leftMargin: 6; anchors.rightMargin: 6
                            echoMode: TextInput.Password
                            placeholderText: root.t("Paste your %1 key", "Cole sua chave do %1").arg(root.cloudInfo.label || "")
                            text: root.cloudKeyDraft
                            onTextChanged: root.cloudKeyDraft = text
                            background: Item {}
                            color: root.textHi
                            placeholderTextColor: root.textLo
                            Keys.onReturnPressed: saveKey.clicked()
                        }
                    }
                    Rectangle {
                        id: saveKey
                        signal clicked
                        implicitWidth: saveText.implicitWidth + 26; implicitHeight: 32
                        radius: 16
                        color: root.cloudKeyDraft.trim() ? (saveMa.containsMouse ? theme.greenBright : theme.green) : theme.a(theme.textHi, 0.07)
                        QQC2.Label {
                            id: saveText
                            anchors.centerIn: parent
                            text: root.t("Save", "Salvar")
                            color: root.cloudKeyDraft.trim() ? "#06130c" : root.textLo
                            font.bold: true
                        }
                        MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: saveKey.clicked() }
                        onClicked: {
                            if (!root.cloudKeyDraft.trim()) return
                            backend.setCloudKey(root.cloudProvider, root.cloudKeyDraft)
                            root.cloudKeyDraft = ""
                        }
                    }
                }
                QQC2.Label {
                    visible: root.source === "api" && root.cloudProvider !== "" && !root.cloudReady && !!root.cloudInfo.keyUrl
                    Layout.leftMargin: 126
                    text: root.t("Get a key at %1 ↗", "Pegue uma chave em %1 ↗").arg(String(root.cloudInfo.keyUrl).replace(/^https:\/\//, "").split("/")[0])
                    color: theme.greenBright; font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(root.cloudInfo.keyUrl)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.source === "api" && root.cloudReady
                    RowLabel { text: root.t("Model", "Modelo") }
                    // Typed as the company names it, or picked: Genesi's
                    // suggestions first, then what the provider says this key
                    // can use (asked when the list opens).
                    QQC2.ComboBox {
                        id: quickCloudModel
                        Layout.fillWidth: true
                        editable: true
                        model: root.cloudChoices
                        // Pinned to the model in use. Left alone, a ComboBox
                        // given a list jumps to its first entry and shows a
                        // model that is not the one answering.
                        currentIndex: root.cloudChoices.indexOf(root.cloudModel)
                        editText: root.cloudModel
                        onPressedChanged: if (pressed && root.cloudSuggestions.length === 0)
                                              backend.listCloudModels(root.cloudProvider)
                        onAccepted: root.pickCloudModel(editText)
                        onActivated: root.pickCloudModel(root.cloudChoices[currentIndex])
                    }
                }
                QQC2.Label {
                    visible: root.source === "api"
                    Layout.fillWidth: true
                    text: root.t("Fast and free to start: Groq, Cerebras, Hugging Face, Gemini, OpenRouter.",
                                 "Rápidos e grátis para começar: Groq, Cerebras, Hugging Face, Gemini, OpenRouter.")
                    color: root.textLo; font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                SectionTitle { text: root.t("BEHAVIOUR", "COMPORTAMENTO") }
                RowLayout {
                    Layout.fillWidth: true
                    RowLabel { text: root.t("Actions", "Ações") }
                    Seg {
                        options: [{ "value": "approval", "label": root.t("Ask first", "Perguntar antes") },
                                  { "value": "automatic", "label": root.t("Automatic", "Automático") }]
                        current: root.actionMode
                        fillOn: root.actionMode === "automatic" ? theme.turbo : theme.green
                        onPicked: function(v) { root.setActionMode(v) }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    RowLabel { text: root.t("AI Mode", "Modo IA") }
                    Seg {
                        options: [{ "value": "on", "label": root.t("Always on", "Sempre ligado") },
                                  { "value": "auto", "label": "Auto" },
                                  { "value": "off", "label": root.t("Off", "Desligado") }]
                        current: root.forceMode
                        fillOn: root.forceMode === "off" ? theme.red : theme.green
                        onPicked: function(v) { root.forceMode = v; backend.setMode(v) }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    RowLabel { text: root.t("Performance", "Desempenho") }
                    Seg {
                        options: [{ "value": "max", "label": root.t("Maximum", "Máximo") },
                                  { "value": "balanced", "label": root.t("Balanced", "Equilibrado") },
                                  { "value": "battery", "label": root.t("Battery", "Bateria") },
                                  { "value": "auto", "label": "Auto" }]
                        current: root.profileMode
                        onPicked: function(v) { root.profileMode = v; backend.setProfile(v) }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.voiceReady
                    RowLabel { text: root.t("Voice", "Voz") }
                    Seg {
                        options: [{ "value": false, "label": root.t("Silent", "Silenciosa") },
                                  { "value": true, "label": root.t("Read answers out", "Ler respostas") }]
                        current: root.speakAnswers
                        onPicked: function(v) { backend.setSpeakAnswers(v) }
                    }
                    // The language it speaks in. All of them run from the
                    // files already installed -- choosing one downloads and
                    // loads nothing extra.
                    QQC2.ComboBox {
                        visible: root.voiceLanguages.length > 0
                        Layout.preferredWidth: 170
                        textRole: "label"
                        valueRole: "id"
                        model: root.voiceLanguages
                        currentIndex: {
                            for (var i = 0; i < root.voiceLanguages.length; ++i)
                                if (root.voiceLanguages[i].id === root.voiceLanguage)
                                    return i
                            return -1
                        }
                        onActivated: backend.setVoiceLanguage(root.voiceLanguages[currentIndex].id)
                    }
                    Item { Layout.fillWidth: true }
                }

                // The island at the top of the screen: on every desktop.
                SectionTitle { text: root.t("AI ISLAND", "ILHA DA IA") }
                RowLayout {
                    Layout.fillWidth: true
                    RowLabel { text: root.t("Island", "Ilha") }
                    Seg {
                        options: [{ "value": true, "label": root.t("On", "Ligada") },
                                  { "value": false, "label": root.t("Off", "Desligada") }]
                        current: root.islandPrefs.enabled === true
                        onPicked: function(v) { root.setIslandPref("enabled", v ? "on" : "off") }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.islandPrefs.enabled === true
                    RowLabel { text: root.t("Show it", "Mostrar") }
                    Seg {
                        options: [{ "value": "always", "label": root.t("Always", "Sempre") },
                                  { "value": "quickchat", "label": root.t("With the chat", "Com o chat") }]
                        current: root.islandPrefs.mode || "always"
                        onPicked: function(v) { root.setIslandPref("mode", v) }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.islandPrefs.enabled === true
                    RowLabel { text: root.t("Smart Copy", "Cópia inteligente") }
                    Seg {
                        options: [{ "value": true, "label": root.t("On", "Ligada") },
                                  { "value": false, "label": root.t("Off", "Desligada") }]
                        current: root.islandPrefs.smartClip === true
                        onPicked: function(v) { root.setIslandPref("smartClip", v ? "on" : "off") }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: root.t("Copy an error and the island offers to explain it. Read only on this PC.",
                                     "Copie um erro e a ilha oferece explicar. Lido só neste PC.")
                        color: root.textLo; font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    // Turbo speeds up a LOCAL model; with an API it does nothing.
                    visible: root.source === "local"
                    Layout.fillWidth: true
                    implicitHeight: turboControls.implicitHeight + 20
                    radius: 14
                    color: theme.a(theme.turbo, root.turboRequested ? 0.08 : 0.0)
                    border.width: 1
                    border.color: root.turboRequested ? theme.a(theme.turbo, 0.6) : theme.hairline
                    ColumnLayout {
                        id: turboControls
                        anchors.fill: parent; anchors.margins: 10; spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            FIcon { name: "bolt"; size: 20; color: theme.turboBright }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                QQC2.Label { text: "Turbo"; color: root.textHi; font.bold: true }
                                QQC2.Label {
                                    text: root.modelName ? backend.modelLabel(root.modelName) : root.t("Choose a model first", "Escolha um modelo primeiro")
                                    color: root.textLo; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            QQC2.Switch { checked: root.turboRequested; enabled: !!root.modelName; onClicked: root.setTurboWanted(!root.turboRequested) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                QQC2.Label { text: root.t("Speculative decoding", "Decodificação especulativa"); color: root.textHi; font.bold: true; font.pixelSize: 11 }
                                QQC2.Label { text: root.t("Draft model acceleration; best with the CUDA backend", "Aceleração com modelo rascunho; melhor com o backend CUDA"); color: root.textLo; font.pixelSize: 9 }
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
                            text: root.t("Install Vulkan backend", "Instalar backend Vulkan"); icon.name: "system-software-install"
                            onClicked: backend.installTurboBackend("vulkan")
                        }
                    }
                }
            }

            }

            // ── The conversation ────────────────────────────────────────
            QQC2.ScrollView {
                id: chatScroll
                visible: root.expanded && !root.settingsOpen && root.pendingApproval === null
                         && root.timeline.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(380, messages.implicitHeight)
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    id: messages
                    width: chatScroll.availableWidth
                    spacing: 10
                    Repeater {
                        model: root.timeline
                        delegate: Item {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool isAction: modelData.kind === "action"
                            readonly property bool mine: modelData.role === "user"
                            Layout.fillWidth: true
                            Layout.preferredWidth: messages.width
                            implicitHeight: isAction ? actionRow.implicitHeight + 8
                                          : mine ? userBubble.implicitHeight
                                          : answerRow.implicitHeight

                            // What the person asked: a bubble on the right.
                            Rectangle {
                                id: userBubble
                                visible: entry.mine && !entry.isAction
                                anchors.right: parent.right
                                width: Math.min(messages.width * 0.78, userText.implicitWidth + 28)
                                implicitHeight: userText.implicitHeight + 18
                                radius: 16
                                bottomRightRadius: 5
                                color: theme.a(theme.green, 0.2)
                                border.width: 1
                                border.color: theme.a(theme.green, 0.3)
                                QQC2.Label {
                                    id: userText
                                    anchors.fill: parent; anchors.margins: 9; anchors.leftMargin: 14; anchors.rightMargin: 14
                                    text: entry.modelData.content || ""
                                    color: root.textHi
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    font.pixelSize: 13
                                }
                            }

                            // What the AI answered: the leaf, and the answer
                            // as written -- lists, bold, code and all.
                            RowLayout {
                                id: answerRow
                                visible: !entry.mine && !entry.isAction
                                width: parent.width
                                spacing: 10
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                    radius: 13
                                    color: theme.a(theme.green, 0.14)
                                    GenesiLeaf {
                                        anchors.centerIn: parent
                                        size: 16
                                        mood: "normal"
                                        pal: ({ "m3primary": theme.green })
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: answerText.implicitHeight + 20
                                    radius: 14
                                    topLeftRadius: 5
                                    color: theme.a(theme.textHi, answerHover.hovered ? 0.06 : 0.04)
                                    HoverHandler { id: answerHover }
                                    TextEdit {
                                        id: answerText
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14; anchors.rightMargin: 36
                                        text: entry.modelData.content || ""
                                        textFormat: TextEdit.MarkdownText
                                        readOnly: true
                                        selectByMouse: true
                                        color: root.textHi
                                        selectionColor: theme.a(theme.green, 0.4)
                                        wrapMode: TextEdit.Wrap
                                        font.pixelSize: 13
                                        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                                    }
                                    RoundButton {
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: 4
                                        implicitWidth: 28; implicitHeight: 28
                                        visible: answerHover.hovered
                                        icon: "copy"
                                        tip: root.t("Copy", "Copiar")
                                        onClicked: backend.copyText(entry.modelData.content || "")
                                    }
                                }
                            }

                            // A step the agent took: a line on a timeline.
                            RowLayout {
                                id: actionRow
                                visible: entry.isAction
                                width: parent.width
                                spacing: 10
                                readonly property bool bad: entry.modelData.state === "action-error" || entry.modelData.state === "denied"
                                readonly property bool live: entry.modelData.state === "running" || entry.modelData.state === "waiting-approval"
                                readonly property color tone: entry.modelData.state === "stopped" ? root.textMid
                                                             : bad ? theme.red : live ? root.amber : theme.greenBright
                                Item {
                                    Layout.preferredWidth: 26; Layout.fillHeight: true
                                    Layout.minimumHeight: 30
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top; anchors.bottom: parent.bottom
                                        width: 2; color: theme.hairline
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22; height: 22; radius: 11
                                        color: theme.bgTop
                                        border.width: 2; border.color: actionRow.tone
                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: 12; height: 12
                                            source: entry.modelData.icon || "system-run"
                                            color: actionRow.tone
                                        }
                                        SequentialAnimation on scale {
                                            running: actionRow.live && entry.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 1.12; duration: 600; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: entry.modelData.title || "System action"
                                        color: root.textHi; font.pixelSize: 12; font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: entry.modelData.message || ""
                                        visible: text.length > 0
                                        color: root.textMid; font.pixelSize: 11
                                        font.family: theme.mono
                                        elide: Text.ElideRight
                                    }
                                }
                                Rectangle {
                                    implicitWidth: stateLabel.implicitWidth + 14; implicitHeight: 20
                                    radius: 10
                                    color: theme.a(actionRow.tone, 0.14)
                                    QQC2.Label {
                                        id: stateLabel
                                        anchors.centerIn: parent
                                        text: ({"waiting-approval": root.t("WAITING", "AGUARDANDO"), "approved": root.t("APPROVED", "APROVADO"),
                                                "running": root.t("RUNNING", "RODANDO"), "action-complete": root.t("DONE", "FEITO"),
                                                "action-error": root.t("FAILED", "FALHOU"), "denied": root.t("DENIED", "NEGADO"),
                                                "stopped": root.t("STOPPED", "PARADO")})[entry.modelData.state] || root.t("WORKING", "TRABALHANDO")
                                        color: actionRow.tone
                                        font.bold: true; font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }

                    // Thinking: the activity, with three dots.
                    RowLayout {
                        visible: root.thinking && root.pendingApproval === null
                        Layout.leftMargin: 36
                        spacing: 6
                        QQC2.Label {
                            text: root.say(root.activityText)
                            color: root.textMid; font.pixelSize: 12; font.italic: true
                        }
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: 5; height: 5; radius: 2.5
                                color: theme.greenBright
                                SequentialAnimation on opacity {
                                    running: root.thinking
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 150 }
                                    NumberAnimation { to: 0.2; duration: 350 }
                                    NumberAnimation { to: 1; duration: 350 }
                                    PauseAnimation { duration: (2 - index) * 150 }
                                }
                            }
                        }
                    }
                }
            }

            // ── An approval ─────────────────────────────────────────────
            Rectangle {
                visible: root.pendingApproval !== null
                Layout.fillWidth: true
                implicitHeight: approvalBody.implicitHeight + 28
                radius: 18
                color: theme.a(root.amber, 0.07)
                border.width: 1
                border.color: theme.a(root.amber, 0.4)
                ColumnLayout {
                    id: approvalBody
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            radius: 18
                            color: theme.a(root.amber, 0.18)
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 20; height: 20
                                source: root.pendingApproval ? root.pendingApproval.icon : "security-high"
                                color: root.amber
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.pendingApproval ? root.pendingApproval.title : root.t("Allow this action?", "Permitir esta ação?")
                                color: root.textHi; font.bold: true; font.pixelSize: 16
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.pendingApproval ? root.pendingApproval.description : ""
                                color: root.textMid; wrapMode: Text.WordWrap; font.pixelSize: 12
                            }
                        }
                        Rectangle {
                            visible: !!(root.pendingApproval && root.pendingApproval.risk_label)
                            implicitWidth: riskText.implicitWidth + 16; implicitHeight: 22
                            radius: 11
                            readonly property bool severe: !!(root.pendingApproval && root.pendingApproval.risk === "system-change")
                            color: theme.a(severe ? theme.red : theme.green, 0.16)
                            QQC2.Label {
                                id: riskText
                                anchors.centerIn: parent
                                text: root.pendingApproval ? (root.pendingApproval.risk_label || "") : ""
                                color: parent.severe ? theme.red : theme.greenBright
                                font.bold: true; font.pixelSize: 10
                            }
                        }
                    }
                    Repeater {
                        model: root.pendingApproval ? (root.pendingApproval.details || []) : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: detailCol.implicitHeight + 16
                            radius: 10
                            color: theme.a("#000000", 0.25)
                            ColumnLayout {
                                id: detailCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                spacing: 2
                                QQC2.Label { text: modelData.label; color: root.textLo; font.pixelSize: 10; font.bold: true }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: root.textHi; font.family: theme.mono; font.pixelSize: 12
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                    QQC2.Label {
                        text: root.technicalOpen ? root.t("Hide technical details ▴", "Ocultar detalhes técnicos ▴")
                                                 : root.t("Technical details ▾", "Detalhes técnicos ▾")
                        color: root.textLo; font.pixelSize: 11
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.technicalOpen = !root.technicalOpen
                        }
                    }
                    Rectangle {
                        visible: root.technicalOpen
                        Layout.fillWidth: true
                        implicitHeight: technical.implicitHeight + 16
                        radius: 10; color: theme.a("#000000", 0.3)
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
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: denyText.implicitWidth + 32; implicitHeight: 34
                            radius: 17
                            color: denyMa.containsMouse ? theme.a(theme.textHi, 0.12) : theme.a(theme.textHi, 0.06)
                            border.width: 1; border.color: theme.hairline
                            QQC2.Label { id: denyText; anchors.centerIn: parent; text: root.t("Deny", "Negar"); color: root.textHi; font.bold: true }
                            MouseArea { id: denyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resolveApproval(false) }
                        }
                        Rectangle {
                            implicitWidth: allowText.implicitWidth + 36; implicitHeight: 34
                            radius: 17
                            color: allowMa.containsMouse ? theme.greenBright : theme.green
                            QQC2.Label {
                                id: allowText; anchors.centerIn: parent
                                text: {
                                    var l = root.pendingApproval ? (root.pendingApproval.approve_label || "Allow") : "Allow"
                                    var map = {"Allow": root.t("Allow", "Permitir"), "Open": root.t("Open", "Abrir"),
                                               "Create folder": root.t("Create folder", "Criar pasta")}
                                    return map[l] || l
                                }
                                color: "#06130c"; font.bold: true
                            }
                            MouseArea { id: allowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resolveApproval(true) }
                        }
                    }
                }
            }

            // ── The footer ──────────────────────────────────────────────
            RowLayout {
                visible: root.expanded
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    // The model in use; a click opens the settings on it.
                    implicitWidth: modelRow.implicitWidth + 20; implicitHeight: 24
                    radius: 12
                    color: modelMa.containsMouse ? theme.hover : theme.a(theme.textHi, 0.04)
                    border.width: 1; border.color: theme.hairline
                    RowLayout {
                        id: modelRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: root.currentRef ? (root.turboRequested ? theme.turboBright : theme.greenBright) : theme.red
                        }
                        QQC2.Label {
                            text: root.currentRef
                                ? root.currentLabel
                                  + (root.turboRequested && root.source === "local" ? " · Turbo" : "")
                                : (root.source === "api" ? root.t("No API key set", "Sem chave de API")
                                                          : root.t("No model available", "Nenhum modelo"))
                            color: root.textMid
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: 300
                        }
                    }
                    MouseArea {
                        id: modelMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.settingsOpen = !root.settingsOpen
                    }
                }
                QQC2.Label {
                    text: root.actionMode === "automatic" ? root.t("Automatic actions", "Ações automáticas")
                                                          : root.t("Asks before acting", "Pergunta antes de agir")
                    color: root.actionMode === "automatic" ? theme.turboBright : root.textLo
                    font.bold: root.actionMode === "automatic"; font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: root.conversation.length > 0 && !root.thinking && root.pendingApproval === null
                    implicitWidth: newRow.implicitWidth + 20; implicitHeight: 26
                    radius: 13
                    color: newMa.containsMouse ? theme.hover : "transparent"
                    RowLayout {
                        id: newRow
                        anchors.centerIn: parent
                        spacing: 5
                        FIcon { name: "plus"; size: 11; color: root.textMid }
                        QQC2.Label { text: root.t("New chat", "Nova conversa"); color: root.textMid; font.pixelSize: 11 }
                    }
                    MouseArea {
                        id: newMa
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.newChat()
                    }
                }
            }
        }
    }

    Connections {
        target: backend
        function onModelChanged(model) { if (!root.modelName) root.modelName = model }
        function onAgentModeChanged(mode) {
            if (mode === "approval" || mode === "automatic") root.actionMode = mode
        }
        function onCloudLoaded(payload) {
            var d = {}
            try { d = JSON.parse(payload) } catch (error) {}
            root.cloudProviders = d.providers || []
            root.cloudKnown = d.known || []
            // A provider just picked to add a key to stays picked; anything
            // else falls back to the active one.
            var keep = false
            for (var i = 0; i < root.cloudKnown.length; ++i)
                if (root.cloudKnown[i].provider === root.cloudProvider) keep = true
            for (var j = 0; j < root.cloudProviders.length; ++j)
                if (root.cloudProviders[j].provider === root.cloudProvider) keep = true
            if (!keep || !root.cloudProvider)
                root.cloudProvider = d.active || (root.cloudProviders.length
                                                  ? root.cloudProviders[0].provider : "gemini")
        }
        function onCloudModelsListed(provider, payload) {
            if (provider !== root.cloudProvider) return
            try { root.cloudSuggestions = JSON.parse(payload) } catch (error) {}
        }
        function onChatSourceChanged(src) { root.source = src }
        function onVoiceLanguagesLoaded(payload) {
            var d = {}
            try { d = JSON.parse(payload) } catch (error) {}
            root.voiceLanguages = d.languages || []
            root.voiceLanguage = d.language || ""
        }
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
        function onChatDone(stats) {
            if (root.lastOutcome === "") root.lastOutcome = "done"
            root.thinking = false
            root.markTurnEnd()
            leaf.hop()
            if (root.visible) prompt.forceActiveFocus()
            // The whole answer, not the last token: onChatToken appends each
            // one as its own entry, so the reply is every trailing assistant
            // entry joined back together.
            if (root.speakAnswers && root.voiceReady) {
                var said = ""
                for (var i = root.conversation.length - 1; i >= 0; --i) {
                    if (root.conversation[i].role !== "assistant")
                        break
                    said = root.conversation[i].content + said
                }
                if (said.trim().length > 0)
                    backend.speak(said)
            }
            root.publishIsland()
        }
        function onSpeakAnswersChanged(on) { root.speakAnswers = on }
        function onVoiceReadyChanged(ready) { root.voiceReady = ready }
        function onChatStopped() {
            root.lastOutcome = ""
            root.thinking = false
            root.activityText = "Stopped"
            if (root.visible) prompt.forceActiveFocus()
        }
        function onChatError(message) {
            root.lastOutcome = "error"
            root.thinking = false
            root.markTurnEnd()
            root.addMessage("assistant", message)
        }
        function onApprovalRequested(payload) {
            root.pendingApproval = JSON.parse(payload)
            root.rememberAction(root.pendingApproval)
            root.settingsOpen = false
            root.thinking = false
            leaf.hop()
            // With an AI island on screen, the island asks; the window stays
            // where it is (open if it was open, hidden if it was hidden).
            if (!backend.islandShowsApprovals())
                root.showQuick()
        }
        function onAgentActivity(payload) {
            var activity = JSON.parse(payload)
            root.consumeActivity(activity)
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.hideQuick() }
}
