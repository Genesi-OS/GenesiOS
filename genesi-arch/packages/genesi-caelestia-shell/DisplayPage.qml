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

        // ── Drag the screens to where they actually are ──────────────────────
        //
        // Two named orders ("this one on the left") stop being enough at three
        // screens, and never covered "a bit higher than the other" at all.
        //
        // Tiles are sized from LOGICAL extent, not resolution: 2560 at 1.25x
        // occupies 2048, and rotating swaps the axes. Drawing panels instead
        // would make the map disagree with the desktop it describes.
        //
        // The drop hands raw coordinates to `genesi-display place`, which owns
        // the snapping and the shift back to a 0,0 origin. Repeating those
        // rules here would let two copies drift.
        //
        // ── Why the geometry is boxed in twice ───────────────────────────────
        //
        // The first version drew the tiles enormous and outside the card. The
        // scale factor divides by the card's size, and a QML item's width and
        // height are 0 until the layout has run -- so the first evaluation
        // divided by nothing and produced a factor big enough to throw the
        // tiles off the page. It recovered on the next pass, but by then the
        // damage was visible.
        //
        // So the factor now refuses to compute until there is real geometry to
        // compute from, AND the tiles live in a clipped child with the drag
        // bounded to it. One of those fixes the cause; the other makes the
        // symptom unreachable whatever else goes wrong later.
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.monitors.length > 1
            first: true
            last: true
            implicitHeight: 300

            Item {
                id: canvas

                function logicalW(m: var): real {
                    return (m.transform === 1 || m.transform === 3 ? m.height : m.width) / m.scale;
                }

                function logicalH(m: var): real {
                    return (m.transform === 1 || m.transform === 3 ? m.width : m.height) / m.scale;
                }

                readonly property real minX: {
                    let v = 0;
                    for (let i = 0; i < root.monitors.length; i++)
                        v = i === 0 ? root.monitors[i].x : Math.min(v, root.monitors[i].x);
                    return v;
                }
                readonly property real minY: {
                    let v = 0;
                    for (let i = 0; i < root.monitors.length; i++)
                        v = i === 0 ? root.monitors[i].y : Math.min(v, root.monitors[i].y);
                    return v;
                }
                readonly property real spanW: {
                    let v = 0;
                    for (let i = 0; i < root.monitors.length; i++) {
                        const m = root.monitors[i];
                        v = Math.max(v, m.x + canvas.logicalW(m) - canvas.minX);
                    }
                    return v;
                }
                readonly property real spanH: {
                    let v = 0;
                    for (let i = 0; i < root.monitors.length; i++) {
                        const m = root.monitors[i];
                        v = Math.max(v, m.y + canvas.logicalH(m) - canvas.minY);
                    }
                    return v;
                }

                // Zero until every input is real. Producing a factor from a
                // width of 0 is what drew the tiles off the page; a factor of
                // 0 draws nothing for one frame instead, which nobody sees.
                //
                // Capped at 90% so the arrangement never touches the card's
                // edges -- a map that fills its frame edge to edge reads as
                // broken even when it is correct, and leaves nowhere to drop a
                // screen that belongs past the current bounds.
                readonly property real factor: (width > 0 && height > 0 && spanW > 0 && spanH > 0) ? Math.min(width / spanW, height / spanH) * 0.9 : 0

                // The drawn arrangement, centred in whatever space is left.
                readonly property real offX: (width - spanW * factor) / 2
                readonly property real offY: (height - spanH * factor) / 2

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                anchors.bottomMargin: Tokens.padding.largeIncreased * 2
                // Nothing may render outside the card, whatever the numbers do.
                clip: true

                Repeater {
                    model: canvas.factor > 0 ? root.monitors : []

                    StyledRect {
                        id: tile

                        required property var modelData
                        required property int index

                        readonly property bool held: dragArea.drag.active

                        x: canvas.offX + (tile.modelData.x - canvas.minX) * canvas.factor
                        y: canvas.offY + (tile.modelData.y - canvas.minY) * canvas.factor
                        implicitWidth: canvas.logicalW(tile.modelData) * canvas.factor
                        implicitHeight: canvas.logicalH(tile.modelData) * canvas.factor

                        radius: Tokens.rounding.small
                        color: tile.held || tile.modelData.focused ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
                        border.width: 2
                        border.color: tile.held ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                        z: tile.held ? 1 : 0

                        // While a tile is held the mouse drives x/y; the
                        // bindings above take over again on release, once the
                        // compositor has said where the screen really ended up.
                        Behavior on x {
                            enabled: !tile.held
                            CAnim {}
                        }

                        Behavior on y {
                            enabled: !tile.held
                            CAnim {}
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0
                            // A tile can be small on a three-screen desk; the
                            // number goes away before it starts overflowing.
                            visible: tile.height > 44

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.index + 1
                                color: tile.held || tile.modelData.focused ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                font: Tokens.font.headline.builders.large.width(110).build()
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: tile.height > 76 && tile.width > 90
                                text: tile.modelData.name
                                color: tile.held || tile.modelData.focused ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }

                        MouseArea {
                            id: dragArea

                            anchors.fill: parent
                            cursorShape: tile.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            enabled: root.busy === ""

                            drag.target: tile
                            drag.smoothed: false
                            // Bounded to the canvas, so a screen cannot be
                            // dragged out of the card no matter how hard you
                            // pull. The CLI still decides where it really goes.
                            drag.minimumX: 0
                            drag.maximumX: Math.max(0, canvas.width - tile.width)
                            drag.minimumY: 0
                            drag.maximumY: Math.max(0, canvas.height - tile.height)

                            onReleased: {
                                const mx = (tile.x - canvas.offX) / canvas.factor + canvas.minX;
                                const my = (tile.y - canvas.offY) / canvas.factor + canvas.minY;
                                root.run(["genesi-display", "place", tile.modelData.name, String(Math.round(mx)), String(Math.round(my))]);
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.padding.small
                text: qsTr("Drag a screen to where it sits on your desk")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
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
