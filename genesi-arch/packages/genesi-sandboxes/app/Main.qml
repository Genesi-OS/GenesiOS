/*
 * Genesi Sandboxes — main window. Lists Distrobox workspaces and creates new
 * ones from a template. All actions go through the `backend` object, which drives
 * the genesi-sandboxes CLI. Visual language shared with the AI Mode Monitor
 * (Theme + GlassCard + GButton) — the pilot of a unified Genesi UI kit.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi Sandboxes"
    width: Kirigami.Units.gridUnit * 46
    height: Kirigami.Units.gridUnit * 38
    minimumWidth: Kirigami.Units.gridUnit * 34
    minimumHeight: Kirigami.Units.gridUnit * 28
    color: theme.bgBottom

    Theme { id: theme }

    property var boxes: []
    property var templates: []
    property bool hasDistrobox: true
    // NB: must NOT be named `backend` — that would shadow the `backend` context
    // property (the Python object). Keep this the container-engine name only.
    property string containerBackend: ""
    property bool backendReady: true
    property string backendIssue: ""        // "" | inactive | perm  (docker)
    property bool hasCode: false
    property bool busy: false
    property int selTpl: -1

    Connections {
        target: backend
        function onBoxesLoaded(json) {
            try {
                var o = JSON.parse(json)
                win.hasDistrobox = !!o.distrobox
                win.containerBackend = o.backend || ""
                win.backendReady = o.backendReady !== false
                win.backendIssue = o.backendIssue || ""
                win.hasCode = !!o.hasCode
                win.boxes = o.boxes || []
            } catch (e) { win.boxes = [] }
        }
        function onTemplatesLoaded(json) {
            try { win.templates = JSON.parse(json) || [] } catch (e) { win.templates = [] }
            if (win.templates.length > 0 && win.selTpl < 0) win.selTpl = 0
        }
        function onBusyChanged(b) { win.busy = b }
        function onLogLine(line) { logArea.append(line) }
        function onActionDone(msg) { logArea.append("• " + msg) }
    }

    function tpl() { return (win.selTpl >= 0 && win.selTpl < win.templates.length)
                            ? win.templates[win.selTpl] : null }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        background: Rectangle {
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.bgTop }
                GradientStop { position: 1.0; color: theme.bgBottom }
            }
        }

        // ════════════════════════ HEADER ════════════════════════
        header: Rectangle {
            implicitHeight: 58
            color: theme.bgTop
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                // ── Brand mark ──
                Kirigami.Icon {
                    source: "genesi-sandboxes"
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                }
                ColumnLayout {
                    spacing: -2
                    QQC2.Label { text: "Sandboxes"; font.bold: true; font.pixelSize: 16; color: theme.textHi }
                    QQC2.Label { text: "GENESI"; font.pixelSize: 9; font.letterSpacing: 2; color: theme.green }
                }

                Item { Layout.fillWidth: true }

                // backend chip
                Rectangle {
                    visible: win.containerBackend !== "" && win.containerBackend !== "none"
                    radius: 8; height: 26
                    implicitWidth: beRow.implicitWidth + 18
                    color: theme.a(win.backendReady ? theme.green : theme.red, 0.12)
                    border.width: 1
                    border.color: theme.a(win.backendReady ? theme.green : theme.red, 0.45)
                    RowLayout {
                        id: beRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: win.backendReady ? theme.greenBright : theme.red
                        }
                        QQC2.Label {
                            text: win.containerBackend
                            font.pixelSize: 11; color: theme.textMid
                        }
                    }
                }

                GButton {
                    theme: theme
                    kind: "ghost"
                    iconSource: "view-refresh"
                    text: "Refresh"
                    onClicked: backend.refresh()
                }
            }
        }

        // ════════════════════════ CONTENT ════════════════════════
        QQC2.ScrollView {
            anchors.fill: parent
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.largeSpacing

                Item { Layout.preferredHeight: 2 }

                // ── status banners ─────────────────────────────────────
                StatusBanner {
                    theme: theme
                    visible: !win.hasDistrobox
                    accent: theme.red
                    icon: "dialog-error"
                    title: "Distrobox is not installed"
                    body: "Install it from the Genesi Package Installer (distrobox + podman) to create workspaces."
                }
                StatusBanner {
                    theme: theme
                    visible: win.hasDistrobox && win.containerBackend === "none"
                    accent: theme.turbo
                    icon: "dialog-warning"
                    title: "No container backend found"
                    body: "Install podman (recommended, rootless — no daemon, no setup) or docker, then click Refresh."
                }
                StatusBanner {
                    theme: theme
                    visible: win.backendIssue === "inactive"
                    accent: theme.turbo
                    icon: "media-playback-start"
                    title: "Docker is installed but not running"
                    body: "Its service is stopped. Start it once below — it'll also start automatically on every boot. (Tip: podman needs none of this.)"
                    action: "Start Docker"
                    actionIcon: "media-playback-start"
                    busy: win.busy
                    onActionClicked: backend.startDocker()
                }
                StatusBanner {
                    theme: theme
                    visible: win.backendIssue === "perm"
                    accent: theme.turbo
                    icon: "dialog-warning"
                    title: "Your user can't talk to Docker yet"
                    body: "Add yourself to the docker group, then log out and back in:\n    sudo usermod -aG docker $USER"
                }

                // ── create form ────────────────────────────────────────
                GlassCard {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: createCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                    accent: theme.green

                    ColumnLayout {
                        id: createCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            spacing: 8
                            Kirigami.Icon { source: "list-add"; color: theme.green; width: 18; height: 18 }
                            QQC2.Label { text: "New workspace"; font.bold: true; font.pixelSize: 16; color: theme.textHi }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: Kirigami.Units.smallSpacing

                            // name field (styled)
                            QQC2.TextField {
                                id: nameField
                                placeholderText: "workspace name (e.g. my-api)"
                                Layout.preferredWidth: 210
                                enabled: !win.busy
                                color: theme.textHi
                                placeholderTextColor: theme.textLo
                                selectByMouse: true
                                background: Rectangle {
                                    radius: 9
                                    color: theme.a(theme.textHi, 0.04)
                                    border.width: 1
                                    border.color: nameField.activeFocus ? theme.a(theme.green, 0.6) : theme.line
                                    Behavior on border.color { ColorAnimation { duration: 140 } }
                                }
                            }

                            // template picker (custom pill → dialog)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: 9
                                color: tplMa.containsMouse ? theme.a(theme.textHi, 0.08) : theme.a(theme.textHi, 0.04)
                                border.width: 1
                                border.color: theme.line
                                enabled: !win.busy
                                opacity: win.busy ? 0.5 : 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: win.tpl() ? win.tpl().label : "Choose a stack…"
                                        color: win.tpl() ? theme.textHi : theme.textLo
                                        elide: Text.ElideRight
                                    }
                                    Kirigami.Icon { source: "arrow-down"; width: 14; height: 14; color: theme.textMid }
                                }
                                MouseArea {
                                    id: tplMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !win.busy
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tplDialog.open()
                                }
                            }

                            GButton {
                                theme: theme
                                kind: "filled"
                                text: "Create"
                                iconSource: "list-add"
                                enabled: !win.busy && nameField.text.trim().length > 0 && win.selTpl >= 0
                                onClicked: {
                                    var t = win.tpl()
                                    backend.createSandbox(nameField.text, t ? t.id : "plain")
                                    nameField.text = ""
                                }
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: theme.textLo
                            font.pixelSize: 12
                            visible: win.tpl() !== null
                            text: win.tpl() ? (win.tpl().hint + "   ·   image: " + win.tpl().image) : ""
                        }

                        // indeterminate progress while creating/removing
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.preferredHeight: 4
                            radius: 2
                            visible: win.busy
                            color: theme.a(theme.green, 0.15)
                            clip: true
                            Rectangle {
                                width: parent.width * 0.35
                                height: parent.height
                                radius: 2
                                color: theme.greenBright
                                SequentialAnimation on x {
                                    running: win.busy
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -parent.width * 0.35; to: parent.width; duration: 1100; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }
                }

                // ── workspaces header ──────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing + 2
                    Layout.rightMargin: Kirigami.Units.largeSpacing + 2
                    QQC2.Label {
                        text: "Workspaces"
                        font.bold: true; font.pixelSize: 13; color: theme.textMid
                        font.letterSpacing: 1
                    }
                    Rectangle {
                        radius: 9; height: 18; implicitWidth: cntL.implicitWidth + 14
                        color: theme.a(theme.green, 0.16)
                        QQC2.Label { id: cntL; anchors.centerIn: parent; text: win.boxes.length; font.pixelSize: 11; color: theme.greenBright }
                    }
                    Item { Layout.fillWidth: true }
                }

                // ── empty state ────────────────────────────────────────
                GlassCard {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 96
                    visible: win.boxes.length === 0 && win.hasDistrobox
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Kirigami.Icon { source: "genesi-sandboxes"; width: 30; height: 30; opacity: 0.5; Layout.alignment: Qt.AlignHCenter }
                        QQC2.Label { text: "No workspaces yet"; color: theme.textMid; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                        QQC2.Label { text: "Create one above to get an isolated dev environment."; color: theme.textLo; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    }
                }

                // ── workspace cards ────────────────────────────────────
                Repeater {
                    model: win.boxes
                    delegate: GlassCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.preferredHeight: 70
                        accent: modelData.running ? theme.green : theme.line
                        active: modelData.running

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.largeSpacing
                            anchors.rightMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing

                            // status dot
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                color: modelData.running ? theme.greenBright : theme.textLo
                                SequentialAnimation on opacity {
                                    running: modelData.running
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.35; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                QQC2.Label { text: modelData.name; font.bold: true; font.pixelSize: 14; color: theme.textHi }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.image + "   ·   " + modelData.status
                                    color: theme.textLo; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            GButton {
                                theme: theme
                                kind: "tonal"
                                accent: theme.purple
                                text: "Genesi Code"
                                iconSource: "genesi-code"
                                visible: win.hasCode
                                enabled: !win.busy
                                tooltip: "Open this workspace's project folder in Genesi Code"
                                onClicked: backend.openInCode(modelData.name)
                            }
                            GButton {
                                theme: theme
                                kind: "tonal"
                                accent: theme.green
                                text: "Open"
                                iconSource: "utilities-terminal"
                                enabled: !win.busy
                                tooltip: "Open a terminal inside the sandbox (in its project folder)"
                                onClicked: backend.enterSandbox(modelData.name)
                            }
                            GButton {
                                theme: theme
                                kind: "danger"
                                iconSource: "edit-delete"
                                enabled: !win.busy
                                tooltip: "Delete this workspace"
                                onClicked: { confirm.boxName = modelData.name; confirm.open() }
                            }
                        }
                    }
                }

                // ── log ────────────────────────────────────────────────
                GlassCard {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.preferredHeight: 150
                    visible: logArea.text.length > 0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: 4
                        RowLayout {
                            spacing: 7
                            Kirigami.Icon { source: "dialog-scripts"; color: theme.blue; width: 15; height: 15 }
                            QQC2.Label { text: "Activity log"; font.bold: true; font.pixelSize: 12; color: theme.textMid; Layout.fillWidth: true }
                            GButton { theme: theme; kind: "ghost"; text: "Clear"; onClicked: logArea.clear() }
                        }
                        QQC2.ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            QQC2.TextArea {
                                id: logArea
                                readOnly: true
                                wrapMode: Text.Wrap
                                color: theme.textMid
                                font.family: "monospace"
                                font.pixelSize: 12
                                background: null
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }
            }
        }

        // ════════════ TEMPLATE PICKER DIALOG ════════════
        Kirigami.PromptDialog {
            id: tplDialog
            title: "Choose a stack"
            standardButtons: Kirigami.Dialog.Cancel
            preferredWidth: Kirigami.Units.gridUnit * 26

            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: win.templates
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        radius: 9
                        implicitHeight: tRow.implicitHeight + Kirigami.Units.largeSpacing
                        color: tMa.containsMouse || win.selTpl === index
                               ? theme.a(theme.green, 0.12) : theme.a(theme.textHi, 0.04)
                        border.width: 1
                        border.color: win.selTpl === index ? theme.a(theme.green, 0.6) : theme.line
                        ColumnLayout {
                            id: tRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: 1
                            QQC2.Label {
                                text: (win.selTpl === index ? "✓ " : "") + modelData.label
                                color: win.selTpl === index ? theme.greenBright : theme.textHi
                                font.bold: win.selTpl === index
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.hint
                                color: theme.textLo; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                        MouseArea {
                            id: tMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { win.selTpl = index; tplDialog.close() }
                        }
                    }
                }
            }
        }

        // ════════════ REMOVE CONFIRM ════════════
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
