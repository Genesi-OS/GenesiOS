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

    // ── Surfaces (explicit dark, branded) ──────────────────────────
    readonly property color bgTop:        "#0C1A15"
    readonly property color bgBottom:     "#0A1410"
    readonly property color card:         "#0F1D18"
    readonly property color cardHi:       "#13261F"
    readonly property color line:         "#1E382E"
    readonly property color lineHi:       "#2A463B"

    // ── Text ───────────────────────────────────────────────────────
    readonly property color textHi:       "#EAF3EF"
    readonly property color textMid:      "#9DB3AB"
    readonly property color textLo:       "#62756D"

    // Re-alpha a colour: theme.a(theme.green, 0.15)
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
}
