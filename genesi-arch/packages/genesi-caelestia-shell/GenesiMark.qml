// GENESI — the mark, drawn rather than loaded.
//
// A Shape with two stroked paths, not an Image pointed at genesi-leaf.svg, and
// the reason is colour: an SVG carries its own #1d9e75 and #34d399 baked into
// the file, so on a violet scheme the one Genesi thing on the bar would be the
// one green thing on the bar. Drawn, it takes `Colours.palette` like everything
// else and the mark belongs to whatever the desktop currently is.
//
// This is also how caelestia draws its own logo (components/Logo.qml): a Shape
// of PathSvg data with the fill colours bound to the palette. Same mechanism,
// so there is one way a shell logo works here rather than two.
//
// The paths are the 24x24 artwork from genesi-leaf.svg verbatim -- the leaf
// outline and the pulse across it. Scaled by the Shape rather than by the
// viewBox, so the stroke stays proportional at any size the bar asks for.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

Item {
    id: root

    readonly property real designSize: 24

    // The outline takes the primary and the pulse the secondary, which is the
    // same relationship the artwork had (deep green, bright green) expressed in
    // scheme roles instead of hex.
    property color leafColour: Colours.palette.m3primary
    property color pulseColour: Colours.palette.m3secondary
    property real thickness: 1.8

    implicitWidth: designSize
    implicitHeight: designSize

    Shape {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: Math.min(root.width / width, root.height / height)
        transformOrigin: Item.Center
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.leafColour
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: "M12 2.5C8.4 5 6.4 8.6 6.4 13.2C6.4 17.8 9 20.9 12 22.5C15 20.9 17.6 17.8 17.6 13.2C17.6 8.6 15.6 5 12 2.5Z"
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.pulseColour
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: "M7.8 13.4h2.1l1.3-3.2 1.6 5.2 1.1-2h1.9"
            }
        }
    }
}
