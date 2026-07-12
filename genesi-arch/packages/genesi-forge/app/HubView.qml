/*
 * Genesi Forge — the project hub (home). Left rail on the window background;
 * the main content lives inside a rounded, slightly-darker gradient panel
 * (Forge v2 mock) with extra top padding. Header row keeps the title on the
 * left and right-aligns the search field + Import button.
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

        // ── Sidebar (on the window background) ─────────────────────────
        Item {
            Layout.preferredWidth: 248
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 16
                    spacing: 12
                    Rectangle {
                        width: 42; height: 42; radius: 12
                        color: root.theme.a(root.theme.green, 0.14)
                        border.width: 1; border.color: root.theme.a(root.theme.green, 0.4)
                        Kirigami.Icon { anchors.centerIn: parent; source: "genesi-forge"; width: 25; height: 25; color: root.theme.greenBright }
                    }
                    ColumnLayout {
                        spacing: 0
                        QQC2.Label { text: "Genesi Forge"; color: root.theme.textHi
                            font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                        QQC2.Label { text: "Your projects, unified."; color: root.theme.textLo; font.pixelSize: 11 }
                    }
                }

                Repeater {
                    model: [
                        { key: "all",          label: "Projects",     icon: "folder" },
                        { key: "recent",       label: "Recent",       icon: "clock" },
                        { key: "starred",      label: "Starred",      icon: "star" },
                        { key: "templates",    label: "Templates",    icon: "layout-grid" },
                        { key: "integrations", label: "Integrations", icon: "cloud" },
                        { key: "settings",     label: "Settings",     icon: "sliders" }
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

                FCard {
                    theme: root.theme
                    Layout.fillWidth: true; implicitHeight: 52
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 10
                        Rectangle { width: 8; height: 8; radius: 4; color: root.theme.greenBright }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            QQC2.Label { text: "Git service"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                            QQC2.Label { text: "Connected"; color: root.theme.textMid; font.pixelSize: 11 }
                        }
                        FIcon { name: "chevron-right"; size: 14; color: root.theme.textLo }
                    }
                }
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true; implicitHeight: 56
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: root.theme.a(root.theme.green, 0.2)
                            border.width: 1; border.color: root.theme.a(root.theme.green, 0.4)
                            QQC2.Label { anchors.centerIn: parent; text: "G"; color: root.theme.greenBright; font.bold: true; font.pixelSize: 14 }
                        }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            QQC2.Label { text: "dev.genesi"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                            QQC2.Label { text: "Developer"; color: root.theme.textMid; font.pixelSize: 11 }
                        }
                        FIcon { name: "chevron-down"; size: 14; color: root.theme.textLo }
                    }
                }
            }
        }

        // ── Content panel (rounded card, darker gradient, top-heavy padding) ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: panel
                anchors.fill: parent
                anchors.topMargin: 26; anchors.rightMargin: 12; anchors.bottomMargin: 12
                radius: 18
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.theme.panelTop }
                    GradientStop { position: 1.0; color: root.theme.panelBot }
                }
                border.width: 1
                border.color: root.theme.line
                clip: true

                QQC2.ScrollView {
                    id: mainScroll
                    anchors.fill: parent
                    anchors.topMargin: 30      // bigger top padding (mock)
                    anchors.leftMargin: 26
                    anchors.rightMargin: 18    // room for the scrollbar
                    anchors.bottomMargin: 20
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: mainScroll.availableWidth - 8
                        spacing: 20

                        // Header — title left, search + import right-aligned
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            ColumnLayout {
                                spacing: 3
                                QQC2.Label { text: "Projects"; color: root.theme.textHi
                                    font.family: root.theme.display; font.pixelSize: 28; font.bold: true }
                                QQC2.Label { text: "All your repositories in one place."; color: root.theme.textMid; font.pixelSize: 13 }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 280; Layout.preferredHeight: 42
                                Layout.alignment: Qt.AlignVCenter
                                radius: 10; color: root.theme.card
                                border.width: 1; border.color: root.theme.lineHi
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 13; anchors.rightMargin: 10; spacing: 9
                                    FIcon { name: "search"; size: 15; color: root.theme.textMid }
                                    QQC2.TextField {
                                        Layout.fillWidth: true; background: null
                                        placeholderText: "Search projects..."
                                        color: root.theme.textHi; placeholderTextColor: root.theme.textLo
                                        selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                        onTextChanged: root.query = text
                                    }
                                    Rectangle {
                                        width: kbd.implicitWidth + 12; height: 22; radius: 5
                                        color: root.theme.cardHi; border.width: 1; border.color: root.theme.line
                                        QQC2.Label { id: kbd; anchors.centerIn: parent; text: "Ctrl K"; color: root.theme.textLo; font.pixelSize: 10 }
                                    }
                                }
                            }
                            // Import Project — white text, "+" AFTER the text
                            Rectangle {
                                Layout.preferredHeight: 42
                                Layout.preferredWidth: importRow.implicitWidth + 34
                                Layout.alignment: Qt.AlignVCenter
                                radius: 10
                                color: importMa.containsMouse ? Qt.lighter(root.theme.green, 1.12) : root.theme.green
                                Behavior on color { ColorAnimation { duration: 130 } }
                                RowLayout {
                                    id: importRow
                                    anchors.centerIn: parent
                                    spacing: 9
                                    QQC2.Label { text: "Import Project"; color: "#FFFFFF"; font.pixelSize: 14; font.bold: true }
                                    FIcon { name: "plus"; size: 16; color: "#FFFFFF" }
                                }
                                MouseArea { id: importMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: folderDialog.open() }
                            }
                        }

                        // Stat tiles
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            StatTile { theme: root.theme; icon: "folder";     accent: root.theme.green;  value: String(root.stats.total);   label: "Total Projects" }
                            StatTile { theme: root.theme; icon: "git-branch"; accent: root.theme.purple; value: String(root.stats.git);     label: "Git Repositories" }
                            StatTile { theme: root.theme; icon: "star";       accent: root.theme.blue;   value: String(root.stats.starred); label: "Starred" }
                            StatTile { theme: root.theme; icon: "clock";      accent: root.theme.turbo;  value: String(root.stats.recent);  label: "Recently Opened" }
                        }

                        // Section header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            QQC2.Label {
                                text: root.filter === "starred" ? "Starred Projects"
                                    : root.filter === "recent" ? "Recently Opened"
                                    : root.filter === "templates" ? "Templates"
                                    : root.filter === "integrations" ? "Integrations"
                                    : root.filter === "settings" ? "Settings" : "Discovered Projects"
                                color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 18; font.bold: true
                            }
                            Rectangle { width: 7; height: 7; radius: 4; color: root.theme.greenBright; visible: root.isProjectList }
                            QQC2.Label {
                                visible: root.isProjectList
                                text: root.stats.git + " git repositories found"
                                color: root.theme.textMid; font.pixelSize: 13
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: root.isProjectList
                                width: 32; height: 32; radius: 9
                                color: refreshMa.containsMouse ? root.theme.cardHi : "transparent"
                                FIcon {
                                    anchors.centerIn: parent; name: "refresh-cw"; size: 15
                                    color: root.busy ? root.theme.greenBright : root.theme.textMid
                                    RotationAnimation on rotation {
                                        running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900
                                    }
                                }
                                MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: backend.refresh() }
                            }
                        }

                        // Project grid
                        GridLayout {
                            id: grid
                            visible: root.isProjectList
                            Layout.fillWidth: true
                            columnSpacing: 14; rowSpacing: 14
                            columns: Math.max(1, Math.min(4, Math.floor((mainScroll.availableWidth - 8) / 268)))

                            Repeater {
                                model: root.visibleProjects()
                                delegate: ProjectCard {
                                    theme: root.theme
                                    project: modelData
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 208
                                    onOpened: root.openProject(modelData)
                                    onStarToggled: backend.toggleStar(modelData.path)
                                }
                            }
                            ImportCard {
                                theme: root.theme
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 208
                                onBrowse: folderDialog.open()
                            }
                        }

                        // ── Templates ───────────────────────────────────
                        GridLayout {
                            visible: root.filter === "templates"
                            Layout.fillWidth: true
                            columnSpacing: 14; rowSpacing: 14
                            columns: Math.max(1, Math.min(3, Math.floor((mainScroll.availableWidth - 8) / 300)))
                            Repeater {
                                model: [
                                    { name: "Next.js App",  desc: "React framework with SSR & routing", kind: "next",    color: "#E6EDF3", url: "https://nextjs.org/docs/getting-started/installation" },
                                    { name: "React + Vite", desc: "Fast SPA with hot reload",            kind: "react",   color: "#61DAFB", url: "https://vite.dev/guide/" },
                                    { name: "Python API",   desc: "FastAPI service, batteries included", kind: "python",  color: "#3776AB", url: "https://fastapi.tiangolo.com/#installation" },
                                    { name: "Node API",     desc: "Express REST server",                 kind: "node",    color: "#5FA04E", url: "https://expressjs.com/en/starter/generator.html" },
                                    { name: "Static Site",  desc: "Plain HTML/CSS/JS starter",           kind: "html",    color: "#E34F26", url: "https://developer.mozilla.org/en-US/docs/Learn_web_development" },
                                    { name: "Flutter App",  desc: "Cross-platform mobile app",           kind: "flutter", color: "#02569B", url: "https://docs.flutter.dev/get-started/install" }
                                ]
                                delegate: FCard {
                                    theme: root.theme
                                    interactive: true
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 150
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 16; spacing: 6
                                        TechLogo { kind: modelData.kind; color: modelData.color; size: 38 }
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

                        // ── Integrations ────────────────────────────────
                        ColumnLayout {
                            visible: root.filter === "integrations"
                            Layout.fillWidth: true
                            spacing: 10
                            Repeater {
                                model: [
                                    { name: "GitHub",  icon: "github", url: "https://github.com",            provider: true },
                                    { name: "Vercel",  icon: "zap",    url: "https://vercel.com/dashboard",  provider: false },
                                    { name: "Netlify", icon: "globe",  url: "https://app.netlify.com",       provider: false },
                                    { name: "Docker",  icon: "box",    url: "",                              provider: false },
                                    { name: "Render",  icon: "cloud",  url: "https://dashboard.render.com",  provider: false },
                                    { name: "Railway", icon: "cloud",  url: "https://railway.app/dashboard", provider: false },
                                    { name: "Fly.io",  icon: "cloud",  url: "https://fly.io/dashboard",      provider: false }
                                ]
                                delegate: FCard {
                                    id: intRow
                                    theme: root.theme
                                    Layout.fillWidth: true; implicitHeight: 64
                                    readonly property int used: modelData.provider ? root.countProvider("GitHub") : root.countIntegration(modelData.name)
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 14
                                        Rectangle {
                                            width: 38; height: 38; radius: 11
                                            color: root.theme.a(root.theme.green, 0.13)
                                            FIcon { anchors.centerIn: parent; name: modelData.icon; size: 19; color: root.theme.greenBright }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 1
                                            QQC2.Label { text: modelData.name; color: root.theme.textHi; font.pixelSize: 14; font.bold: true }
                                            QQC2.Label {
                                                text: intRow.used > 0 ? (intRow.used + " project" + (intRow.used > 1 ? "s" : "") + " connected") : "Not detected in your projects"
                                                color: intRow.used > 0 ? root.theme.greenBright : root.theme.textLo; font.pixelSize: 12
                                            }
                                        }
                                        GButton { visible: modelData.url !== ""; theme: root.theme; kind: "tonal"; text: "Open dashboard"; iconSource: "icons/external-link.svg"
                                            onClicked: backend.openUrl(modelData.url) }
                                    }
                                }
                            }
                        }

                        // ── Settings ────────────────────────────────────
                        ColumnLayout {
                            visible: root.filter === "settings"
                            Layout.fillWidth: true
                            spacing: 12

                            FCard {
                                theme: root.theme
                                Layout.fillWidth: true; implicitHeight: maintCol.implicitHeight + 32
                                ColumnLayout {
                                    id: maintCol
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                                    spacing: 10
                                    QQC2.Label { text: "Maintenance"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                                    Repeater {
                                        model: [
                                            { label: "Rescan projects",         desc: "Walk your home folder for git repos again", act: "rescan",  btn: "Rescan" },
                                            { label: "Clear recent history",    desc: "Forget which projects you opened recently", act: "recents", btn: "Clear" },
                                            { label: "Clear stars",             desc: "Un-star every project",                     act: "stars",   btn: "Clear" },
                                            { label: "Clear imported projects", desc: "Remove manually-imported folders",          act: "imports", btn: "Clear" }
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

                            FCard {
                                theme: root.theme
                                Layout.fillWidth: true; implicitHeight: aboutCol.implicitHeight + 32
                                ColumnLayout {
                                    id: aboutCol
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                                    spacing: 4
                                    QQC2.Label { text: "About"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                                    QQC2.Label { text: "Genesi Forge 2.1 — the Genesi project hub."; color: root.theme.textMid; font.pixelSize: 12 }
                                    QQC2.Label { text: "Local-first. Git stays on your machine; GitHub uses your gh session."; color: root.theme.textLo; font.pixelSize: 12 }
                                }
                            }
                        }

                        // Drag-and-drop import strip
                        FCard {
                            visible: root.isProjectList
                            theme: root.theme
                            Layout.fillWidth: true
                            implicitHeight: 72
                            border.color: dropArea.containsDrag ? root.theme.a(root.theme.green, 0.5) : root.theme.line
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 14
                                Rectangle {
                                    width: 38; height: 38; radius: 11
                                    color: root.theme.a(root.theme.green, 0.12)
                                    FIcon { anchors.centerIn: parent; name: "folder-plus"; size: 19; color: root.theme.greenBright }
                                }
                                ColumnLayout {
                                    spacing: 1; Layout.fillWidth: true
                                    QQC2.Label { text: "Drag and drop a folder here to import"; color: root.theme.textHi; font.pixelSize: 14; font.bold: true }
                                    QQC2.Label { text: "We'll check if it's a git repository"; color: root.theme.textLo; font.pixelSize: 12 }
                                }
                                GButton { theme: root.theme; kind: "tonal"; text: "Browse"; iconSource: "icons/folder.svg"; onClicked: folderDialog.open() }
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

                        Item { Layout.preferredHeight: 4 }
                    }
                }
            }
        }
    }
}
