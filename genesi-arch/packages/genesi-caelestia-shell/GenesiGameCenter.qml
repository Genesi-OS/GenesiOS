// GENESI — the Game Center: quick games in a drawer that opens from the
// bottom-left corner of the screen.
//
// ── Why that corner ───────────────────────────────────────────────────────
//
// Every edge already means something. The top opens caelestia's dashboard,
// the bottom its launcher, the right its session menu and the utilities in
// that bottom-right corner, and the left is either caelestia's rail or,
// with the Genesi bar on, the quick settings. The bottom-left corner is the
// one place a pointer can be thrown to that nothing answers yet. A corner is
// also the easiest target on a screen: the pointer stops there by itself,
// so the hot spot can be six pixels and still never be missed.
//
// The side panel's strip on the left edge stops short of that corner, so
// the two do not both open when you throw the pointer down the edge.
//
// ── Not over a fullscreen window ──────────────────────────────────────────
//
// The corner sits on the overlay layer so caelestia's own drawers window
// cannot swallow it, which also puts it above a fullscreen game. Somebody
// flicking the mouse in a real game does not want a drawer of small ones.
// So the corner disappears whenever the screen has a fullscreen window --
// the same test caelestia's ContentWindow uses to fold its border away.
//
// ── Where the records live ────────────────────────────────────────────────
//
// `genesi-games.json` in caelestia's state directory: best scores, how many
// times each game was played, and whether the corner is on. One small file
// this shell alone writes. Not shell.json, whose keys are a C++ schema
// caelestia validates, and which is written by genesi-center-set -- a corner
// switch inside the drawer writing there would be a second writer.
//
// ── A plugin ──────────────────────────────────────────────────────────────
//
// Off until it is switched on from the Plugins shelf of Genesi Store (see
// GenesiPluginSwitch). Off means nothing at all: no corner, no drawer, and
// the command below does nothing -- a hot corner nobody asked for is a hot
// corner people only ever meet by accident.
//
// ── Also from anywhere ────────────────────────────────────────────────────
//
//     caelestia shell gameCenter toggle
//
// which is what a keybind or the launcher calls.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils

