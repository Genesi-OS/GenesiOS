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

    // ── Accent (FIXED brand palette — matches the AI Mode Monitor mockup) ──
    // Product decision (2026-07): the green accent no longer follows the Plasma
    // scheme — it's pinned to the mockup's emerald so every Genesi app reads the
    // same green regardless of the user's system accent. Only the SURFACES
    // (bg/card/line) and text still derive from the scheme, so the app keeps the
    // system's dark background while the brand colour stays put. (sysAccent above
    // is retained for `dark`/luminance helpers but no longer drives the accent.)
    readonly property color accent:      "#1FBE6A"
    readonly property color green:       "#1FBE6A"   // primary emerald
    readonly property color greenBright: "#34D989"   // gauges, dots, active text
    readonly property color greenDeep:   "#0F7A47"   // logo/brand-mark gradient foot

    // Legible accent text for use ON an accent-TINTED surface (a chip/badge/nav
    // item filled with theme.a(accent, 0.15)). Painting the raw accent — or even
    // greenBright — onto its own faint wash gives green-on-green: the classic
    // Genesi "selected item / GENESI OS badge is an empty green rectangle, text
    // invisible" bug. This lifts the fixed green hard toward white (dark schemes)
    // or black (light schemes) so it stays readable over the wash while keeping the
    // brand hue — the light-mint eyebrow look of Genesi Welcome (#7FD9BD).
    readonly property color accentText: dark ? mix(green, white, 0.55)
                                             : mix(green, black, 0.45)

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
    // bgBottom is the app's base fill (window + scroll backgrounds). It MUST be
    // fully opaque: the Genesi colour scheme bakes ALPHA into the Window colour
    // (kdeglobals BackgroundNormal=13,32,48,230 → alpha ~0.90) for the desktop
    // "glass" look, and Kirigami.Theme.backgroundColor carries that alpha. Used
    // raw, it makes the whole app body ~10% see-through — the bright wallpaper
    // bleeds through the window body (and washes out light text) while the cards,
    // built from elev()/mix() (which force alpha 1), stay solid. That mismatch is
    // the "only the top is glass, the rest is transparent / invisible text" bug.
    // Genesi Welcome dodges it by hard-setting an opaque #0D2030; we do the same
    // here by stripping the scheme alpha. KWin still frosts the window edge, so we
    // keep the glass feel without the translucent, low-contrast body.
    readonly property color bgBottom: Qt.rgba(sysBg.r, sysBg.g, sysBg.b, 1)
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

    // ── Brand typography (Rubik — genesi-ttf-rubik-vf, shipped by default) ──
    // The app also installs Rubik as the QGuiApplication font, so plain Labels
    // inherit it; these tokens are for explicit display/heading use. If Rubik
    // isn't installed (a dev box) Qt silently falls back to the system sans, so
    // referencing them is always safe.
    readonly property string sans:    "Rubik"
    readonly property string display: "Rubik"

    // ── GPU capability gate ────────────────────────────────────────
    // True only on a real GPU scene-graph (OpenGL/Vulkan/Metal/D3D11). In a VM
    // the apps fall back to the software backend (QT_QUICK_BACKEND=software),
    // where shader effects (soft shadow / blur / glow) are unsupported and
    // crash-prone — gate every such effect on this so a VM renders the flat (but
    // still gradient-shaded) path. Unknown/Software both resolve to false.
    readonly property bool fancy: {
        var api = GraphicsInfo.api
        return api === GraphicsInfo.OpenGL || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal  || api === GraphicsInfo.Direct3D11
    }

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
