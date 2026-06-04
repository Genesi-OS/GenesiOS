import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi AI Mode Monitor"
    width: Kirigami.Units.gridUnit * 42
    height: Kirigami.Units.gridUnit * 36
    minimumWidth: Kirigami.Units.gridUnit * 36
    minimumHeight: Kirigami.Units.gridUnit * 30

    readonly property color genesiGreen: "#1D9E75"

    property var st: ({})
    property bool active: false
    property string forceMode: "auto"
    
    // Turbo integration
    // activeModel = the model Ollama currently has LOADED (live, from /api/ps).
    // It drives the dashboard "AI ativa" card and FLICKERS as Ollama loads/evicts
    // models (keep-alive) or returns an empty /api/ps between cycles — so it must
    // NOT directly control the Turbo server's lifecycle.
    property string activeModel: (st.ollama && st.ollama.length > 0) ? st.ollama[0].name : ""
    property bool turboRequested: false
    property bool turboNeedsInstall: false

    // turboModel = the STABLE model Turbo serves. Driven from activeModel when it
    // has a value, otherwise the first installed model. It is sticky: it NEVER
    // resets to "" on a transient empty poll. Previously Turbo was bound straight
    // to the volatile activeModel, so every 2s flicker stopped + restarted
    // llama-server — the load counter kept resetting to 0 and Turbo never came up.
    property string firstInstalledModel: ""
    property string turboModel: ""

    onActiveModelChanged: if (activeModel) turboModel = activeModel
    onFirstInstalledModelChanged: if (!turboModel && firstInstalledModel) turboModel = firstInstalledModel

    // Changing the model only (re)starts Turbo — it never stops it. Only the user
    // flipping the switch off (turboRequested=false) stops the Turbo server.
    onTurboModelChanged: {
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel)
    }
    onTurboRequestedChanged: {
        if (turboRequested && turboModel) backend.setTurbo(true, turboModel)
        else if (!turboRequested) backend.setTurbo(false, "")
    }

    Component.onCompleted: backend.loadModels()

    Connections {
        target: backend
        function onTurboNeedsInstall(need) {
            win.turboNeedsInstall = need
            if (need) win.turboRequested = false
        }
        // Seed a default Turbo model from the installed list, so Turbo can start
        // even before the first Ollama prompt (otherwise activeModel stays empty
        // until something is loaded and the switch appears to do nothing).
        function onModelsLoaded(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            if (arr.length > 0) win.firstInstalledModel = arr[0]
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
    }

    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.poll() }

    globalDrawer: null // Remove default Kirigami drawer

    // Custom Header
    header: QQC2.ToolBar {
        background: Rectangle { color: Kirigami.Theme.backgroundColor }
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Item { width: Kirigami.Units.smallSpacing }
            
            Kirigami.Icon {
                source: "cpu"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                color: Kirigami.Theme.textColor
            }
            Kirigami.Heading { 
                level: 2; text: "AI Mode"
                font.bold: true; color: Kirigami.Theme.textColor 
            }
            
            Item { width: Kirigami.Units.largeSpacing }

            QQC2.TabBar {
                id: navBar
                Layout.fillWidth: true
                background: Item {}
                QQC2.TabButton { text: "Painel"; width: implicitWidth + Kirigami.Units.largeSpacing }
                QQC2.TabButton { text: "Chat com a IA"; width: implicitWidth + Kirigami.Units.largeSpacing }
                QQC2.TabButton { text: "Modelos"; width: implicitWidth + Kirigami.Units.largeSpacing }
            }

            QQC2.Button {
                text: "Force ON"
                icon.name: "run-build"
                opacity: win.forceMode === "on" ? 1.0 : 0.6
                onClicked: backend.setMode("on")
            }
            QQC2.Button {
                text: "Auto"
                icon.name: "view-refresh"
                highlighted: win.forceMode === "auto"
                onClicked: backend.setMode("auto")
            }
            QQC2.Button {
                text: "Force OFF"
                icon.name: "dialog-cancel"
                palette.button: win.forceMode === "off" ? "#DA4453" : Kirigami.Theme.buttonBackgroundColor
                palette.buttonText: win.forceMode === "off" ? "#ffffff" : Kirigami.Theme.textColor
                onClicked: backend.setMode("off")
            }
            Item { width: Kirigami.Units.smallSpacing }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: navBar.currentIndex

        // 1. Painel
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            
            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.largeSpacing
                
                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing } // Top margin

                // MAIN STATUS CARD
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    radius: 12
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                    border.color: win.active ? win.genesiGreen : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            width: 64; height: 64; radius: 32
                            color: "transparent"
                            border.color: win.active ? win.genesiGreen : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                            border.width: 1
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: "cpu"
                                width: 32; height: 32
                                color: win.active ? win.genesiGreen : Kirigami.Theme.disabledTextColor
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Kirigami.Heading {
                                level: 1
                                text: win.active
                                      ? (win.forceMode === "on" ? "AI Mode ON (forced)"
                                         : st.aggressive ? "AI Mode ON (max)" : "AI Mode ON (battery-safe)")
                                      : "AI Mode OFF"
                                font.bold: true
                            }
                            QQC2.Label {
                                opacity: 0.7
                                text: {
                                    var h = win.hw()
                                    var parts = []
                                    if (h.cpu_vendor) parts.push(h.cpu_vendor + " " + (h.physical_cores||"?") + "c/" + (h.logical_cores||"?") + "t")
                                    if (h.ram_mb) parts.push(Math.round(h.ram_mb/1024) + " GB RAM")
                                    if (h.chassis) parts.push(h.chassis + (h.virtualized ? " (VM)" : ""))
                                    return parts.join("  •  ")
                                }
                            }
                            RowLayout {
                                spacing: 6
                                Rectangle { width: 8; height: 8; radius: 4; color: win.active ? win.genesiGreen : Kirigami.Theme.disabledTextColor }
                                QQC2.Label { 
                                    text: win.active ? "Ativo — otimizações aplicadas" : "Inativo — nenhum ajuste aplicado" 
                                    opacity: 0.8
                                }
                            }
                        }
                        
                        Rectangle {
                            width: 60; height: 30; radius: 15
                            color: win.active ? Qt.rgba(win.genesiGreen.r, win.genesiGreen.g, win.genesiGreen.b, 0.2) : "transparent"
                            border.color: win.active ? win.genesiGreen : Kirigami.Theme.disabledTextColor
                            border.width: 1
                            QQC2.Label {
                                anchors.centerIn: parent
                                text: win.active ? "ON" : "OFF"
                                font.bold: true
                                color: win.active ? win.genesiGreen : Kirigami.Theme.disabledTextColor
                            }
                        }
                    }
                }

                // TURBO CARD
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    radius: 12
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                    border.color: win.turboRequested ? "#E67E22" : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    border.width: win.turboRequested ? 1 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            width: 48; height: 48; radius: 12
                            color: Qt.rgba(230/255, 126/255, 34/255, 0.1)
                            border.color: "#E67E22"
                            border.width: 1
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                source: "lightning"
                                width: 24; height: 24
                                color: "#E67E22"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Kirigami.Heading { level: 2; text: "Modo Turbo"; font.bold: true }
                                QQC2.Button {
                                    text: "Instalar Backend"
                                    icon.name: "download"
                                    visible: win.turboNeedsInstall
                                    onClicked: backend.installTurboBackend()
                                    QQC2.ToolTip.text: "Instalar genesi-llama-cpp"
                                    QQC2.ToolTip.visible: hovered
                                }
                            }
                            QQC2.Label { text: "Libera todo o desempenho para inferência ultrarrápida (speculative decoding)."; opacity: 0.7 }
                        }
                        
                        QQC2.Switch {
                            checked: win.turboRequested
                            onToggled: win.turboRequested = checked
                        }
                    }
                }

                // METRICS ROW
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    // CPU
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: 12
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            
                            Canvas {
                                width: 60; height: 60
                                property real val: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent / 100.0 : 0
                                onValChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0,0,width,height);
                                    var cx = width/2, cy = height/2, r = width/2 - 4;
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1); ctx.stroke();
                                    if(val > 0) {
                                        ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + 2*Math.PI*Math.min(val, 1.0));
                                        ctx.lineWidth = 6; ctx.strokeStyle = win.genesiGreen; ctx.stroke();
                                    }
                                }
                                QQC2.Label { anchors.centerIn: parent; text: win.metrics().cpu_percent !== undefined ? Math.round(win.metrics().cpu_percent) + "\n%" : "—"; horizontalAlignment: Text.AlignHCenter; font.bold: true; font.pixelSize: 12 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: "CPU"; font.bold: true; opacity: 0.7 }
                                Kirigami.Heading { level: 2; text: win.metrics().cpu_percent !== undefined ? win.metrics().cpu_percent.toFixed(1) + "%" : "—" }
                                QQC2.Label { text: (win.hw().physical_cores||"?") + " núcleos • " + (win.hw().logical_cores||"?") + " threads"; opacity: 0.6; font.pixelSize: 12 }
                            }
                        }
                    }

                    // MEMORY
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: 12
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            
                            Canvas {
                                width: 60; height: 60
                                property real val: win.metrics().ram_total_mb ? (win.metrics().ram_used_mb||0) / win.metrics().ram_total_mb : 0
                                onValChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0,0,width,height);
                                    var cx = width/2, cy = height/2, r = width/2 - 4;
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1); ctx.stroke();
                                    if(val > 0) {
                                        ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + 2*Math.PI*Math.min(val, 1.0));
                                        ctx.lineWidth = 6; ctx.strokeStyle = Kirigami.Theme.highlightColor; ctx.stroke();
                                    }
                                }
                                QQC2.Label { anchors.centerIn: parent; text: win.metrics().ram_total_mb ? Math.round(((win.metrics().ram_used_mb||0) / win.metrics().ram_total_mb)*100) + "\n%" : "—"; horizontalAlignment: Text.AlignHCenter; font.bold: true; font.pixelSize: 12 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: "MEMÓRIA"; font.bold: true; opacity: 0.7 }
                                Kirigami.Heading { level: 2; text: win.metrics().ram_total_mb ? (Math.round((win.metrics().ram_used_mb||0)/102.4)/10).toFixed(1) + " / " + Math.round(win.metrics().ram_total_mb/1024) + " GB" : "—" }
                                QQC2.Label { text: (win.metrics().ram_used_mb||0) + " MB em uso"; opacity: 0.6; font.pixelSize: 12 }
                            }
                        }
                    }

                    // INFERENCE
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: 12
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            
                            Canvas {
                                width: 60; height: 60
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0,0,width,height);
                                    var cx = width/2, cy = height/2, r = width/2 - 4;
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1); ctx.stroke();
                                    if(win.activeModel) {
                                        ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + 2*Math.PI);
                                        ctx.lineWidth = 6; ctx.strokeStyle = "#9B59B6"; ctx.stroke();
                                    }
                                }
                                QQC2.Label { anchors.centerIn: parent; text: win.activeModel ? "🚀\n" : "—"; horizontalAlignment: Text.AlignHCenter; font.bold: true; font.pixelSize: 12 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: "INFERÊNCIA"; font.bold: true; opacity: 0.7 }
                                Kirigami.Heading { level: 2; text: win.activeModel ? (st.tokens_per_second ? st.tokens_per_second + " t/s" : "Ativa") : "—" }
                                QQC2.Label { text: win.activeModel ? win.activeModel : "nenhum modelo"; opacity: 0.6; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // APPLIED OPTIMIZATIONS
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    implicitHeight: optLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    radius: 12
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                    
                    ColumnLayout {
                        id: optLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: win.active ? "Otimizações Aplicadas" : "Inativo — nenhum ajuste aplicado"
                            font.bold: true
                            font.pixelSize: 16
                        }
                        
                        QQC2.Label {
                            visible: !win.active
                            opacity: 0.6
                            text: "Inicie um modelo local (ou use Force ON) para ver o tuning ao vivo aqui."
                        }

                        Repeater {
                            model: st.applied || []
                            RowLayout {
                                Layout.fillWidth: true
                                Kirigami.Icon { source: "dialog-ok"; color: win.genesiGreen; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                                QQC2.Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData; opacity: 0.8 }
                            }
                        }
                    }
                }
                
                Item { Layout.fillHeight: true } // spacer
            }
        }

        // 2. Chat
        ChatPage {
            id: chatPage
        }

        // 3. Modelos
        AdvisorPage {
            id: advisorPage
        }
    }
}