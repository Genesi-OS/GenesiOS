/*
 * Genesi Forge — inner surface card for the graphite palette (replaces the
 * kit's navy-pinned GlassCard inside Forge). Soft top→bottom lift gradient,
 * 1px border, optional hover lift and accent ring when active. Shader-free.
 */
import QtQuick

Rectangle {
    id: card
    property var theme
    property bool interactive: false
    property bool active: false
    property color accent: theme ? theme.green : "#1FBE6A"

    readonly property color _base: theme ? theme.card : "#1a1d22"
    readonly property color _line: theme ? theme.line : "#262b33"
    readonly property color _lineHi: theme ? theme.lineHi : "#343a44"
    function _mix(a, b, p) { return Qt.rgba(a.r + (b.r - a.r) * p, a.g + (b.g - a.g) * p, a.b + (b.b - a.b) * p, 1) }

    property real _hb: (interactive && hov.hovered) ? 1 : 0
    Behavior on _hb { NumberAnimation { duration: 150 } }

    radius: 14
    gradient: Gradient {
        GradientStop { position: 0.0; color: card._mix(card._base, "#ffffff", 0.05 + card._hb * 0.03) }
        GradientStop { position: 1.0; color: card._mix(card._base, "#ffffff", 0.01 + card._hb * 0.02) }
    }
    border.width: 1
    border.color: active ? accent : (hov.hovered && interactive ? _lineHi : _line)
    Behavior on border.color { ColorAnimation { duration: 150 } }

    transform: Translate {
        y: (card.interactive && hov.hovered) ? -1.5 : 0
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    // 1px top specular line — subtle glass edge.
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: parent.radius * 0.6; anchors.rightMargin: parent.radius * 0.6
        height: 1
        color: Qt.rgba(1, 1, 1, 0.05)
    }

    HoverHandler { id: hov }
}
