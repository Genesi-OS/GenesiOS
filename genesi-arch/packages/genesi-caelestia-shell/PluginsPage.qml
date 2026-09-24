// GENESI — the Nexus "Plugins" page.
//
// Upstream registers "Plugins -- Manage plugins" under System and points it
// at PlaceholderComp, the "page under construction" screen. Genesi has
// plugins now, so this is the page: every plugin, a switch for each, and the
// one or two things worth doing with it from here.
//
// ── One writer ────────────────────────────────────────────────────────────
//
// A switch here does not write the plugin's file itself. It asks the store
// -- `genesi-store apply plugin-<id>` / `revert` -- because the store keeps
// its own record of what is applied, and a plugin switched on behind its
// back is a card the store shows as off while it is on. Only when the store
// is not installed, or never applied that card (it was switched on some
// other way), does this fall back to writing or deleting the file directly,
// which is all the store would have done.
//
// The state shown is GenesiPluginSwitch's -- the file, read back -- not what
// was last clicked. Between the click and the next read (at most three
// seconds) the switch holds the position it was put in, so it does not
// flick back and forth.
//
// Written in caelestia's own design language (PageBase, SectionHeader,
// ToggleRow, InfoRow), like the Updates, Display and Mouse pages.
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

    // id, the store card, and what the page says about it. The ids are the
    // ones the plugins ask GenesiPluginSwitch about; ci/plugins-test.py
    // checks the two agree.
    readonly property var plugins: [
        {
            id: "game-center",
            name: qsTr("Game Center"),
            icon: "sports_esports",
            blurb: qsTr("Quick games from the bottom-left corner of the screen")
        },
        {
            id: "leaf",
            name: qsTr("Leaf"),
            icon: "eco",
            blurb: qsTr("A desktop pet that shows how your machine is doing")
        },
        {
            id: "live-weather",
            name: qsTr("Live weather"),
            icon: "rainy",
            blurb: qsTr("When it rains outside, it rains on your wallpaper")
        }
    ]

    readonly property var switches: ({
        "game-center": gameCenter,
        "leaf": leaf,
        "live-weather": weather
    })

    // The leaf's XP from its own file; -1 until it has one.
    property real leafXp: -1

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

    title: qsTr("Plugins")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Not drawn. Inside the layout because PageBase's default property
        // is ONE Item -- a Timer or a FileView handed to it directly is a
        // load error for the whole page. UpdatesPage keeps its Processes
        // here for the same reason.
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

        // The leaf's age, to show beside its switch.
        Genesi.GenesiPetMind {
            id: mind
        }

        FileView {
            id: petFile

            path: `${Paths.state}/genesi-pet.json`
            printErrors: false
            onLoaded: {
                try {
                    root.leafXp = JSON.parse(text()).xp ?? 0;
                } catch (e) {}
            }
        }

        InfoRow {
            first: true
            last: true
            label: qsTr("Parts of the desktop that stay off until you want them")
            subtext: qsTr("They are on the Plugins shelf of Genesi Store too -- switching one here is the same switch.")
        }

        IconTextButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.small
            icon: "storefront"
            text: qsTr("Open Genesi Store")
            type: TextButton.Tonal
            onClicked: Quickshell.execDetached(["genesi-store"])
        }

        Repeater {
            model: root.plugins

            ColumnLayout {
                id: block

                required property var modelData
                required property int index

                readonly property var sw: root.switches[block.modelData.id]
                readonly property bool on: root.isOn(block.modelData.id, block.sw?.active ?? false)

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: block.index === 0
                    text: block.modelData.name
                }

                ToggleRow {
                    Layout.fillWidth: true
                    first: true
                    last: !block.on
                    text: block.modelData.blurb
                    subtext: block.on ? qsTr("On") : qsTr("Off")
                    checked: block.on
                    onToggled: root.turn(block.modelData.id, checked)
                }

                // ── What there is to do with each, once it is on ────────────
                InfoRow {
                    Layout.fillWidth: true
                    visible: block.on && block.modelData.id === "game-center"
                    last: true
                    label: qsTr("Throw the pointer into the bottom-left corner")
                    subtext: qsTr("or: caelestia shell gameCenter toggle")
                }

                InfoRow {
                    Layout.fillWidth: true
                    visible: block.on && block.modelData.id === "leaf"
                    last: true
                    label: root.leafXp < 0 ? qsTr("Just sprouted")
                        : qsTr("%1 · level %2").arg(mind.title(mind.levelFor(root.leafXp))).arg(mind.levelFor(root.leafXp))
                    subtext: root.leafXp < 0 ? qsTr("Click it any time to see how it is doing")
                        : qsTr("%1 of %2 XP to the next level").arg(Math.floor(root.leafXp)).arg(mind.xpFor(mind.levelFor(root.leafXp) + 1))
                    Component.onCompleted: petFile.reload()
                }

                InfoRow {
                    Layout.fillWidth: true
                    visible: block.on && block.modelData.id === "live-weather"
                    last: true
                    label: qsTr("Now: %1").arg(Weather.description)
                    subtext: qsTr("Nothing is drawn on a clear or cloudy day")
                    value: Weather.temp
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    visible: block.on && block.modelData.id === "live-weather"
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [
                            { kind: "rain", icon: "rainy", text: qsTr("Rain") },
                            { kind: "storm", icon: "thunderstorm", text: qsTr("Storm") },
                            { kind: "snow", icon: "weather_snowy", text: qsTr("Snow") },
                            { kind: "fog", icon: "foggy", text: qsTr("Fog") }
                        ]

                        IconTextButton {
                            required property var modelData

                            icon: modelData.icon
                            text: qsTr("Preview %1").arg(modelData.text.toLowerCase())
                            type: TextButton.Tonal
                            onClicked: Quickshell.execDetached(["caelestia", "shell", "liveWeather", "preview", modelData.kind])
                        }
                    }
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: Tokens.spacing.small
                    visible: block.on && block.modelData.id === "game-center"
                    icon: "sports_esports"
                    text: qsTr("Open it now")
                    type: TextButton.Tonal
                    onClicked: Quickshell.execDetached(["caelestia", "shell", "gameCenter", "show"])
                }
            }
        }
    }
}
