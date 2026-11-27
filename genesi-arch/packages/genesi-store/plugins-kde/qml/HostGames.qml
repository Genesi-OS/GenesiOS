// The Game Center on Plasma: caelestia's GenesiGames, in a card in the middle
// of the screen. Records go to the same genesi-games.json caelestia keeps, so
// a high score is a high score on either desktop. Plasma has no hot corner to
// open it from; the "Game Center" menu entry does (genesi-plugins toggle
// game-center), and Escape or the close button puts it away.
import QtQuick

Rectangle {
    id: root

    signal closed

    property var best: ({})
    property var plays: ({})
    property bool corner: true
    property bool loaded: false
    readonly property var pal: host.palette

    color: pal.m3surfaceContainer ?? "#101815"
    radius: 22
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    focus: true
    Keys.onEscapePressed: root.closed()

    function save(): void {
        if (!root.loaded)
            return;
        host.writeState("genesi-games.json", JSON.stringify({
            corner: root.corner, best: root.best, plays: root.plays
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

    Component.onCompleted: {
        try {
            const d = JSON.parse(host.readState("genesi-games.json") || "{}");
            root.corner = d.corner !== false;
            root.best = d.best ?? {};
            root.plays = d.plays ?? {};
        } catch (e) {}
        root.loaded = true;
        games.forceActiveFocus();
    }

    GenesiGames {
        id: games

        anchors.fill: parent
        anchors.margins: 22
        pal: root.pal
        shown: true
        best: root.best
        plays: root.plays
        // The hot corner is caelestia's; on Plasma the switch has nothing to
        // switch, but it is kept as it was for the day the person is back on
        // Hyprland.
        corner: root.corner
        focus: true

        onPlayed: (id, score, low) => root.record(id, score, low)
        onCloseRequested: root.closed()
        onCornerToggled: on => {
            root.corner = on;
            root.save();
        }
    }
}
