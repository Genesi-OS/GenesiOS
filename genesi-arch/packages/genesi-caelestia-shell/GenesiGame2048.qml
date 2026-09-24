// GENESI — 2048, for the Game Center.
//
// ── Tiles have identities, not just values ────────────────────────────────
//
// The obvious model is a 4x4 array of numbers and a Repeater over it. That
// draws correctly and never animates: every move rebuilds the array, so the
// delegates see a new value where the old one was instead of a tile that
// SLID. Here each tile is a row in a ListModel with an id; a move rewrites
// its row and column, and `Behavior on x` does the rest.
//
// A merge keeps the tile it merged INTO and sends the other one to the same
// square before removing it, so two tiles visibly meet rather than one of
// them vanishing where it stood.
//
// ── One tile merges once per move ─────────────────────────────────────────
//
// [4, 4, 8, _] slid left is [8, 8, _, _], not [16, _, _, _]: the 8 that was
// just made does not merge again on the same move. `merged` on the line
// being built is what stops it. ci/game-center-test.py plays exactly that
// row, because it is the rule every first attempt at 2048 gets wrong.
import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    // Off in the tests, so a board they lay out stays the board they laid out.
    property bool spawning: true

    property int score: 0
    property bool started: false
    property bool over: false
    property bool won: false
    property bool keepGoing: false
    property int nextId: 1

    readonly property string hint: qsTr("Arrows or WASD to slide · reach 2048")
    readonly property string idleHint: ""

    signal finished(int score)

    ListModel {
        id: tiles
    }

    function restart(): void {
        tiles.clear();
        game.score = 0;
        game.over = false;
        game.won = false;
        game.keepGoing = false;
        game.started = true;
        if (game.spawning) {
            game.spawn();
            game.spawn();
        }
    }

    // The board as numbers, row by row. The tests read it; so does
    // everything in here that needs to know what is where.
    function matrix(): var {
        const m = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
        for (let i = 0; i < tiles.count; i++) {
            const t = tiles.get(i);
            if (!t.dying)
                m[t.r][t.c] = t.v;
        }
        return m;
    }

    function load(m: var): void {
        tiles.clear();
        for (let r = 0; r < 4; r++)
            for (let c = 0; c < 4; c++)
                if (m[r][c])
                    tiles.append({ tid: game.nextId++, v: m[r][c], r: r, c: c, dying: false, fresh: false, pop: false });
        game.over = false;
        game.won = false;
        game.started = true;
    }

    function spawn(): void {
        const m = game.matrix();
        const free = [];
        for (let r = 0; r < 4; r++)
            for (let c = 0; c < 4; c++)
                if (!m[r][c])
                    free.push([r, c]);
        if (!free.length)
            return;
        const at = free[Math.floor(Math.random() * free.length)];
        tiles.append({ tid: game.nextId++, v: Math.random() < 0.9 ? 2 : 4, r: at[0], c: at[1], dying: false, fresh: true, pop: false });
    }

    function indexOf(tid: int): int {
        for (let i = 0; i < tiles.count; i++)
            if (tiles.get(i).tid === tid)
                return i;
        return -1;
    }

    // dr/dc is the direction of travel: (0,-1) left, (0,1) right, (-1,0) up,
    // (1,0) down. Returns whether anything moved.
    function move(dr: int, dc: int): bool {
        if (game.over)
            return false;
        buryDead();

        const cells = [[null, null, null, null], [null, null, null, null],
                       [null, null, null, null], [null, null, null, null]];
        for (let i = 0; i < tiles.count; i++) {
            const t = tiles.get(i);
            cells[t.r][t.c] = { tid: t.tid, v: t.v };
        }

        let moved = false;
        let gained = 0;
        const updates = [];
        for (let line = 0; line < 4; line++) {
            // Walk the line from the edge the tiles are travelling toward.
            const path = [];
            for (let k = 0; k < 4; k++) {
                const step = (dr + dc) > 0 ? 3 - k : k;
                path.push(dr !== 0 ? [step, line] : [line, step]);
            }
            const out = [];
            for (const [r, c] of path) {
                const cell = cells[r][c];
                if (!cell)
                    continue;
                const last = out[out.length - 1];
                if (last && !last.merged && last.v === cell.v) {
                    last.v *= 2;
                    last.merged = true;
                    last.absorbed = cell.tid;
                    gained += last.v;
                } else {
                    out.push({ tid: cell.tid, v: cell.v, merged: false, absorbed: 0, from: [r, c] });
                }
            }
            out.forEach((t, k) => {
                const [r, c] = path[k];
                if (t.merged || t.from[0] !== r || t.from[1] !== c)
                    moved = true;
                updates.push({ t: t, r: r, c: c });
            });
        }

        if (!moved)
            return false;

        for (const u of updates) {
            const i = game.indexOf(u.t.tid);
            tiles.setProperty(i, "r", u.r);
            tiles.setProperty(i, "c", u.c);
            tiles.setProperty(i, "fresh", false);
            tiles.setProperty(i, "pop", u.t.merged);
            if (u.t.merged) {
                tiles.setProperty(i, "v", u.t.v);
                const j = game.indexOf(u.t.absorbed);
                tiles.setProperty(j, "r", u.r);
                tiles.setProperty(j, "c", u.c);
                tiles.setProperty(j, "dying", true);
                if (u.t.v >= 2048 && !game.keepGoing)
                    game.won = true;
            }
        }
        game.score += gained;
        reaper.restart();
        if (game.spawning)
            game.spawn();
        if (!game.canMove())
            game.end();
        return true;
    }

    function canMove(): bool {
        const m = game.matrix();
        for (let r = 0; r < 4; r++)
            for (let c = 0; c < 4; c++) {
                if (!m[r][c])
                    return true;
                if (c < 3 && m[r][c] === m[r][c + 1])
                    return true;
                if (r < 3 && m[r][c] === m[r + 1][c])
                    return true;
            }
        return false;
    }

    function buryDead(): void {
        for (let i = tiles.count - 1; i >= 0; i--)
            if (tiles.get(i).dying)
                tiles.remove(i);
    }

    function end(): void {
        game.over = true;
        game.finished(game.score);
    }

    // Reaching 2048 is a win you can play on from.
    function carryOn(): void {
        game.won = false;
        game.keepGoing = true;
    }

    Component.onCompleted: game.restart()

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (game.won && !game.keepGoing)
            return;
        if (k === Qt.Key_Left || k === Qt.Key_A)
            game.move(0, -1);
        else if (k === Qt.Key_Right || k === Qt.Key_D)
            game.move(0, 1);
        else if (k === Qt.Key_Up || k === Qt.Key_W)
            game.move(-1, 0);
        else if (k === Qt.Key_Down || k === Qt.Key_S)
            game.move(1, 0);
        else
            return;
        event.accepted = true;
    }

    Timer {
        id: reaper

        interval: 140
        onTriggered: game.buryDead()
    }

    // Colour climbs with the value: surface, through primary, into tertiary.
    function tileColour(v: int): color {
        const step = Math.log2(v);
        if (step <= 1)
            return game.pal.m3surfaceContainerHighest;
        if (step <= 6)
            return Qt.tint(game.pal.m3surfaceContainerHighest, Qt.alpha(game.pal.m3primary, (step - 1) / 5));
        return Qt.tint(game.pal.m3primary, Qt.alpha(game.pal.m3tertiary, Math.min(1, (step - 6) / 5)));
    }

    Rectangle {
        id: board

        readonly property real gap: Math.max(6, size * 0.025)
        readonly property real size: Math.min(game.width, game.height)
        readonly property real cell: (size - gap * 5) / 4

        anchors.centerIn: parent
        width: size
        height: size
        radius: 14
        color: Qt.alpha(game.pal.m3onSurface, 0.06)

        Repeater {
            model: 16

            Rectangle {
                required property int index

                x: board.gap + (index % 4) * (board.cell + board.gap)
                y: board.gap + Math.floor(index / 4) * (board.cell + board.gap)
                width: board.cell
                height: board.cell
                radius: 10
                color: Qt.alpha(game.pal.m3onSurface, 0.05)
            }
        }

        Repeater {
            model: tiles

            Rectangle {
                id: tile

                required property int v
                required property int r
                required property int c
                required property bool dying
                required property bool fresh
                required property bool pop

                x: board.gap + tile.c * (board.cell + board.gap)
                y: board.gap + tile.r * (board.cell + board.gap)
                z: tile.dying ? 0 : 1
                width: board.cell
                height: board.cell
                radius: 10
                color: game.tileColour(tile.v)
                scale: tile.fresh ? 0 : 1

                Behavior on x {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Component.onCompleted: if (tile.fresh) grow.start()

                NumberAnimation {
                    id: grow

                    target: tile
                    property: "scale"
                    from: 0
                    to: 1
                    duration: 160
                    easing.type: Easing.OutBack
                }

                onVChanged: if (tile.pop) bump.restart()

                SequentialAnimation {
                    id: bump

                    NumberAnimation { target: tile; property: "scale"; to: 1.12; duration: 80 }
                    NumberAnimation { target: tile; property: "scale"; to: 1; duration: 90 }
                }

                Text {
                    anchors.centerIn: parent
                    text: tile.v
                    font.family: game.sans
                    font.weight: Font.Bold
                    font.pixelSize: board.cell * (tile.v >= 1024 ? 0.3 : tile.v >= 128 ? 0.36 : 0.44)
                    color: Math.log2(tile.v) >= 3 ? game.pal.m3onPrimary : game.pal.m3onSurface
                }
            }
        }
    }
}
