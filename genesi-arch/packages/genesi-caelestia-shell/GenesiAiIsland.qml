// GENESI — the AI island: the Quick Chat, alive at the top of the screen.
//
// A plugin, off until the Plugins shelf (or Nexus -> Plugins) switches it on.
// It shows what Genesi AI is doing -- thinking, each step the agent runs, a
// command waiting for permission, the answer when it is done -- with the leaf
// as its face, and takes files dropped on it. GenesiAiIslandCard draws all of
// that; this file is the window, the data and the commands.
//
// ── Where the data comes from ─────────────────────────────────────────────
//
// The Quick Chat (genesi-ai-mode) writes $XDG_RUNTIME_DIR/genesi-ai-island.json
// every time its state changes, and deletes it when it quits. This only
// READS it. Answers go back the other way as commands to the Quick Chat --
//
//     genesi-ai-quick --approve ID | --deny ID | --stop | --toggle
//     genesi-ai-quick --attach PATH [--prompt TEXT]
//
// -- which reach the running chat over its socket, so the island never needs
// a protocol of its own and the chat stays the one place a decision is made.
//
// ── Living with caelestia's top ───────────────────────────────────────────
//
// caelestia opens its dashboard from the top edge, in the middle -- exactly
// where this island sits. Two rules keep both usable:
//
//   * the island's input region starts a few pixels BELOW the top edge, so
//     the pointer at the very top still reaches caelestia's hover strip;
//   * when the dashboard is open, the island slides up out of the way. The
//     dashboard is the thing the person just asked for; it goes on top.
//
// With Genesi's top bar on, the island hangs under the bar instead of from
// the edge of the screen (GenesiEdges.top says how tall the bar is).
//
// ── Modes ─────────────────────────────────────────────────────────────────
//
//     caelestia shell aiIsland set mode always      the pill is always there
//     caelestia shell aiIsland set mode quickchat   only while the chat is open
//                                                   or the AI is working
//
// Saved in ${Paths.state}/genesi-ai-island.json, which this window alone writes.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.launcher as Launcher

