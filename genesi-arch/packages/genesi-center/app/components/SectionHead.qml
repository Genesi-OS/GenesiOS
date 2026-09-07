/*
 * SectionHead — the numbered rule above every block.
 *
 * The numbering is the ornament. It costs one line and gives the page a spine,
 * which is the whole trick behind instrument panels reading as designed rather
 * than as a grid of widgets.
 *
 * The rule is the other half of that, and for a long time this component was
 * named for a line it did not draw: a bare label floating over a card reads as
 * a caption, while a label with a hairline running out of it to the edge of the
 * page reads as a division. It fades out rather than stopping, because a line
 * that ends in mid-air is a mistake and a line that ends AT the edge boxes the
 * page in.
 *
 * `rule: false` for the one place a SectionHead shares a Row with something
 * else -- there the line would fill the row and push its neighbour off the end.
 */
import QtQuick
import ".."

Row {
    id: root

    property string index: "01"
    property string text: ""
    property bool rule: true

    spacing: 8

    Text {
        text: root.index
        color: Tokens.accentDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: "//"
        visible: root.index !== "//"
        color: Tokens.textFaint
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: root.text.toUpperCase()
        color: Tokens.textDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
        font.letterSpacing: 1.6
        anchors.verticalCenter: parent.verticalCenter
    }

    // Fills whatever the labels left. `x` is set by the Row from the widths
    // BEFORE this one, so measuring the remainder from it cannot depend on this
    // item's own width -- which is what would make it a binding loop.
    Item {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.rule && width > 4
        width: root.parent ? Math.max(0, root.parent.width - x - 2) : 0
        height: 5

        Rectangle {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Tokens.line }
                GradientStop { position: 0.7; color: Tokens.lineSoft }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(Tokens.lineSoft.r, Tokens.lineSoft.g, Tokens.lineSoft.b, 0)
                }
            }
        }

        // A tick at the far end, so the rule terminates in a mark instead of
        // dissolving into nothing.
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 1; height: 5
            color: Tokens.accentDeep
        }
    }
}
