// GENESI — Memory, for the Game Center.
//
// Sixteen cards face down, eight pairs. Turn two; a pair stays up, anything
// else turns back. The score is how many turns it took, and lower is better
// -- the hub is told so through `lowerIsBetter`, like Minesweeper's time.
//
// ── Symbols drawn, not typed ──────────────────────────────────────────────
//
// The faces are four shapes in two colours, drawn from rectangles. An emoji
// or an icon-font glyph would look different on every machine, or not at
// all on one without the font -- and a memory game whose two halves of a
// pair render differently is not a game.
//
// While two unmatched cards are showing, the board takes no clicks: a third
// click in that moment is the classic way this game cheats its player out
// of a turn they did not mean to take.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: game

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property bool active: false

    readonly property bool lowerIsBetter: true

    // [{ sym, up, done }]
    property var cards: []
    property int first: -1
    property bool locked: false
    property int moves: 0

    property int score: 0
    property bool started: false
    property bool over: false
    property bool won: false
    readonly property bool paused: false

    readonly property string hint: qsTr("Click two cards · find all eight pairs")
    readonly property string idleHint: ""

    signal finished(int score)

    function restart(): void {
        const syms = [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7];
        for (let i = syms.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [syms[i], syms[j]] = [syms[j], syms[i]];
        }
        game.cards = syms.map(s => ({ sym: s, up: false, done: false }));
        game.first = -1;
        game.locked = false;
        game.moves = 0;
        game.score = 0;
        game.started = false;
        game.over = false;
        game.won = false;
    }

    function pick(i: int): void {
        if (game.locked || game.won)
            return;
        const c = game.cards[i];
        if (!c || c.up || c.done)
            return;
        game.started = true;
        const cards = game.cards.slice();
        cards[i] = Object.assign({}, c, { up: true });
        game.cards = cards;
        if (game.first < 0) {
            game.first = i;
            return;
        }
        game.moves += 1;
        game.score = game.moves;
        const a = game.first;
        game.first = -1;
        if (cards[a].sym === cards[i].sym) {
            const done = game.cards.slice();
            done[a] = Object.assign({}, done[a], { done: true });
            done[i] = Object.assign({}, done[i], { done: true });
            game.cards = done;
            if (done.every(x => x.done)) {
                game.won = true;
                game.finished(game.moves);
            }
        } else {
            game.locked = true;
            cover.restart();
        }
    }

    // Turn the unmatched pair back over.
    function settle(): void {
        game.cards = game.cards.map(c => c.done ? c : Object.assign({}, c, { up: false }));
        game.locked = false;
    }

    Component.onCompleted: game.restart()

    Timer {
        id: cover

        interval: 750
        onTriggered: game.settle()
    }

    focus: true

    Grid {
        id: board

        readonly property real gap: 10
        readonly property real cell: Math.floor((Math.min(game.width, game.height) - gap * 3) / 4)

        anchors.centerIn: parent
        columns: 4
        spacing: gap

        Repeater {
            model: game.cards.length

            Item {
                id: card

                required property int index
                readonly property var st: game.cards[index] ?? { sym: 0, up: false, done: false }
                property real flip: card.st.up || card.st.done ? 1 : 0

                width: board.cell
                height: board.cell

                Behavior on flip {
                    NumberAnimation { duration: 240; easing.type: Easing.InOutQuad }
                }

                // One face at a time, squeezed to nothing and back: a turn.
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: card.flip > 0.5
                        ? (card.st.done ? Qt.tint(game.pal.m3surfaceContainerHighest, Qt.alpha(game.pal.m3primary, 0.18)) : game.pal.m3surfaceContainerHighest)
                        : (hover.containsMouse && !game.locked ? Qt.lighter(game.pal.m3primaryContainer, 1.15) : game.pal.m3primaryContainer)
                    border.width: card.st.done ? 2 : 0
                    border.color: Qt.alpha(game.pal.m3primary, 0.6)
                    transform: Scale {
                        origin.x: card.width / 2
                        xScale: Math.max(0.02, Math.abs(Math.cos(card.flip * Math.PI)))
                    }

                    // The back: a small leaf-ish diamond, the house mark.
                    Rectangle {
                        visible: card.flip <= 0.5
                        anchors.centerIn: parent
                        width: parent.width * 0.22
                        height: width
                        rotation: 45
                        radius: 3
                        color: Qt.alpha(game.pal.m3onPrimaryContainer, 0.35)
                    }

                    // The face.
                    Item {
                        visible: card.flip > 0.5
                        anchors.centerIn: parent
                        width: parent.width * 0.46
                        height: width

                        readonly property color ink: card.st.sym < 4 ? game.pal.m3primary : game.pal.m3tertiary
                        readonly property int shape: card.st.sym % 4

                        Rectangle {
                            // circle, square, diamond, ring
                            anchors.centerIn: parent
                            width: parent.shape === 2 ? parent.width * 0.72 : parent.width
                            height: width
                            rotation: parent.shape === 2 ? 45 : 0
                            radius: parent.shape === 0 || parent.shape === 3 ? width / 2 : parent.shape === 1 ? 6 : 4
                            color: parent.shape === 3 ? "transparent" : parent.ink
                            border.width: parent.shape === 3 ? width * 0.18 : 0
                            border.color: parent.ink
                        }
                    }
                }

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        game.forceActiveFocus();
                        game.pick(card.index);
                    }
                }
            }
        }
    }
}
