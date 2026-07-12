/*
 * Genesi Forge — project workspace shell (v2 mock): a project-scoped sidebar
 * (PROJECTS · CURRENT PROJECT · GIT · TOOLS) on the window background, and the
 * active page inside the rounded content panel. Overview is the full git
 * dashboard; Commits/Branches/PRs/Stash/Tags/Remotes are focused pages; Forge
 * Canvas hosts the workflow builder; Terminal is the embedded console.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property var project
    property string page: "overview"
    signal back()
    signal toast(string msg)

    property var prs: []
    property var pageBranches: []
    property var pageStashes: []
    property var pageTags: []
    property var pageRemotes: []
    property var pageLog: []

    function loadPage(p) {
        if (!project) return
        try {
            if (p === "commits") pageLog = JSON.parse(backend.gitLog(project.path, 100))
            else if (p === "branches") pageBranches = JSON.parse(backend.gitBranches(project.path))
            else if (p === "stash") pageStashes = JSON.parse(backend.gitStashList(project.path))
            else if (p === "tags") pageTags = JSON.parse(backend.gitTags(project.path))
            else if (p === "remotes") pageRemotes = JSON.parse(backend.gitRemotes(project.path))
            else if (p === "prs") backend.loadPRs(project.slug)
        } catch (e) {}
    }
    onPageChanged: loadPage(page)

    Connections {
        target: backend
        function onPrsLoaded(raw) {
            try { root.prs = JSON.parse(raw) } catch (e) { root.prs = [] }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ═══ Sidebar ═══
        Item {
            Layout.preferredWidth: 224
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4; Layout.bottomMargin: 12
                    spacing: 10
                    Rectangle {
                        width: 36; height: 36; radius: 10
                        color: root.theme.a(root.theme.green, 0.14)
                        border.width: 1; border.color: root.theme.a(root.theme.green, 0.4)
                        Kirigami.Icon { anchors.centerIn: parent; source: "genesi-forge"; width: 21; height: 21; color: root.theme.greenBright }
                    }
                    QQC2.Label { text: "Genesi Forge"; color: root.theme.textHi
                        font.family: root.theme.display; font.pixelSize: 15; font.bold: true }
                }

                QQC2.Label { text: "PROJECTS"; color: root.theme.textLo; font.pixelSize: 9; font.bold: true; Layout.leftMargin: 4 }
                NavItem { theme: root.theme; compact: true; icon: "folder";      label: "Projects";     onClicked: root.back() }
                NavItem { theme: root.theme; compact: true; icon: "zap";         label: "Forge Canvas"; active: root.page === "canvas"; onClicked: root.page = "canvas" }
                NavItem { theme: root.theme; compact: true; icon: "layout-grid"; label: "Repositories"; onClicked: root.back() }

                QQC2.Label { text: "CURRENT PROJECT"; color: root.theme.textLo; font.pixelSize: 9; font.bold: true; Layout.leftMargin: 4; Layout.topMargin: 10 }
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true
                    implicitHeight: 52
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 9
                        TechLogo { kind: root.project ? root.project.stackKind : "git"
                            color: root.project ? root.project.stackColor : "#888"; size: 30 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            QQC2.Label { text: root.project ? root.project.name : ""; color: root.theme.textHi
                                font.pixelSize: 12; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            QQC2.Label { text: root.project ? root.project.shortPath : ""; color: root.theme.textLo
                                font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        }
                    }
                }

                QQC2.Label { text: "GIT"; color: root.theme.textLo; font.pixelSize: 9; font.bold: true; Layout.leftMargin: 4; Layout.topMargin: 10 }
                Repeater {
                    model: [
                        { key: "overview", label: "Overview",      icon: "layout-grid" },
                        { key: "commits",  label: "Commits",       icon: "git-commit" },
                        { key: "branches", label: "Branches",      icon: "git-branch" },
                        { key: "prs",      label: "Pull Requests", icon: "git-pull-request" },
                        { key: "stash",    label: "Stash",         icon: "archive" },
                        { key: "tags",     label: "Tags",          icon: "tag" },
                        { key: "remotes",  label: "Remotes",       icon: "globe" }
                    ]
                    delegate: NavItem {
                        theme: root.theme; compact: true
                        icon: modelData.icon; label: modelData.label
                        active: root.page === modelData.key
                        onClicked: root.page = modelData.key
                    }
                }

                QQC2.Label { text: "TOOLS"; color: root.theme.textLo; font.pixelSize: 9; font.bold: true; Layout.leftMargin: 4; Layout.topMargin: 10 }
                NavItem { theme: root.theme; compact: true; icon: "terminal"; label: "Terminal"; active: root.page === "terminal"; onClicked: root.page = "terminal" }
                NavItem { theme: root.theme; compact: true; icon: "sliders";  label: "Settings"; active: root.page === "settings"; onClicked: root.page = "settings" }

                Item { Layout.fillHeight: true }

                FCard {
                    theme: root.theme
                    Layout.fillWidth: true; implicitHeight: 50
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 9
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: root.theme.a(root.theme.green, 0.2)
                            QQC2.Label { anchors.centerIn: parent; text: "G"; color: root.theme.greenBright; font.bold: true; font.pixelSize: 12 }
                        }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            QQC2.Label { text: "dev.genesi"; color: root.theme.textHi; font.pixelSize: 12; font.bold: true }
                            QQC2.Label { text: "Developer"; color: root.theme.textMid; font.pixelSize: 10 }
                        }
                        FIcon { name: "chevron-right"; size: 12; color: root.theme.textLo }
                    }
                }
            }
        }

        // ═══ Content panel ═══
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
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

                StackLayout {
                    anchors.fill: parent
                    anchors.topMargin: 24        // bigger top padding
                    anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.bottomMargin: 16
                    currentIndex: {
                        var order = ["overview", "commits", "branches", "prs", "stash", "tags", "remotes", "canvas", "terminal", "settings"]
                        var i = order.indexOf(root.page)
                        return i < 0 ? 0 : i
                    }

                    // 0 — Overview (the mock git dashboard)
                    GitOverview {
                        theme: root.theme
                        project: root.project
                        onOpenBranches: { root.page = "branches" }
                    }

                    // 1 — Commits
                    ColumnLayout {
                        spacing: 12
                        QQC2.Label { text: "Commits"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true }
                        QQC2.ScrollView {
                            id: commitScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: commitScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.pageLog
                                    delegate: FCard {
                                        theme: root.theme
                                        Layout.fillWidth: true; implicitHeight: 54
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            Rectangle {
                                                width: 30; height: 30; radius: 15
                                                color: root.theme.a(root.theme.green, 0.15)
                                                QQC2.Label { anchors.centerIn: parent; text: modelData.author.charAt(0).toUpperCase()
                                                    color: root.theme.greenBright; font.pixelSize: 12; font.bold: true }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                QQC2.Label { text: modelData.subject; color: root.theme.textHi; font.pixelSize: 13; font.bold: true
                                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                                QQC2.Label { text: modelData.author + "  ·  " + modelData.ago; color: root.theme.textLo; font.pixelSize: 11 }
                                            }
                                            QQC2.Label { text: modelData.hash; color: root.theme.greenBright; font.family: root.theme.mono; font.pixelSize: 11 }
                                            GButton { theme: root.theme; kind: "ghost"; iconSource: "icons/copy.svg"; tooltip: "Copy hash"
                                                onClicked: backend.copyText(modelData.hash) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2 — Branches
                    ColumnLayout {
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Branches"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 240; Layout.preferredHeight: 38
                                radius: 9; color: root.theme.card; border.width: 1; border.color: root.theme.lineHi
                                QQC2.TextField {
                                    anchors.fill: parent; anchors.leftMargin: 12
                                    background: null
                                    placeholderText: "New branch name…"; placeholderTextColor: root.theme.textLo
                                    color: root.theme.textHi; font.pixelSize: 12
                                    selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                    onAccepted: if (text.trim() !== "") {
                                        backend.createBranch(root.project.path, text.trim()); text = ""; root.loadPage("branches")
                                    }
                                }
                            }
                        }
                        QQC2.ScrollView {
                            id: branchScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: branchScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.pageBranches
                                    delegate: FCard {
                                        theme: root.theme
                                        active: modelData.current
                                        Layout.fillWidth: true; implicitHeight: 52
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            FIcon { name: "git-branch"; size: 16
                                                color: modelData.current ? root.theme.greenBright : root.theme.textMid }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 0
                                                QQC2.Label { text: modelData.name; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                                                QQC2.Label { text: modelData.upstream ? ("tracks " + modelData.upstream) : "no upstream"
                                                    color: root.theme.textLo; font.pixelSize: 10 }
                                            }
                                            QQC2.Label { visible: modelData.current; text: "current"; color: root.theme.greenBright; font.pixelSize: 11; font.bold: true }
                                            GButton { theme: root.theme; kind: "tonal"; text: "Checkout"; visible: !modelData.current
                                                onClicked: { backend.checkout(root.project.path, modelData.name); root.loadPage("branches") } }
                                            GButton { theme: root.theme; kind: "danger"; iconSource: "icons/trash.svg"; tooltip: "Delete branch"
                                                visible: !modelData.current
                                                onClicked: { backend.deleteBranch(root.project.path, modelData.name); root.loadPage("branches") } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3 — Pull Requests
                    ColumnLayout {
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Pull Requests"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
                            GButton { theme: root.theme; kind: "filled"; text: "New PR"; iconSource: "icons/git-pull-request.svg"
                                enabled: root.project && root.project.web !== ""
                                onClicked: backend.openUrl(root.project.web + "/compare") }
                        }
                        QQC2.ScrollView {
                            id: prScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: prScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.prs
                                    delegate: FCard {
                                        theme: root.theme
                                        interactive: true
                                        Layout.fillWidth: true; implicitHeight: 56
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: backend.openUrl(modelData.url) }
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            FIcon { name: "git-pull-request"; size: 16; color: root.theme.greenBright }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 0
                                                QQC2.Label { text: "#" + modelData.number + "  " + modelData.title; color: root.theme.textHi
                                                    font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                                QQC2.Label { text: modelData.headRefName; color: root.theme.textLo; font.pixelSize: 11 }
                                            }
                                            Rectangle {
                                                width: stLbl.implicitWidth + 16; height: 22; radius: 6
                                                color: root.theme.a(modelData.state === "OPEN" ? root.theme.green : root.theme.purple, 0.14)
                                                QQC2.Label { id: stLbl; anchors.centerIn: parent; text: modelData.state
                                                    color: modelData.state === "OPEN" ? root.theme.greenBright : root.theme.purpleBright
                                                    font.pixelSize: 10; font.bold: true }
                                            }
                                        }
                                    }
                                }
                                QQC2.Label { visible: root.prs.length === 0; text: "No open pull requests (or gh is not authenticated)."
                                    color: root.theme.textLo; font.pixelSize: 12 }
                            }
                        }
                    }

                    // 4 — Stash
                    ColumnLayout {
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Stash"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
                            GButton { theme: root.theme; kind: "filled"; text: "Stash Changes"; iconSource: "icons/archive.svg"
                                onClicked: { backend.stashSave(root.project.path); root.loadPage("stash") } }
                        }
                        QQC2.ScrollView {
                            id: stashScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: stashScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.pageStashes
                                    delegate: FCard {
                                        theme: root.theme
                                        Layout.fillWidth: true; implicitHeight: 52
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            FIcon { name: "archive"; size: 15; color: root.theme.turboBright }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 0
                                                QQC2.Label { text: modelData.subject; color: root.theme.textHi; font.pixelSize: 13; font.bold: true
                                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                                QQC2.Label { text: modelData.ref; color: root.theme.textLo; font.family: root.theme.mono; font.pixelSize: 10 }
                                            }
                                            GButton { theme: root.theme; kind: "tonal"; text: "Pop"
                                                onClicked: { backend.stashPop(root.project.path, modelData.ref); root.loadPage("stash") } }
                                            GButton { theme: root.theme; kind: "danger"; iconSource: "icons/trash.svg"; tooltip: "Drop stash"
                                                onClicked: { backend.stashDrop(root.project.path, modelData.ref); root.loadPage("stash") } }
                                        }
                                    }
                                }
                                QQC2.Label { visible: root.pageStashes.length === 0; text: "No stashed changes."
                                    color: root.theme.textLo; font.pixelSize: 12 }
                            }
                        }
                    }

                    // 5 — Tags
                    ColumnLayout {
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Tags"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 220; Layout.preferredHeight: 38
                                radius: 9; color: root.theme.card; border.width: 1; border.color: root.theme.lineHi
                                QQC2.TextField {
                                    anchors.fill: parent; anchors.leftMargin: 12
                                    background: null
                                    placeholderText: "v1.0.0"; placeholderTextColor: root.theme.textLo
                                    color: root.theme.textHi; font.pixelSize: 12
                                    selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                    onAccepted: if (text.trim() !== "") {
                                        backend.createTag(root.project.path, text.trim()); text = ""; root.loadPage("tags")
                                    }
                                }
                            }
                        }
                        QQC2.ScrollView {
                            id: tagScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: tagScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.pageTags
                                    delegate: FCard {
                                        theme: root.theme
                                        Layout.fillWidth: true; implicitHeight: 46
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            FIcon { name: "tag"; size: 15; color: root.theme.blue }
                                            QQC2.Label { text: modelData; color: root.theme.textHi; font.family: root.theme.mono
                                                font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                                        }
                                    }
                                }
                                QQC2.Label { visible: root.pageTags.length === 0; text: "No tags yet — type a name above and press Enter."
                                    color: root.theme.textLo; font.pixelSize: 12 }
                            }
                        }
                    }

                    // 6 — Remotes
                    ColumnLayout {
                        spacing: 12
                        QQC2.Label { text: "Remotes"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true }
                        QQC2.ScrollView {
                            id: remoteScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth; clip: true
                            ColumnLayout {
                                width: remoteScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.pageRemotes
                                    delegate: FCard {
                                        theme: root.theme
                                        Layout.fillWidth: true; implicitHeight: 52
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                            FIcon { name: "globe"; size: 15; color: root.theme.greenBright }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 0
                                                QQC2.Label { text: modelData.name; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                                                QQC2.Label { text: modelData.url; color: root.theme.textLo; font.family: root.theme.mono
                                                    font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                            }
                                            GButton { theme: root.theme; kind: "ghost"; iconSource: "icons/copy.svg"; tooltip: "Copy URL"
                                                onClicked: backend.copyText(modelData.url) }
                                        }
                                    }
                                }
                                QQC2.Label { visible: root.pageRemotes.length === 0; text: "No remotes configured."
                                    color: root.theme.textLo; font.pixelSize: 12 }
                            }
                        }
                    }

                    // 7 — Forge Canvas
                    CanvasView {
                        theme: root.theme
                        project: root.project
                        onToast: function(msg) { root.toast(msg) }
                    }

                    // 8 — Terminal
                    ColumnLayout {
                        spacing: 12
                        QQC2.Label { text: "Terminal"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true }
                        ConsolePanel {
                            theme: root.theme
                            workdir: root.project ? root.project.path : ""
                            showHeader: false
                            Layout.fillWidth: true; Layout.fillHeight: true
                        }
                    }

                    // 9 — Settings
                    ColumnLayout {
                        spacing: 12
                        QQC2.Label { text: "Project Settings"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 22; font.bold: true }
                        FCard {
                            theme: root.theme
                            Layout.fillWidth: true; implicitHeight: setCol.implicitHeight + 32
                            ColumnLayout {
                                id: setCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                                spacing: 10
                                QQC2.Label { text: root.project ? root.project.path : ""; color: root.theme.textMid; font.family: root.theme.mono; font.pixelSize: 12 }
                                RowLayout {
                                    spacing: 8
                                    GButton { theme: root.theme; kind: "tonal"; text: "Open in Genesi Code"; iconSource: "icons/code.svg"
                                        onClicked: backend.openCode(root.project.path) }
                                    GButton { theme: root.theme; kind: "tonal"; text: "Open Terminal"; iconSource: "icons/terminal.svg"
                                        onClicked: backend.openTerminal(root.project.path) }
                                    GButton { theme: root.theme; kind: "ghost"; text: "Open Folder"; iconSource: "icons/folder.svg"
                                        onClicked: backend.openUrl("file://" + root.project.path) }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
