pragma Singleton
/*
 * Tokens — the one place Genesi Center's look is decided.
 *
 * Every other Genesi app derives its colours from the system scheme through the
 * shared UI kit's Theme.qml, so they follow Plasma's accent or caelestia's
 * Material You palette. This app deliberately does not.
 *
 * Roadmap 7.4 asked what Genesi's own conviction is, and the answer this app
 * commits to is emerald on near-black: a terminal that grew into a garden.
 * A control centre that restated itself in whatever hue the wallpaper produced
 * this morning would have no identity of its own to recognise -- and this is the
 * surface where the identity is the point. The rest of the desktop keeps
 * following the system; this one leads.
 *
 * Type carries the same idea. Everything factual -- labels, numbers, section
 * numbering, the terminal -- is monospace, and only the display headline is
 * not. Density is the ornament: numbering, tracking and small caps do the work
 * that empty space does elsewhere.
 */
import QtQuick

QtObject {
    id: tokens

    // ── Which of the two palettes ────────────────────────────────────────────
    //
    // The comment above still holds -- emerald on near-black is this app's own
    // conviction, and it is the DEFAULT. But "every window follows the theme"
    // has to mean every window, and a control centre that is the one thing on
    // the desktop still painted its own colour is the exception that makes the
    // rule look like an accident.
    //
    // So both, and a switch on the Settings page. Following is off until
    // somebody turns it on; the identity does not quietly leave in an update.
    property bool useGenesi: true

    // The active scheme's colours, pushed in by Main from the backend. Empty
    // until it arrives, which is why every derived colour below falls back to
    // its Genesi value rather than to black: a window that flashes black for
    // one frame on every launch is worse than one that never follows at all.
    property var sys: ({})

    readonly property bool following: !tokens.useGenesi && !!tokens.sys.surface

    function role(key, fallback) {
        const v = tokens.sys[key];
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    function pickC(key, fallback) {
        return tokens.following ? tokens.role(key, fallback) : fallback;
    }

    // ── Ground ───────────────────────────────────────────────────────────────
    readonly property color bg:        tokens.pickC("surfaceContainerLowest", "#050a07")
    readonly property color panel:     tokens.pickC("surface", "#08120c")
    readonly property color card:      tokens.pickC("surfaceContainer", "#0a1710")
    readonly property color cardHi:    tokens.pickC("surfaceContainerHigh", "#0d1e14")
    readonly property color line:      tokens.pickC("outlineVariant", "#16301f")
    readonly property color lineSoft:  tokens.pickC("surfaceContainerHighest", "#0f2116")

    // ── Emerald, or whatever the desktop is wearing ──────────────────────────
    //
    // A scheme gives one accent, and this app uses three shades of it. They are
    // DERIVED rather than mapped onto secondary and tertiary: those two are
    // different hues in most schemes, and using them here would give the app a
    // three-colour accent nobody chose. Darkening one hue keeps the app's own
    // shape and lets the scheme decide the colour.
    readonly property color accent:    tokens.pickC("primary", "#35e07f")
    readonly property color accentDim: tokens.following ? Qt.darker(tokens.accent, 1.6)
                                                        : "#1f8f4f"
    readonly property color accentDeep: tokens.following ? Qt.darker(tokens.accent, 3.0)
                                                         : "#0d4527"
    readonly property color glow:      tokens.accent

    // ── Text ─────────────────────────────────────────────────────────────────
    readonly property color textHi:    tokens.pickC("onSurface", "#d6ffe6")
    readonly property color text:      tokens.pickC("onSurfaceVariant", "#8fbfa2")
    readonly property color textDim:   tokens.pickC("outline", "#4d7a5e")
    readonly property color textFaint: tokens.following ? Qt.darker(tokens.textDim, 1.5)
                                                        : "#2c5039"

    // ── Type ─────────────────────────────────────────────────────────────────
    // A monospace family for everything factual. The list is a fallback chain:
    // Qt takes the first that exists, and the last two are always present.
    // font.family takes ONE name and font.families does not exist on every Qt
    // this may run on, so the preference list is resolved HERE, once, against
    // the families actually installed. A comma-separated string is not a
    // fallback chain -- it is a family that does not exist, and Qt answers it
    // by silently picking something else, which rendered every glyph as a box.
    function pick(prefs, fallback) {
        const have = Qt.fontFamilies();
        for (const p of prefs)
            if (have.indexOf(p) >= 0)
                return p;
        return fallback;
    }
    readonly property string mono: pick(["JetBrains Mono", "Cascadia Code", "Cascadia Mono",
                                         "DejaVu Sans Mono", "Liberation Mono", "Consolas"],
                                        "monospace")
    readonly property string sans: pick(["Rubik", "Inter", "DejaVu Sans",
                                         "Liberation Sans", "Segoe UI"],
                                        "sans-serif")

    // The rail's tag column. Resolved separately because no Latin monospace
    // carries CJK, and Qt draws a missing glyph as a box with no complaint.
    readonly property string cjk: pick(["Noto Sans CJK JP", "Noto Sans JP",
                                        "Source Han Sans JP", "Noto Serif CJK JP",
                                        "Yu Gothic", "MS Gothic"], "")
    // Whether the tags can be drawn at all. When they cannot, the rail shows
    // nothing there rather than a column of boxes -- an empty column is a
    // design choice, a column of boxes is a bug.
    readonly property bool hasCjk: cjk !== ""

    readonly property int  fsMicro:  9
    readonly property int  fsLabel:  10
    readonly property int  fsBody:   12
    readonly property int  fsValue:  20
    readonly property int  fsTitle:  15
    readonly property int  fsHero:   58

    // ── Rhythm ───────────────────────────────────────────────────────────────
    readonly property int  gap:      10
    readonly property int  pad:      16
    readonly property int  radius:   10
    readonly property int  radiusSm: 6

    // ── Motion ───────────────────────────────────────────────────────────────
    // Slow enough to read as deliberate, short enough never to be in the way.
    readonly property int  quick:    140
    readonly property int  normal:   260
    readonly property int  slow:     520
    readonly property int  entrance: 680
}
