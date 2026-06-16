/*
 * Genesi Sandboxes — main window. Lists Distrobox workspaces and creates new
 * ones from a template. All actions go through the `backend` object, which
 * drives the genesi-sandboxes CLI.
 */
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi Sandboxes"
    width: 880
    height: 620
    minimumWidth: 640
    minimumHeight: 480

    readonly property color accent: "#22c55e"
    property var boxes: []
    property var templates: []
    property bool hasDistrobox: true
    property bool busy: false

    Connections {
        target: backend
        function onBoxesLoaded(json) {
            try {
                var o = JSON.parse(json)
                win.hasDistrobox = !!o.distrobox
                win.boxes = o.boxes || []
            } catch (e) { win.boxes = [] }
        }
        function onTemplatesLoaded(json) {
            try { win.templates = JSON.parse(json) || [] } catch (e) { win.templates = [] }
            if (win.templates.length > 0 && tplCombo.currentIndex < 0)
                tplCombo.currentIndex = 0
        }
        function onBusyChanged(b) { win.busy = b }
        function onLogLine(line) { logArea.append(line) }
        function onActionDone(msg) { logArea.append("• " + msg) }
    }

    pageStack.initialPage: Kirigami.Page {
        title: "Workspaces"
        actions: [
            Kirigami.Action {
                text: "Refresh"
                icon.name: "view-refresh"
                onTriggered: backend.refresh()
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            // distrobox missing banner
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: !win.hasDistrobox
                type: Kirigami.MessageType.Warning
                text: "Distrobox is not installed. Install it from the Genesi Package Installer (distrobox + podman)."
            }

            // --- create form -------------------------------------------------
            Kirigami.Card {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading { level: 3; text: "New workspace" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.TextField {
                            id: nameField
                            placeholderText: "name (e.g. my-api)"
                            Layout.preferredWidth: 200
                            enabled: !win.busy
                        }
                        QQC2.ComboBox {
                            id: tplCombo
                            Layout.fillWidth: true
                            enabled: !win.busy
                            model: win.templates
                            textRole: "label"
                            currentIndex: -1
                        }
                        QQC2.Button {
                            text: "Create"
                            icon.name: "list-add"
                            enabled: !win.busy && nameField.text.trim().length > 0
                                     && tplCombo.currentIndex >= 0
                            onClicked: {
                                var t = win.templates[tplCombo.currentIndex]
                                backend.createSandbox(nameField.text, t ? t.id : "plain")
                                nameField.text = ""
                            }
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        visible: tplCombo.currentIndex >= 0
                        text: {
                            var t = win.templates[tplCombo.currentIndex]
                            return t ? (t.hint + "  ·  image: " + t.image) : ""
                        }
                    }
                    QQC2.ProgressBar {
                        Layout.fillWidth: true
                        indeterminate: true
                        visible: win.busy
                    }
                }
            }

            // --- existing workspaces ----------------------------------------
            Kirigami.Heading { level: 3; text: "Workspaces (" + win.boxes.length + ")" }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ListView {
                    model: win.boxes
                    spacing: Kirigami.Units.smallSpacing
                    delegate: Kirigami.AbstractCard {
                        width: ListView.view ? ListView.view.width : implicitWidth
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                color: modelData.running ? win.accent : "#9ca3af"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label { text: modelData.name; font.bold: true }
                                QQC2.Label {
                                    text: modelData.image + "  ·  " + modelData.status
                                    opacity: 0.6
                                    font: Kirigami.Theme.smallFont
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            QQC2.Button {
                                text: "Open"
                                icon.name: "utilities-terminal"
                                enabled: !win.busy
                                onClicked: backend.enterSandbox(modelData.name)
                            }
                            QQC2.Button {
                                icon.name: "edit-delete"
                                enabled: !win.busy
                                onClicked: { confirm.boxName = modelData.name; confirm.open() }
                            }
                        }
                    }
                }
            }

            // --- log ---------------------------------------------------------
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: logArea.length > 0
                QQC2.TextArea {
                    id: logArea
                    readOnly: true
                    wrapMode: TextArea.Wrap
                    font.family: "monospace"
                }
            }
        }

        Kirigami.PromptDialog {
            id: confirm
            property string boxName: ""
            title: "Remove workspace"
            subtitle: "Delete '" + boxName + "' and everything inside it? This cannot be undone."
            standardButtons: Kirigami.Dialog.NoButton
            customFooterActions: [
                Kirigami.Action {
                    text: "Delete"
                    icon.name: "edit-delete"
                    onTriggered: { backend.removeSandbox(confirm.boxName); confirm.close() }
                },
                Kirigami.Action {
                    text: "Cancel"
                    icon.name: "dialog-cancel"
                    onTriggered: confirm.close()
                }
            ]
        }
    }
}
