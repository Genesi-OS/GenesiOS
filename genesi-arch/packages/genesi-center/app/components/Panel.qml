/*
 * Panel — the card everything sits in.
 *
 * One hairline border and a barely-there fill, because the ground is nearly
 * black and a heavier surface would turn the page into a stack of boxes. The
 * hover lift is on the border, not the background: it says "this is live"
 * without the card jumping.
 */
import QtQuick
import ".."

Rectangle {
    id: root
    property bool interactive: false
    property bool hovered: false

    color: Tokens.card
    radius: Tokens.radius
    border.width: 1
    border.color: root.interactive && root.hovered ? Tokens.accentDim : Tokens.line

    Behavior on border.color {
        ColorAnimation { duration: Tokens.quick }
    }
}
