// GENESI STORE — the window.
//
// A spine on the left, a shelf in the middle, one line at the bottom saying
// what is happening. Everything it shows comes from `genesi-store catalog`;
// everything it does goes back through `genesi-store apply`.
//
// ── The mosaic ──────────────────────────────────────────────────────────────
//
// Cards are not all the same size, and the sizes are not decorative: a whole
// desktop is a big picture and a colour scheme is a small one, so a rice gets
// two columns and two rows, a wallpaper gets two columns, and everything else
// gets one. The grid is laid out by hand into a fixed column count rather than
// by a Flow, because a Flow with mixed sizes leaves holes, and a shop with
// holes in the shelf looks broken rather than airy.
//
// ── Why Discover is a view and not a shelf ─────────────────────────────────
//
// The catalogue has no items in the "discover" section, on purpose. Discover
// is the front of the shop: the week's collection, then a handful out of every
// other shelf. If it were a shelf of its own, somebody would have to remember
// to put things on it, and the day they forgot it would be an empty shop.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import "."
import "components"

QQC2.ApplicationWindow {
    id: win

    property var items: []
    property var sections: []
    property string section: "discover"
    property string filter: ""
    property string search: ""
    property var busy: ({})
    property string message: ""
    property var sheetItem: null
    property string railLabel: ""
    property real railLabelY: 0
    property string thumbDir: store.thumbDir()

    readonly property var featured: win.byId("rice-floresta-viva")

    // What each shelf calls the things on it, for the line above a card's name.
    readonly property var kindLabels: ({
            "rices": qsTr("ambiente"),
            "themes": qsTr("tema"),
            "decor": qsTr("papel de parede"),
            "lockscreens": qsTr("bloqueio"),
            "bars": qsTr("barra"),
            "fastfetch": qsTr("terminal"),
            "bundles": qsTr("coleção")
        })

    function byId(ident) {
        for (let i = 0; i < win.items.length; i++)
            if (win.items[i].id === ident)
                return win.items[i];
        return null;
    }

    function inSection(id) {
        return win.items.filter(i => i.section === id);
    }

    function shown() {
        let list = win.section === "discover" ? win.items : win.inSection(win.section);
        if (win.filter === "applied")
            return list.filter(i => i.applied);
        if (win.filter)
            list = list.filter(i => (i.tags ?? []).indexOf(win.filter) >= 0
                               || i.family === win.filter);
        if (win.search) {
            const needle = win.search.toLowerCase();
            list = list.filter(i => (i.name ?? "").toLowerCase().indexOf(needle) >= 0
                               || (i.blurb ?? "").toLowerCase().indexOf(needle) >= 0
                               || (i.tags ?? []).join(" ").toLowerCase().indexOf(needle) >= 0);
        }
        if (win.section === "discover" && !win.filter && !win.search) {
            const out = [];
            for (const shelf of ["rices", "themes", "decor", "lockscreens", "bars", "fastfetch", "bundles"])
                out.push(...win.inSection(shelf).slice(0, shelf === "rices" ? 2 : 4));
            return out;
        }
        return list;
    }

    function chips() {
        const seen = {};
        for (const item of (win.section === "discover" ? win.items : win.inSection(win.section)))
            for (const tag of (item.tags ?? []))
                seen[tag] = (seen[tag] ?? 0) + 1;
        return Object.keys(seen).filter(t => seen[t] >= 2).sort((a, b) => seen[b] - seen[a]).slice(0, 7);
    }

    // ── The mosaic ───────────────────────────────────────────────────────────
    //
    // Each item asks for a width and a height in CELLS; this walks a row of
    // occupied columns and drops every card in the first place it fits, which
    // is the smallest layout that never leaves a hole.
    function span(item) {
        if (item.section === "rices" || item.section === "bundles")
            return {"w": 2, "h": 2};
        if (item.section === "decor" || item.section === "lockscreens")
            return {"w": 2, "h": 1};
        return {"w": 1, "h": 1};
    }

    function layout(list, columns) {
        const placed = [];
        const filled = [];          // how many rows deep each column is taken
        for (let c = 0; c < columns; c++)
            filled.push(0);

        for (const item of list) {
            const want = win.span(item);
            const w = Math.min(want.w, columns);
            let best = -1;
            let bestRow = Infinity;
            for (let c = 0; c + w <= columns; c++) {
                let row = 0;
                for (let k = c; k < c + w; k++)
                    row = Math.max(row, filled[k]);
                if (row < bestRow) {
                    bestRow = row;
                    best = c;
                }
            }
            placed.push({"item": item, "col": best, "row": bestRow,
                         "w": w, "h": want.h});
            for (let k = best; k < best + w; k++)
                filled[k] = bestRow + want.h;
        }
        let rows = 0;
        for (const f of filled)
            rows = Math.max(rows, f);
        return {"placed": placed, "rows": rows};
    }

    function applyItem(item) {
        const parts = item.includes ?? [];
        if (parts.length > 0) {
            for (const ident of parts)
                store.apply(ident);
            return;
        }
        store.apply(item.id);
    }

    width: 1280
    height: 820
    minimumWidth: 980
    minimumHeight: 660
    visible: true
    title: qsTr("Genesi Store")
    color: Tokens.bg

    // ── The spine ────────────────────────────────────────────────────────────
    Rectangle {
        id: rail

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Tokens.railWidth
        color: Tokens.rail

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Tokens.hairline
        }

        Leaf {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
            width: 34
            height: 34
            colour: Tokens.accent
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 82
            spacing: 2

            Repeater {
                model: win.sections

                RailButton {
                    required property var modelData

                    icon: modelData.id
                    label: modelData.label
                    current: win.section === modelData.id
                    onActivated: {
                        win.section = modelData.id;
                        win.filter = "";
                        win.search = "";
                    }
                    // The name floats OUTSIDE the rail, so it is drawn by the
                    // window rather than by the button: a label drawn inside
                    // the rail appears under the cards, which is what the
                    // first version did.
                    onHoveredChanged: {
                        if (hovered) {
                            win.railLabel = modelData.label;
                            win.railLabelY = mapToItem(win.contentItem, 0, height / 2).y;
                        } else if (win.railLabel === modelData.label) {
                            win.railLabel = "";
                        }
                    }
                }
            }
        }

        RailButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            icon: "settings"
            label: qsTr("Genesi Center")
            onActivated: store.openCenter()
            onHoveredChanged: {
                if (hovered) {
                    win.railLabel = qsTr("Genesi Center");
                    win.railLabelY = mapToItem(win.contentItem, 0, height / 2).y;
                } else if (win.railLabel === qsTr("Genesi Center")) {
                    win.railLabel = "";
                }
            }
        }
    }

    // ── The header ───────────────────────────────────────────────────────────
    Item {
        id: header

        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        height: 76

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11

            Leaf {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                colour: Tokens.accent
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: qsTr("GENESI STORE")
                    color: Tokens.textHi
                    font.family: Tokens.sans
                    font.pixelSize: Tokens.fsCard
                    font.letterSpacing: 2.6
                    font.weight: Font.DemiBold
                }
                Text {
                    text: qsTr("personalize um amanhã mais tranquilo")
                    color: Tokens.textFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    font.letterSpacing: 1.1
                }
            }
        }

        Rectangle {
            id: searchBox

            anchors.centerIn: parent
            width: Math.min(440, header.width * 0.4)
            height: 40
            radius: 20
            color: Tokens.card
            border.width: 1
            border.color: field.activeFocus ? Tokens.a(Tokens.accent, 0.55) : Tokens.line

            Glyph {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 16
                colour: Tokens.textDim
            }

            QQC2.TextField {
                id: field

                anchors.fill: parent
                anchors.leftMargin: 38
                anchors.rightMargin: 14
                background: null
                color: Tokens.textHi
                placeholderText: qsTr("O que você quer transformar hoje?")
                placeholderTextColor: Tokens.textFaint
                font.family: Tokens.sans
                font.pixelSize: Tokens.fsBody
                onTextChanged: win.search = text
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Chip {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Biblioteca")
                selected: win.filter === "applied"
                onActivated: {
                    win.section = "discover";
                    win.filter = win.filter === "applied" ? "" : "applied";
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: 19
                color: Tokens.card
                border.width: 1
                border.color: Tokens.line

                Glyph {
                    anchors.centerIn: parent
                    name: "refresh"
                    size: 17
                    colour: Tokens.textDim
                }
                TapHandler {
                    onTapped: store.load()
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    // ── The shelf ────────────────────────────────────────────────────────────
    QQC2.ScrollView {
        id: scroller

        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: queue.top
        anchors.leftMargin: 22
        anchors.rightMargin: 40
        contentWidth: availableWidth
        clip: true

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            width: 8
            policy: QQC2.ScrollBar.AsNeeded

            contentItem: Rectangle {
                radius: 4
                color: Tokens.a(Tokens.accentSoft, parent.pressed ? 0.5 : 0.24)
            }
            background: Rectangle {
                color: "transparent"
            }
        }

        Column {
            width: parent.width
            spacing: 18
            bottomPadding: 26

            // ── The week's collection, and a preview beside it ───────────────
            Item {
                width: parent.width
                height: 250
                visible: win.section === "discover" && !win.search && !win.filter && win.featured

                Rectangle {
                    id: heroCard

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.62
                    radius: Tokens.radiusLg
                    color: Tokens.card
                    border.width: 1
                    border.color: Tokens.line
                    clip: true

                    Preview {
                        anchors.fill: parent
                        spec: win.featured ? win.featured.preview : ({})
                        thumbDir: win.thumbDir
                        detailed: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: Qt.rgba(0.02, 0.06, 0.04, 0.94)
                            }
                            GradientStop {
                                position: 0.75
                                color: Qt.rgba(0.02, 0.06, 0.04, 0.35)
                            }
                            GradientStop {
                                position: 1
                                color: "transparent"
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.62
                        spacing: 8

                        Row {
                            spacing: 8

                            Leaf {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13
                                height: 13
                                colour: Tokens.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("COLEÇÃO DA SEMANA")
                                color: Tokens.accentSoft
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 2
                            }
                        }

                        Text {
                            text: win.featured ? win.featured.name : ""
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 42
                            font.weight: Font.Light
                        }

                        Text {
                            width: parent.width
                            text: win.featured ? win.featured.blurb : ""
                            color: Tokens.text
                            font.family: Tokens.sans
                            font.pixelSize: Tokens.fsBody
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            width: 1
                            height: 6
                        }

                        Row {
                            spacing: 10

                            Rectangle {
                                width: 150
                                height: 42
                                radius: Tokens.radiusSm
                                color: heroTap.pressed ? Tokens.accentDeep : Tokens.accent

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Glyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "play"
                                        size: 16
                                        colour: Tokens.bgDeep
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("Aplicar")
                                        color: Tokens.bgDeep
                                        font.family: Tokens.sans
                                        font.pixelSize: Tokens.fsBody
                                        font.weight: Font.DemiBold
                                    }
                                }
                                TapHandler {
                                    id: heroTap

                                    onTapped: if (win.featured) win.applyItem(win.featured)
                                }
                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            Chip {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Ver o que vem junto")
                                onActivated: win.sheetItem = win.featured
                            }
                        }
                    }
                }

                // The live preview panel from the design: the same drawing,
                // with the other collections stacked beside it.
                Rectangle {
                    anchors.left: heroCard.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: Tokens.radiusLg
                    color: Tokens.card
                    border.width: 1
                    border.color: Tokens.line

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        spacing: 7

                        Leaf {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            colour: Tokens.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Prévia ao vivo")
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: Tokens.fsBody
                            font.weight: Font.Medium
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 16
                        anchors.topMargin: 44
                        spacing: 10

                        Rectangle {
                            width: parent.width - 86
                            height: parent.height
                            radius: Tokens.radiusSm
                            color: Tokens.bgDeep
                            clip: true

                            Preview {
                                anchors.fill: parent
                                spec: win.sheetItem ? win.sheetItem.preview
                                                    : (win.featured ? win.featured.preview : ({}))
                                thumbDir: win.thumbDir
                                detailed: true
                            }
                        }

                        Column {
                            width: 76
                            spacing: 8

                            Repeater {
                                model: win.inSection("rices").slice(1, 4)

                                Rectangle {
                                    required property var modelData

                                    width: 76
                                    height: 48
                                    radius: 8
                                    color: Tokens.bgDeep
                                    border.width: 1
                                    border.color: Tokens.line
                                    clip: true

                                    Preview {
                                        anchors.fill: parent
                                        spec: modelData.preview ?? ({})
                                        thumbDir: win.thumbDir
                                    }

                                    TapHandler {
                                        onTapped: win.sheetItem = modelData
                                    }
                                    HoverHandler {
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Where you are, and what you can narrow it to ─────────────────
            Item {
                width: parent.width
                height: 36

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: {
                            if (win.search)
                                return qsTr("Resultados para “%1”").arg(win.search);
                            if (win.filter === "applied")
                                return qsTr("Na sua biblioteca");
                            if (win.section === "discover")
                                return qsTr("Cultivado para você");
                            for (const s of win.sections)
                                if (s.id === win.section)
                                    return s.label;
                            return "";
                        }
                        color: Tokens.textHi
                        font.family: Tokens.sans
                        font.pixelSize: Tokens.fsTitle
                        font.weight: Font.Medium
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Chip {
                        text: qsTr("Tudo")
                        selected: win.filter === ""
                        onActivated: win.filter = ""
                    }

                    Repeater {
                        model: win.chips()

                        Chip {
                            required property string modelData

                            text: modelData
                            selected: win.filter === modelData
                            onActivated: win.filter = win.filter === modelData ? "" : modelData
                        }
                    }
                }
            }

            // ── The cards, in a mosaic ───────────────────────────────────────
            Item {
                id: mosaic

                readonly property int columns: Math.max(2, Math.floor(width / 250))
                readonly property real cell: (width - (columns - 1) * Tokens.gap) / columns
                readonly property real rowHeight: 152
                readonly property var plan: win.layout(win.shown(), columns)

                width: parent.width
                height: plan.rows * (rowHeight + Tokens.gap)

                Repeater {
                    model: mosaic.plan.placed

                    ItemCard {
                        required property var modelData

                        x: modelData.col * (mosaic.cell + Tokens.gap)
                        y: modelData.row * (mosaic.rowHeight + Tokens.gap)
                        width: modelData.w * mosaic.cell + (modelData.w - 1) * Tokens.gap
                        height: modelData.h * mosaic.rowHeight + (modelData.h - 1) * Tokens.gap
                        item: modelData.item
                        thumbDir: win.thumbDir
                        large: modelData.h > 1
                        busy: win.busy[modelData.item.id] ?? ""
                        onPrimary: win.applyItem(modelData.item)
                        onOpened: win.sheetItem = modelData.item
                    }
                }
            }

            // Nothing matched: say so, rather than showing an empty shelf.
            Item {
                width: parent.width
                height: win.shown().length === 0 ? 120 : 0
                visible: height > 0

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.section === "plugins" ? qsTr("Plugins vêm depois")
                                                        : qsTr("Nada por aqui")
                        color: Tokens.textHi
                        font.family: Tokens.sans
                        font.pixelSize: Tokens.fsCard
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.section === "plugins"
                              ? qsTr("Aqui vão entrar extensões que mudam o comportamento do sistema, não só a aparência.")
                              : qsTr("Tente outro termo, ou tire os filtros.")
                        color: Tokens.textDim
                        font.family: Tokens.sans
                        font.pixelSize: Tokens.fsLabel
                    }
                }
            }
        }
    }

    // ── One line that says what is happening ─────────────────────────────────
    Rectangle {
        id: queue

        anchors.left: rail.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: win.message || Object.keys(win.busy).length > 0 ? 56 : 0
        color: Tokens.rail
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Tokens.normal
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Tokens.hairline
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11

            Leaf {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                colour: Tokens.accent

                RotationAnimation on rotation {
                    running: Object.keys(win.busy).length > 0
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 2600
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.message
                color: Tokens.text
                font.family: Tokens.sans
                font.pixelSize: Tokens.fsBody
            }
        }
    }

    // The line down the right edge: texture, in Genesi's own voice.
    Item {
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: queue.top
        width: 26

        Text {
            anchors.centerIn: parent
            rotation: 90
            transformOrigin: Item.Center
            text: qsTr("NATUREZA INSPIRA SISTEMAS MELHORES")
            color: Tokens.textFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 3
        }
    }

    // ── The rail's hover label, drawn last so it is drawn on top ─────────────
    Rectangle {
        visible: win.railLabel !== ""
        x: Tokens.railWidth - 6
        y: win.railLabelY - height / 2
        width: railText.implicitWidth + 20
        height: 30
        radius: 9
        color: Tokens.cardHi
        border.width: 1
        border.color: Tokens.line
        z: 50

        Text {
            id: railText

            anchors.centerIn: parent
            text: win.railLabel
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsBody
        }
    }

    // ── One thing, in full ───────────────────────────────────────────────────
    ItemSheet {
        z: 60
        item: win.sheetItem
        thumbDir: win.thumbDir
        busy: win.sheetItem ? (win.busy[win.sheetItem.id] ?? "") : ""
        resolve: ident => win.byId(ident)
        onApply: if (win.sheetItem) win.applyItem(win.sheetItem)
        onRevert: if (win.sheetItem) store.revert(win.sheetItem.id)
        onClosed: win.sheetItem = null
        onOpenItem: ident => win.sheetItem = win.byId(ident)
    }

    Connections {
        target: store

        function onCatalogLoaded(payload) {
            const data = JSON.parse(payload);
            const list = data.items ?? [];
            for (const item of list) {
                item.kindLabel = win.kindLabels[item.section] ?? "";
                // The lock shelf holds two different machines: hyprlock, in
                // your session, and SDDM, before it. They are not variants of
                // one thing, and a card that calls both "bloqueio" is the
                // reason somebody picks the wrong one.
                if (item.family === "login")
                    item.kindLabel = qsTr("tela de login");
                else if (item.family === "session")
                    item.kindLabel = qsTr("bloqueio da sessão");
            }
            win.items = list;
            // The sheet holds a copy of an item; refresh it so its button
            // stops saying "Aplicar" the moment the apply lands.
            if (win.sheetItem)
                win.sheetItem = win.byId(win.sheetItem.id);
        }

        function onSectionsLoaded(payload) {
            win.sections = JSON.parse(payload).sections ?? [];
        }

        function onBusyChanged(ident, saying) {
            const next = {};
            for (const key in win.busy)
                next[key] = win.busy[key];
            if (saying)
                next[ident] = saying;
            else
                delete next[ident];
            win.busy = next;
            const names = Object.keys(next);
            if (names.length)
                win.message = names.length > 1
                    ? qsTr("%1 %2 itens…").arg(saying).arg(names.length)
                    : qsTr("%1 %2…").arg(saying).arg((win.byId(ident) ?? ({})).name ?? "");
        }

        function onFinished(ident, ok, detail) {
            if (!ok) {
                win.message = detail;
                messageTimer.restart();
                return;
            }
            win.message = qsTr("Pronto.");
            messageTimer.restart();
        }
    }

    Timer {
        id: messageTimer

        interval: 5000
        onTriggered: win.message = ""
    }
}
