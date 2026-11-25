// GENESI — one desktop widget, wrapped.
//
// Builds the widget by name, scales it, and in arrange mode gives it the two
// things a widget needs to be moved: an outline saying it can be, and a way to
// move it.
//
// ── Everything is draggable in arrange mode ─────────────────────────────────
//
// A widget in a corner lives inside a Column, and a Column SETS the x and y of
// everything in it. A drag handler writing x and y to the same item is two
// things assigning one property every frame, and what that looks like is not a
// widget being dragged -- it is a widget vibrating.
//
// The first answer to that was two gestures: UNPIN a corner widget, then drag
// it. Two problems. It is not what anybody means by "move it", and the pill sat
// under the widget -- which is off the bottom of the screen for anything
// anchored there.
//
// So arrange mode moves every widget into the free layer instead, seeded from
// where it already was. One gesture, no positioner to fight, nothing jumps.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher

Item {
    id: host

    required property string widget
    // Which corner it is anchored in, or "free". Only used to scale from the
    // right edge, so growing a widget does not push it off the screen.
    property string corner: "top-left"
    property bool arranging: false
    // The item the drag moves -- the wrapper that owns this host's position.
    // Null means "not draggable", which is every widget while arrange mode is
    // off, and none of them while it is on.
    property Item dragTarget: null

    // The wallpaper item, for the frosted style to blur.
    property Item wallpaper: null

    signal dropped
    // Right-click on the widget itself: the editor, not the desktop menu.
    signal editRequested(real x, real y)

    readonly property var cfg: Config.background.widgets[host.widget]
    readonly property real factor: Math.max(0.5, Math.min(2.5, GenesiWidgetEditState.valueOf(host.widget, "scale", host.cfg?.scale ?? 1)))

    implicitWidth: body.item ? body.item.implicitWidth : 0
    implicitHeight: body.item ? body.item.implicitHeight : 0

    Loader {
        id: body

        // Built by name. The file, the config key and this string are one
        // identifier, so a widget that exists is reachable and one that is not
        // fails visibly at its own Loader instead of quietly not being drawn.
        source: Qt.resolvedUrl("GenesiWidget" + host.widget.charAt(0).toUpperCase() + host.widget.slice(1) + ".qml")
        asynchronous: true

        // NOT scaled. A `scale:` here stretched natively-rendered text to
        // twice its pixels -- "the widgets get pixelated when they are made
        // bigger". The widget is told its size instead and draws itself at it.
        opacity: status === Loader.Ready ? 1 : 0

        Behavior on opacity {
            Anim {}
        }
    }

    Binding {
        target: body.item
        property: "s"
        value: host.factor
        when: body.status === Loader.Ready
    }
    Binding {
        target: body.item
        property: "widgetName"
        value: host.widget
        when: body.status === Loader.Ready
    }
    Binding {
        target: body.item
        property: "wallpaper"
        value: host.wallpaper
        when: body.status === Loader.Ready
    }

    // Above the desktop's own right-click handler, so a right-click ON a widget
    // edits that widget, and a right-click anywhere else still opens the
    // desktop menu.
    MouseArea {
        anchors.fill: parent
        enabled: !host.arranging
        acceptedButtons: Qt.RightButton
        onClicked: event => host.editRequested(event.x, event.y)
    }

    // ── Arrange mode ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        visible: host.arranging
        color: "transparent"
        radius: Tokens.rounding.large
        border.width: 1
        border.color: drag.active ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.5)

        Behavior on border.color {
            CAnim {}
        }
    }

    DragHandler {
        id: drag

        // `target: null` would mean a gesture that exists and moves nothing,
        // which is worse than no gesture at all. `enabled` is what keeps it off
        // when there is nothing for it to move.
        enabled: host.arranging && host.dragTarget !== null
        target: host.dragTarget
        cursorShape: Qt.ClosedHandCursor

        onActiveChanged: if (!active)
            host.dropped()
    }

}