Scope {
    id: root

    signal asked(string key, string value)

    IpcHandler {
        target: "aiIsland"

        function set(key: string, value: string): void {
            root.asked(key, value);
        }
    }

    GenesiPluginSwitch {
        id: gate

        plugin: "ai-island"
    }

    LazyLoader {
        active: gate.active && Screens.screens.length > 0

        StyledWindow {
            id: win

            property string mode: "always"
            property var st: ({})
            property bool live: false
            readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || `/tmp/genesi-ai-${Quickshell.env("UID")}`

            // Whichever screen has focus: the island is where you are looking.
            readonly property var home: Screens.screens.find(s => s.name === (Hypr.focusedMonitor?.name ?? "")) ?? Screens.screens[0]
            screen: win.home
            name: "genesi-ai-island"

            readonly property var monitor: Hypr.monitorFor(win.screen)
            readonly property bool fullscreen: win.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
            readonly property bool dashboardOpen: Visibilities.getForActive()?.dashboard ?? false

            // Genesi's top bar on this screen, at the top: the island hangs
            // from its centre pill, in its colour, and the pill itself is the
            // resting state -- its chip says what the AI is doing.
            readonly property var bar: Launcher.GenesiTopBarState.centres[win.screen?.name ?? ""] ?? null
            readonly property bool hangsFromBar: !!(win.bar && win.bar.shown && win.bar.atTop)

            // Shown at all: always, or only around the chat. Under the bar the
            // card shows only when there is something to show.
            readonly property bool wanted: win.hangsFromBar ? card.expanded
                : (win.mode === "always" || card.expanded || (win.live && (win.st.open ?? false)))
            readonly property bool away: win.dashboardOpen || !win.wanted

            readonly property real top: win.hangsFromBar ? win.bar.bottom + 8 : Launcher.GenesiEdges.top
            readonly property bool attached: !win.hangsFromBar && win.top < 1
            // The strip along the very top the island leaves to caelestia.
            readonly property int passStrip: win.attached ? 6 : 0

            visible: !win.fullscreen

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors.left: true
            anchors.right: true
            anchors.top: true
            implicitHeight: 260

            mask: Region {
                x: card.x
                y: win.away ? 0 : card.y + win.passStrip
                width: win.away ? 0 : card.width
                height: win.away ? 0 : Math.max(0, card.height - win.passStrip)
            }

            GenesiAiIslandCard {
                id: card

                x: Math.round(win.hangsFromBar ? Math.min(Math.max(8, win.bar.x + win.bar.w / 2 - width / 2), win.width - width - 8)
                                        : (win.width - width) / 2)
                y: win.away ? -height - 12 : win.top
                width: implicitWidth
                height: implicitHeight
                opacity: win.away ? 0 : 1
                st: win.st
                live: win.live
                attached: win.attached
                pal: Colours.palette
                fill: win.hangsFromBar ? win.bar.fill : Qt.alpha(Colours.palette.m3surfaceContainer, 0.96)

                Behavior on y {
                    NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 220 }
                }

                onOpenChat: Quickshell.execDetached(["genesi-ai-quick", "--toggle"])
                onApprove: id => Quickshell.execDetached(["genesi-ai-quick", "--approve", id])
                onDeny: id => Quickshell.execDetached(["genesi-ai-quick", "--deny", id])
                onStopWork: Quickshell.execDetached(["genesi-ai-quick", "--stop"])
                onAttach: (path, request) => Quickshell.execDetached(request
                    ? ["genesi-ai-quick", "--attach", path, "--prompt", request]
                    : ["genesi-ai-quick", "--attach", path])
            }

            // Tell the bar what to put in its chip, and listen for its click.
            Binding {
                target: Launcher.GenesiTopBarState
                property: "ai"
                value: ({ phase: card.expanded ? card.phase : "idle", label: card.shortLabel })
            }
            Binding {
                target: Launcher.GenesiTopBarState
                property: "aiOn"
                value: true
            }
            Connections {
                target: Launcher.GenesiTopBarState

                function onAiOpenRequested(): void {
                    if (win.screen?.name === (Hypr.focusedMonitor?.name ?? win.screen?.name))
                        Quickshell.execDetached(["genesi-ai-quick", "--toggle"]);
                }
            }

            Connections {
                target: root

                function onAsked(key: string, value: string): void {
                    if (key === "mode" && (value === "always" || value === "quickchat")) {
                        win.mode = value;
                        prefs.setText(JSON.stringify({ mode: win.mode }) + "\n");
                    }
                }
            }

            // ── Its one setting ─────────────────────────────────────────────
            FileView {
                id: prefs

                path: `${Paths.state}/genesi-ai-island.json`
                printErrors: false
                onLoaded: {
                    try {
                        const m = JSON.parse(text()).mode;
                        if (m === "always" || m === "quickchat")
                            win.mode = m;
                    } catch (e) {}
                }
            }

            // ── What the Quick Chat is doing ────────────────────────────────
            FileView {
                id: chat

                path: `${win.runtime}/genesi-ai-island.json`
                printErrors: false
                watchChanges: true
                onFileChanged: reload()
                onLoaded: {
                    try {
                        win.st = JSON.parse(text());
                        alive.reload();
                    } catch (e) {}
                }
                onLoadFailed: {
                    win.live = false;
                    win.st = {};
                }
            }

            // A chat that crashed leaves its file behind. Its process is the
            // proof it is still there.
            FileView {
                id: alive

                path: win.st.pid ? `/proc/${win.st.pid}/comm` : ""
                printErrors: false
                onLoaded: win.live = true
                onLoadFailed: win.live = false
            }

            Timer {
                // The watch catches most writes; this catches the rest (a file
                // created after the watch was set, a rename the watch missed),
                // faster while something is happening.
                interval: card.expanded ? 400 : 1500
                repeat: true
                running: true
                onTriggered: chat.reload()
            }
        }
    }
}
