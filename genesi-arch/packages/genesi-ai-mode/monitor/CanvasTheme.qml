/*
 * Genesi AI Mode Monitor — Automations canvas theme. Copied from Forge's
 * ForgeTheme so the Automations canvas keeps the exact graphite look of the
 * Forge Canvas, self-contained (no dependency on the Monitor's shared Theme.qml
 * from the UI kit). Fixed-dark by design.
 */
import QtQuick

Item {
    id: t
    visible: false
    width: 0; height: 0

    readonly property bool dark: true
    readonly property color white: "#ffffff"
    readonly property color black: "#000000"

    function mix(a, b, p) {
        return Qt.rgba(a.r + (b.r - a.r) * p,
                       a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, 1)
    }
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
    function elev(p) { return mix(bgBottom, white, p) }
    function sep(p)  { return mix(bgBottom, white, p) }

    // ── Brand accents ──────────────────────────────────────────────────
    readonly property color accent:      "#1FBE6A"
    readonly property color green:       "#1FBE6A"
    readonly property color greenBright: "#34D989"
    readonly property color greenDeep:   "#0F7A47"
    readonly property color accentText:  mix(green, white, 0.55)

    readonly property color turbo:        "#E67E22"
    readonly property color turboBright:  "#F8B24D"
    readonly property color purple:       "#9B59B6"
    readonly property color purpleBright: "#C589DE"
    readonly property color blue:         "#3AAFE0"
    readonly property color red:          "#E74C3C"

    // ── Surfaces (neutral graphite) ────────────────────────────────────
    readonly property color bgBottom: "#141619"
    readonly property color bgTop:    "#16181d"
    readonly property color panelTop: "#131517"
    readonly property color panelBot: "#111315"
    readonly property color card:     "#16191c"
    readonly property color cardHi:   "#20242a"
    readonly property color line:     "#282d33"
    readonly property color lineHi:   "#353b43"

    // ── Text ───────────────────────────────────────────────────────────
    readonly property color textHi:  "#ECEFF4"
    readonly property color textMid: "#9AA3B2"
    readonly property color textLo:  "#5F6774"

    readonly property string mono:    "monospace"
    readonly property string sans:    "Rubik"
    readonly property string display: "Rubik"

    readonly property bool fancy: {
        var api = GraphicsInfo.api
        return api === GraphicsInfo.OpenGL || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal  || api === GraphicsInfo.Direct3D11
    }
}
