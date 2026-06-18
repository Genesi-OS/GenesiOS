/*
 * Genesi API Inspector — central brand palette (shared with the AI Monitor).
 * Instantiate once per root (`Theme { id: theme }`) and reference theme.green etc.
 */
import QtQuick

QtObject {
    // ── Genesi brand ───────────────────────────────────────────────
    readonly property color green:       "#1D9E75"   // primary
    readonly property color greenBright:  "#34D399"   // glow / active text
    readonly property color greenDeep:    "#0F6E56"   // depth

    // ── Functional accents ─────────────────────────────────────────
    readonly property color turbo:        "#E67E22"   // ⚡ / send
    readonly property color turboBright:   "#F8B24D"
    readonly property color purple:       "#9B59B6"   // repeater
    readonly property color blue:         "#3AAFE0"   // intruder
    readonly property color red:          "#E74C3C"   // drop / errors / high

    // ── Severity (scanner) ─────────────────────────────────────────
    readonly property color sevHigh:      "#E74C3C"
    readonly property color sevMedium:    "#E67E22"
    readonly property color sevLow:       "#E0B23A"
    readonly property color sevInfo:      "#3AAFE0"

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

    readonly property string mono: "monospace"

    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }

    function severityColor(sev) {
        if (sev === "high")   return sevHigh
        if (sev === "medium") return sevMedium
        if (sev === "low")    return sevLow
        return sevInfo
    }

    function methodColor(m) {
        if (m === "GET")    return blue
        if (m === "POST")   return green
        if (m === "PUT" || m === "PATCH") return turbo
        if (m === "DELETE") return red
        return purple
    }

    function statusColor(s) {
        if (s === 0)            return textLo
        if (s < 300)            return greenBright
        if (s < 400)            return blue
        if (s < 500)            return turboBright
        return red
    }
}
