import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property var listeners: []

    Plasmoid.icon: "genesi-ports"
    toolTipMainText: "Genesi PortScope"
    toolTipSubText: listeners.length + " listening sockets"

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            if (source.indexOf("genesi-ports list-json") !== -1) {
                try {
                    var parsed = JSON.parse(data["stdout"] || "{}")
                    root.listeners = parsed.listeners || []
                } catch (e) { root.listeners = [] }
            } else {
                refreshDelay.restart()
            }
        }
        function exec(command) { connectSource(command) }
    }

    function refresh() { runner.exec("genesi-ports list-json") }
    function stopProcess(pid, port) {
        runner.exec("pkexec genesi-ports kill " + pid + " " + port)
    }

    Timer {
        interval: 12000; repeat: true; running: root.expanded
        triggeredOnStart: true; onTriggered: root.refresh()
    }
    Timer { id: refreshDelay; interval: 700; onTriggered: root.refresh() }
    Component.onCompleted: refresh()

    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        RowLayout {
            anchors.centerIn: parent; spacing: 3
            Kirigami.Icon {
                source: "genesi-ports"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            PC3.Label { text: root.listeners.length; visible: root.listeners.length > 0; font.bold: true }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 23
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 27
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading { level: 2; text: "PortScope"; Layout.fillWidth: true }
                PC3.Label { text: root.listeners.length + " listening"; opacity: 0.65 }
                PC3.ToolButton {
                    icon.name: "view-refresh"; onClicked: root.refresh()
                    PC3.ToolTip.text: "Refresh"; PC3.ToolTip.visible: hovered
                }
            }

            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.listeners.length === 0
                iconName: "network-disconnect"
                text: "No listening ports"
                explanation: "Local services appear here when they start."
            }

            QQC2.ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.listeners.length > 0; clip: true
                ListView {
                    model: root.listeners; spacing: Kirigami.Units.smallSpacing
                    delegate: Kirigami.AbstractCard {
                        width: ListView.view ? ListView.view.width : implicitWidth
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                width: 48; height: 38; radius: 6
                                color: modelData.scope === "all" ? "#3336e69a" : "#333aafe0"
                                Column {
                                    anchors.centerIn: parent; spacing: 0
                                    PC3.Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.port; font.bold: true }
                                    PC3.Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.proto.toUpperCase(); opacity: 0.55; font.pixelSize: 9 }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                PC3.Label {
                                    text: modelData.process || "Restricted"; font.bold: true
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                PC3.Label {
                                    text: "PID " + (modelData.pid || "?") + "  |  " + modelData.stack
                                    opacity: 0.6; font: Kirigami.Theme.smallFont
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                }
                            }
                            PC3.ToolButton {
                                icon.name: "process-stop"; visible: modelData.pid > 1
                                onClicked: root.stopProcess(modelData.pid, modelData.port)
                                PC3.ToolTip.text: "Stop process"; PC3.ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }

            PC3.Button {
                Layout.fillWidth: true; text: "Open PortScope"; icon.name: "genesi-ports"
                onClicked: {
                    runner.exec("genesi-ports-gui")
                    root.expanded = false
                }
            }
        }
    }
}
