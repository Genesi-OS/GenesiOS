#!/usr/bin/env python3
"""
The Game Center's games load, and play by their rules.

Nothing in the build compiles the shell's QML, so a green package says
nothing about whether a game opens -- let alone whether 2048 merges a tile
twice in one move. The games are plain QtQuick for exactly this reason: they
are handed the palette instead of reaching for caelestia's, so they load here,
offscreen, with nothing stubbed.

Each case below is a rule a first attempt at that game gets wrong, played
rather than read:

  Snake    two quick turns inside one tick both happen; reversing into your
           own neck is ignored; chasing your own tail is legal; the wall kills
  2048     [4,4,8,_] slides to [8,8,_,_], not [16,_,_,_]; a move that moves
           nothing is not a move; a full board with no pair is the end
  Mines    the first click is never a mine, nor next to one; zeros flood;
           a number with its flags placed opens the rest; clearing wins
  Blocks   full rows clear and score by the level; a piece against the wall
           still turns; the bag deals every piece once per seven
  Hub      each game loads through the shelf; a finished game reports its
           score once; a record is a record in the right direction

Any warning Qt prints while loading or playing is a failure too: in QML a
warning is usually a binding that has silently stopped working.

    python ci/game-center-test.py [shots-dir]

With a directory, it also writes a picture of the shelf and of each game.
"""
import io
import os
import re
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.normpath(os.path.join(HERE, "..", "packages",
                                      "genesi-caelestia-shell"))
GAMES = ("GenesiGameSnake.qml", "GenesiGame2048.qml", "GenesiGameMines.qml",
         "GenesiGameBlocks.qml")
PURE = GAMES + ("GenesiGames.qml",)
SHOTS = sys.argv[1] if len(sys.argv) > 1 else ""

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (
        "" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== game center ==")

# ── They have to stay testable ────────────────────────────────────────────
#
# The moment a game imports caelestia -- for a colour, an animation, a font
# -- it stops loading here, and every rule below goes back to being assumed.
for name in PURE:
    body = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, name),
                                           encoding="utf-8").read())
    imports = re.findall(r"^\s*import\s+(\S+)", body, re.M)
    check(f"{name} imports only QtQuick", imports == ["QtQuick"], imports)

try:
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtQuick import QQuickView
except ImportError:
    print("  FAIL PySide6 is not installed -- nothing here can be played")
    sys.exit(1)

warnings = []
qInstallMessageHandler(lambda mode, ctx, msg: warnings.append(
    f"{os.path.basename(ctx.file or '')}:{ctx.line}: {msg}"))

app = QGuiApplication(sys.argv)

PALETTE = """
    QtObject {
        id: pal
        property color m3surface: "#141318"
        property color m3surfaceContainer: "#211f24"
        property color m3surfaceContainerHigh: "#2b292f"
        property color m3surfaceContainerHighest: "#36343a"
        property color m3onSurface: "#e6e1e9"
        property color m3onSurfaceVariant: "#cac4cf"
        property color m3outline: "#948f99"
        property color m3outlineVariant: "#49454e"
        property color m3primary: "#7fd8a4"
        property color m3onPrimary: "#003921"
        property color m3primaryContainer: "#005232"
        property color m3onPrimaryContainer: "#9bf5bf"
        property color m3secondary: "#b5ccba"
        property color m3secondaryContainer: "#374b3e"
        property color m3tertiary: "#a3cddb"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
    }
"""


