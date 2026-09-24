#!/usr/bin/env python3
"""
The shell's plugins load, and behave by their rules: the Game Center's games
play by theirs, and the leaf feels what the machine is doing.

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
  Flappy   a flap lifts, gravity pulls, a branch passed scores, a branch or
           the ground ends it, the sky does not
  Breakout walls bounce; where the ball lands on the paddle is where it
           goes; a brick scores; a lost ball costs a life; a cleared wall
           is the next level
  Memory   eight pairs; a match stays up, a miss turns back; the score is
           turns, lower is better
  Simon    each round is one longer; the right answer advances, a wrong
           one ends it
  Hub      each game loads through the shelf; a finished game reports its
           score once; a record is a record in the right direction
  Leaf     hot beats asleep, music beats asleep; the level curve; XP from
           games without a windfall on first sight; it talks in the
           machine's language; every mood at every stage draws cleanly
  Weather  every WMO code open-meteo sends lands on the right sky; a clear
           day draws nothing; every sky draws cleanly
  Vinyl    the arm parks off the record, lands on the lead-in, creeps in
           through the track; the platter spins up and coasts down
  Wrapped  a week's sums, the period before, the streak, the busiest day,
           who the hours say you are; an empty week says so instead of
           showing zeros; the story steps through and closes at the end
  Wiring   the CPU fraction is turned into percent before the leaf's rules
           read it; every plugin the shell asks about is one the store can
           switch on, at the same path

Any warning Qt prints while loading or playing is a failure too: in QML a
warning is usually a binding that has silently stopped working.

    python ci/plugins-test.py [shots-dir]

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
         "GenesiGameBlocks.qml", "GenesiGameFlappy.qml", "GenesiGameBreakout.qml",
         "GenesiGameMemory.qml", "GenesiGameSimon.qml")
PURE = GAMES + ("GenesiGames.qml", "GenesiPetMind.qml", "GenesiWeatherFx.qml",
                 "GenesiWrappedMath.qml", "GenesiWrappedStory.qml")
# The leaf is drawn with Shapes, which is still Qt and nothing of caelestia's.
DRAWN = ("GenesiLeaf.qml",)
SHOTS = sys.argv[1] if len(sys.argv) > 1 else ""

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (
        "" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== shell plugins ==")

# ── They have to stay testable ────────────────────────────────────────────
#
# The moment a game imports caelestia -- for a colour, an animation, a font
# -- it stops loading here, and every rule below goes back to being assumed.
for name in PURE:
    body = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, name),
                                           encoding="utf-8").read())
    imports = re.findall(r"^\s*import\s+(\S+)", body, re.M)
    check(f"{name} imports only QtQuick", imports == ["QtQuick"], imports)
# The turntable masks the cover round with QtQuick.Effects -- still Qt.
for name in ("GenesiVinylDeck.qml",):
    body = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, name),
                                           encoding="utf-8").read())
    imports = re.findall(r"^\s*import\s+(\S+)", body, re.M)
    check(f"{name} imports only QtQuick and its Effects",
          imports == ["QtQuick", "QtQuick.Effects"], imports)
for name in DRAWN:
    body = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, name),
                                           encoding="utf-8").read())
    imports = re.findall(r"^\s*import\s+(\S+)", body, re.M)
    check(f"{name} imports only QtQuick and its Shapes",
          imports == ["QtQuick", "QtQuick.Shapes"], imports)

# ── Every game on the shelf is a game the package installs ────────────────
#
# The shelf names a file per game and loads it by name. A game added to the
# shelf and not to the patcher's GAMECENTER_FILES is a tile that opens onto
# nothing on the installed system -- and everything here would still pass,
# because here the file is right beside the shelf.
hub_src = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, "GenesiGames.qml"),
                                          encoding="utf-8").read())
shelf_files = set(re.findall(r'file:\s*"([^"]+\.qml)"', hub_src))
patcher_src = io.open(os.path.join(HERE, "caelestia-patches.py"), encoding="utf-8").read()
m = re.search(r"^GAMECENTER_FILES = \((.*?)\)", patcher_src, re.S | re.M)
installed = set(re.findall(r'"([^"]+\.qml)"', m.group(1))) if m else set()
check("every game on the shelf is installed by the package",
      shelf_files and shelf_files <= installed, sorted(shelf_files - installed))
check("...and every game file here is on the shelf",
      set(GAMES) <= shelf_files, sorted(set(GAMES) - shelf_files))

# ── Wiring the tests below cannot see ─────────────────────────────────────
#
# The leaf's rules are played with numbers in percent. The service they come
# from, caelestia's Cpu, reports a FRACTION -- 0.93, not 93 -- and the rules
# would read that as a machine that is never busy. The conversion lives in
# the window, which does not load here, so it is checked as text.
pet_src = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, "GenesiPet.qml"),
                                          encoding="utf-8").read())
check("the leaf turns the CPU fraction into percent before it judges it",
      re.search(r"Cpu\.percentage\s*\*\s*100", pet_src) is not None
      and not re.search(r"cpu:\s*Cpu\.percentage\b(?!\s*\*)", pet_src))

# Every plugin the shell asks about has a card in the store that switches it
# on, writing exactly the file the switch reads.
catalog_path = os.path.normpath(os.path.join(HERE, "..", "packages", "genesi-store",
                                             "catalog", "catalog.json"))
import json  # noqa: E402
catalog = json.load(io.open(catalog_path, encoding="utf-8"))
store_paths = {a.get("path") for i in catalog["items"] if i.get("section") == "plugins"
               for a in i.get("actions", []) if a.get("action") == "file"}
asked = set()
for name in os.listdir(SHELL):
    if name.endswith(".qml"):
        body = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, name),
                                               encoding="utf-8").read())
        asked |= set(re.findall(r'GenesiPluginSwitch\s*\{[^}]*?plugin:\s*"([^"]+)"', body, re.S))
check("the shell asks about every plugin there is",
      {"game-center", "leaf", "live-weather", "vinyl", "wrapped"} <= asked, sorted(asked))

# The Nexus Plugins page lists plugins by hand. One that exists and is not
# listed is a plugin with no switch in the settings; one listed that does
# not exist is a switch that does nothing.
page = re.sub(r"//[^\n]*", "", io.open(os.path.join(SHELL, "PluginsPage.qml"),
                                        encoding="utf-8").read())
listed = set(re.findall(r'\bid:\s*"([a-z-]+)"', page))
check("the Plugins page lists exactly the plugins there are",
      listed == asked, f"page {sorted(listed)} vs shell {sorted(asked)}")
check("...and holds a switch for each of them",
      set(re.findall(r'"([a-z-]+)":\s*\w+', page.split("switches:")[1].split("})")[0]))
      == listed if "switches:" in page else False, "switches map")
for plugin in sorted(asked):
    want = "~/.config/genesi/plugins/%s.json" % plugin
    check(f"the store can switch on '{plugin}', at the path the shell reads",
          want in store_paths, f"{want} not in {sorted(store_paths)}")

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

# ── Flappy Leaf ───────────────────────────────────────────────────────────
run("flappy", game("GenesiGameFlappy.qml"), """
        g.restart();
        const y0 = g.ly;
        g.step(0.1);
        ok("nothing moves before the first flap", g.ly === y0 && !g.over);

        g.flap();
        g.pipes = [];
        g.step(0.05);
        ok("a flap lifts it", g.ly < y0, g.ly + " vs " + y0);
        for (let i = 0; i < 12; i++)
            g.step(0.05);
        ok("...and gravity brings it back down", g.vy > 0, g.vy);

        g.restart();
        g.flap();
        g.ly = g.radius + 2;
        g.vy = -600;
        g.pipes = [{ x: 300, gap: 200, passed: false }];
        g.step(0.02);
        ok("the sky stops it but does not end it", !g.over && g.ly >= g.radius, g.ly);

        g.restart();
        g.flap();
        g.ly = 200;
        g.vy = 0;
        g.pipes = [{ x: g.leafX - g.radius - g.pipeW - 1, gap: 200, passed: false }];
        g.step(0.001);
        ok("a branch passed is a point", g.score === 1, g.score);

        g.restart();
        g.flap();
        g.ly = 60;
        g.vy = 0;
        let ended = -1;
        g.finished.connect(sc => ended = sc);
        g.pipes = [{ x: g.leafX - 10, gap: 300, passed: false }];
        g.step(0.001);
        ok("flying into a branch ends it", g.over && ended === 0, ended);

        g.restart();
        g.flap();
        g.pipes = [];
        g.ly = g.worldH - g.ground - g.radius - 1;
        g.vy = 300;
        g.step(0.02);
        ok("so does the ground", g.over);
        g.restart();
