// GENESI — what the leaf feels, how it grows, and what it says.
//
// Rules only, as plain functions over plain numbers: GenesiPet.qml gathers
// the numbers from the machine, this decides. Kept apart so every rule can be
// played in ci/plugins-test.py -- "sweating at 91% CPU", "asleep but music is
// playing", "level 3 at 180 XP" -- without a shell, a CPU or a clock.
//
// ── Moods, in the order they win ──────────────────────────────────────────
//
//   happy     somebody just played with it, or it just grew
//   hot       CPU at 90% or more, or 85 C -- even asleep: a leaf does not
//             sleep through a fire
//   dancing   music is playing -- this beats sleeping, because listening
//             without touching the mouse is not being away
//   sleeping  nobody has touched the machine for a while
//   sick      a long list of updates, or a nearly full disk -- something
//             the person can DO something about, which is the point
//   normal    everything else
//
// ── Growth ────────────────────────────────────────────────────────────────
//
// Level n is reached at 30·n·(n−1) XP: 60 for level 2, 180 for 3, 600 for
// 5, 1680 for 8. XP comes from time spent together (1 per 5 active
// minutes), games in the Game Center (5 each, 20 for a record) and from
// installing a long list of updates (15) -- being looked after, in short.
import QtQuick

QtObject {
    id: mind

    // The machine's language, the way the rest of Genesi follows it. The
    // leaf talks, and talking in the wrong language is worse than silence.
    property bool portuguese: Qt.locale().name.startsWith("pt")

    readonly property int sickUpdates: 25

    function t(en: string, pt: string): string {
        return mind.portuguese ? pt : en;
    }

    // s: { now, happyUntil, idle, cpu, temp, playing, updates, disk }
    function moodFor(s: var): string {
        if ((s.happyUntil ?? 0) > (s.now ?? 0))
            return "happy";
        if ((s.cpu ?? 0) >= 90 || (s.temp ?? 0) >= 85)
            return "hot";
        if (s.playing)
            return "dancing";
        if (s.idle)
            return "sleeping";
        if ((s.updates ?? 0) >= mind.sickUpdates || (s.disk ?? 0) >= 0.95)
            return "sick";
        return "normal";
    }

    function levelFor(xp: real): int {
        // Largest n with 30·n·(n−1) <= xp.
        const n = Math.floor((1 + Math.sqrt(1 + 4 * Math.max(0, xp) / 30)) / 2);
        return Math.max(1, n);
    }

    function xpFor(level: int): int {
        return 30 * level * (level - 1);
    }

    function title(level: int): string {
        if (level >= 8)
            return mind.t("Elder leaf", "Folha anciã");
        if (level >= 5)
            return mind.t("Leaf", "Folha");
        if (level >= 3)
            return mind.t("Leaflet", "Folhinha");
        return mind.t("Sprout", "Brotinho");
    }

    function greeting(hour: int): string {
        if (hour < 5)
            return mind.t("Still up? Me too.", "Acordado ainda? Eu também.");
        if (hour < 12)
            return mind.t("Good morning!", "Bom dia!");
        if (hour < 18)
            return mind.t("Good afternoon!", "Boa tarde!");
        return mind.t("Good evening!", "Boa noite!");
    }

    // What it says when it is clicked: how it is, and why.
    function status(s: var, xp: real): var {
        const level = mind.levelFor(xp);
        const lines = [];
        const mood = mind.moodFor(s);
        if (mood === "hot")
            lines.push(mind.t("It's hot in here! CPU at %1%", "Tá quente aqui! CPU em %1%").arg(Math.round(s.cpu ?? 0)));
        else if (mood === "sick" && (s.disk ?? 0) >= 0.95)
            lines.push(mind.t("The disk is almost full...", "O disco está quase cheio..."));
        else if (mood === "sick")
            lines.push(mind.t("%1 updates are waiting. They'd make me feel better.", "%1 atualizações esperando. Me fariam bem.").arg(s.updates));
        else if (mood === "dancing")
            lines.push(mind.t("Good song!", "Que música boa!"));
        else
            lines.push(mind.greeting(s.hour ?? 12));

        lines.push(mind.t("CPU %1%", "CPU %1%").arg(Math.round(s.cpu ?? 0))
                   + ((s.temp ?? 0) > 0 ? " · %1 °C".arg(Math.round(s.temp)) : ""));
        if ((s.updates ?? 0) > 0 && mood !== "sick")
            lines.push(s.updates === 1 ? mind.t("1 update available", "1 atualização disponível")
                       : mind.t("%1 updates available", "%1 atualizações disponíveis").arg(s.updates));
        const next = mind.xpFor(level + 1);
        lines.push("%1 · %2 %3 · %4/%5 XP".arg(mind.title(level)).arg(mind.t("level", "nível"))
                   .arg(level).arg(Math.floor(xp)).arg(next));
        return lines;
    }

    // What it says on its own when something changes. Empty means nothing.
    function remark(from: string, to: string, s: var): string {
        if (from === to)
            return "";
        if (to === "hot")
            return mind.t("Phew, it's getting hot!", "Ufa, tá esquentando!");
        if (from === "sick" && to !== "sick" && (s.updates ?? 0) === 0)
            return mind.t("Thanks, I feel brand new!", "Obrigada, me sinto nova!");
        if (from === "sleeping" && to === "normal")
            return mind.greeting(s.hour ?? 12);
        if (to === "sick")
            return mind.t("I'm not feeling great...", "Não tô me sentindo bem...");
        return "";
    }

    // How much a change in the Game Center is worth, and whether to say so.
    // plays/best are the file's totals now; seenPlays/seenBest what the leaf
    // had already counted. Returns { xp, line }.
    function fromGames(plays: int, seenPlays: int, best: var, seenBest: var): var {
        let xp = Math.max(0, plays - seenPlays) * 5;
        let line = "";
        for (const id of Object.keys(best ?? {})) {
            const was = (seenBest ?? {})[id];
            if (was !== undefined && best[id] !== was) {
                xp += 20;
                line = mind.t("New record! I saw that.", "Recorde novo! Eu vi, hein.");
            }
        }
        if (!line && xp > 0)
            line = mind.t("Good game!", "Boa partida!");
        return { xp: xp, line: line };
    }
}
