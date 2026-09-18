// GENESI STORE — one icon.
//
// Material Symbols, which every Genesi desktop already has (the shell depends
// on it), named by the store's own words rather than by the font's: the rail
// asks for "rices" and "decor", not for "grid_view" and "wallpaper", so the
// day an icon is chosen differently there is one line to change.
//
// The font can be missing -- somebody running this app on another desktop --
// and Qt draws a missing glyph as a box without saying so. So there is a
// check, and the fallback is a small leaf: a mark that means nothing in
// particular is better than a row of tofu.
import QtQuick
import ".."

Item {
    id: root

    property string name: ""
    property int size: 18
    property color colour: Tokens.text
    property real fill: 0

    readonly property string family: Tokens.pick(["Material Symbols Rounded", "Material Symbols Outlined", "Material Icons"], "")

    readonly property var glyphs: ({
            "home": "home",
            "discover": "explore",
            "rices": "grid_view",
            "themes": "palette",
            "lockscreens": "lock",
            "bars": "web_asset",
            "fastfetch": "terminal",
            "decor": "wallpaper",
            "bundles": "inventory_2",
            "plugins": "extension",
            "library": "book_2",
            "settings": "tune",
            "help": "help",
            "search": "search",
            "refresh": "sync",
            "install": "download",
            "applied": "check_circle",
            "revert": "undo",
            "play": "play_arrow",
            "queue": "list",
            "day": "light_mode",
            "night": "dark_mode",
            "star": "star",
            "root": "shield_person",
            "square": "square"
        })

    implicitWidth: root.size
    implicitHeight: root.size

    Text {
        anchors.centerIn: parent
        visible: root.family !== ""
        text: root.glyphs[root.name] ?? root.name
        color: root.colour
        font.family: root.family
        font.pixelSize: root.size
        font.variableAxes: ({
                "FILL": root.fill,
                "wght": 420,
                "opsz": root.size
            })
    }

    Leaf {
        anchors.centerIn: parent
        visible: root.family === ""
        width: root.size * 0.8
        height: root.size * 0.8
        colour: root.colour
    }
}
