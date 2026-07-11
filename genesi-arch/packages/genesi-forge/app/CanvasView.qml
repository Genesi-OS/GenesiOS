/*
 * Genesi Forge — the project workspace with the Forge Canvas. A top bar with a
 * breadcrumb + Overview/Files/Forge Canvas tabs and the Run/Generate actions; a
 * draggable node-graph editor (palette · canvas + links + mini-map · config
 * panel); and a workflow status bar. The graph compiles to a real GitHub
 * Actions workflow via the backend.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property var project
    signal back()

    property string tab: "canvas"
    property var nodes: []
    property var links: []
    property var livePos: ({})
    property string selectedId: "github"
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    property var runState: ({})     // node id → "running"/"done"/"failed"
    property bool running: false
    property string pendingFrom: "" // node id while dragging a new link
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

    // ── Default graph (mirrors the Forge Canvas mockup) ─────────────────────
    Component.onCompleted: {
        var g = theme.green, gb = theme.greenBright, pu = theme.purple, bl = theme.blue, tu = theme.turbo, rd = theme.red
        nodes = [
            { id: "start",    kind: "start",    title: "Start",                 icon: "media-playback-start", accent: g,  x: 40,  y: 210, lines: ["New Project"], status: "", statusKind: "ok" },
            { id: "github",   kind: "github",   title: "GitHub Sync",           icon: "github",               accent: pu, x: 270, y: 150, lines: ["Create repo", "Initial commit", "Setup CI/CD"], status: "Configured", statusKind: "ok" },
            { id: "gitignore",kind: "gitignore",title: "Smart .gitignore",      icon: "document-edit",        accent: g,  x: 530, y: 150, lines: ["Detect: Node.js", "Generate rules", "Add .env protection"], status: "Auto-generated", statusKind: "auto" },
            { id: "env",      kind: "env",      title: "Environment Variables", icon: "lock",                 accent: tu, x: 790, y: 150, lines: ["Create .env.example", "Create .env", "Add to .gitignore"], status: "Configured", statusKind: "ok" },
            { id: "install",  kind: "install",  title: "Install Dependencies",  icon: "download",             accent: bl, x: 270, y: 372, lines: ["npm install", "Install all packages"], status: "Configured", statusKind: "ok" },
            { id: "docker",   kind: "docker",   title: "Docker",                icon: "docker",               accent: bl, x: 530, y: 372, lines: ["Generate Dockerfile", "Best practices"], status: "Configured", statusKind: "ok" },
            { id: "database", kind: "database", title: "Database",              icon: "server-database",      accent: g,  x: 780, y: 372, lines: ["PostgreSQL", "Generate schema", "Setup volumes"], status: "Configured", statusKind: "ok" },
            { id: "script",   kind: "script",   title: "Run Script",            icon: "utilities-terminal",   accent: pu, x: 400, y: 560, lines: ["Run tests", "Lint code", "Build project"], status: "Configured", statusKind: "ok" },
            { id: "readme",   kind: "readme",   title: "Generate README",       icon: "document-edit",        accent: bl, x: 650, y: 560, lines: ["Project docs", "Setup guide", "Usage instructions"], status: "Configured", statusKind: "ok" },
            { id: "complete", kind: "complete", title: "Complete",              icon: "checkmark",            accent: g,  x: 900, y: 560, lines: ["Your project is", "ready to ship!"], status: "Success", statusKind: "success" }
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top bar ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 60
            color: root.theme.bgTop
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 12

                Rectangle {
                    width: 34; height: 34; radius: 9
                    color: root.theme.a(root.theme.green, 0.14)
                    Kirigami.Icon { anchors.centerIn: parent; source: "genesi-forge"; width: 20; height: 20; color: root.theme.greenBright }
                }
                QQC2.Label { text: "Genesi Forge"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
                QQC2.Label { text: "/"; color: root.theme.textLo; font.pixelSize: 15 }
                QQC2.Label {
                    text: "Projects"; color: root.theme.textMid; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.back() }
                }
                QQC2.Label { text: "/"; color: root.theme.textLo; font.pixelSize: 15 }
                QQC2.Label { text: root.project ? root.project.name : ""; color: root.theme.textHi; font.pixelSize: 14; font.bold: true }

                Item { Layout.fillWidth: true }

                // Tabs
                Rectangle {
                    Layout.preferredHeight: 40; Layout.preferredWidth: tabRow.implicitWidth + 12
                    radius: 10; color: root.theme.card; border.width: 1; border.color: root.theme.line
                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent; spacing: 4
                        Repeater {
                            model: [ { key: "overview", label: "Overview", icon: "dashboard-show" },
                                     { key: "files", label: "Files", icon: "folder-symbolic" },
                                     { key: "canvas", label: "Forge Canvas", icon: "showgraph" } ]
                            delegate: Rectangle {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: tl.implicitWidth + (modelData.key === "canvas" ? 34 : 26)
                                radius: 8
                                color: root.tab === modelData.key ? root.theme.mix(root.theme.card, root.theme.green, 0.18) : "transparent"
                                border.width: 1; border.color: root.tab === modelData.key ? root.theme.a(root.theme.green, 0.4) : "transparent"
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 6
                                    Kirigami.Icon { visible: modelData.key === "canvas"; source: "color-gradient"; width: 14; height: 14; color: root.theme.greenBright }
                                    QQC2.Label { id: tl; text: modelData.label
                                        color: root.tab === modelData.key ? root.theme.textHi : root.theme.textMid
                                        font.pixelSize: 13; font.bold: root.tab === modelData.key }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = modelData.key }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                GButton { theme: root.theme; kind: root.running ? "danger" : "tonal"
                    text: root.running ? "Stop" : "Run Workflow"
                    iconSource: root.running ? "media-playback-stop" : "media-playback-start"
                    onClicked: root.runWorkflow() }
                GButton { theme: root.theme; kind: "filled"; text: "Generate"; iconSource: "color-gradient"
                    onClicked: backend.generateWorkflow(root.project.path, root.graphJson()) }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.line }

        // ── Body ────────────────────────────────────────────────────────
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.tab === "canvas" ? 2 : (root.tab === "files" ? 1 : 0)

            // Overview
            OverviewTab { theme: root.theme; project: root.project }

            // Files
            Item {
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 8
                    Kirigami.Icon { Layout.alignment: Qt.AlignHCenter; source: "folder-symbolic"; width: 44; height: 44; color: root.theme.textLo }
                    QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: "File browser"; color: root.theme.textMid; font.bold: true; font.pixelSize: 15 }
                    QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: root.project ? root.project.shortPath : ""; color: root.theme.textLo; font.pixelSize: 12 }
                    GButton { Layout.alignment: Qt.AlignHCenter; theme: root.theme; kind: "tonal"; text: "Open in Code"; iconSource: "code-context"
                        onClicked: backend.openCode(root.project.path) }
                }
            }

            // Forge Canvas
            RowLayout {
                spacing: 0

                // Palette
                Rectangle {
                    Layout.preferredWidth: 252; Layout.fillHeight: true; color: root.theme.card
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        QQC2.Label { text: "Nodes"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 17; font.bold: true }
                        QQC2.Label { text: "Drag and drop to build your workflow"; color: root.theme.textLo; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }

                        QQC2.ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            ColumnLayout {
                                width: 220; spacing: 6
                                Repeater {
                                    model: [
                                        { section: "ESSENTIAL" },
                                        { label: "GitHub Sync",           icon: "github",             accent: root.theme.purple, kind: "github" },
                                        { label: "Smart .gitignore",      icon: "document-edit",      accent: root.theme.green,  kind: "gitignore" },
                                        { label: "Environment Variables", icon: "lock",               accent: root.theme.turbo,  kind: "env" },
                                        { label: "Install Dependencies",  icon: "download",           accent: root.theme.blue,   kind: "install" },
                                        { label: "Run Script",            icon: "utilities-terminal", accent: root.theme.purple, kind: "script" },
                                        { section: "INFRASTRUCTURE" },
                                        { label: "Docker",       icon: "docker",              accent: root.theme.blue,   kind: "docker" },
                                        { label: "Database",     icon: "server-database",     accent: root.theme.green,  kind: "database" },
                                        { label: "API Service",  icon: "internet-web-browser",accent: root.theme.purple, kind: "api" },
                                        { label: "Redis",        icon: "server-database",     accent: root.theme.red,    kind: "redis" },
                                        { label: "Web Hook",     icon: "link",                accent: root.theme.green,  kind: "webhook" },
                                        { section: "DOCUMENTATION" },
                                        { label: "Generate README",   icon: "document-edit", accent: root.theme.blue,  kind: "readme" },
                                        { label: "License",           icon: "emblem-important", accent: root.theme.turbo, kind: "license" },
                                        { label: "Contributing Guide",icon: "system-users",  accent: root.theme.green, kind: "contributing" }
                                    ]
                                    delegate: Item {
                                        Layout.fillWidth: true
                                        implicitHeight: modelData.section !== undefined ? 26 : 44
                                        QQC2.Label {
                                            visible: modelData.section !== undefined
                                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                                            text: modelData.section || ""
                                            color: root.theme.textLo; font.pixelSize: 10; font.bold: true
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
                        GButton { theme: root.theme; kind: "tonal"; text: "Auto-arrange"; iconSource: "color-gradient"; Layout.fillWidth: true
                            onClicked: root.autoArrange() }
                    }
                }
                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.theme.line }

                // Canvas
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: root.theme.bgBottom }
                            GradientStop { position: 1; color: root.theme.bgTop }
                        }
                    }
                    // Dotted grid
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = Qt.rgba(root.theme.lineHi.r, root.theme.lineHi.g, root.theme.lineHi.b, 0.5)
                            for (var x = 0; x < width; x += 28)
                                for (var y = 0; y < height; y += 28) { ctx.beginPath(); ctx.arc(x, y, 1, 0, 6.283); ctx.fill() }
                        }
                    }

                    // Drop target for palette drag-and-drop.
                    DropArea {
                        id: canvasDrop
                        anchors.fill: parent
                        keys: [ "genesi/node" ]
                        onDropped: function(drop) {
                            if (!dragGhost.def) return
                            var cx = (drop.x - root.panX) / root.zoom - 107
                            var cy = (drop.y - root.panY) / root.zoom - 60
                            root.addNodeAt(cx, cy, dragGhost.def)
                        }
                    }

                    // Pan handler (empty-canvas drag). Node cards sit on top in
                    // contentLayer, so dragging a node still moves the node.
                    MouseArea {
                        id: panner
                        anchors.fill: parent
                        cursorShape: Qt.OpenHandCursor
                        property real lastX: 0
                        property real lastY: 0
                        onPressed: function(m) { lastX = m.x; lastY = m.y }
                        onPositionChanged: function(m) {
                            root.panX += m.x - lastX; root.panY += m.y - lastY
                            lastX = m.x; lastY = m.y
                        }
                    }

                    // Panned + zoomed content
                    Item {
                        id: contentLayer
                        anchors.fill: parent
                        transform: [
                            Translate { x: root.panX; y: root.panY },
                            Scale { origin.x: 0; origin.y: 0; xScale: root.zoom; yScale: root.zoom }
                        ]

                        Canvas {
                            id: linkLayer
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                ctx.lineWidth = 2
                                for (var i = 0; i < root.links.length; i++) {
                                    var a = root.livePos[root.links[i].from], b = root.livePos[root.links[i].to]
                                    if (!a || !b) continue
                                    var x1 = a.x + (a.w || 214), y1 = a.y + (a.h || 120) / 2
                                    var x2 = b.x, y2 = b.y + (b.h || 120) / 2
                                    var acc = root.nodeAccent(root.links[i].from)
                                    ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.6)
                                    var dx = Math.max(40, Math.abs(x2 - x1) * 0.5)
                                    ctx.beginPath(); ctx.moveTo(x1, y1)
                                    ctx.bezierCurveTo(x1 + dx, y1, x2 - dx, y2, x2, y2); ctx.stroke()
                                    ctx.fillStyle = ctx.strokeStyle
                                    ctx.beginPath(); ctx.arc(x2, y2, 3.2, 0, 6.283); ctx.fill()
                                }
                                if (root.pendingFrom !== "") {
                                    var pa = root.livePos[root.pendingFrom]
                                    if (pa) {
                                        var px1 = pa.x + (pa.w || 214), py1 = pa.y + (pa.h || 120) / 2
                                        var pacc = root.nodeAccent(root.pendingFrom)
                                        ctx.strokeStyle = Qt.rgba(pacc.r, pacc.g, pacc.b, 0.9)
                                        ctx.setLineDash([ 6, 4 ])
                                        var pdx = Math.max(40, Math.abs(root.pendingX - px1) * 0.5)
                                        ctx.beginPath(); ctx.moveTo(px1, py1)
                                        ctx.bezierCurveTo(px1 + pdx, py1, root.pendingX - pdx, root.pendingY, root.pendingX, root.pendingY)
                                        ctx.stroke(); ctx.setLineDash([])
                                    }
                                }
                            }
                        }

                        // Section title chip (top-left of the canvas)
                        Rectangle {
                            x: 24; y: 18
                            width: titleCol.implicitWidth + 44; height: titleCol.implicitHeight + 22
                            radius: 12; color: root.theme.a(root.theme.green, 0.08)
                            border.width: 1; border.color: root.theme.a(root.theme.green, 0.3)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 16; spacing: 10
                                Kirigami.Icon { source: "media-playback-start"; width: 18; height: 18; color: root.theme.greenBright }
                                ColumnLayout {
                                    id: titleCol; spacing: 0
                                    QQC2.Label { text: "Setup Inicial e Boilerplate"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 14; font.bold: true }
                                    QQC2.Label { text: "Automate your project setup from scratch"; color: root.theme.textMid; font.pixelSize: 11 }
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

                    // Mini-map
                    Rectangle {
                        x: 20; y: parent.height - height - 20
                        width: 190; height: 130; radius: 12
                        color: root.theme.a(root.theme.bgBottom, 0.9)
                        border.width: 1; border.color: root.theme.line
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            QQC2.Label { text: "Canvas Mini-map"; color: root.theme.textMid; font.pixelSize: 11; font.bold: true }
                            Canvas {
                                id: miniMap
                                Layout.fillWidth: true; Layout.fillHeight: true
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                                    var sx = width / 1180, sy = height / 720
                                    for (var i = 0; i < root.nodes.length; i++) {
                                        var p = root.livePos[root.nodes[i].id]; if (!p) continue
                                        var acc = root.nodes[i].accent
                                        ctx.fillStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.85)
                                        ctx.fillRect(p.x * sx, p.y * sy, 14 * sx, 8 * sy)
                                    }
                                }
                            }
                        }
                    }
                    // Zoom controls
                    ColumnLayout {
                        x: parent.width - 56; y: parent.height - 168; spacing: 8
                        Repeater {
                            model: [ { ic: "zoom-fit-best", act: "fit" }, { ic: "list-add", act: "in" }, { ic: "list-remove", act: "out" }, { ic: "lock", act: "lock" } ]
                            delegate: Rectangle {
                                Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 9
                                color: zma.containsMouse ? root.theme.cardHi : root.theme.card
                                border.width: 1; border.color: root.theme.line
                                Kirigami.Icon { anchors.centerIn: parent; source: modelData.ic; width: 16; height: 16; color: root.theme.textMid }
                                MouseArea { id: zma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.zoomAction(modelData.act) }
                            }
                        }
                    }
                }
                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.theme.line }

                // Config panel
                Rectangle {
                    Layout.preferredWidth: 322; Layout.fillHeight: true; color: root.theme.card
                    ConfigPanel { anchors.fill: parent; theme: root.theme; project: root.project; node: root.selectedNode(); graphProvider: root }
                }
            }
        }

        // ── Status bar ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 48
            visible: root.tab === "canvas"
            color: root.theme.bgTop
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: root.theme.line }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 18; spacing: 10
                Rectangle { width: 9; height: 9; radius: 5; color: root.running ? root.theme.blue : root.theme.greenBright }
                QQC2.Label { text: "Workflow Status:"; color: root.theme.textMid; font.pixelSize: 13 }
                QQC2.Label { text: root.running ? "Running…" : "Ready"; color: root.running ? root.theme.blue : root.theme.greenBright; font.pixelSize: 13; font.bold: true }
                Item { Layout.fillWidth: true }
                GButton { theme: root.theme; kind: "tonal"; text: "Save Workflow"; iconSource: "document-save"
                    onClicked: backend.saveWorkflow(root.project.path, root.graphJson()) }
            }
        }
    }

    // Floating drag ghost (shared by every PaletteItem). Follows the cursor
    // from the palette onto the canvas; the DropArea creates the node.
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
            anchors.fill: parent; radius: 11; opacity: 0.96
            color: root.theme.cardHi
            border.width: 1.5
            border.color: dragGhost.def ? root.theme.a(dragGhost.def.accent, 0.7) : root.theme.a(root.theme.green, 0.6)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 9
                Rectangle {
                    width: 26; height: 26; radius: 7
                    color: dragGhost.def ? root.theme.a(dragGhost.def.accent, 0.18) : "transparent"
                    Kirigami.Icon { anchors.centerIn: parent; source: dragGhost.def ? dragGhost.def.icon : ""; width: 15; height: 15
                        color: dragGhost.def ? dragGhost.def.accent : root.theme.green }
                }
                QQC2.Label { text: dragGhost.def ? dragGhost.def.label : ""; color: root.theme.textHi; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    signal toast(string msg)

    function nodeAccent(id) {
        for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i].accent
        return theme.green
    }

    function addNode(def) { addNodeAt(460, 300, def) }

    function addNodeAt(nx, ny, def) {
        var id = def.kind + "-" + Date.now()
        var n = { id: id, kind: def.kind, title: def.label, icon: def.icon, accent: def.accent,
                  x: nx, y: ny, lines: ["New step"], status: "Draft", statusKind: "ok" }
        var arr = nodes.slice()
        // Persist current (possibly dragged) positions so the rebuild doesn't
        // snap existing nodes back to their defaults.
        for (var i = 0; i < arr.length; i++) {
            var p = livePos[arr[i].id]
            if (p) { arr[i].x = p.x; arr[i].y = p.y }
        }
        arr.push(n); nodes = arr
        selectedId = id
        Qt.callLater(function() { updatePos(id, nx, ny, 214, 120) })
        toast(def.label + " node added.")
    }

    function autoArrange() {
        var arr = nodes.slice()
        var cols = 4, gapX = 250, gapY = 210, x0 = 60, y0 = 120
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

    function zoomAction(act) {
        if (act === "in") zoom = Math.min(1.6, zoom + 0.1)
        else if (act === "out") zoom = Math.max(0.5, zoom - 0.1)
        else if (act === "fit") zoom = 1.0
    }

    // ── Editing (delete / rename / steps) ───────────────────────────────────
    function _syncPositions(arr) {
        for (var i = 0; i < arr.length; i++) {
            var p = livePos[arr[i].id]
            if (p) { arr[i].x = p.x; arr[i].y = p.y }
        }
        return arr
    }
    function deleteNode(id) {
        var arr = _syncPositions(nodes.slice()).filter(function(n) { return n.id !== id })
        links = links.filter(function(l) { return l.from !== id && l.to !== id })
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

    // ── Linking (drag from a node's output port) ────────────────────────────
    function beginLink(id, sx, sy) {
        pendingFrom = id
        var c = linkLayer.mapFromItem(null, sx, sy)
        pendingX = c.x; pendingY = c.y
        linkLayer.requestPaint()
    }
    function moveLink(sx, sy) {
        var c = linkLayer.mapFromItem(null, sx, sy)
        pendingX = c.x; pendingY = c.y
        linkLayer.requestPaint()
    }
    function endLink(sx, sy) {
        var c = linkLayer.mapFromItem(null, sx, sy)
        var target = ""
        for (var id in livePos) {
            var p = livePos[id]
            if (c.x >= p.x && c.x <= p.x + (p.w || 214) && c.y >= p.y && c.y <= p.y + (p.h || 120)) { target = id; break }
        }
        if (target && target !== pendingFrom) addLink(pendingFrom, target)
        pendingFrom = ""
        linkLayer.requestPaint()
    }
    function addLink(fromId, toId) {
        for (var i = 0; i < links.length; i++)
            if (links[i].from === fromId && links[i].to === toId) { pendingFrom = ""; return }
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
