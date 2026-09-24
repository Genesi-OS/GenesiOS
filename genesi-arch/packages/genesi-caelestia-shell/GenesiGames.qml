// GENESI — what is inside the Game Center drawer: the shelf of games, the
// game being played, and what is said when it ends.
//
// Plain QtQuick, like the games. GenesiGameCenter.qml is the part that knows
// about windows, the screen corner, the palette and the file the records are
// kept in; this knows about none of them, and is handed what it draws with.
// That split is what lets ci/plugins-test.py lay the whole drawer out
// offscreen and play it.
//
// ── Every game answers to the same small shape ────────────────────────────
//
//   score, started, over, won, paused   what the hub reads
//   hint, idleHint                      what it says under and over the board
//   restart()                           what Enter does after it ends
//   finished(score)                     score < 0 means "lost, no score"
//   lowerIsBetter                       only Minesweeper, whose score is time
//
// The end-of-game card, the pause veil and the score chips are drawn HERE,
// once, over whichever game is loaded -- four copies of a dialog is four
// dialogs that drift apart.
pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: hub

    property var pal: ({})
    property string sans: ""
    property string mono: ""
    property string icons: "Material Symbols Rounded"

    // Whether the drawer is on screen. A game only ticks while it is.
    property bool shown: true

    // { id: number }. Handed in by the shell from its file, and written back
    // through `played`, never in here -- one writer.
    property var best: ({})
    property var plays: ({})
    property bool corner: true

    property string current: ""
    property bool lastWasBest: false

    readonly property var games: [
        { id: "snake", name: qsTr("Snake"), blurb: qsTr("Eat, grow, don't bite yourself"), file: "GenesiGameSnake.qml" },
        { id: "2048", name: "2048", blurb: qsTr("Slide the tiles, double them up"), file: "GenesiGame2048.qml" },
        { id: "mines", name: qsTr("Minesweeper"), blurb: qsTr("Read the numbers, flag the mines"), file: "GenesiGameMines.qml" },
        { id: "blocks", name: qsTr("Blocks"), blurb: qsTr("Fill the lines before the well fills"), file: "GenesiGameBlocks.qml" }
    ]
    readonly property var game: hub.games.find(g => g.id === hub.current) ?? null
    readonly property Item board: stage.item
    readonly property int totalPlays: Object.keys(hub.plays).reduce((n, k) => n + (hub.plays[k] || 0), 0)

    signal played(string id, int score, bool lowerIsBetter)
    signal closeRequested
    signal cornerToggled(bool on)

    function open(id: string): void {
        hub.lastWasBest = false;
        hub.current = id;
        stage.forceActiveFocus();
    }

    function leave(): void {
        hub.current = "";
        hub.forceActiveFocus();
    }

    function bestText(id: string): string {
        const b = hub.best[id];
        if (b === undefined)
            return qsTr("Not played yet");
        return id === "mines" ? qsTr("Best %1s").arg(b) : qsTr("Best %1").arg(Number(b).toLocaleString(Qt.locale(), "f", 0));
    }

    function record(score: int): void {
        const g = hub.current;
        const low = hub.board?.lowerIsBetter ?? false;
        const old = hub.best[g];
        hub.lastWasBest = score >= 0 && (score > 0 || low)
            && (old === undefined || (low ? score < old : score > old));
        hub.played(g, score, low);
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (hub.current)
                hub.leave();
            else
                hub.closeRequested();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                   && hub.board && (hub.board.over || hub.board.won)) {
            if (hub.board.won && hub.board.carryOn)
                hub.board.carryOn();
            else
                hub.board.restart();
            hub.lastWasBest = false;
            event.accepted = true;
        }
    }

    component Glyph: Text {
        property real size: 20

        font.family: hub.icons
        font.pixelSize: size
        color: hub.pal.m3onSurface
    }

    component Chip: Rectangle {
        property alias text: label.text
        property bool strong: false

        implicitWidth: label.implicitWidth + 20
        implicitHeight: 28
        radius: 14
        color: strong ? hub.pal.m3primaryContainer : Qt.alpha(hub.pal.m3onSurface, 0.07)

        Text {
            id: label

            anchors.centerIn: parent
            font.family: hub.sans
            font.pixelSize: 13
            font.weight: Font.Medium
            color: parent.strong ? hub.pal.m3onPrimaryContainer : hub.pal.m3onSurface
        }
    }

    component Button: Rectangle {
        id: button

        property alias text: label.text
        property bool filled: false

        signal clicked

        implicitWidth: label.implicitWidth + 32
        implicitHeight: 40
        radius: 20
        color: button.filled
            ? (area.containsMouse ? Qt.lighter(hub.pal.m3primary, 1.1) : hub.pal.m3primary)
            : (area.containsMouse ? Qt.alpha(hub.pal.m3onSurface, 0.12) : Qt.alpha(hub.pal.m3onSurface, 0.07))

        Text {
            id: label

            anchors.centerIn: parent
            font.family: hub.sans
            font.pixelSize: 14
            font.weight: Font.Medium
            color: button.filled ? hub.pal.m3onPrimary : hub.pal.m3onSurface
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // ── The shelf ─────────────────────────────────────────────────────────
    Item {
        id: shelf

        anchors.fill: parent
        visible: opacity > 0
        opacity: hub.current ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: 140 }
        }

        Row {
            id: title

            anchors.left: parent.left
            anchors.top: parent.top
            spacing: 12

            Rectangle {
                width: 44
                height: 44
                radius: 14
                color: hub.pal.m3primaryContainer

                Glyph {
                    anchors.centerIn: parent
                    text: "sports_esports"
                    size: 26
                    color: hub.pal.m3onPrimaryContainer
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: qsTr("Game Center")
                    font.family: hub.sans
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    color: hub.pal.m3onSurface
                }
                Text {
                    text: hub.totalPlays === 0 ? qsTr("Something quick, one corner away")
                        : hub.totalPlays === 1 ? qsTr("1 game played")
                        : qsTr("%1 games played").arg(hub.totalPlays)
                    font.family: hub.sans
                    font.pixelSize: 13
                    color: hub.pal.m3onSurfaceVariant
                }
            }
        }

        Glyph {
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
            text: "close"
            color: closeArea.containsMouse ? hub.pal.m3onSurface : hub.pal.m3onSurfaceVariant

            MouseArea {
                id: closeArea

                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                onClicked: hub.closeRequested()
            }
        }

        Grid {
            id: grid

            anchors.top: title.bottom
            anchors.topMargin: 20
            anchors.left: parent.left
            anchors.right: parent.right
            columns: 2
            spacing: 12

            readonly property real tileW: (width - spacing) / 2

            Repeater {
                model: hub.games

                Rectangle {
                    id: tile

                    required property var modelData
                    required property int index

                    width: grid.tileW
                    height: grid.tileW * 0.98
                    radius: 18
                    color: tileArea.containsMouse
                        ? Qt.tint(hub.pal.m3surfaceContainerHigh, Qt.alpha(hub.pal.m3primary, 0.12))
                        : hub.pal.m3surfaceContainerHigh
                    border.width: 1
                    border.color: tileArea.containsMouse ? Qt.alpha(hub.pal.m3primary, 0.5) : "transparent"
                    scale: tileArea.pressed ? 0.97 : 1

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 90 }
                    }

                    // A little picture of the game, drawn in the scheme's
                    // own colours rather than shipped as an image that would
                    // be the one thing on the desktop in the wrong ones.
                    Item {
                        id: art

                        anchors.top: parent.top
                        anchors.topMargin: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 32
                        height: parent.height * 0.5

                        readonly property real u: Math.min(width / 7, height / 4.2)

                        Repeater {
                            model: tile.modelData.id === "snake"
                                ? [[0, 3, 0], [1, 3, 0], [2, 3, 0], [3, 3, 0], [3, 2, 0], [3, 1, 0], [4, 1, 0], [5, 1, 1], [6, 3, 2]]
                                : tile.modelData.id === "blocks"
                                ? [[1, 3, 0], [2, 3, 0], [3, 3, 0], [4, 3, 0], [5, 3, 1], [5, 2, 1], [6, 3, 1], [2, 2, 2], [3, 2, 2], [3, 1, 2], [4, 0, 3], [4, 1, 3]]
                                : []

                            Rectangle {
                                required property var modelData

                                x: (art.width - art.u * 7) / 2 + modelData[0] * art.u + 1
                                y: modelData[1] * art.u + 1
                                width: art.u - 2
                                height: art.u - 2
                                radius: tile.modelData.id === "snake" ? art.u * 0.3 : 3
                                color: tile.modelData.id === "snake"
                                    ? [hub.pal.m3primary, hub.pal.m3primary, hub.pal.m3tertiary][modelData[2]]
                                    : [hub.pal.m3primary, hub.pal.m3secondary, hub.pal.m3tertiary, hub.pal.m3error][modelData[2]]
                                opacity: tile.modelData.id === "snake" && modelData[2] === 0 ? 0.55 + modelData[0] * 0.06 : 1
                            }
                        }

                        Grid {
                            visible: tile.modelData.id === "2048"
                            anchors.centerIn: parent
                            columns: 3
                            spacing: 4

                            Repeater {
                                model: [2, 4, 0, 8, 16, 2, 0, 32, 64]

                                Rectangle {
                                    required property int modelData

                                    width: art.height / 3 - 4
                                    height: width
                                    radius: 6
                                    color: modelData
                                        ? Qt.tint(hub.pal.m3surfaceContainerHighest, Qt.alpha(hub.pal.m3primary, Math.min(1, Math.log2(modelData) / 6)))
                                        : Qt.alpha(hub.pal.m3onSurface, 0.06)

                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.modelData > 0
                                        text: parent.modelData
                                        font.family: hub.sans
                                        font.weight: Font.Bold
                                        font.pixelSize: parent.width * 0.38
                                        color: parent.modelData >= 8 ? hub.pal.m3onPrimary : hub.pal.m3onSurface
                                    }
                                }
                            }
                        }

                        Grid {
                            visible: tile.modelData.id === "mines"
                            anchors.centerIn: parent
                            columns: 4
                            spacing: 3

                            Repeater {
                                model: ["", "1", "", "", "1", "2", "f", "", "", "1", "", "1", "", "", "", "*"]

                                Rectangle {
                                    required property string modelData
                                    required property int index

                                    width: art.height / 4 - 3
                                    height: width
                                    radius: 4
                                    color: modelData === "*" ? hub.pal.m3error
                                        : (modelData === "" && index % 3 === 0) || modelData === "f"
                                        ? hub.pal.m3surfaceContainerHighest
                                        : Qt.alpha(hub.pal.m3onSurface, 0.06)

                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.modelData === "1" || parent.modelData === "2"
                                        text: parent.modelData
                                        font.family: hub.sans
                                        font.weight: Font.Bold
                                        font.pixelSize: parent.width * 0.55
                                        color: parent.modelData === "1" ? hub.pal.m3primary : hub.pal.m3tertiary
                                    }
                                    Rectangle {
                                        visible: parent.modelData === "f"
                                        anchors.centerIn: parent
                                        width: parent.width * 0.4
                                        height: parent.width * 0.3
                                        radius: 2
                                        color: hub.pal.m3error
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        spacing: 2

                        Text {
                            text: tile.modelData.name
                            font.family: hub.sans
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: hub.pal.m3onSurface
                        }
                        Text {
                            width: parent.width
                            text: tile.modelData.blurb
                            elide: Text.ElideRight
                            font.family: hub.sans
                            font.pixelSize: 12
                            color: hub.pal.m3onSurfaceVariant
                        }
                        Text {
                            topPadding: 4
                            text: hub.bestText(tile.modelData.id)
                            font.family: hub.sans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: hub.best[tile.modelData.id] !== undefined ? hub.pal.m3primary : hub.pal.m3outline
                        }
                    }

                    MouseArea {
                        id: tileArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hub.open(tile.modelData.id)
                    }
                }
            }
        }

        // Whether the corner of the screen opens this. Here, and not only in
        // Genesi Center, because the moment somebody decides the corner is
        // in their way is the moment it has just opened on them.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 52
            radius: 16
            color: Qt.alpha(hub.pal.m3onSurface, 0.05)

            Glyph {
                id: cornerGlyph

                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "south_west"
                size: 18
                color: hub.pal.m3onSurfaceVariant
            }

            Text {
                anchors.left: cornerGlyph.right
                anchors.leftMargin: 10
                anchors.right: toggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Open when the pointer hits the bottom-left corner")
                elide: Text.ElideRight
                font.family: hub.sans
                font.pixelSize: 13
                color: hub.pal.m3onSurface
            }

            Rectangle {
                id: toggle

                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24
                radius: 12
                color: hub.corner ? hub.pal.m3primary : Qt.alpha(hub.pal.m3onSurface, 0.15)

                Rectangle {
                    x: hub.corner ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: 9
                    color: hub.corner ? hub.pal.m3onPrimary : hub.pal.m3onSurfaceVariant

                    Behavior on x {
                        NumberAnimation { duration: 120 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: hub.cornerToggled(!hub.corner)
                }
            }
        }
    }

    // ── A game ────────────────────────────────────────────────────────────
    Item {
        id: play

        anchors.fill: parent
        visible: opacity > 0
        opacity: hub.current ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 140 }
        }

        Row {
            id: bar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 36
            spacing: 10

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: backArea.containsMouse ? Qt.alpha(hub.pal.m3onSurface, 0.1) : "transparent"

                Glyph {
                    anchors.centerIn: parent
                    text: "arrow_back"
                }

                MouseArea {
                    id: backArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: hub.leave()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: bar.width - 36 - scoreChip.width - bestChip.width - bar.spacing * 3
                text: hub.game?.name ?? ""
                elide: Text.ElideRight
                font.family: hub.sans
                font.pixelSize: 18
                font.weight: Font.Bold
                color: hub.pal.m3onSurface
            }

            Chip {
                id: scoreChip

                anchors.verticalCenter: parent.verticalCenter
                strong: true
                text: hub.current === "mines"
                    ? qsTr("%1s").arg(hub.board?.score ?? 0)
                    : Number(hub.board?.score ?? 0).toLocaleString(Qt.locale(), "f", 0)
            }
            Chip {
                id: bestChip

                anchors.verticalCenter: parent.verticalCenter
                text: hub.bestText(hub.current)
            }
        }

        Loader {
            id: stage

            anchors.top: bar.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: hintText.top
            anchors.bottomMargin: 12
            focus: true

            // setSource with the palette, not `source:` and the palette
            // assigned in onLoaded. A game is built -- every colour binding in
            // it evaluated -- before onLoaded runs, so it was built against an
            // empty palette first: a warning per square on every open, and a
            // first frame drawn in no colours at all.
            Connections {
                target: hub

                function onCurrentChanged(): void {
                    if (hub.game)
                        stage.setSource(hub.game.file, {
                            pal: hub.pal,
                            sans: hub.sans,
                            mono: hub.mono
                        });
                    else
                        stage.source = "";
                }
            }

            onLoaded: {
                const g = stage.item;
                // Bound from here on, so a scheme change repaints the game.
                g.pal = Qt.binding(() => hub.pal);
                g.sans = Qt.binding(() => hub.sans);
                g.mono = Qt.binding(() => hub.mono);
                g.active = Qt.binding(() => hub.shown && hub.current !== "");
                g.focus = true;
                g.finished.connect(hub.record);
            }
        }

        Text {
            id: hintText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            horizontalAlignment: Text.AlignHCenter
            text: hub.board?.hint ?? ""
            elide: Text.ElideRight
            font.family: hub.sans
            font.pixelSize: 12
            color: hub.pal.m3onSurfaceVariant
        }

        // Before the first key: what starts it.
        Rectangle {
            anchors.centerIn: stage
            visible: !!hub.board && !hub.board.started && !hub.board.over && (hub.board.idleHint ?? "") !== ""
            width: idle.implicitWidth + 32
            height: 40
            radius: 20
            color: Qt.alpha(hub.pal.m3surface, 0.9)

            Text {
                id: idle

                anchors.centerIn: parent
                text: hub.board?.idleHint ?? ""
                font.family: hub.sans
                font.pixelSize: 14
                color: hub.pal.m3onSurface
            }
        }

        // Paused, or it ended.
        Rectangle {
            id: veil

            readonly property bool ended: !!hub.board && (hub.board.over || hub.board.won)

            anchors.fill: stage
            radius: 12
            visible: opacity > 0
            opacity: veil.ended || (hub.board?.paused ?? false) ? 1 : 0
            color: Qt.alpha(hub.pal.m3surface, 0.82)

            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }

            MouseArea {
                anchors.fill: parent
                enabled: veil.visible
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                width: parent.width - 40

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !veil.ended ? qsTr("Paused")
                        : hub.board.won ? (hub.current === "2048" ? qsTr("You made 2048!") : qsTr("Cleared!"))
                        : hub.current === "mines" ? qsTr("Boom.")
                        : qsTr("Game over")
                    font.family: hub.sans
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    color: hub.pal.m3onSurface
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: veil.ended && !(hub.current === "mines" && !hub.board.won)
                    text: hub.current === "mines"
                        ? qsTr("in %1 seconds").arg(hub.board?.score ?? 0)
                        : qsTr("%1 points").arg(Number(hub.board?.score ?? 0).toLocaleString(Qt.locale(), "f", 0))
                    font.family: hub.sans
                    font.pixelSize: 16
                    color: hub.pal.m3onSurfaceVariant
                }

                Chip {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: veil.ended && hub.lastWasBest
                    strong: true
                    text: qsTr("New best")
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !veil.ended
                    text: qsTr("P to carry on")
                    font.family: hub.sans
                    font.pixelSize: 14
                    color: hub.pal.m3onSurfaceVariant
                }

                Item {
                    width: 1
                    height: 6
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: veil.ended
                    spacing: 10

                    Button {
                        visible: !!hub.board && hub.board.won && !!hub.board.carryOn
                        filled: true
                        text: qsTr("Keep going")
                        onClicked: {
                            hub.board.carryOn();
                            stage.forceActiveFocus();
                        }
                    }
                    Button {
                        filled: !(hub.board && hub.board.won && hub.board.carryOn)
                        text: qsTr("Play again")
                        onClicked: {
                            hub.lastWasBest = false;
                            hub.board.restart();
                            stage.forceActiveFocus();
                        }
                    }
                    Button {
                        text: qsTr("All games")
                        onClicked: hub.leave()
                    }
                }
            }
        }
    }
}
