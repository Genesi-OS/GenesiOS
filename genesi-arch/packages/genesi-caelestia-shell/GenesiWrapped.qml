// GENESI — the Retrospective: your week (or month) on Genesi, as a story.
//
// A plugin ("wrapped"): off until the Plugins shelf of Genesi Store or
// Nexus -> Plugins switches it on. Nothing is counted before that, and
// switching it off stops the counting at once.
//
// ── What it counts, and what it does not ──────────────────────────────────
//
// Every fifteen seconds, if somebody is at the machine (a Wayland idle
// monitor, two minutes), the CLASS of the focused window -- "firefox",
// "code", "foot" -- gets fifteen seconds. Never the title, which is where
// the document, the site and the person would be. Kept per day in
// `genesi-wrapped.json` in caelestia's state directory, for ten weeks, on
// this machine and nowhere else.
//
// ── Seeing it ─────────────────────────────────────────────────────────────
//
//     caelestia shell wrapped show week      (or month)
//
// which is what the Plugins page's button calls. On Sunday evening, the
// first time the shell sees one, it says the week is ready -- once.
//
// It never fails in silence. The buttons were reported as "doing nothing",
// and a story that cannot open has exactly one way to say why: a toast, and
// the answer of the IPC call for whoever ran it from a terminal.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components.containers
import qs.services
import qs.utils
// GenesiPluginBus. A singleton is reached through its module even from next
// door, so it lives with the others in the launcher's directory.
import qs.modules.launcher as Launcher