""", shot="flappy.png")

# ── Breakout ──────────────────────────────────────────────────────────────
run("breakout", game("GenesiGameBreakout.qml"), """
        g.restart();
        ok("forty bricks, three balls", g.bricks.filter(b => b).length === 40 && g.lives === 3);

        g.serve();
        g.bx = 3; g.by = 300; g.vx = -200; g.vy = -100;
        g.step(0.02);
        ok("the left wall bounces", g.vx > 0, g.vx);
        g.bx = g.worldW - 3; g.vx = 200;
        g.step(0.02);
        ok("so does the right", g.vx < 0, g.vx);

        g.px = 180;
        g.bx = 180; g.by = g.padY - g.r - 1; g.vx = 0; g.vy = 250;
        g.step(0.01);
        ok("the middle of the paddle sends it straight up",
           g.vy < 0 && Math.abs(g.vx) < 5, g.vx + "," + g.vy);
        g.bx = 180 + g.padW / 2 - 2; g.by = g.padY - g.r - 1; g.vx = 0; g.vy = 250;
        g.step(0.01);
        ok("the right edge sends it right", g.vy < 0 && g.vx > 100, g.vx);

        const before = g.score;
        g.bx = g.side + g.brickW / 2; g.by = g.brickTop + g.brickH * 4.5 + 16 + 2; g.vx = 0; g.vy = -250;
        g.step(0.02);
        ok("a brick breaks and scores",
           g.bricks.filter(b => b).length === 39 && g.score > before && g.vy > 0, g.score);

        g.bx = 100; g.by = g.worldH + 5; g.vx = 0; g.vy = 300;
        g.step(0.02);
        ok("a lost ball costs a life, and the next waits on the paddle",
           g.lives === 2 && !g.served, g.lives);

        g.serve();
        g.bricks = new Array(40).fill(0);
        g.bricks[0] = 1;
        g.bricks = g.bricks.slice();
        g.bx = g.side + g.brickW / 2; g.by = g.brickTop + g.brickH / 2 + 2; g.vx = 0; g.vy = -250;
        g.step(0.01);
        ok("the last brick brings the next level, and a new wall",
           g.level === 2 && g.bricks.filter(b => b).length === 40, g.level);

        let ended = -1;
        g.finished.connect(sc => ended = sc);
        g.lives = 1;
        g.serve();
        g.bx = 100; g.by = g.worldH + 5; g.vy = 300;
        g.step(0.02);
        ok("the last ball ends it", g.over && ended === g.score, ended);
        g.restart();
