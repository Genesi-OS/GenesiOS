// GENESI — the bar across the top.
//
// caelestia's bar is a vertical rail down the left edge. This is the other
// shape: three islands along the top, the way most desktops have taught people
// to read a status bar.
//
// ── It does NOT replace caelestia. That was the bug ─────────────────────────
//
// The first version of this was a SECOND Quickshell process with its own
// shell.qml, and switching to it ran `pkill -f caelestia`. That does not
// disable a bar, it kills the shell: the launcher, every drawer, the
// notification daemon, the wallpaper, the theme bridge and the CLI all go with
// it. The desktop it left behind was broken in a way no setting could undo,
// and the package was withdrawn.
//
// So this is a WINDOW inside caelestia, exactly like the dock. Same process,
// same config, same colours, and nothing to kill. Turning it on hides the side
// rail through `disabled` on caelestia's own BarWrapper -- a property that
// already existed for excludedScreens -- which collapses its width to the
// border thickness AND drops its exclusive zone. Every drawer reflows because
// Panels.qml anchors itself to `bar.implicitWidth`, which is now zero.
//
// Turning it off puts the rail back. Nothing had to be restarted either way.
//
// ── Islands, not a slab ─────────────────────────────────────────────────────
//
// Three groups, each sized by its own contents, each on its own rounded
// surface. A single row with spacers cannot keep the centre centred when the
// sides are different widths -- the clock drifts as the window title changes,
// which is the tell of a bar built out of a Row. The centre is ANCHORED to the
// bar's centre and the sides are anchored to the edges, so the clock does not
// move when anything else does.
//
// `topbar.islands` off draws the three groups on one continuous surface
// instead, for people who want a bar rather than a tray of pills.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.services
// GenesiTopBarState -- the flag the bar's own settings panel watches. It sits
// beside the launcher's body, which is the module both halves import.
import qs.modules.launcher

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property var cfg: contentItem.Config.topbar
        readonly property var tok: contentItem.Tokens
        // `contentItem`, not a bare `Config`. Config and Tokens are ATTACHED
        // types, and on the window itself -- which is not an Item -- the
        // attachment has no screen and falls back to the global config with a
        // warning. Every caelestia window that reads config at this level goes
        // through contentItem; the ones that read it inside their content do
        // not have to. Getting this wrong is how the dock shipped invisible.
        readonly property bool atTop: win.cfg.position !== "bottom"

        screen: modelData
        name: "genesi-topbar"
        visible: win.cfg.enabled

        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"

        anchors.top: win.atTop
        anchors.bottom: !win.atTop
        anchors.left: true
        anchors.right: true

        implicitHeight: win.cfg.height + win.cfg.gap * 2

        // The whole strip reserves space, so a maximised window stops below the
        // bar instead of underneath it. This is the one place the top bar and
        // the dock differ on purpose: a dock is somewhere you point at, a bar
        // is somewhere you read, and a bar you have to move a window to read is
        // not doing its job.
        exclusiveZone: win.cfg.enabled ? win.cfg.height + win.cfg.gap : 0

        // Only the islands take input. Without this the strip swallows clicks
        // along the entire top edge of every window on the screen.
        mask: Region {
            x: left.x
            y: left.y
            width: left.width
            height: left.height

            Region {
                x: centre.x
                y: centre.y
                width: centre.width
                height: centre.height
            }
            Region {
                x: right.x
                y: right.y
                width: right.width
                height: right.height
            }
        }

        // ── One continuous surface, when islands are off ─────────────────────
        StyledRect {
            anchors.fill: parent
            anchors.margins: win.cfg.gap
            visible: !win.cfg.islands && win.cfg.background
            radius: win.cfg.radius
            color: Qt.alpha(Colours.palette.m3surfaceContainer,
                            Math.max(0, Math.min(100, win.cfg.backgroundOpacity)) / 100)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
        }

        // ── Left ─────────────────────────────────────────────────────
        Island {
            id: left

            anchors.left: parent.left
            anchors.leftMargin: win.cfg.gap * 2
            anchors.verticalCenter: parent.verticalCenter

            // The Genesi mark, and the launcher behind it. Same gesture as
            // caelestia's own OsIcon, because it is the same affordance in a
            // different place.
            BarIcon {
                visible: win.cfg.showLogo
                icon: "workspaces"
                accent: true
                onActivated: {
                    const v = Visibilities.getForActive();
                    if (v)
                        v.launcher = !v.launcher;
                }
            }

            // The button the sidebar needs, because a drawer you can only
            // reach by dragging from an edge is a drawer most people never
            // find. It opens caelestia's own dashboard rather than a second
            // panel of Genesi's: there is one place the calendar, the media
            // controls and the quick toggles live, and duplicating it would be
            // two of everything to keep in step.
            BarIcon {
                visible: win.cfg.showSidebarButton
                icon: "dock_to_right"
                onActivated: {
                    const v = Visibilities.getForActive();
                    if (v)
                        v.dashboard = !v.dashboard;
                }
            }

            Repeater {
                model: win.cfg.showWorkspaces ? (Hypr.workspaces?.values ?? []) : []

                StyledRect {
                    id: ws

                    required property var modelData

                    readonly property bool active: ws.modelData?.id === Hypr.activeWsId
                    readonly property bool occupied: (ws.modelData?.lastIpcObject?.windows ?? 0) > 0

                    anchors.verticalCenter: parent.verticalCenter
                    // The active one is a bar, the rest are dots. Shape rather
                    // than colour alone: which workspace you are on has to be
                    // legible at a glance and out of the corner of an eye, and
                    // a colour difference is neither on a busy wallpaper.
                    implicitWidth: ws.active ? win.cfg.height * 0.62 : win.cfg.height * 0.26
                    implicitHeight: win.cfg.height * 0.26
                    radius: Tokens.rounding.full
                    color: ws.active ? Colours.palette.m3primary
                                     : (ws.occupied ? Colours.palette.m3onSurfaceVariant
                                                    : Qt.alpha(Colours.palette.m3outline, 0.45))

                    Behavior on implicitWidth {
                        Anim {}
                    }
                    Behavior on color {
                        CAnim {}
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(
                            ["hyprctl", "dispatch", "workspace",
                             String(ws.modelData?.id ?? 1)])
                    }
                }
            }
        }

        // ── Centre ─────────────────────────────────────────────────
        //
        // ANCHORED to the centre of the bar, not placed between the other two.
        // Placed, it slides every time the window title changes length.
        Island {
            id: centre

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            clickable: true
            onActivated: {
                const v = Visibilities.getForActive();
                if (v)
                    v.dashboard = !v.dashboard;
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showActiveWindow && text !== ""
                text: Hypr.activeToplevel?.lastIpcObject?.title ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
                // A title is the one thing here with no natural width, so it is
                // the one thing that gets a cap. Without it a browser tab named
                // after an article pushes the clock off-centre.
                width: Math.min(implicitWidth, win.width * 0.22)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showClock
                text: Time.format("hh:mm")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showDate
                text: Time.format("ddd, MMM d")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
        }

        // ── Right ────────────────────────────────────────────────────
        Island {
            id: right

            anchors.right: parent.right
            anchors.rightMargin: win.cfg.gap * 2
            anchors.verticalCenter: parent.verticalCenter

            Reading {
                visible: win.cfg.showResources
                icon: "memory"
                label: `${Math.round(Cpu.percentage * 100)}%`
            }

            Reading {
                visible: win.cfg.showResources
                icon: "memory_alt"
                label: `${Math.round(Memory.percentage * 100)}%`
            }

            Reading {
                visible: win.cfg.showStatus
                icon: Network.active ? "wifi" : "wifi_off"
                label: ""
            }

            Reading {
                id: batteryReading

                readonly property var dev: UPower.displayDevice

                // A desktop has no battery, and a battery reading 100% for ever
                // is a reading nobody has ever looked at twice.
                visible: win.cfg.showStatus && (batteryReading.dev?.isLaptopBattery ?? false)
                icon: (batteryReading.dev?.state === UPowerDeviceState.Charging)
                      ? "battery_charging_full" : "battery_full"
                label: `${Math.round((batteryReading.dev?.percentage ?? 0) * 100)}%`
            }

            BarIcon {
                visible: win.cfg.showPower
                icon: "power_settings_new"
                onActivated: {
                    const v = Visibilities.getForActive();
                    if (v)
                        v.session = !v.session;
                }
            }

            // The bar's own settings, on the bar. Everything about how this
            // strip looks is in there rather than spread across a settings app
            // -- you change a bar while looking at it, or you change it twice.
            BarIcon {
                visible: win.cfg.showConfigButton
                icon: "tune"
                onActivated: GenesiTopBarState.toggle()
            }
        }

        // ── The surface a group sits on ──────────────────────────────────────
        //
        // The island IS the row. It was a rectangle wrapping an Item that
        // filled it, holding a Row centred in that -- so the island's width
        // came from its child's childrenRect, the child's width came from the
        // island, and the centred Row's position came from both. Qt called it
        // what it was: "Binding loop detected for property implicitWidth", six
        // times, one per island per screen.
        //
        // Sized off `row.implicitWidth`, which depends on nothing above it, and
        // the row sits at a fixed x rather than centred. Nothing in the chain
        // reads the island's own width any more.
        component Island: StyledRect {
            id: island

            default property alias content: row.data

            // A click on the whole island, for the groups that want one. The
            // MouseArea is declared HERE rather than passed in, because the
            // default alias sends every child into the row -- a MouseArea
            // there would be laid out as one more item in the row instead of
            // covering it.
            property bool clickable: false

            signal activated

            implicitWidth: row.implicitWidth + win.tok.padding.large * 2
            implicitHeight: win.cfg.height

            radius: win.cfg.radius
            // Only when the groups ARE islands. On one continuous surface the
            // pills would be three lighter rectangles drawn on top of a bar,
            // which reads as a rendering mistake rather than as a design.
            color: (win.cfg.islands && win.cfg.background)
                   ? Qt.alpha(Colours.palette.m3surfaceContainer,
                              Math.max(0, Math.min(100, win.cfg.backgroundOpacity)) / 100)
                   : "transparent"
            border.width: (win.cfg.islands && win.cfg.background) ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            MouseArea {
                anchors.fill: parent
                enabled: island.clickable
                cursorShape: Qt.PointingHandCursor
                onClicked: island.activated()
            }

            Row {
                id: row

                x: win.tok.padding.large
                anchors.verticalCenter: parent.verticalCenter
                spacing: win.tok.spacing.medium
            }
        }

        component BarIcon: Item {
            id: barIcon

            property string icon: ""
            property bool accent: false

            signal activated

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: win.cfg.height * 0.66
            implicitHeight: win.cfg.height * 0.66

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: hover.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                                           : "transparent"

                Behavior on color {
                    CAnim {}
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: barIcon.icon
                color: barIcon.accent ? Colours.palette.m3primary
                                      : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: barIcon.activated()
            }
        }

        // An icon and a number. Read through `reading`, never through `parent`:
        // a `parent` chain is a guess about a tree, and it stops being true the
        // first time anything here is wrapped in a Loader or a Row.
        component Reading: Row {
            id: reading

            property string icon: ""
            property string label: ""

            anchors.verticalCenter: parent.verticalCenter
            spacing: win.tok.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: reading.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: reading.label !== ""
                text: reading.label
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
            }
        }
    }
}
