#!/usr/bin/env python3
"""
Draw the Plugins shelf's pictures from the plugins themselves.

A plugin's card should show the plugin, not a mock-up of it: this loads the
real QML from genesi-caelestia-shell -- the Game Center's shelf, the leaf --
offscreen, with Genesi's own palette and the fonts the shell uses, and writes
catalog/thumbs/plugin-*.jpg. Run it by hand after changing how a plugin looks;
the build only reads the pictures it leaves behind.

    python plugin-previews.py

The two fonts (Rubik, Material Symbols Rounded -- both open licences, both
what the shell itself draws with) are fetched once into a cache outside the
repository, because a picture of an icon font without the font is a picture
of the word "sports_esports".
"""
import os
import sys
import tempfile
import time
import urllib.request

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.normpath(os.path.join(HERE, "..", "genesi-caelestia-shell"))
OUT = os.path.join(HERE, "catalog", "thumbs")
CACHE = os.path.join(tempfile.gettempdir(), "genesi-store-build-cache", "fonts")
FONTS = {
    "Rubik.ttf": "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf",
    "MaterialSymbolsRounded.ttf": "https://github.com/google/material-design-icons/raw/master/"
                                  "variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf",
}

from PySide6.QtCore import QMetaObject, Qt, QUrl  # noqa: E402
from PySide6.QtGui import QFontDatabase, QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402

app = QGuiApplication(sys.argv)

os.makedirs(CACHE, exist_ok=True)
families = {}
for name, url in FONTS.items():
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("fetching", url)
        urllib.request.urlretrieve(url, path)
    fid = QFontDatabase.addApplicationFont(path)
    families[name] = QFontDatabase.applicationFontFamilies(fid)[0]
SANS = families["Rubik.ttf"]
ICONS = families["MaterialSymbolsRounded.ttf"]

# Genesi's own dark scheme -- the emerald the machine ships with.
PALETTE = """
    QtObject {
        property color m3surface: "#0f1512"
        property color m3surfaceContainer: "#1b211e"
        property color m3surfaceContainerHigh: "#252b28"
        property color m3surfaceContainerHighest: "#303633"
        property color m3onSurface: "#dee4df"
        property color m3onSurfaceVariant: "#bfc9c1"
        property color m3outline: "#89938b"
        property color m3outlineVariant: "#3f4943"
        property color m3primary: "#80d8a8"
        property color m3onPrimary: "#003822"
        property color m3primaryContainer: "#005234"
        property color m3onPrimaryContainer: "#9cf4c3"
        property color m3secondary: "#b4ccbc"
        property color m3secondaryContainer: "#364b3e"
        property color m3tertiary: "#a3cddc"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
    }
"""

BACKDROP = """
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#0b1410" }
            GradientStop { position: 1; color: "#133024" }
        }
    }
    Repeater {
        model: [[980, 90, 420, "#1f5a3f"], [1150, 560, 300, "#1a4a5a"], [620, -120, 260, "#24493a"]]
        Rectangle {
            required property var modelData
            x: modelData[0] - modelData[2] / 2
            y: modelData[1] - modelData[2] / 2
            width: modelData[2]
            height: width
            radius: width / 2
            color: modelData[3]
            opacity: 0.35
        }
    }
"""

GAME_CENTER = """
import QtQuick
Item {
    id: host
    width: 1280; height: 720
    property QtObject pal: %(palette)s
    %(backdrop)s
    Rectangle {
        x: 44; y: 52
        width: 452; height: 628
        radius: 26
        color: host.pal.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(host.pal.m3outlineVariant, 0.8)
        GenesiGames {
            anchors.fill: parent
            anchors.margins: 22
            pal: host.pal
            sans: "%(sans)s"
            icons: "%(icons)s"
            best: ({ snake: 340, "2048": 5120, flappy: 23, mines: 48, blocks: 4200 })
            plays: ({ snake: 12, "2048": 7, mines: 5, blocks: 9, flappy: 14 })
        }
    }
    Rectangle {
        x: 560; y: 52
        width: 452; height: 628
        radius: 26
        color: host.pal.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(host.pal.m3outlineVariant, 0.8)
        GenesiGames {
            id: playing
            anchors.fill: parent
            anchors.margins: 22
            pal: host.pal
            sans: "%(sans)s"
            icons: "%(icons)s"
            best: ({ blocks: 4200 })
            Component.onCompleted: {
                playing.open("blocks");
                const b = playing.board;
                const bd = new Array(200).fill(0);
                for (let y = 14; y < 20; y++)
                    for (let x = 0; x < 10; x++)
                        if ((x * 3 + y) %% 7 !== 0)
                            bd[y * 10 + x] = 1 + (x + y) %% 7;
                b.board = bd;
                b.piece = { k: 2, rot: 1, x: 4, y: 7 };
                b.redraw();
                b.score = 3180;
                b.lines = 17;
                b.started = true;
            }
        }
    }
    Text {
        x: 1052; y: 590
        text: "south_west"
        color: host.pal.m3primary
        font.family: "%(icons)s"
        font.pixelSize: 90
        opacity: 0.8
    }
}
"""