""", shot="breakout.png")

# ── Memory ────────────────────────────────────────────────────────────────
run("memory", game("GenesiGameMemory.qml"), """
        g.restart();
        const counts = {};
        g.cards.forEach(c => counts[c.sym] = (counts[c.sym] || 0) + 1);
        ok("sixteen cards, eight pairs",
           g.cards.length === 16 && Object.keys(counts).length === 8
           && Object.values(counts).every(n => n === 2), JSON.stringify(counts));

        g.cards = [0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7].map(s => ({ sym: s, up: false, done: false }));
        g.pick(0);
        g.pick(1);
        ok("a match stays up", g.cards[0].done && g.cards[1].done && g.moves === 1);

        g.pick(2);
        g.pick(4);
        ok("a miss is shown...", g.cards[2].up && g.cards[4].up && g.locked);
        g.pick(6);
        ok("...and the board takes no third card while it is", !g.cards[6].up);
        g.settle();
        ok("...then turns back", !g.cards[2].up && !g.cards[4].up && !g.locked && g.moves === 2);

        let ended = -1;
        g.finished.connect(sc => ended = sc);
        for (let i = 2; i < 16; i += 2) {
            g.pick(i);
            g.pick(i + 1);
        }
        ok("every pair found wins, scored in turns", g.won && ended === 9, ended);
        ok("...and fewer turns is the better score", g.lowerIsBetter === true);
        g.restart();
