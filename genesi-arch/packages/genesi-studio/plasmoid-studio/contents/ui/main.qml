/*
 * Genesi Studio Mode — Plasma 6 widget.
 *
 * Reads the session daemon's $XDG_RUNTIME_DIR/genesi-studio/state.json (active
 * state, focused apps, frozen apps, boosted pids) and drives the same
 * `genesi-studio` CLI the tray and the GNOME extension use — one control path,
 * so the three widgets can never disagree about what Studio Mode is doing.
 *
 * Plasma 6 / KF6 / Qt6 APIs throughout (the Plasma 5 imports — PlasmaCore.
 * IconItem, DataSource, plasmoid 2.0 — do not exist on 6).
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property color genesiGreen: "#1D9E75"
    readonly property color offColor: Kirigami.Theme.disabledTextColor

    property var state: ({})
    property bool studioActive: false
    property var targets: []
    property var frozen: []
    property var openApps: []
    property string backendName: "?"
    property bool supportsFocus: true
    property string lastError: ""

    preferredRepresentation: compactRepresentation

    // Same trick the AI Mode widget uses: a plasmoid can't reliably XHR a
    // file:// path under plasmashell on Plasma 6, but it can `cat` the file
    // through the executable engine it already needs for the buttons.
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            var stdout = (data["stdout"] || "").trim()
            if (source.indexOf("cat ") === 0)
                root.applyState(stdout)
            else if (source.indexOf("genesi-studio list") === 0)
                root.applyList(stdout)
            else
                root.refresh()      // a control command ran; re-read now
        }
        function exec(cmd) { connectSource(cmd) }
    }

    function statePath() {
        // XDG_RUNTIME_DIR is always set inside a Plasma session; the /run/user
        // form is the same path systemd would have given us anyway.
        return "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/genesi-studio/state.json"
    }

    function refresh() { executable.exec("cat " + statePath()) }
    function refreshList() { executable.exec("genesi-studio list --json") }
    function studioOn(target) {
        executable.exec("genesi-studio on " + (target ? target : ""))
    }
    function studioOff() { executable.exec("genesi-studio off") }

    function applyState(txt) {
        try {
            var s = JSON.parse(txt)
            root.state = s
            root.studioActive = s.active || false
            root.targets = s.targets || []
            root.frozen = s.frozen || []
            root.backendName = s.backend || "?"
            root.supportsFocus = s.supports_focus !== false
            root.lastError = s.error || ""
        } catch (e) {
            // transient read miss (the daemon writes atomically, but we can
            // still catch a truncated read) — keep the last good state
        }
    }

    function applyList(txt) {
        try {
            var r = JSON.parse(txt)
            root.openApps = r.windows || []
        } catch (e) {
            // leave the previous list rather than blanking the picker
        }
    }

    function targetNames() {
        var out = []
        for (var i = 0; i < targets.length; i++)
            out.push(targets[i].app_id || String(targets[i].pid))
        return out.join(", ")
    }

    Timer {
        interval: 3000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // The window list is more expensive than a file read (it may load a KWin
    // script), and it only matters while the popup is open.
    Timer {
        interval: 4000
        running: root.expanded && !root.studioActive
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshList()
    }

    toolTipMainText: "Genesi Studio Mode"
    toolTipSubText: studioActive
        ? "ON — " + targetNames() + "\n" + frozen.length + " app(s) frozen"
        : "OFF"

    // ── compact (panel) ───────────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "genesi-studio"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                color: root.studioActive ? root.genesiGreen : root.offColor
                SequentialAnimation on opacity {
                    running: root.studioActive
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 1000 }
                    NumberAnimation { to: 1.0;  duration: 1000 }
                }
            }
            PlasmaComponents.Label {
                text: "STUDIO"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: root.studioActive ? root.genesiGreen : root.offColor
                font.bold: root.studioActive
            }
        }
    }

    // ── full (popup) ──────────────────────────────────────────────────────────
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "genesi-studio"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    color: root.studioActive ? root.genesiGreen : root.offColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        text: "Studio Mode " + (root.studioActive ? "ON" : "OFF")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        color: root.studioActive ? root.genesiGreen
                                                 : Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.studioActive
                            ? root.targetNames()
                            : (root.supportsFocus
                               ? "Ready — follows your focused window"
                               : "Ready — this desktop needs you to pick the app")
                        opacity: 0.7
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.lastError !== ""
                text: "! " + root.lastError
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.neutralTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }

            // ── ON: what Studio Mode is currently doing ──────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.studioActive
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: root.frozen.length + " app(s) frozen — paused, not closed"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }
                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        model: root.frozen
                        clip: true
                        delegate: RowLayout {
                            width: ListView.view.width
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "media-playback-pause"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                opacity: 0.6
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: modelData.app_id || String(modelData.pid)
                                elide: Text.ElideRight
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }
                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    text: "Turn Studio Mode off"
                    icon.name: "media-playback-start"
                    onClicked: root.studioOff()
                }
            }

            // ── OFF: pick what gets the machine ──────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.studioActive
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Button {
                    Layout.fillWidth: true
                    visible: root.supportsFocus
                    text: "Focus the active window"
                    icon.name: "view-fullscreen"
                    onClicked: root.studioOn("")
                }
                PlasmaComponents.Label {
                    text: "…or pick an app:"
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        model: root.openApps
                        clip: true
                        delegate: PlasmaComponents.ItemDelegate {
                            width: ListView.view.width
                            text: (modelData.app_id || String(modelData.pid))
                                  + (modelData.focused ? "  ●" : "")
                            icon.name: "window"
                            onClicked: root.studioOn(String(modelData.pid))
                        }
                    }
                }
                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    visible: root.openApps.length === 0
                    text: "Nothing open that Studio Mode can see"
                    explanation: "Backend: " + root.backendName
                }
            }
        }
    }
}
