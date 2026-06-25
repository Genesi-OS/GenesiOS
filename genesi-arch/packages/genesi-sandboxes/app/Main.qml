/*
 * Genesi Sandboxes — Doquo-style workspace UI: a left sidebar (brand + primary
 * action + filters + backend status) and a content area (header + tabs + a clean
 * list of workspaces). Follows the system light/dark scheme via the shared kit
 * (Theme/GlassCard/GButton/StatusBanner are all theme-aware). Every action goes
 * through the `backend` object, which drives the genesi-sandboxes CLI.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    title: "Genesi Sandboxes"
    width: Kirigami.Units.gridUnit * 58
    height: Kirigami.Units.gridUnit * 40
    minimumWidth: Kirigami.Units.gridUnit * 44
    minimumHeight: Kirigami.Units.gridUnit * 30
    color: theme.bgBottom

    Theme { id: theme }
    I18n { id: i18n }

    property var boxes: []
    property var templates: []
    property bool hasDistrobox: true
    property string containerBackend: ""
    property bool backendReady: true
    property string backendIssue: ""          // "" | inactive | perm  (docker)
    property bool hasCode: false
    property bool busy: false
    property int selTpl: -1
    property string filter: "all"             // all | running | stopped
    property string query: ""

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

    function visibleBoxes() {
        var q = win.query.toLowerCase()
        var out = []
        for (var i = 0; i < win.boxes.length; i++) {
            var b = win.boxes[i]
            if (win.filter === "running" && !b.running) continue
            if (win.filter === "stopped" && b.running) continue
            if (q.length > 0 && b.name.toLowerCase().indexOf(q) < 0) continue
            out.push(b)
        }
        return out
    }

    function runningCount() {
        var n = 0
        for (var i = 0; i < win.boxes.length; i++) if (win.boxes[i].running) n++
        return n
    }

    // Stable per-workspace accent so each row gets its own colour, Doquo-style.
    function accentFor(name) {
        var pal = [theme.green, theme.blue, theme.purple, theme.turbo, theme.sevLow]
        var h = 0
        for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffff
        return pal[h % pal.length]
    }

    // ════════════════════════════════════════════════════════════════════
    pageStack.initialPage: Kirigami.Page {
        padding: 0
        background: Rectangle { color: theme.bgBottom }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ───────────────────────── SIDEBAR ─────────────────────────
            Rectangle {
                Layout.preferredWidth: 248
                Layout.fillHeight: true
                color: theme.bgTop
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.line }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // brand
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: 10
                        Kirigami.Icon { source: "genesi-sandboxes"; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                        ColumnLayout {
                            spacing: -3
                            QQC2.Label { text: "Sandboxes"; font.bold: true; font.pixelSize: 16; color: theme.textHi }
                            QQC2.Label { text: "GENESI OS"; font.pixelSize: 9; font.letterSpacing: 2; color: theme.green }
                        }
                        Item { Layout.fillWidth: true }
                        // Language switch (EN / PT, live)
                        Rectangle {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 26
                            radius: 8
                            color: sbLangMa.containsMouse ? theme.a(theme.green, 0.14) : theme.card
                            border.width: 1; border.color: theme.line
                            QQC2.Label { anchors.centerIn: parent; text: i18n.code; font.bold: true; font.pixelSize: 11; color: theme.textHi }
                            MouseArea {
                                id: sbLangMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: i18n.toggle()
                                QQC2.ToolTip.text: i18n.t("lang.tooltip")
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 400
                            }
                        }
                    }

                    // primary action
                    GButton {
                        theme: theme
                        kind: "filled"
                        Layout.fillWidth: true
                        text: i18n.t("sb.newWorkspace")
                        iconSource: "list-add"
                        enabled: !win.busy && win.hasDistrobox
                        onClicked: createDialog.open()
                    }

                    Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

                    // filters (Doquo-style nav)
                    Repeater {
                        model: [
                            { "k": "all",     "lk": "sb.all",     "icon": "view-list-symbolic" },
                            { "k": "running", "lk": "sb.running", "icon": "media-playback-start" },
                            { "k": "stopped", "lk": "sb.stopped", "icon": "media-playback-stop" }
                        ]
                        delegate: Rectangle {
                            id: navItem
                            required property var modelData
                            readonly property bool sel: win.filter === modelData.k
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            radius: 9
                            color: navItem.sel ? theme.a(theme.green, 0.14)
                                 : (nma.containsMouse ? theme.a(theme.textHi, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 130 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 9
                                Kirigami.Icon {
                                    source: navItem.modelData.icon
                                    Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                    color: navItem.sel ? theme.green : theme.textMid
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: i18n.t(navItem.modelData.lk)
                                    color: navItem.sel ? theme.textHi : theme.textMid
                                    font.bold: navItem.sel
                                }
                                QQC2.Label {
                                    text: modelData.k === "all" ? win.boxes.length
                                        : modelData.k === "running" ? win.runningCount()
                                        : (win.boxes.length - win.runningCount())
                                    color: theme.textLo; font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                id: nma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.filter = modelData.k
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // backend status chip
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 9
                        visible: win.containerBackend !== "" && win.containerBackend !== "none"
                        color: theme.a(win.backendReady ? theme.green : theme.red, 0.10)
                        border.width: 1
                        border.color: theme.a(win.backendReady ? theme.green : theme.red, 0.35)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 8
                            Rectangle { width: 8; height: 8; radius: 4; color: win.backendReady ? theme.greenBright : theme.red }
                            QQC2.Label { Layout.fillWidth: true; text: "backend: " + win.containerBackend; color: theme.textMid; font.pixelSize: 12; elide: Text.ElideRight }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.line }

                    // OTHER
                    Repeater {
                        model: [
                            { "label": "Refresh",  "icon": "view-refresh" },
                            { "label": "Help",     "icon": "help-contents" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 9
                            color: oma.containsMouse ? theme.a(theme.textHi, 0.06) : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 9
                                Kirigami.Icon { source: modelData.icon; Layout.preferredWidth: 15; Layout.preferredHeight: 15; color: theme.textMid }
                                QQC2.Label { Layout.fillWidth: true; text: modelData.label; color: theme.textMid }
                            }
                            MouseArea {
                                id: oma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.label === "Refresh") backend.refresh()
                                    else Qt.openUrlExternally("https://github.com/Genesi-OS/GenesiOS")
                                }
                            }
                        }
                    }
                }
            }

            // ───────────────────────── CONTENT ─────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // header block
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.largeSpacing * 2
                    Layout.bottomMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Rectangle {
                                radius: 6; implicitHeight: 18; implicitWidth: planLbl.implicitWidth + 16
                                color: theme.a(theme.green, 0.15)
                                QQC2.Label { id: planLbl; anchors.centerIn: parent; text: "GENESI OS"; font.pixelSize: 9; font.letterSpacing: 1.5; color: theme.green; font.bold: true }
                            }
                            QQC2.Label { text: "Dev Workspaces"; font.bold: true; font.pixelSize: 26; color: theme.textHi }
                            QQC2.Label { text: "Isolated, container-backed environments — one per project."; color: theme.textMid; font.pixelSize: 13 }
                        }
                        GButton {
                            theme: theme
                            kind: "filled"
                            text: "New workspace"
                            iconSource: "list-add"
                            enabled: !win.busy && win.hasDistrobox
                            Layout.alignment: Qt.AlignTop
                            onClicked: createDialog.open()
                        }
                    }
                }

                // banners
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing * 2
                    Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                    spacing: Kirigami.Units.smallSpacing
                    StatusBanner {
                        theme: theme; visible: !win.hasDistrobox; accent: theme.red; icon: "dialog-error"
                        title: i18n.t("sb.distroboxMissing")
                        body: "Install it from the Genesi Package Installer (distrobox + podman) to create workspaces."
                    }
                    StatusBanner {
                        theme: theme; visible: win.hasDistrobox && win.containerBackend === "none"; accent: theme.turbo; icon: "dialog-warning"
                        title: i18n.t("sb.noBackend")
                        body: "Install podman (recommended, rootless — no daemon, no setup) or docker, then Refresh."
                    }
                    StatusBanner {
                        theme: theme; visible: win.backendIssue === "inactive"; accent: theme.turbo; icon: "media-playback-start"
                        title: i18n.t("sb.dockerNotRunning")
                        body: "Its service is stopped. Start it once below — it'll also start on every boot. (podman needs none of this.)"
                        action: "Start Docker"; actionIcon: "media-playback-start"; busy: win.busy
                        onActionClicked: backend.startDocker()
                    }
                    StatusBanner {
                        theme: theme; visible: win.backendIssue === "perm"; accent: theme.turbo; icon: "dialog-warning"
                        title: i18n.t("sb.dockerNoPerm")
                        body: "Add yourself to the docker group, then log out and back in:\n    sudo usermod -aG docker $USER"
                    }
                }

                // tabs + search
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing * 2
                    Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.largeSpacing

                    Row {
                        spacing: 4
                        Repeater {
                            model: [
                                { "k": "all",     "label": "All" },
                                { "k": "running", "label": "Running" },
                                { "k": "stopped", "label": "Stopped" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: win.filter === modelData.k
                                height: 32
                                width: tabLbl.implicitWidth + 26
                                radius: 8
                                color: sel ? theme.a(theme.green, 0.16)
                                     : (tma.containsMouse ? theme.a(theme.textHi, 0.05) : "transparent")
                                Behavior on color { ColorAnimation { duration: 130 } }
                                QQC2.Label {
                                    id: tabLbl
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.sel ? theme.greenBright : theme.textMid
                                    font.bold: parent.sel
                                    font.pixelSize: 13
                                }
                                MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.filter = modelData.k }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // search
                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 32
                        radius: 8
                        color: theme.a(theme.textHi, theme.dark ? 0.05 : 0.04)
                        border.width: 1
                        border.color: searchField.activeFocus ? theme.a(theme.green, 0.6) : theme.line
                        Behavior on border.color { ColorAnimation { duration: 130 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 6
                            Kirigami.Icon { source: "search"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: theme.textLo }
                            QQC2.TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Search workspaces…"
                                color: theme.textHi
                                placeholderTextColor: theme.textLo
                                background: null
                                onTextChanged: win.query = text
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.leftMargin: Kirigami.Units.largeSpacing*2; Layout.rightMargin: Kirigami.Units.largeSpacing*2; height: 1; color: theme.line }

                // ── list ──
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    QQC2.ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ListView {
                        id: list
                        model: win.visibleBoxes()
                        spacing: Kirigami.Units.smallSpacing
                        topMargin: Kirigami.Units.largeSpacing
                        bottomMargin: Kirigami.Units.largeSpacing

                        delegate: GlassCard {
                            required property var modelData
                            width: ListView.view ? ListView.view.width - Kirigami.Units.largeSpacing * 4 : implicitWidth
                            x: Kirigami.Units.largeSpacing * 2
                            implicitHeight: 68
                            accent: win.accentFor(modelData.name)
                            active: modelData.running

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing

                                // icon tile
                                Rectangle {
                                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                                    radius: 11
                                    color: theme.a(win.accentFor(modelData.name), 0.16)
                                    QQC2.Label {
                                        anchors.centerIn: parent
                                        text: modelData.name.length > 0 ? modelData.name.charAt(0).toUpperCase() : "?"
                                        color: win.accentFor(modelData.name)
                                        font.bold: true; font.pixelSize: 18
                                    }
                                    // running dot
                                    Rectangle {
                                        visible: modelData.running
                                        width: 11; height: 11; radius: 5.5
                                        color: theme.greenBright
                                        border.width: 2; border.color: theme.bgBottom
                                        anchors.right: parent.right; anchors.bottom: parent.bottom
                                        anchors.rightMargin: -2; anchors.bottomMargin: -2
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        spacing: 8
                                        QQC2.Label { text: modelData.name; font.bold: true; font.pixelSize: 14; color: theme.textHi }
                                        Rectangle {
                                            radius: 6; implicitHeight: 17; implicitWidth: tagLbl.implicitWidth + 14
                                            color: theme.a(modelData.running ? theme.green : theme.textLo, 0.15)
                                            QQC2.Label { id: tagLbl; anchors.centerIn: parent; text: modelData.running ? "running" : "stopped"; font.pixelSize: 10; color: modelData.running ? theme.greenBright : theme.textLo }
                                        }
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: modelData.image + "   ·   " + modelData.status
                                        color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight
                                    }
                                }

                                GButton {
                                    theme: theme; kind: "tonal"; accent: theme.purple
                                    text: "Genesi Code"; iconSource: "genesi-code"
                                    visible: win.hasCode; enabled: !win.busy
                                    tooltip: "Open this workspace's project folder in Genesi Code"
                                    onClicked: backend.openInCode(modelData.name)
                                }
                                GButton {
                                    theme: theme; kind: "tonal"; accent: theme.green
                                    text: "Open"; iconSource: "utilities-terminal"; enabled: !win.busy
                                    tooltip: "Open a terminal inside the sandbox"
                                    onClicked: backend.enterSandbox(modelData.name)
                                }
                                GButton {
                                    theme: theme; kind: "danger"; iconSource: "edit-delete"; enabled: !win.busy
                                    tooltip: "Delete this workspace"
                                    onClicked: { confirm.boxName = modelData.name; confirm.open() }
                                }
                            }
                        }
                    }
                    }

                    // empty-state overlay (centered over the list area)
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        spacing: 6
                        Kirigami.Icon { source: "genesi-sandboxes"; Layout.preferredWidth: 44; Layout.preferredHeight: 44; opacity: 0.45; Layout.alignment: Qt.AlignHCenter }
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: win.boxes.length === 0 ? "No workspaces yet" : "Nothing matches"; color: theme.textMid; font.bold: true; font.pixelSize: 15 }
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: win.boxes.length === 0 ? "Create your first isolated dev environment." : "Try a different filter or search."; color: theme.textLo; font.pixelSize: 12 }
                    }
                }

                // activity log (collapsible-ish strip)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    visible: logArea.text.length > 0
                    color: theme.bgTop
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.line }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: 4
                        RowLayout {
                            spacing: 7
                            Kirigami.Icon { source: "dialog-scripts"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: theme.blue }
                            QQC2.Label { text: "Activity"; font.bold: true; font.pixelSize: 12; color: theme.textMid; Layout.fillWidth: true }
                            QQC2.BusyIndicator { running: win.busy; visible: win.busy; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
                            GButton { theme: theme; kind: "ghost"; text: "Clear"; onClicked: logArea.clear() }
                        }
                        QQC2.ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            QQC2.TextArea {
                                id: logArea
                                readOnly: true; wrapMode: Text.Wrap
                                color: theme.textMid; font.family: theme.mono; font.pixelSize: 12
                                background: null
                            }
                        }
                    }
                }
            }
        }

        // ── floating action button (Doquo-style) ──
        Rectangle {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: Kirigami.Units.largeSpacing * 2
            anchors.bottomMargin: Kirigami.Units.largeSpacing * 2
            width: 52; height: 52; radius: 26
            visible: win.hasDistrobox
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.greenBright }
                GradientStop { position: 1.0; color: theme.greenDeep }
            }
            scale: fabMa.pressed ? 0.94 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Kirigami.Icon { anchors.centerIn: parent; source: "list-add"; width: 24; height: 24; color: "#08130E" }
            MouseArea {
                id: fabMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !win.busy
                onClicked: createDialog.open()
                QQC2.ToolTip.text: "New workspace"
                QQC2.ToolTip.visible: containsMouse
            }
        }

        // ════════════ CREATE DIALOG (name + template) ════════════
        Kirigami.PromptDialog {
            id: createDialog
            title: i18n.t("sb.newWorkspace")
            standardButtons: Kirigami.Dialog.NoButton
            preferredWidth: Kirigami.Units.gridUnit * 28
            onOpened: {
                createName.text = ""
                win.selTpl = (win.templates.length > 0 ? 0 : -1)
                createName.forceActiveFocus()
            }

            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label { text: "Name"; color: theme.textMid; font.pixelSize: 12 }
                QQC2.TextField {
                    id: createName
                    Layout.fillWidth: true
                    placeholderText: "e.g. my-api"
                    enabled: !win.busy
                    color: theme.textHi
                    placeholderTextColor: theme.textLo
                    background: Rectangle {
                        radius: 9
                        color: theme.a(theme.textHi, 0.04)
                        border.width: 1
                        border.color: createName.activeFocus ? theme.a(theme.green, 0.6) : theme.line
                    }
                }

                QQC2.Label { text: "Stack"; color: theme.textMid; font.pixelSize: 12; Layout.topMargin: Kirigami.Units.smallSpacing }

                Repeater {
                    model: win.templates
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        radius: 9
                        implicitHeight: tRow.implicitHeight + Kirigami.Units.largeSpacing
                        color: tMa.containsMouse || win.selTpl === index ? theme.a(theme.green, 0.12) : theme.a(theme.textHi, 0.04)
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
                            QQC2.Label { Layout.fillWidth: true; text: modelData.hint; color: theme.textLo; font.pixelSize: 11; wrapMode: Text.WordWrap }
                        }
                        MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.selTpl = index }
                    }
                }

                GButton {
                    theme: theme; kind: "filled"; text: "Create workspace"; iconSource: "list-add"
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    enabled: !win.busy && createName.text.trim().length > 0 && win.selTpl >= 0
                    onClicked: {
                        var t = win.tpl()
                        backend.createSandbox(createName.text, t ? t.id : "plain")
                        createDialog.close()
                    }
                }
            }
        }

        // ════════════ REMOVE CONFIRM ════════════
        Kirigami.PromptDialog {
            id: confirm
            property string boxName: ""
            title: i18n.t("sb.removeWorkspace")
            subtitle: "Delete '" + boxName + "' and everything inside it? This cannot be undone."
            standardButtons: Kirigami.Dialog.NoButton
            customFooterActions: [
                Kirigami.Action { text: "Delete"; icon.name: "edit-delete"; onTriggered: { backend.removeSandbox(confirm.boxName); confirm.close() } },
                Kirigami.Action { text: "Cancel"; icon.name: "dialog-cancel"; onTriggered: confirm.close() }
            ]
        }
    }
}
