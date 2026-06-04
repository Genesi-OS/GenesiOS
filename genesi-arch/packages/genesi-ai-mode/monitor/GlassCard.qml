/*
 * Genesi AI Mode Monitor — reusable "glass" surface card.
 * Dark branded panel with a subtle top sheen, animated hover/active border.
 * Drop content inside as normal children; the sheen stays behind it.
 */
import QtQuick

Rectangle {
    id: card

    // Set `accent` + `active: true` to highlight the card with a coloured border.
    property color accent: "#1E382E"
    property bool active: false

    radius: 18
    color: "#0F1D18"
    border.width: 1
    border.color: active ? accent : (hov.hovered ? "#2A463B" : "#1E382E")
    Behavior on border.color { ColorAnimation { duration: 180 } }

    // Top-edge light sheen for a glassy feel.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        z: 0
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.055) }
            GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    HoverHandler { id: hov }
}
