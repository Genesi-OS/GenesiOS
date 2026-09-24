// GENESI — the Nexus "Plugins" page.
//
// Upstream registers "Plugins -- Manage plugins" under System and points it
// at PlaceholderComp, the "page under construction" screen. This is the
// page: every Genesi plugin as a card -- its picture, a switch, and, once it
// is on, everything there is to set about it.
//
// ── One writer per thing ──────────────────────────────────────────────────
//
// A switch here does not write the plugin's file itself. It asks the store
// -- `genesi-store apply plugin-<id>` / `revert` -- because the store keeps
// its own record of what is applied, and a plugin switched on behind its
// back is a card the store shows as off while it is on. Only when the store
// is not installed, or never applied that card, does this fall back to
// writing or deleting the file directly, which is all the store would do.
//
// A plugin's own settings go through its IPC (`caelestia shell leaf set
// ...`, `caelestia shell gameCenter corner ...`) and never into its files:
// the plugin is the one writer of its state, and this page only READS
// those files back to show what they say.
//
// ── The pictures ──────────────────────────────────────────────────────────
//
// The same ones the store's Plugins shelf shows, from where the store
// installs them. Without the store they are simply not there, and the card
// falls back to its colours and its icon rather than to a broken image.
//
// Written in caelestia's own design language (PageBase, SectionHeader,
// ToggleRow, SelectRow, SliderRow, InfoRow), like the Updates, Display and
// Mouse pages.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common
import qs.modules.background as Genesi

