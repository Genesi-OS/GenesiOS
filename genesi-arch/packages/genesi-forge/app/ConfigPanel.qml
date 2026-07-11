/*
 * Genesi Forge — Forge Canvas config panel (right rail). Shows the selected
 * node's settings. The GitHub Sync node gets the full repository form from the
 * mockup; every node exposes a live YAML Preview compiled from the graph.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property var project
    property var node
    property var graphProvider
    property string sub: "config"

    readonly property bool isGithub: node && node.kind === "github"

    component FieldLabel: QQC2.Label {
        color: root.theme.textMid; font.pixelSize: 12; font.bold: true
        Layout.topMargin: 6
    }
    component Combo: QQC2.ComboBox {
        id: cb
        Layout.fillWidth: true
        implicitHeight: 40
        background: Rectangle { radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi }
        contentItem: QQC2.Label {
            leftPadding: 12; rightPadding: 30; verticalAlignment: Text.AlignVCenter
            text: cb.displayText; color: root.theme.textHi; font.pixelSize: 13; elide: Text.ElideRight
        }
        indicator: Kirigami.Icon { x: cb.width - 26; y: (cb.height - 14) / 2; width: 14; height: 14; source: "arrow-down"; color: root.theme.textMid }
    }
    component GField: Rectangle {
        Layout.fillWidth: true; implicitHeight: 40
        radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
        property alias text: tf.text
        property string icon: ""
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
            Kirigami.Icon { visible: parent.parent.icon !== ""; source: parent.parent.icon; width: 14; height: 14; color: root.theme.textMid }
            QQC2.TextField { id: tf; Layout.fillWidth: true; background: null; color: root.theme.textHi; font.pixelSize: 13
                selectionColor: root.theme.green; selectedTextColor: root.theme.white }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true; spacing: 11
            Rectangle {
                width: 40; height: 40; radius: 11
                color: root.node ? root.theme.a(root.node.accent, 0.18) : root.theme.cardHi
                Kirigami.Icon { anchors.centerIn: parent; source: root.node ? root.node.icon : "showgraph"; width: 20; height: 20
                    color: root.node ? root.node.accent : root.theme.textMid }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                QQC2.Label { text: root.node ? root.node.title : "No node selected"; color: root.theme.textHi
                    font.family: root.theme.display; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                QQC2.Label {
                    text: root.isGithub ? "Initialize repository and setup remote sync"
                        : (root.node ? "Configure this workflow step" : "Pick a node on the canvas")
                    color: root.theme.textMid; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap
                }
            }
        }

        // Sub-tabs
        RowLayout {
            Layout.fillWidth: true; spacing: 0
            Repeater {
                model: [ { k: "config", l: "Config" }, { k: "preview", l: "Preview" } ]
                delegate: Item {
                    Layout.fillWidth: true; implicitHeight: 34
                    QQC2.Label { anchors.centerIn: parent; text: modelData.l
                        color: root.sub === modelData.k ? root.theme.textHi : root.theme.textLo
                        font.pixelSize: 13; font.bold: root.sub === modelData.k }
                    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 2; color: root.sub === modelData.k ? root.theme.green : root.theme.line }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sub = modelData.k }
                }
            }
        }

        // Body
        QQC2.ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: availableWidth

            Item {
                id: bodyContent
                width: root.width - 36
                implicitHeight: githubCol.visible ? githubCol.implicitHeight
                              : genericCol.visible ? genericCol.implicitHeight
                              : previewBox.implicitHeight

            // Config — GitHub form
            ColumnLayout {
                id: githubCol
                visible: root.sub === "config" && root.isGithub
                width: parent.width
                spacing: 6

                FieldLabel { text: "GitHub Account" }
                Combo { model: [ "@dev.genesi" ] }
                FieldLabel { text: "Repository Name" }
                GField { text: root.project ? root.project.name : "project" }
                FieldLabel { text: "Visibility" }
                Combo { model: [ "Private", "Public" ] }

                Item { Layout.preferredHeight: 4 }
                Repeater {
                    model: [ "Initialize with README", "Add .gitignore", "Setup GitHub Actions" ]
                    delegate: RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6
                        QQC2.Label { text: modelData; color: root.theme.textHi; font.pixelSize: 13; Layout.fillWidth: true }
                        GToggle { theme: root.theme; checked: true }
                    }
                }

                FieldLabel { text: "Actions Template" }
                Combo { model: [ "Node.js CI", "Python CI", "Docker Build", "Rust CI" ] }

                Item { Layout.preferredHeight: 6 }
                GButton { theme: root.theme; kind: "tonal"; text: "Advanced Settings"; iconSource: "settings-configure"; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true; Layout.topMargin: 8
                    implicitHeight: createCol.implicitHeight + 28
                    radius: 12; color: root.theme.a(root.theme.purple, 0.08)
                    border.width: 1; border.color: root.theme.a(root.theme.purple, 0.28)
                    ColumnLayout {
                        id: createCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14; spacing: 8
                        QQC2.Label { text: "This will create:"; color: root.theme.purpleBright; font.pixelSize: 12; font.bold: true }
                        Repeater {
                            model: [ "Local Git repository", "GitHub repository", "Initial commit", "GitHub Actions workflow" ]
                            delegate: RowLayout {
                                spacing: 8
                                Kirigami.Icon { source: "checkmark"; width: 14; height: 14; color: root.theme.greenBright }
                                QQC2.Label { text: modelData; color: root.theme.textMid; font.pixelSize: 12 }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
                GButton { theme: root.theme; kind: "filled"; text: "Create Repository"; iconSource: "github"; Layout.fillWidth: true
                    enabled: root.project !== null
                    onClicked: backend.createGitHub(root.project.path, repoField() , true) }
            }

            // Config — generic node (editable)
            ColumnLayout {
                id: genericCol
                visible: root.sub === "config" && !root.isGithub
                width: parent.width
                spacing: 8

                QQC2.Label {
                    visible: !root.node
                    text: "Select a node on the canvas to configure it."
                    color: root.theme.textLo; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap
                }

                FieldLabel { text: "Node name"; visible: root.node }
                Rectangle {
                    visible: root.node
                    Layout.fillWidth: true; implicitHeight: 40; radius: 9
                    color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
                    QQC2.TextField {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10
                        background: null; verticalAlignment: Text.AlignVCenter
                        text: root.node ? root.node.title : ""
                        color: root.theme.textHi; font.pixelSize: 13
                        selectionColor: root.theme.green; selectedTextColor: root.theme.white
                        onEditingFinished: if (root.node) root.graphProvider.renameNode(root.node.id, text)
                    }
                }

                RowLayout {
                    visible: root.node; Layout.fillWidth: true; Layout.topMargin: 4
                    FieldLabel { text: "Steps" }
                    Item { Layout.fillWidth: true }
                    QQC2.Label {
                        text: "+ Add"; color: root.theme.greenBright; font.pixelSize: 12; font.bold: true
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { var l = root.node.lines.slice(); l.push("New step"); root.graphProvider.setNodeLines(root.node.id, l) } }
                    }
                }
                Repeater {
                    model: root.node ? root.node.lines : []
                    delegate: Rectangle {
                        Layout.fillWidth: true; implicitHeight: 38; radius: 9
                        color: root.theme.cardHi; border.width: 1; border.color: root.theme.line
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                            Rectangle { width: 5; height: 5; radius: 2.5; color: root.node ? root.node.accent : root.theme.green }
                            QQC2.TextField {
                                Layout.fillWidth: true; background: null
                                text: modelData; color: root.theme.textHi; font.pixelSize: 13
                                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                onEditingFinished: { var l = root.node.lines.slice(); l[index] = text; root.graphProvider.setNodeLines(root.node.id, l) }
                            }
                            Kirigami.Icon {
                                source: "edit-delete"; width: 13; height: 13; color: root.theme.textLo
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                    onClicked: { var l = root.node.lines.slice(); l.splice(index, 1); root.graphProvider.setNodeLines(root.node.id, l) } }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6; visible: root.node }
                GButton {
                    visible: root.node; theme: root.theme; kind: "danger"
                    text: "Delete Node"; iconSource: "edit-delete"; Layout.fillWidth: true
                    onClicked: if (root.node) root.graphProvider.deleteNode(root.node.id)
                }
            }

            // Preview — generated YAML
            Rectangle {
                id: previewBox
                visible: root.sub === "preview"
                width: parent.width
                implicitHeight: Math.max(200, yamlText.implicitHeight + 24)
                radius: 12; color: root.theme.bgBottom; border.width: 1; border.color: root.theme.line
                QQC2.Label {
                    id: yamlText
                    anchors.fill: parent; anchors.margins: 12
                    text: root.previewYaml()
                    color: root.theme.textMid; font.family: "monospace"; font.pixelSize: 11
                    wrapMode: Text.NoWrap
                }
            }
            }
        }
    }

    function repoField() { return root.project ? root.project.name : "" }
    function previewYaml() {
        if (!root.graphProvider || !root.project) return "# add nodes to generate a workflow"
        return backend.previewWorkflow(root.project.name, root.graphProvider.graphJson())
    }
}
