// GENESI — the AI island: what it looks like and what it says.
//
// Drawing only, in plain QtQuick, so ci/plugins-test.py can play every state
// offscreen and look at it. The SAME file is the island everywhere: caelestia
// hosts it in GenesiAiIsland (Hyprland), and genesi-ai-mode bundles it into
// its own island window for every other desktop (genesi-ai-island). Each
// host reads the Quick Chat's state file, decides where and when, and runs
// the commands this card asks for; nothing here knows which one it is in.
//
// ── What it shows ─────────────────────────────────────────────────────────
//
//   idle       a small pill with the leaf; hover peeks (model, shortcut),
//              a click opens the input right here, right-click the menu
//   ask        the island IS the chat: type, Enter, the answer comes back
//              here -- plus one-click asks about what you just copied
//   work       the leaf talking or dancing, the agent's steps (2/4), Stop
//   approval   the leaf sweating, the exact command, Deny / Allow
//   answer     an answer asked from the island, whole, until dismissed
//   done       an answer asked in the chat window: its start, for a while
//   error      what went wrong
//   hint       Smart Copy: you copied an error / a long text -- explain it?
//   menu       the island's own settings, in the island
//   drop/offer a file dragged here, then what to do with it
//
// `st` is the Quick Chat's genesi-ai-island.json as it was last read:
//   {phase, activity, steps:[{title,state,message}], total, approval:
//    {id,title,description,risk,approve,detail}, answer, prompt, model,
//    open, inline, elapsed, actionMode, hint:{id,kind,preview}}
// `prefs` is ~/.config/genesi/ai-island.json: {mode, smartClip}.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: card

    property var st: ({})
    property var pal: ({})
    property var prefs: ({})
    // The Quick Chat is running (its state file is there).
    property bool live: false
    // Flush with the top of the screen (a notch) or hanging under a bar.
    property bool attached: true
    // The host can give this card the keyboard. Where it cannot, a click
    // opens the chat window instead of the input.
    property bool canType: true
    property string shortcut: "Ctrl+Alt+Space"
    property bool hovered: hover.hovered

    readonly property string phase: card.live ? (card.st.phase ?? "idle") : "idle"
    readonly property var steps: card.st.steps ?? []
    readonly property var approval: card.st.approval ?? null
    readonly property var hint: card.live ? (card.st.hint ?? null) : null

    // A finished answer or an error stays until it is looked at -- or for a
    // while, then the island folds back. Per state: a new phase brings it back.
    property string seenPhase: ""
    property string seenHint: ""
    property string offerPath: ""
    property bool asking: false
    property bool menuOpen: false
    readonly property bool dragging: drop.containsDrag
    // Which request this is: a phase seen for one request is not seen for the next.
    readonly property string turnKey: card.phase + ":" + (card.st.pid ?? "") + ":" + (card.st.turn ?? "")
    readonly property bool busy: card.phase === "thinking" || card.phase === "running"

    readonly property string view: card.dragging ? "drop"
        : card.offerPath !== "" ? "offer"
        : card.phase === "approval" && card.approval ? "approval"
        : card.menuOpen ? "menu"
        : card.busy ? "work"
        : card.asking ? "ask"
        : (card.phase === "done" || card.phase === "error") && card.seenPhase !== card.turnKey
            ? (card.st.inline && card.phase === "done" ? "answer" : card.phase)
        : card.hint && card.hint.id && card.seenHint !== card.hint.id ? "hint"
        : "idle"
    readonly property bool expanded: card.view !== "idle"
    // The host gives the keyboard to the island while this is true.
    readonly property bool typing: card.view === "ask"

    readonly property bool pt: Qt.locale().name.startsWith("pt")
    function t(en: string, ptText: string): string {
        return card.pt ? ptText : en;
    }

    signal openChat
    signal approve(string id)
    signal deny(string id)
    signal stopWork
    signal attach(string path, string request)
    // Ask from the island. withClip: the chat adds what is on the clipboard.
    signal ask(string text, bool withClip)
    signal setting(string key, string value)
    signal copyText(string text)

    // The theme's colours: the active scheme, like every surface of the
    // shell. The literals are only for a palette that is not there yet.
    // `fill` is set by the window when the island hangs from the bar, so the
    // two read as one surface.
    property color fill: Qt.alpha(card.pal.m3surfaceContainer ?? "#16181d", 0.97)
    readonly property color ink: card.fill
    readonly property color hi: card.pal.m3onSurface ?? "#f2f4f8"
    readonly property color mid: card.pal.m3onSurfaceVariant ?? "#a9b1c0"
    readonly property color lo: card.pal.m3outline ?? "#6d7586"
    readonly property color green: card.pal.m3primary ?? "#3ccf7e"
    readonly property color amber: card.pal.m3tertiary ?? "#f0a43a"
    readonly property color red: card.pal.m3error ?? "#ef5b5b"
    readonly property color accent: card.pal.m3primary ?? "#7aa2ff"
    readonly property color accentInk: card.pal.m3onPrimary ?? "#0a0b0f"
    readonly property color well: Qt.alpha(card.hi, 0.06)

    // What the bar's chip says.
    readonly property string shortLabel: card.phase === "approval" ? card.t("Needs permission", "Precisa de permissão")
        : card.phase === "running" ? ((card.st.total ?? 0) > 0
            ? card.steps.filter(s => card.stepMark(s.state) === "✓").length + "/" + card.st.total + " · "
              + (card.steps.length ? card.steps[card.steps.length - 1].title : "")
            : card.t("Working", "Trabalhando"))
        : card.phase === "thinking" ? card.t("Thinking…", "Pensando…")
        : card.phase === "done" ? card.t("Done", "Pronto")
        : card.phase === "error" ? card.t("Something went wrong", "Algo deu errado")
        : ""

    readonly property color tint: card.view === "approval" ? card.amber
        : card.view === "done" || card.view === "answer" || card.view === "drop" || card.view === "offer" ? card.green
        : card.view === "error" ? card.red
        : card.view === "hint" ? card.amber
        : card.accent

    readonly property int fullWidth: card.view === "answer" ? 560 : 500
    implicitWidth: card.expanded ? card.fullWidth : (card.hovered ? 268 : 164)
    implicitHeight: card.expanded ? Math.max(card.view === "ask" ? 0 : 92, body.implicitHeight + 26) : 38

    Behavior on implicitWidth {
        NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
    }

    // ── Words ──────────────────────────────────────────────────────────────
    // Approval labels come from the agent in English.
    function approveLabel(label: string): string {
        const map = { "Allow": card.t("Allow", "Permitir"), "Open": card.t("Open", "Abrir"),
                      "Create folder": card.t("Create folder", "Criar pasta") };
        return map[label] ?? label ?? card.t("Allow", "Permitir");
    }
    function stepMark(state: string): string {
        if (state === "action-complete" || state === "approved") return "✓";
        if (state === "action-error" || state === "denied" || state === "stopped") return "✕";
        return "›";
    }
    function fileName(path: string): string {
        return path.split("/").pop();
    }
    function modelLabel(ref: string): string {
        if (!ref) return "";
        let s = ref.replace(/^gguf:/, "").replace(/^cloud:/, "").split("/").pop();
        return s.length > 26 ? s.slice(0, 25) + "…" : s;
    }
    function seconds(ms: real): string {
        if (!(ms > 0)) return "";
        return ms < 10000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms / 1000) + " s";
    }

    // What one click on a chip asks. Clip: the chat adds the clipboard.
    readonly property var clipAsks: [
        { label: card.t("Explain the copy", "Explicar o copiado"),
          prompt: card.t("Explain this clearly and briefly.", "Explique isto de forma clara e curta.") },
        { label: card.t("Translate", "Traduzir"),
          prompt: card.t("Translate this into English, keeping the meaning and tone.",
                         "Traduza isto para o português, mantendo o sentido e o tom.") },
        { label: card.t("Summarize", "Resumir"),
          prompt: card.t("Summarize this in a few bullet points.", "Resuma isto em poucos tópicos.") }
    ]

    onPhaseChanged: {
        if (card.phase === "done" || card.phase === "error") {
            if (!card.st.inline)
                foldTimer.restart();
            leaf.hop();
        }
        if (card.phase === "running" || card.phase === "approval")
            leaf.hop();
    }
    // By count and by id, not by value: `st` is a new object every time the
    // file is read, so "steps changed" would be true on every poll.
    readonly property int stepCount: card.steps.length
    readonly property string hintId: card.hint?.id ?? ""
    onStepCountChanged: if (card.stepCount) leaf.hop()
    onHintIdChanged: if (card.hintId) { hintTimer.restart(); leaf.hop(); }
    onTypingChanged: if (card.typing) Qt.callLater(() => input.forceActiveFocus())

    Timer {
        id: foldTimer

        interval: 9000
        onTriggered: card.seenPhase = card.turnKey
    }

    Timer {
        // A Smart Copy offer nobody took goes away by itself.
        id: hintTimer

        interval: 14000
        onTriggered: card.seenHint = card.hint?.id ?? ""
    }

    Timer {
        // A file nobody decided about goes away on its own.
        id: offerTimer

        interval: 30000
        onTriggered: card.offerPath = ""
    }

    // ── The shape ───────────────────────────────────────────────────────────
    Rectangle {
        id: shape

        anchors.fill: parent
        color: card.ink
        topLeftRadius: card.attached ? 0 : 16
        topRightRadius: card.attached ? 0 : 16
        bottomLeftRadius: card.expanded ? 28 : 19
        bottomRightRadius: card.expanded ? 28 : 19
        border.width: 1
        border.color: Qt.alpha(card.view === "idle" ? card.hi : card.tint, card.view === "idle" ? 0.08 : 0.28)
        Behavior on border.color { ColorAnimation { duration: 300 } }

        // The glow: the colour of what is going on, rising from the bottom.
        // Its own corners: clip cuts to the rectangle, not to the rounding.
        Rectangle {
            anchors.fill: parent
            topLeftRadius: shape.topLeftRadius
            topRightRadius: shape.topRightRadius
            bottomLeftRadius: shape.bottomLeftRadius
            bottomRightRadius: shape.bottomRightRadius
            opacity: card.expanded ? 1 : 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha(card.tint, card.view === "work" || card.view === "ask" ? 0.12 : 0.22) }
            }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        // Working: a light sweeping along the bottom edge, like the island
        // is thinking along its own outline.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: shape.bottomLeftRadius
            anchors.rightMargin: shape.bottomRightRadius
            height: 2
            visible: card.view === "work"
            clip: true

            Rectangle {
                id: sweep

                width: parent.width * 0.35
                height: 2
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: card.accent }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on x {
                    running: card.view === "work"
                    loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: card.expanded ? Qt.ArrowCursor : Qt.PointingHandCursor
        // The leaf's eyes follow the pointer while it is over the island.
        onPointChanged: {
            const c = halo.mapToItem(card, halo.width / 2, halo.height / 2);
            leaf.look = Qt.point(Math.max(-1, Math.min(1, (hover.point.position.x - c.x) / 120)),
                                 Math.max(-1, Math.min(1, (hover.point.position.y - c.y) / 60)));
        }
        onHoveredChanged: if (!hovered) leaf.look = Qt.point(0, 0)
    }

    TapHandler {
        enabled: !card.expanded
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (card.canType)
                card.asking = true;
            else
                card.openChat();
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: card.menuOpen = !card.menuOpen
    }

    DropArea {
        id: drop

        anchors.fill: parent
        anchors.margins: -12
        keys: ["text/uri-list"]
        onDropped: dropEvent => {
            if (!dropEvent.hasUrls || dropEvent.urls.length === 0)
                return;
            const url = dropEvent.urls[0].toString();
            if (!url.startsWith("file://"))
                return;
            card.offerPath = decodeURIComponent(url.slice(7));
            offerTimer.restart();
            dropEvent.accept();
        }
    }

    // ── The leaf, always there; it moves between the pill and the card ─────
    Rectangle {
        id: halo

        readonly property bool big: card.expanded && card.view !== "ask" && card.view !== "menu"
        x: card.expanded ? 16 : 10
        y: card.view === "ask" || card.view === "menu" || card.view === "answer" ? 14 : (card.height - height) / 2
        width: halo.big ? 66 : card.expanded ? 40 : 26
        height: width
        radius: width / 2
        color: Qt.alpha(card.tint, card.expanded ? 0.16 : 0)
        Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
        Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }

        // Breathes while it works.
        SequentialAnimation on scale {
            running: card.view === "work"
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }

        GenesiLeaf {
            id: leaf

            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            pal: card.pal
            size: halo.big ? 44 : card.expanded ? 28 : 20
            mood: card.view === "approval" || card.view === "hint" ? "hot"
                : card.view === "error" ? "sick"
                : card.view === "done" || card.view === "answer" || card.view === "drop" || card.view === "offer" ? "happy"
                : card.phase === "running" ? "dancing"
                : "normal"
            talking: card.view === "work" || card.view === "approval"
            Behavior on size { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
        }

        // A status dot on the halo, like a badge.
        Rectangle {
            visible: halo.big
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 3
            width: 12
            height: 12
            radius: 6
            color: card.view === "approval" || card.view === "hint" ? card.amber : card.view === "error" ? card.red : card.green
            border.width: 2
            border.color: card.ink
        }
    }

    // ── The pill ────────────────────────────────────────────────────────────
    Row {
        anchors.left: halo.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7
        opacity: card.expanded ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: card.hovered ? card.t("Ask anything", "Pergunte algo") : "Genesi AI"
            color: card.hovered ? card.hi : card.mid
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.live && (card.st.open ?? false) && !card.hovered
            width: 6
            height: 6
            radius: 3
            color: card.green
        }
        // The peek: which model answers, and the key that opens the chat.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.hovered && card.implicitWidth > 200
            text: card.modelLabel(card.st.model ?? "") || card.shortcut
            color: card.lo
            font.pixelSize: 10
        }
    }
    Rectangle {
        // The menu, from the pill: the island's own settings.
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: !card.expanded && card.hovered
        width: 22
        height: 22
        radius: 11
        color: dotsHover.hovered ? Qt.alpha(card.hi, 0.16) : "transparent"
        Text {
            anchors.centerIn: parent
            text: "⋯"
            color: card.mid
            font.pixelSize: 14
        }
        HoverHandler {
            id: dotsHover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: card.menuOpen = true
        }
    }

    // ── The card ────────────────────────────────────────────────────────────
    Column {
        id: body

        anchors.left: halo.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.top: card.view === "ask" || card.view === "menu" || card.view === "answer" ? parent.top : undefined
        anchors.topMargin: 14
        anchors.verticalCenter: card.view === "ask" || card.view === "menu" || card.view === "answer" ? undefined : parent.verticalCenter
        spacing: 7
        opacity: card.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        // Header: who, what state, how far.
        Item {
            width: parent.width
            height: 20
            visible: card.view !== "ask"

            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 4
                    color: card.view === "approval" || card.view === "hint" ? card.amber : card.view === "error" ? card.red : card.green
                    SequentialAnimation on opacity {
                        running: card.view === "work"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Text {
                    text: "Genesi AI"
                    color: card.hi
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: card.view === "approval" ? card.t("needs permission", "precisa de permissão")
                        : card.view === "done" || card.view === "answer" ? card.t("answered", "respondeu")
                            + (card.seconds(card.st.elapsed ?? 0) ? " · " + card.seconds(card.st.elapsed) : "")
                        : card.view === "error" ? card.t("something went wrong", "algo deu errado")
                        : card.view === "drop" || card.view === "offer" ? card.t("file", "arquivo")
                        : card.view === "menu" ? card.t("island", "ilha")
                        : card.view === "hint" ? (card.hint?.kind === "error"
                            ? card.t("you copied an error", "você copiou um erro")
                            : card.t("you copied a long text", "você copiou um texto longo"))
                        : card.phase === "running" ? card.t("working", "trabalhando")
                        : card.t("thinking", "pensando")
                    color: card.lo
                    font.pixelSize: 11
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    visible: card.view === "work" && (card.st.total ?? 0) > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.steps.filter(s => card.stepMark(s.state) === "✓").length + "/" + (card.st.total ?? 0)
                    color: card.lo
                    font.pixelSize: 11
                }
                IconButton {
                    c: card
                    // Stop.
                    visible: card.view === "work"
                    danger: true
                    onClicked: card.stopWork()

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 2
                        color: card.hi
                    }
                }
                IconButton {
                    c: card
                    visible: card.view !== "menu" && card.view !== "hint"
                    glyph: "↗"
                    onClicked: card.act("open")
                }
                IconButton {
                    c: card
                    visible: card.view === "menu" || card.view === "hint" || card.view === "answer"
                    glyph: "✕"
                    onClicked: card.act(card.view === "menu" ? "close-menu" : card.view === "hint" ? "dismiss-hint" : "fold")
                }
            }
        }

        // ── ask: the island is the chat ──
        Rectangle {
            visible: card.view === "ask"
            width: parent.width
            height: 40
            radius: 20
            color: card.well
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(card.accent, 0.6) : Qt.alpha(card.hi, 0.1)
            Behavior on border.color { ColorAnimation { duration: 150 } }

            TextInput {
                id: input

                anchors.left: parent.left
                anchors.right: send.left
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: card.hi
                selectionColor: Qt.alpha(card.accent, 0.4)
                font.pixelSize: 14
                clip: true
                Keys.onReturnPressed: card.act("send")
                Keys.onEnterPressed: card.act("send")
                Keys.onEscapePressed: card.act("close-ask")

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: card.t("Ask anything…", "Pergunte qualquer coisa…")
                    color: card.lo
                    font.pixelSize: 14
                }
            }
            Rectangle {
                id: send

                readonly property bool ready: input.text.trim().length > 0
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: send.ready ? card.accent : Qt.alpha(card.hi, 0.08)
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: send.ready ? card.accentInk : card.lo
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.act("send") }
            }
        }
        Flow {
            visible: card.view === "ask"
            width: parent.width
            spacing: 6

            Repeater {
                model: card.view === "ask" ? card.clipAsks : []

                delegate: Chip {
                    c: card
                    required property var modelData
                    text: modelData.label
                    onClicked: card.askNow(modelData.prompt, true)
                }
            }
            Chip {
                c: card
                text: card.t("Full chat ↗", "Chat completo ↗")
                quiet: true
                onClicked: card.act("open")
            }
        }
        Text {
            visible: card.view === "ask"
            width: parent.width
            elide: Text.ElideRight
            text: card.t("Enter to ask · Esc to close · %1 opens the chat",
                         "Enter pergunta · Esc fecha · %1 abre o chat").arg(card.shortcut)
            color: card.lo
            font.pixelSize: 10
        }

        // ── work: the question, then the steps ──
        Text {
            visible: card.view === "work" && (card.st.prompt ?? "") !== ""
            width: parent.width
            text: "“" + (card.st.prompt ?? "") + "”"
            color: card.lo
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Repeater {
            model: card.view === "work" ? card.steps.slice(-3) : []

            delegate: Row {
                id: stepRow

                required property var modelData
                required property int index
                readonly property bool current: stepRow.index === Math.min(card.steps.length, 3) - 1
                                                && card.stepMark(stepRow.modelData.state) === "›"
                width: body.width
                spacing: 6

                Text {
                    text: card.stepMark(stepRow.modelData.state)
                    color: text === "✓" ? card.green : text === "✕" ? card.red : card.hi
                    font.pixelSize: 12
                    width: 10
                }
                Text {
                    width: parent.width - 16
                    text: stepRow.modelData.title + (stepRow.modelData.message ? " · " + stepRow.modelData.message : "")
                    color: stepRow.current ? card.hi : card.mid
                    font.pixelSize: stepRow.current ? 13 : 11
                    font.weight: stepRow.current ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }
        Row {
            visible: card.view === "work" && card.steps.length === 0
            spacing: 4

            Text {
                text: card.st.activity && card.st.activity !== "Thinking" ? card.st.activity : card.t("Thinking", "Pensando")
                color: card.hi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Repeater {
                model: 3

                delegate: Rectangle {
                    id: dot

                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 4
                    radius: 2
                    color: card.hi
                    SequentialAnimation on opacity {
                        running: card.view === "work"
                        loops: Animation.Infinite
                        PauseAnimation { duration: dot.index * 160 }
                        NumberAnimation { to: 0.2; duration: 380 }
                        NumberAnimation { to: 1; duration: 380 }
                        PauseAnimation { duration: (2 - dot.index) * 160 }
                    }
                }
            }
        }

        // ── approval: exactly what will run ──
        Text {
            visible: card.view === "approval"
            width: parent.width
            text: card.approval?.description ?? ""
            color: card.mid
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Rectangle {
            visible: card.view === "approval" && (card.approval?.detail ?? "") !== ""
            width: parent.width
            height: cmd.implicitHeight + 12
            radius: 8
            color: Qt.alpha(card.hi, 0.07)
            Text {
                id: cmd

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: "$ " + (card.approval?.detail ?? "")
                color: card.hi
                font.family: "monospace"
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
            }
        }

        // ── answer: an answer asked from here, whole ──
        Text {
            visible: card.view === "answer" && (card.st.prompt ?? "") !== ""
            width: parent.width
            text: "“" + (card.st.prompt ?? "") + "”"
            color: card.lo
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Flickable {
            id: answerScroll

            visible: card.view === "answer"
            width: parent.width
            height: Math.min(answerText.implicitHeight, 260)
            contentHeight: answerText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: answerText

                width: answerScroll.width
                text: card.st.answer ?? ""
                textFormat: Text.MarkdownText
                color: card.hi
                linkColor: card.accent
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }

        // ── done / error: the start of the answer ──
        Text {
            visible: card.view === "done" || card.view === "error"
            width: parent.width
            text: (card.st.answer ?? "") !== "" ? card.st.answer
                : card.view === "error" ? card.t("The request did not finish.", "O pedido não terminou.")
                : card.t("Ready.", "Pronto.")
            color: card.hi
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        // ── hint: Smart Copy ──
        Rectangle {
            visible: card.view === "hint"
            width: parent.width
            height: hintText.implicitHeight + 12
            radius: 8
            color: Qt.alpha(card.hi, 0.07)
            Text {
                id: hintText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: card.hint?.preview ?? ""
                color: card.mid
                font.family: "monospace"
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
            }
        }

        // ── menu: the island's settings ──
        Repeater {
            model: card.view === "menu" ? [
                    { key: "mode", label: card.t("Show the island", "Mostrar a ilha"),
                      value: card.prefs.mode ?? "always",
                      options: [{ v: "always", t: card.t("Always", "Sempre") },
                                { v: "quickchat", t: card.t("With the chat", "Com o chat") }] },
                    { key: "actions", label: card.t("Actions", "Ações"),
                      value: card.st.actionMode ?? "approval",
                      options: [{ v: "approval", t: card.t("Ask first", "Perguntar antes") },
                                { v: "automatic", t: card.t("Automatic", "Automático") }] },
                    { key: "smartClip", label: card.t("Smart Copy", "Cópia inteligente"),
                      value: card.prefs.smartClip ? "on" : "off",
                      options: [{ v: "on", t: card.t("On", "Ligada") },
                                { v: "off", t: card.t("Off", "Desligada") }] }
                ] : []

            delegate: Item {
                id: row

                required property var modelData
                width: body.width
                height: 30

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - segBox.width - 10
                    text: row.modelData.label
                    color: card.mid
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: segBox

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: seg.implicitWidth + 6
                    height: 28
                    radius: 14
                    color: card.well

                    Row {
                        id: seg

                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: row.modelData.options

                            delegate: Rectangle {
                                id: opt

                                required property var modelData
                                readonly property bool on: row.modelData.value === opt.modelData.v
                                width: optText.implicitWidth + 20
                                height: 22
                                radius: 11
                                color: opt.on ? card.accent : optHover.hovered ? Qt.alpha(card.hi, 0.1) : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text {
                                    id: optText

                                    anchors.centerIn: parent
                                    text: opt.modelData.t
                                    color: opt.on ? card.accentInk : card.mid
                                    font.pixelSize: 11
                                    font.weight: opt.on ? Font.DemiBold : Font.Normal
                                }
                                HoverHandler {
                                    id: optHover

                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: card.setting(row.modelData.key, opt.modelData.v)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── drop / offer ──
        Rectangle {
            visible: card.view === "drop"
            width: parent.width
            height: 46
            radius: 12
            color: "transparent"
            border.width: 1.5
            border.color: Qt.alpha(card.green, 0.6)
            Column {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: card.t("Drop your file here", "Solte o arquivo aqui")
                    color: card.hi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: card.t("PDF · text · code · images by path", "PDF · texto · código · imagens pelo caminho")
                    color: card.lo
                    font.pixelSize: 10
                }
            }
        }
        Text {
            visible: card.view === "offer"
            width: parent.width
            text: card.t("%1 is ready. What should I do with it?", "%1 está pronto. O que eu faço com ele?").arg(card.fileName(card.offerPath))
            color: card.hi
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideMiddle
        }

        // ── the buttons of whichever view this is ──
        Row {
            spacing: 8
            topPadding: 2
            visible: buttons.count > 0

            Repeater {
                id: buttons

                model: card.view === "approval" ? [
                        { text: card.t("Deny", "Negar"), act: "deny", filled: false },
                        { text: card.approveLabel(card.approval?.approve ?? "Allow"), act: "approve", filled: true }
                    ]
                    : card.view === "answer" ? [
                        { text: card.t("Continue in chat", "Continuar no chat"), act: "open", filled: true },
                        { text: card.t("Copy", "Copiar"), act: "copy", filled: false },
                        { text: card.t("Ask again", "Perguntar mais"), act: "followup", filled: false }
                    ]
                    : card.view === "done" || card.view === "error" ? [
                        { text: card.t("Open chat", "Abrir chat"), act: "open", filled: true },
                        { text: "OK", act: "fold", filled: false }
                    ]
                    : card.view === "hint" ? (card.hint?.kind === "error" ? [
                        { text: card.t("Explain it", "Explicar"), act: "hint-explain", filled: true },
                        { text: card.t("How do I fix it?", "Como corrijo?"), act: "hint-fix", filled: false }
                    ] : [
                        { text: card.t("Summarize", "Resumir"), act: "hint-summary", filled: true },
                        { text: card.t("Translate", "Traduzir"), act: "hint-translate", filled: false }
                    ])
                    : card.view === "offer" ? [
                        { text: card.t("Ask about it", "Perguntar sobre ele"), act: "ask", filled: true },
                        { text: card.t("Summarize", "Resumir"), act: "summary", filled: false },
                        { text: card.t("Cancel", "Cancelar"), act: "cancel", filled: false }
                    ]
                    : card.view === "menu" ? [
                        { text: card.t("Open Quick Chat", "Abrir Quick Chat"), act: "open", filled: true }
                    ]
                    : []

                delegate: Rectangle {
                    id: btn

                    required property var modelData
                    width: label.implicitWidth + 26
                    height: 28
                    radius: 14
                    color: btn.modelData.filled ? (btnHover.hovered ? Qt.lighter(card.accent, 1.12) : card.accent)
                                                : (btnHover.hovered ? Qt.alpha(card.hi, 0.16) : Qt.alpha(card.hi, 0.08))
                    Text {
                        id: label

                        anchors.centerIn: parent
                        text: btn.modelData.text
                        color: btn.modelData.filled ? card.accentInk : card.hi
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    HoverHandler {
                        id: btnHover

                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: card.act(btn.modelData.act)
                    }
                }
            }
        }
    }

    // ── Small pieces ────────────────────────────────────────────────────────
    // Inline components do not see this file's ids: each one is handed the
    // card as `c`.
    component IconButton: Rectangle {
        id: ib

        property Item c
        property string glyph: ""
        property bool danger: false
        signal clicked

        width: 22
        height: 22
        radius: 11
        color: ibHover.hovered ? Qt.alpha(ib.danger ? ib.c.red : ib.c.hi, ib.danger ? 0.3 : 0.18) : Qt.alpha(ib.c.hi, 0.08)
        Text {
            anchors.centerIn: parent
            visible: ib.glyph !== ""
            text: ib.glyph
            color: ib.c.hi
            font.pixelSize: 11
        }
        HoverHandler {
            id: ibHover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: ib.clicked()
        }
    }

    component Chip: Rectangle {
        id: chip

        property Item c
        property string text: ""
        property bool quiet: false
        signal clicked

        width: chipText.implicitWidth + 22
        height: 26
        radius: 13
        color: chipHover.hovered ? Qt.alpha(chip.c.accent, 0.22) : chip.quiet ? "transparent" : Qt.alpha(chip.c.accent, 0.1)
        border.width: 1
        border.color: Qt.alpha(chip.c.accent, chip.quiet ? 0.2 : 0.35)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: chipText

            anchors.centerIn: parent
            text: chip.text
            color: chip.c.hi
            font.pixelSize: 11
        }
        HoverHandler {
            id: chipHover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: chip.clicked()
        }
    }

    // ── What every button does ─────────────────────────────────────────────
    function askNow(text: string, withClip: bool): void {
        const q = text.trim();
        if (q === "")
            return;
        card.ask(q, withClip);
        input.text = "";
        card.asking = false;
    }

    function act(what: string): void {
        if (what === "approve")
            card.approve(card.approval?.id ?? "");
        else if (what === "deny")
            card.deny(card.approval?.id ?? "");
        else if (what === "open") {
            card.seenPhase = card.turnKey;
            card.asking = false;
            card.menuOpen = false;
            card.openChat();
        } else if (what === "fold")
            card.seenPhase = card.turnKey;
        else if (what === "copy")
            card.copyText(card.st.answer ?? "");
        else if (what === "followup") {
            card.seenPhase = card.turnKey;
            card.asking = true;
        } else if (what === "send")
            card.askNow(input.text, false);
        else if (what === "close-ask") {
            input.text = "";
            card.asking = false;
        } else if (what === "close-menu")
            card.menuOpen = false;
        else if (what === "dismiss-hint")
            card.seenHint = card.hint?.id ?? "";
        else if (what.startsWith("hint-")) {
            const prompts = {
                "hint-explain": card.t("Explain this error: what it means and why it happens.",
                                       "Explique este erro: o que significa e por que acontece."),
                "hint-fix": card.t("How do I fix this error? Give me concrete steps.",
                                   "Como eu corrijo este erro? Me dê passos concretos."),
                "hint-summary": card.clipAsks[2].prompt,
                "hint-translate": card.clipAsks[1].prompt
            };
            card.seenHint = card.hint?.id ?? "";
            card.ask(prompts[what] ?? "", true);
        } else if (what === "ask" || what === "summary") {
            card.attach(card.offerPath, what === "summary"
                ? card.t("Summarize this file in a few bullet points.", "Resuma este arquivo em poucos tópicos.") : "");
            card.offerPath = "";
        } else if (what === "cancel")
            card.offerPath = "";
    }
}
