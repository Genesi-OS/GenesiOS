// GENESI — Blocks: the falling-block game, for the Game Center. Not called by
// the name everybody knows it by, because that name is a trademark.
//
// Ten wide, twenty tall, the seven pieces dealt from a shuffled bag of
// seven (so there are never three S pieces in a row and no I for forty), a
// ghost of where the piece will land, and wall kicks on rotation so a piece
// against the wall still turns.
//
// ── What is drawn is one array ────────────────────────────────────────────
//
// The settled board and the falling piece are two things, and drawing them
// as two layers means two sets of squares that have to agree on where the
// grid is. `view` is the board with the piece and its ghost written into a
// copy, rebuilt on every change: two hundred squares, each bound to one
// number. That is cheap, and it cannot disagree with itself.
import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    readonly property int cols: 10
    readonly property int rows: 20

    // Seven shapes as cells in their own box. O does not turn.
    readonly property var shapes: [
        { size: 4, cells: [[0, 1], [1, 1], [2, 1], [3, 1]] },  // I
        { size: 2, cells: [[0, 0], [1, 0], [0, 1], [1, 1]] },  // O
        { size: 3, cells: [[1, 0], [0, 1], [1, 1], [2, 1]] },  // T
        { size: 3, cells: [[1, 0], [2, 0], [0, 1], [1, 1]] },  // S
        { size: 3, cells: [[0, 0], [1, 0], [1, 1], [2, 1]] },  // Z
        { size: 3, cells: [[0, 0], [0, 1], [1, 1], [2, 1]] },  // J
        { size: 3, cells: [[2, 0], [0, 1], [1, 1], [2, 1]] }   // L
    ]

    property var board: []
    property var view: []
    property var piece: null
    property var bag: []
    property int next: 0

    property int score: 0
    property int lines: 0
    readonly property int level: 1 + Math.floor(game.lines / 10)
    property bool started: false
    property bool over: false
    readonly property bool won: false
    property bool paused: false

    readonly property string hint: qsTr("←→ move · ↑ turn · ↓ drop · Space slam · P pause")
    readonly property string idleHint: qsTr("Press any arrow to start")

    signal finished(int score)

    function restart(): void {
        game.board = new Array(game.cols * game.rows).fill(0);
        game.bag = [];
        game.score = 0;
        game.lines = 0;
        game.over = false;
        game.paused = false;
        game.started = false;
        game.next = game.deal();
        game.spawn();
    }

    function deal(): int {
        if (!game.bag.length) {
            const bag = [0, 1, 2, 3, 4, 5, 6];
            for (let i = bag.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [bag[i], bag[j]] = [bag[j], bag[i]];
            }
            game.bag = bag;
        }
        const k = game.bag[0];
        game.bag = game.bag.slice(1);
        return k;
    }

    function cellsOf(p: var): var {
        const shape = game.shapes[p.k];
        return shape.cells.map(([x, y]) => {
            for (let t = 0; t < p.rot; t++) {
                if (p.k === 1)
                    break;
                [x, y] = [shape.size - 1 - y, x];
            }
            return [p.x + x, p.y + y];
        });
    }

    function fits(p: var): bool {
        for (const [x, y] of game.cellsOf(p)) {
            if (x < 0 || x >= game.cols || y >= game.rows)
                return false;
            if (y >= 0 && game.board[y * game.cols + x])
                return false;
        }
        return true;
    }

    function spawn(): void {
        const k = game.next;
        game.next = game.deal();
        // The I sits one row higher in its box, so it starts one row up.
        const p = { k: k, rot: 0, x: 3, y: k === 0 ? -1 : 0 };
        if (!game.fits(p)) {
            game.piece = p;
            game.over = true;
            game.redraw();
            game.finished(game.score);
            return;
        }
        game.piece = p;
        game.redraw();
    }

    function shift(dx: int, dy: int): bool {
        if (!game.piece || game.over)
            return false;
        const p = Object.assign({}, game.piece, { x: game.piece.x + dx, y: game.piece.y + dy });
        if (!game.fits(p))
            return false;
        game.piece = p;
        game.redraw();
        return true;
    }

    function turn(): void {
        if (!game.piece || game.over)
            return;
        const turned = Object.assign({}, game.piece, { rot: (game.piece.rot + 1) % 4 });
        // Kicks: in place, then a step each way, then two (the I needs two),
        // then one up for a piece turned against the floor.
        for (const [dx, dy] of [[0, 0], [-1, 0], [1, 0], [-2, 0], [2, 0], [0, -1]]) {
            const p = Object.assign({}, turned, { x: turned.x + dx, y: turned.y + dy });
            if (game.fits(p)) {
                game.piece = p;
                game.redraw();
                return;
            }
        }
    }

    function fall(): void {
        if (!game.shift(0, 1))
            game.lock();
    }

    function slam(): void {
        if (!game.piece || game.over)
            return;
        let dropped = 0;
        while (game.shift(0, 1))
            dropped++;
        game.score += dropped * 2;
        game.lock();
    }

    function lock(): void {
        const b = game.board.slice();
        for (const [x, y] of game.cellsOf(game.piece)) {
            if (y < 0) {
                // Settled above the top of the well.
                game.over = true;
                game.finished(game.score);
                return;
            }
            b[y * game.cols + x] = game.piece.k + 1;
        }
        game.board = b;
        game.clear();
        game.spawn();
    }

    function clear(): int {
        const kept = [];
        for (let y = 0; y < game.rows; y++) {
            const row = game.board.slice(y * game.cols, (y + 1) * game.cols);
            if (row.some(v => !v))
                kept.push(row);
        }
        const n = game.rows - kept.length;
        if (!n)
            return 0;
        const b = [];
        for (let i = 0; i < n; i++)
            b.push(...new Array(game.cols).fill(0));
        for (const row of kept)
            b.push(...row);
        game.board = b;
        game.score += [0, 100, 300, 500, 800][n] * game.level;
        game.lines += n;
        return n;
    }

    function ghostOf(p: var): var {
        let g = p;
        for (;;) {
            const lower = Object.assign({}, g, { y: g.y + 1 });
            if (!game.fits(lower))
                return g;
            g = lower;
        }
    }

    function redraw(): void {
        const v = game.board.slice();
        if (game.piece) {
            for (const [x, y] of game.cellsOf(game.ghostOf(game.piece)))
                if (y >= 0 && !v[y * game.cols + x])
                    v[y * game.cols + x] = -(game.piece.k + 1);
            for (const [x, y] of game.cellsOf(game.piece))
                if (y >= 0)
                    v[y * game.cols + x] = game.piece.k + 1;
        }
        game.view = v;
    }

    function colourOf(k: int): color {
        const p = game.pal;
        return [p.m3primary, p.m3secondary, p.m3tertiary, p.m3error,
                Qt.tint(p.m3primary, Qt.alpha(p.m3tertiary, 0.5)),
                Qt.tint(p.m3secondary, Qt.alpha(p.m3error, 0.45)),
                Qt.tint(p.m3tertiary, Qt.alpha(p.m3onSurface, 0.3))][k] ?? p.m3primary;
    }

    Component.onCompleted: game.restart()

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (game.over)
            return;
        if (k === Qt.Key_P && game.started) {
            game.paused = !game.paused;
            event.accepted = true;
            return;
        }
        if (game.paused)
            return;
        if (k === Qt.Key_Left || k === Qt.Key_A)
            game.shift(-1, 0);
        else if (k === Qt.Key_Right || k === Qt.Key_D)
            game.shift(1, 0);
        else if (k === Qt.Key_Up || k === Qt.Key_W || k === Qt.Key_X)
            game.turn();
        else if (k === Qt.Key_Down || k === Qt.Key_S) {
            if (game.shift(0, 1))
                game.score += 1;
        } else if (k === Qt.Key_Space)
            game.slam();
        else
            return;
        game.started = true;
        event.accepted = true;
    }

    Timer {
        interval: Math.max(90, 760 - (game.level - 1) * 70)
        repeat: true
        running: game.active && game.started && !game.over && !game.paused
        onTriggered: game.fall()
    }

    Row {
        anchors.centerIn: parent
        spacing: 16

        Rectangle {
            id: well

            readonly property real cell: Math.floor(Math.min((game.height - 4) / game.rows, (game.width - 110) / game.cols))

            width: well.cell * game.cols + 4
            height: well.cell * game.rows + 4
            radius: 10
            color: Qt.alpha(game.pal.m3onSurface, 0.05)
            border.width: 1
            border.color: Qt.alpha(game.pal.m3outlineVariant, 0.6)

            Repeater {
                model: game.cols * game.rows

                Rectangle {
                    required property int index
                    readonly property int v: game.view[index] ?? 0

                    x: 2 + (index % game.cols) * well.cell + 1
                    y: 2 + Math.floor(index / game.cols) * well.cell + 1
                    width: well.cell - 2
                    height: well.cell - 2
                    radius: 3
                    color: v > 0 ? game.colourOf(v - 1)
                        : v < 0 ? "transparent"
                        : Qt.alpha(game.pal.m3onSurface, 0.025)
                    border.width: v < 0 ? 1.5 : 0
                    border.color: v < 0 ? Qt.alpha(game.colourOf(-v - 1), 0.7) : "transparent"
                }
            }
        }

        Column {
            spacing: 14
            width: 90

            Text {
                text: qsTr("Next")
                color: game.pal.m3onSurfaceVariant
                font.family: game.sans
                font.pixelSize: 12
            }

            Item {
                width: 80
                height: 50

                Repeater {
                    model: game.shapes[game.next].cells

                    Rectangle {
                        required property var modelData
                        readonly property int size: game.shapes[game.next].size

                        x: (80 - size * 16) / 2 + modelData[0] * 16
                        y: modelData[1] * 16 + (game.next === 0 ? -8 : 4)
                        width: 15
                        height: 15
                        radius: 3
                        color: game.colourOf(game.next)
                    }
                }
            }

            Text {
                text: qsTr("Level")
                color: game.pal.m3onSurfaceVariant
                font.family: game.sans
                font.pixelSize: 12
            }
            Text {
                text: game.level
                color: game.pal.m3onSurface
                font.family: game.sans
                font.weight: Font.Bold
                font.pixelSize: 22
            }
            Text {
                text: qsTr("Lines")
                color: game.pal.m3onSurfaceVariant
                font.family: game.sans
                font.pixelSize: 12
            }
            Text {
                text: game.lines
                color: game.pal.m3onSurface
                font.family: game.sans
                font.weight: Font.Bold
                font.pixelSize: 22
            }
        }
    }
}
