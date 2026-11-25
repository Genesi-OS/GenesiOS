/*
 * Genesi AI Mode Monitor — Automations canvas theme. Structure copied from
 * Forge's ForgeTheme (self-contained, fixed-dark), but the SURFACES are the
 * Monitor's pinned navy palette (ui-kit Theme.qml: #040b17/#0d1623/#16223a…),
 * NOT Forge's graphite — the tab lives inside the Monitor and must match it
 * (the graphite mismatch was reported 2026-07-19). If the ui-kit surface
 * palette ever changes, mirror it here.
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
    // violet was referenced by the canvas and the config panel and never
    // defined here, so two icons -- "Describe the automation" and "Values you
    // can use here" -- were being handed `undefined` as a colour and rendered
    // as nothing. Invisible on a dark background, which is why it survived: the
    // only trace was a QML warning nobody could see without running the app.
    readonly property color violet:       "#7C5CFF"
    readonly property color purple:       "#9B59B6"
    readonly property color purpleBright: "#C589DE"
    readonly property color blue:         "#3AAFE0"
    readonly property color red:          "#E74C3C"

    // ── Surfaces (Monitor navy — mirrors ui-kit Theme.qml) ─────────────
    readonly property color bgBottom: "#040b17"
    readonly property color bgTop:    "#0a1220"
    readonly property color panelTop: "#0a1220"
    readonly property color panelBot: "#040b17"
    readonly property color card:     "#0d1623"
    readonly property color cardHi:   "#16223a"
    readonly property color line:     "#1b2740"
    readonly property color lineHi:   "#27374f"

    // ── Text ───────────────────────────────────────────────────────────
    // ── Shape, rhythm and type ──────────────────────────────────────────
    // Mirrors genesi-ui-kit/Theme.qml token for token. The canvas carries its
    // own palette on purpose (a self-contained graphite theme, no dependency on
    // the shared one), but it should not also invent its own geometry -- two
    // cards in the same window rounding differently is the thing these exist to
    // stop. ci/qml-sanity-test.py fails if this family uses a token missing
    // here, which is how the first attempt at this was caught.
    readonly property int rSm:   8
    readonly property int rMd:   12
    readonly property int rLg:   16
    readonly property int rXl:   22
    readonly property int rPill: 999

    readonly property int sp1: 4
    readonly property int sp2: 8
    readonly property int sp3: 12
    readonly property int sp4: 16
    readonly property int sp5: 24
    readonly property int sp6: 36

    readonly property int fsDisplay: 30
    readonly property int fsTitle:   19
    readonly property int fsHead:    15
    readonly property int fsBody:    13
    readonly property int fsSmall:   11
    readonly property int fsMicro:   10

    readonly property color hairline: a(white, 0.07)
    readonly property color hover:    a(white, 0.05)
    readonly property color surface:  a(white, 0.035)

    readonly property color textHi:  "#ECEFF4"
    readonly property color textMid: "#9AA8BC"
    readonly property color textLo:  "#5F6E86"

    readonly property string mono:    "monospace"
    readonly property string sans:    "Rubik"
    readonly property string display: "Rubik"

    readonly property bool fancy: {
        var api = GraphicsInfo.api
        return api === GraphicsInfo.OpenGL || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal  || api === GraphicsInfo.Direct3D11
    }
}
