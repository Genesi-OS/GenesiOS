// GENESI STORE — the window.
//
// A spine on the left, a shelf in the middle, and one line at the bottom that
// says what is happening. Everything it shows comes from `genesi-store
// catalog`; everything it does goes back through `genesi-store apply`. The app
// holds no opinion about what a theme IS -- it draws cards and presses buttons.
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
import QtQuick.Layouts
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

    readonly property var featured: win.byId("rice-floresta-viva")

    function byId(ident) {
        for (let i = 0; i < win.items.length; i++)
            if (win.items[i].id === ident)
                return win.items[i];
        return null;
    }

    function inSection(id) {
        const out = [];
        for (let i = 0; i < win.items.length; i++)
            if (win.items[i].section === id)
                out.push(win.items[i]);
        return out;
    }

    // What the middle of the window is showing, after the shelf, the chips and
    // the search box have all had their say.
    function shown() {
        let list = win.section === "discover" ? win.items : win.inSection(win.section);
        if (win.filter)
            list = list.filter(i => (i.tags ?? []).indexOf(win.filter) >= 0
                               || i.section === win.filter
                               || i.family === win.filter);
        if (win.search) {
            const needle = win.search.toLowerCase();
            list = list.filter(i => (i.name ?? "").toLowerCase().indexOf(needle) >= 0
                               || (i.blurb ?? "").toLowerCase().indexOf(needle) >= 0
                               || (i.tags ?? []).join(" ").toLowerCase().indexOf(needle) >= 0);
        }
        if (win.section === "discover" && !win.filter && !win.search) {
            // A handful of each, so the front page is a sample of the shop
            // rather than eighty cards in catalogue order.
            const out = [];
            for (const shelf of ["rices", "themes", "decor", "lockscreens", "bars", "fastfetch", "bundles"])
                out.push(...win.inSection(shelf).slice(0, shelf === "rices" ? 3 : 4));
            return out;
        }
        return list;
    }

    // The chips above the shelf: what is actually on it, not a fixed list.
    function chips() {
        const seen = {};
        for (const item of (win.section === "discover" ? win.items : win.inSection(win.section)))
            for (const tag of (item.tags ?? []))
                seen[tag] = (seen[tag] ?? 0) + 1;
        return Object.keys(seen).filter(t => seen[t] >= 2).sort((a, b) => seen[b] - seen[a]).slice(0, 7);
    }

    width: 1280
    height: 820
    minimumWidth: 940
    minimumHeight: 640
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
            anchors.topMargin: 22
            width: 30
            height: 30
            colour: Tokens.accent
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 84
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
                    }
                }
            }
        }

        RailButton {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            icon: "settings"
            label: qsTr("Genesi Center")
            onActivated: Qt.openUrlExternally("")
        }
    }

    // ── The header ───────────────────────────────────────────────────────────
    Item {
        id: header

        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        height: 74

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: qsTr("GENESI STORE")
                color: Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: Tokens.fsCard
                font.letterSpacing: 2.4
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

        // Search: the fastest route in a shop with eighty things in it.
        Rectangle {
            id: searchBox

            anchors.centerIn: parent
            width: Math.min(460, header.width * 0.42)
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
                text: qsTr("Biblioteca")
                selected: win.filter === "applied"
                onActivated: {
                    win.section = "discover";
                    win.filter = win.filter === "applied" ? "" : "applied";
                }
            }

            Rectangle {
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
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: queue.top
        anchors.leftMargin: 22
        // Wider on the right: the line of type down that edge is part of the
        // page, and content sliding under it reads as a rendering fault.
        anchors.rightMargin: 40
        contentWidth: availableWidth
        clip: true

        // The desktop style draws a light scrollbar on a dark app, which is
        // the one piece of chrome nobody chose.
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
            bottomPadding: 24

            // ── The week's collection ────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 226
                visible: win.section === "discover" && !win.search && win.featured
                radius: Tokens.radiusLg
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: "#0f2418"
                    }
                    GradientStop {
                        position: 1
                        color: Tokens.card
                    }
                }
                border.width: 1
                border.color: Tokens.line
                clip: true

                Leaf {
                    anchors.right: parent.right
                    anchors.rightMargin: 60
                    anchors.verticalCenter: parent.verticalCenter
                    width: 190
                    height: 190
                    colour: Tokens.a(Tokens.accent, 0.13)
                    fill: 1
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.55
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
                        font.pixelSize: Tokens.fsHero
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
                            width: 148
                            height: 40
                            radius: Tokens.radiusSm
                            color: Tokens.accentDeep

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "play"
                                    size: 16
                                    colour: Tokens.textHi
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Aplicar coleção")
                                    color: Tokens.textHi
                                    font.family: Tokens.sans
                                    font.pixelSize: Tokens.fsBody
                                    font.weight: Font.Medium
                                }
                            }
                            TapHandler {
                                onTapped: if (win.featured) win.applyItem(win.featured)
                            }
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                            }
                        }

                        Chip {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Ver o que vem junto")
                            onActivated: win.section = "rices"
                        }
                    }
                }
            }

            // ── Where you are, and what you can narrow it to ─────────────────
            Item {
                width: parent.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (win.search)
                            return qsTr("Resultados para “%1”").arg(win.search);
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

            // ── The cards ────────────────────────────────────────────────────
            Flow {
                width: parent.width
                spacing: Tokens.gap

                Repeater {
                    model: win.shown()

                    ItemCard {
                        required property var modelData

                        item: modelData
                        wide: modelData.section === "rices" || modelData.section === "bundles"
                        busy: win.busy[modelData.id] ?? ""
                        onPrimary: win.applyItem(modelData)
                        onSecondary: store.revert(modelData.id)
                    }
                }
            }

            // Plugins: announced, not pretended.
            Rectangle {
                width: parent.width
                height: 96
                visible: win.section === "plugins"
                radius: Tokens.radius
                color: Tokens.card
                border.width: 1
                border.color: Tokens.line

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Plugins vêm depois")
                        color: Tokens.textHi
                        font.family: Tokens.sans
                        font.pixelSize: Tokens.fsCard
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Aqui vão entrar extensões que mudam o comportamento do sistema, não só a aparência.")
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
        height: win.message || Object.keys(win.busy).length > 0 ? 54 : 0
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
            spacing: 10

            Leaf {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
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

    // The line down the right edge, the way the Center has one: texture, and
    // Genesi's own voice rather than borrowed ornament.
    // In its own narrow column, not anchored to the edge directly: a rotated
    // Text still occupies its UNROTATED width for anchoring, so anchoring it
    // to the right edge put the strip a whole line-length inside the window,
    // across the chips.
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

    // ── Doing things ─────────────────────────────────────────────────────────
    function applyItem(item) {
        // A collection is its parts: applying it applies each of them, in the
        // order the catalogue lists them, so "one wallpaper and a theme" is
        // not two buttons.
        const parts = item.includes ?? [];
        if (parts.length > 0) {
            for (const ident of parts)
                store.apply(ident);
            return;
        }
        store.apply(item.id);
    }

    Connections {
        target: store

        function onCatalogLoaded(payload) {
            const data = JSON.parse(payload);
            const list = data.items ?? [];
            // The picture of a wallpaper, once it is on disk.
            for (const item of list)
                if (item.installed && item.preview && item.preview.kind === "image")
                    item.localPreview = store.assetPath(item.id);
            win.items = list;
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
            win.message = names.length ? qsTr("%1 %2…").arg(saying || qsTr("trabalhando")).arg(names.length > 1 ? qsTr("(%1 itens)").arg(names.length) : "") : win.message;
        }

        function onFinished(ident, ok, detail) {
            if (!ok) {
                win.message = detail;
                return;
            }
            win.message = qsTr("Pronto.");
            messageTimer.restart();
        }
    }

    Timer {
        id: messageTimer

        interval: 4000
        onTriggered: win.message = ""
    }
}
