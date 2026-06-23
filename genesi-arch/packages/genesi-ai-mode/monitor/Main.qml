import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi AI Mode Monitor"
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 37
    minimumWidth: Kirigami.Units.gridUnit * 38
    minimumHeight: Kirigami.Units.gridUnit * 30
    color: theme.bgBottom

    Theme { id: theme }
    I18n { id: i18n }

    property var st: ({})
    property bool active: false
    property string forceMode: "auto"
    property string profileMode: "auto"
    property string activity: "idle"   // active | warm | idle (smart auto-detect)
    property int currentTab: 0

    // ── Turbo integration ───────────────────────────────────────────────────
    // activeModel = the model Ollama currently has LOADED (live, from /api/ps).
    // It drives the dashboard "AI ativa" card and FLICKERS as Ollama loads/evicts
    // models (keep-alive) or returns an empty /api/ps between cycles — so it must
    // NOT directly control the Turbo server's lifecycle.
    property string activeModel: (st.ollama && st.ollama.length > 0) ? st.ollama[0].name : ""
    property bool turboRequested: false
    property bool turboSpec: false        // use speculative decoding for Turbo?
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

    onActiveModelChanged: if (activeModel && !turboModelLocked) turboModel = activeModel
    onFirstInstalledModelChanged: if (!turboModel && firstInstalledModel && !turboModelLocked) turboModel = firstInstalledModel

    // Changing the model only (re)starts Turbo — it never stops it. Only the user
    // flipping the switch off (turboRequested=false) stops the Turbo server.
    onTurboModelChanged: {
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
    }
    onTurboRequestedChanged: {
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
        else if (!turboRequested) backend.setTurbo(false, "", false)
    }
    // Flipping speculative on/off while Turbo runs restarts it in the new mode.
    onTurboSpecChanged: {
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel, turboSpec)
    }

    Component.onCompleted: { backend.loadModels(); backend.recommendTurboModel() }

    Connections {
        target: backend
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
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.poll() }

    globalDrawer: null

    // ════════════════════════ HEADER ════════════════════════
    header: QQC2.ToolBar {
        background: Rectangle {
            color: theme.bgTop
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }
        }
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Item { width: Kirigami.Units.smallSpacing }

            // ── Brand mark ──
            Rectangle {
                width: 34; height: 34; radius: 10
                gradient: Gradient {
                    GradientStop { position: 0.0; color: theme.greenBright }
                    GradientStop { position: 1.0; color: theme.greenDeep }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "cpu"; width: 19; height: 19; color: "#08130E"
                }
            }
            ColumnLayout {
                spacing: -2
                QQC2.Label { text: "AI Mode"; font.bold: true; font.pixelSize: 15; color: theme.textHi }
                QQC2.Label { text: "GENESI"; font.pixelSize: 9; font.letterSpacing: 2; color: theme.green }
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
            Rectangle {
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
        anchors.fill: parent
        spacing: 0

        // ──────────────────────── SIDEBAR (nav) ────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 60
            color: theme.bgTop
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.line }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Kirigami.Units.largeSpacing
                anchors.bottomMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: [
                        { "icon": "view-list-icons", "key": "nav.dashboard" },
                        { "icon": "mail-message",    "key": "nav.chat" },
                        { "icon": "server-database", "key": "nav.models" }
                    ]
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property bool sel: win.currentTab === index
                        Layout.alignment: Qt.AlignHCenter
                        width: 40; height: 40; radius: 12
                        color: sel ? theme.a(theme.green, 0.16)
                             : (navMa.containsMouse ? theme.a(theme.textHi, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: modelData.icon
                            width: 22; height: 22
                            color: sel ? theme.greenBright : theme.textMid
                        }
                        MouseArea {
                            id: navMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.currentTab = index
                            QQC2.ToolTip.text: i18n.t(modelData.key)
                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 400
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ──────────────────────── PAGES ────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: win.currentTab

        // ───────────────────────── 1. PAINEL ─────────────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            background: Rectangle {
                gradient: Gradient {
                    GradientStop { position: 0.0; color: theme.bgTop }
                    GradientStop { position: 1.0; color: theme.bgBottom }
                }
            }

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
                                    source: "cpu"; width: 28; height: 28
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
                                font.bold: true; font.pixelSize: 21
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
                    Layout.preferredHeight: (win.turboStatusText.length > 0 ? 116 : 100)
                                            + (win.turboRecommend.length > 0 ? 22 : 0)
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    accent: theme.turbo
                    active: win.turboRequested

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
                                source: "lightning"; width: 26; height: 26
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
                                QQC2.Button {
                                    // Always available: when a backend is missing it installs one;
                                    // when one is present it lets you SWITCH between Vulkan and CUDA
                                    // (the dialog shows which is active + recommends per hardware).
                                    text: win.turboNeedsInstall ? i18n.t("turbo.installBackend") : i18n.t("turbo.backend")
                                    icon.name: "download"
                                    onClicked: { backend.backendInfo(); backendDialog.open() }
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
                            // Advisor → Turbo model pick: biggest model that fits 100% in VRAM.
                            RowLayout {
                                visible: win.turboRecommend.length > 0
                                spacing: Kirigami.Units.smallSpacing
                                QQC2.Label {
                                    text: i18n.t("turbo.recommendedGpu")
                                    color: theme.textLo; font.pixelSize: 11
                                }
                                Rectangle {
                                    radius: 6; height: 20
                                    width: recLbl.implicitWidth + 16
                                    color: win.turboModel === win.turboRecommend
                                         ? theme.a(theme.green, 0.30) : theme.a(theme.textHi, 0.10)
                                    border.width: 1
                                    border.color: win.turboModel === win.turboRecommend
                                         ? theme.a(theme.green, 0.6) : theme.line
                                    QQC2.Label {
                                        id: recLbl
                                        anchors.centerIn: parent
                                        text: win.turboModel === win.turboRecommend
                                            ? "✓ " + win.turboRecommend : win.turboRecommend
                                        font.pixelSize: 10
                                        color: win.turboModel === win.turboRecommend
                                             ? theme.greenBright : theme.textMid
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { win.turboModel = win.turboRecommend; win.turboModelLocked = true }
                                        QQC2.ToolTip.text: i18n.t("tip.recVram")
                                        QQC2.ToolTip.visible: containsMouse
                                    }
                                }
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

                        // custom toggle
                        Rectangle {
                            width: 54; height: 30; radius: 15
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

                // ── METRICS ROW ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    // CPU
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 116
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            GaugeArc {
                                value: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent / 100.0 : 0
                                stroke: theme.green
                                big: win.metrics().cpu_percent !== undefined ? Math.round(win.metrics().cpu_percent) + "" : "—"
                                small: win.metrics().cpu_percent !== undefined ? "%" : ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: i18n.t("card.cpu"); font.bold: true; font.pixelSize: 11; font.letterSpacing: 1; color: theme.green }
                                QQC2.Label { text: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent.toFixed(1) + "%" : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                QQC2.Label { text: (win.hw().physical_cores || "?") + " " + i18n.t("u.cores") + " · " + (win.hw().logical_cores || "?") + " " + i18n.t("u.threads"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }

                    // MEMORY
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 116
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            GaugeArc {
                                value: win.metrics().ram_total_mb ? (win.metrics().ram_used_mb || 0) / win.metrics().ram_total_mb : 0
                                stroke: theme.blue
                                big: win.metrics().ram_total_mb ? Math.round(((win.metrics().ram_used_mb || 0) / win.metrics().ram_total_mb) * 100) + "" : "—"
                                small: win.metrics().ram_total_mb ? "%" : ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: i18n.t("card.memory"); font.bold: true; font.pixelSize: 11; font.letterSpacing: 1; color: theme.blue }
                                QQC2.Label { text: win.metrics().ram_total_mb ? (Math.round((win.metrics().ram_used_mb || 0) / 102.4) / 10).toFixed(1) + " / " + Math.round(win.metrics().ram_total_mb / 1024) + " GB" : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                QQC2.Label { text: (win.metrics().ram_used_mb || 0) + " " + i18n.t("u.inUse"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }

                    // INFERENCE
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 116
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            GaugeArc {
                                value: win.activeModel ? 1 : 0
                                stroke: theme.purple
                                icon: win.activeModel ? "icons/rocket.svg" : ""
                                big: win.activeModel ? "" : "—"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: i18n.t("card.inference"); font.bold: true; font.pixelSize: 11; font.letterSpacing: 1; color: theme.purpleBright }
                                QQC2.Label { text: win.activeModel ? (st.tokens_per_second ? st.tokens_per_second + " t/s" : i18n.t("u.active")) : "—"; font.bold: true; font.pixelSize: 18; color: theme.textHi }
                                QQC2.Label { text: win.activeModel ? win.activeModel : i18n.t("u.noModel"); color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ── APPLIED OPTIMIZATIONS ──
                GlassCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    implicitHeight: optLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        id: optLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon { source: "configure"; color: theme.green; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
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
                    implicitHeight: benchLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    accent: theme.blue

                    ColumnLayout {
                        id: benchLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon { source: "speedometer"; color: theme.blue; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                            QQC2.Label {
                                text: i18n.t("bench.title")
                                font.bold: true; font.pixelSize: 15; color: theme.textHi
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.BusyIndicator {
                                running: win.benchRunning
                                visible: win.benchRunning
                                Layout.preferredWidth: 22; Layout.preferredHeight: 22
                            }
                            QQC2.Button {
                                text: win.benchRunning ? i18n.t("bench.measuring") : i18n.t("bench.run")
                                icon.name: "speedometer"
                                enabled: !win.benchRunning
                                onClicked: backend.runBench(win.turboModel || win.activeModel || win.firstInstalledModel || "llama3.2")
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
        ChatPage { id: chatPage; i18n: i18n }

        // ───────────────────────── 3. MODELOS ─────────────────────────
        AdvisorPage { id: advisorPage; i18n: i18n }
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
                            text: (turboModelDialog.selected === modelData ? "✓ " : "") + modelData
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
