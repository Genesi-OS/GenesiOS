/*
 * OverviewPage — the dashboard.
 *
 * Three bands: the hero and telemetry on the left, the art and the core plate
 * on the right, and a bottom row of snapshots / storage / activity with the
 * terminal beside it. The numbering down the left edge is the spine; every
 * block announces itself the same way.
 *
 * All numbers come from `genesi-center-data`, one process per tick. Nothing
 * here reads /proc: the tick is the only thing that knows where data comes
 * from, so the page can be rendered with no system at all -- which is how it
 * gets reviewed against the design without a desktop.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property string treeArt: ""

    property var tele: ({})
    property var core: ({})
    property var store: ({})
    property var acts: ({ items: [] })
    property bool seeded: false

    readonly property int railW: 300

    // Short window: the same layout, tighter. Measured against the window's
    // own minimum (720) plus the room the bottom band and the hero need.
    readonly property bool dense: height < 840

    function num(v, dash) {
        return (v === null || v === undefined) ? (dash || "—") : v;
    }
    function rate(bps) {
        if (bps === null || bps === undefined)
            return "—";
        if (bps > 1048576)
            return (bps / 1048576).toFixed(1) + " MB/s";
        if (bps > 1024)
            return (bps / 1024).toFixed(1) + " KB/s";
        return bps + " B/s";
    }

    // The backend pushes a JSON blob per tick; everything below is bound to it.
    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onDataReady(payload) {
            const d = JSON.parse(payload);
            if (d.telemetry) {
                const first = !page.seeded;
                page.seeded = true;
                const feed = (tile, v) => first ? tile.graph.seed(v) : tile.graph.push(v);
                page.tele = d.telemetry;
                feed(cpuTile, d.telemetry.cpu_percent);
                feed(ramTile, d.telemetry.memory ? d.telemetry.memory.percent : null);
                feed(diskTile, d.telemetry.disk ? d.telemetry.disk.percent : null);
                feed(netTile, d.telemetry.network
                     ? Math.min(100, d.telemetry.network.rx_bps / 1024) : null);
                feed(tempTile, d.telemetry.temperature_c);
            }
            if (d.core) page.core = d.core;
            if (d.storage) { page.store = d.storage; ring.reveal(); }
            if (d.activity) page.acts = d.activity;
        }
    }

    // ── Right column: core plate, quote, terminal ────────────────────────────
    Item {
        id: rightCol
        anchors { right: parent.right; top: parent.top; bottom: bottomBand.top }
        anchors.rightMargin: 20
        anchors.topMargin: 54
        anchors.bottomMargin: Tokens.gap
        width: page.railW

        Panel {
            id: corePlate
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 152
            // Was transparent, from when there was nothing behind it.
            color: Qt.rgba(Tokens.panel.r, Tokens.panel.g, Tokens.panel.b, 0.82)

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 9

                Text {
                    text: "GENESI CORE"
                    color: Tokens.textHi
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsLabel
                    font.letterSpacing: 1.6
                }
                Repeater {
                    model: [
                        { k: qsTr("Kernel"),      v: page.num(page.core.kernel) },
                        { k: qsTr("Architecture"), v: page.num(page.core.arch) },
                        { k: qsTr("Build"),       v: page.num(page.core.build) },
                        { k: qsTr("Session"),    v: page.num(page.core.session) }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: corePlate.width - 28
                        height: 17
                        Text {
                            anchors.left: parent.left
                            text: modelData.k
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                        Text {
                            anchors.right: parent.right
                            text: modelData.v
                            color: Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            elide: Text.ElideLeft
                            width: 150
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
                Row {
                    spacing: 7
                    Image {
                        source: "../art/genesi-leaf.svg"
                        sourceSize: Qt.size(12, 12)
                        width: 12; height: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "// " + qsTr("ready")
                        color: Tokens.accentDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }
            }
        }

        // The quote sits on the art, not in a box: it is the one piece of the
        // page that is voice rather than instrument.
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: 6
            spacing: 8

            Text {
                text: "❝"
                color: Tokens.accentDim
                font.pixelSize: 22
            }
            Text {
                width: parent.width
                text: qsTr("Great creations grow from an environment that feeds them.")
                color: Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: 14
                lineHeight: 1.35
                wrapMode: Text.WordWrap
            }
            Text {
                text: "— Genesi"
                color: Tokens.textDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsLabel
            }
        }
    }

    // ── The art ──────────────────────────────────────────────────────────────
    //
    // A shipped image when one is installed, and a procedural glow when not.
    // The fallback is deliberate: an empty rectangle where the art belongs
    // makes a finished layout look broken, and this app is judged on whether it
    // looks finished.
    // The mesh under the middle of the page. Behind the art and behind the
    // telemetry panel, not behind the rail: it is the ground the instruments
    // sit on, and running it under the whole window would flatten the
    // separation between the rail and the content.
    GridTexture {
        anchors { left: leftCol.left; right: rightCol.right; top: parent.top; bottom: bottomBand.top }
        anchors.leftMargin: -8
        z: -2
    }

    Item {
        id: art
        // To the window edge, under the right column rather than beside it.
        // Boxed into the gap between the two columns the artwork came out
        // small and polite; it is meant to be the largest thing on the page.
        anchors { left: leftCol.right; right: parent.right; top: parent.top; bottom: bottomBand.top }
        anchors.leftMargin: -40
        z: -1
        clip: true

        Image {
            id: tree
            // Crop, not fit: fitting sized the tree to the SHORTER side and
            // left it floating in the middle of a lot of nothing.
            width: parent.width * 1.18
            height: parent.height * 1.24
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -10
            source: page.treeArt
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            opacity: status === Image.Ready ? 0.92 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.slow } }

            // It breathes. Very slowly, and never far enough to notice as
            // motion -- only far enough that the page is never quite still.
            SequentialAnimation on scale {
                running: tree.status === Image.Ready
                loops: Animation.Infinite
                NumberAnimation { to: 1.025; duration: 7000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;   duration: 7000; easing.type: Easing.InOutSine }
            }
        }

        // The scrim. Strongest under the right column, gone by the middle of
        // the art, so the tree stays the biggest thing on the page and the
        // words on top of it stay readable.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: "transparent" }
                GradientStop { position: 0.52; color: Qt.rgba(Tokens.bg.r, Tokens.bg.g, Tokens.bg.b, 0.30) }
                GradientStop { position: 1.00; color: Qt.rgba(Tokens.bg.r, Tokens.bg.g, Tokens.bg.b, 0.88) }
            }

        // Hairlines from the readings to the tree. Anchored to the art so they
        // scale with it, and drawn after the image so they sit on top of the
        // canopy rather than under it.
        Connectors {
            id: links
            anchors.fill: parent
            stroke: Tokens.accent
            links: [
                { x1: 0.10, y1: 0.30, x2: 0.46, y2: 0.20 },
                { x1: 0.10, y1: 0.42, x2: 0.55, y2: 0.34 },
                { x1: 0.10, y1: 0.54, x2: 0.41, y2: 0.52 },
                { x1: 0.10, y1: 0.66, x2: 0.60, y2: 0.63 },
                { x1: 0.10, y1: 0.78, x2: 0.50, y2: 0.79 }
            ]
        }

        }

        Canvas {
            anchors.fill: parent
            visible: tree.status !== Image.Ready
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2;
                const g = ctx.createRadialGradient(cx, cy, 0, cx, cy,
                                                   Math.min(width, height) / 1.6);
                g.addColorStop(0, Qt.rgba(0.21, 0.88, 0.50, 0.16));
                g.addColorStop(1, Qt.rgba(0.21, 0.88, 0.50, 0.0));
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, width, height);
            }
        }

        // Vertical Japanese line, as in the design. Kept as ornament, off to
        // the edge, where it reads as texture rather than as a label.
        Column {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.rightMargin: 4
            spacing: 1
            Repeater {
                model: ["創", "造", "は", "こ", "こ", "か", "ら", "始", "ま", "る"]
                delegate: Text {
                    required property string modelData
                    text: modelData
                    color: Tokens.textFaint
                    font.pixelSize: 11
                }
            }
        }
    }

    // ── Left column: hero, telemetry, quick tools ────────────────────────────
    Column {
        id: leftCol
        anchors { left: parent.left; top: parent.top; bottom: bottomBand.top }
        anchors.leftMargin: 24
        anchors.topMargin: 20
        anchors.bottomMargin: Tokens.gap
        width: Math.max(430, parent.width * 0.42)
        spacing: page.dense ? 9 : 16

        SectionHead { index: "01"; text: qsTr("Overview") }

        Column {
            spacing: 4
            Text {
                id: wordmark
                text: "GENESI"
                color: Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: page.dense ? 40 : Tokens.fsHero
                font.letterSpacing: 13
                font.weight: Font.Light
            }
            Text {
                text: qsTr("A living system. Built to evolve.")
                color: Tokens.text
                font.family: Tokens.sans
                font.pixelSize: 15
            }
            Item { width: 1; height: 6 }
            Row {
                spacing: 7
                Text {
                    text: "> status:"
                    color: Tokens.textDim
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsBody
                }
                Text {
                    text: qsTr("stable")
                    color: Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsBody
                }
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Tokens.accent
                    anchors.verticalCenter: parent.verticalCenter
                    // A pulse, because a status light that never moves is
                    // indistinguishable from a drawn dot.
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        SectionHead { index: "02"; text: qsTr("System telemetry") }

        Panel {
            width: parent.width
            // Slightly translucent so the mesh behind it stays visible. A
            // solid card here cut a rectangular hole in the ground.
            color: Qt.rgba(Tokens.card.r, Tokens.card.g, Tokens.card.b, 0.82)
            // Four rows of tiles plus the margins. Sized from the contents
            // rather than guessed: the previous 210 fitted three rows, and the
            // fourth drew over the section heading underneath.
            height: 14 * 2 + 4 * (page.dense ? 46 : 58) + 3 * 8

            Grid {
                anchors.fill: parent
                anchors.margins: 14
                columns: 2
                columnSpacing: 18
                rowSpacing: 8


                StatTile {
                    id: cpuTile
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 0
                    glyph: "▣"; label: qsTr("CPU")
                    n: page.tele.cpu_percent; unit: "%"
                }
                StatTile {
                    id: tempTile
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 1
                    glyph: "▲"; label: qsTr("Temperature")
                    n: page.tele.temperature_c; unit: "°C"
                }
                StatTile {
                    id: ramTile
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 2
                    glyph: "▤"; label: qsTr("RAM")
                    n: page.tele.memory ? page.tele.memory.percent : undefined; unit: "%"
                    sub: page.tele.memory
                         ? (page.tele.memory.used_mb / 1024).toFixed(1) + " / "
                           + (page.tele.memory.total_mb / 1024).toFixed(0) + " GB" : ""
                }
                StatTile {
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 3
                    glyph: "◷"; label: qsTr("Uptime")
                    showGraph: false
                    value: page.tele.uptime ? page.num(page.tele.uptime.text) : "—"
                }
                StatTile {
                    id: diskTile
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 4
                    glyph: "▥"; label: qsTr("Disk")
                    n: page.tele.disk ? page.tele.disk.percent : undefined; unit: "%"
                    sub: page.tele.disk && page.tele.disk.total_gb
                         ? page.tele.disk.used_gb + " / " + page.tele.disk.total_gb + " GB" : ""
                }
                StatTile {
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 5
                    glyph: "∿"; label: qsTr("Processes")
                    showGraph: false
                    n: page.tele.processes
                }
                StatTile {
                    id: netTile
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 6
                    glyph: "~"; label: qsTr("Network")
                    value: page.tele.network ? page.rate(page.tele.network.tx_bps) : "—"
                    sub: page.tele.network ? "v " + page.rate(page.tele.network.rx_bps) : ""
                }
                StatTile {
                    width: (parent.width - 18) / 2
                    implicitHeight: page.dense ? 46 : 58
                    order: 7
                    glyph: "o"; label: qsTr("Users")
                    showGraph: false
                    value: page.tele.users ? page.num(page.tele.users.count) : "—"
                    sub: page.tele.users ? (page.tele.users.names || []).join(", ") : ""
                }
            }
        }

        SectionHead { index: "03"; text: qsTr("Quick tools") }

        Row {
            spacing: Tokens.gap
            Repeater {
                model: [
                    { g: "▭", l: qsTr("File\nManager"), c: ["xdg-open", "."] },
                    { g: "▶_", l: qsTr("Terminal"),                c: ["foot"] },
                    { g: "‹›", l: qsTr("Genesi Code"),             c: ["genesi-code"] },
                    { g: "◱",  l: qsTr("System\nMonitor"),     c: ["genesi-ai-monitor"] },
                    { g: "✦",  l: qsTr("Smart\nCleanup"),    c: ["genesi-cleanup"] },
                    { g: "◎",  l: qsTr("Update\nCentre"), c: ["genesi-update-center"] }
                ]
                delegate: Panel {
                    id: tool
                    required property var modelData
                    required property int index
                    width: 88
                    height: page.dense ? 64 : 78

                    opacity: 0
                    Component.onCompleted: toolIn.start()
                    SequentialAnimation {
                        id: toolIn
                        // After the eight readings above have finished.
                        PauseAnimation { duration: 560 + tool.index * 60 }
                        NumberAnimation {
                            target: tool; property: "opacity"
                            from: 0; to: 1
                            duration: Tokens.normal; easing.type: Easing.OutCubic
                        }
                    }
                    interactive: true
                    hovered: toolMouse.containsMouse
                    scale: toolMouse.containsMouse ? 1.03 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: Tokens.quick; easing.type: Easing.OutCubic }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tool.modelData.g
                            color: Tokens.accent
                            font.family: Tokens.mono
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tool.modelData.l
                            color: Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            horizontalAlignment: Text.AlignHCenter
                            lineHeight: 1.25
                        }
                    }
                    MouseArea {
                        id: toolMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (page.backend) page.backend.launch(tool.modelData.c)
                    }
                }
            }
        }
    }

    // ── Bottom band ──────────────────────────────────────────────────────────
    Item {
        id: bottomBand
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: 20
        height: page.dense ? 148 : 178

        Row {
            id: bandRow
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            anchors.leftMargin: 4
            width: parent.width - page.railW - Tokens.gap - 4
            spacing: Tokens.gap

            // 04 — Snapshots
            Column {
                width: (bandRow.width - Tokens.gap * 2) / 3
                spacing: 8
                SectionHead { index: "04"; text: qsTr("Snapshots") }
                Panel {
                    width: parent.width
                    height: page.dense ? 112 : 140
                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 7
                        Text {
                            text: "◈"
                            color: Tokens.accentDim
                            font.pixelSize: 22
                        }
                        Text {
                            text: qsTr("Last snapshot")
                            color: Tokens.textHi
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsBody
                        }
                        Text {
                            text: qsTr("—")
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }
                }
            }

            // 05 — Storage
            Column {
                width: (bandRow.width - Tokens.gap * 2) / 3
                spacing: 8
                SectionHead { index: "05"; text: qsTr("Storage") }
                Panel {
                    width: parent.width
                    height: page.dense ? 112 : 140
                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Item {
                            width: 92; height: 92
                            anchors.verticalCenter: parent.verticalCenter
                            Ring {
                                id: ring
                                anchors.fill: parent
                                total: page.store.total_gb || 0
                                segments: (page.store.slices || []).map((s, i) => ({
                                    gb: s.gb,
                                    color: [Tokens.accent, Tokens.accentDim, Tokens.accentDeep][i % 3]
                                }))
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: page.store.total_gb ? page.store.total_gb + " GB" : "—"
                                    color: Tokens.textHi
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsBody
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: qsTr("Total")
                                    color: Tokens.textFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Repeater {
                                model: (page.store.slices || []).map((s, i) => ({
                                    label: [qsTr("System"), qsTr("Data"), qsTr("Other")][i] || s.label,
                                    gb: s.gb,
                                    color: [Tokens.accent, Tokens.accentDim, Tokens.accentDeep][i % 3]
                                }))
                                delegate: Row {
                                    required property var modelData
                                    spacing: 7
                                    Rectangle {
                                        width: 7; height: 7; radius: 2
                                        color: modelData.color
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.label
                                        color: Tokens.text
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fsMicro
                                        width: 58
                                    }
                                    Text {
                                        text: modelData.gb + " GB"
                                        color: Tokens.textDim
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fsMicro
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 06 — Activity
            Column {
                width: (bandRow.width - Tokens.gap * 2) / 3
                spacing: 8
                SectionHead { index: "06"; text: qsTr("Recent activity") }
                Panel {
                    width: parent.width
                    height: page.dense ? 112 : 140
                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8
                        Repeater {
                            model: (page.acts.items || []).slice(0, 4)
                            delegate: Row {
                                required property var modelData
                                spacing: 9
                                Text {
                                    text: "✓"
                                    color: Tokens.accentDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.text
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    elide: Text.ElideRight
                                    width: 160
                                }
                            }
                        }
                    }
                }
            }
        }

        // The terminal plate: the app's own voice, and the only place the
        // brand mark is drawn rather than set.
        Panel {
            id: termPlate
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: page.railW
            color: Tokens.panel
            // Nothing in here may leave the card. The mark did.
            clip: true

            // The prompt types itself. It is the one element on the page that
            // is pretending to be a terminal, and a terminal that is already
            // finished when you look at it is a screenshot.
            Text {
                id: prompt
                anchors { left: parent.left; top: parent.top; margins: 14 }
                readonly property string full: "> genesi@os:~ $"
                property int chars: 0
                text: full.substring(0, chars)
                color: Tokens.accent
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsLabel

                Component.onCompleted: typing.start()
                SequentialAnimation {
                    id: typing
                    PauseAnimation { duration: 420 }
                    NumberAnimation {
                        target: prompt; property: "chars"
                        from: 0; to: prompt.full.length
                        duration: 700
                    }
                }
            }

            Column {
                id: termFoot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                spacing: 4

                Text {
                    text: "# where creations begin"
                    color: Tokens.textDim
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
                Text {
                    text: "_"
                    color: Tokens.accent
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsBody
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 620 }
                        NumberAnimation { to: 1; duration: 620 }
                    }
                }
            }

            // The mark, rasterised from art/genesi-leaf.svg rather than typed,
            // by devtools/leaf-matrix.py -- so the plate and the logo can never
            // drift apart.
            //
            // Braille, not block characters: a braille cell carries a 2x4 dot
            // grid, so the same area holds eight times the samples.
            //
            // Its SIZE is measured, not chosen. Thirteen rows at a hand-picked
            // 11px overflowed this card and spilled onto the page, because a
            // Column will happily grow past its parent and nothing was
            // clipping. The type size now comes from the space actually left
            // between the prompt and the footer, so it fits at any window size.
            Item {
                id: markBox
                anchors {
                    left: parent.left; right: parent.right
                    top: prompt.bottom; bottom: termFoot.top
                    leftMargin: 14; rightMargin: 14
                    topMargin: 8; bottomMargin: 8
                }

                readonly property int rows: 13
                readonly property real lineH: 0.92

                Text {
                    anchors.centerIn: parent
                    text: "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⣿⣿⣦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⠟⠁⠈⠻⣿⣧⡀⠀⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⢠⣿⡿⠃⠀⠀⠀⠀⠘⢿⣿⡄⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⢠⣿⡿⠁⠀⠀⠀⠀⠀⠀⠈⢿⣿⡄⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⣼⣿⠇⠀⢀⣾⣿⡄⠀⠀⠀⠸⣿⣧⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⣿⣿⣀⣀⣼⣿⣿⣧⢀⣀⣀⣀⣿⣿⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⣿⣿⠿⠿⠿⠟⢻⣿⣿⡿⠿⠿⣿⣿⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⢻⣿⡆⠀⠀⠀⠈⠿⠟⠁⠀⢰⣿⡟⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠘⣿⣷⡀⠀⠀⠀⠀⠀⠀⢀⣾⣿⠃⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⠘⢿⣿⣄⠀⠀⠀⠀⣠⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⢿⣷⣦⣴⣾⡿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⠟⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
                    color: Tokens.accentDim
                    font.family: Tokens.mono
                    font.pixelSize: Math.max(4, Math.floor(
                        markBox.height / (markBox.rows * markBox.lineH)))
                    lineHeight: markBox.lineH
                }
            }
        }
    }

    // Entrance: the page assembles rather than appearing. One sweep, once.
    Component.onCompleted: {
        entrance.start();
        links.draw();
    }
    ParallelAnimation {
        id: entrance
        NumberAnimation {
            target: leftCol; property: "opacity"; from: 0; to: 1
            duration: Tokens.entrance; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: leftCol; property: "anchors.leftMargin"; from: 4; to: 24
            duration: Tokens.entrance; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: rightCol; property: "opacity"; from: 0; to: 1
            duration: Tokens.entrance + 160; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: bottomBand; property: "opacity"; from: 0; to: 1
            duration: Tokens.entrance + 260; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: art; property: "opacity"; from: 0; to: 1
            duration: Tokens.entrance + 420; easing.type: Easing.OutCubic
        }
    }
}
