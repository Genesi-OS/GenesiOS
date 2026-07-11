/*
 * Genesi Forge — the Forge Canvas page (hosted inside ProjectView). A slim
 * header (Run/Generate), the node palette, the canvas itself and the config
 * panel, plus the workflow status bar.
 *
 * The canvas is a large fixed SHEET (2400×1500) inside a Flickable: panning is
 * native, zoom scales the sheet, and the link layer is sheet-sized — so links
 * are never clipped no matter how far a node is dragged. All node/link
 * coordinates live in sheet space (nodes are children of the sheet, so
 * mapToItem(parent) in CanvasNode already yields sheet coords).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property var project
    signal toast(string msg)

    readonly property real sheetW: 2400
    readonly property real sheetH: 1500

    property var nodes: []
    property var links: []
    property var livePos: ({})
    property string selectedId: "github"
    property real zoom: 1.0
    property var runState: ({})
    property bool running: false
    property string pendingFrom: ""
    property real pendingX: 0
    property real pendingY: 0

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
            out.push({ id: n.id, kind: n.kind, title: n.title, x: p.x, y: p.y })
        }
        return JSON.stringify({ nodes: out, links: links })
    }

    // ── Default graph (mock layout, bundled icon names) ─────────────────────
    Component.onCompleted: {
        var g = theme.green, pu = theme.purple, bl = theme.blue, tu = theme.turbo
        nodes = [
            { id: "start",     kind: "start",     title: "Start",                 icon: "play",       accent: g,  x: 60,  y: 220, lines: ["New Project"], status: "", statusKind: "ok" },
            { id: "github",    kind: "github",    title: "GitHub Sync",           icon: "github",     accent: pu, x: 320, y: 150, lines: ["Create repo", "Initial commit", "Setup CI/CD"], status: "Configured", statusKind: "ok" },
            { id: "gitignore", kind: "gitignore", title: "Smart .gitignore",      icon: "edit",       accent: g,  x: 600, y: 150, lines: ["Detect: Node.js", "Generate rules", "Add .env protection"], status: "Auto-generated", statusKind: "auto" },
            { id: "env",       kind: "env",       title: "Environment Variables", icon: "lock",       accent: tu, x: 880, y: 150, lines: ["Create .env.example", "Create .env", "Add to .gitignore"], status: "Configured", statusKind: "ok" },
            { id: "install",   kind: "install",   title: "Install Dependencies",  icon: "download",   accent: bl, x: 320, y: 400, lines: ["npm install", "Install all packages"], status: "Configured", statusKind: "ok" },
            { id: "docker",    kind: "docker",    title: "Docker",                icon: "box",        accent: bl, x: 600, y: 400, lines: ["Generate Dockerfile", "Best practices"], status: "Configured", statusKind: "ok" },
            { id: "database",  kind: "database",  title: "Database",              icon: "database",   accent: g,  x: 880, y: 400, lines: ["PostgreSQL", "Generate schema", "Setup volumes"], status: "Configured", statusKind: "ok" },
            { id: "script",    kind: "script",    title: "Run Script",            icon: "terminal",   accent: pu, x: 460, y: 640, lines: ["Run tests", "Lint code", "Build project"], status: "Configured", statusKind: "ok" },
            { id: "readme",    kind: "readme",    title: "Generate README",       icon: "book-open",  accent: bl, x: 730, y: 640, lines: ["Project docs", "Setup guide", "Usage instructions"], status: "Configured", statusKind: "ok" },
            { id: "complete",  kind: "complete",  title: "Complete",              icon: "check",      accent: g,  x: 1000, y: 640, lines: ["Your project is", "ready to ship!"], status: "Success", statusKind: "success" }
        ]
        links = [
            { from: "start", to: "github" }, { from: "github", to: "gitignore" }, { from: "gitignore", to: "env" },
            { from: "github", to: "install" }, { from: "install", to: "docker" }, { from: "docker", to: "database" },
            { from: "install", to: "script" }, { from: "database", to: "script" },
            { from: "script", to: "readme" }, { from: "readme", to: "complete" }
        ]
        nodesChanged()
    }

    function updatePos(id, x, y, w, h) {
        livePos[id] = { x: x, y: y, w: w, h: h }
        linkLayer.requestPaint()
        miniMap.requestPaint()
    }

    function nodeAccent(id) {
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i].accent
        return theme.green
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
                QQC2.Label { text: "Forge Canvas"; color: root.theme.textHi
                    font.family: root.theme.display; font.pixelSize: 18; font.bold: true }
                QQC2.Label { text: "Automate your project setup and delivery"; color: root.theme.textLo; font.pixelSize: 11 }
            }
            Item { Layout.fillWidth: true }
            GButton { theme: root.theme; kind: root.running ? "danger" : "tonal"
                text: root.running ? "Stop" : "Run Workflow"
                iconSource: root.running ? "icons/square.svg" : "icons/play.svg"
                onClicked: root.runWorkflow() }
            GButton { theme: root.theme; kind: "filled"; text: "Generate"; iconSource: "icons/zap.svg"
                onClicked: backend.generateWorkflow(root.project.path, root.graphJson()) }
        }

        // ── Body: palette | canvas | config ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Palette
            FCard {
                theme: root.theme
                Layout.preferredWidth: 232
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 9
                    QQC2.Label { text: "Nodes"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                    QQC2.Label { text: "Drag and drop to build your workflow"; color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap }

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
                                    { section: "ESSENTIAL" },
                                    { label: "GitHub Sync",           icon: "github",   accent: root.theme.purple, kind: "github" },
                                    { label: "Smart .gitignore",      icon: "edit",     accent: root.theme.green,  kind: "gitignore" },
                                    { label: "Environment Variables", icon: "lock",     accent: root.theme.turbo,  kind: "env" },
                                    { label: "Install Dependencies",  icon: "download", accent: root.theme.blue,   kind: "install" },
                                    { label: "Run Script",            icon: "terminal", accent: root.theme.purple, kind: "script" },
                                    { section: "INFRASTRUCTURE" },
                                    { label: "Docker",      icon: "box",      accent: root.theme.blue,   kind: "docker" },
                                    { label: "Database",    icon: "database", accent: root.theme.green,  kind: "database" },
                                    { label: "API Service", icon: "globe",    accent: root.theme.purple, kind: "api" },
                                    { label: "Redis",       icon: "database", accent: root.theme.red,    kind: "redis" },
                                    { label: "Web Hook",    icon: "link",     accent: root.theme.green,  kind: "webhook" },
                                    { section: "DOCUMENTATION" },
                                    { label: "Generate README",    icon: "book-open", accent: root.theme.blue,  kind: "readme" },
                                    { label: "License",            icon: "shield",    accent: root.theme.turbo, kind: "license" },
                                    { label: "Contributing Guide", icon: "users",     accent: root.theme.green, kind: "contributing" }
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

                        // Dotted grid (painted once, sheet-sized).
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = Qt.rgba(root.theme.lineHi.r, root.theme.lineHi.g, root.theme.lineHi.b, 0.35)
                                for (var x = 20; x < width; x += 30)
                                    for (var y = 20; y < height; y += 30) { ctx.beginPath(); ctx.arc(x, y, 1, 0, 6.283); ctx.fill() }
                            }
                        }

                        // Links — sheet-sized, so curves are never clipped.
                        Canvas {
                            id: linkLayer
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                ctx.lineWidth = 2.5
                                for (var i = 0; i < root.links.length; i++) {
                                    var a = root.livePos[root.links[i].from], b = root.livePos[root.links[i].to]
                                    if (!a || !b) continue
                                    var x1 = a.x + (a.w || 214), y1 = a.y + (a.h || 120) / 2
                                    var x2 = b.x, y2 = b.y + (b.h || 120) / 2
                                    var acc = root.nodeAccent(root.links[i].from)
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
                                        var px1 = pa.x + (pa.w || 214), py1 = pa.y + (pa.h || 120) / 2
                                        var pacc = root.nodeAccent(root.pendingFrom)
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

                        // Section chip
                        Rectangle {
                            x: 28; y: 22
                            width: titleRow.implicitWidth + 30; height: 52
                            radius: 12
                            color: root.theme.a(root.theme.green, 0.08)
                            border.width: 1; border.color: root.theme.a(root.theme.green, 0.3)
                            RowLayout {
                                id: titleRow
                                anchors.centerIn: parent; spacing: 10
                                FIcon { name: "play"; size: 16; color: root.theme.greenBright }
                                ColumnLayout {
                                    spacing: 0
                                    QQC2.Label { text: "Setup Inicial e Boilerplate"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 13; font.bold: true }
                                    QQC2.Label { text: "Automate your project setup from scratch"; color: root.theme.textMid; font.pixelSize: 10 }
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
                                runState: root.runState[modelData.id] || ""
                                boundW: root.sheetW
                                boundH: root.sheetH
                                Component.onCompleted: { x = modelData.x; y = modelData.y; root.updatePos(modelData.id, x, y, width, height) }
                                onMoved: root.updatePos(modelData.id, x, y, width, height)
                                onPicked: root.selectedId = modelData.id
                                onDeleteRequested: root.deleteNode(modelData.id)
                                onLinkBegin: function(sx, sy) { root.beginLink(modelData.id, sx, sy) }
                                onLinkMove: function(sx, sy) { root.moveLink(sx, sy) }
                                onLinkEnd: function(sx, sy) { root.endLink(sx, sy) }
                            }
                        }
                    }
                }

                // Palette drop target — maps viewport coords into sheet space.
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

                // Mini-map (with viewport rectangle).
                Rectangle {
                    x: 16; y: parent.height - height - 16
                    width: 180; height: 120; radius: 12
                    color: Qt.rgba(0.05, 0.055, 0.065, 0.92)
                    border.width: 1; border.color: root.theme.line
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 5
                        QQC2.Label { text: "Canvas Mini-map"; color: root.theme.textMid; font.pixelSize: 10; font.bold: true }
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
                                // viewport
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.45)
                                ctx.lineWidth = 1
                                ctx.strokeRect(flick.contentX / root.zoom * sx, flick.contentY / root.zoom * sy,
                                               flick.width / root.zoom * sx, flick.height / root.zoom * sy)
                            }
                        }
                    }
                }

                // Zoom controls
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
            }

            // Config panel
            FCard {
                theme: root.theme
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                ConfigPanel { anchors.fill: parent; theme: root.theme; project: root.project; node: root.selectedNode(); graphProvider: root }
            }
        }

        // ── Status bar ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle { width: 9; height: 9; radius: 5; color: root.running ? root.theme.blue : root.theme.greenBright }
            QQC2.Label { text: "Workflow Status:"; color: root.theme.textMid; font.pixelSize: 13 }
            QQC2.Label { text: root.running ? "Running…" : "Ready"
                color: root.running ? root.theme.blue : root.theme.greenBright; font.pixelSize: 13; font.bold: true }
            Item { Layout.fillWidth: true }
            GButton { theme: root.theme; kind: "tonal"; text: "Save Workflow"; iconSource: "icons/save.svg"
                onClicked: backend.saveWorkflow(root.project.path, root.graphJson()) }
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

    function addNodeAt(nx, ny, def) {
        var id = def.kind + "-" + Date.now()
        var n = { id: id, kind: def.kind, title: def.label, icon: def.icon, accent: def.accent,
                  x: nx, y: ny, lines: ["New step"], status: "Draft", statusKind: "ok" }
        var arr = _syncPositions(nodes.slice())
        arr.push(n); nodes = arr
        selectedId = id
        Qt.callLater(function() { updatePos(id, nx, ny, 214, 120) })
        toast(def.label + " node added.")
    }

    function deleteNode(id) {
        var arr = _syncPositions(nodes.slice()).filter(function(n) { return n.id !== id })
        links = links.filter(function(l) { return l.from !== id && l.to !== id })
        delete livePos[id]
        nodes = arr
        if (selectedId === id) selectedId = arr.length ? arr[arr.length - 1].id : ""
        Qt.callLater(function() { linkLayer.requestPaint(); miniMap.requestPaint() })
        toast("Node removed.")
    }

    function renameNode(id, title) {
        var arr = _syncPositions(nodes.slice())
        for (var i = 0; i < arr.length; i++) if (arr[i].id === id) arr[i].title = title
        nodes = arr
        Qt.callLater(function() { linkLayer.requestPaint() })
    }

    function setNodeLines(id, lines) {
        var arr = _syncPositions(nodes.slice())
        for (var i = 0; i < arr.length; i++) if (arr[i].id === id) arr[i].lines = lines
        nodes = arr
        Qt.callLater(function() { linkLayer.requestPaint() })
    }

    function autoArrange() {
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
    }

    // ── Linking (drag from a node's output port; coords are sheet-space) ────
    function beginLink(id, sx, sy) {
        pendingFrom = id
        pendingX = sx; pendingY = sy
        linkLayer.requestPaint()
    }
    function moveLink(sx, sy) {
        pendingX = sx; pendingY = sy
        linkLayer.requestPaint()
    }
    function endLink(sx, sy) {
        var target = ""
        for (var id in livePos) {
            var p = livePos[id]
            if (sx >= p.x - 14 && sx <= p.x + (p.w || 214) + 14 &&
                sy >= p.y - 10 && sy <= p.y + (p.h || 120) + 10) { target = id; break }
        }
        if (target && target !== pendingFrom) addLink(pendingFrom, target)
        pendingFrom = ""
        linkLayer.requestPaint()
    }
    function addLink(fromId, toId) {
        for (var i = 0; i < links.length; i++)
            if (links[i].from === fromId && links[i].to === toId) return
        var lk = links.slice(); lk.push({ from: fromId, to: toId }); links = lk
        linkLayer.requestPaint()
        toast("Nodes connected.")
    }

    // ── Local run wiring ────────────────────────────────────────────────────
    function runWorkflow() {
        if (running) { backend.stopWorkflow(); return }
        runState = ({})
        running = true
        backend.runWorkflow(project.path, graphJson())
    }

    function zoomAction(act) {
        if (act === "in") zoom = Math.min(1.6, zoom + 0.1)
        else if (act === "out") zoom = Math.max(0.4, zoom - 0.1)
        else if (act === "fit") zoom = 1.0
        miniMap.requestPaint()
    }

    Connections {
        target: backend
        function onWorkflowStep(raw) {
            try {
                var s = JSON.parse(raw)
                var m = {}
                for (var k in root.runState) m[k] = root.runState[k]
                m[s.id] = s.state
                root.runState = m
            } catch (e) {}
        }
        function onWorkflowDone(ok) { root.running = false }
    }
}
