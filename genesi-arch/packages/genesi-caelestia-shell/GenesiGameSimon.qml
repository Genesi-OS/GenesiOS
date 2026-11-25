// GENESI — Simon, for the Game Center.
//
// Four pads light up in a sequence; play it back. Each round adds one more
// and plays a little faster. The score is the longest sequence repeated.
// Click the pads, or use the arrows (up, right, down, left, clockwise from
// the top-left pad) or 1-4.
//
// While the sequence is being shown, input is ignored -- a key pressed
// during the demonstration is somebody reacting to it, not answering it.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    property var seq: []
    property int at: 0
    // "idle" before the first round, "show" while it plays, "input" while
    // it is the player's turn.
    property string phase: "idle"
    property int lit: -1
    property int showing: 0

    property int score: 0
    property bool started: false
    property bool over: false
    readonly property bool won: false
    readonly property bool paused: false

    readonly property string hint: qsTr("Repeat the sequence · click, arrows or 1-4")
    readonly property string idleHint: qsTr("Click a pad or press Space to start")

    signal finished(int score)

    function restart(): void {
        game.seq = [];
        game.at = 0;
        game.phase = "idle";
        game.lit = -1;
        game.score = 0;
        game.started = false;
        game.over = false;
    }

    function begin(): void {
        if (game.phase !== "idle" || game.over)
            return;
        game.started = true;
        game.grow();
    }

    // One more step, then show the whole sequence.
    function grow(): void {
        game.seq = game.seq.concat([Math.floor(Math.random() * 4)]);
        game.at = 0;
        game.showing = 0;
        game.phase = "show";
        demo.restart();
    }

    function press(pad: int): void {
        if (game.phase === "idle") {
            game.begin();
            return;
        }
        if (game.phase !== "input" || game.over)
            return;
        game.flash(pad);
        if (game.seq[game.at] !== pad) {
            game.over = true;
            game.phase = "idle";
            game.finished(game.score);
            return;
        }
        game.at += 1;
        if (game.at >= game.seq.length) {
            game.score = game.seq.length;
            game.phase = "show";
            next.restart();
        }
    }

    function flash(pad: int): void {
        game.lit = pad;
        unlight.restart();
    }

    readonly property int beat: Math.max(260, 560 - game.seq.length * 22)

    Component.onCompleted: game.restart()

    // Plays the sequence: lit for a beat, dark for a third of one.
    Timer {
        id: demo

        interval: game.beat
        repeat: true
        onTriggered: {
            if (game.lit >= 0) {
                game.lit = -1;
                demo.interval = game.beat / 3;
                return;
            }
            demo.interval = game.beat;
            if (game.showing >= game.seq.length) {
                demo.stop();
                game.phase = "input";
                return;
            }
            game.lit = game.seq[game.showing];
            game.showing += 1;
        }
    }

    Timer {
        id: unlight

        interval: 220
        onTriggered: if (game.phase === "input")
            game.lit = -1
    }

    Timer {
        id: next

        interval: 650
        onTriggered: game.grow()
    }

    focus: true
    Keys.onPressed: event => {
        const map = {};
        map[Qt.Key_Up] = 0;
        map[Qt.Key_Right] = 1;
        map[Qt.Key_Down] = 2;
        map[Qt.Key_Left] = 3;
        map[Qt.Key_1] = 0;
        map[Qt.Key_2] = 1;
        map[Qt.Key_3] = 2;
        map[Qt.Key_4] = 3;
        if (event.key === Qt.Key_Space && game.phase === "idle" && !game.over) {
            game.begin();
            event.accepted = true;
        } else if (map[event.key] !== undefined && !game.over) {
            game.press(map[event.key]);
            event.accepted = true;
        }
    }

    Item {
        id: disc

        readonly property real size: Math.min(game.width, game.height) * 0.92

        anchors.centerIn: parent
        width: disc.size
        height: disc.size

        Repeater {
            model: 4

            Rectangle {
                id: pad

                required property int index
                readonly property color base: [game.pal.m3primary, game.pal.m3tertiary,
                                               game.pal.m3error, game.pal.m3secondary][index]
                readonly property bool glowing: game.lit === index

                x: (index === 1 || index === 2) ? disc.size / 2 + 5 : 0
                y: index >= 2 ? disc.size / 2 + 5 : 0
                width: disc.size / 2 - 5
                height: disc.size / 2 - 5
                topLeftRadius: index === 0 ? width : 14
                topRightRadius: index === 1 ? width : 14
                bottomRightRadius: index === 2 ? width : 14
                bottomLeftRadius: index === 3 ? width : 14
                color: pad.glowing ? Qt.lighter(pad.base, 1.25) : Qt.alpha(pad.base, 0.32)
                scale: pad.glowing ? 1.03 : 1

                Behavior on color {
                    ColorAnimation { duration: 90 }
                }
                Behavior on scale {
                    NumberAnimation { duration: 90 }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: {
                        game.forceActiveFocus();
                        game.press(pad.index);
                    }
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: disc.size * 0.34
            height: width
            radius: width / 2
            color: game.pal.m3surfaceContainer
            border.width: 6
            border.color: game.pal.m3surfaceContainerHigh

            Column {
                anchors.centerIn: parent

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: game.seq.length
                    color: game.pal.m3onSurface
                    font.family: game.sans
                    font.pixelSize: disc.size * 0.09
                    font.weight: Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: game.phase === "show" ? qsTr("watch") : game.phase === "input" ? qsTr("your turn") : ""
                    color: game.pal.m3onSurfaceVariant
                    font.family: game.sans
                    font.pixelSize: disc.size * 0.04
                }
            }
        }
    }
}
