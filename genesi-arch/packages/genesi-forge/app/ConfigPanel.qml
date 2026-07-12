/*
 * Genesi Forge — Forge Canvas config panel (right rail). Shows the selected
 * node's settings. The GitHub Sync node gets the full repository form from the
 * mockup; every node exposes a live YAML Preview compiled from the graph.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

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
        indicator: FIcon { x: cb.width - 26; y: (cb.height - 14) / 2; size: 14; name: "chevron-down"; color: root.theme.textMid }
    }
    component GField: Rectangle {
        Layout.fillWidth: true; implicitHeight: 40
        radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
        property alias text: tf.text
        property string icon: ""
        signal accepted(string value)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
            FIcon { visible: parent.parent.icon !== ""; name: parent.parent.icon; size: 14; color: root.theme.textMid }
            QQC2.TextField { id: tf; Layout.fillWidth: true; background: null; color: root.theme.textHi; font.pixelSize: 13
                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                onEditingFinished: parent.parent.accepted(text) }
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
                FIcon { anchors.centerIn: parent; name: root.node ? root.node.icon : "zap"; size: 19
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
                GButton { theme: root.theme; kind: "tonal"; text: "Advanced Settings"; iconSource: "icons/sliders.svg"; Layout.fillWidth: true }

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
                                FIcon { name: "check"; size: 13; color: root.theme.greenBright }
                                QQC2.Label { text: modelData; color: root.theme.textMid; font.pixelSize: 12 }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
                GButton { theme: root.theme; kind: "filled"; text: "Create Repository"; iconSource: "icons/github.svg"; Layout.fillWidth: true
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

                FieldLabel { text: "Trigger"; visible: root.node && root.node.kind === "event" }
                Combo {
                    visible: root.node && root.node.kind === "event"
                    model: [ "push", "pull_request", "branch_created", "schedule" ]
                    currentIndex: root.optionIndex(model, root.configValue("event", "push"))
                    onActivated: root.setConfig("event", currentText)
                }
                FieldLabel { text: "Branch filter"; visible: root.node && root.node.kind === "event" }
                GField { visible: root.node && root.node.kind === "event"; text: root.configValue("branch", "main"); icon: "git-branch"
                    onAccepted: root.setConfig("branch", value) }

                FieldLabel { text: "Project template"; visible: root.node && (root.node.kind === "bootstrap" || root.node.kind === "template") }
                Combo {
                    visible: root.node && (root.node.kind === "bootstrap" || root.node.kind === "template")
                    model: [ "react-vite", "next", "electron", "react-native", "rust", "go", "python", "spring" ]
                    currentIndex: root.optionIndex(model, root.configValue("template", "react-vite"))
                    onActivated: root.setConfig("template", currentText)
                }

                FieldLabel { text: "Command"; visible: root.node && (root.node.kind === "script" || root.node.kind === "tests") }
                GField { visible: root.node && (root.node.kind === "script" || root.node.kind === "tests")
                    text: root.configValue("command", ""); icon: "terminal"; onAccepted: root.setConfig("command", value) }

                FieldLabel { text: "Backend framework"; visible: root.node && root.node.kind === "backend" }
                Combo { visible: root.node && root.node.kind === "backend"; model: [ "fastapi", "express" ]
                    currentIndex: root.optionIndex(model, root.configValue("framework", "fastapi"))
                    onActivated: root.setConfig("framework", currentText) }

                FieldLabel { text: "Quality tool"; visible: root.node && root.node.kind === "quality" }
                Combo { visible: root.node && root.node.kind === "quality"; model: [ "biome", "eslint" ]
                    currentIndex: root.optionIndex(model, root.configValue("tool", "biome"))
                    onActivated: root.setConfig("tool", currentText) }

                FieldLabel { text: "Frontend tooling"; visible: root.node && root.node.kind === "frontend" }
                Combo { visible: root.node && root.node.kind === "frontend"; model: [ "tailwind", "shadcn" ]
                    currentIndex: root.optionIndex(model, root.configValue("tool", "tailwind"))
                    onActivated: root.setConfig("tool", currentText) }

                FieldLabel { text: "Deploy provider"; visible: root.node && root.node.kind === "deploy" }
                Combo { visible: root.node && root.node.kind === "deploy"; model: [ "vercel", "railway", "render" ]
                    currentIndex: root.optionIndex(model, root.configValue("provider", "vercel"))
                    onActivated: root.setConfig("provider", currentText) }

                FieldLabel { text: "Package manager"; visible: root.node && root.node.kind === "install" }
                Combo { visible: root.node && root.node.kind === "install"; model: [ "auto", "npm", "pnpm", "yarn", "bun" ]
                    currentIndex: root.optionIndex(model, root.configValue("manager", "auto"))
                    onActivated: root.setConfig("manager", currentText) }

                FieldLabel { text: "Base branch"; visible: root.node && root.node.kind === "git_automation" }
                GField { visible: root.node && root.node.kind === "git_automation"; text: root.configValue("base", "staging"); icon: "git-branch"
                    onAccepted: root.setConfig("base", value) }
                FieldLabel { text: "New branch"; visible: root.node && root.node.kind === "git_automation" }
                GField { visible: root.node && root.node.kind === "git_automation"; text: root.configValue("branch", "feature/new-feature"); icon: "git-branch"
                    onAccepted: root.setConfig("branch", value) }

                FieldLabel { text: "Variables (KEY=value, comma separated)"; visible: root.node && root.node.kind === "env" }
                GField { visible: root.node && root.node.kind === "env"; text: root.configValue("variables", "APP_ENV=development"); icon: "lock"
                    onAccepted: root.setConfig("variables", value) }

                FieldLabel { text: "Webhook URL"; visible: root.node && root.node.kind === "webhook" }
                GField { visible: root.node && root.node.kind === "webhook"; text: root.configValue("url", "https://example.com/hook"); icon: "link"
                    onAccepted: root.setConfig("url", value) }

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
                            FIcon {
                                name: "x"; size: 13; color: root.theme.textLo
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                    onClicked: { var l = root.node.lines.slice(); l.splice(index, 1); root.graphProvider.setNodeLines(root.node.id, l) } }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6; visible: root.node }
                GButton {
                    visible: root.node; theme: root.theme; kind: "danger"
                    text: "Delete Node"; iconSource: "icons/trash.svg"; Layout.fillWidth: true
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
    function configValue(key, fallback) {
        return root.node && root.node.config && root.node.config[key] !== undefined ? root.node.config[key] : fallback
    }
    function setConfig(key, value) {
        if (root.node && root.graphProvider) root.graphProvider.setNodeConfig(root.node.id, key, value)
    }
    function optionIndex(model, value) {
        for (var i = 0; i < model.length; i++) if (model[i] === value) return i
        return 0
    }
    function previewYaml() {
        if (!root.graphProvider || !root.project) return "# add nodes to generate a workflow"
        return backend.previewWorkflow(root.project.name, root.graphProvider.graphJson())
    }
}
