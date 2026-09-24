// GENESI — the leaf: a desktop pet that is the state of the machine, alive.
//
// A plugin: nothing here exists until the Plugins shelf of Genesi Store
// switches it on, and when it is switched off again the LazyLoader below
// throws all of it away -- window, timers, the CPU sampling. A pet you did
// not ask for costs nothing.
//
// ── What it notices ───────────────────────────────────────────────────────
//
//   the CPU's load and temperature   Caelestia.Services Cpu, held by a
//                                    ServiceRef so it is sampled only while
//                                    something is listening
//   whether anybody is there         a Wayland IdleMonitor, five minutes
//   music                            the active MPRIS player
//   updates waiting                  checkupdates, hourly -- its own private
//                                    database, never a partial `pacman -Sy`
//   the disk                         Storage, the root mount
//   notifications                    it hops when one arrives
//   the Game Center                  its records file: XP for every game,
//                                    more for a record
//
// GenesiPetMind turns all of that into a mood, a level and a sentence;
// GenesiLeaf draws the result. This file only gathers and places.
//
// ── Where it lives ────────────────────────────────────────────────────────
//
// Along the bottom of the first screen, standing on whatever Genesi surface
// is down there (GenesiEdges knows how tall the dock is). It wanders every
// minute or two like a leaf on a breeze, and can be dragged anywhere along
// the edge; where it was left is remembered. Its window is the width of the
// screen but takes input only over the leaf and its speech bubble -- a strip
// that swallowed clicks along the bottom of every window would be a pet
// nobody keeps.
//
// On the TOP layer, not the overlay: a fullscreen window covers it, which is
// exactly what somebody playing a real game wants.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import qs.components.containers
import qs.services
import qs.utils
import qs.modules.launcher as Launcher

