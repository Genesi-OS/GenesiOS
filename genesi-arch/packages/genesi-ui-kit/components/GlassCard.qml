/*
 * Genesi UI kit — reusable "glass" surface card, shared across all Genesi apps.
 * SYSTEM-FOLLOWING: it self-derives every colour from the active scheme
 * (Kirigami.Theme), so it needs no `theme` passed in — the surface is an
 * elevation of the system background and the active border/glow default to the
 * system accent. On KDE that's the Plasma scheme; on Hyprland it's caelestia's
 * Material You palette (mirrored into qt6ct by genesi-caelestia-theme-sync).
 * No hardcoded brand colour anywhere.
 *
 * DEPTH is delivered in two tiers:
 *   • Always (incl. QT_QUICK_BACKEND=software in VMs): a top→bottom elevation
 *     gradient, a 1px top specular highlight, a hover brighten + lift, and a
 *     shader-free accent ring when `active`.
 *   • GPU only (`fancy`, see Theme.qml): a soft MultiEffect drop shadow that
 *     turns into an accent-coloured halo when `active`. Gated so the software
 *     backend never instantiates a shader (it would blank/crash in a VM).
 *
 * Set `accent` + `active: true` to highlight; `wash: true` for a faint accent
 * tint over the surface (hero cards); `entranceDelay >= 0` to fade+scale the
 * card in (staggered by the caller — default -1, i.e. no entrance, so list
 * delegates in other apps are unaffected). `interactive: false` on purely
 * decorative cards that shouldn't react to hover.
 */
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Rectangle {
    id: card

    readonly property color sysBg: Kirigami.Theme.backgroundColor
    readonly property bool dark: !((0.299 * sysBg.r + 0.587 * sysBg.g + 0.114 * sysBg.b) >= 0.5)

    // Elevation/separator helpers (kept local so the card takes no `theme`).
    // _white/_black are real colours — _mix must be fed colours, not strings.
    readonly property color _white: "#ffffff"
    readonly property color _black: "#000000"
    function _mix(c, b, p) { return Qt.rgba(c.r + (b.r - c.r) * p, c.g + (b.g - c.g) * p, c.b + (b.b - c.b) * p, 1) }
    function _elev(p) { return _mix(sysBg, _white, p) }
    function _sep(p)  { return dark ? _mix(sysBg, _white, p) : _mix(sysBg, _black, p) }

    property color accent: Kirigami.Theme.highlightColor
    property bool active: false
    property bool interactive: true
    property bool wash: false
    property real entranceDelay: -1

    // Real GPU only — gate the soft shadow (VMs render flat). Unknown/Software
    // both resolve to false, so the software backend never enables the layer.
    readonly property bool fancy: {
        var api = GraphicsInfo.api
        return api === GraphicsInfo.OpenGL || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal  || api === GraphicsInfo.Direct3D11
    }

    // Hover brighten driver (0..1), animated — drives the surface gradient so the
    // card lifts on hover with no shader.
    property real _hb: (interactive && hov.hovered) ? 1 : 0
    Behavior on _hb { NumberAnimation { duration: 160 } }

    radius: 18

    // Surface: a soft top→bottom elevation gradient (premium depth, shader-free).
    gradient: Gradient {
        GradientStop { position: 0.0; color: card._elev((card.dark ? 0.14 : 0.065) + card._hb * (card.dark ? 0.06 : 0.03)) }
        GradientStop { position: 1.0; color: card._elev((card.dark ? 0.07 : 0.030) + card._hb * (card.dark ? 0.04 : 0.02)) }
    }

    border.width: 1
    border.color: active ? accent
                : (interactive && hov.hovered ? _sep(dark ? 0.20 : 0.16) : _sep(dark ? 0.12 : 0.10))
    Behavior on border.color { ColorAnimation { duration: 180 } }

    // Hover lift (2D translate — software-safe).
    transform: Translate {
        y: (card.interactive && hov.hovered) ? -2 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // Soft drop shadow — GPU only. When active it becomes an accent halo (follows
    // the system accent); otherwise a neutral elevation shadow beneath the card.
    layer.enabled: card.fancy
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: card.active
            ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.50)
            : Qt.rgba(0, 0, 0, card.dark ? 0.50 : 0.26)
        shadowBlur: card.active ? 0.9 : 0.55
        shadowVerticalOffset: card.active ? 0 : 5
        shadowHorizontalOffset: 0
        autoPaddingEnabled: true
    }

    // Active accent ring (shader-free) — reinforces the selection on the software
    // backend too, where the soft shadow above is off.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1.5
        radius: parent.radius + 1.5
        color: "transparent"
        border.width: 1.5
        border.color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, card.active ? 0.28 : 0.0)
        Behavior on border.color { ColorAnimation { duration: 200 } }
        z: -1
    }

    // Signature accent wash (hero cards) — a faint diagonal tint in the system
    // accent. Sits under the caller's content (declared before it).
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: card.wash
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, card.dark ? 0.10 : 0.07) }
            GradientStop { position: 0.65; color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.0) }
        }
    }

    // Top specular highlight (1px) — crisp glass edge, shader-free.
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: parent.radius * 0.5; anchors.rightMargin: parent.radius * 0.5
        height: 1
        color: Qt.rgba(1, 1, 1, card.dark ? 0.10 : 0.45)
    }

    // Entrance: fade + subtle scale-in, staggered by entranceDelay. Disabled by
    // default (entranceDelay < 0) so list delegates in the other apps are
    // unchanged; the AI Monitor opts in per card for the dashboard reveal.
    opacity: 1
    Component.onCompleted: {
        if (entranceDelay >= 0) { opacity = 0; _entrance.start() }
    }
    SequentialAnimation {
        id: _entrance
        PauseAnimation { duration: card.entranceDelay < 0 ? 0 : card.entranceDelay }
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale";   from: 0.985; to: 1; duration: 300; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler { id: hov }
}
