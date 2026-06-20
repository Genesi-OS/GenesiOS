/*
 * Genesi UI kit — reusable "glass" surface card, shared across all Genesi apps.
 * ADAPTIVE: self-derives light/dark from the system scheme (Kirigami.Theme), so
 * it needs no `theme` passed in. The dark branch is byte-identical to the
 * pre-adaptive card (dark systems are unchanged); the light branch is a clean
 * white card with a soft border.
 *
 * Polish is deliberately SHADER-FREE (no MultiEffect / DropShadow): those go
 * blank under QT_QUICK_BACKEND=software, which the apps fall back to in VMs.
 *
 * Set `accent` + `active: true` to highlight with a coloured border;
 * `interactive: false` on purely decorative cards that shouldn't react.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: card

    readonly property color sysBg: Kirigami.Theme.backgroundColor
    readonly property bool dark: !((0.299 * sysBg.r + 0.587 * sysBg.g + 0.114 * sysBg.b) >= 0.5)

    property color accent: dark ? "#21425A" : "#E7E9EF"
    property bool active: false
    property bool interactive: true

    radius: 18
    color: dark ? (interactive && hov.hovered ? "#143A55" : "#122E42")
                : (interactive && hov.hovered ? "#F3F5F9" : "#FFFFFF")
    Behavior on color { ColorAnimation { duration: 160 } }

    border.width: 1
    border.color: active ? accent
                : dark ? (interactive && hov.hovered ? "#2C5470" : "#21425A")
                       : (interactive && hov.hovered ? "#D3D8E1" : "#E7E9EF")
    Behavior on border.color { ColorAnimation { duration: 180 } }

    // Elevation: lift a touch on hover (2D translate — software-backend safe).
    transform: Translate {
        y: (card.interactive && hov.hovered) ? -2 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // Glass sheen: top light + faint bottom shade. Dark only — on a white card it
    // would just look muddy, so there the border carries the definition.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        z: 0
        visible: card.dark
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.86; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    HoverHandler { id: hov }
}