def run(title, root_item, script, size=(460, 560), shot=""):
    """Load `root_item` in a window and run `script` against it.

    The script runs in QML's own JavaScript, with the game in `g`, and
    reports through ok(name, cond, detail) -- so a rule is tested with the
    same engine, the same arrays and the same numbers the shell uses.
    """
    qml = """
import QtQuick
Item {
    id: host
    width: %d; height: %d
    property var results: []
    function ok(name, cond, detail) {
        host.results = host.results.concat([[name, !!cond, detail === undefined ? "" : String(detail)]]);
    }
    property QtObject pal: %s
    Rectangle { anchors.fill: parent; color: host.pal.m3surfaceContainer }
    %s
    function play() {
%s
    }
}
""" % (size[0], size[1], PALETTE, root_item, script)
    before = len(warnings)
    view = QQuickView()
    view.engine().addImportPath(SHELL)
    comp = QQmlComponent(view.engine())
    comp.setData(qml.encode("utf-8"), QUrl.fromLocalFile(
        os.path.join(SHELL, "_game_center_test.qml")))
    if comp.isError():
        check(f"{title}: loads", False, "; ".join(e.toString() for e in comp.errors()))
        return
    host = comp.create()
    if host is None:
        check(f"{title}: loads", False, "; ".join(e.toString() for e in comp.errors()))
        return
    view.setContent(QUrl(), comp, host)
    view.resize(*size)
    view.show()
    app.processEvents()
    from PySide6.QtCore import QMetaObject, Qt
    QMetaObject.invokeMethod(host, "play", Qt.DirectConnection)
    app.processEvents()
    for name, cond, detail in host.property("results").toVariant() \
            if hasattr(host.property("results"), "toVariant") else host.property("results"):
        check(f"{title}: {name}", cond, detail)
    if shot and SHOTS:
        for _ in range(20):
            app.processEvents()
        view.grabWindow().save(os.path.join(SHOTS, shot))
    # Qt on Windows ships no fonts and says so once. That is the machine
    # this was run on, not the game.
    new = [w for w in warnings[before:]
           if "QFontDatabase: Cannot find font directory" not in w]
    check(f"{title}: Qt printed no warnings", not new, "\n         ".join(new))
    view.close()
    view.deleteLater()


def game(file, extra=""):
    # Built with the palette, the way the shelf builds it -- see the
    # Loader in GenesiGames.qml for why "after" is not the same thing.
    return """
    %s {
        id: gm
        anchors.fill: parent
        anchors.margins: 16
        pal: host.pal
        sans: "sans-serif"
        active: true
        %s
    }
    readonly property Item g: gm
""" % (file[:-4], extra)


# ── Snake ─────────────────────────────────────────────────────────────────
run("snake", game("GenesiGameSnake.qml"), """
        g.restart();
        ok("starts three long, heading right", g.body.length === 3 && g.dir.x === 1);

        g.turn(-1, 0);
        ok("reversing into its own neck is ignored", g.queue.length === 0);

        g.turn(0, -1);
        g.turn(-1, 0);
        ok("two turns inside one tick are both kept", g.queue.length === 2);
        const h = g.body[0];
        g.food = { x: 0, y: 0 };
        g.step();
        g.step();
        ok("...and both happen, one per tick",
           g.body[0].x === h.x - 1 && g.body[0].y === h.y - 1 && g.dir.x === -1,
           JSON.stringify(g.body[0]));

        g.restart();
        const y = g.body[0].y;
        g.food = { x: 7, y: y };
        g.step();
        ok("eating grows it and scores ten", g.body.length === 4 && g.score === 10);

        // A 2x2 loop: the head moves into the square the tail is leaving.
        g.body = [{ x: 5, y: 5 }, { x: 5, y: 6 }, { x: 4, y: 6 }, { x: 4, y: 5 }];
        g.dir = { x: -1, y: 0 };
        g.queue = [];
        g.food = { x: 0, y: 0 };
        g.over = false;
        g.step();
        ok("chasing its own tail is legal", !g.over && g.body[0].x === 4 && g.body[0].y === 5);

        let ended = -1;
        g.finished.connect(s => ended = s);
        g.body = [{ x: g.cols - 1, y: 3 }, { x: g.cols - 2, y: 3 }];
        g.dir = { x: 1, y: 0 };
        g.score = 30;
        g.over = false;
        g.step();
        ok("the wall ends it, and the score is reported", g.over && ended === 30, ended);
""", shot="snake.png")

