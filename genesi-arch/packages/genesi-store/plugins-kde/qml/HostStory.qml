// The Retrospective's story on Plasma: caelestia's GenesiWrappedStory, built
// from the tracker's days the same way GenesiWrapped.build does -- the other
// plugins' files for the games and the leaf, app names and icons from the
// .desktop files and the icon theme (the host's appInfo and image://icon).
import QtQuick

Rectangle {
    id: root

    property int days: 7
    property var tracker: null
    signal closed

    color: host.palette.m3surface ?? "#0b120f"
    radius: 24
    clip: true
    focus: true
    Keys.onEscapePressed: root.closed()

    GenesiWrappedMath { id: math }
    GenesiPetMind { id: leafMind }

    property var slides: []
    property var names: ({})
    property var icons: ({})

    function build(): void {
        const daysData = root.tracker ? root.tracker.days : {};
        const s = math.summarize(daysData, new Date(), root.days);
        let games = {}, pet = {};
        try { games = JSON.parse(host.readState("genesi-games.json") || "{}"); } catch (e) {}
        try { pet = JSON.parse(host.readState("genesi-pet.json") || "{}"); } catch (e) {}
        const plays = games.plays ?? {};
        const total = Object.values(plays).reduce((a, b) => a + b, 0);
        const fav = Object.keys(plays).sort((a, b) => plays[b] - plays[a])[0];
        const gameNames = { snake: "Snake", "2048": "2048", flappy: "Flappy Leaf", blocks: "Blocks",
                            breakout: "Breakout", mines: math.t("Minesweeper", "Campo Minado"),
                            memory: math.t("Memory", "Memória"), simon: "Simon" };
        const extra = {
            games: total > 0 ? { total: total, favourite: gameNames[fav] ?? fav, best: (games.best ?? {})[fav] } : null,
            leaf: pet.xp !== undefined ? { level: leafMind.levelFor(pet.xp),
                                           title: leafMind.title(leafMind.levelFor(pet.xp)) } : null
        };
        const names = {}, icons = {};
        for (const a of s.top.slice(0, 5)) {
            const info = host.appInfo(a.app);
            names[a.app] = info.name || a.app;
            icons[a.app] = "image://icon/" + (info.icon || a.app);
        }
        root.names = names;
        root.icons = icons;
        root.slides = math.slides(s, extra);
    }

    Component.onCompleted: {
        if (root.tracker)
            root.tracker.save();
        root.build();
        story.forceActiveFocus();
    }

    GenesiWrappedStory {
        id: story

        anchors.fill: parent
        pal: host.palette
        slides: root.slides
        names: root.names
        icons: root.icons
        focus: true
        onClosed: root.closed()
    }
}