Scope {
    id: root

    property var days: ({})
    property string announced: ""
    property bool loaded: false
    property bool dirty: false

    property bool open: false
    property int span: 7
    property var slides: []
    property var names: ({})
    property var icons: ({})

    // Read on demand from the other plugins' files, for the story.
    property var games: ({})
    property var pet: ({})

    function save(): void {
        if (!root.loaded)
            return;
        // Ten weeks and not a day more.
        const keep = {};
        const cutoff = mathNow.dayKey(new Date(Date.now() - 70 * 86400000));
        for (const k of Object.keys(root.days))
            if (k >= cutoff)
                keep[k] = root.days[k];
        store.setText(JSON.stringify({ version: 1, announced: root.announced, days: keep }) + "\n");
        root.dirty = false;
    }

    function tick(seconds: int): void {
        const cls = Hypr.activeToplevel?.lastIpcObject?.class ?? "";
        const now = new Date();
        const key = mathNow.dayKey(now);
        const days = root.days;
        const d = days[key] ?? { active: 0, apps: {}, hours: new Array(24).fill(0) };
        d.active += seconds;
        d.hours[now.getHours()] = (d.hours[now.getHours()] || 0) + seconds;
        if (cls)
            d.apps[cls] = (d.apps[cls] || 0) + seconds;
        days[key] = d;
        root.days = days;
        root.dirty = true;
    }

    // Straight to caelestia's Toaster, in-process. It used to go out through
    // `caelestia shell toaster`, one more hop that could fail unseen.
    function toast(title: string, body: string): void {
        Toaster.toast(title, body, "auto_awesome", Toast.Warning);
    }

    function show(span: int): string {
        if (!gate.active) {
            root.toast(mathNow.t("The Retrospective is off", "A Retrospectiva está desligada"),
                       mathNow.t("Switch it on in Settings -> Plugins first", "Ligue ela antes em Configurações -> Plugins"));
            return "off";
        }
        try {
            root.build(span);
        } catch (e) {
            console.warn("genesi-wrapped: could not build the story:", e);
            root.toast(mathNow.t("The Retrospective could not open", "A Retrospectiva não abriu"), String(e));
            return `error: ${e}`;
        }
        return "shown";
    }

    function build(span: int): void {
        root.span = span;
        const s = mathNow.summarize(root.days, new Date(), span);

        const plays = root.games.plays ?? {};
        const total = Object.values(plays).reduce((a, b) => a + b, 0);
        const fav = Object.keys(plays).sort((a, b) => plays[b] - plays[a])[0];
        const gameNames = { snake: "Snake", "2048": "2048", flappy: "Flappy Leaf", blocks: "Blocks",
                            breakout: "Breakout", mines: mathNow.t("Minesweeper", "Campo Minado"),
                            memory: mathNow.t("Memory", "Memória"), simon: "Simon" };
        const leafXp = root.pet.xp;
        const extra = {
            games: total > 0 ? { total: total, favourite: gameNames[fav] ?? fav, best: (root.games.best ?? {})[fav] } : null,
            leaf: leafXp !== undefined ? { level: leafMind.levelFor(leafXp), title: leafMind.title(leafMind.levelFor(leafXp)) } : null
        };

        const names = {};
        const icons = {};
        for (const a of s.top.slice(0, 5)) {
            const entry = DesktopEntries.heuristicLookup(a.app);
            names[a.app] = entry?.name ?? a.app;
            icons[a.app] = Icons.getAppIcon(a.app, "application-x-executable");
        }
        root.names = names;
        root.icons = icons;
        root.slides = mathNow.slides(s, extra);
        root.open = true;
    }

    GenesiPluginSwitch {
        id: gate

        plugin: "wrapped"
    }

    // The Plugins page's buttons, without leaving the process.
    Connections {
        target: Launcher.GenesiPluginBus

        function onWrappedRequested(span: string): void {
            root.show(span === "month" ? 30 : 7);
        }
    }

    GenesiWrappedMath {
        id: mathNow
    }

    GenesiPetMind {
        id: leafMind
    }

    FileView {
        id: store

        path: `${Paths.state}/genesi-wrapped.json`
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.days = d.days ?? {};
                root.announced = d.announced ?? "";
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
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
                root.pet = JSON.parse(text());
            } catch (e) {}
        }
    }

    Timer {
        // The other plugins' files, kept fresh so the story is built from
        // what they said a minute ago rather than waiting on a read.
        interval: 60000
        repeat: true
        running: gate.active
        triggeredOnStart: true
        onTriggered: {
            gamesFile.reload();
            petFile.reload();
        }
    }

    IdleMonitor {
        id: idle

        enabled: gate.active
        timeout: 120
        respectInhibitors: false
    }

    Timer {
        interval: 15000
        repeat: true
        running: gate.active && root.loaded
        onTriggered: if (!idle.isIdle)
            root.tick(15)
    }

    Timer {
        // Saved every two minutes rather than every tick: a desktop that
        // writes to disk four times a minute for a statistic is a desktop
        // doing something nobody asked it to.
        interval: 120000
        repeat: true
        running: gate.active && root.dirty
        onTriggered: root.save()
    }

    Timer {
        // Sunday from six in the evening: the week is ready. Said once.
        interval: 300000
        repeat: true
        running: gate.active && root.loaded
        onTriggered: {
            const now = new Date();
            const key = mathNow.dayKey(now);
            if (now.getDay() === 0 && now.getHours() >= 18 && root.announced !== key) {
                root.announced = key;
                root.save();
                Quickshell.execDetached(["caelestia", "shell", "toaster", "info",
                                         mathNow.t("Your week on Genesi is ready", "Sua semana no Genesi saiu"),
                                         mathNow.t("Open it from Settings -> Plugins", "Abra em Configurações -> Plugins"),
                                         "auto_awesome"]);
            }
        }
    }

    IpcHandler {
        target: "wrapped"

        function show(span: string): string {
            return root.show(span === "month" ? 30 : 7);
        }

        function hide(): void {
            root.open = false;
        }
    }

    LazyLoader {
        active: root.open

        StyledWindow {
            id: win

            screen: Screens.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Screens.screens[0]
            name: "genesi-wrapped"

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            GenesiWrappedStory {
                id: story

                anchors.fill: parent
                opacity: 0
                pal: Colours.palette
                sans: win.contentItem.Tokens.font.body.small.family
                slides: root.slides
                names: root.names
                icons: root.icons
                focus: true

                onClosed: fadeOut.start()

                Component.onCompleted: {
                    fadeIn.start();
                    story.restart();
                    story.forceActiveFocus();
                }

                NumberAnimation {
                    id: fadeIn

                    target: story
                    property: "opacity"
                    to: 1
                    duration: 350
                }

                NumberAnimation {
                    id: fadeOut

                    target: story
                    property: "opacity"
                    to: 0
                    duration: 250
                    onFinished: root.open = false
                }
            }
        }
    }
}
