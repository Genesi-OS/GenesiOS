// GENESI — Breakout, for the Game Center.
//
// A paddle, a ball and a wall of bricks in the scheme's colours. The mouse
// moves the paddle, and so do the arrows; Space or a click serves. Three
// balls; clear the wall and the next one comes in faster.
//
// ── Where the ball hits the paddle is where it goes ───────────────────────
//
// A paddle that only reflects makes every rally the same angle, and the
// game is decided by the first serve. The outgoing angle follows how far
// from the middle the ball landed, the way it did in the arcade, so the
// paddle is aimed rather than merely held up.
//
// Played in its own 360 x 480 units and drawn scaled, like Flappy Leaf.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    readonly property real worldW: 360
    readonly property real worldH: 480
    readonly property int cols: 8
    readonly property int rows: 5
    readonly property real brickH: 16
    readonly property real brickGap: 4
    readonly property real brickTop: 56
    readonly property real side: 12
    readonly property real brickW: (game.worldW - 2 * game.side - (game.cols - 1) * game.brickGap) / game.cols
    readonly property real padW: 72
    readonly property real padH: 10
    readonly property real padY: game.worldH - 34
    readonly property real r: 6

    property real px: game.worldW / 2
    property real bx: 0
    property real by: 0
    property real vx: 0
    property real vy: 0
    property bool served: false
    property var bricks: []
    property int lives: 3
    property int level: 1
    property bool holdLeft: false
    property bool holdRight: false

    property int score: 0
    property bool started: false
    property bool over: false
    readonly property bool won: false
    property bool paused: false

    readonly property string hint: qsTr("Mouse or ←→ to move · Space to serve · P to pause")
    readonly property string idleHint: qsTr("Space or click to serve")

    signal finished(int score)

    function speed(): real {
        return 250 + (game.level - 1) * 35;
    }

    function wall(): void {
        game.bricks = new Array(game.cols * game.rows).fill(1);
    }

    function restart(): void {
        game.score = 0;
        game.lives = 3;
        game.level = 1;
        game.over = false;
        game.paused = false;
        game.started = false;
        game.px = game.worldW / 2;
        game.wall();
        game.rest();
    }

    // The ball back on the paddle, waiting to be served.
    function rest(): void {
        game.served = false;
        game.bx = game.px;
        game.by = game.padY - game.r - 1;
        game.vx = 0;
        game.vy = 0;
    }

    function serve(): void {
        if (game.over || game.served)
            return;
        game.started = true;
        game.served = true;
        const v = game.speed();
        game.vx = v * 0.45;
        game.vy = -v * 0.89;
    }

    function movePaddle(x: real): void {
        game.px = Math.max(game.padW / 2, Math.min(game.worldW - game.padW / 2, x));
        if (!game.served)
            game.bx = game.px;
    }

    function step(dt: real): void {
        if (game.over || game.paused)
            return;
        if (game.holdLeft !== game.holdRight)
            game.movePaddle(game.px + (game.holdRight ? 1 : -1) * 430 * dt);
        if (!game.served)
            return;

        let x = game.bx + game.vx * dt;
        let y = game.by + game.vy * dt;
        let vx = game.vx;
        let vy = game.vy;

        if (x < game.r) {
            x = game.r;
            vx = Math.abs(vx);
        } else if (x > game.worldW - game.r) {
            x = game.worldW - game.r;
            vx = -Math.abs(vx);
        }
        if (y < game.r) {
            y = game.r;
            vy = Math.abs(vy);
        }

        // The paddle, only on the way down.
        if (vy > 0 && y + game.r >= game.padY && game.by + game.r <= game.padY + game.padH
                && Math.abs(x - game.px) <= game.padW / 2 + game.r) {
            const off = Math.max(-1, Math.min(1, (x - game.px) / (game.padW / 2)));
            const v = game.speed();
            const angle = off * 65 * Math.PI / 180;
            vx = v * Math.sin(angle);
            vy = -v * Math.cos(angle);
            y = game.padY - game.r;
        }

        // A brick: the first one the ball is inside.
        const col = Math.floor((x - game.side) / (game.brickW + game.brickGap));
        const row = Math.floor((y - game.brickTop) / (game.brickH + game.brickGap));
        for (const [c, rr] of [[col, row], [Math.floor((x - game.side + game.r) / (game.brickW + game.brickGap)), row],
                               [Math.floor((x - game.side - game.r) / (game.brickW + game.brickGap)), row],
                               [col, Math.floor((y - game.brickTop - game.r) / (game.brickH + game.brickGap))],
                               [col, Math.floor((y - game.brickTop + game.r) / (game.brickH + game.brickGap))]]) {
            if (c < 0 || c >= game.cols || rr < 0 || rr >= game.rows)
                continue;
            const i = rr * game.cols + c;
            if (!game.bricks[i])
                continue;
            const b = game.bricks.slice();
            b[i] = 0;
            game.bricks = b;
            game.score += 10 * (game.rows - rr) * game.level;
            vy = -vy;
            break;
        }

        game.bx = x;
        game.by = y;
        game.vx = vx;
        game.vy = vy;

        if (game.by > game.worldH + game.r) {
            game.lives -= 1;
            if (game.lives <= 0) {
                game.over = true;
                game.finished(game.score);
            } else {
                game.rest();
            }
            return;
        }

        if (!game.bricks.some(b => b)) {
            game.level += 1;
            game.score += 100 * game.level;
            game.wall();
            game.rest();
        }
    }

    Component.onCompleted: game.restart()

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (game.over)
            return;
        if (k === Qt.Key_Left || k === Qt.Key_A)
            game.holdLeft = true;
        else if (k === Qt.Key_Right || k === Qt.Key_D)
            game.holdRight = true;
        else if (k === Qt.Key_Space || k === Qt.Key_Up)
            game.serve();
        else if (k === Qt.Key_P && game.started)
            game.paused = !game.paused;
        else
            return;
        game.started = true;
        event.accepted = true;
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A)
            game.holdLeft = false;
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D)
            game.holdRight = false;
    }

    FrameAnimation {
        running: game.active && game.started && !game.over && !game.paused
        onTriggered: game.step(Math.min(frameTime, 0.033))
    }

    Item {
        id: world

        width: game.worldW
        height: game.worldH
        anchors.centerIn: parent
        scale: Math.min(game.width / game.worldW, game.height / game.worldH)

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.alpha(game.pal.m3onSurface, 0.04)
            border.width: 1
            border.color: Qt.alpha(game.pal.m3outlineVariant, 0.6)
        }

        Repeater {
            model: game.cols * game.rows

            Rectangle {
                required property int index

                readonly property int row: Math.floor(index / game.cols)

                visible: !!game.bricks[index]
                x: game.side + (index % game.cols) * (game.brickW + game.brickGap)
                y: game.brickTop + row * (game.brickH + game.brickGap)
                width: game.brickW
                height: game.brickH
                radius: 4
                color: [game.pal.m3error, game.pal.m3tertiary, game.pal.m3primary,
                        game.pal.m3secondary, Qt.tint(game.pal.m3primary, Qt.alpha(game.pal.m3tertiary, 0.5))][row % 5]
            }
        }

        Rectangle {
            x: game.px - game.padW / 2
            y: game.padY
            width: game.padW
            height: game.padH
            radius: game.padH / 2
            color: game.pal.m3onSurface
        }

        Rectangle {
            x: game.bx - game.r
            y: game.by - game.r
            width: game.r * 2
            height: width
            radius: game.r
            color: game.pal.m3primary
        }

        Row {
            x: 14
            y: 18
            spacing: 6

            Repeater {
                model: game.lives

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: game.pal.m3primary
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 12
            text: qsTr("Level %1").arg(game.level)
            color: game.pal.m3onSurfaceVariant
            font.family: game.sans
            font.pixelSize: 13
        }
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            const p = world.mapFromItem(pointer, mouse.x, mouse.y);
            game.movePaddle(p.x);
        }
        onPressed: {
            game.forceActiveFocus();
            game.serve();
        }
    }
}