LEAF = """
import QtQuick
Item {
    id: host
    width: 1280; height: 720
    property QtObject pal: %(palette)s
    %(backdrop)s
    GenesiLeaf {
        id: hero
        x: 250; y: 250
        size: 290
        pal: host.pal
        mood: "happy"
        level: 5
    }
    Rectangle {
        x: 150; y: 70
        width: bubble.implicitWidth + 44
        height: bubble.implicitHeight + 30
        radius: 24
        color: host.pal.m3surfaceContainerHigh
        border.width: 1
        border.color: Qt.alpha(host.pal.m3outlineVariant, 0.8)
        Text {
            id: bubble
            x: 22; y: 15
            text: "Good morning!\\nCPU 12%% · 41 °C\\nLeaf · level 5 · 640/900 XP"
            lineHeight: 1.2
            color: host.pal.m3onSurface
            font.family: "%(sans)s"
            font.pixelSize: 24
        }
    }
    Row {
        x: 640; y: 280
        spacing: 24
        Repeater {
            model: [["normal", "calm"], ["sleeping", "asleep"], ["hot", "hot CPU"],
                    ["sick", "updates"], ["dancing", "music"]]
            Column {
                required property var modelData
                spacing: 8
                GenesiLeaf {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 90
                    pal: host.pal
                    mood: modelData[0]
                    level: 3
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData[1]
                    color: "#a9c9b8"
                    font.family: "%(sans)s"
                    font.pixelSize: 18
                }
            }
        }
    }
}
"""

WEATHER = """
import QtQuick
Item {
    id: host
    width: 1280; height: 720
    // A wallpaper the store already ships (D3Ext/aesthetic-wallpapers, MIT),
    // with the plugin's own rain drawn over it.
    Image {
        anchors.fill: parent
        source: "%(thumbs)s/wall-forest-dark.jpg"
        fillMode: Image.PreserveAspectCrop
    }
    GenesiWeatherFx {
        anchors.fill: parent
        forced: "rain"
        wind: 0.55
    }
    Rectangle {
        x: 40; y: 40
        width: label.implicitWidth + 40
        height: 58
        radius: 29
        color: Qt.rgba(0.06, 0.09, 0.08, 0.72)
        Row {
            id: label
            anchors.centerIn: parent
            spacing: 12
            Text {
                text: "rainy"
                color: "#9cf4c3"
                font.family: "%(icons)s"
                font.pixelSize: 30
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Rain · 14 °C"
                color: "#e6f4ec"
                font.family: "%(sans)s"
                font.pixelSize: 24
            }
        }
    }
}
"""

VINYL = """
import QtQuick
Item {
    id: host
    width: 1280; height: 720
    property QtObject pal: %(palette)s
    Image {
        anchors.fill: parent
        source: "%(thumbs)s/wall-nord-city.jpg"
        fillMode: Image.PreserveAspectCrop
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
    }
    GenesiVinylDeck {
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        scale: 2.1
        pal: host.pal
        sans: "%(sans)s"
        playing: true
        speed: 200
        angle: 40
        title: "Aurora"
        artist: "Genesi Sessions"
        art: "%(thumbs)s/wall-aurora.jpg"
        progress: 0.45
    }
}
"""

WRAPPED = """
import QtQuick
Item {
    id: host
    width: 1280; height: 720
    property QtObject pal: %(palette)s
    GenesiWrappedStory {
        id: tale
        anchors.fill: parent
        pal: host.pal
        sans: "%(sans)s"
        portuguese: false
        slides: [
            { kind: "intro", title: "Your week on Genesi" },
            { kind: "total", title: "You spent", value: 46200 },
            { kind: "top5", title: "Your top five", apps: [
                { app: "code", secs: 35200 }, { app: "firefox", secs: 17400 },
                { app: "foot", secs: 9600 }, { app: "discord", secs: 6100 },
                { app: "steam", secs: 4300 }] },
            { kind: "outro", title: "See you next week" }
        ]
        names: ({ code: "Visual Studio Code", firefox: "Firefox", foot: "Terminal",
                  discord: "Discord", steam: "Steam" })
        Component.onCompleted: {
            tale.at = 2;
            tale.paused = true;
            tale.enter();
        }
    }
}
"""


def render(qml, name):
    view = QQuickView()
    view.engine().addImportPath(SHELL)
    comp = QQmlComponent(view.engine())
    comp.setData((qml % {"palette": PALETTE, "backdrop": BACKDROP,
                         "sans": SANS, "icons": ICONS,
                         "thumbs": QUrl.fromLocalFile(OUT).toString()}).encode("utf-8"),
                 QUrl.fromLocalFile(os.path.join(SHELL, "_preview.qml")))
    root = comp.create()
    if root is None:
        raise SystemExit("\n".join(e.toString() for e in comp.errors()))
    view.setContent(QUrl(), comp, root)
    view.resize(1280, 720)
    view.show()
    end = time.time() + 2.5
    while time.time() < end:
        app.processEvents()
    dest = os.path.join(OUT, name)
    view.grabWindow().save(dest, "JPG", 86)
    print("wrote", dest)
    view.close()


render(GAME_CENTER, "plugin-game-center.jpg")
render(LEAF, "plugin-leaf.jpg")
render(WEATHER, "plugin-live-weather.jpg")
render(VINYL, "plugin-vinyl.jpg")
render(WRAPPED, "plugin-wrapped.jpg")
