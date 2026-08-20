/*
 * Genesi AI Mode Monitor — the Automations canvas. Adapted from the Forge Canvas
 * (CanvasView.qml): same fixed SHEET (2400×1500) inside a Flickable with native
 * pan + scaled zoom, the same drag-and-drop palette, nodes, bezier links, minimap
 * and undo — but retargeted from project/git automation to PC-wide automation.
 *
 * The graphs are stored top-level (not per-project) via the Monitor Backend's
 * automation slots, and they are RUN by genesi-automationd in the background, so
 * this view is purely an editor + a live status/log window. All node/link
 * coordinates live in sheet space.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    signal toast(string msg)

    readonly property real sheetW: 2400
    readonly property real sheetH: 1500

    property var nodes: []
    property var links: []
    property var livePos: ({})
    property string selectedId: ""
    property real zoom: 1.0

    // Responsive: the Monitor often runs tiled/half-screen or on small displays.
    // Below these widths the side panels shrink and the header buttons drop
    // their labels, so the sheet keeps usable space instead of being crushed
    // (reported 2026-07-18: the tab "broke" whenever the window wasn't
    // fullscreen).
    readonly property bool compact: width < 1080
    readonly property bool tight: width < 900

    property var automations: []
    property string activeId: ""
    property string activeName: "Automation"
    property bool activeEnabled: false
    property bool ready: false
    property bool hotkeyAvailable: false

    property var genModels: []
    property var undoStack: []
    property bool restoringHistory: false

    property string pendingFrom: ""
    property string pendingPort: ""
    property real pendingX: 0
    property real pendingY: 0

    // ── result ports ────────────────────────────────────────────────────────
    // Action kinds listed here grow two output dots — on ok (green) and on
    // error (red) — and genesi-automationd follows a link only when its port
    // matches the node's result. A link from the single default dot (every
    // other kind) always fires. The Command sensor deliberately keeps ONE dot:
    // its own properties (Fire when: exit0 / match / regex) define the
    // condition, and chained mid-flow it GATES the chain — the single output
    // only fires when that condition holds (user feedback 2026-07-19: three
    // dots there duplicated what the properties already say). Mirrors
    // PORT_KINDS + the run_chain gate in the daemon.
    // A Condition answers rather than succeeds, so its dots are True/False —
    // the shape everyone already reads in a flowchart. A Loop's dots are the
    // body and what comes after it. Both mirror COND_KINDS / LOOP_KINDS and the
    // routing in the daemon's _walk; if these two ever disagree, the canvas is
    // drawing a graph that is not the one that runs.
    function portsFor(kind) {
        if (kind === "act_cond")
            return [ { port: "true",  label: "True",  color: theme.greenBright },
                     { port: "false", label: "False", color: theme.turbo } ]
        if (kind === "act_loop")
            return [ { port: "each", label: "for each", color: theme.violet },
                     { port: "done", label: "after",    color: theme.blue } ]
        if (kind === "act_script" || kind === "act_ai" || kind === "act_http"
                || kind === "act_file")
            return [ { port: "ok",  label: "on ok",    color: theme.greenBright },
                     { port: "err", label: "on error", color: theme.red } ]
        return []
    }
    // "output" is a LEGACY port: its dot was removed in pkgrel 130 and the
    // daemon now treats such a link as a plain default link (it used to fire on
    // "any output produced", which bypassed a Command sensor's gate entirely).
    // Render it like a default link so the canvas matches what actually runs.
    function portColor(port) {
        if (port === "ok" || port === "true") return theme.greenBright
        if (port === "err") return theme.red
        if (port === "false") return theme.turbo
        if (port === "each") return theme.violet
        if (port === "done") return theme.blue
        return null
    }
    function portLabel(port) {
        if (port === "ok") return "on ok"
        if (port === "err") return "on error"
        if (port === "true") return "True"
        if (port === "false") return "False"
        if (port === "each") return "for each"
        if (port === "done") return "after"
        return ""
    }
    // Sheet-space point a link leaves a node from (must mirror the dot layout
    // in CanvasNode.qml: 16px dots, 10px spacing, vertically centered).
    function portPoint(id, port) {
        var p = livePos[id]
        if (!p) return { x: 0, y: 0 }
        var x = p.x + (p.w || 214)
        var n = null
        for (var i = 0; i < nodes.length; i++)
            if (nodes[i].id === id) { n = nodes[i]; break }
        var ports = n ? portsFor(n.kind) : []
        var idx = -1
        for (var j = 0; j < ports.length; j++)
            if (ports[j].port === port) { idx = j; break }
        // No ports, no port on the link, or an unknown/legacy port name → the
        // link leaves from the card's mid-height default point.
        if (!ports.length || !port || idx < 0)
            return { x: x, y: p.y + (p.h || 120) / 2 }
        var total = ports.length * 16 + (ports.length - 1) * 10
        return { x: x, y: p.y + ((p.h || 120) - total) / 2 + idx * 26 + 8 }
    }

    Shortcut {
        sequence: StandardKey.Undo
        enabled: root.ready && root.undoStack.length > 0
        onActivated: root.undo()
    }

    Component.onCompleted: {
        backend.ensureAutomationDaemon()
        Qt.callLater(initialize)
    }

    function selectedNode() {
        for (var i = 0; i < nodes.length; i++)
            if (nodes[i].id === selectedId) return nodes[i]
        return null
    }

    function graphJson() {
        var out = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            var p = livePos[n.id] || { x: n.x, y: n.y }
            out.push({ id: n.id, kind: n.kind, title: n.title, icon: n.icon,
                       accentKey: n.accentKey || "green", x: p.x, y: p.y,
                       lines: n.lines || [], config: n.config || ({}) })
        }
        return JSON.stringify({ id: activeId, name: activeName, nodes: out, links: links })
    }

    function accentFor(key) {
        if (key === "purple") return theme.purple
        if (key === "blue") return theme.blue
        if (key === "turbo") return theme.turbo
        if (key === "red") return theme.red
        return theme.green
    }

    // ── automation store (Backend slots → genesi-automationd) ───────────────
    function initialize() {
        var store = JSON.parse(backend.listAutomations())
        automations = store.items || []
        if (!automations.length) {
            var id = backend.createAutomation("My first automation")
            automations = [ { id: id, name: "My first automation", enabled: false, nodes: 0 } ]
            switchTo(id)
        } else {
            switchTo(automations[0].id)
        }
    }

    function refreshList() {
        var store = JSON.parse(backend.listAutomations())
        automations = store.items || []
        var sel = 0
        for (var i = 0; i < automations.length; i++) if (automations[i].id === activeId) sel = i
        autoPicker.currentIndex = sel
    }

    function persist() {
        if (ready && activeId) backend.saveAutomation(activeId, activeName, graphJson())
    }

    function switchTo(id) {
        if (!id || (ready && id === activeId)) return
        persist()
        var graph = JSON.parse(backend.loadAutomation(id))
        activeId = id
        applyGraph(graph)
        clearHistory()
        ready = true
        refreshList()
        nameField.text = activeName
    }

    function applyGraph(graph) {
        var incoming = graph.nodes || []
        for (var i = 0; i < incoming.length; i++) {
            incoming[i].accentKey = incoming[i].accentKey || "green"
            incoming[i].accent = accentFor(incoming[i].accentKey)
            incoming[i].config = incoming[i].config || ({})
            incoming[i].lines = summaryLines(incoming[i])
            incoming[i].status = ""
            incoming[i].statusKind = "ok"
        }
        livePos = ({})
        nodes = incoming
        links = graph.links || []
        activeName = graph.name || "Automation"
        activeEnabled = graph.enabled || false
        selectedId = nodes.length ? nodes[0].id : ""
        Qt.callLater(function() { linkLayer.requestPaint(); miniMap.requestPaint() })
    }

    // ── undo ────────────────────────────────────────────────────────────────
    function clearHistory() { undoStack = [] }
    function recordHistory() {
        if (restoringHistory || !ready) return
        var history = undoStack.slice()
        history.push(graphJson())
        if (history.length > 50) history.shift()
        undoStack = history
    }
    function undo() {
        if (!undoStack.length) return
        var history = undoStack.slice()
        var snap = history.pop()
        undoStack = history
        restoringHistory = true
        applyGraph(JSON.parse(snap))
        restoringHistory = false
        scheduleSave()
        toast("Last change undone.")
    }

    // Debounced autosave — every mutation nudges this; the daemon reloads on save.
    Timer {
        id: saveTimer
        interval: 700; repeat: false
        onTriggered: root.persist()
    }
    function scheduleSave() { if (ready) saveTimer.restart() }

    // ── node summary lines (what the card shows under the title) ────────────
    function baseName(p) {
        if (!p) return ""
        var s = ("" + p).replace(/\/+$/, "")
        var i = s.lastIndexOf("/")
        return i >= 0 ? s.substring(i + 1) : s
    }
    function summaryLines(n) {
        var c = n.config || ({})
        var out = []
        if (n.kind === "evt_fs") {
            out.push((c.change || "any") + " in " + (baseName(c.path) || "?"))
            if (c.pattern && c.pattern !== "*") out.push("match " + c.pattern)
            if (c.recursive) out.push("recursive")
        } else if (n.kind === "evt_resource") {
            out.push((c.metric || "cpu").toUpperCase() + " " + (c.op || ">") + " " + (c.threshold || "80") + "%")
        } else if (n.kind === "evt_temperature") {
            out.push("temp > " + (c.threshold || "80") + "°C" + (c.sensor ? (" (" + c.sensor + ")") : ""))
        } else if (n.kind === "evt_app") {
            out.push((c.transition || "opened") + ": " + (c.app || "—"))
        } else if (n.kind === "evt_process") {
            out.push((c.app || "?") + " " + (c.metric || "mem") + " > " + (c.threshold || "1000") + (c.metric === "cpu" ? "%" : "MB"))
        } else if (n.kind === "evt_power") {
            var pe = c.event || "on_battery"
            out.push(pe === "on_ac" ? "AC plugged in" : pe === "on_battery" ? "on battery"
                   : pe === "battery_below" ? ("battery < " + (c.level || "20") + "%")
                   : ("battery > " + (c.level || "20") + "%"))
        } else if (n.kind === "evt_disk") {
            var de = c.event || "usage_above"
            out.push(de === "usage_above" ? ((c.path || "/") + " > " + (c.threshold || "90") + "%")
                   : de === "mounted" ? "a drive is mounted" : "a drive is unmounted")
        } else if (n.kind === "evt_usb") {
            out.push("USB " + (c.action || "added"))
        } else if (n.kind === "evt_network") {
            var ne = c.event || "online"
            out.push(ne === "online" ? "internet online" : ne === "offline" ? "internet offline"
                   : ((c.iface || "iface") + " " + (ne === "iface_up" ? "up" : "down")))
        } else if (n.kind === "evt_bluetooth") {
            out.push("BT " + (c.action || "connected") + (c.name ? (": " + c.name) : ""))
        } else if (n.kind === "evt_idle") {
            out.push((c.event === "active") ? "back from idle" : ("idle " + (c.minutes || "5") + " min"))
        } else if (n.kind === "evt_hotkey") {
            out.push(c.combo ? c.combo : "press Capture to set")
        } else if (n.kind === "evt_schedule") {
            out.push(c.cron ? ("cron " + c.cron)
                   : c.time ? ("at " + c.time)
                   : ("every " + (c.interval || "60") + " min"))
        } else if (n.kind === "evt_clipboard") {
            out.push(c.onlyUrl ? "a link is copied"
                   : c.contains ? ("copied ~ " + c.contains) : "anything is copied")
        } else if (n.kind === "evt_screenshot") {
            out.push("a screenshot is taken")
            if (c.path) out.push("in " + baseName(c.path))
        } else if (n.kind === "evt_webhook") {
            out.push("POST /" + ((c.path || "hook").replace(/^\/+/, "")))
            out.push(c.token ? ("port " + (c.port || 8737) + " · token set")
                             : ("port " + (c.port || 8737) + " · no token"))
        } else if (n.kind === "evt_startup") {
            out.push("on login / boot")
        } else if (n.kind === "evt_log") {
            out.push((baseName(c.path) || "a file") + (c.pattern ? (" ~ " + c.pattern) : " new line"))
        } else if (n.kind === "evt_command") {
            out.push(c.command ? ("" + c.command).split("\n")[0].substring(0, 26) : "no command")
            out.push("on " + (c.on || "exit0"))
        } else if (n.kind === "evt_manual") {
            out.push("Run on demand")
        } else if (n.kind === "act_cond") {
            out.push((c.mode === "ai") ? (c.prompt ? ("ask: " + ("" + c.prompt).substring(0, 26))
                                                   : "no question")
                                       : (c.expr || "no condition"))
        } else if (n.kind === "act_loop") {
            var src = c.source || "lines"
            out.push(src === "list" ? ("list: " + (c.list || "—"))
                   : src === "range" ? ((c.from || 1) + " → " + (c.to || 0))
                   : src === "json" ? "each JSON item" : "each input line")
            out.push("max " + (c.max || 100))
        } else if (n.kind === "act_subflow") {
            out.push(c.workflow ? ("run: " + c.workflow) : "pick a workflow")
        } else if (n.kind === "act_email") {
            out.push((c.mode === "read") ? ("read " + (c.folder || "INBOX"))
                                         : ("send → " + (c.to || "—")))
            out.push(c.account || "no account")
        } else if (n.kind === "act_script") {
            out.push(c.command ? ("" + c.command).split("\n")[0].substring(0, 30) : "no command")
            if (c.terminal) out.push("in a terminal window")
        } else if (n.kind === "act_ai") {
            out.push(c.model ? c.model : "pick a model")
            var ex = c.exec || (c.autonomous ? "auto" : "advisory")
            out.push((c.turbo ? "Turbo" : "Ollama") + " · " + (ex === "auto" ? "autonomous" : ex === "ask" ? "ask first" : "advisory"))
        } else if (n.kind === "act_notify") {
            out.push(c.title || "Notification")
        } else if (n.kind === "act_http") {
            out.push((c.method || "GET") + " " + (baseName(c.url) || c.url || "url"))
        } else if (n.kind === "act_file") {
            out.push((c.op || "copy") + " " + (baseName(c.src) || baseName(c.dest) || "…"))
        } else if (n.kind === "act_app") {
            out.push((c.op || "launch") + " " + (c.app || "—"))
        } else if (n.kind === "act_sound") {
            out.push(c.sound ? baseName(c.sound) : "play a beep")
        } else if (n.kind === "act_wait") {
            out.push("wait " + (c.seconds || "5") + "s")
        } else if (n.kind === "act_power") {
            out.push(c.op || "lock")
        }
        if (n.kind.indexOf("evt_") === 0)
            out.push((c.mode === "once") ? "runs once" : "always on")
        return out
    }

    function updatePos(id, x, y, w, h) {
        livePos[id] = { x: x, y: y, w: w, h: h }
        linkLayer.requestPaint(); miniMap.requestPaint()
    }
    function nodeAccent(id) {
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i].accent
        return theme.green
    }
    function nodeTitle(id) {
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i].title
        return id
    }
    // Per-node run indicator driven by the daemon's live status. While the
    // automation is firing, every node glows "running" (blue, spinning pill);
    // when it's armed and idle, its event nodes show an amber "Waiting for
    // event" pill — so it's obvious at a glance whether it's listening or busy.
    // Per-node run state straight from the daemon (nodeStates: id -> running |
    // ok | failed | skipped). Previously a single per-automation `running` bool
    // lit EVERY card blue, so you couldn't see which path the flow took
    // (reported 2026-07-19). Falls back to the armed "Waiting for event" hint
    // on trigger blocks when nothing is running.
    property var nodeStates: ({})

    function nodeRunState(n) {
        if (!n) return ""
        var s = nodeStates[n.id]
        if (s === "running") return "running"
        if (s === "ok") return "done"
        if (s === "failed") return "failed"
        if (s === "skipped") return "skipped"
        if (running) return ""
        if (activeEnabled && ("" + n.kind).indexOf("evt_") === 0 && n.kind !== "evt_manual")
            return "waiting"
        return ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                width: 34; height: 34; radius: 9
                color: root.theme.a(root.theme.green, 0.14)
                FIcon { anchors.centerIn: parent; name: "zap"; size: 17; color: root.theme.greenBright }
            }
            ColumnLayout {
                spacing: 0
                QQC2.Label { text: "Automations"; color: root.theme.textHi
                    font.family: root.theme.display; font.pixelSize: 18; font.bold: true }
                QQC2.Label { text: "Automate anything on your PC — runs in the background"
                    visible: !root.compact
                    color: root.theme.textLo; font.pixelSize: 11 }
            }
            Item { Layout.fillWidth: true }

            // Enabled switch (drives genesi-automationd)
            RowLayout {
                spacing: 7
                Rectangle { width: 8; height: 8; radius: 4
                    color: root.activeEnabled ? root.theme.greenBright : root.theme.textLo }
                QQC2.Label { text: root.activeEnabled ? "Enabled" : "Disabled"
                    visible: !root.tight
                    color: root.activeEnabled ? root.theme.greenBright : root.theme.textMid; font.pixelSize: 12 }
                GToggle { theme: root.theme; checked: root.activeEnabled
                    onToggled: function(v) { root.activeEnabled = v; backend.setAutomationEnabled(root.activeId, v)
                        root.toast(v ? "Automation enabled — running in background." : "Automation disabled.") } }
            }

            QQC2.ComboBox {
                id: autoPicker
                Layout.preferredWidth: root.tight ? 136 : (root.compact ? 170 : 210); implicitHeight: 38
                model: root.automations; textRole: "name"
                background: Rectangle { radius: 8; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi }
                contentItem: QQC2.Label { leftPadding: 11; rightPadding: 28; text: autoPicker.displayText
                    color: root.theme.textHi; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                onActivated: root.switchTo(root.automations[currentIndex].id)
            }
            GButton { theme: root.theme; kind: "ghost"; iconSource: "icons/copy.svg"; tooltip: "Duplicate"
                onClicked: { var id = backend.duplicateAutomation(root.activeId); root.refreshList(); root.switchTo(id) } }
            GButton { theme: root.theme; kind: "ghost"; iconSource: "icons/trash.svg"; tooltip: "Delete"
                enabled: root.automations.length > 1
                onClicked: { backend.deleteAutomation(root.activeId); root.activeId = ""; root.ready = false; root.initialize() } }
            GButton { theme: root.theme; kind: "tonal"; text: root.tight ? "" : "New"; iconSource: "icons/plus.svg"
                tooltip: root.tight ? "New automation" : ""
                onClicked: { var id = backend.createAutomation("New automation"); root.refreshList(); root.switchTo(id) } }
            GButton { theme: root.theme; kind: "tonal"; text: root.tight ? "" : "Build with AI"; iconSource: "icons/bot.svg"
                tooltip: "Describe an automation and have it built"
                onClicked: { backend.loadModels(); genPopup.open() } }
            GButton { theme: root.theme; kind: "tonal"; text: root.tight ? "" : "Template"; iconSource: "icons/layout-grid.svg"
                tooltip: root.tight ? "Start from a template" : ""
                onClicked: templatePopup.open() }
            GButton { theme: root.theme; kind: "filled"; text: root.tight ? "" : "Run now"; iconSource: "icons/play.svg"
                tooltip: "Test run: runs the actions now, without waiting for the trigger"
                onClicked: { root.showLog = true; backend.runAutomationNow(root.activeId); root.toast("Test run — running the actions now…") } }
        }

        // ── Body: palette | canvas | config ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Palette
            FCard {
                theme: root.theme
                Layout.preferredWidth: root.compact ? 190 : 232
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 9
                    QQC2.Label { text: "Blocks"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                    QQC2.Label { text: "Drag onto the canvas: an event, then what to do"; color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap }

                    QQC2.ScrollView {
                        id: paletteScroll
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ColumnLayout {
                            width: paletteScroll.availableWidth
                            spacing: 5
                            Repeater {
                                model: [
                                    { section: "EVENTS (WHEN…)" },
                                    { label: "File / folder change", icon: "folder", accent: root.theme.turbo, accentKey: "turbo", kind: "evt_fs" },
                                    { label: "CPU / RAM threshold", icon: "cpu", accent: root.theme.blue, accentKey: "blue", kind: "evt_resource" },
                                    { label: "Temperature", icon: "alert", accent: root.theme.red, accentKey: "red", kind: "evt_temperature" },
                                    { label: "App opens / closes", icon: "box", accent: root.theme.purple, accentKey: "purple", kind: "evt_app" },
                                    { label: "Process CPU / RAM", icon: "sliders", accent: root.theme.purple, accentKey: "purple", kind: "evt_process" },
                                    { label: "Power / battery", icon: "bolt", accent: root.theme.turbo, accentKey: "turbo", kind: "evt_power" },
                                    { label: "Disk usage / mount", icon: "database", accent: root.theme.blue, accentKey: "blue", kind: "evt_disk" },
                                    { label: "USB device", icon: "archive", accent: root.theme.green, accentKey: "green", kind: "evt_usb" },
                                    { label: "Network on / off", icon: "globe", accent: root.theme.blue, accentKey: "blue", kind: "evt_network" },
                                    { label: "Bluetooth device", icon: "link", accent: root.theme.blue, accentKey: "blue", kind: "evt_bluetooth" },
                                    { label: "User idle / active", icon: "user", accent: root.theme.green, accentKey: "green", kind: "evt_idle" },
                                    { label: "Hotkey / keys", icon: "terminal", accent: root.theme.green, accentKey: "green", kind: "evt_hotkey" },
                                    { label: "Schedule / interval", icon: "clock", accent: root.theme.blue, accentKey: "blue", kind: "evt_schedule" },
                                    { label: "On startup / login", icon: "rocket", accent: root.theme.green, accentKey: "green", kind: "evt_startup" },
                                    { label: "Log line match", icon: "file-text", accent: root.theme.turbo, accentKey: "turbo", kind: "evt_log" },
                                    { label: "Command sensor", icon: "search", accent: root.theme.purple, accentKey: "purple", kind: "evt_command" },
                                    { label: "Clipboard copy", icon: "copy", accent: root.theme.purple, accentKey: "purple", kind: "evt_clipboard" },
                                    { label: "Screenshot taken", icon: "image", accent: root.theme.turbo, accentKey: "turbo", kind: "evt_screenshot" },
                                    { label: "Webhook (HTTP)", icon: "cloud", accent: root.theme.blue, accentKey: "blue", kind: "evt_webhook" },
                                    { label: "Manual trigger", icon: "play", accent: root.theme.green, accentKey: "green", kind: "evt_manual" },
                                    { section: "ACTIONS (DO…)" },
                                    { label: "Condition (if / else)", icon: "git-branch", accent: root.theme.turbo, accentKey: "turbo", kind: "act_cond" },
                                    { label: "Loop / for each", icon: "refresh-cw", accent: root.theme.purple, accentKey: "purple", kind: "act_loop" },
                                    { label: "Sub-workflow", icon: "layers", accent: root.theme.blue, accentKey: "blue", kind: "act_subflow" },
                                    { label: "Email (send / read)", icon: "mail", accent: root.theme.green, accentKey: "green", kind: "act_email" },
                                    { label: "Run Script", icon: "terminal", accent: root.theme.purple, accentKey: "purple", kind: "act_script" },
                                    { label: "AI Action", icon: "bot", accent: root.theme.turbo, accentKey: "turbo", kind: "act_ai" },
                                    { label: "Notification", icon: "alert", accent: root.theme.green, accentKey: "green", kind: "act_notify" },
                                    { label: "HTTP request", icon: "cloud", accent: root.theme.blue, accentKey: "blue", kind: "act_http" },
                                    { label: "File operation", icon: "copy", accent: root.theme.green, accentKey: "green", kind: "act_file" },
                                    { label: "Launch / close app", icon: "external-link", accent: root.theme.purple, accentKey: "purple", kind: "act_app" },
                                    { label: "Play sound", icon: "bolt", accent: root.theme.turbo, accentKey: "turbo", kind: "act_sound" },
                                    { label: "Wait / delay", icon: "clock", accent: root.theme.blue, accentKey: "blue", kind: "act_wait" },
                                    { label: "Power (lock / suspend…)", icon: "lock", accent: root.theme.red, accentKey: "red", kind: "act_power" }
                                ]
                                delegate: Item {
                                    Layout.fillWidth: true
                                    implicitHeight: modelData.section !== undefined ? 24 : 44
                                    QQC2.Label {
                                        visible: modelData.section !== undefined
                                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                                        text: modelData.section || ""
                                        color: root.theme.textLo; font.pixelSize: 9; font.bold: true
                                    }
                                    PaletteItem {
                                        visible: modelData.section === undefined
                                        anchors.fill: parent
                                        theme: root.theme
                                        label: modelData.label || ""
                                        icon: modelData.icon || ""
                                        kind: modelData.kind || ""
                                        accent: modelData.accent || root.theme.green
                                        dragGhost: dragGhost
                                        onAdd: root.addNode(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // Hotkey availability hint (evdev needs the 'input' group).
                    Rectangle {
                        visible: !root.hotkeyAvailable
                        Layout.fillWidth: true; Layout.preferredHeight: hkCol.implicitHeight + 16
                        radius: 9; color: root.theme.a(root.theme.turbo, 0.10)
                        border.width: 1; border.color: root.theme.a(root.theme.turbo, 0.30)
                        ColumnLayout {
                            id: hkCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 8; spacing: 2
                            QQC2.Label { text: "Hotkeys need input access"; color: root.theme.turboBright; font.pixelSize: 11; font.bold: true }
                            QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 10; color: root.theme.textMid
                                text: "Add your user to the 'input' group, then re-log:  sudo usermod -aG input $USER" }
                        }
                    }
                    GButton { theme: root.theme; kind: "tonal"; text: "Auto-arrange"; iconSource: "icons/layout-grid.svg"; Layout.fillWidth: true
                        onClicked: root.autoArrange() }
                }
            }

            // Canvas
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: "#0d0e11"
                border.width: 1
                border.color: root.theme.line
                clip: true

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: root.sheetW * root.zoom
                    contentHeight: root.sheetH * root.zoom
                    boundsBehavior: Flickable.StopAtBounds
                    onContentXChanged: miniMap.requestPaint()
                    onContentYChanged: miniMap.requestPaint()

                    Item {
                        id: sheet
                        width: root.sheetW
                        height: root.sheetH
                        transformOrigin: Item.TopLeft
                        scale: root.zoom

                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = Qt.rgba(root.theme.lineHi.r, root.theme.lineHi.g, root.theme.lineHi.b, 0.35)
                                for (var x = 20; x < width; x += 30)
                                    for (var y = 20; y < height; y += 30) { ctx.beginPath(); ctx.arc(x, y, 1, 0, 6.283); ctx.fill() }
                            }
                        }

                        Canvas {
                            id: linkLayer
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                ctx.lineWidth = 2.5
                                for (var i = 0; i < root.links.length; i++) {
                                    var a = root.livePos[root.links[i].from], b = root.livePos[root.links[i].to]
                                    if (!a || !b) continue
                                    var sp = root.portPoint(root.links[i].from, root.links[i].fromPort || "")
                                    var x1 = sp.x, y1 = sp.y
                                    var x2 = b.x, y2 = b.y + (b.h || 120) / 2
                                    var acc = root.portColor(root.links[i].fromPort || "")
                                             || root.nodeAccent(root.links[i].from)
                                    ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.65)
                                    var dx = Math.max(46, Math.abs(x2 - x1) * 0.5)
                                    ctx.beginPath(); ctx.moveTo(x1, y1)
                                    ctx.bezierCurveTo(x1 + dx, y1, x2 - dx, y2, x2, y2); ctx.stroke()
                                    ctx.fillStyle = ctx.strokeStyle
                                    ctx.beginPath(); ctx.arc(x2, y2, 4, 0, 6.283); ctx.fill()
                                    ctx.beginPath(); ctx.arc(x1, y1, 4, 0, 6.283); ctx.fill()
                                }
                                if (root.pendingFrom !== "") {
                                    var pa = root.livePos[root.pendingFrom]
                                    if (pa) {
                                        var psp = root.portPoint(root.pendingFrom, root.pendingPort)
                                        var px1 = psp.x, py1 = psp.y
                                        var pacc = root.portColor(root.pendingPort)
                                                  || root.nodeAccent(root.pendingFrom)
                                        ctx.strokeStyle = Qt.rgba(pacc.r, pacc.g, pacc.b, 0.95)
                                        ctx.setLineDash([6, 5])
                                        var pdx = Math.max(46, Math.abs(root.pendingX - px1) * 0.5)
                                        ctx.beginPath(); ctx.moveTo(px1, py1)
                                        ctx.bezierCurveTo(px1 + pdx, py1, root.pendingX - pdx, root.pendingY, root.pendingX, root.pendingY)
                                        ctx.stroke(); ctx.setLineDash([])
                                    }
                                }
                            }
                        }

                        Repeater {
                            id: nodeRepeater
                            model: root.nodes
                            delegate: CanvasNode {
                                theme: root.theme
                                node: modelData
                                selected: root.selectedId === modelData.id
                                runState: root.nodeRunState(modelData)
                                outPorts: root.portsFor(modelData.kind)
                                boundW: root.sheetW
                                boundH: root.sheetH
                                Component.onCompleted: { x = modelData.x; y = modelData.y; root.updatePos(modelData.id, x, y, width, height) }
                                onMoved: root.updatePos(modelData.id, x, y, width, height)
                                onMoveBegin: root.recordHistory()
                                onPicked: root.selectedId = modelData.id
                                onDeleteRequested: root.deleteNode(modelData.id)
                                onLinkBegin: function(sx, sy, port) { root.beginLink(modelData.id, sx, sy, port) }
                                onLinkMove: function(sx, sy) { root.moveLink(sx, sy) }
                                onLinkEnd: function(sx, sy) { root.endLink(sx, sy) }
                            }
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: [ "genesi/node" ]
                    onDropped: function(drop) {
                        if (!dragGhost.def) return
                        var cx = (flick.contentX + drop.x) / root.zoom - 107
                        var cy = (flick.contentY + drop.y) / root.zoom - 60
                        root.addNodeAt(Math.max(0, cx), Math.max(0, cy), dragGhost.def)
                    }
                }

                Rectangle {
                    // Hide the mini-map when the canvas itself is small — it
                    // would cover most of the visible sheet.
                    visible: parent.width > 470
                    x: 16; y: parent.height - height - 16
                    width: 180; height: 120; radius: 12
                    color: Qt.rgba(0.05, 0.055, 0.065, 0.92)
                    border.width: 1; border.color: root.theme.line
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 5
                        QQC2.Label { text: "Mini-map"; color: root.theme.textMid; font.pixelSize: 10; font.bold: true }
                        Canvas {
                            id: miniMap
                            Layout.fillWidth: true; Layout.fillHeight: true
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                var sx = width / root.sheetW, sy = height / root.sheetH
                                for (var i = 0; i < root.nodes.length; i++) {
                                    var p = root.livePos[root.nodes[i].id]; if (!p) continue
                                    var acc = root.nodes[i].accent
                                    ctx.fillStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.9)
                                    ctx.fillRect(p.x * sx, p.y * sy, Math.max(4, (p.w || 214) * sx), Math.max(3, (p.h || 120) * sy))
                                }
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.45)
                                ctx.lineWidth = 1
                                ctx.strokeRect(flick.contentX / root.zoom * sx, flick.contentY / root.zoom * sy,
                                               flick.width / root.zoom * sx, flick.height / root.zoom * sy)
                            }
                        }
                    }
                }

                ColumnLayout {
                    x: parent.width - 50; y: parent.height - 158
                    spacing: 7
                    Repeater {
                        model: [ { ic: "maximize", act: "fit" }, { ic: "plus", act: "in" }, { ic: "minus", act: "out" } ]
                        delegate: Rectangle {
                            Layout.preferredWidth: 34; Layout.preferredHeight: 34; radius: 9
                            color: zma.containsMouse ? root.theme.cardHi : root.theme.card
                            border.width: 1; border.color: root.theme.line
                            FIcon { anchors.centerIn: parent; name: modelData.ic; size: 15; color: root.theme.textMid }
                            MouseArea { id: zma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.zoomAction(modelData.act) }
                        }
                    }
                }

                // Run log overlay — streamed from genesi-automationd status.json.
                Rectangle {
                    id: logPanel
                    visible: root.showLog
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 10
                    height: 180
                    radius: 12
                    color: "#0b0c0f"
                    border.width: 1; border.color: root.theme.line
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: root.running ? root.theme.blue : root.theme.greenBright
                            }
                            QQC2.Label { text: "Run Log"; color: root.theme.textHi; font.pixelSize: 12; font.bold: true }
                            QQC2.Label { text: root.running ? "running…" : (runLog.count ? "idle" : "")
                                color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true }
                            Rectangle {
                                width: 22; height: 22; radius: 6; color: xLogMa.containsMouse ? root.theme.cardHi : "transparent"
                                FIcon { anchors.centerIn: parent; name: "x"; size: 11; color: root.theme.textLo }
                                MouseArea { id: xLogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showLog = false }
                            }
                        }
                        // Pending AI approvals ("ask" mode) — Approve / Deny.
                        Repeater {
                            model: root.pendingApprovals
                            delegate: Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 8
                                color: root.theme.a(root.theme.turbo, 0.10)
                                border.width: 1; border.color: root.theme.a(root.theme.turbo, 0.4)
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                    FIcon { name: "bot"; size: 15; color: root.theme.turboBright }
                                    ColumnLayout { Layout.fillWidth: true; spacing: -1
                                        QQC2.Label { text: "AI wants to run: " + modelData.tool; color: root.theme.textHi; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                        QQC2.Label { visible: modelData.reason; text: modelData.reason || ""; color: root.theme.textLo; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                                    }
                                    GButton { theme: root.theme; kind: "tonal"; text: "Approve"; iconSource: "icons/check.svg"
                                        onClicked: backend.resolveAutomationApproval(modelData.id, true) }
                                    GButton { theme: root.theme; kind: "danger"; text: "Deny"; iconSource: "icons/x.svg"
                                        onClicked: backend.resolveAutomationApproval(modelData.id, false) }
                                }
                            }
                        }
                        ListView {
                            id: logList
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            model: runLog
                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                            onCountChanged: positionViewAtEnd()
                            delegate: QQC2.Label {
                                width: logList.width
                                text: model.line
                                color: model.level === "cmd" ? root.theme.greenBright
                                     : model.level === "step" ? root.theme.blue
                                     : model.level === "ok" ? root.theme.greenBright
                                     : model.level === "err" ? root.theme.red : root.theme.textMid
                                font.family: root.theme.mono; font.pixelSize: 11
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }

            // Config panel
            FCard {
                theme: root.theme
                Layout.preferredWidth: root.compact ? 252 : 300
                Layout.fillHeight: true
                AutomationConfigPanel { anchors.fill: parent; theme: root.theme; node: root.selectedNode(); graphProvider: root; hotkeyAvailable: root.hotkeyAvailable }
            }
        }

        // ── Status bar ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle { width: 9; height: 9; radius: 5; color: root.running ? root.theme.blue : (root.activeEnabled ? root.theme.greenBright : root.theme.textLo) }
            QQC2.Label { text: "Status:"; color: root.theme.textMid; font.pixelSize: 13 }
            QQC2.Label { text: root.running ? "Running…" : (root.activeEnabled ? "Listening in background" : "Disabled")
                color: root.running ? root.theme.blue : (root.activeEnabled ? root.theme.greenBright : root.theme.textLo); font.pixelSize: 13; font.bold: true }
            Item { Layout.fillWidth: true }
            QQC2.TextField {
                id: nameField
                Layout.preferredWidth: root.tight ? 136 : 200; implicitHeight: 34
                text: root.activeName; placeholderText: "Automation name"
                color: root.theme.textHi; selectionColor: root.theme.green; selectedTextColor: root.theme.white
                background: Rectangle { radius: 7; color: root.theme.cardHi; border.width: 1; border.color: root.theme.line }
                onEditingFinished: {
                    root.activeName = text.trim() || "Automation"
                    root.persist(); root.refreshList()
                }
            }
            GButton { theme: root.theme; kind: "ghost"; text: root.showLog ? "Hide Log" : "Run Log"; iconSource: "icons/terminal.svg"
                onClicked: root.showLog = !root.showLog }
            GButton { theme: root.theme; kind: "tonal"; text: "Save"; iconSource: "icons/save.svg"
                onClicked: { root.persist(); root.toast("Automation saved.") } }
        }
    }

    // ── Template gallery ────────────────────────────────────────────────────
    property var templateList: [
        { id: "downloads", name: "Organize Downloads", sub: "New file in ~/Downloads → sort into folders by type", icon: "folder" },
        { id: "lowbatt",   name: "Low battery alert",  sub: "Battery below 20% → notify you", icon: "bolt" },
        { id: "idlelock",  name: "Auto-lock when idle", sub: "Idle 10 min → lock the screen", icon: "lock" },
        { id: "lowdisk",   name: "Low disk warning",   sub: "Root disk over 90% → notify you", icon: "database" },
        { id: "overheat",  name: "Overheat guard",     sub: "CPU over 85°C → notify you", icon: "alert" },
        { id: "cpuhog",    name: "CPU hog alert",      sub: "CPU over 90% → notify you", icon: "cpu" },
        { id: "usbbackup", name: "Backup on USB",      sub: "USB plugged in → run a backup script", icon: "archive" },
        { id: "morning",   name: "Morning routine",    sub: "08:00 → open your browser + a good-morning ping", icon: "clock" },
        { id: "aihotkey",  name: "AI on a hotkey",     sub: "Ctrl+Alt+G → ask the local AI for a quick status", icon: "bot" }
    ]


    // ── Describe it, and let the model build it ─────────────────────────────
    //
    // The honesty rules are the whole feature. A generator that quietly builds
    // something adjacent to what was asked is worse than one that refuses:
    // the user only finds out weeks later, when the automation does not fire.
    // So the panel has three states and never blurs them — it built what you
    // asked, it built PART of it and says which part is missing, or it could
    // not and says why.
    property string genStatus: ""       // "" | working | ok | partial | error
    property string genNote: ""
    property var genGraph: null
    property string genName: ""

    Connections {
        target: backend
        function onWorkflowGenerated(payload) {
            var res = {}
            try { res = JSON.parse(payload) } catch (e) { res = { status: "error",
                note: "The reply could not be read." } }
            root.genStatus = res.status || "error"
            root.genNote = res.note || ""
            root.genGraph = res.graph || null
            root.genName = res.name || ""
        }
        function onNoticeToast(msg) { root.toast(msg) }
        function onModelsLoaded(jsonStr) {
            try { root.genModels = JSON.parse(jsonStr) } catch (e) { root.genModels = [] }
        }
    }

    QQC2.Popup {
        id: genPopup
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(680, parent ? parent.width - 24 : 680)
        height: Math.min(560, parent ? parent.height - 24 : 560)
        modal: true; focus: true
        closePolicy: QQC2.Popup.CloseOnEscape
        background: Rectangle {
            radius: 14; color: root.theme.card
            border.width: 1
            // The border breathes while the model is thinking. It is the only
            // thing on screen that moves, so "it is working" needs no spinner.
            border.color: root.genStatus === "working" ? root.theme.violet
                                                       : root.theme.lineHi
            Behavior on border.color { ColorAnimation { duration: 400 } }
            SequentialAnimation on opacity {
                running: root.genStatus === "working"
                loops: Animation.Infinite
                NumberAnimation { to: 0.88; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
            }
        }
        onOpened: { root.genStatus = ""; root.genNote = ""; root.genGraph = null }

        contentItem: ColumnLayout {
            spacing: 12

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                FIcon { size: 20; name: "bot"; color: root.theme.violet }
                QQC2.Label { text: "Describe the automation"
                    color: root.theme.textHi; font.family: root.theme.display
                    font.pixelSize: 20; font.bold: true }
                Item { Layout.fillWidth: true }
                GButton { theme: root.theme; kind: "ghost"; text: "✕"
                    onClicked: genPopup.close() }
            }
            QQC2.Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: "In your own words — what should start it, and what should happen. It runs on your machine, on the model you picked."
                color: root.theme.textMid; font.pixelSize: 12 }

            Rectangle {
                Layout.fillWidth: true; implicitHeight: 96
                radius: 10; color: root.theme.cardHi
                border.width: 1
                border.color: genInput.activeFocus ? root.theme.violet : root.theme.line
                QQC2.TextArea {
                    id: genInput
                    anchors.fill: parent; anchors.margins: 10
                    background: null; color: root.theme.textHi
                    font.pixelSize: 13; wrapMode: TextEdit.Wrap
                    placeholderText: "every morning at 9, check if my disk is above 90% and warn me with the exact number"
                    placeholderTextColor: root.theme.textLo
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                QQC2.Label { text: "Model"; color: root.theme.textMid; font.pixelSize: 12 }
                QQC2.ComboBox {
                    id: genModel
                    Layout.fillWidth: true; implicitHeight: 36
                    model: root.genModels
                    background: Rectangle { radius: 9; color: root.theme.cardHi
                        border.width: 1; border.color: root.theme.lineHi }
                    contentItem: QQC2.Label {
                        leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter
                        text: genModel.displayText; color: root.theme.textHi
                        font.pixelSize: 12; elide: Text.ElideRight }
                }
                GButton {
                    theme: root.theme; kind: "filled"
                    text: root.genStatus === "working" ? "Designing…" : "Generate"
                    enabled: root.genStatus !== "working" && genInput.text.trim().length > 3
                    onClicked: {
                        root.genStatus = "working"; root.genNote = ""; root.genGraph = null
                        backend.generateWorkflow(genInput.text,
                                                 genModel.currentText || "")
                    }
                }
            }

            // What came back. Three states, never blurred together.
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                radius: 10; color: root.theme.bgTop
                border.width: 1
                border.color: root.genStatus === "error" ? root.theme.red
                            : root.genStatus === "partial" ? root.theme.turbo
                            : root.genStatus === "ok" ? root.theme.greenBright
                            : root.theme.line
                Behavior on border.color { ColorAnimation { duration: 250 } }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 8

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        visible: root.genStatus !== "" && root.genStatus !== "working"
                        FIcon { size: 14
                            name: root.genStatus === "error" ? "x"
                                : root.genStatus === "partial" ? "alert" : "check"
                            color: root.genStatus === "error" ? root.theme.red
                                 : root.genStatus === "partial" ? root.theme.turbo
                                 : root.theme.greenBright }
                        QQC2.Label {
                            color: root.theme.textHi; font.pixelSize: 13; font.bold: true
                            text: root.genStatus === "error" ? "It could not build this"
                                : root.genStatus === "partial" ? "Built, with something left out"
                                : ("Ready: " + root.genName) }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        visible: root.genNote.length > 0
                        text: root.genNote
                        color: root.theme.textMid; font.pixelSize: 12 }

                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        visible: root.genStatus === ""
                        text: "Nothing yet. Describe it above and press Generate."
                        color: root.theme.textLo; font.pixelSize: 12 }

                    // A plain-language reading of the graph, so the user checks
                    // the WORKFLOW rather than trusting a drawing they have not
                    // read yet.
                    QQC2.ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        visible: root.genGraph !== null
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: 4
                            Repeater {
                                model: root.genGraph ? root.genGraph.nodes : []
                                delegate: RowLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; spacing: 8
                                    QQC2.Label { text: (index + 1) + "."
                                        color: root.theme.textLo; font.pixelSize: 11 }
                                    FIcon { size: 13; name: modelData.icon || "box"
                                        color: root.accentFor(modelData.accentKey) }
                                    QQC2.Label { text: modelData.title || modelData.kind
                                        color: root.theme.textHi; font.pixelSize: 12 }
                                    QQC2.Label { text: modelData.kind
                                        color: root.theme.textLo; font.pixelSize: 10
                                        font.family: root.theme.mono }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GButton { theme: root.theme; kind: "ghost"; text: "Cancel"
                    onClicked: genPopup.close() }
                GButton {
                    theme: root.theme; kind: "tonal"; text: "Replace this workflow"
                    enabled: root.genGraph !== null
                    onClicked: {
                        root.recordHistory()
                        root.applyGraph({ nodes: root.genGraph.nodes,
                                          links: root.genGraph.links,
                                          name: root.genName || root.activeName,
                                          enabled: root.activeEnabled })
                        root.persist()
                        genPopup.close()
                        root.toast("Workflow built — check it, then enable it.")
                    }
                }
            }
        }
    }

    QQC2.Popup {
        id: templatePopup
        parent: QQC2.Overlay.overlay
        anchors.centerIn: parent
        // Fit small windows: this was a fixed 720×520 that overflowed whenever
        // the Monitor wasn't maximized.
        width: Math.min(720, parent ? parent.width - 24 : 720)
        height: Math.min(520, parent ? parent.height - 24 : 520)
        modal: true; focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        background: Rectangle { radius: 12; color: root.theme.card; border.width: 1; border.color: root.theme.lineHi }
        contentItem: ColumnLayout {
            spacing: 12
            QQC2.Label { text: "Start from a template"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 20; font.bold: true }
            QQC2.Label { text: "Ready-made automations — pick one, then tweak it. Remember to enable it."; color: root.theme.textMid; font.pixelSize: 12 }
            QQC2.ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
                GridLayout {
                    width: templatePopup.availableWidth
                    columns: templatePopup.width < 580 ? 2 : 3
                    columnSpacing: 10; rowSpacing: 10
                    Repeater {
                        model: root.templateList
                        delegate: Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 108; radius: 8
                            color: tcardMa.containsMouse ? root.theme.cardHi : root.theme.card
                            border.width: 1; border.color: tcardMa.containsMouse ? root.theme.a(root.theme.green, 0.6) : root.theme.line
                            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 5
                                RowLayout { spacing: 8
                                    FIcon { name: modelData.icon; size: 16; color: root.theme.greenBright }
                                    QQC2.Label { text: modelData.name; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                                }
                                QQC2.Label { text: modelData.sub; color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            }
                            MouseArea { id: tcardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.createFromTemplate(modelData) }
                        }
                    }
                }
            }
        }
    }

    // Floating drag ghost (shared by every PaletteItem).
    Item {
        id: dragGhost
        property var def: null
        property bool dragging: false
        visible: dragging
        z: 5000
        width: 190; height: 46
        Drag.active: dragging
        Drag.keys: [ "genesi/node" ]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Rectangle {
            anchors.fill: parent; radius: 11; opacity: 0.97
            color: root.theme.cardHi
            border.width: 1.5
            border.color: dragGhost.def ? root.theme.a(dragGhost.def.accent, 0.7) : root.theme.a(root.theme.green, 0.6)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 9
                Rectangle {
                    width: 26; height: 26; radius: 7
                    color: dragGhost.def ? root.theme.a(dragGhost.def.accent, 0.18) : "transparent"
                    FIcon { anchors.centerIn: parent; name: dragGhost.def ? dragGhost.def.icon : ""; size: 14
                        color: dragGhost.def ? dragGhost.def.accent : root.theme.green }
                }
                QQC2.Label { text: dragGhost.def ? dragGhost.def.label : ""; color: root.theme.textHi; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }
    }

    // ── Graph mutations ─────────────────────────────────────────────────────
    function addNode(def) { addNodeAt(flick.contentX / zoom + 120, flick.contentY / zoom + 160, def) }

    function _syncPositions(arr) {
        for (var i = 0; i < arr.length; i++) {
            var p = livePos[arr[i].id]
            if (p) { arr[i].x = p.x; arr[i].y = p.y }
        }
        return arr
    }

    function defaultConfig(kind) {
        if (kind === "evt_fs") return { path: "~/Downloads", pattern: "*", change: "created", recursive: false, mode: "always" }
        if (kind === "evt_resource") return { metric: "cpu", op: ">", threshold: "80", mode: "always" }
        if (kind === "evt_temperature") return { sensor: "", threshold: "80", mode: "always" }
        if (kind === "evt_app") return { app: "", transition: "opened", mode: "always" }
        if (kind === "evt_process") return { app: "", metric: "mem", threshold: "1000", mode: "always" }
        if (kind === "evt_power") return { event: "on_battery", level: "20", mode: "always" }
        if (kind === "evt_disk") return { event: "usage_above", path: "/", threshold: "90", mode: "always" }
        if (kind === "evt_usb") return { action: "added", mode: "always" }
        if (kind === "evt_network") return { event: "online", iface: "", mode: "always" }
        if (kind === "evt_bluetooth") return { action: "connected", name: "", mode: "always" }
        if (kind === "evt_idle") return { event: "idle", minutes: "5", mode: "always" }
        if (kind === "evt_hotkey") return { combo: "", mode: "always" }
        if (kind === "evt_schedule") return { interval: "60", time: "", mode: "always" }
        if (kind === "evt_startup") return { mode: "always" }
        if (kind === "evt_log") return { path: "", pattern: "", mode: "always" }
        if (kind === "evt_command") return { command: "", on: "exit0", match: "", interval: "30", mode: "always" }
        if (kind === "evt_manual") return { mode: "always" }
        if (kind === "act_script") return { command: "", terminal: false }
        if (kind === "act_ai") return { model: "", aiMode: false, turbo: false, spec: false, exec: "advisory", prompt: "" }
        if (kind === "act_notify") return { title: "Genesi", body: "" }
        if (kind === "act_http") return { url: "", method: "GET", body: "" }
        if (kind === "act_file") return { op: "copy", src: "", dest: "" }
        if (kind === "act_app") return { op: "launch", app: "" }
        if (kind === "act_sound") return { sound: "" }
        if (kind === "act_wait") return { seconds: "5" }
        if (kind === "act_power") return { op: "lock" }
        return ({})
    }

    // ── templates ───────────────────────────────────────────────────────────
    function tnode(id, kind, title, icon, accentKey, x, y, config) {
        return { id: id, kind: kind, title: title, icon: icon, accentKey: accentKey, x: x, y: y, config: config }
    }

    function buildTemplate(tid) {
        var E = 80, A = 380, B = 680, Y = 200
        if (tid === "downloads") return {
            nodes: [ tnode("t-e", "evt_fs", "New download", "folder", "turbo", E, Y, { path: "~/Downloads", pattern: "*", change: "created", recursive: false, mode: "always" }),
                     tnode("t-a", "act_script", "Sort by type", "terminal", "purple", A, Y, { command: 'cd ~/Downloads && for f in *.*; do [ -f "$f" ] || continue; ext="${f##*.}"; mkdir -p "$ext" && mv -n "$f" "$ext"/; done' }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "lowbatt") return {
            nodes: [ tnode("t-e", "evt_power", "Battery low", "bolt", "turbo", E, Y, { event: "battery_below", level: "20", mode: "always" }),
                     tnode("t-a", "act_notify", "Notify", "alert", "green", A, Y, { title: "Battery low", body: "Plug in your charger — battery is under 20%." }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "idlelock") return {
            nodes: [ tnode("t-e", "evt_idle", "When idle", "user", "green", E, Y, { event: "idle", minutes: "10", mode: "always" }),
                     tnode("t-a", "act_power", "Lock screen", "lock", "red", A, Y, { op: "lock" }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "lowdisk") return {
            nodes: [ tnode("t-e", "evt_disk", "Disk almost full", "database", "blue", E, Y, { event: "usage_above", path: "/", threshold: "90", mode: "always" }),
                     tnode("t-a", "act_notify", "Notify", "alert", "green", A, Y, { title: "Disk almost full", body: "Your root disk is over 90% used." }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "overheat") return {
            nodes: [ tnode("t-e", "evt_temperature", "CPU too hot", "alert", "red", E, Y, { sensor: "", threshold: "85", mode: "always" }),
                     tnode("t-a", "act_notify", "Notify", "alert", "green", A, Y, { title: "CPU is hot", body: "CPU crossed 85°C — check your cooling." }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "cpuhog") return {
            nodes: [ tnode("t-e", "evt_resource", "High CPU", "cpu", "blue", E, Y, { metric: "cpu", op: ">", threshold: "90", mode: "always" }),
                     tnode("t-a", "act_notify", "Notify", "alert", "green", A, Y, { title: "High CPU", body: "CPU usage is over 90%." }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "usbbackup") return {
            nodes: [ tnode("t-e", "evt_usb", "USB plugged in", "archive", "green", E, Y, { action: "added", mode: "always" }),
                     tnode("t-a", "act_script", "Run backup", "terminal", "purple", A, Y, { command: 'echo "USB detected — edit this to rsync your files to the drive"' }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        if (tid === "morning") return {
            nodes: [ tnode("t-e", "evt_schedule", "At 08:00", "clock", "blue", E, Y, { interval: "60", time: "08:00", mode: "always" }),
                     tnode("t-a", "act_app", "Open browser", "external-link", "purple", A, Y, { op: "launch", app: "xdg-open https://news.google.com" }),
                     tnode("t-b", "act_notify", "Good morning", "alert", "green", B, Y, { title: "Good morning", body: "Have a great day!" }) ],
            links: [ { from: "t-e", to: "t-a" }, { from: "t-a", to: "t-b" } ] }
        if (tid === "aihotkey") return {
            nodes: [ tnode("t-e", "evt_hotkey", "Ctrl+Alt+G", "terminal", "green", E, Y, { combo: "ctrl+alt+g", mode: "always" }),
                     tnode("t-a", "act_ai", "Ask the AI", "bot", "turbo", A, Y, { model: "", aiMode: false, turbo: false, spec: false, exec: "advisory", autonomous: false, prompt: "Give me a short system status: CPU, RAM and disk usage." }) ],
            links: [ { from: "t-e", to: "t-a" } ] }
        return { nodes: [], links: [] }
    }

    function createFromTemplate(t) {
        var id = backend.createAutomation(t.name)
        refreshList()
        switchTo(id)
        var g = buildTemplate(t.id)
        applyGraph({ id: id, name: t.name, enabled: false, nodes: g.nodes, links: g.links })
        persist()
        templatePopup.close()
        toast("Created from template: " + t.name + " — enable it when ready.")
    }

    function addNodeAt(nx, ny, def) {
        recordHistory()
        var id = def.kind + "-" + Date.now()
        var cfg = defaultConfig(def.kind)
        var n = { id: id, kind: def.kind, title: def.label, icon: def.icon, accent: def.accent,
                  accentKey: def.accentKey || "green", x: nx, y: ny,
                  config: cfg, status: "", statusKind: "ok" }
        n.lines = summaryLines(n)
        var arr = _syncPositions(nodes.slice())
        arr.push(n); nodes = arr
        selectedId = id
        Qt.callLater(function() { updatePos(id, nx, ny, 214, 120) })
        scheduleSave()
        toast(def.label + " added.")
    }

    function deleteNode(id) {
        recordHistory()
        var arr = _syncPositions(nodes.slice()).filter(function(n) { return n.id !== id })
        links = links.filter(function(l) { return l.from !== id && l.to !== id })
        delete livePos[id]
        nodes = arr
        if (selectedId === id) selectedId = arr.length ? arr[arr.length - 1].id : ""
        Qt.callLater(function() { linkLayer.requestPaint(); miniMap.requestPaint() })
        scheduleSave()
        toast("Block removed.")
    }

    function renameNode(id, title) {
        var current = null
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) current = nodes[i]
        if (!current || current.title === title) return
        recordHistory()
        _replaceNode(id, { title: title })
        scheduleSave()
        Qt.callLater(function() { linkLayer.requestPaint() })
    }

    // Replace nodes[i] with a COPY carrying `patch`. slice() is a shallow copy,
    // so mutating the element in place kept the SAME object reference — QML then
    // saw no identity change on `node` and never re-evaluated the config panel's
    // bindings, which is why conditional fields (the regex input on the Command
    // sensor's "match" mode) only appeared after reselecting the block
    // (reported 2026-07-19). A fresh object forces the re-evaluation.
    function _replaceNode(id, patch) {
        var arr = _syncPositions(nodes.slice())
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id !== id) continue
            var copy = ({})
            for (var k in arr[i]) copy[k] = arr[i][k]
            for (var p in patch) copy[p] = patch[p]
            copy.lines = summaryLines(copy)
            arr[i] = copy
            break
        }
        nodes = arr
    }

    function setNodeConfig(id, key, value) {
        var current = null
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) current = nodes[i]
        if (!current) return
        var old = current.config || ({})
        if (old[key] === value) return
        recordHistory()
        var cfg = ({})
        for (var k in old) cfg[k] = old[k]
        cfg[key] = value
        _replaceNode(id, { config: cfg })
        scheduleSave()
        Qt.callLater(function() { linkLayer.requestPaint() })
    }

    function autoArrange() {
        recordHistory()
        var arr = nodes.slice()
        var cols = 4, gapX = 270, gapY = 230, x0 = 60, y0 = 110
        for (var i = 0; i < arr.length; i++) {
            arr[i].x = x0 + (i % cols) * gapX
            arr[i].y = y0 + Math.floor(i / cols) * gapY
        }
        nodes = arr
        Qt.callLater(function() {
            for (var j = 0; j < nodeRepeater.count; j++) {
                var it = nodeRepeater.itemAt(j)
                if (it) { it.x = arr[j].x; it.y = arr[j].y; updatePos(arr[j].id, it.x, it.y, it.width, it.height) }
            }
        })
        scheduleSave()
    }

    // ── Linking ─────────────────────────────────────────────────────────────
    function beginLink(id, sx, sy, port) { pendingFrom = id; pendingPort = port || ""; pendingX = sx; pendingY = sy; linkLayer.requestPaint() }
    function moveLink(sx, sy) { pendingX = sx; pendingY = sy; linkLayer.requestPaint() }
    function endLink(sx, sy) {
        var target = ""
        for (var id in livePos) {
            var p = livePos[id]
            if (sx >= p.x - 14 && sx <= p.x + (p.w || 214) + 14 &&
                sy >= p.y - 10 && sy <= p.y + (p.h || 120) + 10) { target = id; break }
        }
        if (target && target !== pendingFrom) addLink(pendingFrom, target, pendingPort)
        pendingFrom = ""; pendingPort = ""
        linkLayer.requestPaint()
    }
    function addLink(fromId, toId, port) {
        port = port || ""
        for (var i = 0; i < links.length; i++)
            if (links[i].from === fromId && links[i].to === toId
                && (links[i].fromPort || "") === port) return
        recordHistory()
        var o = { from: fromId, to: toId }
        if (port) o.fromPort = port
        var lk = links.slice(); lk.push(o); links = lk
        linkLayer.requestPaint()
        scheduleSave()
        toast(port ? "Blocks connected (" + portLabel(port) + ")." : "Blocks connected.")
    }
    function connectionsFor(id) {
        var result = []
        for (var i = 0; i < links.length; i++) {
            var link = links[i]
            var p = link.fromPort || ""
            var suffix = p ? "  ·  " + portLabel(p) : ""
            if (link.from === id)
                result.push({ from: link.from, to: link.to, port: p,
                              label: "To " + nodeTitle(link.to) + suffix })
            else if (link.to === id)
                result.push({ from: link.from, to: link.to, port: p,
                              label: "From " + nodeTitle(link.from) + suffix })
        }
        return result
    }
    function removeLink(fromId, toId, port) {
        for (var i = 0; i < links.length; i++) {
            if (links[i].from === fromId && links[i].to === toId
                && (port === undefined || (links[i].fromPort || "") === (port || ""))) {
                recordHistory()
                var next = links.slice(); next.splice(i, 1); links = next
                linkLayer.requestPaint(); scheduleSave(); toast("Connection removed.")
                return
            }
        }
    }

    function zoomAction(act) {
        if (act === "in") zoom = Math.min(1.6, zoom + 0.1)
        else if (act === "out") zoom = Math.max(0.4, zoom - 0.1)
        else if (act === "fit") zoom = 1.0
        miniMap.requestPaint()
    }

    // ── Live status/log from the daemon ──────────────────────────────────────
    property bool showLog: false
    property bool running: false
    property var pendingApprovals: []
    ListModel { id: runLog }

    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.pollStatus()
    }

    function pollStatus() {
        var st
        try { st = JSON.parse(backend.automationStatus()) } catch (e) { return }
        root.hotkeyAvailable = st.hotkeyAvailable || false
        var autos = st.automations || ({})
        var mine = autos[root.activeId]
        if (!mine) { root.running = false; root.pendingApprovals = []; return }
        root.running = mine.running || false
        root.nodeStates = mine.nodes || ({})
        root.pendingApprovals = mine.pending || []
        if (root.pendingApprovals.length > 0) root.showLog = true
        var log = mine.log || []
        if (runLog.count !== log.length) {
            runLog.clear()
            for (var i = 0; i < log.length; i++)
                runLog.append({ line: log[i].line, level: log[i].level || "out" })
        }
    }
}
