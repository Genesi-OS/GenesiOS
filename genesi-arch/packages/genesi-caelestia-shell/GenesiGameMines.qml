// GENESI — Minesweeper, for the Game Center.
//
// ── The first click is always safe ────────────────────────────────────────
//
// Mines are laid AFTER the first click, and never on it or next to it, so
// every game opens a patch of board to work from. Laying them up front and
// moving one if it is hit still lets the first click land on a lone "1"
// with nothing to reason from, which is a coin toss wearing a puzzle's
// clothes.
//
// The score is the time, and lower is better -- the hub is told so through
// `lowerIsBetter`, which is the one thing about this game it has to know.
import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    readonly property int cols: 10
    readonly property int rows: 10
    readonly property int mines: 15
    readonly property bool lowerIsBetter: true

    // [{ mine, n, open, flag }], row by row.
    property var cells: []
    property bool laid: false

    property int score: 0
    property real startedAt: 0
    property bool started: false
    property bool over: false
    property bool won: false
    readonly property int flags: game.cells.filter(c => c.flag).length

    readonly property string hint: qsTr("Click to open · right-click to flag")
    readonly property string idleHint: ""

    signal finished(int score)

    function restart(): void {
        const cells = [];
        for (let i = 0; i < game.cols * game.rows; i++)
            cells.push({ mine: false, n: 0, open: false, flag: false });
        game.cells = cells;
        game.laid = false;
        game.score = 0;
        game.started = false;
        game.over = false;
        game.won = false;
    }

    function around(i: int): var {
        const x = i % game.cols;
        const y = Math.floor(i / game.cols);
        const out = [];
        for (let dy = -1; dy <= 1; dy++)
            for (let dx = -1; dx <= 1; dx++) {
                if (!dx && !dy)
                    continue;
                const nx = x + dx;
                const ny = y + dy;
                if (nx >= 0 && ny >= 0 && nx < game.cols && ny < game.rows)
                    out.push(ny * game.cols + nx);
            }
        return out;
    }

    // `at` is a list of cell indexes. The tests use it to lay a known board;
    // play uses lay(), which calls it with random ones.
    function layAt(at: var): void {
        const cells = game.cells.map(c => Object.assign({}, c));
        for (const i of at)
            cells[i].mine = true;
        for (let i = 0; i < cells.length; i++)
            cells[i].n = game.around(i).filter(j => cells[j].mine).length;
        game.cells = cells;
        game.laid = true;
    }

    function lay(safe: int): void {
        const banned = new Set([safe].concat(game.around(safe)));
        const pool = [];
        for (let i = 0; i < game.cols * game.rows; i++)
            if (!banned.has(i))
                pool.push(i);
        const at = [];
        while (at.length < game.mines && pool.length)
            at.push(pool.splice(Math.floor(Math.random() * pool.length), 1)[0]);
        game.layAt(at);
    }

    function open(i: int): void {
        if (game.over || game.won)
            return;
        if (!game.laid)
            game.lay(i);
        if (!game.started) {
            game.started = true;
            game.startedAt = Date.now();
        }
        const cells = game.cells.map(c => Object.assign({}, c));
        const cell = cells[i];
        if (cell.flag)
            return;

        // Clicking an open number with its flags all placed opens the rest
        // around it -- the move that makes a board go fast once you can read it.
        if (cell.open) {
            const near = game.around(i);
            if (cell.n === 0 || near.filter(j => cells[j].flag).length !== cell.n)
                return;
            for (const j of near)
                if (!cells[j].flag && !cells[j].open && game.flood(cells, j))
                    break;
        } else {
            game.flood(cells, i);
        }
        game.cells = cells;
        game.settle();
    }

    // Opens `i`, and outward from it while the squares are empty. Returns
    // true if it opened a mine.
    function flood(cells: var, i: int): bool {
        if (cells[i].mine) {
            cells[i].open = true;
            game.over = true;
            for (const c of cells)
                if (c.mine)
                    c.open = true;
            return true;
        }
        const todo = [i];
        while (todo.length) {
            const j = todo.pop();
            if (cells[j].open || cells[j].flag)
                continue;
            cells[j].open = true;
            if (cells[j].n === 0)
                for (const k of game.around(j))
                    if (!cells[k].open)
                        todo.push(k);
        }
        return false;
    }

    function settle(): void {
        if (game.over) {
            game.finished(-1);
            return;
        }
        // Against the mines actually laid, not the number there should be.
        const shut = game.cells.filter(c => !c.open).length;
        if (shut === game.cells.filter(c => c.mine).length) {
            game.won = true;
            game.score = Math.max(1, Math.round((Date.now() - game.startedAt) / 1000));
            game.finished(game.score);
        }
    }

    function flag(i: int): void {
        if (game.over || game.won || game.cells[i].open)
            return;
        const cells = game.cells.slice();
        cells[i] = Object.assign({}, cells[i], { flag: !cells[i].flag });
        game.cells = cells;
    }

    Component.onCompleted: game.restart()

    Timer {
        interval: 250
        repeat: true
        running: game.active && game.started && !game.over && !game.won
        onTriggered: game.score = Math.round((Date.now() - game.startedAt) / 1000)
    }

    readonly property var numberColours: [
        "transparent", game.pal.m3primary, game.pal.m3tertiary, game.pal.m3error,
        game.pal.m3secondary, game.pal.m3error, game.pal.m3tertiary,
        game.pal.m3onSurface, game.pal.m3onSurfaceVariant
    ]

    Rectangle {
        id: board

        readonly property real gap: 3
        readonly property real cell: Math.floor((Math.min(game.width, game.height) - gap * (game.cols + 1)) / game.cols)

        anchors.centerIn: parent
        width: gap + game.cols * (cell + gap)
        height: gap + game.rows * (cell + gap)
        radius: 12
        color: Qt.alpha(game.pal.m3onSurface, 0.05)

        Repeater {
            model: game.cols * game.rows

            Rectangle {
                id: square

                required property int index
                readonly property var st: game.cells[index] ?? { mine: false, n: 0, open: false, flag: false }

                x: board.gap + (index % game.cols) * (board.cell + board.gap)
                y: board.gap + Math.floor(index / game.cols) * (board.cell + board.gap)
                width: board.cell
                height: board.cell
                radius: 6
                color: square.st.open
                    ? (square.st.mine ? game.pal.m3error : Qt.alpha(game.pal.m3onSurface, 0.04))
                    : (hover.containsMouse && !game.over && !game.won
                       ? Qt.tint(game.pal.m3surfaceContainerHighest, Qt.alpha(game.pal.m3primary, 0.25))
                       : game.pal.m3surfaceContainerHighest)

                Behavior on color {
                    ColorAnimation { duration: 90 }
                }

                Text {
                    anchors.centerIn: parent
                    visible: square.st.open && !square.st.mine && square.st.n > 0
                    text: square.st.n
                    font.family: game.sans
                    font.weight: Font.Bold
                    font.pixelSize: board.cell * 0.5
                    color: game.numberColours[square.st.n]
                }

                // A mine: a dot with a ring. A flag: a pennant on a pole.
                Rectangle {
                    visible: square.st.open && square.st.mine
                    anchors.centerIn: parent
                    width: board.cell * 0.4
                    height: width
                    radius: width / 2
                    color: game.pal.m3onError
                }
                Item {
                    visible: square.st.flag && !square.st.open
                    anchors.centerIn: parent
                    width: board.cell * 0.44
                    height: board.cell * 0.5

                    Rectangle {
                        x: parent.width * 0.2
                        width: 2
                        height: parent.height
                        color: game.pal.m3onSurface
                    }
                    Rectangle {
                        x: parent.width * 0.2 + 2
                        width: parent.width * 0.7
                        height: parent.height * 0.5
                        radius: 2
                        color: game.pal.m3error
                    }
                }

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        game.forceActiveFocus();
                        if (mouse.button === Qt.RightButton)
                            game.flag(square.index);
                        else
                            game.open(square.index);
                    }
                }
            }
        }
    }
}