# ── 2048 ──────────────────────────────────────────────────────────────────
run("2048", game("GenesiGame2048.qml", "spawning: false"), """
        function row(m) { g.load([m, [0,0,0,0], [0,0,0,0], [0,0,0,0]]); }

        row([2, 2, 2, 2]);
        g.score = 0;
        g.move(0, -1);
        ok("[2,2,2,2] left is [4,4,_,_] and scores 8",
           JSON.stringify(g.matrix()[0]) === "[4,4,0,0]" && g.score === 8,
           JSON.stringify(g.matrix()[0]) + " " + g.score);

        g.buryDead();
        row([4, 4, 8, 0]);
        g.move(0, -1);
        ok("a tile made this move does not merge again: [4,4,8,_] -> [8,8,_,_]",
           JSON.stringify(g.matrix()[0]) === "[8,8,0,0]", JSON.stringify(g.matrix()[0]));

        g.buryDead();
        row([2, 0, 0, 2]);
        g.move(0, 1);
        ok("[2,_,_,2] right is [_,_,_,4]", JSON.stringify(g.matrix()[0]) === "[0,0,0,4]",
           JSON.stringify(g.matrix()[0]));

        g.buryDead();
        g.load([[2,0,0,0], [2,0,0,0], [4,0,0,0], [4,0,0,0]]);
        g.move(-1, 0);
        const col = g.matrix().map(r => r[0]);
        ok("a column slides up the same way: [2,2,4,4] -> [4,8,_,_]",
           JSON.stringify(col) === "[4,8,0,0]", JSON.stringify(col));

        g.buryDead();
        row([2, 4, 0, 0]);
        ok("a move that moves nothing is not a move", g.move(0, -1) === false);

        g.load([[2,4,2,4], [4,2,4,2], [2,4,2,4], [4,2,4,2]]);
        ok("a full board with no pair is the end", !g.canMove());

        g.load([[1024,1024,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0]]);
        g.move(0, -1);
        ok("making 2048 is a win you can play on from", g.won && !g.over);
        g.carryOn();
        ok("...and carrying on clears it", !g.won);

        g.spawning = true;
        g.restart();
""", shot="2048.png")

# ── Minesweeper ───────────────────────────────────────────────────────────
run("mines", game("GenesiGameMines.qml"), """
        let lostOn = 0;
        for (let t = 0; t < 60; t++) {
            g.restart();
            g.open(55);
            const near = [55].concat(g.around(55));
            if (g.over || near.some(i => g.cells[i].mine))
                lostOn++;
        }
        ok("the first click is never a mine, nor next to one (60 boards)", lostOn === 0, lostOn);

        g.restart();
        ok("the board has the mines it says", (() => { g.open(0); return g.cells.filter(c => c.mine).length; })() === g.mines);

        // A known board: two mines in the top-right corner.
        g.restart();
        g.layAt([8, 9]);
        g.open(90);
        ok("a zero floods open everything it can reach",
           g.cells.filter(c => c.open).length > 80 && !g.over);

        const seven = 7;
        ok("the square beside the mines shows its count",
           g.cells[seven].open && g.cells[seven].n === 1, JSON.stringify(g.cells[seven]));

        // The flood above opened every safe square, so that was a win.
        ok("opening every safe square wins, with a time",
           g.cells.filter(c => !c.open).length === 2 && g.won && g.score >= 1,
           g.won + " " + g.score);

        g.restart();
        g.layAt([0, 2, 20, 22]);
        let lost = 0;
        g.finished.connect(s => lost = s);
        g.flag(0);
        g.flag(2);
        g.flag(20);
        g.flag(22);
        g.open(11);
        g.open(11);
        ok("a number with its flags placed opens what is around it",
           g.around(11).every(i => [0, 2, 20, 22].includes(i) || g.cells[i].open),
           JSON.stringify(g.around(11).map(i => g.cells[i].open)));

        // A numbered square first: opening a zero would flood the whole
        // board and win it before the mine could be reached.
        g.restart();
        g.layAt([44]);
        g.open(34);
        g.open(44);
        ok("a mine ends it, reported as no score", g.over && lost === -1, lost);
        ok("...and shows where every mine was", g.cells[44].open);
""", shot="mines.png")

