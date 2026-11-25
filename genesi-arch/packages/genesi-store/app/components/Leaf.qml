// GENESI STORE — the Genesi mark.
//
// THE mark, not a leaf somebody drew: the same outline and the same five veins
// as genesi-plymouth's logo.svg and the 256px icon the system ships, scaled
// out of their 256 viewBox. The first version of this file was a shape I made
// up, and a store wearing an invented version of its own logo is the one thing
// on the desktop that cannot be explained away.
//
// Drawn rather than loaded from the SVG so it takes whatever colour it is
// given -- the rail wants it green, a card wants it in the item's accent, the
// queue bar spins it -- and stays sharp at any size.
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color colour: "#8be8c8"
    // The original is a 13px outline and 10px veins in a 256 box. Everything
    // below is that, as a fraction, so the mark keeps its weight at any size.
    readonly property real unit: Math.min(width, height) / 256

    implicitWidth: 24
    implicitHeight: 24

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The outline.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 13 * root.unit
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (18 - 9) * root.unit
            PathCubic {
                x: 48 * root.unit
                y: (157 - 9) * root.unit
                control1X: 76 * root.unit
                control1Y: (52 - 9) * root.unit
                control2X: 48 * root.unit
                control2Y: (104 - 9) * root.unit
            }
            PathCubic {
                x: 128 * root.unit
                y: (256 - 9) * root.unit
                control1X: 48 * root.unit
                control1Y: (202 - 9) * root.unit
                control2X: 79 * root.unit
                control2Y: (233 - 9) * root.unit
            }
            PathCubic {
                x: 208 * root.unit
                y: (157 - 9) * root.unit
                control1X: 177 * root.unit
                control1Y: (233 - 9) * root.unit
                control2X: 208 * root.unit
                control2Y: (202 - 9) * root.unit
            }
            PathCubic {
                x: 128 * root.unit
                y: (18 - 9) * root.unit
                control1X: 208 * root.unit
                control1Y: (104 - 9) * root.unit
                control2X: 180 * root.unit
                control2Y: (52 - 9) * root.unit
            }
        }

        // The midrib.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 10 * root.unit
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (69 - 9) * root.unit
            PathLine {
                x: 128 * root.unit
                y: (220 - 9) * root.unit
            }
        }

        // Four veins, two a side.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 10 * root.unit
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (112 - 9) * root.unit
            PathLine {
                x: 87 * root.unit
                y: (138 - 9) * root.unit
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 10 * root.unit
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (151 - 9) * root.unit
            PathLine {
                x: 85 * root.unit
                y: (179 - 9) * root.unit
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 10 * root.unit
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (112 - 9) * root.unit
            PathLine {
                x: 169 * root.unit
                y: (138 - 9) * root.unit
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colour
            strokeWidth: 10 * root.unit
            capStyle: ShapePath.RoundCap

            startX: 128 * root.unit
            startY: (151 - 9) * root.unit
            PathLine {
                x: 171 * root.unit
                y: (179 - 9) * root.unit
            }
        }
    }
}
