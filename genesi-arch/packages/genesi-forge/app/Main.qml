import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

QQC2.ApplicationWindow {
    id: win
    width: 1420; height: 880; minimumWidth: 1120; minimumHeight: 700
    visible: true; title: "Genesi Forge"; color: appTheme.bgBottom

    property var projects: []
    property var stats: ({ total: 0, git: 0, starred: 0, recent: 0 })
    property var currentProject: null
    property bool busy: false
    property string toast: ""
    property bool showSplash: true

    // Forge-local theme (graphite surfaces from the v2 mock). NOTE: the id must
    // NOT be "theme" — inside Component{} blocks the views' own `property var
    // theme` would shadow it and the pass would self-reference to null (the
    // all-white-UI bug).
    ForgeTheme { id: appTheme }

    function openProject(p) { win.currentProject = p }
    function toHub() { win.currentProject = null; backend.refresh() }
    function showToast(msg) { win.toast = msg; toastTimer.restart() }

    Connections {
        target: backend
        function onProjectsLoaded(raw) {
            try {
                var data = JSON.parse(raw)
                win.projects = data.projects || []
                if (win.currentProject) {
                    var replacement = null
                    for (var i = 0; i < win.projects.length; i++)
                        if (win.projects[i].id === win.currentProject.id) replacement = win.projects[i]
                    if (replacement) win.currentProject = replacement
                }
            } catch (e) { win.projects = [] }
        }
        function onStatsLoaded(raw) {
            try { win.stats = JSON.parse(raw) } catch (e) {}
        }
        function onBusyChanged(value) { win.busy = value }
        function onMessage(value) { win.showToast(value) }
    }
    Timer { id: toastTimer; interval: 4200; onTriggered: win.toast = "" }

    // Window background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: appTheme.bgTop }
            GradientStop { position: 1; color: appTheme.bgBottom }
        }
    }

    // Main content — hub or project workspace
    Loader {
        id: content
        anchors.fill: parent
        sourceComponent: win.currentProject ? projectComponent : hubComponent
        opacity: win.showSplash ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    Component {
        id: hubComponent
        HubView {
            theme: appTheme
            projects: win.projects
            stats: win.stats
            busy: win.busy
            onOpenProject: function(p) { win.openProject(p) }
        }
    }
    Component {
        id: projectComponent
        ProjectView {
            theme: appTheme
            project: win.currentProject
            onBack: win.toHub()
            onToast: function(msg) { win.showToast(msg) }
        }
    }

    // Splash overlay
    Loader {
        anchors.fill: parent
        active: win.showSplash
        sourceComponent: splashComponent
    }
    Component {
        id: splashComponent
        Splash {
            theme: appTheme
            onFinished: win.showSplash = false
        }
    }

    // Toast
    Rectangle {
        visible: win.toast !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 26
        width: Math.min(560, toastLabel.implicitWidth + 36); height: 44; radius: 11
        color: appTheme.cardHi; border.width: 1; border.color: appTheme.a(appTheme.green, 0.55)
        z: 999
        QQC2.Label { id: toastLabel; anchors.centerIn: parent; text: win.toast; color: appTheme.textHi; font.pixelSize: 13 }
    }
}
