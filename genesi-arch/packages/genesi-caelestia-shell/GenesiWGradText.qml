// GENESI — a headline painted with the widget's colours.
//
// In gradient mode a big number is the most visible place for the gradient to
// be, and a Text takes one colour. So the letters are used as a MASK over a
// gradient: they are cut out of it.
//
// The mask is a ShaderEffectSource with hideSource, not the label with
// `visible: false`. An invisible item renders nothing into its layer, and a
// MultiEffect handed an empty mask draws its source unmasked -- which is how
// the first version of this drew every percentage as a solid coloured block.
//
// And the threshold is not 0. MultiEffect hides what is BELOW the threshold,
// so at 0 nothing is below it and the whole rectangle shows -- the second way
// the percentages came out as blocks. The spread keeps the glyph edges soft.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    property alias text: label.text
    property alias s: label.s
    property alias size: label.size
    property alias tracking: label.tracking
    property alias fontWeight: label.font.weight
    property color from: "white"
    property color to: root.from
    readonly property bool gradient: !Qt.colorEqual(root.from, root.to)

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    GenesiWText {
        id: label

        color: root.from
    }

    ShaderEffectSource {
        id: letters

        anchors.fill: label
        sourceItem: label
        hideSource: root.gradient
        visible: false
    }

    Rectangle {
        id: fill

        anchors.fill: label
        visible: false
        // Always on, not `root.gradient`. A layer switched on LATER on an item
        // that is not visible is never rendered, so a widget going from one
        // colour to a gradient -- which is what the editor does, and what a
        // widget does when its config arrives a frame after it is built --
        // masked an empty texture and its headline number vanished. The
        // rectangle is the size of a word; the texture costs nothing.
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: root.from
            }
            GradientStop {
                position: 1
                color: root.to
            }
        }
    }

    MultiEffect {
        anchors.fill: label
        visible: root.gradient
        source: fill
        maskEnabled: true
        maskSource: letters
        maskThresholdMin: 0.45
        maskSpreadAtMin: 0.4
        autoPaddingEnabled: false
    }
}
