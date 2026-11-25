// GENESI — the frame every desktop widget sits in, and everything it looks like.
//
// One place decides how a widget is drawn, so fifteen of them cannot drift
// apart. It owns four things the right-click editor changes:
//
//   style    glass    the wallpaper behind it, frosted, under a tint
//            solid    an opaque card
//            outline  a border in the accent colour over the faintest tint
//            minimal  no card at all; the content casts a soft shadow so it
//                     stays readable on a busy wallpaper
//   opacity  of the whole widget
//   colour   auto (the wallpaper's own palette), solid, or a gradient between
//            two colours -- which the rings, bars and headline numbers take
//   size     `s`, which every widget multiplies its measurements by
//
// ── Why `s` and not a transform ─────────────────────────────────────────────
//
// The widgets used to be scaled with `scale:`, and text rendered natively is
// rasterised at its own size before the transform stretches it: a 2x widget was
// a 1x widget's pixels, doubled. Everything is measured in `s` now, so a bigger
// widget is drawn bigger, not enlarged.
//
// The content is measured with childrenRect and placed at a fixed offset rather
// than anchored to the middle: a child anchored to a parent that sizes itself
// FROM that child is a binding loop that does not announce itself.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import qs.services
// GenesiWidgetEditState -- the editor's live preview, read ahead of the config.
import qs.modules.launcher

Item {
    id: root

    default property alias content: inner.data

    // Set by the host.
    property string widgetName: ""
    property real s: 1
    property Item wallpaper: null

    property real basePadding: 18

    readonly property var cfg: root.widgetName !== "" ? Config.background.widgets[root.widgetName] : null

    // "" means "follow the old cards switch", which is what every widget
    // configured before styles existed has -- so an update changes nothing
    // until somebody picks a style.
    function look(key: string, fallback: var): var {
        return GenesiWidgetEditState.valueOf(root.widgetName, key, fallback);
    }

    readonly property string style: {
        const v = root.look("style", root.cfg?.style ?? "");
        if (v === "glass" || v === "solid" || v === "outline" || v === "minimal")
            return v;
        return Config.background.widgets.cards ? "glass" : "minimal";
    }
    readonly property real alpha: Math.max(0.15, Math.min(1, root.look("opacity", root.cfg?.opacity ?? 1)))
    readonly property string colourMode: root.look("colourMode", root.cfg?.colourMode || "auto")
    readonly property string colourA: root.look("colour", root.cfg?.colour ?? "")
    readonly property string colourB: root.look("colour2", root.cfg?.colour2 ?? "")

    function validColour(c: string): bool {
        return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(c || "");
    }

    readonly property color accent: root.colourMode !== "auto" && root.validColour(root.colourA) ? root.colourA : Colours.palette.m3primary
    readonly property color accent2: {
        if (root.colourMode === "gradient" && root.validColour(root.colourB))
            return root.colourB;
        if (root.colourMode === "auto")
            return Colours.palette.m3tertiary;
        return root.accent;
    }
    readonly property color ink: Colours.palette.m3onSurface
    readonly property color inkDim: Colours.palette.m3onSurfaceVariant
    readonly property color inkFaint: Colours.palette.m3outline
    readonly property color track: Qt.alpha(Colours.palette.m3onSurface, 0.09)

    readonly property real pad: root.basePadding * root.s
    readonly property real corner: 22 * root.s
    readonly property bool plated: root.style === "glass" || root.style === "solid"

    implicitWidth: inner.childrenRect.width + root.pad * 2
    implicitHeight: inner.childrenRect.height + root.pad * 2
    opacity: root.alpha

    Behavior on opacity {
        NumberAnimation {
            duration: 180
        }
    }

    // ── The ground ───────────────────────────────────────────────────────────
    RectangularShadow {
        anchors.fill: plate
        visible: root.plated
        radius: root.corner
        blur: 28 * root.s
        spread: 0
        offset.y: 6 * root.s
        color: Qt.rgba(0, 0, 0, root.style === "solid" ? 0.35 : 0.22)
    }

    // Frosted: the wallpaper behind the widget, blurred and masked to the card.
    Item {
        id: frost

        anchors.fill: parent
        visible: root.style === "glass" && root.wallpaper !== null

        property rect region: Qt.rect(0, 0, 0, 0)

        function sync(): void {
            if (!root.wallpaper || root.width <= 0)
                return;
            const p = root.mapToItem(root.wallpaper, 0, 0);
            const r = Qt.rect(Math.round(p.x), Math.round(p.y), Math.round(root.width), Math.round(root.height));
            if (r.x !== frost.region.x || r.y !== frost.region.y || r.width !== frost.region.width || r.height !== frost.region.height)
                frost.region = r;
        }

        // Where the card is on the wallpaper is not a notifiable property --
        // it depends on every ancestor's position. A slow tick that only
        // reassigns when something moved costs one mapToItem, and keeps the
        // frost under a widget that was just dragged.
        Timer {
            running: frost.visible
            interval: 400
            repeat: true
            triggeredOnStart: true
            onTriggered: frost.sync()
        }

        ShaderEffectSource {
            id: behind

            anchors.fill: parent
            visible: false
            sourceItem: root.wallpaper
            sourceRect: frost.region
        }

        Rectangle {
            id: frostMask

            anchors.fill: parent
            radius: root.corner
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: behind
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: -0.2
            maskEnabled: true
            maskSource: frostMask
            autoPaddingEnabled: false
        }
    }

    Rectangle {
        id: plate

        anchors.fill: parent
        visible: root.style !== "minimal"
        radius: root.corner
        color: {
            if (root.style === "glass")
                return Qt.alpha(Colours.palette.m3surface, root.wallpaper ? 0.55 : 0.7);
            if (root.style === "solid")
                return Colours.palette.m3surfaceContainer;
            // Outline: the faintest tint. Fully clear, light text on a pale
            // sky was a border around nothing legible.
            return Qt.alpha(Colours.palette.m3surface, 0.2);
        }
        border.width: root.style === "outline" ? Math.max(1, 1.5 * root.s) : 1
        border.color: root.style === "outline" ? Qt.alpha(root.accent, 0.6) : Qt.rgba(1, 1, 1, root.style === "glass" ? 0.1 : 0.05)

        // A little light along the top edge, the way real glass catches it.
        Rectangle {
            visible: root.style === "glass"
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 0.07)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.rgba(1, 1, 1, 0)
                }
            }
        }
    }

    // ── The content ──────────────────────────────────────────────────────────
    Item {
        id: inner

        x: root.pad
        y: root.pad
        width: childrenRect.width
        height: childrenRect.height

        // Minimal and outline have no fill to read against, so the content
        // carries its own shadow. Only then: a shadow under text that already
        // sits on a card is mud.
        layer.enabled: root.style === "minimal" || root.style === "outline"
        layer.effect: MultiEffect {
            shadowEnabled: true
            // Strong enough to hold light text on a bright sky. At half this
            // a white clock on a pale wallpaper was simply not there.
            shadowColor: Qt.rgba(0, 0, 0, 0.9)
            shadowBlur: 0.7
            shadowScale: 1.02
            shadowVerticalOffset: 2
            autoPaddingEnabled: true
        }
    }
}
