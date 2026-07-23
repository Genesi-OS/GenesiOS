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
    // PIDs ticked in the picker. Studio Mode takes any number of apps, so the
    // picker is multi-select and only commits when the user says go — clicking
    // a row used to fire immediately, which made choosing a second app
    // impossible.
    property var selected: []
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
            // Drop the shell/compositor windows the daemon flagged: they are
            // protected, so they can neither be frozen nor meaningfully
            // focused, and they crowded the real apps out of the picker.
            var all = r.windows || []
            var out = []
            for (var i = 0; i < all.length; i++) {
                if (!all[i].protected)
                    out.push(all[i])
            }
            root.openApps = out
        } catch (e) {
            // leave the previous list rather than blanking the picker
        }
    }

    function isSelected(pid) {
        return root.selected.indexOf(pid) !== -1
    }

    function toggleSelect(pid) {
        // Reassign rather than mutate: QML property bindings do not observe
        // in-place changes to a JS array, so push()/splice() alone would tick
        // the box in the model but never repaint the row.
        var next = root.selected.slice()
        var at = next.indexOf(pid)
        if (at === -1)
            next.push(pid)
        else
            next.splice(at, 1)
        root.selected = next
    }

    function startSelected() {
        if (root.selected.length === 0)
            return
        root.studioOn(root.selected.join(" "))
        root.selected = []
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
                // Without isMask the `color` below does nothing and the raw SVG
                // is painted as-is — which is why the panel icon came out dark.
                // As a mask it takes the theme's text colour when idle and the
                // Genesi green when Studio Mode holds the machine.
                isMask: true
                color: root.studioActive ? root.genesiGreen
                                         : Kirigami.Theme.textColor
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

            // ── header ───────────────────────────────────────────────────────
            // While Studio Mode is on the header becomes the focused app itself
            // — its real icon, its real name — so a glance at the popup answers
            // "what has the machine right now" without reading a list.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large + 10
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large + 10
                    radius: 12
                    color: root.studioActive
                        ? Qt.rgba(root.genesiGreen.r, root.genesiGreen.g,
                                  root.genesiGreen.b, 0.14)
                        : Qt.rgba(Kirigami.Theme.textColor.r,
                                  Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.06)
                    border.width: 1
                    border.color: root.studioActive
                        ? Qt.rgba(root.genesiGreen.r, root.genesiGreen.g,
                                  root.genesiGreen.b, 0.5)
                        : Qt.rgba(Kirigami.Theme.textColor.r,
                                  Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.12)
                    Behavior on color { ColorAnimation { duration: 180 } }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.large
                        height: Kirigami.Units.iconSizes.large
                        source: root.studioActive && root.targets.length > 0
                            ? (root.targets[0].icon || "application-x-executable")
                            : "genesi-studio"
                        // Only the idle Studio glyph is a mask; a real app icon
                        // must keep its own colours.
                        isMask: !root.studioActive
                        color: root.studioActive ? "transparent"
                                                 : Kirigami.Theme.textColor
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.studioActive
                            ? (root.targets.length > 0
                               ? (root.targets[0].name || root.targets[0].app_id)
                               : "Studio Mode")
                            : "Studio Mode"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        elide: Text.ElideRight
                        color: root.studioActive ? root.genesiGreen
                                                 : Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.studioActive
                            ? (root.targets.length > 1
                               ? "+ " + (root.targets.length - 1) + " more · has the machine"
                               : "has the machine")
                            : (root.supportsFocus
                               ? "Ready — follows your focused window"
                               : "Ready — pick an app below")
                        opacity: 0.7
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    // Live proof it is doing something, not just claiming to.
                    RowLayout {
                        visible: root.studioActive
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents.Label {
                            text: "❄ " + root.frozen.length + " paused"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.85
                        }
                        PlasmaComponents.Label {
                            visible: (root.state.boosted || []).length > 0
                            text: "⚡ boosted"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: root.genesiGreen
                            opacity: 0.9
                        }
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
                    text: "Paused, not closed — they keep their unsaved work"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.65
                }
                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        model: root.frozen
                        clip: true
                        spacing: 2
                        delegate: Item {
                            width: ListView.view.width
                            height: Kirigami.Units.iconSizes.medium
                                    + Kirigami.Units.smallSpacing
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: modelData.icon || "application-x-executable"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    // Dimmed: these apps are asleep, and the
                                    // list should read that way at a glance.
                                    opacity: 0.45
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.app_id
                                          || String(modelData.pid)
                                    elide: Text.ElideRight
                                    opacity: 0.75
                                }
                                Kirigami.Icon {
                                    source: "media-playback-pause"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.4
                                }
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
                    visible: root.supportsFocus && root.selected.length === 0
                    text: "Focus the active window"
                    icon.name: "view-fullscreen"
                    onClicked: root.studioOn("")
                }
                PlasmaComponents.Label {
                    text: root.selected.length > 0
                        ? root.selected.length + " app(s) selected"
                        : (root.supportsFocus ? "…or tick the apps to focus:"
                                              : "Tick the apps to focus:")
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        model: root.openApps
                        clip: true
                        spacing: 2
                        delegate: PlasmaComponents.ItemDelegate {
                            width: ListView.view.width
                            height: Kirigami.Units.iconSizes.large
                            // Ticks the row; the run button below commits.
                            onClicked: root.toggleSelect(modelData.pid)

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.CheckBox {
                                    checked: root.isSelected(modelData.pid)
                                    onToggled: root.toggleSelect(modelData.pid)
                                }
                                Kirigami.Icon {
                                    source: modelData.icon || "application-x-executable"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.app_id
                                              || String(modelData.pid)
                                        elide: Text.ElideRight
                                        font.bold: modelData.focused === true
                                    }
                                    // The window title is the only way to tell
                                    // two windows of the same app apart.
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        visible: (modelData.title || "") !== ""
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        opacity: 0.6
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    }
                                }
                                PlasmaComponents.Label {
                                    visible: modelData.focused === true
                                    text: "active"
                                    color: root.genesiGreen
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                            }
                        }
                    }
                }
                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    visible: root.openApps.length === 0
                    text: "Nothing open that Studio Mode can see"
                    explanation: "Backend: " + root.backendName
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.selected.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: root.selected.length === 1
                            ? "Give the machine to this app"
                            : "Give the machine to these " + root.selected.length + " apps"
                        icon.name: "media-playback-start"
                        onClicked: root.startSelected()
                    }
                    PlasmaComponents.Button {
                        text: "Clear"
                        flat: true
                        onClicked: root.selected = []
                    }
                }
            }
        }
    }
}
