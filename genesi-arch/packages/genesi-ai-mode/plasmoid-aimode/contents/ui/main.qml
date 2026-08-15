/*
 * Genesi AI Mode — Plasma 6 widget.
 *
 * Reads the daemon's /run/genesi-ai-mode/state.json (live metrics, applied
 * tweaks, loaded Ollama models, tokens/s) and offers the on/auto toggle via the
 * genesi-ai-mode CLI. Plasma 6 / KF6 / Qt6 APIs throughout (the old Plasma 5
 * imports — PlasmaCore.IconItem, DataSource, plasmoid 2.0 — don't exist on 6).
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color genesiGreen: "#1D9E75"
    readonly property color offColor: Kirigami.Theme.disabledTextColor

    property var state: ({})
    property bool aiModeActive: false
    property string forceMode: "auto"
    property bool aggressive: false

    preferredRepresentation: compactRepresentation

    // Read state.json and run the CLI through the executable engine. A plasmoid
    // can't reliably XHR a file:// path under plasmashell (Plasma 6 blocks it),
    // but it can `cat` the file via the same engine it uses for the buttons.
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var out = (data["stdout"] || "").trim()
            // Two different `cat` sources now, so dispatch on the path rather
            // than on the "cat " prefix alone — otherwise the benchmark file
            // would be parsed as state and blank the whole widget.
            if (source.indexOf("bench.json") >= 0)
                root.applyBench(out)
            else if (source.indexOf("cat ") === 0)
                root.applyState(out)
            else
                root.readState()        // a control command ran; refresh now
        }
        function exec(cmd) { connectSource(cmd) }
    }

    // Last measured OFF-vs-ON result, written by `genesi-ai-mode bench`.
    // Empty until the user has ever run one — the widget then invites them to.
    property var bench: ({})

    function applyBench(txt) {
        try {
            root.bench = JSON.parse(txt)
        } catch (e) {
            root.bench = ({})          // never benchmarked, or the file is mid-write
        }
    }

    function readBench() {
        executable.exec("cat $HOME/.cache/genesi-ai-mode/bench.json")
    }
    function runBench() {
        // Long-running and interactive-ish: give it a terminal instead of
        // freezing the panel for the couple of minutes it takes.
        executable.exec("setsid -f konsole -e sh -c 'genesi-ai-mode bench; echo; read -p \"Enter para fechar...\" _'")
    }

    function readState() {
        executable.exec("cat /run/genesi-ai-mode/state.json")
        root.readBench()
    }
    function setMode(mode) { executable.exec("genesi-ai-mode " + mode) }
    function openMonitor() { executable.exec("setsid -f /usr/local/bin/genesi-ai-monitor") }
    function openQuickChat() { executable.exec("setsid -f /usr/local/bin/genesi-ai-quick --show") }

    function applyState(txt) {
        try {
            var s = JSON.parse(txt)
            root.state = s
            root.aiModeActive = s.ai_mode_active || false
            root.forceMode = s.force_mode || "auto"
            root.aggressive = s.aggressive || false
        } catch (e) {
            // transient read miss — keep the last good state, don't blank the UI
        }
    }

    Timer {
        interval: 3000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: readState()
    }

    function statusLabel() {
        if (aiModeActive)
            return forceMode === "on" ? "ON (forced)"
                 : aggressive ? "ON (max)" : "ON (battery-safe)"
        return forceMode === "off" ? "OFF (forced)" : "OFF"
    }

    // ── compact (panel) ───────────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                id: icon
                source: "cpu"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                color: root.aiModeActive ? root.genesiGreen : root.offColor
                SequentialAnimation on opacity {
                    running: root.aiModeActive
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 1000 }
                    NumberAnimation { to: 1.0;  duration: 1000 }
                }
            }
            PlasmaComponents.Label {
                text: "AI"
                color: root.aiModeActive ? root.genesiGreen : root.offColor
                font.bold: root.aiModeActive
            }
        }
    }

    // ── full (popup) ──────────────────────────────────────────────────────────
    fullRepresentation: Item {
        id: fullRoot
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 25
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 27

        function metrics() { return root.state.metrics || ({}) }
        function gpus() { return (root.state.metrics && root.state.metrics.gpus) || [] }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                
                Rectangle {
                    width: Kirigami.Units.iconSizes.huge
                    height: Kirigami.Units.iconSizes.huge
                    radius: width / 2
                    color: "transparent"
                    border.color: root.aiModeActive ? root.genesiGreen : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                    border.width: 1
                    
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: "cpu"
                        width: Kirigami.Units.iconSizes.large
                        height: Kirigami.Units.iconSizes.large
                        color: root.aiModeActive ? root.genesiGreen : root.offColor
                    }
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Kirigami.Heading { 
                        level: 3; 
                        text: "Genesi AI Mode"
                        font.bold: true
                    }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: root.aiModeActive ? root.genesiGreen : root.offColor
                        }
                        PlasmaComponents.Label {
                            text: "AI Mode: " + root.statusLabel()
                            color: root.aiModeActive ? root.genesiGreen : root.offColor
                            font.bold: true
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // CPU
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "CPU"; font.bold: true; opacity: 0.8 }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: (fullRoot.metrics().cpu_percent !== undefined
                               ? fullRoot.metrics().cpu_percent.toFixed(1) + "%" : "—")
                        font.bold: true
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    Rectangle {
                        width: parent.width * (fullRoot.metrics().cpu_percent !== undefined ? Math.min(fullRoot.metrics().cpu_percent / 100.0, 1.0) : 0)
                        height: parent.height
                        radius: 3
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.genesiGreen }
                            GradientStop { position: 1.0; color: Kirigami.Theme.highlightColor }
                        }
                    }
                }
            }

            // RAM
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "RAM"; font.bold: true; opacity: 0.8 }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: fullRoot.metrics().ram_used_mb !== undefined
                              ? (fullRoot.metrics().ram_used_mb + " / "
                                 + fullRoot.metrics().ram_total_mb + " MB")
                              : "—"
                        font.bold: true
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    Rectangle {
                        width: fullRoot.metrics().ram_total_mb ? parent.width * Math.min(fullRoot.metrics().ram_used_mb / fullRoot.metrics().ram_total_mb, 1.0) : 0
                        height: parent.height
                        radius: 3
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.genesiGreen }
                            GradientStop { position: 1.0; color: Kirigami.Theme.highlightColor }
                        }
                    }
                }
            }

            // GPUs
            Repeater {
                model: fullRoot.gpus()
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label { text: "GPU " + (modelData.vendor || "?"); font.bold: true; opacity: 0.8 }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents.Label {
                            text: (modelData.util != null ? modelData.util + "%" : "—")
                            font.bold: true
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                        Rectangle {
                            width: parent.width * (modelData.util != null ? Math.min(modelData.util / 100.0, 1.0) : 0)
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: root.genesiGreen }
                                GradientStop { position: 1.0; color: Kirigami.Theme.highlightColor }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true } // spacer to push everything to top and bottom

            // Performance / Model text
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                PlasmaComponents.Label {
                    text: root.aiModeActive ? "Performance — profile applied" : "Idle — no profile applied"
                    font.bold: true
                }
                PlasmaComponents.Label {
                    text: {
                        var modelText = (root.state.ollama && root.state.ollama.length > 0) 
                                        ? "Modelo local" : "Nenhum modelo carregado";
                        var tokText = root.state.tokens_per_second ? root.state.tokens_per_second + " tok/s" : "";
                        if (tokText) return modelText + " · " + tokText;
                        return modelText;
                    }
                    opacity: 0.7
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                // What AI Mode is actually buying you.
                //
                // Every optimizer in this daemon was invisible before: the
                // benchmark printed a number once and it was lost. Showing the
                // last measured OFF-vs-ON result makes the tuning legible —
                // and it is a MEASURED figure from this machine, never an
                // estimate, so it stays honest.
                PlasmaComponents.Label {
                    visible: root.bench && root.bench.on_tps !== undefined
                    text: {
                        if (!root.bench || root.bench.on_tps === undefined)
                            return ""
                        var g = root.bench.gain_pct
                        var sign = g > 0 ? "+" : ""
                        return "Turbo: " + sign + g.toFixed(0) + "% medido  ("
                             + root.bench.off_tps.toFixed(1) + " → "
                             + root.bench.on_tps.toFixed(1) + " tok/s)"
                    }
                    color: (root.bench && root.bench.gain_pct > 0)
                           ? Kirigami.Theme.positiveTextColor
                           : Kirigami.Theme.textColor
                    opacity: 0.85
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PlasmaComponents.Label {
                    visible: !(root.bench && root.bench.on_tps !== undefined)
                    text: "Turbo: ganho ainda não medido nesta máquina"
                    opacity: 0.55
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }

            // Quick Chat entry + visible global shortcut.
            PlasmaComponents.Button {
                Layout.fillWidth: true
                text: "Open Quick Chat"
                icon.name: "input-keyboard"
                onClicked: root.openQuickChat()
            }

            // Offered only until there IS a number. Once measured, the result
            // sits in the status line above and this button stops taking space.
            PlasmaComponents.Button {
                visible: !(root.bench && root.bench.on_tps !== undefined)
                Layout.fillWidth: true
                text: "Medir o ganho do Turbo"
                icon.name: "speedometer"
                onClicked: root.runBench()
            }
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Ctrl + Alt + Space from anywhere"
                opacity: 0.72
                font.family: "monospace"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            // Open monitor button
            PlasmaComponents.Button {
                Layout.fillWidth: true
                text: "Open AI Mode Monitor"
                icon.name: "cpu"
                onClicked: root.openMonitor()
            }

            // Controls
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    text: "Force ON"
                    icon.name: "run-build"
                    opacity: root.forceMode === "on" ? 1.0 : 0.6
                    onClicked: root.setMode("on")
                }
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    text: "Auto"
                    icon.name: "view-refresh"
                    highlighted: root.forceMode === "auto"
                    onClicked: root.setMode("auto")
                }
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    text: "Force OFF"
                    icon.name: "dialog-cancel"
                    opacity: root.forceMode === "off" ? 1.0 : 0.6
                    onClicked: root.setMode("off")
                }
            }
        }
    }
}
