/*
 * Genesi design kit — central brand palette (shared look with the AI Mode
 * Monitor). Instantiate once per root (`Theme { id: theme }`) and reference
 * theme.green etc. Keeps every Genesi app on the same colours instead of
 * scattered hexes. Kept identical to monitor/Theme.qml on purpose: this is the
 * pilot of a shared Genesi UI kit — once validated, extract to one package.
 */
import QtQuick

QtObject {
    // ── Genesi brand ───────────────────────────────────────────────
    readonly property color green:       "#1D9E75"   // primary
    readonly property color greenBright:  "#34D399"   // glow / active text
    readonly property color greenDeep:    "#0F6E56"   // depth

    // ── Functional accents ─────────────────────────────────────────
    readonly property color turbo:        "#E67E22"   // ⚡ action
    readonly property color turboBright:   "#F8B24D"
    readonly property color purple:       "#9B59B6"
    readonly property color purpleBright:   "#C589DE"
    readonly property color blue:         "#3AAFE0"
    readonly property color red:          "#E74C3C"   // destructive / errors

    // ── Surfaces (Genesi system blue-dark; green stays an accent only) ──
    readonly property color bgTop:        "#0F2536"
    readonly property color bgBottom:     "#0A1B29"
    readonly property color card:         "#122E42"
    readonly property color cardHi:       "#173A52"
    readonly property color line:         "#21425A"
    readonly property color lineHi:       "#2C5470"

    // ── Text ───────────────────────────────────────────────────────
    readonly property color textHi:       "#EAEEF2"
    readonly property color textMid:      "#A2B2BD"
    readonly property color textLo:       "#647889"

    // Re-alpha a colour: theme.a(theme.green, 0.15)
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
}
