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
        // Referenced by id rather than by parent.parent.parent: a Timer nested
        // in the TextField sits one level deeper than the handlers do, and
        // counting parents is how that silently starts calling the wrong thing.
        id: field
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
                onEditingFinished: field.accepted(text)
                // Save while typing, not only on Enter or focus loss. Clicking
                // straight from a field onto ANOTHER CARD swapped the panel out
                // before editingFinished ever arrived, so the text was simply
                // gone — and the block went on running with its previous value,
                // which is how an output name nobody had typed in a while kept
                // showing up in the error messages.
                //
                // Guarded on activeFocus because `text` is bound to the config:
                // a save rewrites the config, which rewrites the binding, which
                // would fire this again. Only a human holding focus starts it.
                onTextChanged: if (tf.activeFocus) fieldSave.restart()
                Timer {
                    id: fieldSave
                    interval: 350          // a pause in typing, not a keystroke
                    onTriggered: field.accepted(tf.text)
                }
            }
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
                onEditingFinished: area.accepted(text)
                // Same as GField: a prompt is the field people type most and
                // lose most. See there for why activeFocus guards it.
                onTextChanged: if (ta.activeFocus) areaSave.restart()
                Timer {
                    id: areaSave
                    interval: 350
                    onTriggered: area.accepted(ta.text)
                }
            }
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

                // Two blocks of the same kind publish the same names, so the
                // later one wins and the first one's value is gone — two App
                // cards fighting over {{app.name}} is how this was reported,
                // but two Run Scripts over {{stdout}} is the same bug. Only the
                // user can say which is which, so let them: this block's values
                // also arrive under a name they choose, which nothing else can
                // overwrite. Shown wherever the block actually publishes
                // something, so it never appears on a block it would do nothing
                // for. Slugged on the way in, like an AI output name.
                FieldLabel { text: "Value name (optional)"; visible: root.canName() }
                GField { visible: root.canName()
                    text: root.cfg("varName", ""); icon: "tag"
                    onAccepted: root.setConfig("varName", value ? root.slugPlain(value) : "") }
                QQC2.Label { visible: root.canName()
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: ("" + root.cfg("varName", "")).length === 0
                        ? "Give this block a name and its values are also published under it — " + root.handledExample("name") + " — so a second block of the same kind cannot overwrite them."
                        : "Also publishes " + root.provides(true) + ", which nothing else can overwrite."
                    color: root.theme.textLo; font.pixelSize: 10 }

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
                FieldLabel { text: "Process name — leave empty for ANY app"
                    visible: root.kindIs("evt_app") }
                GField { visible: root.kindIs("evt_app"); text: root.cfg("app", ""); icon: "box"
                    onAccepted: root.setConfig("app", value) }
                QQC2.Label { visible: root.kindIs("evt_app") && ("" + root.cfg("app", "")).length === 0
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Any app: this fires for whatever opens or closes, and {{app.name}} tells you which. Only installed applications count — background processes and helper scripts are ignored, which is what stopped this from firing every few seconds on an idle machine."
                    color: root.theme.textLo; font.pixelSize: 10 }
                FieldLabel { text: "When it"; visible: root.kindIs("evt_app") }
                Combo { visible: root.kindIs("evt_app"); model: [ "opened", "closed" ]
                    currentIndex: root.optionIndex(model, root.cfg("transition", "opened"))
                    onActivated: root.setConfig("transition", currentText) }
                // Only meaningful mid-chain, where the block WAITS instead of
                // triggering — so it only appears once something feeds into it.
                FieldLabel { text: "Give up after (seconds)"
                    visible: root.kindIs("evt_app") && root.isFed() }
                GField { visible: root.kindIs("evt_app") && root.isFed()
                    text: root.cfg("waitSeconds", "300"); icon: "clock"
                    onAccepted: root.setConfig("waitSeconds", value) }
                QQC2.Label { visible: root.kindIs("evt_app") && root.isFed()
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Something is connected INTO this block, so it waits here instead of starting the workflow: the chain pauses until the app is in that state. Name the app — \"any app\" cannot be waited for. If it never happens the block fails, so wire the on-error dot if you want to handle that."
                    color: root.theme.textLo; font.pixelSize: 10 }

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

                // ── evt_schedule: the visual cron builder ────────────────
                //
                // Cron is five fields of syntax that nobody remembers and
                // everybody gets wrong by one field. The pickers below WRITE
                // that syntax, and the sentence underneath reads the result
                // back in plain language — so the check is "does that sentence
                // describe what I wanted", not "did I count the asterisks".
                //
                // The raw field stays, and stays authoritative: anything the
                // pickers cannot express (a stepped range, a list of months)
                // can still be typed, and the pickers simply stop claiming to
                // describe it.
                FieldLabel { text: "…or build a schedule"; visible: root.kindIs("evt_schedule") }
                RowLayout {
                    visible: root.kindIs("evt_schedule")
                    Layout.fillWidth: true; spacing: 6
                    Combo {
                        id: cronEvery
                        Layout.preferredWidth: 132
                        model: ["every minute", "every 5 min", "every 15 min",
                                "every 30 min", "hourly", "daily", "weekly", "monthly"]
                        currentIndex: root.cronPreset()
                        onActivated: root.setConfig("cron", root.cronBuild(
                            currentIndex, cronHour.currentIndex, cronDay.currentIndex))
                    }
                    Combo {
                        id: cronHour
                        Layout.preferredWidth: 92
                        visible: cronEvery.currentIndex >= 5
                        model: root.hourList()
                        currentIndex: root.cronHourIndex()
                        onActivated: root.setConfig("cron", root.cronBuild(
                            cronEvery.currentIndex, currentIndex, cronDay.currentIndex))
                    }
                    Combo {
                        id: cronDay
                        Layout.fillWidth: true
                        visible: cronEvery.currentIndex === 6 || cronEvery.currentIndex === 7
                        model: cronEvery.currentIndex === 7
                            ? root.monthDayList()
                            : ["Sunday", "Monday", "Tuesday", "Wednesday",
                               "Thursday", "Friday", "Saturday"]
                        currentIndex: root.cronDayIndex()
                        onActivated: root.setConfig("cron", root.cronBuild(
                            cronEvery.currentIndex, cronHour.currentIndex, currentIndex))
                    }
                }
                // What the daemon will actually do, read back from the string.
                Rectangle {
                    visible: root.kindIs("evt_schedule") && ("" + root.cfg("cron", "")).length > 0
                    Layout.fillWidth: true
                    implicitHeight: cronRead.implicitHeight + 16
                    radius: 8
                    color: root.theme.cardHi
                    border.width: 1
                    border.color: root.cronValid() ? root.theme.line : root.theme.red
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 8
                        FIcon { size: 13; name: root.cronValid() ? "clock" : "alert"
                            color: root.cronValid() ? root.theme.greenBright : root.theme.red }
                        QQC2.Label {
                            id: cronRead
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: root.cronExplain()
                            color: root.cronValid() ? root.theme.textMid : root.theme.red
                            font.pixelSize: 11
                        }
                    }
                }

                FieldLabel { text: "…or a cron expression (optional)"; visible: root.kindIs("evt_schedule") }
                GField { visible: root.kindIs("evt_schedule"); text: root.cfg("cron", ""); icon: "code"
                    onAccepted: root.setConfig("cron", value) }
                QQC2.Label { visible: root.kindIs("evt_schedule"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "A cron expression wins over the two fields above. Use the pickers, or type it: five fields — minute hour day month weekday — with *, lists (0,30), ranges (9-17) and steps (*/15)."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_cond ────────────────────────────────────────────
                FieldLabel { text: "Decide with"; visible: root.kindIs("act_cond") }
                Combo { visible: root.kindIs("act_cond")
                    model: ["expression", "ai"]
                    currentIndex: root.optionIndex(["expression", "ai"],
                                                   root.cfg("mode", "expr") === "ai" ? "ai" : "expression")
                    onActivated: root.setConfig("mode", currentText === "ai" ? "ai" : "expr") }

                FieldLabel { text: "Condition"; visible: root.kindIs("act_cond") && root.cfg("mode", "expr") !== "ai" }
                GField { visible: root.kindIs("act_cond") && root.cfg("mode", "expr") !== "ai"
                    text: root.cfg("expr", ""); icon: "git-branch"
                    onAccepted: root.setConfig("expr", value) }
                QQC2.Label { visible: root.kindIs("act_cond") && root.cfg("mode", "expr") !== "ai"
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Compare values from the blocks above: {{cpu}} > 80, {{status}} == running, {input} contains error. Also startswith, endswith and matches (regex). A value on its own (true / 1 / yes) is read as a flag."
                    color: root.theme.textLo; font.pixelSize: 10 }

                FieldLabel { text: "Question for the AI"; visible: root.kindIs("act_cond") && root.cfg("mode", "expr") === "ai" }
                GArea { visible: root.kindIs("act_cond") && root.cfg("mode", "expr") === "ai"
                    text: root.cfg("prompt", "")
                    onAccepted: root.setConfig("prompt", value) }
                FieldLabel { text: "Model"; visible: root.kindIs("act_cond") && root.cfg("mode", "expr") === "ai" }
                Combo { visible: root.kindIs("act_cond") && root.cfg("mode", "expr") === "ai"
                    model: root.models
                    currentIndex: root.optionIndex(root.models, root.cfg("model", ""))
                    onActivated: root.setConfig("model", root.models[currentIndex]) }
                QQC2.Label { visible: root.kindIs("act_cond") && root.cfg("mode", "expr") === "ai"
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "The model answers your question about the incoming data with true or false. It cannot take any action while deciding. If it answers something that is neither, the block fails instead of guessing — wire the True and False dots to the two paths."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_loop ────────────────────────────────────────────
                FieldLabel { text: "Repeat over"; visible: root.kindIs("act_loop") }
                Combo { visible: root.kindIs("act_loop")
                    model: ["lines", "json", "list", "range"]
                    currentIndex: root.optionIndex(["lines", "json", "list", "range"], root.cfg("source", "lines"))
                    onActivated: root.setConfig("source", currentText) }
                FieldLabel { text: "Items (comma separated)"; visible: root.kindIs("act_loop") && root.cfg("source", "lines") === "list" }
                GField { visible: root.kindIs("act_loop") && root.cfg("source", "lines") === "list"
                    text: root.cfg("list", ""); icon: "layers"
                    onAccepted: root.setConfig("list", value) }
                RowLayout { visible: root.kindIs("act_loop") && root.cfg("source", "lines") === "range"
                    Layout.fillWidth: true; spacing: 8
                    GField { text: root.cfg("from", "1"); icon: "arrow-down"
                        onAccepted: root.setConfig("from", value) }
                    GField { text: root.cfg("to", "10"); icon: "arrow-up"
                        onAccepted: root.setConfig("to", value) } }
                FieldLabel { text: "Stop after (safety cap)"; visible: root.kindIs("act_loop") }
                GField { visible: root.kindIs("act_loop"); text: root.cfg("max", "100"); icon: "shield"
                    onAccepted: root.setConfig("max", value) }
                QQC2.Label { visible: root.kindIs("act_loop"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Everything wired to for each runs once per item, with {{item}}, {{index}} and {{count}} available inside. after runs once, when the loop is finished."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_subflow ─────────────────────────────────────────
                FieldLabel { text: "Workflow to run"; visible: root.kindIs("act_subflow") }
                Combo { visible: root.kindIs("act_subflow")
                    model: root.otherWorkflows()
                    currentIndex: root.optionIndex(root.otherWorkflows(), root.cfg("workflow", ""))
                    onActivated: root.setConfig("workflow", currentText) }
                QQC2.Label { visible: root.kindIs("act_subflow"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Runs another automation as one step of this one, then carries on. Values it publishes come back with it, so a workflow can be split into reusable pieces. A workflow cannot run itself, and nesting stops at three levels."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── act_email ───────────────────────────────────────────
                FieldLabel { text: "Do what"; visible: root.kindIs("act_email") }
                Combo { visible: root.kindIs("act_email")
                    model: ["send", "read"]
                    currentIndex: root.optionIndex(["send", "read"], root.cfg("mode", "send"))
                    onActivated: root.setConfig("mode", currentText) }
                FieldLabel { text: "Account (label in your keyring)"; visible: root.kindIs("act_email") }
                GField { visible: root.kindIs("act_email"); text: root.cfg("account", ""); icon: "user"
                    onAccepted: root.setConfig("account", value) }
                FieldLabel { text: root.cfg("mode", "send") === "read" ? "IMAP server" : "SMTP server"
                    visible: root.kindIs("act_email") }
                RowLayout { visible: root.kindIs("act_email"); Layout.fillWidth: true; spacing: 8
                    GField { text: root.cfg("host", ""); icon: "globe"
                        onAccepted: root.setConfig("host", value) }
                    GField { text: root.cfg("port", root.cfg("mode", "send") === "read" ? "993" : "587"); icon: "link"
                        onAccepted: root.setConfig("port", value) } }
                FieldLabel { text: "Username"; visible: root.kindIs("act_email") }
                GField { visible: root.kindIs("act_email"); text: root.cfg("user", ""); icon: "user"
                    onAccepted: root.setConfig("user", value) }

                FieldLabel { text: "To"; visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read" }
                GField { visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read"
                    text: root.cfg("to", ""); icon: "mail"
                    onAccepted: root.setConfig("to", value) }
                FieldLabel { text: "Subject"; visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read" }
                GField { visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read"
                    text: root.cfg("subject", ""); icon: "edit"
                    onAccepted: root.setConfig("subject", value) }
                FieldLabel { text: "Message"; visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read" }
                GArea { visible: root.kindIs("act_email") && root.cfg("mode", "send") !== "read"
                    text: root.cfg("body", "")
                    onAccepted: root.setConfig("body", value) }

                FieldLabel { text: "Folder"; visible: root.kindIs("act_email") && root.cfg("mode", "send") === "read" }
                GField { visible: root.kindIs("act_email") && root.cfg("mode", "send") === "read"
                    text: root.cfg("folder", "INBOX"); icon: "folder"
                    onAccepted: root.setConfig("folder", value) }
                FieldLabel { text: "How many"; visible: root.kindIs("act_email") && root.cfg("mode", "send") === "read" }
                GField { visible: root.kindIs("act_email") && root.cfg("mode", "send") === "read"
                    text: root.cfg("limit", "5"); icon: "archive"
                    onAccepted: root.setConfig("limit", value) }
                QQC2.Label { visible: root.kindIs("act_email") && root.cfg("mode", "send") === "read"
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "The newest unread messages arrive as {{mail.from}}, {{mail.subject}}, {{mail.body}} and {{mail.count}}, and the whole batch as JSON for a Loop."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // The password is NEVER stored in the workflow. Workflow files
                // get copied, shared in forum posts and synced between machines;
                // an app password in one would leak the first time somebody asked
                // for help with their automation.
                RowLayout { visible: root.kindIs("act_email"); Layout.fillWidth: true
                    Layout.topMargin: 8; spacing: 8
                    GButton { theme: root.theme; kind: "tonal"; text: "Store the password…"
                        enabled: ("" + root.cfg("account", "")).length > 0
                        onClicked: backend.storeEmailSecret(root.cfg("account", "")) }
                }
                QQC2.Label { visible: root.kindIs("act_email"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Use an app password, not your main one — Gmail and Outlook both issue them. It is kept in your system keyring, never in this workflow, so sharing the automation never shares the account."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── evt_clipboard ───────────────────────────────────────
                FieldLabel { text: "Only when it contains (optional)"; visible: root.kindIs("evt_clipboard") }
                GField { visible: root.kindIs("evt_clipboard"); text: root.cfg("contains", ""); icon: "search"
                    onAccepted: root.setConfig("contains", value) }
                RowToggle { visible: root.kindIs("evt_clipboard"); label: "Only when a link is copied"
                    value: root.cfgBool("onlyUrl")
                    onToggled: function(v) { root.setConfig("onlyUrl", v) } }
                QQC2.Label { visible: root.kindIs("evt_clipboard"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "The copied text arrives as {input}. What was already on the clipboard when you logged in never fires — only a change does."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── evt_screenshot ──────────────────────────────────────
                FieldLabel { text: "Folder to watch (optional)"; visible: root.kindIs("evt_screenshot") }
                GField { visible: root.kindIs("evt_screenshot"); text: root.cfg("path", ""); icon: "folder"
                    onAccepted: root.setConfig("path", value) }
                QQC2.Label { visible: root.kindIs("evt_screenshot"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Left empty, your screenshots folder is found automatically. The new image's full path arrives as {input}, so the next block can read, move or describe it."
                    color: root.theme.textLo; font.pixelSize: 10 }

                // ── evt_webhook ─────────────────────────────────────────
                FieldLabel { text: "Path"; visible: root.kindIs("evt_webhook") }
                GField { visible: root.kindIs("evt_webhook"); text: root.cfg("path", "hook"); icon: "link"
                    onAccepted: root.setConfig("path", value) }
                FieldLabel { text: "Port"; visible: root.kindIs("evt_webhook") }
                GField { visible: root.kindIs("evt_webhook"); text: root.cfg("port", "8737"); icon: "cloud"
                    onAccepted: root.setConfig("port", value) }
                FieldLabel { text: "Token (a shared secret)"; visible: root.kindIs("evt_webhook") }
                GField { visible: root.kindIs("evt_webhook"); text: root.cfg("token", ""); icon: "shield"
                    onAccepted: root.setConfig("token", value) }
                RowToggle { visible: root.kindIs("evt_webhook")
                    label: "Accept calls from the network (needs a token)"
                    value: root.cfgBool("bindAll")
                    onToggled: function(v) { root.setConfig("bindAll", v) } }
                QQC2.Label { visible: root.kindIs("evt_webhook"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "POST or GET to http://127.0.0.1:" + root.cfg("port", "8737") + "/" + ("" + root.cfg("path", "hook")).replace(/^\/+/, "") + " and the workflow runs; the request body arrives as {input}.\n\nIt listens on this machine only unless you turn the switch above on, and that switch does nothing without a token — a webhook runs commands, so an open port with no secret would be a shell for anyone on your network."
                    color: root.theme.textLo; font.pixelSize: 10 }

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
                Combo { id: aiModelCombo
                    visible: root.kindIs("act_ai"); model: root.models
                    currentIndex: root.optionIndex(root.models, root.cfg("model", ""))
                    // Values stay raw references (Ollama tags and `gguf:<stem>`)
                    // so a saved automation keeps working; only display changes.
                    displayText: backend.modelLabel(currentText)
                    delegate: QQC2.ItemDelegate {
                        width: aiModelCombo.width
                        text: backend.modelLabel(modelData)
                        highlighted: aiModelCombo.highlightedIndex === index
                    }
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

                // ── act_ai: named outputs ───────────────────────────────
                //
                // What turns the AI block from "prints a paragraph" into a
                // source of values. Each row is a field the model must return,
                // and every block after this one can then say {{name}}.
                RowLayout {
                    visible: root.kindIs("act_ai"); Layout.fillWidth: true
                    Layout.topMargin: 10; spacing: 8
                    QQC2.Label { text: "Outputs"; color: root.theme.textMid
                        font.pixelSize: 12; font.bold: true }
                    Item { Layout.fillWidth: true }
                    GButton { theme: root.theme; kind: "ghost"; text: "+ add"
                        onClicked: root.addOutput() }
                }
                Repeater {
                    model: root.kindIs("act_ai") ? root.outputs() : []
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 6
                        GField { text: modelData.name || ""; icon: "tag"
                            Layout.preferredWidth: 110
                            // Slugged on the way in, not rejected. Someone typed
                            // "RAM {{app.name}} usage" as a field name; the model
                            // was then asked for a key that {{ }} could never
                            // reference, and the block failed three steps later
                            // with a message about JSON. Correcting it here, in
                            // front of them, beats explaining it afterwards.
                            onAccepted: root.setOutput(index, "name",
                                                       root.slugName(value)) }
                        GField { text: modelData.desc || ""; icon: "edit"
                            onAccepted: root.setOutput(index, "desc", value) }
                        GButton { theme: root.theme; kind: "ghost"; text: "✕"
                            onClicked: root.removeOutput(index) }
                    }
                }
                QQC2.Label { visible: root.kindIs("act_ai") && root.badOutput() !== ""
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "\"" + root.badOutput() + "\" was changed: a field name has to be letters, digits and _ so it can be written as {{name}} later."
                    color: root.theme.turboBright; font.pixelSize: 10 }
                QQC2.Label { visible: root.kindIs("act_ai"); Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: root.outputs().length === 0
                        ? "With no outputs the block simply answers in prose, and the next block receives that text as {input}."
                        : "The model is told to reply with exactly these fields, and the blocks after this one can use them as {{" + (root.outputs()[0].name || "name") + "}}. If the reply is missing one, the block fails instead of passing half a result down the chain — wire the on error dot to catch that."
                    color: root.theme.textLo; font.pixelSize: 10 }


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


                // ── Values ──────────────────────────────────────────────
                //
                // Shown on EVERY block, because "which of these cards can give
                // me a number, and what is it called" was unanswerable without
                // reading the daemon. The top list is what the blocks before
                // this one publish — click one and it lands on the clipboard
                // ready to paste into any field. The bottom line is what THIS
                // block hands to the ones after it.
                Rectangle {
                    visible: root.node !== null && root.node !== undefined
                    Layout.fillWidth: true; Layout.topMargin: 14
                    implicitHeight: valuesCol.implicitHeight + 20
                    radius: 10
                    color: root.theme.bgTop
                    border.width: 1; border.color: root.theme.line

                    ColumnLayout {
                        id: valuesCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            FIcon { size: 13; name: "link"; color: root.theme.violet }
                            QQC2.Label {
                                text: "Values you can use here"
                                color: root.theme.textMid
                                font.pixelSize: 12; font.bold: true }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            visible: root.available().length === 0
                            text: "Nothing yet — connect a block into this one and whatever it produces shows up here."
                            color: root.theme.textLo; font.pixelSize: 10 }

                        Repeater {
                            model: root.available()
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 7
                                color: valMouse.containsMouse ? root.theme.cardHi : "transparent"
                                MouseArea {
                                    id: valMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyValue(modelData.name)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6; anchors.rightMargin: 6
                                    spacing: 8
                                    QQC2.Label {
                                        text: "{{" + modelData.name + "}}"
                                        color: root.theme.accentText
                                        font.family: root.theme.mono; font.pixelSize: 11 }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: modelData.desc || ""
                                        color: root.theme.textLo; font.pixelSize: 10
                                        elide: Text.ElideRight }
                                    FIcon {
                                        size: 12; name: "copy"
                                        visible: valMouse.containsMouse
                                        color: root.theme.textMid }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1
                            color: root.theme.line
                            visible: root.provides().length > 0 }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            visible: root.provides().length > 0
                            text: "This block then provides: " + root.provides()
                            color: root.theme.textLo; font.pixelSize: 10 }
                    }
                }

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
    // Every OTHER automation, by name. A workflow cannot call itself, so the
    // one being edited is left out of the list rather than offered and refused.
    // The declared outputs, always an array so the UI never has to guess.
    // ── cron, read and written ──────────────────────────────────────────────
    //
    // These mirror _cron_match in genesi-automationd. The daemon is the
    // authority on what a field MEANS; this side only has to write fields the
    // daemon understands and describe them back honestly. When it meets a field
    // it cannot describe, it says so instead of guessing — a schedule the user
    // was told runs "every weekday at 9" but actually runs hourly is worse than
    // one nobody explained.
    function hourList() {
        var out = []
        for (var h = 0; h < 24; h++) out.push((h < 10 ? "0" + h : "" + h) + ":00")
        return out
    }
    function monthDayList() {
        var out = []
        for (var d = 1; d <= 28; d++) out.push("day " + d)
        return out
    }
    function cronFields() {
        var raw = ("" + cfg("cron", "")).trim()
        return raw.length ? raw.split(/\s+/) : []
    }
    function cronValid() {
        var f = cronFields()
        if (f.length !== 5) return false
        for (var i = 0; i < 5; i++)
            if (!/^[\d*,\/-]+$/.test(f[i])) return false
        return true
    }
    // Which preset, if any, the current expression corresponds to. -1 means the
    // expression is hand-written and the pickers must not pretend to own it.
    function cronPreset() {
        var f = cronFields()
        if (f.length !== 5) return 5
        var m = f[0], h = f[1], dom = f[2], dow = f[4]
        if (m === "*") return 0
        if (m === "*/5") return 1
        if (m === "*/15") return 2
        if (m === "*/30") return 3
        if (h === "*" && dom === "*" && dow === "*") return 4
        if (dom === "*" && dow === "*") return 5
        if (dow !== "*") return 6
        if (dom !== "*") return 7
        return 5
    }
    function cronHourIndex() {
        var f = cronFields()
        var h = (f.length === 5) ? parseInt(f[1], 10) : 9
        return (isFinite(h) && h >= 0 && h < 24) ? h : 9
    }
    function cronDayIndex() {
        var f = cronFields()
        if (f.length !== 5) return 1
        if (f[4] !== "*") {
            var d = parseInt(f[4], 10)
            return (isFinite(d) && d >= 0 && d < 7) ? d : 1
        }
        var dom = parseInt(f[2], 10)
        return (isFinite(dom) && dom >= 1 && dom <= 28) ? dom - 1 : 0
    }
    function cronBuild(preset, hour, day) {
        var h = (hour >= 0 && hour < 24) ? hour : 9
        if (preset === 0) return "* * * * *"
        if (preset === 1) return "*/5 * * * *"
        if (preset === 2) return "*/15 * * * *"
        if (preset === 3) return "*/30 * * * *"
        if (preset === 4) return "0 * * * *"
        if (preset === 5) return "0 " + h + " * * *"
        if (preset === 6) return "0 " + h + " * * " + ((day >= 0 && day < 7) ? day : 1)
        if (preset === 7) return "0 " + h + " " + ((day >= 0 && day < 28) ? day + 1 : 1) + " * *"
        return "0 " + h + " * * *"
    }
    function cronField(part, unit) {
        if (part === "*") return "every " + unit
        if (part.indexOf("*/") === 0) return "every " + part.substring(2) + " " + unit + "s"
        if (part.indexOf("-") > 0) return unit + " " + part.replace("-", " to ")
        if (part.indexOf(",") >= 0) return unit + " " + part.replace(/,/g, ", ")
        return unit + " " + part
    }
    function cronExplain() {
        var f = cronFields()
        if (f.length !== 5)
            return "A cron expression needs exactly five fields: minute hour day month weekday."
        if (!cronValid())
            return "This is not a cron expression Genesi can read, so the schedule would never fire."
        var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
                    "Friday", "Saturday"]
        var m = f[0], h = f[1], dom = f[2], mon = f[3], dow = f[4]
        var when = ""
        if (m === "*" && h === "*") when = "Every minute"
        else if (m.indexOf("*/") === 0 && h === "*") when = "Every " + m.substring(2) + " minutes"
        else if (m === "0" && h === "*") when = "Every hour, on the hour"
        else if (h === "*") when = "At " + cronField(m, "minute") + " of every hour"
        else if (/^\d+$/.test(h) && /^\d+$/.test(m))
            when = "At " + (h.length < 2 ? "0" + h : h) + ":" + (m.length < 2 ? "0" + m : m)
        else when = "At " + cronField(h, "hour") + ", " + cronField(m, "minute")

        var scope = ""
        if (dow !== "*") {
            if (/^\d$/.test(dow)) scope = " on " + days[parseInt(dow, 10)] + "s"
            else if (dow === "1-5") scope = " on weekdays"
            else scope = " on weekdays " + dow
        } else if (dom !== "*") {
            scope = /^\d+$/.test(dom) ? " on day " + dom + " of the month"
                                      : " on days " + dom
        }
        if (mon !== "*") scope += " (months " + mon + ")"
        return when + scope + "."
    }

    // What the blocks upstream of this one publish, and what this one publishes
    // in turn. Both come from the catalogue the daemon actually uses, so the
    // panel cannot promise a value that does not exist at run time.
    function available() {
        if (!root.node || !root.graphProvider) return []
        return root.graphProvider.upstreamOutputs(root.node.id)
    }
    // Does this block publish anything? Only then is a value name any use.
    function canName() {
        if (!root.node || !root.graphProvider) return false
        var cat = root.graphProvider.outputCatalogue[root.node.kind] || []
        for (var i = 0; i < cat.length; i++)
            if (("" + cat[i].name).indexOf("<") !== 0) return true
        return root.node.kind === "act_ai"
    }
    function handledExample(handle) {
        if (!root.node || !root.graphProvider) return ""
        var cat = root.graphProvider.outputCatalogue[root.node.kind] || []
        for (var i = 0; i < cat.length; i++) {
            if (("" + cat[i].name).indexOf("<") === 0) continue
            return "{{" + handle + "." + ("" + cat[i].name).split(".").pop() + "}}"
        }
        return "{{" + handle + ".value}}"
    }
    function provides(handledOnly) {
        if (!root.node || !root.graphProvider) return ""
        var cat = root.graphProvider.outputCatalogue[root.node.kind] || []
        var names = []
        if (root.node.kind === "act_ai") {
            var declared = root.outputs()
            for (var d = 0; d < declared.length; d++)
                if (declared[d].name) names.push("{{" + declared[d].name + "}}")
        }
        var handle = ("" + root.cfg("varName", "")).trim()
        if (handledOnly) names = []
        for (var i = 0; i < cat.length; i++) {
            if (("" + cat[i].name).indexOf("<") === 0) continue
            // The block's own prefix first: it is the name nothing else can
            // overwrite, which is the reason to have named the block at all.
            if (handle)
                names.push("{{" + handle + "." + ("" + cat[i].name).split(".").pop() + "}}")
            if (!handledOnly) names.push("{{" + cat[i].name + "}}")
        }
        return names.join(", ")
    }
    function copyValue(name) {
        // Copy rather than insert: the panel does not know which of a block's
        // fields the user is aiming at, and pasting into the wrong one is a
        // worse outcome than one extra keystroke.
        backend.copyToClipboard("{{" + name + "}}")
    }
    // Does anything link INTO this block? An event block with an incoming link
    // stops being a trigger and becomes a step in the chain, which changes what
    // its settings mean — so the panel has to know.
    // The same shape the daemon accepts (_VAR_NAME_RE): what {{ }} can resolve.
    property string lastSlugged: ""
    // The shape without the bookkeeping. lastSlugged drives a warning that
    // belongs to the AI block's output rows, so anything ELSE that needs a slug
    // (an App block's value name) must not leave a stale warning behind for the
    // next block the user clicks.
    function slugPlain(raw) {
        var clean = ("" + raw).trim().replace(/[^A-Za-z0-9_]+/g, "_")
                              .replace(/^_+|_+$/g, "").toLowerCase()
        if (clean.length === 0) clean = "value"
        if (/^[0-9]/.test(clean)) clean = "v" + clean
        return clean
    }
    function slugName(raw) {
        var clean = slugPlain(raw)
        lastSlugged = (clean !== ("" + raw).trim()) ? ("" + raw).trim() : ""
        return clean
    }
    function badOutput() { return lastSlugged }
    function isFed() {
        if (!root.node || !root.graphProvider) return false
        var links = root.graphProvider.links || []
        for (var i = 0; i < links.length; i++)
            if (links[i].to === root.node.id) return true
        return false
    }
    function outputs() {
        var v = cfg("outputs", [])
        return (v && v.length !== undefined) ? v : []
    }
    function addOutput() {
        var list = outputs().slice()
        list.push({ name: "", desc: "" })
        setConfig("outputs", list)
    }
    function setOutput(index, key, value) {
        var list = outputs().slice()
        if (index < 0 || index >= list.length) return
        var row = { name: list[index].name || "", desc: list[index].desc || "" }
        row[key] = value
        list[index] = row
        setConfig("outputs", list)
    }
    function removeOutput(index) {
        var list = outputs().slice()
        if (index < 0 || index >= list.length) return
        list.splice(index, 1)
        setConfig("outputs", list)
    }
    function otherWorkflows() {
        var out = []
        try {
            var store = JSON.parse(backend.listAutomations())
            var items = store.items || []
            for (var i = 0; i < items.length; i++)
                if (!root.graphProvider || items[i].id !== root.graphProvider.activeId)
                    out.push(items[i].name)
        } catch (e) { }
        return out
    }
    function optionIndex(model, value) {
        for (var i = 0; i < model.length; i++) if (model[i] === value) return i
        return 0
    }
}
