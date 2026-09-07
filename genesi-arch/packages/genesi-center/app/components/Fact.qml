/*
 * Fact — one labelled reading that does not change.
 *
 * For the things a machine simply IS: the kernel, the processor, when it last
 * updated. No sparkline and no ring, because there is nothing to trend.
 *
 * A missing value prints as an em-dash rather than as an empty row or a zero.
 * The data plane omits what it cannot read on purpose, and "—" is the only
 * honest way to draw that: 0 packages installed and "we could not ask pacman"
 * are different facts and must not look the same.
 */
import QtQuick
import ".."

Column {
    id: root

    property string label: ""
    property string value: ""
    property string sub: ""
    property bool wide: false

    spacing: 4

    // A short rule over each reading. Thirteen label/value pairs in a grid with
    // nothing between them read as a table of contents; the tick is what makes
    // each one read as a separate measurement, and it costs 4px of height.
    // Half-length and left-aligned, so the eye follows the column rather than
    // the row -- a full-width rule here would draw thirteen boxes instead.
    Rectangle {
        width: 14
        height: 1
        color: Tokens.accentDeep
    }

    Text {
        text: root.label.toUpperCase()
        color: Tokens.textFaint
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsMicro
        font.letterSpacing: 1.4
    }
    Text {
        width: root.width
        text: root.value === "" ? "—" : root.value
        color: root.value === "" ? Tokens.textDim : Tokens.textHi
        font.family: Tokens.sans
        font.pixelSize: root.wide ? 13 : 14
        // wrapMode is not optional here: `elide` is ignored on text that spans
        // more than one line without it, so a two-line GPU name ran straight
        // through the cell beside it. maximumLineCount is what keeps a long
        // value from pushing the whole grid row taller than its neighbours.
        wrapMode: Text.Wrap
        maximumLineCount: root.wide ? 2 : 1
        elide: Text.ElideRight
    }
    Text {
        visible: root.sub !== ""
        width: root.width
        text: root.sub
        color: Tokens.textDim
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsMicro
        elide: Text.ElideRight
    }
}
