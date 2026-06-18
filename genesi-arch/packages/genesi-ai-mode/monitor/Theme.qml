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

    // ── Surfaces (neutral system dark; green stays an accent only) ──
    readonly property color bgTop:        "#1A1D1F"
    readonly property color bgBottom:     "#141618"
    readonly property color card:         "#1F2225"
    readonly property color cardHi:       "#282C30"
    readonly property color line:         "#31363B"
    readonly property color lineHi:       "#3D434A"

    // ── Text ───────────────────────────────────────────────────────
    readonly property color textHi:       "#EAEDEF"
    readonly property color textMid:      "#A4ABAF"
    readonly property color textLo:       "#6B7378"

    // Re-alpha a colour: theme.a(theme.green, 0.15)
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
}
