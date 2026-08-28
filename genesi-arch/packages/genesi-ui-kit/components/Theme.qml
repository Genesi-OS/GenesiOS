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

    // ── Surfaces (FIXED dark palette — colour-picked from the AI Monitor mockup) ──
    // Product decision (2026-07): the window background and card colours are pinned,
    // not derived from the Plasma scheme. The mockup uses a near-black navy for the
    // window and a slightly-lifted panel for cards/sidebar; the user colour-picked
    // #040b17 (bg) and #0d1623 (cards). Opaque — KWin still frosts the window edge,
    // so the glass feel survives without a translucent, low-contrast body. (sysBg/
    // elev/sep above stay defined for the accent helpers; they no longer drive
    // these surfaces.) GlassCard.qml pins the same #040b17 base so its cards land on
    // ~#0d1623 too.
    readonly property color bgBottom: "#040b17"   // window / scroll base
    readonly property color bgTop:    "#0a1220"   // header / raised base
    readonly property color card:     "#0d1623"   // sidebar, panels, card base
    readonly property color cardHi:   "#16223a"   // hover / raised chips, search fields
    readonly property color line:     "#1b2740"   // subtle separators / borders
    readonly property color lineHi:   "#27374f"   // stronger borders

    // ── Text (from the system foreground) ──────────────────────────
    readonly property color textHi:   sysText
    readonly property color textMid:  mix(sysText, sysBg, 0.35)
    readonly property color textLo:   mix(sysText, sysBg, 0.58)

    // ── Shape, rhythm and type scale (2026-08: the modern/minimal pass) ──
    //
    // Before this every app picked its own radii and paddings inline, so two
    // cards side by side rounded differently and nothing lined up on a grid.
    // These are the whole vocabulary: if a value is not here, it is probably
    // the wrong value. Numbers, not Kirigami.Units, because the design is a
    // fixed pixel rhythm rather than a font-relative one -- a card that grows
    // with the user's font size stops being the shape it was drawn as.
    readonly property int rSm:   8     // chips, small fields
    readonly property int rMd:   12    // buttons, list rows
    readonly property int rLg:   16    // cards, panels
    readonly property int rXl:   22    // hero surfaces, the composer
    readonly property int rPill: 999   // fully round ends

    readonly property int sp1: 4
    readonly property int sp2: 8
    readonly property int sp3: 12
    readonly property int sp4: 16
    readonly property int sp5: 24
    readonly property int sp6: 36

    // One type scale for every app. Display is for a single hero line only.
    readonly property int fsDisplay: 30
    readonly property int fsTitle:   19
    readonly property int fsHead:    15
    readonly property int fsBody:    13
    readonly property int fsSmall:   11
    readonly property int fsMicro:   10

    // A 1px separator that reads as a hairline rather than a drawn border.
    readonly property color hairline: a(white, dark ? 0.07 : 0.10)
    // The faint tint under a hovered row: visible, never a block of colour.
    readonly property color hover:    a(white, dark ? 0.05 : 0.06)
    // Card fill for the minimal look: barely lifted off the background, with
    // the hairline doing the separating instead of a heavy fill.
    readonly property color surface:  a(white, dark ? 0.035 : 0.55)

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
