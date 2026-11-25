// GENESI — Snake, for the Game Center.
//
// Plain QtQuick and nothing else, like the other three games: the shell
// hands in its palette and its fonts, and the game reads nothing from
// caelestia. That is what lets ci/plugins-test.py load it offscreen and
// play it, rather than trusting it because it parses.
//
// ── Turns are queued, not assigned ────────────────────────────────────────
//
// A tick is ~110 ms and a quick player presses two keys inside one. Writing
// each press straight into `dir` keeps only the last, so up-then-left from
// moving right becomes a single left -- straight back into your own neck,
// which reads as the game killing you for no reason. Each press is checked
// against the turn BEFORE it and queued; one comes off per tick.
import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    readonly property int cols: 18
    readonly property int rows: 18

    property var body: []
    property var food: ({ x: 0, y: 0 })
    property var dir: ({ x: 1, y: 0 })
    property var queue: []

    property int score: 0
    property bool started: false
    property bool over: false
    property bool won: false
    property bool paused: false

    readonly property string hint: qsTr("Arrows or WASD to steer · P to pause")
    readonly property string idleHint: qsTr("Press an arrow to start")

    signal finished(int score)

    function restart(): void {
        const y = Math.floor(game.rows / 2);
        game.body = [{ x: 6, y: y }, { x: 5, y: y }, { x: 4, y: y }];
        game.dir = { x: 1, y: 0 };
        game.queue = [];
        game.score = 0;
        game.over = false;
        game.won = false;
        game.paused = false;
        game.started = false;
        game.place();
    }

    function place(): void {
        const free = [];
        for (let y = 0; y < game.rows; y++)
            for (let x = 0; x < game.cols; x++)
                if (!game.body.some(s => s.x === x && s.y === y))
                    free.push({ x: x, y: y });
        if (free.length === 0) {
            game.won = true;
            game.end();
            return;
        }
        game.food = free[Math.floor(Math.random() * free.length)];
    }

    function turn(dx: int, dy: int): void {
        if (game.over)
            return;
        const last = game.queue.length ? game.queue[game.queue.length - 1] : game.dir;
        // Straight back into yourself, or the way you are already going.
        if ((dx === -last.x && dy === -last.y) || (dx === last.x && dy === last.y)) {
            game.started = true;
            return;
        }
        if (game.queue.length < 3)
            game.queue = game.queue.concat([{ x: dx, y: dy }]);
        game.started = true;
    }

    function step(): void {
        if (game.queue.length) {
            game.dir = game.queue[0];
            game.queue = game.queue.slice(1);
        }
        const head = game.body[0];
        const next = { x: head.x + game.dir.x, y: head.y + game.dir.y };
        if (next.x < 0 || next.y < 0 || next.x >= game.cols || next.y >= game.rows) {
            game.end();
            return;
        }
        const eating = next.x === game.food.x && next.y === game.food.y;
        // The tail moves out of the way on the same tick the head moves in,
        // so chasing your own tail is legal -- unless you are growing.
        const rest = eating ? game.body : game.body.slice(0, -1);
        if (rest.some(s => s.x === next.x && s.y === next.y)) {
            game.end();
            return;
        }
        game.body = [next].concat(rest);
        if (eating) {
            game.score += 10;
            game.place();
        }
    }

    function end(): void {
        game.over = true;
        game.finished(game.score);
    }

    Component.onCompleted: game.restart()

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Left || k === Qt.Key_A)
            game.turn(-1, 0);
        else if (k === Qt.Key_Right || k === Qt.Key_D)
            game.turn(1, 0);
        else if (k === Qt.Key_Up || k === Qt.Key_W)
            game.turn(0, -1);
        else if (k === Qt.Key_Down || k === Qt.Key_S)
            game.turn(0, 1);
        else if (k === Qt.Key_P && game.started && !game.over)
            game.paused = !game.paused;
        else
            return;
        event.accepted = true;
    }

    Timer {
        // Faster as it grows, down to a floor a person can still steer at.
        interval: Math.max(62, 118 - game.score / 10 * 2)
        repeat: true
        running: game.active && game.started && !game.over && !game.paused
        onTriggered: game.step()
    }

    Rectangle {
        id: board

        readonly property real cell: Math.floor(Math.min(game.width / game.cols, game.height / game.rows))

        anchors.centerIn: parent
        width: board.cell * game.cols
        height: board.cell * game.rows
        radius: 10
        color: Qt.alpha(game.pal.m3onSurface, 0.04)
        border.width: 1
        border.color: Qt.alpha(game.pal.m3outlineVariant, 0.6)
        clip: true

        // A faint checker, so speed reads as squares going by.
        Repeater {
            model: game.cols * game.rows

            Rectangle {
                required property int index

                visible: (index % game.cols + Math.floor(index / game.cols)) % 2 === 0
                x: (index % game.cols) * board.cell
                y: Math.floor(index / game.cols) * board.cell
                width: board.cell
                height: board.cell
                color: Qt.alpha(game.pal.m3onSurface, 0.025)
            }
        }

        Rectangle {
            id: apple

            x: game.food.x * board.cell + board.cell * 0.15
            y: game.food.y * board.cell + board.cell * 0.15
            width: board.cell * 0.7
            height: width
            radius: width / 2
            color: game.pal.m3tertiary

            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: game.active
                NumberAnimation { to: 1.15; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.9; duration: 420; easing.type: Easing.InOutSine }
            }
        }

        Repeater {
            model: game.body.length

            Rectangle {
                required property int index

                readonly property var seg: game.body[index] ?? { x: 0, y: 0 }
                readonly property bool head: index === 0

                x: seg.x * board.cell + 1
                y: seg.y * board.cell + 1
                width: board.cell - 2
                height: board.cell - 2
                radius: head ? board.cell * 0.4 : board.cell * 0.28
                // Fades toward the tail, so the direction of travel is
                // readable at a glance.
                color: head ? game.pal.m3primary
                    : Qt.tint(game.pal.m3primary,
                              Qt.alpha(game.pal.m3surfaceContainerHighest,
                                       Math.min(0.55, index / Math.max(1, game.body.length) * 0.6)))

                Row {
                    visible: parent.head
                    anchors.centerIn: parent
                    spacing: board.cell * 0.18
                    rotation: game.dir.x === 1 ? 90 : game.dir.x === -1 ? -90 : game.dir.y === 1 ? 180 : 0

                    Repeater {
                        model: 2

                        Rectangle {
                            width: board.cell * 0.16
                            height: width
                            radius: width / 2
                            color: game.pal.m3onPrimary
                        }
                    }
                }
            }
        }
    }
}
