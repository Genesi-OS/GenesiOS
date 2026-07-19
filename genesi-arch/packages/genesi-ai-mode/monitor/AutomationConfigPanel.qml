/*
 * Genesi AI Mode Monitor — Automations config panel (right rail). Adapted from
 * the Forge ConfigPanel: shows the selected block's settings, one form per node
 * kind (events + actions). No project/git or YAML preview here.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property var node
    property var graphProvider

    property var models: []
    property bool capturing: false
    property bool hotkeyAvailable: true
    property string captureNote: ""

    readonly property bool isEvent: node && ("" + node.kind).indexOf("evt_") === 0

    Component.onCompleted: backend.loadModels()
    Connections {
        target: backend
        function onModelsLoaded(jsonStr) {
            try { root.models = JSON.parse(jsonStr) } catch (e) { root.models = [] }
        }
        function onHotkeyCaptured(combo) {
            if (!root.capturing) return
            root.capturing = false
            if (combo && root.node) {
                root.setConfig("combo", combo)
                root.captureNote = ""
            } else {
                root.captureNote = root.hotkeyAvailable
                    ? "No keys detected — click Capture and hold your shortcut."
                    : "Needs input access: run  sudo usermod -aG input $USER  then log out and back in."
            }
        }
    }

    component FieldLabel: QQC2.Label {
        color: root.theme.textMid; font.pixelSize: 12; font.bold: true
        Layout.topMargin: 6
    }
    component Combo: QQC2.ComboBox {
        id: cb
        Layout.fillWidth: true
        implicitHeight: 40
        background: Rectangle { radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi }
        contentItem: QQC2.Label {
            leftPadding: 12; rightPadding: 30; verticalAlignment: Text.AlignVCenter
            text: cb.displayText; color: root.theme.textHi; font.pixelSize: 13; elide: Text.ElideRight
        }
        indicator: FIcon { x: cb.width - 26; y: (cb.height - 14) / 2; size: 14; name: "chevron-down"; color: root.theme.textMid }
    }
    component GField: Rectangle {
        Layout.fillWidth: true; implicitHeight: 40
        radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
        property alias text: tf.text
        property string icon: ""
        signal accepted(string value)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
            FIcon { visible: parent.parent.icon !== ""; name: parent.parent.icon; size: 14; color: root.theme.textMid }
            QQC2.TextField { id: tf; Layout.fillWidth: true; background: null; color: root.theme.textHi; font.pixelSize: 13
                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                onEditingFinished: parent.parent.accepted(text) }
        }
    }
    component GArea: Rectangle {
        id: area
        Layout.fillWidth: true; implicitHeight: 92
        radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
        property alias text: ta.text
        signal accepted(string value)
        // ScrollView reparents its content into an internal flickable, so the
        // TextArea's `parent` is NOT this Rectangle — reference it by id.
        QQC2.ScrollView {
            anchors.fill: parent; anchors.margins: 6; clip: true
            QQC2.TextArea { id: ta; background: null; color: root.theme.textHi; font.pixelSize: 13; wrapMode: Text.Wrap
                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                onEditingFinished: area.accepted(text) }
        }
    }
    component RowToggle: RowLayout {
        id: rt
        Layout.fillWidth: true; Layout.topMargin: 6
        property string label: ""
        property bool value: false
        signal toggled(bool v)
        QQC2.Label { text: rt.label; color: root.theme.textHi; font.pixelSize: 13; Layout.fillWidth: true }
        GToggle { theme: root.theme; checked: rt.value; onToggled: function(v) { rt.toggled(v) } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true; spacing: 11
            Rectangle {
                width: 40; height: 40; radius: 11
                color: root.node ? root.theme.a(root.node.accent, 0.18) : root.theme.cardHi
                FIcon { anchors.centerIn: parent; name: root.node ? root.node.icon : "zap"; size: 19
                    color: root.node ? root.node.accent : root.theme.textMid }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                QQC2.Label { text: root.node ? root.node.title : "No block selected"; color: root.theme.textHi
                    font.family: root.theme.display; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                QQC2.Label {
                    text: root.node ? (root.isEvent ? "When this happens…" : "…do this") : "Pick a block on the canvas"
                    color: root.theme.textMid; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap
                }
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: availableWidth

            ColumnLayout {
                id: col
                width: root.width - 36
                spacing: 8

                QQC2.Label {
                    visible: !root.node
                    text: "Select a block on the canvas to configure it."
                    color: root.theme.textLo; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap
                }

                FieldLabel { text: "Block name"; visible: root.node }
                Rectangle {
                    visible: root.node
                    Layout.fillWidth: true; implicitHeight: 40; radius: 9
                    color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
                    QQC2.TextField {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10
                        background: null; verticalAlignment: Text.AlignVCenter
                        text: root.node ? root.node.title : ""
                        color: root.theme.textHi; font.pixelSize: 13
                        selectionColor: root.theme.green; selectedTextColor: root.theme.white
                        onEditingFinished: if (root.node) root.graphProvider.renameNode(root.node.id, text)
                    }
                }

                // ── evt_fs ──────────────────────────────────────────────
                FieldLabel { text: "Folder to watch"; visible: root.kindIs("evt_fs") }
                GField { visible: root.kindIs("evt_fs"); text: root.cfg("path", "~/Downloads"); icon: "folder"
                    onAccepted: root.setConfig("path", value) }
                FieldLabel { text: "Name pattern (glob)"; visible: root.kindIs("evt_fs") }
                GField { visible: root.kindIs("evt_fs"); text: root.cfg("pattern", "*"); icon: "search"
                    onAccepted: root.setConfig("pattern", value) }
                FieldLabel { text: "On"; visible: root.kindIs("evt_fs") }
                Combo { visible: root.kindIs("evt_fs"); model: [ "created", "modified", "deleted", "any" ]
                    currentIndex: root.optionIndex(model, root.cfg("change", "created"))
                    onActivated: root.setConfig("change", currentText) }
                RowToggle { visible: root.kindIs("evt_fs"); label: "Include subfolders"; value: root.cfgBool("recursive")
                    onToggled: function(v) { root.setConfig("recursive", v) } }

                // ── evt_resource ────────────────────────────────────────
                FieldLabel { text: "Metric"; visible: root.kindIs("evt_resource") }
                Combo { visible: root.kindIs("evt_resource"); model: [ "cpu", "ram" ]
                    currentIndex: root.optionIndex(model, root.cfg("metric", "cpu"))
                    onActivated: root.setConfig("metric", currentText) }
                FieldLabel { text: "Condition"; visible: root.kindIs("evt_resource") }
                RowLayout {
                    visible: root.kindIs("evt_resource"); Layout.fillWidth: true; spacing: 8
                    Combo { Layout.preferredWidth: 70; model: [ ">", "<" ]
                        currentIndex: root.optionIndex(model, root.cfg("op", ">"))
                        onActivated: root.setConfig("op", currentText) }
                    GField { Layout.fillWidth: true; text: root.cfg("threshold", "80"); icon: "sliders"
                        onAccepted: root.setConfig("threshold", value) }
                    QQC2.Label { text: "%"; color: root.theme.textMid; font.pixelSize: 14 }
                }

                // ── evt_app ─────────────────────────────────────────────
                FieldLabel { text: "Process name"; visible: root.kindIs("evt_app") }
                GField { visible: root.kindIs("evt_app"); text: root.cfg("app", ""); icon: "box"
                    onAccepted: root.setConfig("app", value) }
                FieldLabel { text: "When it"; visible: root.kindIs("evt_app") }
                Combo { visible: root.kindIs("evt_app"); model: [ "opened", "closed" ]
                    currentIndex: root.optionIndex(model, root.cfg("transition", "opened"))
                    onActivated: root.setConfig("transition", currentText) }

                // ── evt_hotkey ──────────────────────────────────────────
                FieldLabel { text: "Shortcut"; visible: root.kindIs("evt_hotkey") }
                RowLayout {
                    visible: root.kindIs("evt_hotkey"); Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 40; radius: 9
                        color: root.theme.cardHi; border.width: 1
                        border.color: root.capturing ? root.theme.a(root.theme.turbo, 0.7) : root.theme.lineHi
                        QQC2.Label {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            text: root.capturing ? "press & hold your shortcut, then release…" : (root.cfg("combo", "") || "not set")
                            color: root.capturing ? root.theme.turboBright : root.theme.textHi
                            font.family: root.theme.mono; font.pixelSize: 13
                        }
                    }
                    GButton { theme: root.theme; kind: "tonal"; text: root.capturing ? "waiting…" : "Capture"; iconSource: "icons/terminal.svg"
                        enabled: !root.capturing
                        onClicked: { root.captureNote = ""; root.capturing = true; backend.captureHotkey() } }
                }
                QQC2.Label { visible: root.kindIs("evt_hotkey") && root.captureNote !== ""
                    Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.captureNote
                    color: root.hotkeyAvailable ? root.theme.textMid : root.theme.turboBright; font.pixelSize: 10 }
                QQC2.Label { visible: root.kindIs("evt_hotkey"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Modifier-only shortcuts (Ctrl, Shift, Ctrl+Shift…) are allowed. Note: a modifier-only shortcut fires whenever you use it elsewhere too."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── evt_schedule ────────────────────────────────────────
                FieldLabel { text: "Every N minutes"; visible: root.kindIs("evt_schedule") }
                GField { visible: root.kindIs("evt_schedule"); text: root.cfg("interval", "60"); icon: "clock"
                    onAccepted: { root.setConfig("interval", value); root.setConfig("time", "") } }
                FieldLabel { text: "…or daily at (HH:MM, optional)"; visible: root.kindIs("evt_schedule") }
                GField { visible: root.kindIs("evt_schedule"); text: root.cfg("time", ""); icon: "clock"
                    onAccepted: root.setConfig("time", value) }

                // ── act_script ──────────────────────────────────────────
                FieldLabel { text: "Shell command / script"; visible: root.kindIs("act_script") }
                GArea { visible: root.kindIs("act_script"); text: root.cfg("command", "")
                    onAccepted: root.setConfig("command", value) }
                QQC2.Label { visible: root.kindIs("act_script"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "{input} (or $GENESI_INPUT) holds the previous block's output. Drag links from the on ok / on error dots to branch on the result; either way the script's output flows to the next block."
                    color: root.theme.textLo; font.pixelSize: 10 }
                RowToggle { visible: root.kindIs("act_script"); label: "Run in a terminal window"; value: root.cfgBool("terminal")
                    onToggled: function(v) { root.setConfig("terminal", v) } }
                QQC2.Label { visible: root.kindIs("act_script") && root.cfgBool("terminal"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Opens the command in a real terminal — needed for interactive/TUI programs (cmatrix, htop, installers). In this mode the output can't be captured: on ok means \"launched\" and nothing is piped to the next block."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_ai ──────────────────────────────────────────────
                FieldLabel { text: "Model"; visible: root.kindIs("act_ai") }
                Combo { visible: root.kindIs("act_ai"); model: root.models
                    currentIndex: root.optionIndex(root.models, root.cfg("model", ""))
                    onActivated: root.setConfig("model", root.models[currentIndex]) }
                RowToggle { visible: root.kindIs("act_ai"); label: "Turn AI Mode on"; value: root.cfgBool("aiMode")
                    onToggled: function(v) { root.setConfig("aiMode", v) } }
                RowToggle { visible: root.kindIs("act_ai"); label: "Use Turbo (on this model)"; value: root.cfgBool("turbo")
                    onToggled: function(v) { root.setConfig("turbo", v) } }
                RowToggle { visible: root.kindIs("act_ai") && root.cfgBool("turbo"); label: "⚡ Speculative decoding"; value: root.cfgBool("spec")
                    onToggled: function(v) { root.setConfig("spec", v) } }
                FieldLabel { text: "AI can"; visible: root.kindIs("act_ai") }
                Combo { visible: root.kindIs("act_ai"); model: [ "advisory", "ask", "auto" ]
                    currentIndex: root.optionIndex(model, root.aiExec())
                    onActivated: root.setConfig("exec", currentText) }
                QQC2.Label { visible: root.kindIs("act_ai"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: root.aiExec() === "auto" ? "Autonomous: the AI runs desktop actions without asking."
                        : root.aiExec() === "ask" ? "Ask first: each action waits for your Approve/Deny here (up to 5 min)."
                        : "Advisory: the AI just answers and notifies you — no actions taken."
                    color: root.theme.textLo; font.pixelSize: 10 }
                FieldLabel { text: "Prompt"; visible: root.kindIs("act_ai") }
                GArea { visible: root.kindIs("act_ai"); text: root.cfg("prompt", "")
                    onAccepted: root.setConfig("prompt", value) }

                // ── act_notify ──────────────────────────────────────────
                FieldLabel { text: "Title"; visible: root.kindIs("act_notify") }
                GField { visible: root.kindIs("act_notify"); text: root.cfg("title", "Genesi"); icon: "alert"
                    onAccepted: root.setConfig("title", value) }
                FieldLabel { text: "Message"; visible: root.kindIs("act_notify") }
                GArea { visible: root.kindIs("act_notify"); text: root.cfg("body", "")
                    onAccepted: root.setConfig("body", value) }

                // ── evt_temperature ─────────────────────────────────────
                FieldLabel { text: "Sensor filter (optional)"; visible: root.kindIs("evt_temperature") }
                GField { visible: root.kindIs("evt_temperature"); text: root.cfg("sensor", ""); icon: "search"
                    onAccepted: root.setConfig("sensor", value) }
                FieldLabel { text: "Above (°C)"; visible: root.kindIs("evt_temperature") }
                GField { visible: root.kindIs("evt_temperature"); text: root.cfg("threshold", "80"); icon: "alert"
                    onAccepted: root.setConfig("threshold", value) }

                // ── evt_process ─────────────────────────────────────────
                FieldLabel { text: "Process name"; visible: root.kindIs("evt_process") }
                GField { visible: root.kindIs("evt_process"); text: root.cfg("app", ""); icon: "box"
                    onAccepted: root.setConfig("app", value) }
                FieldLabel { text: "Metric"; visible: root.kindIs("evt_process") }
                Combo { visible: root.kindIs("evt_process"); model: [ "mem", "cpu" ]
                    currentIndex: root.optionIndex(model, root.cfg("metric", "mem"))
                    onActivated: root.setConfig("metric", currentText) }
                FieldLabel { text: root.cfg("metric","mem") === "cpu" ? "Above (%)" : "Above (MB)"; visible: root.kindIs("evt_process") }
                GField { visible: root.kindIs("evt_process"); text: root.cfg("threshold", "1000"); icon: "sliders"
                    onAccepted: root.setConfig("threshold", value) }

                // ── evt_power ───────────────────────────────────────────
                FieldLabel { text: "When"; visible: root.kindIs("evt_power") }
                Combo { visible: root.kindIs("evt_power"); model: [ "on_battery", "on_ac", "battery_below", "battery_above" ]
                    currentIndex: root.optionIndex(model, root.cfg("event", "on_battery"))
                    onActivated: root.setConfig("event", currentText) }
                FieldLabel { text: "Battery level (%)"; visible: root.kindIs("evt_power") && (root.cfg("event","on_battery") === "battery_below" || root.cfg("event","on_battery") === "battery_above") }
                GField { visible: root.kindIs("evt_power") && (root.cfg("event","on_battery") === "battery_below" || root.cfg("event","on_battery") === "battery_above")
                    text: root.cfg("level", "20"); icon: "bolt"; onAccepted: root.setConfig("level", value) }

                // ── evt_disk ────────────────────────────────────────────
                FieldLabel { text: "When"; visible: root.kindIs("evt_disk") }
                Combo { visible: root.kindIs("evt_disk"); model: [ "usage_above", "mounted", "unmounted" ]
                    currentIndex: root.optionIndex(model, root.cfg("event", "usage_above"))
                    onActivated: root.setConfig("event", currentText) }
                FieldLabel { text: "Mount path"; visible: root.kindIs("evt_disk") && root.cfg("event","usage_above") === "usage_above" }
                GField { visible: root.kindIs("evt_disk") && root.cfg("event","usage_above") === "usage_above"
                    text: root.cfg("path", "/"); icon: "database"; onAccepted: root.setConfig("path", value) }
                FieldLabel { text: "Usage above (%)"; visible: root.kindIs("evt_disk") && root.cfg("event","usage_above") === "usage_above" }
                GField { visible: root.kindIs("evt_disk") && root.cfg("event","usage_above") === "usage_above"
                    text: root.cfg("threshold", "90"); icon: "sliders"; onAccepted: root.setConfig("threshold", value) }

                // ── evt_usb ─────────────────────────────────────────────
                FieldLabel { text: "When a USB device is"; visible: root.kindIs("evt_usb") }
                Combo { visible: root.kindIs("evt_usb"); model: [ "added", "removed" ]
                    currentIndex: root.optionIndex(model, root.cfg("action", "added"))
                    onActivated: root.setConfig("action", currentText) }

                // ── evt_network ─────────────────────────────────────────
                FieldLabel { text: "When"; visible: root.kindIs("evt_network") }
                Combo { visible: root.kindIs("evt_network"); model: [ "online", "offline", "iface_up", "iface_down" ]
                    currentIndex: root.optionIndex(model, root.cfg("event", "online"))
                    onActivated: root.setConfig("event", currentText) }
                FieldLabel { text: "Interface"; visible: root.kindIs("evt_network") && (root.cfg("event","online") === "iface_up" || root.cfg("event","online") === "iface_down") }
                GField { visible: root.kindIs("evt_network") && (root.cfg("event","online") === "iface_up" || root.cfg("event","online") === "iface_down")
                    text: root.cfg("iface", ""); icon: "globe"; onAccepted: root.setConfig("iface", value) }

                // ── evt_bluetooth ───────────────────────────────────────
                FieldLabel { text: "When a device is"; visible: root.kindIs("evt_bluetooth") }
                Combo { visible: root.kindIs("evt_bluetooth"); model: [ "connected", "disconnected" ]
                    currentIndex: root.optionIndex(model, root.cfg("action", "connected"))
                    onActivated: root.setConfig("action", currentText) }
                FieldLabel { text: "Device name filter (optional)"; visible: root.kindIs("evt_bluetooth") }
                GField { visible: root.kindIs("evt_bluetooth"); text: root.cfg("name", ""); icon: "link"
                    onAccepted: root.setConfig("name", value) }

                // ── evt_idle ────────────────────────────────────────────
                FieldLabel { text: "When the user is"; visible: root.kindIs("evt_idle") }
                Combo { visible: root.kindIs("evt_idle"); model: [ "idle", "active" ]
                    currentIndex: root.optionIndex(model, root.cfg("event", "idle"))
                    onActivated: root.setConfig("event", currentText) }
                FieldLabel { text: "Idle minutes"; visible: root.kindIs("evt_idle") }
                GField { visible: root.kindIs("evt_idle"); text: root.cfg("minutes", "5"); icon: "clock"
                    onAccepted: root.setConfig("minutes", value) }
                QQC2.Label { visible: root.kindIs("evt_idle"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Idle detection uses global input, so it needs the same input access as hotkeys."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── evt_startup ─────────────────────────────────────────
                QQC2.Label { visible: root.kindIs("evt_startup"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Runs once every time you log in (when the automations engine starts). No settings needed."
                    color: root.theme.textMid; font.pixelSize: 12 }

                // ── evt_log ─────────────────────────────────────────────
                FieldLabel { text: "File to tail"; visible: root.kindIs("evt_log") }
                GField { visible: root.kindIs("evt_log"); text: root.cfg("path", ""); icon: "file-text"
                    onAccepted: root.setConfig("path", value) }
                FieldLabel { text: "Match regex (optional)"; visible: root.kindIs("evt_log") }
                GField { visible: root.kindIs("evt_log"); text: root.cfg("pattern", ""); icon: "search"
                    onAccepted: root.setConfig("pattern", value) }

                // ── evt_command ─────────────────────────────────────────
                FieldLabel { text: "Command to poll"; visible: root.kindIs("evt_command") }
                GArea { visible: root.kindIs("evt_command"); text: root.cfg("command", "")
                    onAccepted: root.setConfig("command", value) }
                FieldLabel { text: "Fire when"; visible: root.kindIs("evt_command") }
                Combo { visible: root.kindIs("evt_command")
                    // Friendly labels; stored values stay exit0/error/match/
                    // changed (the daemon and old graphs use them).
                    property var vals: [ "exit0", "error", "match", "changed" ]
                    model: [ "command succeeds (ok)", "command fails (error)",
                             "output matches regex", "output changed since last check" ]
                    currentIndex: Math.max(0, vals.indexOf(root.cfg("on", "exit0")))
                    onActivated: root.setConfig("on", vals[currentIndex]) }
                FieldLabel { text: "Output matches regex"; visible: root.kindIs("evt_command") && root.cfg("on","exit0") === "match" }
                GField { visible: root.kindIs("evt_command") && root.cfg("on","exit0") === "match"; text: root.cfg("match", ""); icon: "search"
                    onAccepted: root.setConfig("match", value) }
                FieldLabel { text: "Check every (seconds)"; visible: root.kindIs("evt_command") }
                GField { visible: root.kindIs("evt_command"); text: root.cfg("interval", "30"); icon: "clock"
                    onAccepted: root.setConfig("interval", value) }
                QQC2.Label { visible: root.kindIs("evt_command"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "The regex is tested against the command's stdout AND stderr (error text like \"command not found\" lives on stderr). Commands run under /bin/sh, so shell messages may differ from your interactive shell (fish). Chained AFTER another block, this becomes a checker: it stops polling and runs once per chain, with the previous block's output in {input} / $GENESI_INPUT (leave the command empty to test that output directly). The chain only continues past it when the condition above holds."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_http ────────────────────────────────────────────
                FieldLabel { text: "URL"; visible: root.kindIs("act_http") }
                GField { visible: root.kindIs("act_http"); text: root.cfg("url", ""); icon: "link"
                    onAccepted: root.setConfig("url", value) }
                FieldLabel { text: "Method"; visible: root.kindIs("act_http") }
                Combo { visible: root.kindIs("act_http"); model: [ "GET", "POST", "PUT", "DELETE" ]
                    currentIndex: root.optionIndex(model, root.cfg("method", "GET"))
                    onActivated: root.setConfig("method", currentText) }
                FieldLabel { text: "Body (JSON)"; visible: root.kindIs("act_http") && root.cfg("method","GET") !== "GET" }
                GArea { visible: root.kindIs("act_http") && root.cfg("method","GET") !== "GET"; text: root.cfg("body", "")
                    onAccepted: root.setConfig("body", value) }

                // ── act_file ────────────────────────────────────────────
                FieldLabel { text: "Operation"; visible: root.kindIs("act_file") }
                Combo { visible: root.kindIs("act_file"); model: [ "copy", "move", "delete", "mkdir" ]
                    currentIndex: root.optionIndex(model, root.cfg("op", "copy"))
                    onActivated: root.setConfig("op", currentText) }
                FieldLabel { text: "Source"; visible: root.kindIs("act_file") && root.cfg("op","copy") !== "mkdir" }
                GField { visible: root.kindIs("act_file") && root.cfg("op","copy") !== "mkdir"; text: root.cfg("src", ""); icon: "folder"
                    onAccepted: root.setConfig("src", value) }
                FieldLabel { text: root.cfg("op","copy") === "mkdir" ? "Folder to create" : "Destination"; visible: root.kindIs("act_file") && root.cfg("op","copy") !== "delete" }
                GField { visible: root.kindIs("act_file") && root.cfg("op","copy") !== "delete"; text: root.cfg("dest", ""); icon: "folder"
                    onAccepted: root.setConfig("dest", value) }

                // ── act_app ─────────────────────────────────────────────
                FieldLabel { text: "Operation"; visible: root.kindIs("act_app") }
                Combo { visible: root.kindIs("act_app"); model: [ "launch", "close" ]
                    currentIndex: root.optionIndex(model, root.cfg("op", "launch"))
                    onActivated: root.setConfig("op", currentText) }
                FieldLabel { text: root.cfg("op","launch") === "close" ? "Process name" : "Command / app"; visible: root.kindIs("act_app") }
                GField { visible: root.kindIs("act_app"); text: root.cfg("app", ""); icon: "external-link"
                    onAccepted: root.setConfig("app", value) }

                // ── act_sound ───────────────────────────────────────────
                FieldLabel { text: "Sound file (empty = default beep)"; visible: root.kindIs("act_sound") }
                GField { visible: root.kindIs("act_sound"); text: root.cfg("sound", ""); icon: "bolt"
                    onAccepted: root.setConfig("sound", value) }

                // ── act_wait ────────────────────────────────────────────
                FieldLabel { text: "Wait (seconds)"; visible: root.kindIs("act_wait") }
                GField { visible: root.kindIs("act_wait"); text: root.cfg("seconds", "5"); icon: "clock"
                    onAccepted: root.setConfig("seconds", value) }
                QQC2.Label { visible: root.kindIs("act_wait"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Pauses the chain before the next block (up to 1 hour). The previous block's output passes through unchanged."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_power ───────────────────────────────────────────
                FieldLabel { text: "Action"; visible: root.kindIs("act_power") }
                Combo { visible: root.kindIs("act_power"); model: [ "lock", "suspend", "hibernate", "shutdown", "reboot", "logout" ]
                    currentIndex: root.optionIndex(model, root.cfg("op", "lock"))
                    onActivated: root.setConfig("op", currentText) }

                // ── run mode (events only) ──────────────────────────────
                FieldLabel { text: "After it triggers"; visible: root.isEvent }
                Combo {
                    visible: root.isEvent
                    model: [ "Keep running (always)", "Run once" ]
                    currentIndex: root.cfg("mode", "always") === "once" ? 1 : 0
                    onActivated: root.setConfig("mode", currentIndex === 1 ? "once" : "always")
                }

                // ── connections ─────────────────────────────────────────
                RowLayout {
                    visible: root.node && root.graphProvider && root.graphProvider.connectionsFor(root.node.id).length > 0
                    Layout.fillWidth: true; Layout.topMargin: 6
                    FieldLabel { text: "Connections" }
                    Item { Layout.fillWidth: true }
                }
                Repeater {
                    model: root.node && root.graphProvider ? root.graphProvider.connectionsFor(root.node.id) : []
                    delegate: Rectangle {
                        Layout.fillWidth: true; implicitHeight: 36; radius: 9
                        color: root.theme.cardHi; border.width: 1; border.color: root.theme.line
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 7
                            FIcon { name: "link"; size: 12; color: root.theme.greenBright }
                            QQC2.Label { text: modelData.label; color: root.theme.textMid; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                width: 24; height: 24; radius: 6
                                color: unlinkMa.containsMouse ? root.theme.a(root.theme.red, 0.16) : "transparent"
                                FIcon { anchors.centerIn: parent; name: "x"; size: 12; color: unlinkMa.containsMouse ? root.theme.red : root.theme.textLo }
                                MouseArea { id: unlinkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.graphProvider.removeLink(modelData.from, modelData.to, modelData.port) }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6; visible: root.node }
                GButton {
                    visible: root.node; theme: root.theme; kind: "danger"
                    text: "Delete Block"; iconSource: "icons/trash.svg"; Layout.fillWidth: true
                    onClicked: if (root.node) root.graphProvider.deleteNode(root.node.id)
                }
            }
        }
    }

    function kindIs(k) { return root.node && root.node.kind === k }
    function cfg(key, fallback) {
        return root.node && root.node.config && root.node.config[key] !== undefined ? root.node.config[key] : fallback
    }
    function cfgBool(key) { return cfg(key, false) === true }
    function aiExec() { return cfg("exec", cfgBool("autonomous") ? "auto" : "advisory") }
    function setConfig(key, value) {
        if (root.node && root.graphProvider) root.graphProvider.setNodeConfig(root.node.id, key, value)
    }
    function optionIndex(model, value) {
        for (var i = 0; i < model.length; i++) if (model[i] === value) return i
        return 0
    }
}