# ── Blocks ────────────────────────────────────────────────────────────────
run("blocks", game("GenesiGameBlocks.qml"), """
        g.restart();
        const dealt = [];
        g.bag = [];
        for (let i = 0; i < 14; i++)
            dealt.push(g.deal());
        const counts = [0, 0, 0, 0, 0, 0, 0];
        dealt.forEach(k => counts[k]++);
        ok("the bag deals every piece once per seven", counts.every(n => n === 2), JSON.stringify(counts));

        g.restart();
        const b = new Array(200).fill(0);
        for (let x = 0; x < 10; x++) {
            b[19 * 10 + x] = 1;
            b[18 * 10 + x] = 2;
        }
        b[17 * 10 + 4] = 3;
        g.board = b;
        const n = g.clear();
        ok("two full rows clear, and score 300 at level one", n === 2 && g.score === 300 && g.lines === 2,
           n + " " + g.score);
        ok("...and what was above them falls", g.board[19 * 10 + 4] === 3);

        g.restart();
        g.piece = { k: 0, rot: 1, x: -2, y: 5 };
        ok("an upright I can sit against the left wall", g.fits(g.piece));
        g.turn();
        ok("...and still turns there, kicked off the wall", g.piece.rot === 2 && g.fits(g.piece),
           JSON.stringify(g.piece));

        g.restart();
        g.piece = { k: 1, rot: 0, x: 4, y: 0 };
        g.score = 0;
        g.slam();
        const filled = g.board.filter(v => v).length;
        ok("a slam lands the piece on the floor and pays for the drop",
           filled === 4 && g.board[19 * 10 + 4] === 2 && g.score === 36, filled + " " + g.score);

        g.restart();
        let ended = -1;
        g.finished.connect(s => ended = s);
        const full = new Array(200).fill(0);
        for (let i = 0; i < 40; i++)
            full[i] = (i % 10 === 9) ? 0 : 5;
        g.board = full;
        g.spawn();
        ok("a piece with nowhere to appear ends it", g.over && ended === g.score, ended);
""", size=(460, 600), shot="blocks.png")

# ── The shelf, and a game through it ─────────────────────────────────────
run("hub", """
    GenesiGames {
        id: hubItem
        anchors.fill: parent
        anchors.margins: 20
        pal: host.pal
        sans: "sans-serif"
        best: ({ snake: 120, mines: 40 })
        plays: ({ snake: 3, mines: 2 })
    }
    readonly property Item g: hubItem
""", """
        const said = [];
        g.played.connect((id, score, low) => said.push([id, score, low]));

        ok("the shelf lists four games", g.games.length === 4);
        ok("best scores read the right way round",
           g.bestText("snake") === "Best 120" && g.bestText("mines") === "Best 40s"
           && g.bestText("blocks") === "Not played yet", g.bestText("snake") + " / " + g.bestText("mines"));

        for (const id of ["snake", "2048", "mines", "blocks"]) {
            g.open(id);
            ok(id + " loads through the shelf", !!g.board && g.current === id);
        }

        g.open("snake");
        g.board.finished(150);
        ok("a better score is a record", g.lastWasBest);
        g.board.finished(20);
        ok("a worse one is not", !g.lastWasBest);

        g.open("mines");
        g.board.finished(30);
        ok("in Minesweeper a LOWER time is the record", g.lastWasBest);
        g.board.finished(-1);
        ok("...and a loss is never one", !g.lastWasBest);

        ok("each finished game is reported exactly once",
           said.length === 4 && said[0][0] === "snake" && said[0][1] === 150
           && said[2][0] === "mines" && said[2][2] === true, JSON.stringify(said));

        g.leave();
        ok("leaving goes back to the shelf", g.current === "");
""", size=(460, 640), shot="shelf.png")

print()
if fails:
    print(f"game center: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("game center: OK")