""", shot="memory.png")

# ── Simon ─────────────────────────────────────────────────────────────────
run("simon", game("GenesiGameSimon.qml"), """
        g.restart();
        g.begin();
        ok("the first round is one long", g.seq.length === 1 && g.phase === "show");
        g.press(g.seq[0]);
        ok("pressing during the demonstration does nothing", g.at === 0);

        g.phase = "input";
        g.press(g.seq[0]);
        ok("the right answer completes the round", g.score === 1 && g.phase === "show");
        g.grow();
        ok("...and the next is one longer", g.seq.length === 2);

        g.phase = "input";
        g.press(g.seq[0]);
        ok("half of it is progress, not a round", g.at === 1 && g.score === 1);

        let ended = -1;
        g.finished.connect(sc => ended = sc);
        g.press((g.seq[1] + 1) % 4);
        ok("a wrong pad ends it, with the rounds done", g.over && ended === 1, ended);
        g.restart();
""", shot="simon.png")

# ── The shelf, and a game through it ─────────────────────────────────────
run("hub", """
    GenesiGames {
        id: hubItem
        anchors.fill: parent
        anchors.margins: 20
        pal: host.pal
        sans: "sans-serif"
        best: ({ snake: 120, mines: 40, memory: 18 })
        plays: ({ snake: 3, mines: 2 })
    }
    readonly property Item g: hubItem
