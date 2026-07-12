/*
 * Genesi Forge — app-local theme. Mirrors the shared UI-kit Theme API (so
 * GButton and every Forge component keep working) but pins the Forge v2 mock
 * palette: neutral graphite surfaces (window #141619, content panel ~#121315,
 * inner cards lifted) instead of the kit's navy. Accents stay the Genesi
 * emerald + the fixed semantic colours. The app is fixed-dark by design.
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

    // ── Brand accents (same as the kit) ────────────────────────────────
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

    // ── Surfaces (Forge v2 mock — neutral graphite) ────────────────────
    // Depth order (dark → light): content panel < window < inner cards. The
    // panel is the darkest well; cards sit clearly lighter on top of it.
    readonly property color bgBottom: "#141619"   // window base
    readonly property color bgTop:    "#16181d"   // window top of gradient
    readonly property color panelTop: "#131517"   // content panel (user-pinned #131517)
    readonly property color panelBot: "#111315"
    readonly property color card:     "#16191c"   // inner cards (user-pinned)
    readonly property color cardHi:   "#20242a"   // hover / input fields (a touch lighter)
    readonly property color line:     "#282d33"   // borders
    readonly property color lineHi:   "#353b43"

    // ── Text (fixed-dark app) ──────────────────────────────────────────
    readonly property color textHi:  "#ECEFF4"
    readonly property color textMid: "#9AA3B2"
    readonly property color textLo:  "#5F6774"

    readonly property string mono:    "monospace"
    readonly property string sans:    "Rubik"
    readonly property string display: "Rubik"

    // GPU gate (same rule as the kit) — shader effects only on a real GPU.
    readonly property bool fancy: {
        var api = GraphicsInfo.api
        return api === GraphicsInfo.OpenGL || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal  || api === GraphicsInfo.Direct3D11
    }
}
