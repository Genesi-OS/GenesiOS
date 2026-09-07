/*
 * Panel — the card everything sits in.
 *
 * One hairline border and a barely-there fill, because the ground is nearly
 * black and a heavier surface would turn the page into a stack of boxes. The
 * hover lift is on the border, not the background: it says "this is live"
 * without the card jumping.
 *
 * ── The corner ticks ─────────────────────────────────────────────────────────
 *
 * A hairline rectangle is a container, not a design. Sixty-two of them stacked
 * down a page read as a form, which is what the grids on this app looked like:
 * correct, legible, and anonymous. The ticks are the smallest mark that fixes
 * that -- two L-brackets on opposite corners, the convention every technical
 * drawing and instrument face uses to say "this is a measured area".
 *
 * DIAGONAL, not all four. Four corners frames the card and turns it back into a
 * box; two make it read as a crop mark, which is the whole point. They sit
 * INSIDE the rounded corner (7px, radius is 10) so they never fight the border
 * they are drawn against.
 *
 * `tag` is the same trick SectionHead uses on sections, applied to cards: one
 * micro monospace label in the top-right corner. It costs a line and gives a
 * grid of tiles a spine.
 *
 * All of it is above the page's own content (z: 1) rather than under it. A card
 * whose children fill it -- and several do -- would otherwise paint over the
 * marks and the personality would be there on some cards and not others, which
 * is worse than not having it. The marks live in the corners at a 7px inset,
 * where nothing else in this app draws.
 */
import QtQuick
import ".."

Rectangle {
    id: root

    property bool interactive: false
    property bool hovered: false

    // The corner ticks. Off for a card that is already carrying a drawing of
    // its own, where they would be the second frame in the same 100px.
    property bool ticks: true
    // A micro label in the top-right. Empty draws nothing.
    property string tag: ""

    readonly property bool live: root.interactive && root.hovered

    color: Tokens.card
    radius: Tokens.radius
    border.width: 1
    border.color: root.live ? Tokens.accentDim : Tokens.line

    Behavior on border.color {
        ColorAnimation { duration: Tokens.quick }
    }

    // ── The marks ────────────────────────────────────────────────────────────
    Item {
        id: marks

        anchors.fill: parent
        z: 1

        readonly property color ink: root.live ? Tokens.accent : Tokens.accentDeep
        readonly property int inset: 7
        readonly property int arm: 10

        // Top-left bracket.
        Rectangle {
            visible: root.ticks
            x: marks.inset; y: marks.inset
            width: marks.arm; height: 1
            color: marks.ink
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
        }
        Rectangle {
            visible: root.ticks
            x: marks.inset; y: marks.inset
            width: 1; height: marks.arm
            color: marks.ink
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
        }

        // Bottom-right bracket.
        Rectangle {
            visible: root.ticks
            x: parent.width - marks.inset - marks.arm
            y: parent.height - marks.inset - 1
            width: marks.arm; height: 1
            color: marks.ink
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
        }
        Rectangle {
            visible: root.ticks
            x: parent.width - marks.inset - 1
            y: parent.height - marks.inset - marks.arm
            width: 1; height: marks.arm
            color: marks.ink
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
        }

        // The tag, in the corner the top-left bracket leaves empty.
        Text {
            visible: root.tag !== ""
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 12
            anchors.topMargin: 10
            text: root.tag.toUpperCase()
            color: root.live ? Tokens.accentDim : Tokens.textFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.2
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
        }

        // A hairline along the top edge that runs out from the left on hover.
        // The border already brightens; this is what makes the card feel
        // switched on rather than merely outlined.
        Rectangle {
            visible: root.interactive
            x: root.radius
            y: 0
            height: 1
            width: root.live ? Math.max(0, parent.width - root.radius * 2) : 0
            color: Tokens.accent
            opacity: 0.75
            Behavior on width {
                NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic }
            }
        }
    }
}
