/*
 * Genesi Containers — Plasma 6 widget for Docker/Podman.
 *
 * Pure front-end: it polls `genesi-containers list-json` through Plasma's
 * Executable data source and renders the result, and runs start/stop/restart/
 * logs/shell through the same CLI. No privileged logic lives here.
 */
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support 2.0 as P5Support

PlasmoidItem {
    id: root

    readonly property string helper: "genesi-containers"
    property var containers: []
    property string engine: "none"
    property int runningCount: 0

    Plasmoid.icon: "docker"
    toolTipMainText: "Genesi Containers"
    toolTipSubText: engine === "none"
        ? "No container engine detected"
        : (runningCount + " running · engine: " + engine)

    // --- command runner ------------------------------------------------------
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source) // one-shot
            if (source.indexOf(root.helper + " list-json") !== -1) {
                root.parseList(data["stdout"] || "")
            } else {
                // any control command (start/stop/...) -> refresh shortly after
                refreshTimer.restart()
            }
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function refresh() {
        runner.exec(helper + " list-json")
    }

    function parseList(stdout) {
        try {
            var obj = JSON.parse(stdout)
            root.engine = obj.engine || "none"
            root.containers = obj.containers || []
            var n = 0
            for (var i = 0; i < root.containers.length; i++)
                if (root.containers[i].running) n++
            root.runningCount = n
        } catch (e) {
            root.engine = "none"
            root.containers = []
            root.runningCount = 0
        }
    }

    function control(action, id) {
        // shell-safe: ids from the engine are [a-z0-9] but quote anyway
        runner.exec(helper + " " + action + " '" + id + "'")
    }

    Timer {
        id: pollTimer
        interval: 4000
        running: root.expanded || Plasmoid.location === PlasmaCore.Types.Floating
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer { id: refreshTimer; interval: 600; onTriggered: root.refresh() }

    Component.onCompleted: refresh()

    // --- compact representation (panel) -------------------------------------
    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "docker"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            PC3.Label {
                text: root.runningCount
                visible: root.runningCount > 0
                font.bold: true
            }
        }
    }

    // --- full representation (popup) ----------------------------------------
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 2
                    text: "Containers"
                    Layout.fillWidth: true
                }
                PC3.Label {
                    text: root.engine === "none" ? "" : root.engine
                    opacity: 0.6
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    PC3.ToolTip.text: "Refresh"
                    PC3.ToolTip.visible: hovered
                }
            }

            // empty state
            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.containers.length === 0
                iconName: "docker"
                text: root.engine === "none"
                    ? "No container engine found"
                    : "No containers"
                explanation: root.engine === "none"
                    ? "Install Docker or Podman from the Genesi Package Installer."
                    : "Create one and it shows up here."
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.containers.length > 0
                clip: true
                ListView {
                    model: root.containers
                    spacing: Kirigami.Units.smallSpacing
                    delegate: Kirigami.AbstractCard {
                        width: ListView.view ? ListView.view.width : implicitWidth
                        contentItem: ColumnLayout {
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: modelData.running ? "#22c55e" : "#9ca3af"
                                }
                                PC3.Label {
                                    text: modelData.name
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // actions
                                PC3.ToolButton {
                                    icon.name: "media-playback-start"
                                    visible: !modelData.running
                                    onClicked: root.control("start", modelData.id)
                                    PC3.ToolTip.text: "Start"; PC3.ToolTip.visible: hovered
                                }
                                PC3.ToolButton {
                                    icon.name: "media-playback-stop"
                                    visible: modelData.running
                                    onClicked: root.control("stop", modelData.id)
                                    PC3.ToolTip.text: "Stop"; PC3.ToolTip.visible: hovered
                                }
                                PC3.ToolButton {
                                    icon.name: "view-refresh"
                                    visible: modelData.running
                                    onClicked: root.control("restart", modelData.id)
                                    PC3.ToolTip.text: "Restart"; PC3.ToolTip.visible: hovered
                                }
                                PC3.ToolButton {
                                    icon.name: "utilities-terminal"
                                    visible: modelData.running
                                    onClicked: root.control("shell", modelData.id)
                                    PC3.ToolTip.text: "Shell"; PC3.ToolTip.visible: hovered
                                }
                                PC3.ToolButton {
                                    icon.name: "viewlog"
                                    onClicked: root.control("logs", modelData.id)
                                    PC3.ToolTip.text: "Logs"; PC3.ToolTip.visible: hovered
                                }
                            }
                            PC3.Label {
                                text: modelData.image
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: modelData.ports && modelData.ports.length
                                    ? ("⇄ " + modelData.ports) : modelData.status
                                opacity: 0.55
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
