/*
 * Genesi design kit — reusable "glass" surface card (shared look across the AI
 * Mode Monitor, Sandboxes and API Inspector). Dark branded panel with a glassy
 * top sheen + a faint bottom shade for depth, an animated hover/active border,
 * and a subtle lift on hover.
 *
 * Polish is deliberately SHADER-FREE (no MultiEffect / DropShadow): those need
 * the GPU scene graph and go blank under QT_QUICK_BACKEND=software, which these
 * apps fall back to inside VMs. Everything here (gradients, 2D Translate, colour
 * animations) renders fine on the software backend.
 *
 * Set `accent` + `active: true` to highlight with a coloured border. Set
 * `interactive: false` on purely decorative cards that shouldn't react.
 */
import QtQuick

Rectangle {
    id: card

    property color accent: "#21425A"
    property bool active: false
    property bool interactive: true

    radius: 18
    color: (interactive && hov.hovered) ? "#143A55" : "#122E42"
    Behavior on color { ColorAnimation { duration: 160 } }

    border.width: 1
    border.color: active ? accent
                : ((interactive && hov.hovered) ? "#2C5470" : "#21425A")
    Behavior on border.color { ColorAnimation { duration: 180 } }

    // Elevation: lift a touch on hover (2D translate — software-backend safe).
    transform: Translate {
        y: (card.interactive && hov.hovered) ? -2 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // Glass: top light sheen + faint bottom shade, all inside the radius.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        z: 0
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.86; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    HoverHandler { id: hov }
}
