// GENESI STORE — the leaf.
//
// Genesi's mark, drawn rather than shipped as an image so it takes the colour
// it is given and stays sharp at any size. Two arcs and a vein: a leaf is the
// simplest shape that reads as "something alive", which is the whole idea the
// store is built on.
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color colour: "#39d98a"
    property real thickness: Math.max(1, width * 0.06)
    // 0 draws only the outline, 1 fills it.
    property real fill: 1

    implicitWidth: 22
    implicitHeight: 22

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fill > 0 ? Qt.rgba(root.colour.r, root.colour.g, root.colour.b, root.fill) : "transparent"
            strokeColor: root.colour
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            // A leaf is two arcs meeting at a point twice: up the left
            // side to the tip, down the right side back to the base. Four
            // cubics drew something rounder at both ends -- a pebble.
            startX: root.width * 0.5
            startY: root.height * 0.04
            PathQuad {
                x: root.width * 0.5
                y: root.height * 0.96
                controlX: root.width * -0.12
                controlY: root.height * 0.34
            }
            PathQuad {
                x: root.width * 0.5
                y: root.height * 0.04
                controlX: root.width * 1.12
                controlY: root.height * 0.66
            }
        }

        // The vein, always a line so the leaf does not read as a pebble.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.fill > 0.5 ? Qt.rgba(0, 0, 0, 0.35) : root.colour
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            startX: root.width * 0.5
            startY: root.height * 0.9
            PathQuad {
                x: root.width * 0.5
                y: root.height * 0.12
                controlX: root.width * 0.42
                controlY: root.height * 0.5
            }
        }
    }
}
