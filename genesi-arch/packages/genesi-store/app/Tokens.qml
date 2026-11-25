// GENESI STORE — the look, in one place.
//
// Genesi Center is emerald on near-black because it is an instrument: it
// reports. The store SELLS, so it is the same family with the lights on --
// deeper greens, more air, and one warm accent for the thing you are meant to
// press. Everything below is a token so that a card, a chip and a hero cannot
// drift apart.
pragma Singleton

import QtQuick

QtObject {
    id: root

    // ── Surfaces ─────────────────────────────────────────────────────────────
    // A near-black with green in it, not grey: the whole app should read as
    // something growing in the dark rather than as a dark grey app.
    readonly property color bg: "#070c09"
    readonly property color bgDeep: "#050806"
    readonly property color rail: "#0a120d"
    readonly property color card: "#0d1711"
    readonly property color cardHi: "#122017"
    readonly property color line: "#1b2c21"
    readonly property color hairline: "#142018"

    // ── Ink ──────────────────────────────────────────────────────────────────
    readonly property color textHi: "#eaf5ee"
    readonly property color text: "#b9cdc0"
    readonly property color textDim: "#7e9488"
    readonly property color textFaint: "#4a5c52"

    // ── Green ────────────────────────────────────────────────────────────────
    readonly property color accent: "#39d98a"
    readonly property color accentSoft: "#8fd6ab"
    readonly property color accentDeep: "#1f7a4d"
    readonly property color glow: "#39d98a"
    // The one warm note, for a price, a badge, a "popular".
    readonly property color warm: "#e8c07d"

    function a(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, alpha);
    }

    // ── Type ─────────────────────────────────────────────────────────────────
    function pick(families, fallback) {
        for (let i = 0; i < families.length; i++)
            if (Qt.fontFamilies().indexOf(families[i]) >= 0)
                return families[i];
        return fallback;
    }

    readonly property string sans: root.pick(["Rubik", "Inter", "DejaVu Sans", "Segoe UI"], "sans-serif")
    readonly property string mono: root.pick(["CaskaydiaCove Nerd Font", "Cascadia Code", "JetBrains Mono", "DejaVu Sans Mono", "Consolas"], "monospace")

    readonly property int fsMicro: 9
    readonly property int fsLabel: 11
    readonly property int fsBody: 13
    readonly property int fsCard: 15
    readonly property int fsTitle: 20
    readonly property int fsHero: 46

    // ── Rhythm ───────────────────────────────────────────────────────────────
    readonly property int gap: 12
    readonly property int pad: 16
    readonly property int radius: 14
    readonly property int radiusSm: 9
    readonly property int radiusLg: 20
    readonly property int railWidth: 78

    readonly property int quick: 120
    readonly property int normal: 220
}
