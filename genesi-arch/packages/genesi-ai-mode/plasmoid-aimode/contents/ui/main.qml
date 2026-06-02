import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: root

    property bool aiModeActive: false
    property string forceMode: "auto"      // "on" | "off" | "auto"
    property var aiProcesses: []
    property string statusText: "AI Mode: OFF"
    property color statusColor: "#888888"

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
    Plasmoid.compactRepresentation: CompactRepresentation {}
    Plasmoid.fullRepresentation: FullRepresentation {}

    // Runs shell commands (the genesi-ai-mode CLI) from the widget.
    PlasmaCore.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: {
            disconnectSource(sourceName)
            updateStatus()
        }
        function run(cmd) {
            connectSource(cmd)
        }
    }

    Timer {
        id: statusTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: updateStatus()
    }

    Component.onCompleted: updateStatus()

    function updateStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///run/genesi-ai-mode/state.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var state = JSON.parse(xhr.responseText)
                        aiModeActive = state.ai_mode_active || false
                        forceMode = state.force_mode || "auto"
                        aiProcesses = state.ai_processes || []

                        if (aiModeActive) {
                            statusText = forceMode === "on"
                                ? "AI Mode: ON (forced)"
                                : "AI Mode: ON"
                            statusColor = "#1D9E75" // Genesi green
                        } else {
                            statusText = forceMode === "off"
                                ? "AI Mode: OFF (forced)"
                                : "AI Mode: OFF"
                            statusColor = "#888888"
                        }
                    } catch (e) {
                        console.log("Failed to parse AI state:", e)
                    }
                }
            }
        }
        xhr.send()
    }

    Component {
        id: CompactRepresentation

        Item {
            Layout.preferredWidth: icon.width + label.width + 16
            Layout.preferredHeight: icon.height

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: icon.scale = 1.1
                onExited: icon.scale = 1.0
                onClicked: plasmoid.expanded = !plasmoid.expanded
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                PlasmaCore.IconItem {
                    id: icon
                    source: "cpu"
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22

                    Behavior on scale {
                        NumberAnimation { duration: 150 }
                    }

                    SequentialAnimation on opacity {
                        running: aiModeActive
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 1000 }
                        NumberAnimation { to: 1.0; duration: 1000 }
                    }
                }

                PlasmaComponents3.Label {
                    id: label
                    text: "AI"
                    color: statusColor
                    font.bold: aiModeActive
                    font.pixelSize: 12
                }
            }
        }
    }

    Component {
        id: FullRepresentation

        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.preferredHeight: 200
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                PlasmaCore.IconItem {
                    source: "cpu"
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    PlasmaComponents3.Label {
                        text: "Genesi AI Mode"
                        font.bold: true
                        font.pixelSize: 16
                    }

                    PlasmaComponents3.Label {
                        text: statusText
                        color: statusColor
                        font.pixelSize: 12
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#333333"
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                PlasmaComponents3.Label {
                    text: "Detected AI Processes:"
                    font.bold: true
                    font.pixelSize: 12
                }

                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        model: aiProcesses
                        delegate: RowLayout {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: "#1D9E75"
                            }

                            PlasmaComponents3.Label {
                                text: modelData.name + " (PID: " + modelData.pid + ")"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    visible: aiProcesses.length === 0
                    text: "No AI processes detected"
                    color: "#888888"
                    font.italic: true
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#333333"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                PlasmaComponents3.Label {
                    text: "Optimizations when AI Mode is ON:"
                    font.bold: true
                    font.pixelSize: 11
                }
                PlasmaComponents3.Label {
                    text: "• CPU governor: performance"
                    font.pixelSize: 10
                    color: "#CCCCCC"
                }
                PlasmaComponents3.Label {
                    text: "• Swappiness: 10 (keep model in RAM)"
                    font.pixelSize: 10
                    color: "#CCCCCC"
                }
                PlasmaComponents3.Label {
                    text: "• Transparent huge pages: always"
                    font.pixelSize: 10
                    color: "#CCCCCC"
                }
                PlasmaComponents3.Label {
                    text: "• AI processes: high priority (nice -5)"
                    font.pixelSize: 10
                    color: "#CCCCCC"
                }
            }

            PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: "Refresh Status"
                icon.name: "view-refresh"
                onClicked: updateStatus()
            }

            // Manual override — writes the daemon's force file via the CLI.
            PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: forceMode === "on" ? "Back to automatic" : "Force AI Mode ON"
                icon.name: forceMode === "on" ? "dialog-cancel" : "run-build"
                onClicked: {
                    runner.run(forceMode === "on"
                        ? "genesi-ai-mode auto"
                        : "genesi-ai-mode on")
                }
            }
        }
    }
}