Scope {
    id: root

    GenesiPluginSwitch {
        id: gate

        plugin: "leaf"
    }

    LazyLoader {
        active: gate.active && Screens.screens.length > 0

        StyledWindow {
            id: win

            screen: Screens.screens[0]
            name: "genesi-leaf"

            readonly property var monitor: Hypr.monitorFor(win.screen)
            readonly property bool fullscreen: win.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

            // ── What it knows ───────────────────────────────────────────────
            property real xp: 0
            property real fx: 0.12
            property int seenPlays: -1
            property var seenBest: ({})
            property bool loaded: false

            property bool idle: false
            property int updates: 0
            property real happyUntil: 0
            property var cpuSamples: []
            readonly property real cpu: win.cpuSamples.length
                ? win.cpuSamples.reduce((a, b) => a + b, 0) / win.cpuSamples.length : 0

            readonly property var senses: ({
                now: clock.now,
                happyUntil: win.happyUntil,
                idle: win.idle,
                cpu: win.cpu,
                temp: Cpu.temperature,
                playing: Players.active?.isPlaying ?? false,
                updates: win.updates,
                disk: win.rootDisk,
                hour: new Date(clock.now).getHours()
            })
            // The primary disk, as a fraction -- what the dashboard shows.
            readonly property real rootDisk: Storage.percentage
            readonly property string mood: mind.moodFor(win.senses)
            readonly property int level: mind.levelFor(win.xp)
            property string lastMood: ""
            property int lastLevel: 0

            property var bubble: []
            property bool talking: false

            function say(lines: var, ms: int): void {
                win.bubble = typeof lines === "string" ? [lines] : lines;
                win.talking = true;
                talkTimer.restart();
                bubbleTimer.interval = ms || 5000;
                bubbleTimer.restart();
            }

            function cheer(ms: int): void {
                win.happyUntil = Date.now() + (ms || 4000);
                leaf.hop();
            }

            function gain(amount: real): void {
                if (amount <= 0)
                    return;
                win.xp += amount;
                win.save();
            }

            function save(): void {
                if (!win.loaded)
                    return;
                petFile.setText(JSON.stringify({
                    xp: Math.floor(win.xp),
                    fx: Math.round(win.fx * 1000) / 1000,
                    seenPlays: win.seenPlays,
                    seenBest: win.seenBest
                }, null, 2) + "\n");
            }

            onMoodChanged: {
                if (!win.loaded)
                    return;
                const line = mind.remark(win.lastMood, win.mood, win.senses);
                win.lastMood = win.mood;
                if (line)
                    win.say(line, 4000);
            }

            onLevelChanged: {
                if (win.loaded && win.lastLevel > 0 && win.level > win.lastLevel) {
                    win.say(mind.t("I grew! Level %1 — %2", "Cresci! Nível %1 — %2")
                            .arg(win.level).arg(mind.title(win.level)), 6000);
                    win.cheer(6000);
                }
                win.lastLevel = win.level;
            }

            visible: !win.fullscreen

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            implicitHeight: 230

            // The leaf, and the bubble while it is talking. Nothing else.
            mask: Region {
                x: leaf.x - 6
                y: leaf.y - 6
                width: leaf.width + 12
                height: leaf.height + 12

                Region {
                    x: bubbleCard.visible ? bubbleCard.x : 0
                    y: bubbleCard.visible ? bubbleCard.y : 0
                    width: bubbleCard.visible ? bubbleCard.width : 0
                    height: bubbleCard.visible ? bubbleCard.height : 0
                }
            }

            GenesiPetMind {
                id: mind
            }

            ServiceRef {
                service: Cpu
            }

            ServiceRef {
                service: Storage
            }

            IdleMonitor {
                timeout: 300
                respectInhibitors: true
                onIsIdleChanged: win.idle = isIdle
            }

            QtObject {
                id: clock

                property real now: Date.now()
            }

            Timer {
                // One tick drives the clock, the CPU average and the XP for
                // time spent together.
                interval: 2000
                repeat: true
                running: true
                onTriggered: {
                    clock.now = Date.now();
                    // Cpu.percentage is a FRACTION. The mind speaks percent, and
                    // reading 0.93 as 0.93% is a leaf that never feels the heat.
                    win.cpuSamples = win.cpuSamples.slice(-4).concat([Cpu.percentage * 100]);
                }
            }

            Timer {
                interval: 5 * 60 * 1000
                repeat: true
                running: true
                onTriggered: if (!win.idle)
                    win.gain(1)
            }

            // ── Its memory ──────────────────────────────────────────────────
            FileView {
                id: petFile

                path: `${Paths.state}/genesi-pet.json`
                printErrors: false
                onLoaded: {
                    try {
                        const d = JSON.parse(text());
                        win.xp = d.xp ?? 0;
                        win.fx = Math.min(0.95, Math.max(0.03, d.fx ?? 0.12));
                        win.seenPlays = d.seenPlays ?? -1;
                        win.seenBest = d.seenBest ?? {};
                    } catch (e) {}
                    win.wake();
                }
                onLoadFailed: win.wake()
            }

            function wake(): void {
                win.loaded = true;
                win.lastMood = win.mood;
                win.lastLevel = win.level;
                win.say([mind.greeting(new Date().getHours()),
                         mind.t("I'm your leaf. Click me any time.", "Sou sua folhinha. Clica em mim quando quiser.")], 6000);
                leaf.hop();
            }

            // The Game Center's records. Polled for the same reason the
            // plugin switch is: the file does not exist until the first game.
            FileView {
                id: gamesFile

                path: `${Paths.state}/genesi-games.json`
                printErrors: false
                onLoaded: {
                    if (!win.loaded)
                        return;
                    let d;
                    try {
                        d = JSON.parse(text());
                    } catch (e) {
                        return;
                    }
                    const plays = Object.values(d.plays ?? {}).reduce((a, b) => a + b, 0);
                    const best = d.best ?? {};
                    if (win.seenPlays < 0) {
                        // First sight of the file: a baseline, not a windfall.
                        win.seenPlays = plays;
                        win.seenBest = best;
                        win.save();
                        return;
                    }
                    const got = mind.fromGames(plays, win.seenPlays, best, win.seenBest);
                    win.seenPlays = plays;
                    win.seenBest = best;
                    if (got.xp > 0) {
                        win.gain(got.xp);
                        if (got.line) {
                            win.say(got.line, 3500);
                            win.cheer(3500);
                        }
                    } else {
                        win.save();
                    }
                }
            }

            Timer {
                interval: 8000
                repeat: true
                running: true
                onTriggered: gamesFile.reload()
            }

            // ── Updates ─────────────────────────────────────────────────────
            Process {
                id: checker

                command: ["sh", "-c", "if command -v checkupdates >/dev/null 2>&1; then checkupdates 2>/dev/null; else pacman -Qu 2>/dev/null; fi | grep -c ."]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const n = parseInt(text.trim()) || 0;
                        // A long list installed is being looked after.
                        if (win.updates >= mind.sickUpdates && n === 0)
                            win.gain(15);
                        win.updates = n;
                    }
                }
            }

            Timer {
                interval: 60 * 60 * 1000
                repeat: true
                running: true
                triggeredOnStart: false
                onTriggered: checker.running = true
            }

            Timer {
                // Not at login: the network is still coming up, and the
                // first thing a session does should not be a mirror sync.
                interval: 3 * 60 * 1000
                running: true
                onTriggered: checker.running = true
            }

            // A notification arrived: look up.
            Connections {
                target: Notifs

                function onListChanged(): void {
                    if (win.loaded && !win.idle)
                        leaf.hop();
                }
            }

            // ── Wandering ───────────────────────────────────────────────────
            Timer {
                id: wander

                interval: 60000
                repeat: true
                running: win.mood === "normal" && !drag.pressed
                onTriggered: {
                    wander.interval = 45000 + Math.random() * 90000;
                    let to = 0.05 + Math.random() * 0.9;
                    // A short hop sideways more often than a trip across.
                    if (Math.random() < 0.7)
                        to = Math.min(0.95, Math.max(0.05, win.fx + (Math.random() - 0.5) * 0.3));
                    drift.to = to;
                    drift.duration = 1400 + Math.abs(to - win.fx) * 9000;
                    drift.restart();
                }
            }

            NumberAnimation {
                id: drift

                target: win
                property: "fx"
                easing.type: Easing.InOutSine
                onFinished: win.save()
            }

            // ── The leaf ────────────────────────────────────────────────────
            readonly property real floor: contentItem.Config.border.thickness + Launcher.GenesiEdges.bottom + 2

            GenesiLeaf {
                id: leaf

                size: 64 + Math.min(win.level, 8) * 3
                x: win.fx * (win.width - leaf.width)
                // A leaf in the air bobs; one on the ground does not.
                y: win.height - leaf.height - win.floor - (drift.running ? 10 + Math.sin(win.fx * 60) * 8 : 0)
                pal: Colours.palette
                mood: win.mood
                level: win.level
                talking: win.talking
                rotation: drift.running ? (drift.to > win.fx ? 12 : -12) : 0

                Behavior on rotation {
                    NumberAnimation { duration: 400 }
                }

                MouseArea {
                    id: drag

                    property real startX: 0
                    property bool moved: false

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    onPressed: mouse => {
                        drift.stop();
                        drag.startX = mouse.x;
                        drag.moved = false;
                    }
                    onPositionChanged: mouse => {
                        if (drag.pressed) {
                            const dx = mouse.x - drag.startX;
                            if (Math.abs(dx) > 3)
                                drag.moved = true;
                            if (drag.moved)
                                win.fx = Math.min(0.97, Math.max(0.01, win.fx + dx / Math.max(1, win.width - leaf.width)));
                        } else {
                            leaf.look = Qt.point((mouse.x / leaf.width - 0.5) * 2, (mouse.y / leaf.height - 0.5) * 2);
                        }
                    }
                    onExited: leaf.look = Qt.point(0, 0)
                    onReleased: if (drag.moved)
                        win.save()
                    onClicked: if (!drag.moved) {
                        win.say(mind.status(win.senses, win.xp), 7000);
                    }
                    onDoubleClicked: {
                        win.cheer(3000);
                        win.say(mind.t("Hehe!", "Hihi!"), 1600);
                    }
                }
            }

            // ── The speech bubble ───────────────────────────────────────────
            Rectangle {
                id: bubbleCard

                visible: opacity > 0
                opacity: bubbleTimer.running ? 1 : 0
                width: Math.min(300, bubbleText.implicitWidth + 28)
                height: bubbleText.implicitHeight + 20
                x: Math.min(win.width - width - 8, Math.max(8, leaf.x + leaf.width / 2 - width / 2))
                y: leaf.y - height - 10
                radius: 14
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                Text {
                    id: bubbleText

                    x: 14
                    y: 10
                    width: Math.min(272, implicitWidth)
                    text: win.bubble.join("\n")
                    wrapMode: Text.Wrap
                    lineHeight: 1.15
                    color: Colours.palette.m3onSurface
                    font.family: win.contentItem.Tokens.font.body.small.family
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: bubbleTimer.stop()
                }
            }

            Timer {
                id: bubbleTimer

                interval: 5000
            }

            Timer {
                id: talkTimer

                interval: 1400
                onTriggered: win.talking = false
            }
        }
    }
}
