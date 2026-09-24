// GENESI — Flappy Leaf, for the Game Center.
//
// The leaf from the desktop -- the same GenesiLeaf the pet is drawn with --
// flying between branches. Space, the up arrow or a click is a gust under
// it; gravity is everything else.
//
// ── Played in its own units ───────────────────────────────────────────────
//
// The world is 360 x 480 whatever size the drawer is, and drawn scaled. So
// the gap between branches is the same gap on a laptop and on a 4K screen,
// and a record means the same thing on both.
//
// ── Stepped by the frame, tested by the step ──────────────────────────────
//
// A FrameAnimation calls step(dt) once per frame with the real time since
// the last one; ci/plugins-test.py calls step() itself with numbers it
// chose. The ceiling stops the leaf rather than killing it -- flying into
// the sky is not a mistake anybody feels they made.
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
    readonly property real ground: 44
    readonly property real leafX: 100
    readonly property real radius: 15
    readonly property real gapH: 150
    readonly property real pipeW: 58
    readonly property real spacing: 205

    property real ly: 0
    property real vy: 0
    property var pipes: []

    property int score: 0
    property bool started: false
    property bool over: false
    readonly property bool won: false
    property bool paused: false

    readonly property string hint: qsTr("Space, ↑ or click to flap · P to pause")
    readonly property string idleHint: qsTr("Press Space to fly")

    signal finished(int score)

    function restart(): void {
        game.ly = game.worldH * 0.42;
        game.vy = 0;
        game.pipes = [];
        game.score = 0;
        game.over = false;
        game.started = false;
        game.paused = false;
    }

    function flap(): void {
        if (game.over || game.paused)
            return;
        game.started = true;
        game.vy = -390;
    }

    function speed(): real {
        return 150 + Math.min(game.score * 4, 100);
    }

    function step(dt: real): void {
        if (!game.started || game.over || game.paused)
            return;
        game.vy = Math.min(game.vy + 1350 * dt, 620);
        game.ly += game.vy * dt;
        if (game.ly < game.radius) {
            game.ly = game.radius;
            game.vy = 0;
        }

        const v = game.speed();
        const next = game.pipes
            .map(p => ({ x: p.x - v * dt, gap: p.gap, passed: p.passed }))
            .filter(p => p.x > -game.pipeW);
        if (!next.length || next[next.length - 1].x < game.worldW - game.spacing) {
            const lo = 90;
            const hi = game.worldH - game.ground - 90;
            next.push({ x: game.worldW + 10, gap: lo + Math.random() * (hi - lo), passed: false });
        }
        let scored = 0;
        for (const p of next)
            if (!p.passed && p.x + game.pipeW < game.leafX - game.radius) {
                p.passed = true;
                scored++;
            }
        game.pipes = next;
        game.score += scored;

        if (game.hits())
            game.end();
    }

    function hits(): bool {
        if (game.ly + game.radius >= game.worldH - game.ground)
            return true;
        for (const p of game.pipes) {
            if (game.leafX + game.radius > p.x && game.leafX - game.radius < p.x + game.pipeW) {
                if (game.ly - game.radius < p.gap - game.gapH / 2 || game.ly + game.radius > p.gap + game.gapH / 2)
                    return true;
            }
        }
        return false;
    }

    function end(): void {
        game.over = true;
        game.finished(game.score);
    }

    Component.onCompleted: game.restart()

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Space || k === Qt.Key_Up || k === Qt.Key_W) {
            if (game.over)
                return;
            game.flap();
        } else if (k === Qt.Key_P && game.started && !game.over) {
            game.paused = !game.paused;
        } else {
            return;
        }
        event.accepted = true;
    }

    FrameAnimation {
        running: game.active && game.started && !game.over && !game.paused
        onTriggered: game.step(Math.min(frameTime, 0.05))
    }

    Item {
        id: world

        width: game.worldW
        height: game.worldH
        anchors.centerIn: parent
        scale: Math.min(game.width / game.worldW, game.height / game.worldH)
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: 14
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.tint(game.pal.m3surfaceContainerHighest, Qt.alpha(game.pal.m3tertiary, 0.18)) }
                GradientStop { position: 1; color: game.pal.m3surfaceContainer }
            }
        }

        // Far hills, for depth. They drift slower than the branches.
        Repeater {
            model: 4

            Rectangle {
                required property int index

                x: ((index * 150 - (game.score * 37 + game.ly * 0.02)) % 600 + 600) % 600 - 120
                y: game.worldH - game.ground - 60 - (index % 2) * 24
                width: 220
                height: 160
                radius: 110
                color: Qt.alpha(game.pal.m3primary, 0.08)
            }
        }

        // The branches: a trunk from each edge, leafy where it ends.
        Repeater {
            model: game.pipes

            Item {
                id: pipe

                required property var modelData

                x: pipe.modelData.x
                width: game.pipeW
                height: game.worldH

                Rectangle {
                    y: -10
                    width: parent.width
                    height: pipe.modelData.gap - game.gapH / 2 + 10
                    radius: 10
                    color: Qt.tint(game.pal.m3secondaryContainer, Qt.alpha("#6b4f2f", 0.45))
                }
                Rectangle {
                    x: -6
                    y: pipe.modelData.gap - game.gapH / 2 - 18
                    width: parent.width + 12
                    height: 18
                    radius: 9
                    color: game.pal.m3primary
                    opacity: 0.85
                }
                Rectangle {
                    y: pipe.modelData.gap + game.gapH / 2
                    width: parent.width
                    height: game.worldH - y
                    radius: 10
                    color: Qt.tint(game.pal.m3secondaryContainer, Qt.alpha("#6b4f2f", 0.45))
                }
                Rectangle {
                    x: -6
                    y: pipe.modelData.gap + game.gapH / 2
                    width: parent.width + 12
                    height: 18
                    radius: 9
                    color: game.pal.m3primary
                    opacity: 0.85
                }
            }
        }

        Rectangle {
            y: game.worldH - game.ground
            width: game.worldW
            height: game.ground
            color: Qt.tint(game.pal.m3surfaceContainerHigh, Qt.alpha(game.pal.m3primary, 0.18))

            Rectangle {
                width: parent.width
                height: 4
                color: Qt.alpha(game.pal.m3primary, 0.5)
            }
        }

        GenesiLeaf {
            id: flyer

            size: 40
            x: game.leafX - flyer.width / 2
            y: game.ly - flyer.height / 2
            pal: game.pal
            mood: game.over ? "sick" : game.vy < -200 ? "happy" : "normal"
            level: 3
            rotation: Math.max(-25, Math.min(70, game.vy / 9))
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 22
            visible: game.started
            text: game.score
            color: game.pal.m3onSurface
            font.family: game.sans
            font.pixelSize: 44
            font.weight: Font.Bold
            style: Text.Outline
            styleColor: Qt.alpha(game.pal.m3surface, 0.6)
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: {
            game.forceActiveFocus();
            game.flap();
        }
    }
}
