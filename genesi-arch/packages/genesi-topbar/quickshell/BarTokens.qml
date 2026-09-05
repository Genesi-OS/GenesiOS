pragma Singleton
/*
 * BarTokens — the Genesi bar's own look.
 *
 * Separate from Genesi Center's Tokens even though the palette is the same
 * emerald. The bar sits on the desktop, not inside a window: it has to hold up
 * over any wallpaper, so its ground is darker and its contrast higher than a
 * page that owns its own background.
 */
import QtQuick

QtObject {
    readonly property color bg:       "#070d09"
    readonly property color panel:    "#0b1710"
    readonly property color line:     "#173322"
    readonly property color accent:   "#35e07f"
    readonly property color accentDim:"#1f8f4f"
    readonly property color textHi:   "#dcffe9"
    readonly property color text:     "#9ec9ad"
    readonly property color textDim:  "#5b8a6b"

    function pick(prefs, fallback) {
        const have = Qt.fontFamilies();
        for (const p of prefs)
            if (have.indexOf(p) >= 0)
                return p;
        return fallback;
    }
    readonly property string mono: pick(["JetBrains Mono", "Cascadia Mono",
                                         "DejaVu Sans Mono", "Liberation Mono",
                                         "Consolas"], "monospace")
    readonly property string sans: pick(["Rubik", "Inter", "DejaVu Sans",
                                         "Liberation Sans", "Segoe UI"],
                                        "sans-serif")

    readonly property int radius: 6
    readonly property int quick: 130
    readonly property int normal: 240
}
