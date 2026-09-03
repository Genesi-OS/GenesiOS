//
// DisplayPage.qml — the Nexus "Display" page.
//
// Upstream REGISTERS this one only as a comment: PageRegistry has the entry
// commented out with a `// TODO` above it. So unlike Updates, the override has
// to enable the menu item as well as supply the page — which is why it waited
// until the CLI underneath had run on real hardware, and until the two-monitor
// bugs that hardware exposed were fixed.
//
// ── Written in caelestia's design language on purpose ────────────────────────
//
// PageBase / SliderRow / SelectRow / InfoRow / SectionHeader with Tokens and
// Colours — not one Genesi component. Same reasoning as UpdatesPage.qml: the
// colours here retint live from the wallpaper and our fixed emerald would
// fight them.
//
// ── Why everything goes through genesi-display ───────────────────────────────
//
// The compositor takes a WHOLE monitor line, so changing a scale means
// rewriting resolution, refresh rate and position too — and getting the
// position wrong moves someone's second screen. It also has to re-apply every
// other monitor, because the one that was not told anything keeps rendering
// its old contents, and re-pack them, because scaling changes a monitor's
// logical width and the neighbour then overlaps or drifts.
//
// None of that belongs in a view. It lives in genesi-display, where the
// launcher entries, the keybinds and a terminal all get the same behaviour.
//
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property var monitors: []
    property bool loaded: false
    property string busy: ""

    // index 0..3 = 0°, 90°, 180°, 270° — the order onSelected reads back.
    readonly property list<MenuItem> rotationItems: [
        MenuItem {
            text: qsTr("Normal")
            icon: "stay_current_landscape"
        },
        MenuItem {
            text: "90°"
            icon: "screen_rotation"
        },
        MenuItem {
            text: "180°"
            icon: "screen_rotation"
        },
        MenuItem {
            text: "270°"
            icon: "screen_rotation"
        }
    ]

    title: qsTr("Display")

    function refresh(): void {
        readProc.running = true;
    }

    function run(args: list<string>): void {
        root.busy = args.join(" ");
        actProc.command = args;
        actProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // `genesi-display list` prints exactly what the compositor reports, as
        // JSON. Reading the compositor here as well would be a second source
        // of truth for the same fact, and the two would drift.
        Process {
            id: readProc

            running: true
            command: ["genesi-display", "list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let mons = [];
                    try {
                        mons = JSON.parse(text);
                    } catch (e) {
                        mons = [];
                    }
                    root.monitors = mons;
                    root.loaded = true;
                }
            }
        }

        Process {
            id: actProc

            // argv, never a shell string. Every element is either a fixed word
            // or a monitor name that came from the compositor — nothing a user
            // typed reaches this.
            onExited: {
                root.busy = "";
                root.refresh();
            }
        }

        Repeater {
            model: root.monitors

            ColumnLayout {
                id: monBlock

                required property var modelData
                required property int index

                readonly property var mon: monBlock.modelData
                // Hyprland's transform: 0..3 are the plain rotations, 4..7 the
                // flipped ones. Only the plain four are offered — a flipped
                // screen is a thing people set up deliberately with a tool
                // that shows them a preview, not from a dropdown.
                readonly property int rotIndex: monBlock.mon.transform < 4 ? monBlock.mon.transform : 0

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: monBlock.mon.name + (monBlock.mon.focused ? qsTr("  ·  in use") : "")
                }

                InfoRow {
                    Layout.fillWidth: true
                    first: true
                    label: qsTr("Resolution")
                    subtext: qsTr("Position %1, %2").arg(monBlock.mon.x).arg(monBlock.mon.y)
                    value: `${monBlock.mon.width}×${monBlock.mon.height}@${Math.round(monBlock.mon.refresh)}Hz`
                }

                SliderRow {
                    Layout.fillWidth: true
                    icon: "fit_screen"
                    label: qsTr("Scale")
                    enabled: root.busy === ""
                    // 1 .. 2 mapped onto the slider's 0 .. 1. Hyprland refuses
                    // a scale that does not divide the resolution into whole
                    // pixels, so the value is snapped to the quarter steps that
                    // do rather than letting the slider produce a rejection.
                    value: (monBlock.mon.scale - 1)
                    valueLabel: Math.round(monBlock.mon.scale * 100) + "%"
                    onMoved: v => {
                        const s = 1 + Math.round(v * 4) / 4;
                        if (Math.abs(s - monBlock.mon.scale) < 0.01)
                            return;
                        root.run(["genesi-display", "scale", monBlock.mon.name, s.toFixed(2)]);
                    }
                }

                SelectRow {
                    Layout.fillWidth: true
                    label: qsTr("Rotation")
                    menuItems: root.rotationItems
                    active: root.rotationItems[monBlock.rotIndex]
                    onSelected: item => {
                        const deg = root.rotationItems.indexOf(item) * 90;
                        root.run(["genesi-display", "rotate", monBlock.mon.name, String(deg)]);
                    }
                }

                // "Primary" means different things per session, and the CLI
                // does the right one for each: on X11 the real xrandr flag, on
                // Hyprland the default workspace binding. The page does not
                // need to know which — it just asks.
                // An action, not a toggle. hyprctl reports `focused` -- where
                // the pointer is right now -- and nothing at all about which
                // screen is primary, because Hyprland has no such flag. A
                // switch drawn from `focused` would light up whichever screen
                // the mouse happened to be on, which is a confident lie. A
                // button says what it does and claims nothing about state.
                ConnectedRect {
                    Layout.fillWidth: true
                    last: true
                    implicitHeight: primaryRow.implicitHeight + Tokens.padding.large * 2

                    RowLayout {
                        id: primaryRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.largeIncreased
                        anchors.rightMargin: Tokens.padding.largeIncreased
                        spacing: Tokens.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: qsTr("Main screen")
                                font: Tokens.font.body.large
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Where the desktop starts and full-screen apps open")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.medium
                            }
                        }

                        IconTextButton {
                            icon: "star"
                            text: qsTr("Set")
                            enabled: root.busy === ""
                            type: TextButton.Filled
                            onClicked: root.run(["genesi-display", "primary", monBlock.mon.name])
                        }
                    }
                }
            }
        }

        SectionHeader {
            visible: root.monitors.length > 1
            text: qsTr("Arrangement")
        }

        // Positioning is stated in words rather than dragged, because a drag
        // target needs a scaled preview of every screen and this page would
        // then be a layout editor. The two orders people actually want are
        // these, and both stay correct when a screen is scaled or rotated
        // because the CLI computes from logical size.
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.monitors.length === 2
            first: true
            last: true
            implicitHeight: arrangeCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: arrangeCol

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Which screen is on the left")
                    font: Tokens.font.body.large
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.monitors

                        IconTextButton {
                            required property var modelData
                            required property int index

                            icon: "swap_horiz"
                            text: modelData.name
                            enabled: root.busy === ""
                            type: TextButton.Filled
                            onClicked: {
                                const other = root.monitors[index === 0 ? 1 : 0];
                                root.run(["genesi-display", "position", modelData.name, "left-of", other.name]);
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("More than two screens, or stacked one above another? `genesi-display position` takes above and below too.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }

        SectionHeader {
            text: qsTr("Reset")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: resetCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: resetCol

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Undo every scale, rotation and position set from here. Anything you wrote in hyprland.conf yourself is untouched.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignLeft
                    icon: "settings_backup_restore"
                    text: qsTr("Reset displays")
                    enabled: root.busy === ""
                    type: TextButton.Filled
                    onClicked: root.run(["genesi-display", "reset"])
                }
            }
        }
    }
}