""", """
        const said = [];
        g.played.connect((id, score, low) => said.push([id, score, low]));

        ok("the shelf lists eight games", g.games.length === 8);
        ok("best scores read the right way round",
           g.bestText("snake") === "Best 120" && g.bestText("mines") === "Best 40s"
           && g.bestText("memory") === "Best: 18 moves"
           && g.bestText("blocks") === "Not played yet", g.bestText("snake") + " / " + g.bestText("mines"));

        for (const id of ["snake", "2048", "flappy", "blocks", "breakout", "mines", "memory", "simon"]) {
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

# ── The leaf's mind ───────────────────────────────────────────────────────
run("leaf mind", """
    GenesiPetMind {
        id: brain
        portuguese: false
    }
    readonly property QtObject g: brain
""", """
        const calm = { now: 10, happyUntil: 0, idle: false, cpu: 12, temp: 45,
                       playing: false, updates: 3, disk: 0.4, hour: 9 };
        const w = o => Object.assign({}, calm, o);

        ok("a quiet machine is a calm leaf", g.moodFor(calm) === "normal");
        ok("90% CPU is hot", g.moodFor(w({ cpu: 90 })) === "hot");
        ok("85 C is hot too", g.moodFor(w({ temp: 86 })) === "hot");
        ok("hot beats asleep: no sleeping through a fire",
           g.moodFor(w({ idle: true, cpu: 97 })) === "hot");
        ok("music beats asleep: listening is not being away",
           g.moodFor(w({ idle: true, playing: true })) === "dancing");
        ok("nobody there is asleep", g.moodFor(w({ idle: true })) === "sleeping");
        ok("a long list of updates makes it sick", g.moodFor(w({ updates: 25 })) === "sick");
        ok("...a short one does not", g.moodFor(w({ updates: 24 })) === "normal");
        ok("a nearly full disk makes it sick", g.moodFor(w({ disk: 0.96 })) === "sick");
        ok("just played with, it is happy above all",
           g.moodFor(w({ happyUntil: 20, cpu: 99 })) === "happy");

        ok("level 1 at nothing", g.levelFor(0) === 1);
        ok("level 2 at 60 XP, not a point before",
           g.levelFor(59) === 1 && g.levelFor(60) === 2, g.levelFor(59) + "/" + g.levelFor(60));
        ok("level 3 at 180, 5 at 600, 8 at 1680",
           g.levelFor(180) === 3 && g.levelFor(600) === 5 && g.levelFor(1680) === 8
           && g.levelFor(1679) === 7);
        ok("xpFor and levelFor agree", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].every(n => g.levelFor(g.xpFor(n)) === n));

        const first = g.fromGames(3, 3, { snake: 50 }, { snake: 50 });
        ok("no new games, no XP", first.xp === 0 && first.line === "");
        const two = g.fromGames(5, 3, { snake: 50 }, { snake: 50 });
        ok("5 XP a game", two.xp === 10 && two.line !== "", JSON.stringify(two));
        const rec = g.fromGames(4, 3, { snake: 90 }, { snake: 50 });
        ok("a record is worth 20 more, and it says so", rec.xp === 25 && rec.line.indexOf("record") >= 0,
           JSON.stringify(rec));
        const firstBest = g.fromGames(4, 3, { mines: 40 }, {});
        ok("a first score is a game, not a record", firstBest.xp === 5, JSON.stringify(firstBest));

        const lines = g.status(w({ cpu: 93.4, temp: 71 }), 200);
        ok("clicked while hot, it says so, with the number",
           lines[0].indexOf("93%") >= 0 && lines.join(" ").indexOf("71") >= 0, lines.join(" | "));
        ok("...and where it is in growing up",
           lines[lines.length - 1].indexOf("level 3") >= 0 && lines[lines.length - 1].indexOf("360") >= 0,
           lines[lines.length - 1]);
        ok("healed by updates, it is grateful",
           g.remark("sick", "normal", w({ updates: 0 })).length > 0);
        ok("nothing changed, nothing said", g.remark("normal", "normal", calm) === "");

        g.portuguese = true;
        ok("it talks in the machine's language",
           g.status(w({ cpu: 93 }), 0)[0].indexOf("quente") >= 0 && g.title(5) === "Folha");
""")

# ── The weather ───────────────────────────────────────────────────────────
run("weather", """
    GenesiWeatherFx {
        id: sky
        anchors.fill: parent
    }
    readonly property Item g: sky
""", """
        const want = [[0, "none"], [2, "none"], [3, "none"], [45, "fog"], [48, "fog"],
                      [51, "drizzle"], [55, "drizzle"], [61, "rain"], [65, "rain"],
                      [66, "rain"], [71, "snow"], [75, "snow"], [77, "snow"],
                      [80, "rain"], [82, "rain"], [85, "snow"], [86, "snow"],
                      [95, "storm"], [96, "storm"], [99, "storm"]];
        const wrong = want.filter(([c, k]) => g.classify(c).kind !== k)
                          .map(([c, k]) => c + "->" + g.classify(c).kind + " (want " + k + ")");
        ok("every WMO code lands on the right sky", wrong.length === 0, wrong.join(", "));
        ok("heavy rain is heavier than light rain",
           g.classify(65).intensity > g.classify(61).intensity);

        g.code = 1;
        ok("a clear day draws nothing", g.drops === 0 && g.flakes === 0 && g.kind === "none");
        g.code = 63;
        ok("rain draws rain", g.drops > 100 && g.flakes === 0, g.drops);
        g.code = 73;
        ok("snow draws snow", g.flakes > 50 && g.drops === 0, g.flakes);
        g.forced = "storm";
        ok("a preview overrides the sky outside", g.kind === "storm" && g.drops > 150);
        g.forced = "";
        ok("...and ends", g.kind === "snow");
        g.code = 65;
""", size=(640, 360), shot="weather.png")

# ── The turntable ─────────────────────────────────────────────────────────
run("vinyl", """
    GenesiVinylDeck {
        id: deckItem
        anchors.centerIn: parent
        pal: host.pal
        sans: "sans-serif"
        title: "Clair de Lune"
        artist: "Debussy"
        progress: 0.4
    }
    readonly property Item g: deckItem
""", """
        ok("stopped, the arm is parked off the record", g.armAngle(false, 0.5) < 0);
        ok("playing, it lands on the lead-in", Math.abs(g.armAngle(true, 0) - 16) < 0.01);
        ok("...and creeps in through the track",
           g.armAngle(true, 0.5) > g.armAngle(true, 0) && g.armAngle(true, 1) > g.armAngle(true, 0.5));
        ok("...never past the end, whatever the player reports",
           g.armAngle(true, 3) === g.armAngle(true, 1) && g.armAngle(true, -1) === g.armAngle(true, 0));
        ok("stopped, the platter is still", g.speed === 0);
        g.playing = true;
        ok("playing, it spins up rather than snapping to speed", g.speed < g.fullSpeed, g.speed);
""", size=(420, 300), shot="vinyl.png")

# ── The Retrospective ─────────────────────────────────────────────────────
run("wrapped math", """
    GenesiWrappedMath {
        id: wm
        portuguese: false
    }
    readonly property QtObject g: wm
""", """
        const h = (n, at) => { const a = new Array(24).fill(0); a[at] = n; return a; };
        // A week ending on Wednesday 2026-09-23, crossing nothing, with the
        // week before it lighter.
        const days = {
            "2026-09-17": { active: 3600, apps: { firefox: 3600 }, hours: h(3600, 10) },
            "2026-09-18": { active: 7200, apps: { code: 7200 }, hours: h(7200, 14) },
            "2026-09-21": { active: 3600, apps: { firefox: 1800, foot: 1800 }, hours: h(3600, 23) },
            "2026-09-22": { active: 30000, apps: { code: 28000, firefox: 2000 }, hours: h(30000, 15) },
            "2026-09-23": { active: 1800, apps: { foot: 1800 }, hours: h(1800, 9) },
            "2026-09-12": { active: 36000, apps: { code: 36000 }, hours: h(36000, 12) }
        };
        const s = g.summarize(days, new Date(2026, 8, 23), 7);
        ok("the week is the seven days ending on the day", s.first === "2026-09-17" && s.last === "2026-09-23",
           s.first + ".." + s.last);
        ok("its total is its days, and only its days", s.total === 46200, s.total);
        ok("it knows how many of them were used", s.activeDays === 5, s.activeDays);
        ok("apps are summed across the days", s.top[0].app === "code" && s.top[0].secs === 35200,
           JSON.stringify(s.top[0]));
        ok("the busiest day is the busiest day", s.busiest.key === "2026-09-22", s.busiest.key);
        ok("the week before is compared", s.previous === 36000 && s.change === 28, s.change);
        ok("the streak counts back from the last day", s.streak === 3, s.streak);
        ok("the hours are summed into the day", s.hours[15] === 30000 && s.hours[23] === 3600);
        ok("a day over eight hours makes a marathoner", g.persona(s).key === "marathon", g.persona(s).key);

        const owl = g.summarize({ "2026-09-23": { active: 4000, apps: { a: 4000 }, hours: h(4000, 23) } },
                                new Date(2026, 8, 23), 7);
        ok("late hours make a night owl", g.persona(owl).key === "owl");

        const empty = g.summarize({}, new Date(2026, 8, 23), 7);
        const slidesEmpty = g.slides(empty, {});
        ok("an empty week says so instead of showing zeros",
           slidesEmpty.length === 2 && slidesEmpty[1].kind === "empty", JSON.stringify(slidesEmpty.map(x => x.kind)));

        const slides = g.slides(s, { games: { total: 12, favourite: "Snake", best: 340 },
                                     leaf: { level: 3, title: "Leaflet" } });
        const kinds = slides.map(x => x.kind).join(",");
        ok("a full week tells the whole story, in order",
           kinds === "intro,total,topapp,top5,rhythm,busiest,games,leaf,outro", kinds);
        ok("...and leaves out what it has nothing to say about",
           g.slides(s, {}).every(x => x.kind !== "games" && x.kind !== "leaf"));
        ok("a month is called a month", g.slides(g.summarize(days, new Date(2026, 8, 23), 30), {})[0].title.indexOf("month") >= 0);
        ok("hours read like hours", g.fmt(35200) === "9h 46min" && g.fmt(1800) === "30min" && g.fmt(7200) === "2h");
""")

run("wrapped story", """
    GenesiWrappedStory {
        id: tale
        anchors.fill: parent
        pal: host.pal
        sans: "sans-serif"
        portuguese: false
        slides: [
            { kind: "intro", title: "Your week on Genesi", line: "2026-09-17 → 2026-09-23" },
            { kind: "total", title: "You spent", value: 46200, line: "with your computer, on 5 of 7 days", change: 28 },
            { kind: "top5", title: "Your top five", apps: [{ app: "code", secs: 35200 }, { app: "firefox", secs: 7400 }, { app: "foot", secs: 3600 }] },
            { kind: "rhythm", title: "Marathoner", line: "One day went past eight hours.", hours: [0,0,0,0,0,0,0,0,0,1800,3600,0,0,0,7200,30000,0,0,0,0,0,0,0,3600] },
            { kind: "leaf", title: "Your leaf", level: 5, name: "Leaf" },
            { kind: "outro", title: "See you next week", line: "3 days in a row, and counting." }
        ]
        names: ({ code: "Visual Studio Code", firefox: "Firefox", foot: "Foot" })
    }
    readonly property Item g: tale
""", """
        let closed = 0;
        g.closed.connect(() => closed++);
        g.restart();
        ok("it opens on the first slide", g.at === 0 && g.slide.kind === "intro");
        g.go(1);
        ok("forward is the next slide", g.at === 1 && g.slide.kind === "total");
        g.go(-1);
        g.go(-1);
        ok("back never goes before the first", g.at === 0);
        for (let i = 0; i < 5; i++)
            g.go(1);
        ok("it reaches the last", g.at === 5 && g.slide.kind === "outro" && closed === 0);
        g.go(1);
        ok("...and going past it closes the story", closed === 1 && g.at === 5);
        ok("names come from the shell, and a class with none is itself",
           g.nameOf("code") === "Visual Studio Code" && g.nameOf("weird-app") === "weird-app");
        g.at = 3;
""", size=(1000, 640), shot="wrapped.png")

# ── The leaf, drawn ───────────────────────────────────────────────────────
run("leaf drawing", """
    Grid {
        id: garden
        anchors.centerIn: parent
        columns: 6
        spacing: 10
        Repeater {
            model: [["normal", 1], ["happy", 3], ["sleeping", 1], ["hot", 5],
                    ["sick", 2], ["dancing", 8],
                    ["normal", 3], ["normal", 5], ["normal", 8],
                    ["happy", 8], ["sleeping", 5], ["hot", 1]]
            GenesiLeaf {
                required property var modelData
                pal: host.pal
                mood: modelData[0]
                level: modelData[1]
                size: 64
            }
        }
    }
    readonly property Item g: garden
""", """
        ok("twelve leaves, every mood and every stage", g.children.length >= 12, g.children.length);
""", size=(520, 220), shot="leaves.png")

print()
if fails:
    print(f"plugins: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("plugins: OK")