Scope {
    id: root

    readonly property bool enabled: gate.active

    property bool shown: false
    // An open game, or an open by name, stays until dismissed. A drawer the
    // corner opened closes when the pointer leaves it -- until a game starts.
    property bool pinned: false
    property string openOn: ""

    property bool corner: true
    property var best: ({})
    property var plays: ({})
    property bool loaded: false

    // Switched off from the store while open: put it away.
    onEnabledChanged: if (!root.enabled)
        root.dismiss()

    function showOn(screenName: string, pin: bool): void {
        if (!root.enabled)
            return;
        root.openOn = screenName;
        root.pinned = pin;
        root.shown = true;
    }

    function dismiss(): void {
        root.shown = false;
        root.pinned = false;
    }

    function save(): void {
        if (!root.loaded)
            return;
        store.setText(JSON.stringify({
            corner: root.corner,
            best: root.best,
            plays: root.plays
        }, null, 2) + "\n");
    }

    function record(id: string, score: int, lowerIsBetter: bool): void {
        const plays = Object.assign({}, root.plays);
        plays[id] = (plays[id] || 0) + 1;
        root.plays = plays;
        if (score >= 0 && (score > 0 || lowerIsBetter)) {
            const old = root.best[id];
            if (old === undefined || (lowerIsBetter ? score < old : score > old)) {
                const best = Object.assign({}, root.best);
                best[id] = score;
                root.best = best;
            }
        }
        root.save();
    }

    GenesiPluginSwitch {
        id: gate

        plugin: "game-center"
    }

    FileView {
        id: store

        path: `${Paths.state}/genesi-games.json`
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.corner = data.corner !== false;
                root.best = data.best ?? {};
                root.plays = data.plays ?? {};
            } catch (e) {
                // A file somebody broke by hand is a file we start over,
                // not a Game Center that never opens.
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "gameCenter"

        function toggle(): void {
            if (root.shown)
                root.dismiss();
            else
                root.showOn(Hypr.focusedMonitor?.name ?? "", true);
        }

        function show(): void {
            root.showOn(Hypr.focusedMonitor?.name ?? "", true);
        }

        function hide(): void {
            root.dismiss();
        }

        // From the Plugins page. A string, not a bool: it arrives from a
        // command line either way, and "false" as a bool is true.
        function corner(on: string): void {
            root.corner = on === "true";
            root.save();
        }
    }

    Variants {
        model: Screens.screens

        Scope {
            id: scope

            required property ShellScreen modelData

            readonly property var monitor: Hypr.monitorFor(scope.modelData)
            readonly property bool fullscreen: scope.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

            // ── The corner ──────────────────────────────────────────────────
            StyledWindow {
                screen: scope.modelData
                name: "genesi-games-corner"
                visible: root.enabled && root.corner && !scope.fullscreen && !root.shown

                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                color: "transparent"

                anchors.left: true
                anchors.bottom: true
                implicitWidth: 6
                implicitHeight: 6

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: if (containsMouse)
                        root.showOn(scope.modelData.name, false)
                }
            }

            // ── The drawer ──────────────────────────────────────────────────
            StyledWindow {
                id: win

                readonly property bool mine: root.shown && root.openOn === scope.modelData.name
                readonly property var tok: contentItem.Tokens
                readonly property real barStrip: contentItem.Config.topbar.enabled
                    ? contentItem.Config.topbar.height + contentItem.Config.topbar.gap * 2 : 0
                readonly property bool barAtBottom: contentItem.Config.topbar.position === "bottom"

                screen: scope.modelData
                name: "genesi-games"
                visible: win.mine || card.opacity > 0

                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                // Exclusive while a game is being played: the arrows belong to
                // the game and not to whatever window was focused before. A
                // drawer somebody only hovered past takes nothing.
                WlrLayershell.keyboardFocus: !win.mine ? WlrKeyboardFocus.None
                    : root.pinned ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
                color: "transparent"

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                // Open, the whole window takes input -- a click anywhere off
                // the card is how it is put away. Closing, only the card does,
                // and it is invisible soon after: a fullscreen transparent
                // window that ate clicks would be the whole desktop gone dead.
                //
                // Geometry, not `item:`, for the reason GenesiDock gives: this
                // Quickshell's Region names no item, and a property that does
                // not exist fails the whole file.
                mask: Region {
                    x: win.mine ? 0 : card.x
                    y: win.mine ? 0 : card.y
                    width: win.mine ? win.width : card.width
                    height: win.mine ? win.height : card.height
                }

                MouseArea {
                    id: backdrop

                    anchors.fill: parent
                    onClicked: root.dismiss()
                }

                Rectangle {
                    id: card

                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: win.tok.padding.large
                    anchors.bottomMargin: (win.barAtBottom ? win.barStrip : 0) + win.tok.padding.large

                    width: Math.min(460, parent.width - 2 * win.tok.padding.large)
                    height: Math.min(640, parent.height - win.barStrip - 2 * win.tok.padding.large)
                    radius: win.tok.rounding.large
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                    // Grown out of the corner it was called from.
                    transformOrigin: Item.BottomLeft
                    opacity: win.mine ? 1 : 0
                    scale: win.mine ? 1 : 0.85

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                    Behavior on scale {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    // Eats clicks, so the backdrop's "click outside to close"
                    // stays outside.
                    MouseArea {
                        anchors.fill: parent
                    }

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered)
                                leave.stop();
                            else if (win.mine && !root.pinned)
                                leave.restart();
                        }
                    }

                    // Not immediate: a pointer that overshoots by a pixel on
                    // its way in should not shut the drawer it just opened.
                    Timer {
                        id: leave

                        interval: 450
                        onTriggered: if (!root.pinned)
                            root.dismiss()
                    }

                    GenesiGames {
                        id: games

                        anchors.fill: parent
                        anchors.margins: win.tok.padding.large + 4

                        pal: Colours.palette
                        sans: win.tok.font.body.small.family
                        mono: win.tok.font.mono.small.family
                        icons: win.tok.font.icon.small.family
                        shown: win.mine
                        best: root.best
                        plays: root.plays
                        corner: root.corner

                        focus: win.mine

                        onCurrentChanged: if (games.current !== "")
                            root.pinned = true
                        onPlayed: (id, score, low) => root.record(id, score, low)
                        onCloseRequested: root.dismiss()
                        onCornerToggled: on => {
                            root.corner = on;
                            root.save();
                        }
                    }
                }
            }
        }
    }
}
