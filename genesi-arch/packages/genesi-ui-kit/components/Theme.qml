/*
 * Genesi UI kit — central palette + helpers, shared by every Genesi Qt6/QML app
 * (AI Mode Monitor, Sandboxes, API Inspector, …).
 *
 * SYSTEM-FOLLOWING: every structural colour (accent, surfaces, text) is derived
 * live from the system scheme via Kirigami.Theme — NOT a fixed brand palette.
 *   • On KDE/Plasma, Kirigami.Theme reflects the active Plasma colour scheme
 *     (kdeglobals) — so the apps match the desktop accent out of the box.
 *   • On Hyprland + caelestia, the apps run under qt6ct, into which
 *     genesi-caelestia-theme-sync mirrors caelestia's Material You palette
 *     (Highlight=primary, Window=surface, WindowText=onSurface). Kirigami.Theme
 *     reads that QPalette, so the apps follow the bar's dynamic colour too.
 *
 * Result: no more hardcoded blue. `accent`/`green` = the system accent;
 * surfaces are elevations of the system background. Only the *semantic* accents
 * (red=error, orange=warn, blue=info/GET, …) stay fixed, because their meaning
 * must not drift with the scheme.
 *
 * It's an Item (not a QtObject) only so Kirigami.Theme attaches; it draws
 * nothing. Instantiate once per root (`Theme { id: theme }`) and reference
 * theme.accent / theme.card / theme.textHi etc.
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

    // ── System inputs (live from the active scheme) ────────────────
    readonly property color sysBg:     Kirigami.Theme.backgroundColor
    readonly property color sysText:   Kirigami.Theme.textColor
    readonly property color sysAccent: Kirigami.Theme.highlightColor
    readonly property real  sysLum:    0.299 * sysBg.r + 0.587 * sysBg.g + 0.114 * sysBg.b
    readonly property bool  dark:      !(sysLum >= 0.5)

    // Colour constants (real color objects — a string "#fff" has no .r/.g/.b, so
    // mix() must be fed colours, not string literals).
    readonly property color white: "#ffffff"
    readonly property color black: "#000000"

    // Linear blend of two colours (p in 0..1). Software-backend safe.
    function mix(a, b, p) {
        return Qt.rgba(a.r + (b.r - a.r) * p,
                       a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, 1)
    }
    // Elevation: surfaces brighten away from the background (toward white on
    // dark schemes, toward white on light schemes too — i.e. lighter cards).
    function elev(p) { return mix(sysBg, white, p) }
    // Separators: nudge toward white on dark schemes, toward black on light.
    function sep(p)  { return dark ? mix(sysBg, white, p) : mix(sysBg, black, p) }

    // ── Accent (follows the system) ────────────────────────────────
    // `green` is kept as a name for source compatibility but now IS the system
    // accent — every app that referenced theme.green now tracks the scheme.
    readonly property color accent:      sysAccent
    readonly property color green:       sysAccent
    readonly property color greenBright: dark ? Qt.lighter(sysAccent, 1.18) : Qt.darker(sysAccent, 1.12)
    readonly property color greenDeep:   Qt.darker(sysAccent, 1.35)

    // ── Functional / semantic accents (fixed — meaning must not drift) ──
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

    // ── Surfaces (elevations of the system background) ─────────────
    readonly property color bgBottom: sysBg
    readonly property color bgTop:    elev(dark ? 0.05 : 0.02)
    readonly property color card:     elev(dark ? 0.10 : 0.05)
    readonly property color cardHi:   elev(dark ? 0.16 : 0.09)
    readonly property color line:     sep(dark ? 0.12 : 0.10)
    readonly property color lineHi:   sep(dark ? 0.20 : 0.16)

    // ── Text (from the system foreground) ──────────────────────────
    readonly property color textHi:   sysText
    readonly property color textMid:  mix(sysText, sysBg, 0.35)
    readonly property color textLo:   mix(sysText, sysBg, 0.58)

    readonly property string mono: "monospace"

    // Re-alpha a colour: theme.a(theme.accent, 0.15)
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }

    function severityColor(sev) {
        if (sev === "high")   return sevHigh
        if (sev === "medium") return sevMedium
        if (sev === "low")    return sevLow
        return sevInfo
    }

    function methodColor(m) {
        if (m === "GET")    return blue
        if (m === "POST")   return accent
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
