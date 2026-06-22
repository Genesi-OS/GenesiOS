/*
 * Genesi UI kit — reusable "glass" surface card, shared across all Genesi apps.
 * SYSTEM-FOLLOWING: it self-derives every colour from the active scheme
 * (Kirigami.Theme), so it needs no `theme` passed in — the surface is an
 * elevation of the system background and the active border defaults to the
 * system accent. On KDE that's the Plasma scheme; on Hyprland it's caelestia's
 * Material You palette (mirrored into qt6ct by genesi-caelestia-theme-sync).
 * No hardcoded brand blue anymore.
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

    // Same elevation/separator helpers as Theme.qml, kept local so the card stays
    // self-contained (it takes no `theme`). _white/_black are real colours — mix
    // must be fed colours, not string literals (a string has no .r/.g/.b).
    readonly property color _white: "#ffffff"
    readonly property color _black: "#000000"
    function _mix(c, b, p) { return Qt.rgba(c.r + (b.r - c.r) * p, c.g + (b.g - c.g) * p, c.b + (b.b - c.b) * p, 1) }
    function _elev(p) { return _mix(sysBg, _white, p) }
    function _sep(p)  { return dark ? _mix(sysBg, _white, p) : _mix(sysBg, _black, p) }

    property color accent: Kirigami.Theme.highlightColor
    property bool active: false
    property bool interactive: true

    radius: 18
    color: interactive && hov.hovered ? _elev(dark ? 0.14 : 0.07) : _elev(dark ? 0.10 : 0.05)
    Behavior on color { ColorAnimation { duration: 160 } }

    border.width: 1
    border.color: active ? accent
                : (interactive && hov.hovered ? _sep(dark ? 0.20 : 0.16) : _sep(dark ? 0.12 : 0.10))
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
