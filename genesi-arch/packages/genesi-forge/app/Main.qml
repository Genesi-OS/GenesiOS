import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: win
    width: 1220; height: 760; minimumWidth: 980; minimumHeight: 620
    visible: true; title: "Genesi Forge"; color: theme.bgBottom

    property var projects: []
    property var selected: null
    property var runs: []
    property string pipelineReason: ""
    property string query: ""
    property string filter: "all"
    property string view: "overview"
    property bool busy: false
    property string toast: ""

    Theme { id: theme }

    function filtered() {
        var result = []; var q = query.toLowerCase()
        for (var i = 0; i < projects.length; i++) {
            var p = projects[i]
            if (filter === "changed" && p.changed === 0) continue
            if (filter === "github" && p.provider !== "GitHub") continue
            if (filter === "deploy" && p.deployCount === 0) continue
            var hay = (p.name + " " + p.path + " " + p.branch + " " + p.provider + " " + p.slug).toLowerCase()
            if (q && hay.indexOf(q) < 0) continue
            result.push(p)
        }
        return result
    }

    function choose(project) {
        selected = project; runs = []; pipelineReason = ""
        if (view === "pipelines") backend.loadPipelines(JSON.stringify(project))
    }

    Connections {
        target: backend
        function onProjectsLoaded(raw) {
            try {
                var data = JSON.parse(raw); win.projects = data.projects || []
                if (win.selected) {
                    var replacement = null
                    for (var i = 0; i < win.projects.length; i++)
                        if (win.projects[i].id === win.selected.id) replacement = win.projects[i]
                    win.selected = replacement
                }
                if (!win.selected && win.projects.length) win.choose(win.projects[0])
            } catch (e) { win.projects = [] }
        }
        function onPipelinesLoaded(raw) {
            try { var data = JSON.parse(raw); win.runs = data.runs || []; win.pipelineReason = data.reason || "" }
            catch (e) { win.runs = []; win.pipelineReason = "Could not read pipelines" }
        }
        function onBusyChanged(value) { win.busy = value }
        function onMessage(value) { win.toast = value; toastTimer.restart() }
    }
    Timer { id: toastTimer; interval: 4200; onTriggered: win.toast = "" }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient { GradientStop { position: 0; color: theme.bgTop } GradientStop { position: 1; color: theme.bgBottom } }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 74; color: theme.card
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 14
                Rectangle {
                    width: 42; height: 42; radius: 8; color: theme.mix(theme.card, theme.green, 0.20)
                    border.width: 1; border.color: theme.a(theme.green, 0.55)
                    Kirigami.Icon { anchors.centerIn: parent; width: 24; height: 24; source: "genesi-forge"; color: theme.greenBright }
                }
                ColumnLayout {
                    spacing: 1
                    QQC2.Label { text: "Forge"; color: theme.textHi; font.family: theme.display; font.pixelSize: 22; font.bold: true }
                    QQC2.Label { text: "Projects, Git remotes and delivery"; color: theme.textMid; font.pixelSize: 12 }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 285; height: 38; radius: 7; color: theme.cardHi; border.width: 1; border.color: theme.lineHi
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 8
                        Kirigami.Icon { source: "search"; width: 16; height: 16; color: theme.textMid }
                        QQC2.TextField {
                            Layout.fillWidth: true; background: null; placeholderText: "Search projects"
                            color: theme.textHi; placeholderTextColor: theme.textLo
                            selectedTextColor: theme.white; selectionColor: theme.green
                            onTextChanged: win.query = text
                        }
                    }
                }
                GButton { theme: theme; kind: "ghost"; iconSource: "view-refresh"; tooltip: "Scan projects"; enabled: !win.busy; onClicked: backend.refresh() }
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: theme.line }

        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            Rectangle {
                Layout.preferredWidth: 184; Layout.fillHeight: true; color: theme.card
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    QQC2.Label { text: "WORKSPACE"; color: theme.textLo; font.pixelSize: 11; font.bold: true }
                    Repeater {
                        model: [
                            {key:"all", label:"All projects", icon:"folder-development"},
                            {key:"changed", label:"Local changes", icon:"document-edit"},
                            {key:"github", label:"GitHub", icon:"github"},
                            {key:"deploy", label:"Deployments", icon:"cloud-upload"}
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 39; radius: 6
                            color: win.filter === modelData.key ? theme.mix(theme.card, theme.green, 0.18) : "transparent"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.filter = modelData.key }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                                Kirigami.Icon { source: modelData.icon; width: 17; height: 17; color: win.filter === modelData.key ? theme.greenBright : theme.textMid }
                                QQC2.Label { text: modelData.label; Layout.fillWidth: true; color: win.filter === modelData.key ? theme.textHi : theme.textMid; font.bold: win.filter === modelData.key }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    StatusBanner {
                        Layout.fillWidth: true; theme: theme; accent: theme.blue; icon: "security-high"
                        title: "Local first"; body: "Git stays local. GitHub uses your gh session."
                    }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: theme.line }

            Item {
                Layout.preferredWidth: 360; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 9
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Projects"; color: theme.textHi; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                        QQC2.Label { text: win.filtered().length; color: theme.textLo }
                    }
                    QQC2.ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        ListView {
                            id: projectList; model: win.filtered(); spacing: 7
                            delegate: Rectangle {
                                width: projectList.width; height: 92; radius: 7
                                color: win.selected && win.selected.id === modelData.id ? theme.mix(theme.cardHi, theme.green, 0.12) : theme.card
                                border.width: 1; border.color: win.selected && win.selected.id === modelData.id ? theme.a(theme.green, 0.60) : theme.line
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.choose(modelData) }
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 11; spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        QQC2.Label { text: modelData.name; color: theme.textHi; font.bold: true; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Rectangle {
                                            visible: modelData.changed > 0; height: 22; width: changeText.implicitWidth + 14; radius: 6
                                            color: theme.a(theme.turbo, 0.16); border.width: 1; border.color: theme.a(theme.turbo, 0.42)
                                            QQC2.Label { id: changeText; anchors.centerIn: parent; text: modelData.changed + " changed"; color: theme.turbo; font.pixelSize: 10; font.bold: true }
                                        }
                                    }
                                    RowLayout {
                                        Kirigami.Icon { source: "vcs-branch"; width: 14; height: 14; color: theme.greenBright }
                                        QQC2.Label { text: modelData.branch; color: theme.textMid; font.pixelSize: 11 }
                                        QQC2.Label { text: "  " + modelData.provider; color: theme.textLo; font.pixelSize: 11 }
                                        Item { Layout.fillWidth: true }
                                        QQC2.Label { visible: modelData.ahead > 0; text: "↑" + modelData.ahead; color: theme.greenBright; font.bold: true }
                                        QQC2.Label { visible: modelData.behind > 0; text: "↓" + modelData.behind; color: theme.turbo; font.bold: true }
                                    }
                                    QQC2.Label { text: modelData.path; color: theme.textLo; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: theme.line }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 12
                    ColumnLayout {
                        visible: win.selected !== null; Layout.fillWidth: true; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                QQC2.Label { text: win.selected ? win.selected.name : ""; color: theme.textHi; font.pixelSize: 24; font.bold: true }
                                QQC2.Label { text: win.selected ? win.selected.slug || win.selected.path : ""; color: theme.textMid; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            }
                            GButton { theme: theme; kind: "primary"; text: "Open in Code"; iconSource: "code-context"; onClicked: backend.openCode(win.selected.path) }
                            GButton { theme: theme; kind: "tonal"; iconSource: "utilities-terminal"; tooltip: "Open terminal"; onClicked: backend.openTerminal(win.selected.path) }
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [{key:"overview",label:"Overview"},{key:"pipelines",label:"Pipelines"},{key:"integrations",label:"Integrations"}]
                                delegate: QQC2.Button {
                                    text: modelData.label; checkable: true; checked: win.view === modelData.key
                                    onClicked: { win.view = modelData.key; if (modelData.key === "pipelines") backend.loadPipelines(JSON.stringify(win.selected)) }
                                    palette.buttonText: checked ? theme.white : theme.textMid
                                    background: Rectangle { radius: 6; color: parent.checked ? theme.green : theme.cardHi; border.width: 1; border.color: parent.checked ? theme.greenBright : theme.line }
                                }
                            }
                        }
                    }

                    StackLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        currentIndex: win.view === "overview" ? 0 : (win.view === "pipelines" ? 1 : 2)
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 9
                                    Repeater {
                                        model: win.selected ? [
                                            {label:"Branch", value:win.selected.branch, color:theme.greenBright},
                                            {label:"Staged", value:win.selected.staged, color:theme.blue},
                                            {label:"Modified", value:win.selected.modified, color:theme.turbo},
                                            {label:"Untracked", value:win.selected.untracked, color:theme.textHi}
                                        ] : []
                                        delegate: Rectangle {
                                            Layout.fillWidth: true; height: 72; radius: 7; color: theme.card; border.width: 1; border.color: theme.line
                                            Column { anchors.centerIn: parent; spacing: 2
                                                QQC2.Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: modelData.color; font.pixelSize: 20; font.bold: true }
                                                QQC2.Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: theme.textLo; font.pixelSize: 10 }
                                            }
                                        }
                                    }
                                }
                                GlassCard {
                                    Layout.fillWidth: true; Layout.preferredHeight: 126
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 15; spacing: 7
                                        QQC2.Label { text: "Latest commit"; color: theme.textLo; font.pixelSize: 11; font.bold: true }
                                        QQC2.Label { text: win.selected ? win.selected.lastSubject || "No commits yet" : ""; color: theme.textHi; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                        QQC2.Label { text: win.selected ? win.selected.lastHash : ""; color: theme.greenBright; font.family: "monospace" }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    GButton { theme: theme; kind: "tonal"; text: "Fetch"; iconSource: "vcs-update-required"; enabled: !win.busy; onClicked: backend.fetch(win.selected.path) }
                                    GButton { theme: theme; kind: "tonal"; text: "Pull FF"; iconSource: "go-down"; enabled: !win.busy; onClicked: backend.pull(win.selected.path) }
                                    GButton { theme: theme; kind: "tonal"; text: "Push"; iconSource: "go-up"; enabled: !win.busy; onClicked: backend.push(win.selected.path) }
                                    Item { Layout.fillWidth: true }
                                    GButton { visible: win.selected && win.selected.web; theme: theme; kind: "ghost"; text: "Repository"; iconSource: "internet-web-browser"; onClicked: backend.openUrl(win.selected.web) }
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; spacing: 9
                                StatusBanner { visible: win.pipelineReason !== ""; Layout.fillWidth: true; theme: theme; accent: theme.turbo; icon: "dialog-warning"; title: "Pipelines unavailable"; body: win.pipelineReason }
                                QQC2.ScrollView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                    ListView {
                                        id: runList; model: win.runs; spacing: 7
                                        delegate: Rectangle {
                                            width: runList.width; height: 78; radius: 7; color: theme.card; border.width: 1; border.color: theme.line
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 11; spacing: 10
                                            Rectangle { width: 9; height: 9; radius: 5; color: modelData.status !== "completed" ? theme.blue : (modelData.conclusion === "success" ? theme.greenBright : theme.red) }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 2
                                                    QQC2.Label { text: modelData.displayTitle || modelData.name; color: theme.textHi; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                                    QQC2.Label { text: (modelData.workflowName || "Workflow") + "  ·  " + modelData.headBranch + "  ·  " + (modelData.conclusion || modelData.status); color: theme.textMid; font.pixelSize: 11 }
                                                }
                                                GButton { theme: theme; kind: "ghost"; iconSource: "internet-web-browser"; tooltip: "Open run"; onClicked: backend.openUrl(modelData.url) }
                                                GButton { visible: modelData.status === "completed"; theme: theme; kind: "ghost"; iconSource: "view-refresh"; tooltip: "Rerun"; onClicked: backend.rerun(String(modelData.databaseId), win.selected.slug) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Item {
                            ColumnLayout {
                                anchors.fill: parent; spacing: 8
                                QQC2.Label { text: "Detected from project files"; color: theme.textMid }
                                Repeater {
                                    model: win.selected ? win.selected.integrations : []
                                    delegate: Rectangle {
                                        Layout.fillWidth: true; height: 64; radius: 7; color: theme.card; border.width: 1; border.color: theme.line
                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: 11
                                            Kirigami.Icon { source: modelData.name === "Docker" ? "docker" : "cloud-status"; width: 24; height: 24; color: theme.greenBright }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                                QQC2.Label { text: modelData.name; color: theme.textHi; font.bold: true }
                                                QQC2.Label { text: modelData.detail; color: theme.textLo; font.pixelSize: 10 }
                                            }
                                            GButton { visible: modelData.url !== ""; theme: theme; kind: "ghost"; text: "Dashboard"; iconSource: "internet-web-browser"; onClicked: backend.openUrl(modelData.url) }
                                        }
                                    }
                                }
                                StatusBanner { visible: win.selected && win.selected.integrations.length === 0; Layout.fillWidth: true; theme: theme; accent: theme.blue; icon: "documentinfo"; title: "No integrations detected"; body: "Vercel, Netlify, Render, Railway, Fly.io, Docker and CI manifests appear here." }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
                Column {
                    visible: win.selected === null; anchors.centerIn: parent; spacing: 8
                    Kirigami.Icon { anchors.horizontalCenter: parent.horizontalCenter; source: "folder-development"; width: 48; height: 48; color: theme.textLo }
                    QQC2.Label { text: win.busy ? "Scanning your projects..." : "No Git projects found"; color: theme.textMid; font.bold: true }
                }
            }
        }
    }

    Rectangle {
        visible: win.toast !== ""; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        width: Math.min(520, toastLabel.implicitWidth + 34); height: 42; radius: 7; color: theme.cardHi; border.width: 1; border.color: theme.a(theme.green, 0.55)
        QQC2.Label { id: toastLabel; anchors.centerIn: parent; text: win.toast; color: theme.textHi }
    }
}
