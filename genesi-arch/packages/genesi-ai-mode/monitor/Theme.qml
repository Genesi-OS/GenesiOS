/*
 * Genesi AI Mode Monitor — central brand palette.
 * Instantiate once per root (`Theme { id: theme }`) and reference theme.green etc.
 * Keeps every page on the official Genesi colours instead of scattered hexes.
 */
import QtQuick

QtObject {
    // ── Genesi brand ───────────────────────────────────────────────
    readonly property color green:       "#1D9E75"   // primary
    readonly property color greenBright:  "#34D399"   // glow / active text
    readonly property color greenDeep:    "#0F6E56"   // depth

    // ── Functional accents ─────────────────────────────────────────
    readonly property color turbo:        "#E67E22"   // ⚡ Turbo
    readonly property color turboBright:   "#F8B24D"
    readonly property color purple:       "#9B59B6"   // inference
    readonly property color purpleBright:   "#C589DE"
    readonly property color blue:         "#3AAFE0"   // memory
    readonly property color red:          "#E74C3C"   // off / errors

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
