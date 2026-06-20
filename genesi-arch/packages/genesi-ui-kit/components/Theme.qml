/*
 * Genesi UI kit — central brand palette + helpers, shared by every Genesi
 * Qt6/QML app (AI Mode Monitor, Sandboxes, API Inspector, …).
 *
 * ADAPTIVE: it follows the system (KDE) colour scheme. `dark` is derived from the
 * luminance of Kirigami.Theme.backgroundColor and defaults to TRUE on any
 * uncertainty, so the worst case is the existing dark look — never unreadable.
 * Every dark-branch value below is byte-identical to the pre-adaptive palette, so
 * on a dark system (Genesi's default) nothing changes; the light branch only
 * kicks in on a light system.
 *
 * It's an Item (not a QtObject) only so Kirigami.Theme attaches; it draws
 * nothing. Instantiate once per root (`Theme { id: theme }`) and reference
 * theme.green etc.
 *
 * Canonical source: genesi-arch/packages/genesi-ui-kit/components/. Bundled into
 * each app at build (see README) — NOT a published package.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: t
    visible: false
    width: 0; height: 0

    // Follow the system scheme. dark = the system background is dark.
    readonly property color sysBg: Kirigami.Theme.backgroundColor
    readonly property real sysLum: 0.299 * sysBg.r + 0.587 * sysBg.g + 0.114 * sysBg.b
    readonly property bool dark: !(sysLum >= 0.5)

    // ── Genesi brand ───────────────────────────────────────────────
    readonly property color green:       "#1D9E75"
    readonly property color greenBright:  dark ? "#34D399" : "#15976B"
    readonly property color greenDeep:    "#0F6E56"

    // ── Functional accents ─────────────────────────────────────────
    readonly property color turbo:        "#E67E22"
    readonly property color turboBright:   dark ? "#F8B24D" : "#D9781A"
    readonly property color purple:       "#9B59B6"
    readonly property color purpleBright:   dark ? "#C589DE" : "#7C4DCB"
    readonly property color violet:       "#7C5CFF"   // Doquo-style AI accent
    readonly property color blue:         "#3AAFE0"
    readonly property color red:          "#E74C3C"

    // ── Severity (scanner / inspector) ─────────────────────────────
    readonly property color sevHigh:      "#E74C3C"
    readonly property color sevMedium:    "#E67E22"
    readonly property color sevLow:       dark ? "#E0B23A" : "#B8860B"
    readonly property color sevInfo:      "#3AAFE0"

    // ── Surfaces ───────────────────────────────────────────────────
    readonly property color bgTop:    dark ? "#0F2536" : "#F6F7FB"
    readonly property color bgBottom: dark ? "#0A1B29" : "#FFFFFF"
    readonly property color card:     dark ? "#122E42" : "#FFFFFF"
    readonly property color cardHi:   dark ? "#173A52" : "#F3F5F9"
    readonly property color line:     dark ? "#21425A" : "#E7E9EF"
    readonly property color lineHi:   dark ? "#2C5470" : "#D3D8E1"

    // ── Text ───────────────────────────────────────────────────────
    readonly property color textHi:   dark ? "#EAEEF2" : "#1B2430"
    readonly property color textMid:  dark ? "#A2B2BD" : "#5C6775"
    readonly property color textLo:   dark ? "#647889" : "#97A1AE"

    readonly property string mono: "monospace"

    // Re-alpha a colour: theme.a(theme.green, 0.15)
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
