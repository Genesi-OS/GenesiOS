// GENESI — the frame every desktop widget sits in.
//
// One place decides how a widget is bounded, so fourteen of them cannot drift
// apart: the same padding, the same corner, the same translucent ground, and
// one switch (`background.widgets.cards`) that turns the ground off for people
// who want them floating on the wallpaper the way the clock does.
//
// The content is measured with childrenRect and drawn at a fixed offset rather
// than anchored to the middle. A child anchored to a parent that sizes itself
// FROM that child is the classic QML binding loop, and it does not announce
// itself -- it just settles on a wrong size or spins.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    default property alias content: inner.data
    property int padding: Tokens.padding.large

    readonly property bool card: Config.background.widgets.cards

    implicitWidth: inner.childrenRect.width + root.padding * 2
    implicitHeight: inner.childrenRect.height + root.padding * 2

    radius: Tokens.rounding.large
    color: root.card ? Qt.alpha(Colours.palette.m3surfaceContainer, 0.55) : "transparent"
    border.width: root.card ? 1 : 0
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.45)

    Behavior on color {
        CAnim {}
    }

    Item {
        id: inner

        x: root.padding
        y: root.padding
    }
}
