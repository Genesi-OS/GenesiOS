// GENESI — the turntable: whatever is playing, spinning on the desktop.
//
// A plugin ("vinyl"): off until the Plugins shelf of Genesi Store or
// Nexus -> Plugins switches it on, and entirely gone when it is off.
//
// What is playing is caelestia's own Players.active -- the MPRIS player the
// dashboard shows -- so the turntable and the dashboard always agree. The
// record is the cover; click it to pause or play, scroll over it to skip.
//
// ── Above the windows, by default ─────────────────────────────────────────
//
// It started on the BOTTOM layer, under every window, like the weather. On a
// tiling desktop that is nowhere: the first window on a workspace covers the
// whole screen, so the turntable only ever showed on an empty workspace --
// reported, fairly, as "it does not appear when something is playing".
//
// So it sits on the TOP layer now, in its corner, and hides for a fullscreen
// window. `layer desktop` puts it back under the windows for anyone who
// wants it there. Either way the window covers the screen and takes input
// only over the deck, so every click that misses the record goes to whatever
// is under it.
//
// ── Told things from outside ──────────────────────────────────────────────
//
//     caelestia shell vinyl set corner <top-left|top-right|bottom-left|bottom-right>
//     caelestia shell vinyl set scale 1.2        (0.6 to 1.6)
//     caelestia shell vinyl set idle <hide|show> (with nothing playing)
//     caelestia shell vinyl set layer <above|desktop>
//
// kept in `genesi-vinyl.json` in caelestia's state directory, which this
// file alone writes.
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

    property string corner: "bottom-right"
    property real scaleF: 1
    property bool hideIdle: true
    property bool above: true
    property bool loaded: false

    function save(): void {
        if (!root.loaded)
            return;
        store.setText(JSON.stringify({
            corner: root.corner,
            scale: root.scaleF,
            hideIdle: root.hideIdle,
            layer: root.above ? "above" : "desktop"
        }, null, 2) + "\n");
    }

    GenesiPluginSwitch {
        id: gate

        plugin: "vinyl"
    }

    FileView {
        id: store

        path: `${Paths.state}/genesi-vinyl.json`
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.corner = ["top-left", "top-right", "bottom-left", "bottom-right"].includes(d.corner) ? d.corner : "bottom-right";
                root.scaleF = Math.min(1.6, Math.max(0.6, d.scale ?? 1));
                root.hideIdle = d.hideIdle !== false;
                root.above = d.layer !== "desktop";
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "vinyl"

        function set(key: string, value: string): void {
            if (key === "corner" && ["top-left", "top-right", "bottom-left", "bottom-right"].includes(value))
                root.corner = value;
            else if (key === "scale")
                root.scaleF = Math.min(1.6, Math.max(0.6, parseFloat(value) || 1));
            else if (key === "idle")
                root.hideIdle = value !== "show";
            else if (key === "layer")
                root.above = value !== "desktop";
            else
                return;
            root.save();
        }
    }

    LazyLoader {
        active: gate.active && Screens.screens.length > 0

        StyledWindow {
            id: win

            readonly property var player: Players.active
            readonly property bool present: !!win.player && !!win.player.trackTitle
            readonly property var monitor: Hypr.monitorFor(win.screen)
            readonly property bool fullscreen: win.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
            readonly property bool shown: win.present || !root.hideIdle

            readonly property real edge: contentItem.Config.border.thickness + 18
            readonly property bool atTop: root.corner.startsWith("top")
            readonly property bool atLeft: root.corner.endsWith("left")

            screen: Screens.screens[0]
            name: "genesi-vinyl"
            visible: !win.fullscreen

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: root.above ? WlrLayer.Top : WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: Region {
                x: deck.opacity > 0 ? holder.x : 0
                y: deck.opacity > 0 ? holder.y : 0
                width: deck.opacity > 0 ? holder.width : 0
                height: deck.opacity > 0 ? holder.height : 0
            }

            // The position is only polled while it plays -- MPRIS does not
            // push it, and a stopped track has nowhere to move to.
            Timer {
                interval: 1000
                repeat: true
                running: win.player?.isPlaying ?? false
                onTriggered: win.player?.positionChanged()
            }

            Item {
                id: holder

                width: deck.implicitWidth * root.scaleF
                height: deck.implicitHeight * root.scaleF
                x: win.atLeft ? win.edge : win.width - holder.width - win.edge
                y: win.atTop ? win.edge + Launcher.GenesiEdges.top
                    : win.height - holder.height - win.edge - Launcher.GenesiEdges.bottom

                GenesiVinylDeck {
                    id: deck

                    width: deck.implicitWidth
                    height: deck.implicitHeight
                    scale: root.scaleF
                    transformOrigin: Item.TopLeft
                    opacity: win.shown ? 1 : 0
                    visible: opacity > 0

                    pal: Colours.palette
                    sans: win.contentItem.Tokens.font.body.small.family
                    present: win.present
                    playing: win.player?.isPlaying ?? false
                    title: win.player?.trackTitle ?? ""
                    artist: win.player?.trackArtist ?? ""
                    art: win.player?.trackArtUrl ?? ""
                    progress: (win.player?.length ?? 0) > 0 ? (win.player.position / win.player.length) : 0

                    onToggle: win.player?.togglePlaying()
                    onNext: if (win.player?.canGoNext)
                        win.player.next()
                    onPrevious: if (win.player?.canGoPrevious)
                        win.player.previous()

                    Behavior on opacity {
                        NumberAnimation { duration: 500 }
                    }
                }
            }
        }
    }
}
