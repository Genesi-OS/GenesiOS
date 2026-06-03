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
            if (source.indexOf("cat ") === 0)
                root.applyState((data["stdout"] || "").trim())
            else
                root.readState()        // a control command ran; refresh now
        }
        function exec(cmd) { connectSource(cmd) }
    }

    function readState() { executable.exec("cat /run/genesi-ai-mode/state.json") }
    function setMode(mode) { executable.exec("genesi-ai-mode " + mode) }
    function openMonitor() { executable.exec("genesi-ai-monitor") }

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
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

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
                Kirigami.Icon {
                    source: "cpu"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    color: root.aiModeActive ? root.genesiGreen : root.offColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Kirigami.Heading { level: 3; text: "Genesi AI Mode" }
                    PlasmaComponents.Label {
                        text: "AI Mode: " + root.statusLabel()
                        color: root.aiModeActive ? root.genesiGreen : root.offColor
                        font.bold: true
                    }
                }
                PlasmaComponents.Label {
                    visible: !!root.state.tokens_per_second
                    text: (root.state.tokens_per_second || 0) + " tok/s"
                    color: root.genesiGreen
                    font.bold: true
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // live metrics
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.largeSpacing

                PlasmaComponents.Label { text: "CPU"; opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: (fullRoot.metrics().cpu_percent !== undefined
                           ? fullRoot.metrics().cpu_percent + "%" : "—")
                          + (fullRoot.metrics().cpu_temp_c != null
                             ? "   " + fullRoot.metrics().cpu_temp_c + "°C" : "")
                }
                PlasmaComponents.Label { text: "RAM"; opacity: 0.7 }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: fullRoot.metrics().ram_used_mb !== undefined
                          ? (fullRoot.metrics().ram_used_mb + " / "
                             + fullRoot.metrics().ram_total_mb + " MB")
                          : "—"
                }
            }

            // GPUs
            Repeater {
                model: fullRoot.gpus()
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "GPU " + (modelData.vendor || "?"); opacity: 0.7 }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: (modelData.util != null ? modelData.util + "%  " : "")
                              + (modelData.vram_used_mb != null
                                 ? modelData.vram_used_mb + "/" + modelData.vram_total_mb + "MB  " : "")
                              + (modelData.temp_c != null ? modelData.temp_c + "°C" : "")
                    }
                }
            }

            // loaded Ollama models
            ColumnLayout {
                Layout.fillWidth: true
                visible: (root.state.ollama || []).length > 0
                spacing: 2
                Kirigami.Separator { Layout.fillWidth: true }
                PlasmaComponents.Label { text: "Loaded models"; font.bold: true }
                Repeater {
                    model: root.state.ollama || []
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "• " + modelData.name
                              + (modelData.size_mb ? "  (" + modelData.size_mb + "MB, " + modelData.where + ")" : "")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            // applied tweaks
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                Kirigami.Separator { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.aiModeActive ? "Applied optimizations" : "Idle — nothing applied"
                    font.bold: true
                }
                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        model: root.state.applied || []
                        delegate: PlasmaComponents.Label {
                            width: ListView.view.width
                            text: "• " + modelData
                            wrapMode: Text.WordWrap
                            color: root.genesiGreen
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }
                }
            }

            // open the full Monitor app (dashboard + chat + model advisor)
            PlasmaComponents.Button {
                Layout.fillWidth: true
                text: "Abrir AI Mode Monitor"
                icon.name: "cpu"
                onClicked: root.openMonitor()
            }

            // controls
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    text: root.forceMode === "on" ? "Forced ON" : "Force ON"
                    icon.name: "run-build"
                    highlighted: root.forceMode === "on"
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
                    text: root.forceMode === "off" ? "Forced OFF" : "Force OFF"
                    icon.name: "dialog-cancel"
                    highlighted: root.forceMode === "off"
                    onClicked: root.setMode("off")
                }
            }
        }
    }
}
