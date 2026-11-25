// GENESI STORE — one icon.
//
// SVGs shipped with the package, not a font.
//
// The first version asked for Material Symbols, on the reasoning that every
// Genesi desktop has it (the shell depends on it). On a real machine it was
// not found, and the fallback -- a small leaf -- was then drawn nine times
// down the rail, so every shelf had the same icon. A dependency that is
// "definitely there" is a dependency that decides what the app looks like,
// and this one decided wrong.
//
// So the icons are files here, in the same feather hand as the rest of Genesi
// (most come from the AI Mode set, five were drawn to match), and they are
// recoloured rather than shipped in every colour: one file, any accent.
import QtQuick
import QtQuick.Effects
import ".."

Item {
    id: root

    property string name: ""
    property int size: 18
    property color colour: Tokens.text
    // Kept so callers that ask for a filled icon still work; the feather set
    // is all strokes, so it only nudges the weight.
    property real fill: 0

    // The store's own words on the left, the file on the right. The rail asks
    // for "rices", not for "layout-grid", so choosing a different drawing is
    // one line here instead of a hunt through the QML.
    readonly property var files: ({
            "discover": "compass",
            "rices": "layout-grid",
            "themes": "palette",
            "login": "shield",
            "lockscreens": "lock",
            "bars": "bar",
            "fastfetch": "terminal",
            "decor": "image",
            "bundles": "box",
            "plugins": "puzzle",
            "library": "book-open",
            "settings": "sliders",
            "help": "compass",
            "search": "search",
            "refresh": "refresh-cw",
            "install": "download",
            "applied": "check",
            "revert": "rotate-ccw",
            "play": "play",
            "more": "more",
            "close": "x",
            "root": "shield",
            "star": "star",
            "square": "sliders"
        })

    readonly property string file: root.files[root.name] ?? root.name

    implicitWidth: root.size
    implicitHeight: root.size

    Image {
        id: art

        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/" + root.file + ".svg")
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: art
        colorization: 1.0
        colorizationColor: root.colour
        brightness: root.fill > 0.5 ? 0.15 : 0
        visible: art.status === Image.Ready
    }
}
