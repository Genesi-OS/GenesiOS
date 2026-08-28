/*
 * Genesi Sandboxes — Doquo-style workspace UI: a left sidebar (brand + primary
 * action + filters + backend status) and a content area (header + tabs + a clean
 * list of workspaces). Uses the Forge-inspired Studio surface language while
 * every action continues to go
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
    color: appTheme.bgBottom

    // appTheme, not `theme`: a component that HAS a `theme` property
    // (GButton, StudioCard, StatusBanner, GlassCard) resolves a bare
    // `theme` on the right-hand side to its own UNSET property, not to
    // this id -- so `theme: appTheme` binds the property to itself and every
    // sibling binding reading appTheme.x gets undefined.
    StudioTheme { id: appTheme }
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
        var pal = [appTheme.green, appTheme.blue, appTheme.purple, appTheme.turbo, appTheme.sevLow]
        var h = 0
        for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffff
        return pal[h % pal.length]
    }

    // ════════════════════════════════════════════════════════════════════
    pageStack.initialPage: Kirigami.Page {
        padding: 0
        background: Rectangle { color: appTheme.bgBottom }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ───────────────────────── SIDEBAR ─────────────────────────
            Rectangle {
                Layout.preferredWidth: 238
                Layout.fillHeight: true
                color: appTheme.panelTop
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: appTheme.line }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // brand
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: 8
                            color: appTheme.a(appTheme.green, 0.13)
                            border.width: 1; border.color: appTheme.a(appTheme.green, 0.32)
                            Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: "genesi-sandboxes"; color: appTheme.greenBright }
                        }
                        ColumnLayout {
                            spacing: -3
                            QQC2.Label { text: "Workspace Lab"; font.bold: true; font.pixelSize: 16; color: appTheme.textHi }
                            QQC2.Label { text: "GENESI SANDBOXES"; font.pixelSize: 9; color: appTheme.accentText; font.bold: true }
                        }
                        Item { Layout.fillWidth: true }
                        // Language switch (EN / PT, live)
                        Rectangle {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 26
                            radius: 8
                            color: sbLangMa.containsMouse ? appTheme.a(appTheme.green, 0.14) : appTheme.card
                            border.width: 1; border.color: appTheme.line
                            QQC2.Label { anchors.centerIn: parent; text: i18n.code; font.bold: true; font.pixelSize: 11; color: appTheme.textHi }
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

                    // The primary action used to be here TOO. Three buttons
                    // that open the same dialog were on this screen at once:
                    // this one, the one beside the page title, and a floating
                    // one in the bottom-right corner. The sidebar's job is
                    // navigation; the action that creates the thing belongs
                    // beside the thing.
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
                            radius: 8
                            color: navItem.sel ? appTheme.a(appTheme.green, 0.14)
                                 : (nma.containsMouse ? appTheme.a(appTheme.textHi, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 130 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 9
                                Kirigami.Icon {
                                    source: navItem.modelData.icon
                                    Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                    color: navItem.sel ? appTheme.green : appTheme.textMid
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: i18n.t(navItem.modelData.lk)
                                    color: navItem.sel ? appTheme.textHi : appTheme.textMid
                                    font.bold: navItem.sel
                                }
                                QQC2.Label {
                                    text: modelData.k === "all" ? win.boxes.length
                                        : modelData.k === "running" ? win.runningCount()
                                        : (win.boxes.length - win.runningCount())
                                    color: appTheme.textLo; font.pixelSize: 11
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
                        radius: 8
                        visible: win.containerBackend !== "" && win.containerBackend !== "none"
                        color: appTheme.a(win.backendReady ? appTheme.green : appTheme.red, 0.10)
                        border.width: 1
                        border.color: appTheme.a(win.backendReady ? appTheme.green : appTheme.red, 0.35)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 8
                            Rectangle { width: 8; height: 8; radius: 4; color: win.backendReady ? appTheme.greenBright : appTheme.red }
                            QQC2.Label { Layout.fillWidth: true; text: "backend: " + win.containerBackend; color: appTheme.textMid; font.pixelSize: 12; elide: Text.ElideRight }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: appTheme.line }

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
                            color: oma.containsMouse ? appTheme.a(appTheme.textHi, 0.06) : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 9
                                Kirigami.Icon { source: modelData.icon; Layout.preferredWidth: 15; Layout.preferredHeight: 15; color: appTheme.textMid }
                                QQC2.Label { Layout.fillWidth: true; text: modelData.label; color: appTheme.textMid }
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
                    Layout.margins: Kirigami.Units.largeSpacing * 1.75
                    Layout.bottomMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Rectangle {
                                radius: 6; implicitHeight: 18; implicitWidth: planLbl.implicitWidth + 16
                                color: appTheme.a(appTheme.green, 0.15)
                                QQC2.Label { id: planLbl; anchors.centerIn: parent; text: "GENESI OS"; font.pixelSize: 9; font.letterSpacing: 1.5; color: appTheme.accentText; font.bold: true }
                            }
                            QQC2.Label { text: "Isolated Workspaces"; font.bold: true; font.pixelSize: 27; color: appTheme.textHi }
                            QQC2.Label { text: "Container-backed environments with a real project attached."; color: appTheme.textMid; font.pixelSize: 13 }
                        }
                        GButton {
                            theme: appTheme
                            kind: "filled"
                            text: "New workspace"
                            iconSource: "list-add"
                            enabled: !win.busy && win.hasDistrobox
                            Layout.alignment: Qt.AlignTop
                            onClicked: createDialog.open()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 18

                        ColumnLayout {
                            spacing: 0
                            QQC2.Label { text: win.boxes.length; color: appTheme.textHi; font.pixelSize: 18; font.bold: true }
                            QQC2.Label { text: "TOTAL WORKSPACES"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                        }
                        Rectangle { width: 1; height: 30; color: appTheme.lineHi }
                        ColumnLayout {
                            spacing: 0
                            QQC2.Label { text: win.runningCount(); color: appTheme.greenBright; font.pixelSize: 18; font.bold: true }
                            QQC2.Label { text: "RUNNING"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                        }
                        Rectangle { width: 1; height: 30; color: appTheme.lineHi }
                        ColumnLayout {
                            spacing: 0
                            QQC2.Label { text: Math.max(0, win.boxes.length - win.runningCount()); color: appTheme.textMid; font.pixelSize: 18; font.bold: true }
                            QQC2.Label { text: "STOPPED"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                        }
                        Rectangle { width: 1; height: 30; color: appTheme.lineHi }
                        ColumnLayout {
                            spacing: 0
                            QQC2.Label { text: win.containerBackend || "detecting"; color: win.backendReady ? appTheme.accentText : appTheme.turboBright; font.pixelSize: 13; font.bold: true }
                            QQC2.Label { text: "RUNTIME"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // banners
                ColumnLayout {
                    Layout.fillWidth: true
                    // fillHeight FALSE, explicitly. Qt defaults it to TRUE for a
                    // nested layout (and false for everything else), so this
                    // column -- four banners, all of them hidden on a healthy
                    // machine -- was silently swallowing every spare pixel and
                    // pushing the search row four hundred of them down the page.
                    // That gap was the biggest thing on the screen and belonged
                    // to nothing at all.
                    Layout.fillHeight: false
                    Layout.leftMargin: Kirigami.Units.largeSpacing * 2
                    Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                    spacing: Kirigami.Units.smallSpacing
                    StatusBanner {
                        theme: appTheme; visible: !win.hasDistrobox; accent: appTheme.red; icon: "dialog-error"
                        title: i18n.t("sb.distroboxMissing")
                        body: "Install it from the Genesi Package Installer (distrobox + podman) to create workspaces."
                    }
                    StatusBanner {
                        theme: appTheme; visible: win.hasDistrobox && win.containerBackend === "none"; accent: appTheme.turbo; icon: "dialog-warning"
                        title: i18n.t("sb.noBackend")
                        body: "Install podman (recommended, rootless — no daemon, no setup) or docker, then Refresh."
                    }
                    StatusBanner {
                        theme: appTheme; visible: win.backendIssue === "inactive"; accent: appTheme.turbo; icon: "media-playback-start"
                        title: i18n.t("sb.dockerNotRunning")
                        body: "Its service is stopped. Start it once below — it'll also start on every boot. (podman needs none of this.)"
                        action: "Start Docker"; actionIcon: "media-playback-start"; busy: win.busy
                        onActionClicked: backend.startDocker()
                    }
                    StatusBanner {
                        theme: appTheme; visible: win.backendIssue === "perm"; accent: appTheme.turbo; icon: "dialog-warning"
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

// The All / Running / Stopped tabs used to be here, duplicating the
                    // nav in the sidebar three inches to the left -- which also
                    // carries the COUNTS, so it is the better of the two.


                    Item { Layout.fillWidth: true }

                    // search
                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 32
                        radius: 8
                        color: appTheme.a(appTheme.textHi, appTheme.dark ? 0.05 : 0.04)
                        border.width: 1
                        border.color: searchField.activeFocus ? appTheme.a(appTheme.green, 0.6) : appTheme.line
                        Behavior on border.color { ColorAnimation { duration: 130 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 6
                            Kirigami.Icon { source: "search"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: appTheme.textLo }
                            QQC2.TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Search workspaces…"
                                color: appTheme.textHi
                                placeholderTextColor: appTheme.textLo
                                selectedTextColor: appTheme.white
                                selectionColor: appTheme.a(appTheme.green, 0.72)
                                background: null
                                onTextChanged: win.query = text
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing; Layout.leftMargin: Kirigami.Units.largeSpacing*2; Layout.rightMargin: Kirigami.Units.largeSpacing*2; height: 1; color: appTheme.line }

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

                        delegate: StudioCard {
                            required property var modelData
                            width: ListView.view ? ListView.view.width - Kirigami.Units.largeSpacing * 4 : implicitWidth
                            x: Kirigami.Units.largeSpacing * 2
                            implicitHeight: 78
                            accent: win.accentFor(modelData.name)
                            active: modelData.running

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing

                                // icon tile
                                Rectangle {
                                    Layout.preferredWidth: 46; Layout.preferredHeight: 46
                                    radius: 8
                                    color: appTheme.a(win.accentFor(modelData.name), 0.16)
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
                                        color: appTheme.greenBright
                                        border.width: 2; border.color: appTheme.bgBottom
                                        anchors.right: parent.right; anchors.bottom: parent.bottom
                                        anchors.rightMargin: -2; anchors.bottomMargin: -2
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        spacing: 8
                                        QQC2.Label { text: modelData.name; font.bold: true; font.pixelSize: 14; color: appTheme.textHi }
                                        Rectangle {
                                            radius: 6; implicitHeight: 17; implicitWidth: tagLbl.implicitWidth + 14
                                            color: appTheme.a(modelData.running ? appTheme.green : appTheme.textLo, 0.15)
                                            QQC2.Label { id: tagLbl; anchors.centerIn: parent; text: modelData.running ? "running" : "stopped"; font.pixelSize: 10; color: modelData.running ? appTheme.accentText : appTheme.textMid }
                                        }
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: modelData.image + "   ·   " + modelData.status
                                        color: appTheme.textLo; font.pixelSize: 11; elide: Text.ElideRight
                                    }
                                }

                                GButton {
                                    theme: appTheme; kind: "tonal"; accent: appTheme.purple
                                    text: "Genesi Code"; iconSource: "genesi-code"
                                    visible: win.hasCode; enabled: !win.busy
                                    tooltip: "Open this workspace's project folder in Genesi Code"
                                    onClicked: backend.openInCode(modelData.name)
                                }
                                GButton {
                                    theme: appTheme; kind: "tonal"; accent: appTheme.green
                                    text: "Open"; iconSource: "utilities-terminal"; enabled: !win.busy
                                    tooltip: "Open a terminal inside the sandbox"
                                    onClicked: backend.enterSandbox(modelData.name)
                                }
                                GButton {
                                    theme: appTheme; kind: "danger"; iconSource: "edit-delete"; enabled: !win.busy
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
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: win.boxes.length === 0 ? "No workspaces yet" : "Nothing matches"; color: appTheme.textMid; font.bold: true; font.pixelSize: 15 }
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: win.boxes.length === 0 ? "Create your first isolated dev environment." : "Try a different filter or search."; color: appTheme.textLo; font.pixelSize: 12 }
                        // An empty state that names the next step should offer
                        // it. This is where the removed floating button's job
                        // actually belonged.
                        GButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: appTheme.sp2
                            visible: win.boxes.length === 0 && win.hasDistrobox
                            theme: appTheme
                            kind: "filled"
                            text: i18n.t("sb.newWorkspace")
                            iconSource: "list-add"
                            enabled: !win.busy
                            onClicked: createDialog.open()
                        }
                    }
                }

                // activity log (collapsible-ish strip)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    visible: logArea.text.length > 0
                    color: appTheme.bgTop
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: appTheme.line }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: 4
                        RowLayout {
                            spacing: 7
                            Kirigami.Icon { source: "dialog-scripts"; Layout.preferredWidth: 14; Layout.preferredHeight: 14; color: appTheme.blue }
                            QQC2.Label { text: "Activity"; font.bold: true; font.pixelSize: 12; color: appTheme.textMid; Layout.fillWidth: true }
                            QQC2.BusyIndicator { running: win.busy; visible: win.busy; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
                            GButton { theme: appTheme; kind: "ghost"; text: "Clear"; onClicked: logArea.clear() }
                        }
                        QQC2.ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            QQC2.TextArea {
                                id: logArea
                                readOnly: true; wrapMode: Text.Wrap
                                color: appTheme.textMid; font.family: appTheme.mono; font.pixelSize: 12
                                background: null
                            }
                        }
                    }
                }
            }
        }

        // The floating action button is gone. It was the THIRD control on
        // this screen opening the create dialog, it is a phone pattern in a
        // desktop window, and it sat on top of the last row of the list.
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

                QQC2.Label { text: "Name"; color: appTheme.textMid; font.pixelSize: 12 }
                QQC2.TextField {
                    id: createName
                    Layout.fillWidth: true
                    placeholderText: "e.g. my-api"
                    enabled: !win.busy
                    color: appTheme.textHi
                    placeholderTextColor: appTheme.textLo
                    selectedTextColor: appTheme.white
                    selectionColor: appTheme.a(appTheme.green, 0.72)
                    background: Rectangle {
                        radius: 9
                        color: appTheme.a(appTheme.textHi, 0.04)
                        border.width: 1
                        border.color: createName.activeFocus ? appTheme.a(appTheme.green, 0.6) : appTheme.line
                    }
                }

                QQC2.Label { text: "Stack"; color: appTheme.textMid; font.pixelSize: 12; Layout.topMargin: Kirigami.Units.smallSpacing }

                Repeater {
                    model: win.templates
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        radius: 9
                        implicitHeight: tRow.implicitHeight + Kirigami.Units.largeSpacing
                        color: tMa.containsMouse || win.selTpl === index ? appTheme.a(appTheme.green, 0.12) : appTheme.a(appTheme.textHi, 0.04)
                        border.width: 1
                        border.color: win.selTpl === index ? appTheme.a(appTheme.green, 0.6) : appTheme.line
                        ColumnLayout {
                            id: tRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: 1
                            QQC2.Label {
                                text: (win.selTpl === index ? "✓ " : "") + modelData.label
                                color: win.selTpl === index ? appTheme.greenBright : appTheme.textHi
                                font.bold: win.selTpl === index
                            }
                            QQC2.Label { Layout.fillWidth: true; text: modelData.hint; color: appTheme.textLo; font.pixelSize: 11; wrapMode: Text.WordWrap }
                        }
                        MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.selTpl = index }
                    }
                }

                GButton {
                    theme: appTheme; kind: "filled"; text: "Create workspace"; iconSource: "list-add"
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
