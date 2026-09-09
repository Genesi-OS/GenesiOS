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

    // ── Graphite, or whatever the desktop is wearing ────────────────────
    //
    // Fixed-dark by design, and that is still the DEFAULT. But "every window
    // follows the theme" has to mean every window, so the surfaces and the
    // accent can come from caelestia's active scheme instead.
    //
    // The switch is Genesi Center's -- one setting for both apps. `backend` is
    // a context property, so it is reachable here without being passed down
    // through every component that owns a colour.
    readonly property var sys: (typeof backend !== "undefined" && backend)
                               ? (backend.systemPalette || ({})) : ({})
    readonly property bool following: (typeof backend !== "undefined" && backend)
                                      ? (backend.followSystemTheme === true
                                         && !!t.sys.surface) : false

    function pickC(key, fallback) {
        if (!t.following)
            return fallback;
        const v = t.sys[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    function mix(a, b, p) {
        return Qt.rgba(a.r + (b.r - a.r) * p,
                       a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, 1)
    }
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
    function elev(p) { return mix(bgBottom, white, p) }
    function sep(p)  { return mix(bgBottom, white, p) }

    // ── Brand accents (same as the kit) ────────────────────────────────
    // The accent follows; the three shades of it are DERIVED, because a scheme
    // gives one accent and this app uses three. Mapping the other two onto
    // secondary and tertiary would give Forge a three-hue accent nobody chose.
    readonly property color accent:      t.pickC("primary", "#1FBE6A")
    readonly property color green:       t.accent
    readonly property color greenBright: t.following ? Qt.lighter(t.accent, 1.25)
                                                     : "#34D989"
    readonly property color greenDeep:   t.following ? Qt.darker(t.accent, 1.9)
                                                     : "#0F7A47"
    readonly property color accentText:  mix(green, white, 0.55)

    readonly property color turbo:        "#E67E22"
    readonly property color turboBright:  "#F8B24D"
    readonly property color purple:       "#9B59B6"
    readonly property color purpleBright: "#C589DE"
    readonly property color blue:         "#3AAFE0"
    // Only red follows. turbo, purple and blue carry MEANING here -- AI Turbo
    // is orange wherever you see it -- and a semantic colour that changes with
    // the wallpaper is a legend that stops being true.
    readonly property color red:          t.pickC("error", "#E74C3C")

    // ── Surfaces (Forge v2 mock — neutral graphite) ────────────────────
    // Depth order (dark → light): content panel < window < inner cards. The
    // panel is the darkest well; cards sit clearly lighter on top of it.
    readonly property color bgBottom: t.pickC("surface", "#141619")            // window base
    readonly property color bgTop:    t.pickC("surfaceContainerLow", "#16181d") // window top of gradient
    readonly property color panelTop: t.pickC("surfaceContainerLowest", "#131517")
    readonly property color panelBot: t.pickC("surfaceContainerLowest", "#111315")
    readonly property color card:     t.pickC("surfaceContainer", "#16191c")   // inner cards
    readonly property color cardHi:   t.pickC("surfaceContainerHigh", "#20242a")
    readonly property color line:     t.pickC("outlineVariant", "#282d33")     // borders
    readonly property color lineHi:   t.pickC("outline", "#353b43")

    // ── Text (fixed-dark app) ──────────────────────────────────────────
    readonly property color textHi:  t.pickC("onSurface", "#ECEFF4")
    readonly property color textMid: t.pickC("onSurfaceVariant", "#9AA3B2")
    readonly property color textLo:  t.pickC("outline", "#5F6774")

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