PageBase {
    id: root

    // The ids are the ones the plugins ask GenesiPluginSwitch about;
    // ci/plugins-test.py checks the page and the shell agree.
    readonly property var plugins: [
        {
            id: "game-center",
            name: qsTr("Game Center"),
            icon: "sports_esports",
            blurb: qsTr("Eight quick games in a drawer that opens from the bottom-left corner of the screen.")
        },
        {
            id: "leaf",
            name: qsTr("Leaf"),
            icon: "eco",
            blurb: qsTr("A little pet that is the state of your machine: it sweats when the CPU runs hot, sleeps when you step away and grows up with you.")
        },
        {
            id: "live-weather",
            name: qsTr("Live weather"),
            icon: "rainy",
            blurb: qsTr("When it rains outside, it rains on your wallpaper -- rain, snow, storms and fog, underneath your windows.")
        },
        {
            id: "vinyl",
            name: qsTr("Turntable"),
            icon: "album",
            blurb: qsTr("Whatever is playing, spinning on your desktop: the cover on the label, the arm following the track. Click to pause, scroll to skip.")
        },
        {
            id: "wrapped",
            name: qsTr("Retrospective"),
            icon: "auto_awesome",
            blurb: qsTr("Your week and your month on Genesi, told as a story: your apps, your hours, your rhythm, your records.")
        }
    ]

    readonly property var switches: ({
        "game-center": gameCenter,
        "leaf": leaf,
        "live-weather": weather,
        "vinyl": vinyl,
        "wrapped": wrapped
    })

    readonly property var gameNames: ({
        snake: qsTr("Snake"),
        "2048": "2048",
        flappy: qsTr("Flappy Leaf"),
        blocks: qsTr("Blocks"),
        breakout: qsTr("Breakout"),
        mines: qsTr("Minesweeper"),
        memory: qsTr("Memory"),
        simon: qsTr("Simon")
    })

    // What the plugins' own files say, read back.
    property var games: ({})
    property var pet: ({})
    property var deck: ({})
    property int daysCounted: -1

    readonly property int enabledCount: root.plugins.filter(p => root.isOn(p.id, root.switches[p.id]?.active ?? false)).length

    // id -> the position a switch was just put in, until the file agrees.
    property var pending: ({})

    function turn(id: string, on: bool): void {
        const p = Object.assign({}, root.pending);
        p[id] = on;
        root.pending = p;
        settle.restart();
        const file = `"\${XDG_CONFIG_HOME:-$HOME/.config}/genesi/plugins/${id}.json"`;
        Quickshell.execDetached(["sh", "-c", on
            ? `genesi-store apply plugin-${id} >/dev/null 2>&1 || { mkdir -p "\${XDG_CONFIG_HOME:-$HOME/.config}/genesi/plugins" && printf '{"enabled": true}\\n' > ${file}; }`
            : `genesi-store revert plugin-${id} >/dev/null 2>&1; rm -f ${file}`]);
    }

    function isOn(id: string, active: bool): bool {
        return root.pending[id] !== undefined ? root.pending[id] : active;
    }

    function leafSet(key: string, value: string): void {
        const p = Object.assign({}, root.pet);
        p[key] = value === "true" ? true : value === "false" ? false : (key === "scale" ? parseFloat(value) : value);
        root.pet = p;
        Quickshell.execDetached(["caelestia", "shell", "leaf", "set", key, value]);
    }

    title: qsTr("Plugins")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        // ── Not drawn ───────────────────────────────────────────────────────
        // Inside the layout because PageBase's default property is ONE Item:
        // a Timer or a FileView handed to it directly is a load error for the
        // whole page. UpdatesPage keeps its Processes here for the same reason.
        Timer {
            id: settle

            interval: 8000
            onTriggered: root.pending = ({})
        }

        Genesi.GenesiPluginSwitch {
            id: gameCenter

            plugin: "game-center"
        }

        Genesi.GenesiPluginSwitch {
            id: leaf

            plugin: "leaf"
        }

        Genesi.GenesiPluginSwitch {
            id: weather

            plugin: "live-weather"
        }

        Genesi.GenesiPluginSwitch {
            id: vinyl

            plugin: "vinyl"
        }

        Genesi.GenesiPluginSwitch {
            id: wrapped

            plugin: "wrapped"
        }

        FileView {
            id: deckFile

            path: `${Paths.state}/genesi-vinyl.json`
            printErrors: false
            onLoaded: {
                try {
                    if (!deckSend.running)
                        root.deck = JSON.parse(text());
                } catch (e) {}
            }
        }

        FileView {
            id: wrappedFile

            path: `${Paths.state}/genesi-wrapped.json`
            printErrors: false
            onLoaded: {
                try {
                    root.daysCounted = Object.keys(JSON.parse(text()).days ?? {}).length;
                } catch (e) {}
            }
        }

        Timer {
            id: deckSend

            property real value: 1

            interval: 250
            onTriggered: Quickshell.execDetached(["caelestia", "shell", "vinyl", "set", "scale", deckSend.value.toFixed(2)])
        }

        MenuItem {
            id: cornerTL

            text: qsTr("Top left")
            icon: "north_west"
        }
        MenuItem {
            id: cornerTR

            text: qsTr("Top right")
            icon: "north_east"
        }
        MenuItem {
            id: cornerBL

            text: qsTr("Bottom left")
            icon: "south_west"
        }
        MenuItem {
            id: cornerBR

            text: qsTr("Bottom right")
            icon: "south_east"
        }

        Genesi.GenesiPetMind {
            id: mind
        }

        FileView {
            id: gamesFile

            path: `${Paths.state}/genesi-games.json`
            printErrors: false
            onLoaded: {
                try {
                    root.games = JSON.parse(text());
                } catch (e) {}
            }
        }

        FileView {
            id: petFile

            path: `${Paths.state}/genesi-pet.json`
            printErrors: false
            onLoaded: {
                try {
                    // Not while the size slider is sending: a read of the
                    // file from before the change would yank it back.
                    const d = JSON.parse(text());
                    if (!scaleSend.running)
                        root.pet = d;
                } catch (e) {}
            }
        }

        Timer {
            // Re-read while the page is open, so a record set a minute ago or
            // a level gained is on the page without reopening it.
            interval: 3000
            repeat: true
            running: root.visible
            triggeredOnStart: true
            onTriggered: {
                gamesFile.reload();
                petFile.reload();
                deckFile.reload();
                wrappedFile.reload();
            }
        }

        Timer {
            id: scaleSend

            property real value: 1

            interval: 250
            onTriggered: root.leafSet("scale", scaleSend.value.toFixed(2))
        }

        Variants {
            id: screenItems

            model: Quickshell.screens

            MenuItem {
                required property ShellScreen modelData

                text: modelData.name
                icon: "monitor"
            }
        }

        MenuItem {
            id: followItem

            text: qsTr("Follow focus")
            icon: "ads_click"
        }

        // ── The header ──────────────────────────────────────────────────────
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                id: header

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "extension"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: qsTr("Genesi plugins")
                        font: Tokens.font.title.medium
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Parts of the desktop that stay off until you want them. %1 of %2 on.")
                            .arg(root.enabledCount).arg(root.plugins.length)
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                IconTextButton {
                    icon: "storefront"
                    text: qsTr("Store")
                    type: TextButton.Tonal
                    onClicked: Quickshell.execDetached(["genesi-store"])
                }
            }
        }

        // ── One card per plugin ─────────────────────────────────────────────
        Repeater {
            model: root.plugins

            StyledClippingRect {
                id: card

                required property var modelData
                required property int index

                readonly property string pid: card.modelData.id
                readonly property bool enabled_: root.isOn(card.pid, root.switches[card.pid]?.active ?? false)

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.large
                implicitHeight: hero.height + (card.enabled_ ? body.implicitHeight + Tokens.padding.large * 2 : 0)
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainerLow

                // The picture, with the name, the blurb and the switch over it.
                Item {
                    id: hero

                    width: card.width
                    height: Math.min(230, card.width * 0.36)

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Colours.palette.m3primaryContainer }
                            GradientStop { position: 1; color: Colours.palette.m3tertiaryContainer }
                        }

                        MaterialIcon {
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.padding.large * 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: picture.status !== Image.Ready
                            text: card.modelData.icon
                            color: Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.35)
                            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                        }
                    }

                    Image {
                        id: picture

                        anchors.fill: parent
                        source: `file:///usr/share/genesi-store/thumbs/plugin-${card.pid}.jpg`
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: card.enabled_ ? 1 : 0.55

                        Behavior on opacity {
                            Anim {}
                        }
                    }

                    // Dark at the bottom, so the words stay readable over any
                    // picture.
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.25; color: "transparent" }
                            GradientStop { position: 1; color: Qt.alpha("#000000", 0.78) }
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        StyledRect {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: Tokens.rounding.large
                            color: card.enabled_ ? Colours.palette.m3primary : Qt.alpha("#ffffff", 0.18)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: card.modelData.icon
                                color: card.enabled_ ? Colours.palette.m3onPrimary : "white"
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: card.modelData.name
                                color: "white"
                                font: Tokens.font.title.medium
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.blurb
                                color: Qt.alpha("#ffffff", 0.82)
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        StyledSwitch {
                            checked: card.enabled_
                            onToggled: root.turn(card.pid, checked)
                        }
                    }
                }

                // ── What there is to set, once it is on ─────────────────────
                ColumnLayout {
                    id: body

                    y: hero.height + Tokens.padding.large
                    x: Tokens.padding.large
                    width: card.width - Tokens.padding.large * 2
                    spacing: Tokens.spacing.extraSmall / 2
                    visible: card.enabled_

                    // Game Center ------------------------------------------
                    InfoRow {
                        Layout.fillWidth: true
                        visible: card.pid === "game-center"
                        first: true
                        label: qsTr("Throw the pointer into the bottom-left corner")
                        subtext: qsTr("or bind a key to: caelestia shell gameCenter toggle")
                        value: qsTr("%1 played").arg(Object.values(root.games.plays ?? {}).reduce((a, b) => a + b, 0))
                    }

                    ToggleRow {
                        Layout.fillWidth: true
                        visible: card.pid === "game-center"
                        text: qsTr("Open from the corner")
                        subtext: qsTr("Off: only the command opens it")
                        checked: root.games.corner !== false
                        onToggled: {
                            const g = Object.assign({}, root.games);
                            g.corner = checked;
                            root.games = g;
                            Quickshell.execDetached(["caelestia", "shell", "gameCenter", "corner", String(checked)]);
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        visible: card.pid === "game-center"
                        implicitHeight: records.implicitHeight + Tokens.padding.large * 2
                        topLeftRadius: Tokens.rounding.extraSmall
                        topRightRadius: Tokens.rounding.extraSmall
                        bottomLeftRadius: Tokens.rounding.extraLarge
                        bottomRightRadius: Tokens.rounding.extraLarge
                        color: Colours.tPalette.m3surfaceContainer

                        ColumnLayout {
                            id: records

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: qsTr("Your records")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.medium
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                Repeater {
                                    model: Object.keys(root.gameNames)

                                    StyledRect {
                                        id: rec

                                        required property string modelData
                                        readonly property var best: (root.games.best ?? {})[rec.modelData]

                                        implicitWidth: recText.implicitWidth + Tokens.padding.large * 2
                                        implicitHeight: recText.implicitHeight + Tokens.padding.small * 2
                                        radius: Tokens.rounding.full
                                        color: rec.best !== undefined ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                                        StyledText {
                                            id: recText

                                            anchors.centerIn: parent
                                            text: rec.best === undefined ? root.gameNames[rec.modelData]
                                                : rec.modelData === "mines" ? `${root.gameNames[rec.modelData]} · ${rec.best}s`
                                                : rec.modelData === "memory" ? qsTr("%1 · %2 moves").arg(root.gameNames[rec.modelData]).arg(rec.best)
                                                : `${root.gameNames[rec.modelData]} · ${Number(rec.best).toLocaleString(Qt.locale(), "f", 0)}`
                                            color: rec.best !== undefined ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3outline
                                        }
                                    }
                                }
                            }

                            IconTextButton {
                                Layout.alignment: Qt.AlignRight
                                icon: "sports_esports"
                                text: qsTr("Play now")
                                type: TextButton.Filled
                                onClicked: Quickshell.execDetached(["caelestia", "shell", "gameCenter", "show"])
                            }
                        }
                    }

                    // Leaf ---------------------------------------------------
                    StyledRect {
                        id: growthCard

                        readonly property real xp: root.pet.xp ?? 0
                        readonly property int level: mind.levelFor(growthCard.xp)
                        readonly property int floorXp: mind.xpFor(growthCard.level)
                        readonly property int nextXp: mind.xpFor(growthCard.level + 1)

                        Layout.fillWidth: true
                        visible: card.pid === "leaf"
                        implicitHeight: growth.implicitHeight + Tokens.padding.large * 2
                        topLeftRadius: Tokens.rounding.extraLarge
                        topRightRadius: Tokens.rounding.extraLarge
                        bottomLeftRadius: Tokens.rounding.extraSmall
                        bottomRightRadius: Tokens.rounding.extraSmall
                        color: Colours.tPalette.m3surfaceContainer

                        ColumnLayout {
                            id: growth

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.small

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("%1 · level %2").arg(mind.title(growthCard.level)).arg(growthCard.level)
                                    font: Tokens.font.title.small
                                }
                                StyledText {
                                    text: qsTr("%1 / %2 XP").arg(Math.floor(growthCard.xp)).arg(growthCard.nextXp)
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: Math.max(0, Math.min(1, (growthCard.xp - growthCard.floorXp) / Math.max(1, growthCard.nextXp - growthCard.floorXp)))
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("It grows with time together and with games in the Game Center: a dewdrop at level 3, a flower at 5, a golden edge at 8.")
                                color: Colours.palette.m3outline
                                font: Tokens.font.label.small
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    SelectRow {
                        Layout.fillWidth: true
                        visible: card.pid === "leaf"
                        label: qsTr("Screen")
                        subtext: qsTr("Where the leaf lives -- or right-click it for “Next screen”")
                        menuItems: [followItem, ...screenItems.instances]
                        active: root.pet.screen === "follow" ? followItem
                            : (screenItems.instances.find(i => i.text === root.pet.screen) ?? screenItems.instances[0] ?? null)
                        onSelected: item => root.leafSet("screen", item === followItem ? "follow" : item.text)
                    }

                    SliderRow {
                        Layout.fillWidth: true
                        visible: card.pid === "leaf"
                        icon: "open_in_full"
                        label: qsTr("Size")
                        // 0.6 to 1.8, shown on a 0 to 1 slider.
                        value: ((root.pet.scale ?? 1) - 0.6) / 1.2
                        valueLabel: Math.round((root.pet.scale ?? 1) * 100) + "%"
                        onMoved: v => {
                            const scale = 0.6 + v * 1.2;
                            const p = Object.assign({}, root.pet);
                            p.scale = scale;
                            root.pet = p;
                            scaleSend.value = scale;
                            scaleSend.restart();
                        }
                    }

                    ToggleRow {
                        Layout.fillWidth: true
                        visible: card.pid === "leaf"
                        text: qsTr("Wander along the edge")
                        subtext: qsTr("Off: it stays where you put it")
                        checked: root.pet.wander !== false
                        onToggled: root.leafSet("wander", String(checked))
                    }

                    ToggleRow {
                        Layout.fillWidth: true
                        visible: card.pid === "leaf"
                        last: true
                        text: qsTr("Speak up on its own")
                        subtext: qsTr("Off: it only talks when you click it")
                        checked: root.pet.chatty !== false
                        onToggled: root.leafSet("chatty", String(checked))
                    }

                    IconTextButton {
                        Layout.alignment: Qt.AlignRight
                        Layout.topMargin: Tokens.spacing.small
                        visible: card.pid === "leaf"
                        icon: "bedtime"
                        text: qsTr("Nap for an hour")
                        type: TextButton.Tonal
                        onClicked: root.leafSet("nap", "true")
                    }

                    // Live weather --------------------------------------------
                    InfoRow {
                        Layout.fillWidth: true
                        visible: card.pid === "live-weather"
                        first: true
                        last: true
                        label: qsTr("Now: %1").arg(Weather.description)
                        subtext: Weather.city ? qsTr("In %1 · nothing is drawn on a clear or cloudy day").arg(Weather.city)
                            : qsTr("Nothing is drawn on a clear or cloudy day")
                        value: Weather.temp
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacing.medium
                        visible: card.pid === "live-weather"
                        text: qsTr("See it now, for thirty seconds")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }

                    Flow {
                        Layout.fillWidth: true
                        visible: card.pid === "live-weather"
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: [
                                { kind: "drizzle", icon: "grain", text: qsTr("Drizzle") },
                                { kind: "rain", icon: "rainy", text: qsTr("Rain") },
                                { kind: "storm", icon: "thunderstorm", text: qsTr("Storm") },
                                { kind: "snow", icon: "weather_snowy", text: qsTr("Snow") },
                                { kind: "fog", icon: "foggy", text: qsTr("Fog") }
                            ]

                            IconTextButton {
                                required property var modelData

                                icon: modelData.icon
                                text: modelData.text
                                type: TextButton.Tonal
                                onClicked: Quickshell.execDetached(["caelestia", "shell", "liveWeather", "preview", modelData.kind])
                            }
                        }
                    }

                    // Turntable -----------------------------------------------
                    SelectRow {
                        Layout.fillWidth: true
                        visible: card.pid === "vinyl"
                        first: true
                        label: qsTr("Corner")
                        subtext: qsTr("Where it sits on the desktop")
                        menuItems: [cornerTL, cornerTR, cornerBL, cornerBR]
                        active: ({ "top-left": cornerTL, "top-right": cornerTR, "bottom-left": cornerBL })[root.deck.corner] ?? cornerBR
                        onSelected: item => {
                            const corner = item === cornerTL ? "top-left" : item === cornerTR ? "top-right" : item === cornerBL ? "bottom-left" : "bottom-right";
                            const d = Object.assign({}, root.deck);
                            d.corner = corner;
                            root.deck = d;
                            Quickshell.execDetached(["caelestia", "shell", "vinyl", "set", "corner", corner]);
                        }
                    }

                    SliderRow {
                        Layout.fillWidth: true
                        visible: card.pid === "vinyl"
                        icon: "open_in_full"
                        label: qsTr("Size")
                        // 0.6 to 1.6 on a 0 to 1 slider.
                        value: ((root.deck.scale ?? 1) - 0.6) / 1.0
                        valueLabel: Math.round((root.deck.scale ?? 1) * 100) + "%"
                        onMoved: v => {
                            const scale = 0.6 + v;
                            const d = Object.assign({}, root.deck);
                            d.scale = scale;
                            root.deck = d;
                            deckSend.value = scale;
                            deckSend.restart();
                        }
                    }

                    ToggleRow {
                        Layout.fillWidth: true
                        visible: card.pid === "vinyl"
                        last: true
                        text: qsTr("Hide it when nothing is playing")
                        subtext: qsTr("Off: an empty turntable waits on the desktop")
                        checked: root.deck.hideIdle !== false
                        onToggled: {
                            const d = Object.assign({}, root.deck);
                            d.hideIdle = checked;
                            root.deck = d;
                            Quickshell.execDetached(["caelestia", "shell", "vinyl", "set", "idle", checked ? "hide" : "show"]);
                        }
                    }

                    // Retrospective --------------------------------------------
                    InfoRow {
                        Layout.fillWidth: true
                        visible: card.pid === "wrapped"
                        first: true
                        last: true
                        label: root.daysCounted > 1 ? qsTr("%1 days counted so far").arg(root.daysCounted)
                            : root.daysCounted === 1 ? qsTr("Counting since today")
                            : qsTr("Counting starts now")
                        subtext: qsTr("Only which app is in front, never a window title -- kept on this machine, ten weeks at most.")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        visible: card.pid === "wrapped"
                        spacing: Tokens.spacing.small

                        Item {
                            Layout.fillWidth: true
                        }

                        IconTextButton {
                            icon: "calendar_month"
                            text: qsTr("Your month")
                            type: TextButton.Tonal
                            onClicked: Quickshell.execDetached(["caelestia", "shell", "wrapped", "show", "month"])
                        }

                        IconTextButton {
                            icon: "auto_awesome"
                            text: qsTr("Your week")
                            type: TextButton.Filled
                            onClicked: Quickshell.execDetached(["caelestia", "shell", "wrapped", "show", "week"])
                        }
                    }
                }
            }
        }
    }
}
