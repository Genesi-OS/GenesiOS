import QtQuick

Item {
    id: t
    visible: false
    width: 0
    height: 0

    readonly property bool dark: true
    readonly property color white: "#ffffff"
    readonly property color black: "#000000"

    function mix(a, b, p) {
        return Qt.rgba(a.r + (b.r - a.r) * p,
                       a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, 1)
    }
    function a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
    function elev(p) { return mix(bgBottom, white, p) }
    function sep(p) { return mix(bgBottom, white, p) }

    readonly property color accent: "#1FBE6A"
    readonly property color green: "#1FBE6A"
    readonly property color greenBright: "#34D989"
    readonly property color greenDeep: "#0F7A47"
    readonly property color accentText: "#A8F0CA"

    readonly property color turbo: "#E67E22"
    readonly property color turboBright: "#F8B24D"
    readonly property color purple: "#9B59B6"
    readonly property color purpleBright: "#C589DE"
    readonly property color violet: "#7C5CFF"
    readonly property color blue: "#3AAFE0"
    readonly property color red: "#E74C3C"
    readonly property color sevHigh: red
    readonly property color sevMedium: turbo
    readonly property color sevLow: "#E0B23A"
    readonly property color sevInfo: blue

    // Forge-inspired neutral surfaces. Accent is reserved for state and action.
    readonly property color bgBottom: "#111315"
    readonly property color bgTop: "#15181C"
    readonly property color panelTop: "#101214"
    readonly property color panelBot: "#0D0F11"
    readonly property color card: "#181B1F"
    readonly property color cardHi: "#20242A"
    readonly property color line: "#2A2F35"
    readonly property color lineHi: "#394049"

    readonly property color textHi: "#F2F4F7"
    readonly property color textMid: "#A5ADB9"
    readonly property color textLo: "#697380"
    readonly property string mono: "monospace"
    readonly property string sans: "Rubik"
    readonly property string display: "Rubik"

    function severityColor(sev) {
        if (sev === "high") return sevHigh
        if (sev === "medium") return sevMedium
        if (sev === "low") return sevLow
        return sevInfo
    }
    function methodColor(method) {
        if (method === "GET") return blue
        if (method === "POST") return greenBright
        if (method === "PUT" || method === "PATCH") return turboBright
        if (method === "DELETE") return red
        return purpleBright
    }
    function statusColor(status) {
        if (status === 0) return textLo
        if (status < 300) return greenBright
        if (status < 400) return blue
        if (status < 500) return turboBright
        return red
    }
}
