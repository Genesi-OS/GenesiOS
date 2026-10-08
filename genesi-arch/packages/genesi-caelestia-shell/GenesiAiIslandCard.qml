// GENESI — the AI island: what it looks like and what it says.
//
// Drawing only, in plain QtQuick, so ci/plugins-test.py can play every state
// offscreen and look at it. GenesiAiIsland is the window around it: it reads
// the Quick Chat's state file, decides on which screen and when, and runs the
// commands this card asks for.
//
// ── What it shows ─────────────────────────────────────────────────────────
//
//   idle       a small black pill with the leaf; a click opens the chat
//   thinking   the leaf talking, the question, "Pensando…"
//   running    the leaf dancing, the agent's steps as they happen (2/4)
//   approval   the leaf sweating, the exact command, Negar / Permitir
//   done       the leaf happy, the start of the answer, Abrir chat / OK
//   error      the leaf sick, what went wrong
//   a drag     "Solte o arquivo aqui"; after the drop, what to do with it
//
// `st` is the Quick Chat's genesi-ai-island.json as it was last read:
//   {phase, activity, steps:[{title,state,message}], total, approval:
//    {id,title,description,risk,approve,detail}, answer, prompt, model, open}
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: card

    property var st: ({})
    property var pal: ({})
    // The Quick Chat is running (its state file is there).
    property bool live: false
    // Flush with the top of the screen (a notch) or hanging under a bar.
    property bool attached: true
    property bool hovered: hover.hovered

    readonly property string phase: card.live ? (card.st.phase ?? "idle") : "idle"
    readonly property var steps: card.st.steps ?? []
    readonly property var approval: card.st.approval ?? null

    // A finished answer or an error stays until it is looked at -- or for a
    // while, then the island folds back. Per state: a new phase brings it back.
    property string seenPhase: ""
    property string offerPath: ""
    readonly property bool dragging: drop.containsDrag
    // Which request this is: a phase seen for one request is not seen for the next.
    readonly property string turnKey: card.phase + ":" + (card.st.pid ?? "") + ":" + (card.st.turn ?? "")

    readonly property string view: card.dragging ? "drop"
        : card.offerPath !== "" ? "offer"
        : card.phase === "approval" && card.approval ? "approval"
        : (card.phase === "thinking" || card.phase === "running") ? "work"
        : (card.phase === "done" || card.phase === "error") && card.seenPhase !== card.turnKey ? card.phase
        : "idle"
    readonly property bool expanded: card.view !== "idle"

    readonly property bool pt: Qt.locale().name.startsWith("pt")
    function t(en: string, ptText: string): string {
        return card.pt ? ptText : en;
    }

    signal openChat
    signal approve(string id)
    signal deny(string id)
    signal stopWork
    signal attach(string path, string request)

    readonly property color ink: "#0a0b0f"
    readonly property color hi: "#f2f4f8"
    readonly property color mid: "#a9b1c0"
    readonly property color lo: "#6d7586"
    readonly property color green: "#3ccf7e"
    readonly property color amber: "#f0a43a"
    readonly property color red: "#ef5b5b"
    readonly property color accent: card.pal.m3primary ?? "#7aa2ff"

    readonly property color tint: card.view === "approval" ? card.amber
        : card.view === "done" || card.view === "drop" || card.view === "offer" ? card.green
        : card.view === "error" ? card.red
        : card.accent

    readonly property int fullWidth: 500
    implicitWidth: card.expanded ? card.fullWidth : (card.hovered ? 196 : 164)
    implicitHeight: card.expanded ? Math.max(92, body.implicitHeight + 26) : 38

    Behavior on implicitWidth {
        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
    }

    // ── Approval labels come from the agent in English ─────────────────────
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

    onPhaseChanged: {
        if (card.phase === "done" || card.phase === "error")
            foldTimer.restart();
        if (card.phase === "running" || card.phase === "approval")
            leaf.hop();
    }
    onStepsChanged: if (card.steps.length) leaf.hop()

    Timer {
        id: foldTimer

        interval: 9000
        onTriggered: card.seenPhase = card.turnKey
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
        color: Qt.alpha(card.ink, 0.97)
        topLeftRadius: card.attached ? 0 : 14
        topRightRadius: card.attached ? 0 : 14
        bottomLeftRadius: card.expanded ? 26 : 19
        bottomRightRadius: card.expanded ? 26 : 19
        border.width: 1
        border.color: Qt.alpha("white", 0.06)

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
                GradientStop { position: 1.0; color: Qt.alpha(card.tint, card.view === "work" ? 0.14 : 0.26) }
            }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: card.expanded ? Qt.ArrowCursor : Qt.PointingHandCursor
    }

    TapHandler {
        enabled: !card.expanded
        onTapped: card.openChat()
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

        x: card.expanded ? 16 : 10
        y: card.expanded ? (card.height - height) / 2 : (card.height - height) / 2
        width: card.expanded ? 66 : 26
        height: width
        radius: width / 2
        color: Qt.alpha(card.tint, card.expanded ? 0.16 : 0)
        Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
        Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
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
            size: card.expanded ? 44 : 20
            mood: card.view === "approval" ? "hot"
                : card.view === "error" ? "sick"
                : card.view === "done" || card.view === "drop" || card.view === "offer" ? "happy"
                : card.phase === "running" ? "dancing"
                : "normal"
            talking: card.view === "work" || card.view === "approval"
            Behavior on size { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
        }

        // A status dot on the halo, like a badge.
        Rectangle {
            visible: card.expanded
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 3
            width: 12
            height: 12
            radius: 6
            color: card.view === "approval" ? card.amber : card.view === "error" ? card.red : card.green
            border.width: 2
            border.color: card.ink
        }
    }

    // ── The pill ────────────────────────────────────────────────────────────
    Row {
        anchors.left: halo.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        opacity: card.expanded ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: card.hovered ? card.t("Ask the AI", "Perguntar à IA") : "Genesi AI"
            color: card.hovered ? card.hi : card.mid
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.live && (card.st.open ?? false)
            width: 6
            height: 6
            radius: 3
            color: card.green
        }
    }

    // ── The card ────────────────────────────────────────────────────────────
    Column {
        id: body

        anchors.left: halo.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        opacity: card.expanded ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        // Header: who, what state, how far.
        Item {
            width: parent.width
            height: 18

            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 4
                    color: card.view === "approval" ? card.amber : card.view === "error" ? card.red : card.green
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
                        : card.view === "done" ? card.t("done", "terminou")
                        : card.view === "error" ? card.t("something went wrong", "algo deu errado")
                        : card.view === "drop" || card.view === "offer" ? card.t("file", "arquivo")
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
                Rectangle {
                    // Stop.
                    visible: card.view === "work"
                    width: 22
                    height: 22
                    radius: 11
                    color: stopHover.hovered ? Qt.alpha(card.red, 0.3) : Qt.alpha("white", 0.08)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 2
                        color: card.hi
                    }
                    HoverHandler {
                        id: stopHover

                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: card.stopWork()
                    }
                }
                Rectangle {
                    // Open the chat.
                    width: 22
                    height: 22
                    radius: 11
                    color: openHover.hovered ? Qt.alpha("white", 0.18) : Qt.alpha("white", 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: "↗"
                        color: card.hi
                        font.pixelSize: 11
                    }
                    HoverHandler {
                        id: openHover

                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: card.openChat()
                    }
                }
            }
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
            color: Qt.alpha("white", 0.07)
            Text {
                id: cmd

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: card.approval?.detail ?? ""
                color: card.hi
                font.family: "monospace"
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
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
                    : card.view === "done" || card.view === "error" ? [
                        { text: card.t("Open chat", "Abrir chat"), act: "open", filled: true },
                        { text: "OK", act: "fold", filled: false }
                    ]
                    : card.view === "offer" ? [
                        { text: card.t("Ask about it", "Perguntar sobre ele"), act: "ask", filled: true },
                        { text: card.t("Summarize", "Resumir"), act: "summary", filled: false },
                        { text: card.t("Cancel", "Cancelar"), act: "cancel", filled: false }
                    ]
                    : []

                delegate: Rectangle {
                    id: btn

                    required property var modelData
                    width: label.implicitWidth + 26
                    height: 28
                    radius: 14
                    color: btn.modelData.filled ? (btnHover.hovered ? "white" : card.hi)
                                                : (btnHover.hovered ? Qt.alpha("white", 0.16) : Qt.alpha("white", 0.08))
                    Text {
                        id: label

                        anchors.centerIn: parent
                        text: btn.modelData.text
                        color: btn.modelData.filled ? card.ink : card.hi
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

    function act(what: string): void {
        if (what === "approve")
            card.approve(card.approval?.id ?? "");
        else if (what === "deny")
            card.deny(card.approval?.id ?? "");
        else if (what === "open") {
            card.seenPhase = card.turnKey;
            card.openChat();
        } else if (what === "fold")
            card.seenPhase = card.turnKey;
        else if (what === "ask" || what === "summary") {
            card.attach(card.offerPath, what === "summary"
                ? card.t("Summarize this file in a few bullet points.", "Resuma este arquivo em poucos tópicos.") : "");
            card.offerPath = "";
        } else if (what === "cancel")
            card.offerPath = "";
    }
}
