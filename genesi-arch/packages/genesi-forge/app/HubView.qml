/*
 * Genesi Forge — the project hub (home). Left rail with workspace navigation +
 * account footer; main area with the header, stat tiles, and the discovered-
 * project grid (each card opens the project workspace / Forge Canvas).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property var projects: []
    property var stats: ({ total: 0, git: 0, starred: 0, recent: 0 })
    property bool busy: false
    property string filter: "all"
    property string query: ""
    signal openProject(var project)

    function visibleProjects() {
        var out = []
        var q = query.toLowerCase()
        for (var i = 0; i < projects.length; i++) {
            var p = projects[i]
            if (filter === "recent" && !(p.lastOpened > 0)) continue
            if (filter === "starred" && !p.starred) continue
            var hay = (p.name + " " + p.path + " " + p.stack + " " + p.branch).toLowerCase()
            if (q && hay.indexOf(q) < 0) continue
            out.push(p)
        }
        return out
    }

    readonly property bool isProjectList: filter === "all" || filter === "recent" || filter === "starred"

    function countProvider(name) {
        var c = 0
        for (var i = 0; i < projects.length; i++) if (projects[i].provider === name) c++
        return c
    }
    function countIntegration(name) {
        var c = 0
        for (var i = 0; i < projects.length; i++) {
            var ints = projects[i].integrations || []
            for (var j = 0; j < ints.length; j++) if (ints[j].name === name) { c++; break }
        }
        return c
    }

    FolderDialog {
        id: folderDialog
        title: "Choose a project folder"
        onAccepted: {
            var p = selectedFolder.toString().replace(/^file:\/\//, "")
            if (p) backend.importProject(decodeURIComponent(p))
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sidebar ────────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 264
            Layout.fillHeight: true
            color: root.theme.card

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 14
                    spacing: 12
                    Rectangle {
                        width: 44; height: 44; radius: 12
                        color: root.theme.a(root.theme.green, 0.14)
                        border.width: 1; border.color: root.theme.a(root.theme.green, 0.4)
                        Kirigami.Icon { anchors.centerIn: parent; source: "genesi-forge"; width: 26; height: 26; color: root.theme.greenBright }
                    }
                    ColumnLayout {
                        spacing: 0
                        QQC2.Label { text: "Genesi Forge"; color: root.theme.textHi
                            font.family: root.theme.display; font.pixelSize: 17; font.bold: true }
                        QQC2.Label { text: "Your projects, unified."; color: root.theme.textLo; font.pixelSize: 11 }
                    }
                }

                Repeater {
                    model: [
                        { key: "all",          label: "Projects",     icon: "folder-symbolic" },
                        { key: "recent",       label: "Recent",       icon: "appointment-new" },
                        { key: "starred",      label: "Starred",      icon: "rating" },
                        { key: "templates",    label: "Templates",    icon: "folder-templates-symbolic" },
                        { key: "integrations", label: "Integrations", icon: "cloud-upload" },
                        { key: "settings",     label: "Settings",     icon: "settings-configure" }
                    ]
                    delegate: NavItem {
                        theme: root.theme
                        icon: modelData.icon
                        label: modelData.label
                        active: root.filter === modelData.key
                        onClicked: root.filter = modelData.key
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 54
                    radius: 12; color: root.theme.cardHi
                    border.width: 1; border.color: root.theme.line
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 10
                        Rectangle { width: 9; height: 9; radius: 5; color: root.theme.greenBright }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            QQC2.Label { text: "Git service"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                            QQC2.Label { text: "Connected"; color: root.theme.textMid; font.pixelSize: 11 }
                        }
                        Kirigami.Icon { source: "arrow-right"; width: 15; height: 15; color: root.theme.textLo }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 58
                    radius: 12; color: root.theme.cardHi
                    border.width: 1; border.color: root.theme.line
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                        Rectangle {
                            width: 34; height: 34; radius: 17
                            color: root.theme.a(root.theme.green, 0.2)
                            border.width: 1; border.color: root.theme.a(root.theme.green, 0.4)
                            QQC2.Label { anchors.centerIn: parent; text: "G"; color: root.theme.greenBright; font.bold: true; font.pixelSize: 15 }
                        }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            QQC2.Label { text: "dev.genesi"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                            QQC2.Label { text: "Developer"; color: root.theme.textMid; font.pixelSize: 11 }
                        }
                        Kirigami.Icon { source: "arrow-down"; width: 15; height: 15; color: root.theme.textLo }
                    }
                }
            }
        }
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.theme.line }

        // ── Main content ───────────────────────────────────────────────
        QQC2.ScrollView {
            id: mainScroll
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: mainScroll.availableWidth
                spacing: 22

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30; Layout.topMargin: 28
                    ColumnLayout {
                        spacing: 3; Layout.fillWidth: true
                        QQC2.Label { text: "Projects"; color: root.theme.textHi
                            font.family: root.theme.display; font.pixelSize: 30; font.bold: true }
                        QQC2.Label { text: "All your repositories in one place."; color: root.theme.textMid; font.pixelSize: 14 }
                    }
                    Rectangle {
                        Layout.preferredWidth: 300; Layout.preferredHeight: 42
                        radius: 10; color: root.theme.cardHi
                        border.width: 1; border.color: root.theme.lineHi
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 13; anchors.rightMargin: 10; spacing: 9
                            Kirigami.Icon { source: "search"; width: 16; height: 16; color: root.theme.textMid }
                            QQC2.TextField {
                                Layout.fillWidth: true; background: null
                                placeholderText: "Search projects..."
                                color: root.theme.textHi; placeholderTextColor: root.theme.textLo
                                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                onTextChanged: root.query = text
                            }
                            Rectangle {
                                width: kbd.implicitWidth + 12; height: 22; radius: 5
                                color: root.theme.card; border.width: 1; border.color: root.theme.line
                                QQC2.Label { id: kbd; anchors.centerIn: parent; text: "Ctrl K"; color: root.theme.textLo; font.pixelSize: 10 }
                            }
                        }
                    }
                    GButton { theme: root.theme; kind: "filled"; text: "Import Project"; iconSource: "list-add"; onClicked: folderDialog.open() }
                }

                // Stat tiles
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    spacing: 16
                    StatTile { theme: root.theme; icon: "folder-symbolic";   accent: root.theme.green;  value: String(root.stats.total);   label: "Total Projects" }
                    StatTile { theme: root.theme; icon: "code-context";      accent: root.theme.purple; value: String(root.stats.git);     label: "Git Repositories" }
                    StatTile { theme: root.theme; icon: "rating";            accent: root.theme.blue;   value: String(root.stats.starred); label: "Starred" }
                    StatTile { theme: root.theme; icon: "appointment-new";   accent: root.theme.turbo;  value: String(root.stats.recent);  label: "Recently Opened" }
                }

                // Section header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    spacing: 12
                    QQC2.Label {
                        text: root.filter === "starred" ? "Starred Projects"
                            : root.filter === "recent" ? "Recently Opened"
                            : root.filter === "templates" ? "Templates"
                            : root.filter === "integrations" ? "Integrations"
                            : root.filter === "settings" ? "Settings" : "Discovered Projects"
                        color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 19; font.bold: true
                    }
                    Rectangle { width: 8; height: 8; radius: 4; color: root.theme.greenBright; visible: root.isProjectList }
                    QQC2.Label {
                        visible: root.isProjectList
                        text: root.stats.git + " git repositories found"
                        color: root.theme.textMid; font.pixelSize: 13
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: root.isProjectList
                        width: 34; height: 34; radius: 9
                        color: refreshMa.containsMouse ? root.theme.cardHi : "transparent"
                        Kirigami.Icon {
                            anchors.centerIn: parent; source: "view-refresh"; width: 17; height: 17
                            color: root.busy ? root.theme.greenBright : root.theme.textMid
                            RotationAnimation on rotation {
                                running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900
                            }
                        }
                        MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: backend.refresh() }
                    }
                }

                // Project grid  (or a placeholder for Templates/Integrations/Settings)
                GridLayout {
                    id: grid
                    visible: root.isProjectList
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    columnSpacing: 16; rowSpacing: 16
                    columns: Math.max(1, Math.min(4, Math.floor((root.width - 264 - 60) / 260)))

                    Repeater {
                        model: root.visibleProjects()
                        delegate: ProjectCard {
                            theme: root.theme
                            project: modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            onOpened: root.openProject(modelData)
                            onStarToggled: backend.toggleStar(modelData.path)
                        }
                    }
                    ImportCard {
                        theme: root.theme
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        onBrowse: folderDialog.open()
                    }
                }

                // ── Templates ───────────────────────────────────────────────
                GridLayout {
                    visible: root.filter === "templates"
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    columnSpacing: 16; rowSpacing: 16
                    columns: Math.max(1, Math.min(3, Math.floor((root.width - 264 - 60) / 300)))
                    Repeater {
                        model: [
                            { name: "Next.js App",    desc: "React framework with SSR & routing", kind: "next",    color: "#E6EDF3", url: "https://nextjs.org/docs/getting-started/installation" },
                            { name: "React + Vite",   desc: "Fast SPA with hot reload",            kind: "react",   color: "#61DAFB", url: "https://vite.dev/guide/" },
                            { name: "Python API",     desc: "FastAPI service, batteries included", kind: "python",  color: "#3776AB", url: "https://fastapi.tiangolo.com/#installation" },
                            { name: "Node API",       desc: "Express REST server",                 kind: "node",    color: "#5FA04E", url: "https://expressjs.com/en/starter/generator.html" },
                            { name: "Static Site",    desc: "Plain HTML/CSS/JS starter",           kind: "html",    color: "#E34F26", url: "https://developer.mozilla.org/en-US/docs/Learn_web_development" },
                            { name: "Flutter App",    desc: "Cross-platform mobile app",           kind: "flutter", color: "#02569B", url: "https://docs.flutter.dev/get-started/install" }
                        ]
                        delegate: GlassCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 140
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 6
                                TechLogo { kind: modelData.kind; color: modelData.color; size: 40 }
                                Item { Layout.fillHeight: true }
                                QQC2.Label { text: modelData.name; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                                QQC2.Label { text: modelData.desc; color: root.theme.textLo; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                QQC2.Label {
                                    text: "Get started →"; color: root.theme.greenBright; font.pixelSize: 13; font.bold: true; Layout.topMargin: 4
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: backend.openUrl(modelData.url) }
                                }
                            }
                        }
                    }
                }

                // ── Integrations ────────────────────────────────────────────
                ColumnLayout {
                    visible: root.filter === "integrations"
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    spacing: 12
                    Repeater {
                        model: [
                            { name: "GitHub",  icon: "github",        url: "https://github.com",                 provider: true },
                            { name: "Vercel",  icon: "cloud-upload",  url: "https://vercel.com/dashboard",       provider: false },
                            { name: "Netlify", icon: "cloud-upload",  url: "https://app.netlify.com",            provider: false },
                            { name: "Docker",  icon: "docker",        url: "",                                   provider: false },
                            { name: "Render",  icon: "cloud-upload",  url: "https://dashboard.render.com",       provider: false },
                            { name: "Railway", icon: "cloud-upload",  url: "https://railway.app/dashboard",      provider: false },
                            { name: "Fly.io",  icon: "cloud-upload",  url: "https://fly.io/dashboard",           provider: false }
                        ]
                        delegate: Rectangle {
                            id: intRow
                            Layout.fillWidth: true; implicitHeight: 66; radius: 12
                            color: root.theme.card; border.width: 1; border.color: root.theme.line
                            readonly property int used: modelData.provider ? root.countProvider("GitHub") : root.countIntegration(modelData.name)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 14
                                Rectangle {
                                    width: 40; height: 40; radius: 11
                                    color: root.theme.a(root.theme.green, 0.14)
                                    Kirigami.Icon { anchors.centerIn: parent; source: modelData.icon; width: 22; height: 22; color: root.theme.greenBright }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    QQC2.Label { text: modelData.name; color: root.theme.textHi; font.pixelSize: 14; font.bold: true }
                                    QQC2.Label {
                                        text: intRow.used > 0 ? (intRow.used + " project" + (intRow.used > 1 ? "s" : "") + " connected") : "Not detected in your projects"
                                        color: intRow.used > 0 ? root.theme.greenBright : root.theme.textLo; font.pixelSize: 12
                                    }
                                }
                                GButton { visible: modelData.url !== ""; theme: root.theme; kind: "tonal"; text: "Open dashboard"; iconSource: "internet-web-browser"
                                    onClicked: backend.openUrl(modelData.url) }
                            }
                        }
                    }
                }

                // ── Settings ────────────────────────────────────────────────
                ColumnLayout {
                    visible: root.filter === "settings"
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30
                    spacing: 12

                    GlassCard {
                        Layout.fillWidth: true; implicitHeight: maintCol.implicitHeight + 32
                        ColumnLayout {
                            id: maintCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                            spacing: 10
                            QQC2.Label { text: "Maintenance"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                            Repeater {
                                model: [
                                    { label: "Rescan projects",          desc: "Walk your home folder for git repos again", act: "rescan",  btn: "Rescan" },
                                    { label: "Clear recent history",      desc: "Forget which projects you opened recently", act: "recents", btn: "Clear" },
                                    { label: "Clear stars",               desc: "Un-star every project",                     act: "stars",   btn: "Clear" },
                                    { label: "Clear imported projects",   desc: "Remove manually-imported folders",          act: "imports", btn: "Clear" }
                                ]
                                delegate: RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        QQC2.Label { text: modelData.label; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                                        QQC2.Label { text: modelData.desc; color: root.theme.textLo; font.pixelSize: 11 }
                                    }
                                    GButton {
                                        theme: root.theme; kind: modelData.act === "rescan" ? "tonal" : "ghost"; text: modelData.btn
                                        onClicked: modelData.act === "rescan" ? backend.refresh() : backend.clearData(modelData.act)
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        Layout.fillWidth: true; implicitHeight: aboutCol.implicitHeight + 32
                        ColumnLayout {
                            id: aboutCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                            spacing: 4
                            QQC2.Label { text: "About"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                            QQC2.Label { text: "Genesi Forge 2.0 — the Genesi project hub."; color: root.theme.textMid; font.pixelSize: 12 }
                            QQC2.Label { text: "Local-first. Git stays on your machine; GitHub uses your gh session."; color: root.theme.textLo; font.pixelSize: 12 }
                        }
                    }
                }

                // Drag-and-drop import strip
                Rectangle {
                    visible: root.isProjectList
                    Layout.fillWidth: true
                    Layout.leftMargin: 30; Layout.rightMargin: 30; Layout.bottomMargin: 28
                    Layout.preferredHeight: 74
                    radius: 14
                    color: dropArea.containsDrag ? root.theme.a(root.theme.green, 0.08) : root.theme.card
                    border.width: 1; border.color: dropArea.containsDrag ? root.theme.a(root.theme.green, 0.5) : root.theme.line
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 14
                        Rectangle {
                            width: 40; height: 40; radius: 11
                            color: root.theme.a(root.theme.green, 0.12)
                            Kirigami.Icon { anchors.centerIn: parent; source: "folder-add"; width: 20; height: 20; color: root.theme.greenBright }
                        }
                        ColumnLayout {
                            spacing: 1; Layout.fillWidth: true
                            QQC2.Label { text: "Drag and drop a folder here to import"; color: root.theme.textHi; font.pixelSize: 14; font.bold: true }
                            QQC2.Label { text: "We'll check if it's a git repository"; color: root.theme.textLo; font.pixelSize: 12 }
                        }
                        GButton { theme: root.theme; kind: "tonal"; text: "Browse"; iconSource: "folder-open"; onClicked: folderDialog.open() }
                    }
                    DropArea {
                        id: dropArea
                        anchors.fill: parent
                        onDropped: function(drop) {
                            if (drop.hasUrls && drop.urls.length > 0) {
                                var p = drop.urls[0].toString().replace(/^file:\/\//, "")
                                backend.importProject(decodeURIComponent(p))
                            }
                        }
                    }
                }
            }
        }
    }
}
