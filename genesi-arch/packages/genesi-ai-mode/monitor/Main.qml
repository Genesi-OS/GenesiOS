import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi AI Mode Monitor"
    width: Kirigami.Units.gridUnit * 64
    height: Kirigami.Units.gridUnit * 42
    // The old floor was 52 grid units (~936px), which is wider than the point
    // the layout collapses at -- so the collapsed layout could never actually
    // be reached, and the app simply refused to be made small. It now goes down
    // to a size a half-screen tile on a 1366 laptop gives you.
    minimumWidth: Kirigami.Units.gridUnit * 38
    minimumHeight: Kirigami.Units.gridUnit * 26
    color: theme.bgBottom

    Theme { id: theme }
    I18n { id: i18n }

    property var st: ({})
    property bool active: false
    property string forceMode: "auto"
    property string profileMode: "auto"
    property string activity: "idle"   // active | warm | idle (smart auto-detect)
    property int currentTab: 0

    // ── Breakpoints ────────────────────────────────────────────────────────
    // Two numbers, each named for what it protects. Below `wide` the right rail
    // goes: everything on it is reachable from the top bar or the nav, so it is
    // the first thing that can afford to leave. Below `roomy` the sidebar
    // collapses to an icon rail rather than disappearing — losing the labels
    // costs a little, losing navigation entirely would strand the user on
    // whatever page they happened to be on.
    readonly property bool wide:     width >= 1180
    readonly property bool railMode: width < 1000

    // ── chat history (sidebar HISTORY rail) + MemPalace recall ──
    property var sessions: []          // [{id,title,updated,count}] newest-first
    property bool recall: false        // "AI remembers everything" (heavier, opt-in)

    function refreshSessions() {
        try { sessions = JSON.parse(backend.listSessions()) } catch (e) { sessions = [] }
    }
    function relTime(ts) {
        if (!ts) return ""
        var d = Date.now() / 1000 - ts
        if (d < 60)     return "now"
        if (d < 3600)   return Math.floor(d / 60) + "m"
        if (d < 86400)  return Math.floor(d / 3600) + "h"
        if (d < 604800) return Math.floor(d / 86400) + "d"
        return Math.floor(d / 604800) + "w"
    }
    function openSession(sid) { chatPage.loadSessionInto(sid); win.currentTab = 1 }
    function newChat() { chatPage.newChat(); win.currentTab = 1 }

    // ── Turbo integration ───────────────────────────────────────────────────
    // activeModel = the model Ollama currently has LOADED (live, from /api/ps).
    // It drives the dashboard "AI ativa" card and FLICKERS as Ollama loads/evicts
    // models (keep-alive) or returns an empty /api/ps between cycles — so it must
    // NOT directly control the Turbo server's lifecycle.
    property string activeModel: (st.ollama && st.ollama.length > 0) ? st.ollama[0].name : ""
    property bool turboRequested: false
    property bool turboSpec: false        // use speculative decoding for Turbo?
    // One-shot guard: we default turboSpec ON the FIRST time we learn the backend
    // is CUDA (spec is the proven win there). After that the user's toggle wins —
    // re-opening the backend dialog re-emits backendAdvice and must not flip it.
    property bool turboSpecInit: false
    property string backendCurrent: ""    // installed backend: cuda | vulkan | ""
    property bool turboNeedsInstall: false
    property string turboStatusText: ""

    // Backend install choice (Vulkan universal ⇄ CUDA NVIDIA-only)
    property string backendRecommend: "vulkan"
    property string backendReason: ""
    property bool backendNvWorks: false
    property bool backendHasNvidia: false
    property string backendAur: ""

    // ── Benchmark integration ───────────────────────────────────────────────
    property bool benchRunning: false
    property string benchProgress: ""
    property string benchError: ""
    property bool benchHasResult: false
    property real benchOff: 0
    property real benchOn: 0
    property real benchDelta: 0
    property string benchModel: ""

    // Advisor → Turbo model pick (biggest model that fits 100% in VRAM)
    property string turboRecommend: ""

    // turboModel = the STABLE model Turbo serves. Driven from activeModel when it
    // has a value, otherwise the first installed model. It is sticky: it NEVER
    // resets to "" on a transient empty poll. Previously Turbo was bound straight
    // to the volatile activeModel, so every 2s flicker stopped + restarted
    // llama-server — the load counter kept resetting to 0 and Turbo never came up.
    property string firstInstalledModel: ""
    property string turboModel: ""
    // All installed (Ollama) models — feeds the "which model?" picker shown
    // when Turbo is switched on.
    property var installedModels: []
    // Set true once the user explicitly picks a Turbo model. While locked, the
    // live activeModel / firstInstalledModel auto-seed below must NOT overwrite
    // their choice — that was the "Turbo starts with a model I didn't pick" bug.
    property bool turboModelLocked: false
    // Path of the local GGUF currently handed to Turbo ("" when the selection is
    // a normal Ollama tag). Drives the "in use" state in the GGUF library list.
    property string turboGguf: ""

    onActiveModelChanged: if (activeModel && !turboModelLocked) turboModel = activeModel
    onFirstInstalledModelChanged: if (!turboModel && firstInstalledModel && !turboModelLocked) turboModel = firstInstalledModel

    // Changing the model only (re)starts Turbo — it never stops it. Only the user
    // flipping the switch off (turboRequested=false) stops the Turbo server.
    // True while poll() is copying the REAL Turbo state into these properties.
    // Every handler below has to stand down during that, or the sync becomes a
    // feedback loop: the poll assigns turboRequested, the handler fires, and
    // setTurbo restarts the very server we were only trying to display.
    property bool turboSyncing: false

    onTurboModelChanged: {
        if (turboSyncing) return
        // Switching back to a normal Ollama tag clears the GGUF selection, so the
        // library list stops showing a stale "in use" badge.
        if (turboGguf && turboModel !== turboGguf) turboGguf = ""
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
    }
    onTurboRequestedChanged: {
        if (turboSyncing) return
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
        else if (!turboRequested) {
            backend.setTurbo(false, "", false)
            turboGguf = ""     // nothing is being served -> drop the "in use" badge
        }
    }
    // Flipping speculative on/off while Turbo runs restarts it in the new mode.
    onTurboSpecChanged: {
        if (turboSyncing) return
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
    }

    Component.onCompleted: {
        backend.loadModels(); backend.recommendTurboModel(); backend.backendInfo()
        win.refreshSessions()
        try { win.recall = JSON.parse(backend.mempalaceState()).recall || false } catch (e) {}
    }

    Connections {
        target: backend
        function onSessionsChanged() { win.refreshSessions() }
        function onTurboNeedsInstall(need) {
            win.turboNeedsInstall = need
            if (need) win.turboRequested = false
        }
        function onTurboStatus(s) { win.turboStatusText = s }
        function onTurboRecommended(tag) { win.turboRecommend = tag }
        function onBackendAdvice(jsonStr) {
            var a = ({})
            try { a = JSON.parse(jsonStr) } catch (e) { return }
            win.backendRecommend = a.recommend || "vulkan"
            win.backendReason = a.reason || ""
            win.backendNvWorks = a.nvidia_works || false
            win.backendHasNvidia = a.has_nvidia || false
            win.backendAur = a.aur || ""
            win.backendCurrent = a.current || ""
            // First time we see a CUDA backend, default ⚡ speculative ON (it's the
            // real Turbo win on CUDA; harmless on models that spill VRAM — the CLI
            // drops the draft then). Only once, so the user's toggle stays sticky.
            if (!win.turboSpecInit) {
                win.turboSpecInit = true
                if (a.current === "cuda") win.turboSpec = true
            }
        }
        // Seed a default Turbo model from the installed list, so Turbo can start
        // even before the first Ollama prompt (otherwise activeModel stays empty
        // until something is loaded and the switch appears to do nothing).
        function onModelsLoaded(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            win.installedModels = arr
            if (arr.length > 0) win.firstInstalledModel = arr[0]
        }
        // ── Benchmark ──
        function onBenchRunning(on) {
            win.benchRunning = on
            if (on) { win.benchError = ""; win.benchProgress = "starting…" }
        }
        function onBenchProgress(s) { win.benchProgress = s }
        function onBenchError(s) { win.benchError = s; win.benchProgress = "" }
        function onBenchDone(jsonStr) {
            var r = ({})
            try { r = JSON.parse(jsonStr) } catch (e) { return }
            win.benchOff = r.off_rate || 0
            win.benchOn = r.on_rate || 0
            win.benchDelta = r.delta_pct || 0
            win.benchModel = r.model || ""
            win.benchHasResult = true
            win.benchProgress = ""
        }
    }

    function num(v, suffix) { return v === undefined || v === null ? "—" : v + (suffix || "") }
    function metrics() { return st.metrics || ({}) }
    function gpus() { return (st.metrics && st.metrics.gpus) || [] }
    function hw() { return st.hardware || ({}) }

    function poll() {
        var txt = backend.state()
        try { st = JSON.parse(txt) } catch (e) { st = ({}) }
        active = st.ai_mode_active || false
        forceMode = st.force_mode || "auto"
        profileMode = st.profile_mode || "auto"
        activity = st.activity || "idle"

        // Reflect what Turbo is ACTUALLY doing, not what this window last asked
        // for. Anything can start it — an automation, the CLI, a Mesh peer, a
        // server left over from the previous session — and until now the switch
        // only ever showed this window's own intent, so the machine could be
        // serving a model with the switch sitting at off.
        //
        // Skipped while turbo_busy: a start takes seconds to answer /health,
        // and syncing from the probe in that window would flick the switch back
        // under the user's finger.
        if (st.turbo_busy !== true && st.turbo_running !== undefined) {
            turboSyncing = true
            if (st.turbo_running !== turboRequested)
                turboRequested = st.turbo_running
            // Adopt the model it is really serving, so the UI does not label a
            // running server with the model this window happened to have picked.
            if (st.turbo_running && st.turbo_model && st.turbo_model !== "?"
                    && st.turbo_model !== turboModel) {
                turboModelLocked = true
                turboModel = st.turbo_model
            }
            turboSyncing = false
        }
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.poll() }

    globalDrawer: null

    Rectangle {
        anchors.fill: parent
        color: theme.bgBottom
        z: 0
    }

    // ════════════════════════ HEADER ════════════════════════
    header: QQC2.ToolBar {
        implicitHeight: 50
        background: Rectangle {
            color: theme.bgTop
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }
        }
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { width: Kirigami.Units.smallSpacing }

            // ── Brand mark ──
            // App brand mark — the Genesi AI Mode Monitor symbol (leaf logo),
            // standalone in the brand green, matching the mockup header.
            Kirigami.Icon {
                source: Qt.resolvedUrl("icons/logo.svg")
                isMask: true
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                color: theme.greenBright
            }
            ColumnLayout {
                spacing: -2
                QQC2.Label { text: "Genesi AI"; font.bold: true; font.pixelSize: 15; color: theme.textHi }
                QQC2.Label { text: "MODE MONITOR"; font.pixelSize: 9; font.letterSpacing: 2; color: theme.green }
            }

            Item { Layout.fillWidth: true }

            // ── Mode segmented control ──
            Rectangle {
                radius: 11
                color: theme.card
                border.width: 1; border.color: theme.line
                implicitWidth: modeRow.implicitWidth + 8
                implicitHeight: 36
                Row {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: [
                            { "mode": "on",   "key": "mode.on",   "accent": theme.green },
                            { "mode": "auto", "key": "mode.auto", "accent": theme.green },
                            { "mode": "off",  "key": "mode.off",  "accent": theme.red }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: win.forceMode === modelData.mode
                            height: 28
                            width: mlbl.implicitWidth + 22
                            radius: 8
                            color: sel ? theme.a(modelData.accent, 0.9)
                                 : (mma.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }
                            QQC2.Label {
                                id: mlbl
                                anchors.centerIn: parent
                                text: i18n.t(modelData.key)
                                font.bold: sel
                                font.pixelSize: 12
                                color: sel ? "#08130E" : theme.textMid
                            }
                            MouseArea {
                                id: mma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setMode(modelData.mode)
                            }
                        }
                    }
                }
            }

            // ── Profile segmented control (intensity) ──
            // Hidden on a narrow window: it is the widest group up here and the
            // same control sits on the Dashboard, so nothing is lost.
            Rectangle {
                visible: !win.railMode
                radius: 11
                color: theme.card
                border.width: 1; border.color: theme.line
                implicitWidth: profRow.implicitWidth + 8
                implicitHeight: 36
                Row {
                    id: profRow
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: [
                            { "p": "max",      "key": "prof.max",      "accent": theme.green },
                            { "p": "balanced", "key": "prof.balanced", "accent": theme.green },
                            { "p": "battery",  "key": "prof.battery",  "accent": theme.green },
                            { "p": "auto",     "key": "prof.auto",     "accent": theme.green }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: win.profileMode === modelData.p
                            height: 28
                            width: plbl.implicitWidth + 22
                            radius: 8
                            color: sel ? theme.a(modelData.accent, 0.9)
                                 : (pma.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }
                            QQC2.Label {
                                id: plbl
                                anchors.centerIn: parent
                                text: i18n.t(modelData.key)
                                font.bold: sel
                                font.pixelSize: 12
                                color: sel ? "#08130E" : theme.textMid
                            }
                            MouseArea {
                                id: pma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setProfile(modelData.p)
                            }
                        }
                    }
                }
            }

            // Quick Chat discoverability: visible command + shortcut keycap.
            Rectangle {
                radius: 9
                implicitWidth: quickChatRow.implicitWidth + 18
                implicitHeight: 36
                color: quickChatMa.containsMouse ? theme.a(theme.green, 0.16) : theme.card
                border.width: 1
                border.color: quickChatMa.containsMouse ? theme.a(theme.green, 0.55) : theme.line
                Behavior on color { ColorAnimation { duration: 140 } }
                Row {
                    id: quickChatRow
                    anchors.centerIn: parent
                    spacing: 7
                    Kirigami.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "input-keyboard"
                        width: 17; height: 17
                        color: theme.greenBright
                    }
                    QQC2.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Quick Chat"
                        color: theme.textHi
                        font.bold: true
                        font.pixelSize: 11
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: quickKeys.implicitWidth + 10
                        implicitHeight: 20
                        radius: 5
                        color: theme.bgBottom
                        border.width: 1; border.color: theme.lineHi
                        QQC2.Label {
                            id: quickKeys
                            anchors.centerIn: parent
                            text: "Ctrl Alt Space"
                            color: theme.textMid
                            font.family: theme.mono
                            font.pixelSize: 9
                        }
                    }
                }
                MouseArea {
                    id: quickChatMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.openQuickChat()
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.text: "Open Quick Chat from anywhere with Ctrl+Alt+Space"
                    QQC2.ToolTip.delay: 350
                }
            }

            // ── Language switch (EN / PT) ──
            Rectangle {
                radius: 11
                implicitWidth: langRow.implicitWidth + 18
                implicitHeight: 36
                color: langMa.containsMouse ? theme.a(theme.green, 0.14) : theme.card
                border.width: 1; border.color: theme.line
                Behavior on color { ColorAnimation { duration: 150 } }
                Row {
                    id: langRow
                    anchors.centerIn: parent
                    spacing: 6
                    Kirigami.Icon { anchors.verticalCenter: parent.verticalCenter; source: "globe"; width: 16; height: 16; color: theme.textMid }
                    QQC2.Label { anchors.verticalCenter: parent.verticalCenter; text: i18n.code; font.bold: true; font.pixelSize: 12; color: theme.textHi }
                }
                MouseArea {
                    id: langMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: i18n.toggle()
                    QQC2.ToolTip.text: i18n.t("lang.tooltip")
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 400
                }
            }

            Item { width: Kirigami.Units.smallSpacing }
        }
    }

    // ════════════════════════ CONTENT ════════════════════════
    RowLayout {
        z: 1
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // ──────────────────────── SIDEBAR (nav) ────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: win.railMode ? 62 : 218
            Behavior on Layout.preferredWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            radius: 18
            color: theme.card
            border.width: 1
            border.color: theme.lineHi

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: theme.a(theme.violet, 0.20)
                        border.width: 1
                        border.color: theme.a(theme.violet, 0.45)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: Qt.resolvedUrl("icons/logo.svg")
                            isMask: true
                            width: 20; height: 20
                            color: theme.greenBright
                        }
                    }
                    ColumnLayout {
                        visible: !win.railMode
                        Layout.fillWidth: true
                        spacing: -2
                        QQC2.Label { text: "Genesi"; font.bold: true; font.pixelSize: 14; color: theme.textHi }
                        QQC2.Label { text: win.active ? "AI Mode active" : "AI Mode standby"; font.pixelSize: 10; color: win.active ? theme.greenBright : theme.textLo }
                    }
                    Kirigami.Icon { visible: !win.railMode; source: "configure"; Layout.preferredWidth: 15; Layout.preferredHeight: 15; color: theme.textLo }
                }

                Rectangle {
                    visible: !win.railMode
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 9
                    color: theme.a(theme.textHi, 0.045)
                    border.width: 1
                    border.color: theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 7
                        Kirigami.Icon { source: "search"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: theme.textLo }
                        QQC2.Label { text: "Search monitor..."; color: theme.textLo; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }

                QQC2.Label {
                    visible: !win.railMode
                    text: "GENERAL"
                    color: theme.textLo
                    font.pixelSize: 10
                    font.letterSpacing: 1.1
                }

                Repeater {
                    model: [
                        { "icon": "icons/nav-dashboard.svg", "key": "nav.dashboard" },
                        { "icon": "icons/nav-chat.svg",      "key": "nav.chat" },
                        { "icon": "icons/nav-models.svg",    "key": "nav.models" },
                        { "icon": "icons/zap.svg",           "key": "nav.automations", "label": "Automations" },
                        { "icon": "icons/nav-models.svg",    "key": "nav.mesh", "label": "Mesh" }
                    ]
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property bool sel: win.currentTab === index
                        Layout.fillWidth: true
                        // Layout.preferredHeight, not height: a ColumnLayout
                        // overrides a plain `height`, and once the rail hides
                        // everything below the nav there was nothing left to
                        // absorb the slack, so the five items stretched to fill
                        // the sidebar.
                        Layout.preferredHeight: 38
                        radius: 10
                        color: sel ? theme.a(theme.green, 0.16)
                             : (navMa.containsMouse ? theme.a(theme.textHi, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: 150 } }
                        // Selected accent rail (left) — the mockup's bright-green bar.
                        Rectangle {
                            visible: sel
                            width: 3; radius: 1.5
                            height: parent.height - 16
                            anchors.left: parent.left; anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: theme.greenBright
                        }
                        // Brand mask icon, tinted by the system scheme (selected =
                        // accent, idle = muted text) so it still follows the theme.
                        Kirigami.Icon {
                            anchors.left: parent.left
                            // Centred on the rail, where there is no label to sit
                            // next to. Computed rather than re-anchored: swapping
                            // anchors at runtime is how items end up at 0,0.
                            anchors.leftMargin: win.railMode
                                                ? Math.max(0, (parent.width - 21) / 2) : 11
                            anchors.verticalCenter: parent.verticalCenter
                            source: Qt.resolvedUrl(modelData.icon)
                            isMask: true
                            width: 21; height: 21
                            color: sel ? theme.greenBright : theme.textMid
                        }
                        QQC2.Label {
                            visible: !win.railMode
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label !== undefined ? modelData.label : i18n.t(modelData.key)
                            color: sel ? theme.textHi : theme.textMid
                            font.bold: sel
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: navMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.currentTab = index
                            QQC2.ToolTip.text: modelData.label !== undefined ? modelData.label : i18n.t(modelData.key)
                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 400
                        }
                    }
                }

                QQC2.Label {
                    visible: !win.railMode
                    text: "HISTORY"
                    color: theme.textLo
                    font.pixelSize: 10
                    font.letterSpacing: 1.1
                    Layout.topMargin: Kirigami.Units.smallSpacing
                }

                // + New chat
                Rectangle {
                    visible: !win.railMode
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: newChatMa.containsMouse ? theme.a(theme.green, 0.14) : theme.a(theme.textHi, 0.04)
                    border.width: 1; border.color: theme.a(theme.green, 0.30)
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                        Kirigami.Icon { source: "list-add"; Layout.preferredWidth: 13; Layout.preferredHeight: 13; color: theme.greenBright }
                        QQC2.Label { Layout.fillWidth: true; text: "New chat"; color: theme.textHi; font.pixelSize: 11; font.bold: true }
                    }
                    MouseArea { id: newChatMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.newChat() }
                }

                // The saved conversations scroll INSIDE the sidebar. As a bare
                // Repeater in the column they grew without limit, and a handful of
                // chats was enough to push the Memory Palace card off the bottom of
                // the window on a short screen -- reported as the card being cut off.
                // On the rail there is no history list to take the slack, so
                // something has to, or the nav spreads out again.
                Item { visible: win.railMode; Layout.fillHeight: true }

                QQC2.ScrollView {
                    visible: !win.railMode
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: parent.width
                        spacing: 3
                    // saved conversations (newest-first, from ~/.config/genesi-ai-monitor/sessions)
                    Repeater {
                        model: win.sessions
                        delegate: Rectangle {
                            id: histItem
                            required property var modelData
                            readonly property bool sel: chatPage.sessionId === modelData.id && win.currentTab === 1
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 8
                            color: sel ? theme.a(theme.green, 0.14)
                                 : ((histMa.containsMouse || delMa.containsMouse) ? theme.a(theme.textHi, 0.05) : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 7
                                Kirigami.Icon { source: Qt.resolvedUrl("icons/chat.svg"); isMask: true; Layout.preferredWidth: 13; Layout.preferredHeight: 13; color: histItem.sel ? theme.greenBright : theme.textLo }
                                QQC2.Label { Layout.fillWidth: true; text: histItem.modelData.title; color: histItem.sel ? theme.textHi : theme.textMid; font.pixelSize: 11; elide: Text.ElideRight }
                                QQC2.Label { text: win.relTime(histItem.modelData.updated); color: theme.textLo; font.pixelSize: 9 }
                            }
                            MouseArea { id: histMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openSession(histItem.modelData.id) }
                            // delete — revealed on hover; declared after histMa so it wins the click in its area
                            Rectangle {
                                visible: histMa.containsMouse || delMa.containsMouse
                                anchors.right: parent.right; anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                color: delMa.containsMouse ? theme.a(theme.red, 0.22) : theme.a(theme.textHi, 0.08)
                                Kirigami.Icon { anchors.centerIn: parent; source: "edit-delete"; width: 12; height: 12; color: delMa.containsMouse ? theme.red : theme.textLo }
                                MouseArea {
                                    id: delMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (chatPage.sessionId === histItem.modelData.id) chatPage.newChat()
                                        backend.deleteSession(histItem.modelData.id)
                                    }
                                    QQC2.ToolTip.text: "Delete chat"
                                    QQC2.ToolTip.visible: containsMouse
                                    QQC2.ToolTip.delay: 400
                                }
                            }
                        }
                    }

                    QQC2.Label {
                        visible: win.sessions.length === 0
                        Layout.fillWidth: true
                        text: "No chats yet — start one in AI Chat."
                        color: theme.textLo
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }

                    }
                }

                Rectangle {
                    // No room for it on the rail, and it is a settings card
                    // rather than navigation, so it is safe to drop.
                    visible: !win.railMode
                    Layout.fillWidth: true
                    implicitHeight: mpCol.implicitHeight + 24
                    radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: theme.a(theme.violet, 0.22) }
                        GradientStop { position: 1.0; color: theme.a(theme.green, 0.10) }
                    }
                    border.width: 1
                    border.color: theme.a(theme.violet, 0.32)
                    ColumnLayout {
                        id: mpCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        QQC2.Label { text: "Memory Palace"; color: theme.textHi; font.bold: true; font.pixelSize: 12 }

                        // "AI remembers everything" — opt-in recall (heavier: grows the
                        // prompt + needs Turbo). Off = chat runs exactly as before.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -1
                                QQC2.Label { text: "Remember everything"; color: theme.textHi; font.pixelSize: 11; font.bold: true }
                                QQC2.Label { Layout.fillWidth: true; text: win.recall ? "Recalling past chats" : "Off — lighter"; color: theme.textLo; font.pixelSize: 9; elide: Text.ElideRight }
                            }
                            Rectangle {
                                width: 40; height: 22; radius: 11
                                color: win.recall ? theme.violet : theme.a(theme.textHi, 0.16)
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Rectangle {
                                    width: 16; height: 16; radius: 8; y: 3
                                    x: win.recall ? 21 : 3
                                    color: theme.textHi
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.recall = (backend.setRecall(!win.recall) === "on")
                                    QQC2.ToolTip.text: "Injects your past conversations into the model so it remembers across chats. Heavier (grows the prompt) and needs Turbo — that's why it's off by default."
                                    QQC2.ToolTip.visible: containsMouse
                                    QQC2.ToolTip.delay: 300
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: inviteLbl.implicitWidth + 24
                            radius: 13
                            color: theme.textHi
                            QQC2.Label { id: inviteLbl; anchors.centerIn: parent; text: "New chat"; color: theme.bgBottom; font.bold: true; font.pixelSize: 10 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.newChat() }
                        }
                    }
                }
            }
        }

        // ──────────────────────── PAGES ────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 18
            color: theme.card
            border.width: 1
            border.color: theme.lineHi
            clip: true

        StackLayout {
            anchors.fill: parent
            currentIndex: win.currentTab

        // ───────────────────────── 1. PAINEL ─────────────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            background: Rectangle { color: theme.bgBottom }

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.largeSpacing

                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

                // ── HERO STATUS CARD ──
                GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 124
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    accent: theme.green
                    active: win.active
                    wash: true               // signature accent tint (system accent)
                    entranceDelay: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing + 2
                        spacing: Kirigami.Units.largeSpacing

                        // glowing icon ring
                        Item {
                            width: 66; height: 66
                            Rectangle {
                                anchors.centerIn: parent
                                width: 66; height: 66; radius: 33
                                color: "transparent"
                                border.width: 2
                                border.color: win.active ? theme.green : theme.line
                                SequentialAnimation on opacity {
                                    running: win.active
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.35; to: 0.95; duration: 1200; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.95; to: 0.35; duration: 1200; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 48; height: 48; radius: 24
                                color: win.active ? theme.a(theme.green, 0.14) : "transparent"
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: Qt.resolvedUrl("icons/bot.svg"); isMask: true
                                    width: 30; height: 30
                                    color: win.active ? theme.greenBright : theme.textLo
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            QQC2.Label {
                                text: win.active
                                      ? (st.profile === "max" ? i18n.t("hero.onMax")
                                         : st.profile === "balanced" ? i18n.t("hero.onBalanced")
                                         : st.profile === "battery" ? i18n.t("hero.onBattery")
                                         : st.aggressive ? i18n.t("hero.onMax") : i18n.t("hero.onEconomy"))
                                      : i18n.t("hero.off")
                                font.family: theme.display
                                font.bold: true; font.pixelSize: 22; font.letterSpacing: 0.2
                                color: theme.textHi
                            }
                            QQC2.Label {
                                visible: win.active
                                opacity: 0.85
                                font.pixelSize: 12
                                color: win.activity === "active" ? theme.greenBright : theme.textMid
                                text: win.activity === "active" ? i18n.t("hero.generating")
                                      : win.activity === "warm" ? i18n.t("hero.warm")
                                      : i18n.t("hero.standby")
                            }
                            QQC2.Label {
                                opacity: 0.85
                                color: theme.textMid
                                text: {
                                    var h = win.hw()
                                    var parts = []
                                    if (h.cpu_vendor) parts.push(h.cpu_vendor + " " + (h.physical_cores || "?") + "c/" + (h.logical_cores || "?") + "t")
                                    if (h.ram_mb) parts.push(Math.round(h.ram_mb / 1024) + " GB RAM")
                                    if (h.chassis) parts.push(h.chassis + (h.virtualized ? " (VM)" : ""))
                                    return parts.join("   •   ")
                                }
                            }
                            RowLayout {
                                spacing: 7
                                Rectangle {
                                    width: 9; height: 9; radius: 4.5
                                    color: win.active ? theme.greenBright : theme.textLo
                                    SequentialAnimation on opacity {
                                        running: win.active
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.3; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                    }
                                }
                                QQC2.Label {
                                    color: theme.textMid
                                    text: win.active ? i18n.t("hero.optReal") : i18n.t("hero.noTweaks")
                                }
                            }
                        }

                        // ON/OFF pill
                        Rectangle {
                            width: 66; height: 32; radius: 16
                            color: win.active ? theme.a(theme.green, 0.18) : "transparent"
                            border.color: win.active ? theme.green : theme.line
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 200 } }
                            QQC2.Label {
                                anchors.centerIn: parent
                                text: win.active ? "ON" : "OFF"
                                font.bold: true; font.pixelSize: 13
                                color: win.active ? theme.greenBright : theme.textLo
                            }
                        }
                    }
                }

                // ── TURBO CARD ──
                GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.turboStatusText.length > 0 ? 116 : 100
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    accent: theme.turbo
                    active: win.turboRequested
                    entranceDelay: 70

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing + 2
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            width: 50; height: 50; radius: 14
                            color: theme.a(theme.turbo, 0.14)
                            border.color: theme.a(theme.turbo, 0.55); border.width: 1
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl("icons/bolt.svg"); isMask: true
                                width: 24; height: 24
                                color: theme.turboBright
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                QQC2.Label { text: i18n.t("turbo.title"); font.bold: true; font.pixelSize: 16; color: theme.textHi }
                                // Speculative on/off toggle. Turbo runs plain full
                                // GPU offload by default (reliable); speculative is
                                // opt-in — faster on a mature GPU driver, can
                                // regress on Vulkan/NVK. Click to switch.
                                Rectangle {
                                    radius: 6; height: 20
                                    width: specLbl.implicitWidth + 16
                                    color: win.turboSpec ? theme.a(theme.turbo, 0.30)
                                                         : theme.a(theme.textHi, 0.10)
                                    border.width: 1
                                    border.color: win.turboSpec ? theme.a(theme.turbo, 0.6) : theme.line
                                    QQC2.Label {
                                        id: specLbl
                                        anchors.centerIn: parent
                                        text: win.turboSpec ? i18n.t("turbo.speculative") : i18n.t("turbo.fullOffload")
                                        font.pixelSize: 10
                                        color: win.turboSpec ? theme.turboBright : theme.textMid
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.turboSpec = !win.turboSpec
                                        QQC2.ToolTip.text: win.turboSpec
                                            ? "Advanced mode ON: speculative decoding (draft model) + dynamic draft length + persistent KV cache on disk. Faster on a mature GPU driver (CUDA); can regress on Vulkan/NVK. Click to go back to full offload (stable)."
                                            : "Full offload (stable). Click to enable advanced mode: ⚡ speculative decoding + dynamic draft + persistent KV — validate with the benchmark first (can regress on Vulkan/NVK)."
                                        QQC2.ToolTip.visible: containsMouse
                                    }
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: win.turboSpec ? i18n.t("turbo.descSpec") : i18n.t("turbo.descFull")
                                color: win.turboSpec ? theme.turboBright : theme.textMid
                                opacity: 0.9
                                font.pixelSize: 12
                            }
                            QQC2.Label {
                                visible: win.turboStatusText.length > 0
                                Layout.fillWidth: true
                                text: win.turboStatusText
                                color: theme.turboBright
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        // Right-hand controls: backend picker stacked on top of the
                        // on/off toggle, both flush to the card's right edge.
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                            spacing: Kirigami.Units.smallSpacing

                            // Always available: when a backend is missing it installs one;
                            // when one is present it lets you SWITCH between Vulkan and CUDA
                            // (the dialog shows which is active + recommends per hardware).
                            // Custom rounded pill (the flat Fusion QQC2.Button looked out of place).
                            Rectangle {
                                id: backendBtn
                                Layout.alignment: Qt.AlignRight
                                implicitHeight: 30
                                implicitWidth: backendRow.implicitWidth + 24
                                radius: 9
                                color: backendMa.containsMouse ? theme.cardHi : theme.a(theme.textHi, 0.06)
                                border.width: 1; border.color: theme.line
                                Behavior on color { ColorAnimation { duration: 140 } }
                                RowLayout {
                                    id: backendRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Kirigami.Icon { source: "download"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: theme.textMid }
                                    QQC2.Label {
                                        text: win.turboNeedsInstall ? i18n.t("turbo.installBackend") : i18n.t("turbo.backend")
                                        color: theme.textHi; font.pixelSize: 12
                                    }
                                    Kirigami.Icon { source: "go-down"; Layout.preferredWidth: 12; Layout.preferredHeight: 12; color: theme.textLo }
                                }
                                MouseArea {
                                    id: backendMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { backend.backendInfo(); backendDialog.open() }
                                }
                            }

                            // custom toggle
                            Rectangle {
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 30
                                implicitWidth: 54; implicitHeight: 30
                                radius: 15
                                color: win.turboRequested ? theme.turbo : theme.a(theme.textHi, 0.13)
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Rectangle {
                                    width: 24; height: 24; radius: 12; y: 3
                                    x: win.turboRequested ? parent.width - 27 : 3
                                    color: "#FFFFFF"
                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (win.turboRequested) {
                                            // turning Turbo OFF — release the lock so the
                                            // next start asks again / re-seeds from live.
                                            win.turboRequested = false
                                            win.turboModelLocked = false
                                        } else {
                                            // turning Turbo ON — ask which model first.
                                            backend.loadModels()
                                            turboModelDialog.openPicker()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── METRICS ROW ──
                //
                // A GridLayout, not a Row: three 128px-tall cards side by side
                // stop being readable long before the window stops shrinking --
                // the gauge and its number end up sharing about ninety pixels.
                // Two columns first, then one.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    columns: win.width < 820 ? 1 : (win.width < 1180 ? 2 : 3)
                    rowSpacing: Kirigami.Units.largeSpacing
                    columnSpacing: Kirigami.Units.largeSpacing

                    // CPU
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 128
                        entranceDelay: 140
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: theme.a(theme.green, 0.16)
                                    Kirigami.Icon { anchors.centerIn: parent; source: "cpu"; width: 15; height: 15; color: theme.greenBright }
                                }
                                QQC2.Label { text: i18n.t("card.cpu"); font.bold: true; font.pixelSize: theme.fsSmall; font.letterSpacing: 0.3; color: theme.textMid }
                                Item { Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                GaugeArc {
                                    value: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent / 100.0 : 0
                                    stroke: theme.green
                                    big: win.metrics().cpu_percent !== undefined ? Math.round(win.metrics().cpu_percent) + "" : "—"
                                    small: win.metrics().cpu_percent !== undefined ? "%" : ""
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label { text: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent.toFixed(1) + "%" : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                    QQC2.Label { text: (win.hw().physical_cores || "?") + " " + i18n.t("u.cores") + " · " + (win.hw().logical_cores || "?") + " " + i18n.t("u.threads"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    // MEMORY
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 128
                        entranceDelay: 175
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: theme.a(theme.blue, 0.16)
                                    Kirigami.Icon { anchors.centerIn: parent; source: "media-flash"; width: 15; height: 15; color: theme.blue }
                                }
                                QQC2.Label { text: i18n.t("card.memory"); font.bold: true; font.pixelSize: theme.fsSmall; font.letterSpacing: 0.3; color: theme.textMid }
                                Item { Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                GaugeArc {
                                    value: win.metrics().ram_total_mb ? (win.metrics().ram_used_mb || 0) / win.metrics().ram_total_mb : 0
                                    stroke: theme.blue
                                    big: win.metrics().ram_total_mb ? Math.round(((win.metrics().ram_used_mb || 0) / win.metrics().ram_total_mb) * 100) + "" : "—"
                                    small: win.metrics().ram_total_mb ? "%" : ""
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label { text: win.metrics().ram_total_mb ? (Math.round((win.metrics().ram_used_mb || 0) / 102.4) / 10).toFixed(1) + " / " + Math.round(win.metrics().ram_total_mb / 1024) + " GB" : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                    QQC2.Label { text: (win.metrics().ram_used_mb || 0) + " " + i18n.t("u.inUse"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    // INFERENCE
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 128
                        entranceDelay: 210
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: theme.a(theme.purple, 0.16)
                                    Kirigami.Icon { anchors.centerIn: parent; source: Qt.resolvedUrl("icons/rocket.svg"); isMask: true; width: 15; height: 15; color: theme.purpleBright }
                                }
                                QQC2.Label { text: i18n.t("card.inference"); font.bold: true; font.pixelSize: theme.fsSmall; font.letterSpacing: 0.3; color: theme.textMid }
                                Item { Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing
                                GaugeArc {
                                    value: win.activeModel ? 1 : 0
                                    stroke: theme.purple
                                    icon: win.activeModel ? "icons/rocket.svg" : ""
                                    big: win.activeModel ? "" : "—"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label { text: win.activeModel ? (st.tokens_per_second ? st.tokens_per_second + " t/s" : i18n.t("u.active")) : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                    QQC2.Label { text: win.activeModel ? win.activeModel : i18n.t("u.noModel"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                // ── APPLIED OPTIMIZATIONS ──
                GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    entranceDelay: 260
                    implicitHeight: optLayout.implicitHeight + (Kirigami.Units.largeSpacing + 8) * 2
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        id: optLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing + 8
                        spacing: Kirigami.Units.smallSpacing + 2

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing + 2
                            Rectangle {
                                width: 30; height: 30; radius: 9
                                color: theme.a(theme.green, 0.16)
                                Kirigami.Icon { anchors.centerIn: parent; source: "configure"; width: 17; height: 17; color: theme.greenBright }
                            }
                            QQC2.Label {
                                text: win.active ? i18n.t("opt.applied") : i18n.t("opt.inactive")
                                font.bold: true; font.pixelSize: 15; color: theme.textHi
                            }
                        }

                        QQC2.Label {
                            visible: !win.active
                            color: theme.textLo
                            text: i18n.t("opt.hint")
                        }

                        Repeater {
                            model: st.applied || []
                            delegate: RowLayout {
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon { source: "dialog-ok-apply"; color: theme.green; Layout.preferredWidth: 15; Layout.preferredHeight: 15; Layout.alignment: Qt.AlignTop }
                                QQC2.Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData; color: theme.textMid }
                            }
                        }
                    }
                }

                // ── BENCHMARK CARD ──
                GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    entranceDelay: 320
                    implicitHeight: benchLayout.implicitHeight + (Kirigami.Units.largeSpacing + 8) * 2
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    accent: theme.purple

                    ColumnLayout {
                        id: benchLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing + 8
                        spacing: Kirigami.Units.smallSpacing + 2

                        // header: title + description on the LEFT, Run button on the RIGHT
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing + 2
                                    Rectangle {
                                        width: 30; height: 30; radius: 9
                                        color: theme.a(theme.purple, 0.16)
                                        Kirigami.Icon { anchors.centerIn: parent; source: "speedometer"; width: 17; height: 17; color: theme.purpleBright }
                                    }
                                    QQC2.Label {
                                        text: i18n.t("bench.title")
                                        font.bold: true; font.pixelSize: 15; color: theme.textHi
                                    }
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: theme.textLo
                                    font.pixelSize: 12
                                    text: i18n.t("bench.descPre")
                                        + (win.turboModel || win.activeModel || win.firstInstalledModel || "llama3.2")
                                        + i18n.t("bench.descPost")
                                }
                            }

                            // Run benchmark — signature purple gradient pill (Memory Palace vibe)
                            Rectangle {
                                id: benchBtn
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: 42
                                implicitWidth: benchBtnRow.implicitWidth + 34
                                radius: 12
                                opacity: win.benchRunning ? 0.6 : (benchBtnMa.containsMouse ? 1.0 : 0.94)
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: theme.violet }
                                    GradientStop { position: 1.0; color: theme.purple }
                                }
                                RowLayout {
                                    id: benchBtnRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    QQC2.BusyIndicator {
                                        running: win.benchRunning; visible: win.benchRunning
                                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                    }
                                    Kirigami.Icon { visible: !win.benchRunning; source: "speedometer"; Layout.preferredWidth: 16; Layout.preferredHeight: 16; color: "#FFFFFF" }
                                    QQC2.Label {
                                        text: win.benchRunning ? i18n.t("bench.measuring") : i18n.t("bench.run")
                                        color: "#FFFFFF"; font.bold: true; font.pixelSize: 13
                                    }
                                }
                                MouseArea {
                                    id: benchBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !win.benchRunning
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: backend.runBench(win.turboModel || win.activeModel || win.firstInstalledModel || "llama3.2")
                                }
                            }
                        }

                        // live progress
                        RowLayout {
                            visible: win.benchRunning && win.benchProgress.length > 0
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon { source: "view-refresh"; color: theme.blue; Layout.preferredWidth: 14; Layout.preferredHeight: 14 }
                            QQC2.Label { Layout.fillWidth: true; text: win.benchProgress; color: theme.textMid; elide: Text.ElideRight }
                        }

                        // error
                        QQC2.Label {
                            visible: win.benchError.length > 0 && !win.benchRunning
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: win.benchError
                            color: theme.red
                            font.pixelSize: 12
                        }

                        // result graph: two horizontal bars OFF vs ON
                        ColumnLayout {
                            id: benchGraph
                            visible: win.benchHasResult && !win.benchRunning
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing
                            readonly property real maxRate: Math.max(win.benchOff, win.benchOn, 0.01)

                            Repeater {
                                model: [
                                    { "label": "OFF", "rate": win.benchOff, "col": theme.textLo },
                                    { "label": "ON",  "rate": win.benchOn,  "col": theme.green }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Label {
                                        text: modelData.label
                                        font.bold: true; font.pixelSize: 12
                                        color: theme.textMid
                                        Layout.preferredWidth: 34
                                    }
                                    Rectangle {              // track
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 22
                                        radius: 6
                                        color: theme.a(theme.textHi, 0.06)
                                        Rectangle {          // bar
                                            height: parent.height
                                            radius: 6
                                            width: Math.max(parent.width * (modelData.rate / benchGraph.maxRate || 0), 2)
                                            color: modelData.col
                                            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    QQC2.Label {
                                        text: modelData.rate.toFixed(1) + " t/s"
                                        font.bold: true; font.pixelSize: 12
                                        color: theme.textHi
                                        Layout.preferredWidth: 72
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: (win.benchDelta >= 0 ? "▲ +" : "▼ ") + win.benchDelta.toFixed(1)
                                    + i18n.t("bench.gain")
                                    + (Math.abs(win.benchDelta) < 1 ? i18n.t("bench.vmNote") : "")
                                color: win.benchDelta >= 1 ? theme.greenBright
                                     : (win.benchDelta <= -1 ? theme.red : theme.textMid)
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ───────────────────────── 2. CHAT ─────────────────────────
        // onNavigate: the chat's hero pills reach the rest of the app, but
        // the page does not own the tab -- the shell does.
        ChatPage { id: chatPage; i18n: i18n
            onNavigate: function (tab) { win.currentTab = tab } }

        // ───────────────────────── 3. MODELOS ─────────────────────────
        AdvisorPage {
            id: advisorPage
            i18n: i18n
            activeGguf: win.turboGguf
            // Picking a local GGUF hands the file straight to Turbo. It MUST run
            // through Turbo: llama-server loads a .gguf path directly (reading the
            // architecture and chat template from the header), while Ollama's chat
            // API only knows models in its own registry — so we switch Turbo on
            // rather than letting the pick silently do nothing.
            onUseGguf: function (path, label) {
                win.turboGguf = path
                win.turboModelLocked = true      // don't let polling overwrite it
                win.turboModel = path
                win.turboRequested = true
            }
        }

        // ───────────────────────── 4. AUTOMAÇÕES ─────────────────────────
        AutomationsPage { id: automationsPage }

        // ───────────────────────── 5. MESH ─────────────────────────
        MeshPage { id: meshPage; i18n: i18n }
        }
        }

        Rectangle {
            Layout.fillHeight: true
            visible: win.wide
            Layout.preferredWidth: win.wide ? 250 : 0
            radius: 18
            color: theme.card
            border.width: 1
            border.color: theme.lineHi

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                visible: false

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    QQC2.Label { text: "AI Module"; color: theme.textHi; font.bold: true; font.pixelSize: 14 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 8
                        color: theme.a(theme.red, 0.16)
                        border.width: 1
                        border.color: theme.a(theme.red, 0.35)
                        RowLayout {
                            id: modelBadge
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6
                            Kirigami.Icon { source: Qt.resolvedUrl("icons/bolt.svg"); isMask: true; Layout.preferredWidth: 13; Layout.preferredHeight: 13; color: theme.red }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: win.turboRequested ? "Turbo" : (win.activeModel ? win.activeModel : "Local AI")
                                color: win.turboRequested ? theme.turboBright : theme.textHi
                                font.bold: true
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Kirigami.Icon { source: "go-down"; Layout.preferredWidth: 12; Layout.preferredHeight: 12; color: theme.textLo }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.currentTab = 2 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        color: theme.a(theme.textHi, 0.07)
                        radius: 9
                        QQC2.Label { anchors.centerIn: parent; text: "TOOLS"; color: theme.textHi; font.bold: true; font.pixelSize: 11 }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        color: "transparent"
                        QQC2.Label { anchors.centerIn: parent; text: "MODELS"; color: theme.textLo; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.currentTab = 2 }
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: "Command AI turns local models into system actions, benchmarks and hardware tuning."
                    wrapMode: Text.WordWrap
                    color: theme.textLo
                    font.pixelSize: 11
                }

                QQC2.Label { text: "Your Projects"; color: theme.textHi; font.bold: true; font.pixelSize: 13 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [
                            { "name": "Monitor Dashboard", "tab": 0, "icon": "icons/nav-dashboard.svg" },
                            { "name": "AI Chat", "tab": 1, "icon": "icons/nav-chat.svg" },
                            { "name": "Model Advisor", "tab": 2, "icon": "icons/nav-models.svg" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: win.currentTab === modelData.tab
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 9
                            color: sel ? theme.a(theme.green, 0.14) : (projMa.containsMouse ? theme.a(theme.textHi, 0.05) : "transparent")
                            border.width: sel ? 1 : 0
                            border.color: theme.a(theme.green, 0.34)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 8
                                Kirigami.Icon { source: Qt.resolvedUrl(modelData.icon); isMask: true; Layout.preferredWidth: 15; Layout.preferredHeight: 15; color: sel ? theme.greenBright : theme.textLo }
                                QQC2.Label { text: modelData.name; color: sel ? theme.textHi : theme.textMid; font.bold: sel; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            MouseArea { id: projMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.currentTab = modelData.tab }
                        }
                    }
                }

                QQC2.Label { text: "Integrate Apps"; color: theme.textLo; font.pixelSize: 10; Layout.topMargin: Kirigami.Units.smallSpacing }

                Repeater {
                    model: [
                        { "name": "Ollama", "sub": win.firstInstalledModel ? "Models available" : "Install a model first", "on": win.firstInstalledModel.length > 0 },
                        { "name": "Turbo", "sub": win.turboRequested ? "Serving " + win.turboModel : "GPU backend ready", "on": win.turboRequested },
                        { "name": "Advisor", "sub": "Hardware-aware picks", "on": true }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -1
                            QQC2.Label { text: modelData.name; color: theme.textHi; font.pixelSize: 11; font.bold: true }
                            QQC2.Label { text: modelData.sub; color: theme.textLo; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Rectangle {
                            width: 24; height: 14; radius: 7
                            color: modelData.on ? theme.a(theme.green, 0.50) : theme.a(theme.textHi, 0.12)
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                y: 2
                                x: modelData.on ? 12 : 2
                                color: modelData.on ? theme.greenBright : theme.textLo
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 12
                    color: win.active ? theme.a(theme.green, 0.14) : theme.a(theme.textHi, 0.05)
                    border.width: 1
                    border.color: win.active ? theme.a(theme.green, 0.40) : theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: win.active ? theme.greenBright : theme.textLo }
                        QQC2.Label { text: win.active ? "AI Mode online" : "AI Mode idle"; color: theme.textHi; font.bold: true; font.pixelSize: 11; Layout.fillWidth: true }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    QQC2.Label {
                        text: "AI Module"
                        color: theme.textHi
                        font.bold: true
                        font.pixelSize: 15
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: "Quick controls for the local inference stack."
                        color: theme.textLo
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 88
                    radius: 16
                    color: theme.a(theme.green, win.active ? 0.22 : 0.12)
                    border.width: 1
                    border.color: win.active ? theme.a(theme.greenBright, 0.78) : theme.a(theme.green, 0.34)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                width: 28; height: 28; radius: 9
                                color: theme.a(theme.greenBright, win.active ? 0.28 : 0.16)
                                Kirigami.Icon { anchors.centerIn: parent; source: Qt.resolvedUrl("icons/bot.svg"); isMask: true; width: 16; height: 16; color: win.active ? theme.greenBright : theme.textLo }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -1
                                QQC2.Label { text: "AI Mode"; color: theme.textHi; font.bold: true; font.pixelSize: 12 }
                                QQC2.Label {
                                    text: win.forceMode === "auto" ? "Auto: " + (win.active ? "active now" : "standing by")
                                         : win.forceMode === "on" ? "Forced ON" : "Forced OFF"
                                    color: theme.textLo
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            Rectangle {
                                id: aiModeSwitch
                                readonly property bool switchOn: win.forceMode === "auto" ? win.active : win.forceMode === "on"
                                width: 42; height: 24; radius: 12
                                color: switchOn ? theme.green : theme.a(theme.textHi, 0.16)
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    y: 3
                                    x: aiModeSwitch.switchOn ? 21 : 3
                                    color: theme.textHi
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.setMode(aiModeSwitch.switchOn ? "off" : "on")
                                }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: "Use Auto in the top bar when you want Genesi to decide."
                            color: theme.textLo
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 84
                    radius: 16
                    color: theme.a(theme.turbo, win.turboRequested ? 0.24 : 0.12)
                    border.width: 1
                    border.color: win.turboRequested ? theme.a(theme.turboBright, 0.80) : theme.a(theme.turbo, 0.34)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                width: 28; height: 28; radius: 9
                                color: theme.a(theme.turboBright, 0.24)
                                Kirigami.Icon { anchors.centerIn: parent; source: Qt.resolvedUrl("icons/bolt.svg"); isMask: true; width: 16; height: 16; color: theme.turboBright }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -1
                                QQC2.Label { text: "Turbo"; color: theme.textHi; font.bold: true; font.pixelSize: 12 }
                                QQC2.Label {
                                    text: win.turboRequested ? (win.turboModel || "Serving selected model") : "Pick a model before starting"
                                    color: theme.textLo
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            Rectangle {
                                id: turboSwitch
                                width: 42; height: 24; radius: 12
                                color: win.turboRequested ? theme.turbo : theme.a(theme.textHi, 0.16)
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    y: 3
                                    x: win.turboRequested ? 21 : 3
                                    color: theme.textHi
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (win.turboRequested) {
                                            win.turboRequested = false
                                            win.turboModelLocked = false
                                        } else {
                                            backend.loadModels()
                                            turboModelDialog.openPicker()
                                        }
                                    }
                                }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: win.turboStatusText.length > 0 ? win.turboStatusText : "Full GPU offload for local chat."
                            color: win.turboRequested ? theme.turboBright : theme.textLo
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 78
                    radius: 16
                    color: theme.a(theme.purple, win.turboSpec ? 0.22 : 0.11)
                    border.width: 1
                    border.color: win.turboSpec ? theme.a(theme.purpleBright, 0.80) : theme.a(theme.purple, 0.34)
                    opacity: win.turboRequested ? 0.58 : 1.0
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                width: 28; height: 28; radius: 9
                                color: theme.a(theme.purpleBright, 0.24)
                                Kirigami.Icon { anchors.centerIn: parent; source: "media-playback-start"; width: 15; height: 15; color: theme.purpleBright }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -1
                                QQC2.Label { text: "Speculative"; color: theme.textHi; font.bold: true; font.pixelSize: 12 }
                                QQC2.Label {
                                    text: win.turboRequested ? "Locked while Turbo is running" : (win.turboSpec ? "Enabled for next Turbo start" : "Disabled for next Turbo start")
                                    color: theme.textLo
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            Rectangle {
                                id: specSwitch
                                width: 42; height: 24; radius: 12
                                color: win.turboSpec ? theme.purple : theme.a(theme.textHi, 0.16)
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    y: 3
                                    x: win.turboSpec ? 21 : 3
                                    color: theme.textHi
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !win.turboRequested
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                    onClicked: win.turboSpec = !win.turboSpec
                                }
                            }
                        }
                    }
                }

                QQC2.Label {
                    text: "Workspace shortcuts"
                    color: theme.textLo
                    font.pixelSize: 10
                    font.letterSpacing: 1.1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [
                            { "name": "Dashboard", "tab": 0, "icon": "icons/nav-dashboard.svg" },
                            { "name": "AI Chat", "tab": 1, "icon": "icons/nav-chat.svg" },
                            { "name": "Models", "tab": 2, "icon": "icons/nav-models.svg" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: win.currentTab === modelData.tab
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: 10
                            color: sel ? theme.a(theme.green, 0.14) : (shortcutMa.containsMouse ? theme.a(theme.textHi, 0.055) : theme.a(theme.textHi, 0.025))
                            border.width: 1
                            border.color: sel ? theme.a(theme.green, 0.38) : theme.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                Kirigami.Icon { source: Qt.resolvedUrl(modelData.icon); isMask: true; Layout.preferredWidth: 15; Layout.preferredHeight: 15; color: sel ? theme.greenBright : theme.textLo }
                                QQC2.Label { text: modelData.name; color: sel ? theme.textHi : theme.textMid; font.bold: sel; font.pixelSize: 11; Layout.fillWidth: true }
                            }
                            MouseArea { id: shortcutMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.currentTab = modelData.tab }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 14
                    color: theme.a(win.active ? theme.green : theme.textHi, win.active ? 0.13 : 0.045)
                    border.width: 1
                    border.color: win.active ? theme.a(theme.green, 0.34) : theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: win.active ? theme.greenBright : theme.textLo }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -2
                            QQC2.Label { text: win.active ? "AI Mode online" : "AI Mode idle"; color: theme.textHi; font.bold: true; font.pixelSize: 11 }
                            QQC2.Label { text: (win.profileMode.charAt(0).toUpperCase() + win.profileMode.slice(1)) + " profile"; color: theme.textLo; font.pixelSize: 9 }
                        }
                        // mini activity sparkline (shader-free bar strip) — mockup accent
                        Row {
                            id: statusSpark
                            height: 16
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: [6, 10, 7, 13, 9, 15, 8, 11]
                                delegate: Rectangle {
                                    required property int modelData
                                    width: 3; radius: 1.5
                                    height: modelData
                                    y: statusSpark.height - height
                                    color: win.active ? theme.greenBright : theme.a(theme.textHi, 0.28)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════════ BACKEND CHOICE DIALOG (Vulkan ⇄ CUDA) ════════════
    Kirigami.PromptDialog {
        id: backendDialog
        title: i18n.t("dlg.backendTitle")
        standardButtons: Kirigami.Dialog.Cancel
        preferredWidth: Kirigami.Units.gridUnit * 28

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: win.backendReason || i18n.t("dlg.backendIntro")
                color: theme.textMid
            }

            // ── Vulkan ──
            Rectangle {
                Layout.fillWidth: true
                radius: 10
                implicitHeight: vkCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                color: vkMa.containsMouse ? theme.a(theme.green, 0.10) : theme.a(theme.textHi, 0.04)
                border.width: 1
                border.color: win.backendRecommend === "vulkan" ? theme.a(theme.green, 0.6) : theme.line
                ColumnLayout {
                    id: vkCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: Kirigami.Units.largeSpacing
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Vulkan"; font.bold: true; font.pixelSize: 15; color: theme.textHi }
                        Rectangle {
                            visible: win.backendRecommend === "vulkan"
                            radius: 6; height: 18; width: recVk.implicitWidth + 14
                            color: theme.a(theme.green, 0.25)
                            QQC2.Label { id: recVk; anchors.centerIn: parent; text: i18n.t("dlg.recommended"); font.pixelSize: 10; color: theme.greenBright }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.textMid; font.pixelSize: 12
                        text: i18n.t("dlg.vulkanDesc")
                    }
                }
                MouseArea {
                    id: vkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { backend.installTurboBackend("vulkan"); backendDialog.close() }
                }
            }

            // ── CUDA ──
            Rectangle {
                Layout.fillWidth: true
                radius: 10
                implicitHeight: cuCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                color: cuMa.containsMouse ? theme.a(theme.turbo, 0.10) : theme.a(theme.textHi, 0.04)
                border.width: 1
                border.color: win.backendRecommend === "cuda" ? theme.a(theme.turbo, 0.6) : theme.line
                ColumnLayout {
                    id: cuCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: Kirigami.Units.largeSpacing
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "CUDA"; font.bold: true; font.pixelSize: 15; color: theme.textHi }
                        Rectangle {
                            visible: win.backendRecommend === "cuda"
                            radius: 6; height: 18; width: recCu.implicitWidth + 14
                            color: theme.a(theme.turbo, 0.25)
                            QQC2.Label { id: recCu; anchors.centerIn: parent; text: i18n.t("dlg.recommended"); font.pixelSize: 10; color: theme.turboBright }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.textMid; font.pixelSize: 12
                        text: i18n.t("dlg.cudaDesc")
                    }
                    QQC2.Label {
                        visible: win.backendRecommend === "cuda" && !win.backendNvWorks
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11; color: theme.red
                        text: i18n.t("dlg.cudaWarn")
                    }
                    QQC2.Label {
                        visible: !win.backendAur
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 11; color: theme.textLo
                        text: i18n.t("dlg.aurNeed")
                    }
                }
                MouseArea {
                    id: cuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { backend.installTurboBackend("cuda"); backendDialog.close() }
                }
            }
        }
    }

    // ════════════ TURBO MODEL PICKER ════════════
    // Asked every time Turbo is switched on, so Turbo always runs the model the
    // user chose — never one auto-grabbed from whatever Ollama happened to load.
    Kirigami.PromptDialog {
        id: turboModelDialog
        title: i18n.t("dlg.turboTitle")
        standardButtons: Kirigami.Dialog.Cancel
        preferredWidth: Kirigami.Units.gridUnit * 26

        property string selected: ""

        function openPicker() {
            // Default to the GPU-fit recommendation, then the current pick, the
            // live/active model, and finally the first installed one.
            selected = win.turboRecommend || win.turboModel || win.activeModel
                       || win.firstInstalledModel
                       || (win.installedModels.length > 0 ? win.installedModels[0] : "")
            open()
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: theme.textMid
                font.pixelSize: 12
                text: win.installedModels.length > 0
                    ? i18n.t("dlg.turboPick")
                    : i18n.t("dlg.turboNone")
            }

            Repeater {
                model: win.installedModels
                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    implicitHeight: rowM.implicitHeight + Kirigami.Units.largeSpacing
                    color: maM.containsMouse || turboModelDialog.selected === modelData
                           ? theme.a(theme.turbo, 0.12) : theme.a(theme.textHi, 0.04)
                    border.width: 1
                    border.color: turboModelDialog.selected === modelData
                                  ? theme.a(theme.turbo, 0.6) : theme.line
                    RowLayout {
                        id: rowM
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Label {
                            // modelData is the raw reference (Ollama tag or
                            // `gguf:<stem>`); show the friendly name instead.
                            text: (turboModelDialog.selected === modelData ? "✓ " : "")
                                  + backend.modelLabel(modelData)
                            color: turboModelDialog.selected === modelData ? theme.turboBright : theme.textHi
                            font.bold: turboModelDialog.selected === modelData
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            visible: modelData === win.turboRecommend
                            radius: 6; height: 18; width: recPk.implicitWidth + 14
                            color: theme.a(theme.turbo, 0.25)
                            QQC2.Label {
                                id: recPk; anchors.centerIn: parent
                                text: i18n.t("dlg.fitsGpu"); font.pixelSize: 10; color: theme.turboBright
                            }
                        }
                    }
                    MouseArea {
                        id: maM; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: turboModelDialog.selected = modelData
                    }
                }
            }

            QQC2.Button {
                Layout.fillWidth: true
                text: i18n.t("dlg.startTurbo")
                enabled: turboModelDialog.selected.length > 0
                onClicked: {
                    win.turboModel = turboModelDialog.selected
                    win.turboModelLocked = true
                    win.turboRequested = true
                    turboModelDialog.close()
                }
            }
        }
    }
}
