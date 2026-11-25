// GENESI — a progress ring whose arc can carry a gradient.
//
// A Shape stroke takes one colour, so the arc is drawn as a FILLED annular
// sector instead -- the band between two arcs, with round ends -- and that
// fill takes a conical gradient. Curve-rendered, so it stays smooth at any
// size instead of being a canvas bitmap stretched by a transform.
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real s: 1
    property real size: 64
    property real thickness: 7
    property real value: 0
    property color from: "white"
    property color to: root.from
    property color track: Qt.rgba(1, 1, 1, 0.08)

    readonly property real v: Math.max(0, Math.min(1, root.value))
    readonly property real t: root.thickness * root.s
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2
    readonly property real mid: root.width / 2 - root.t / 2

    implicitWidth: root.size * root.s
    implicitHeight: root.size * root.s

    // SVG arc from the top, clockwise, for a fraction of the circle.
    function sector(frac: real): string {
        const R = root.mid + root.t / 2;
        const r = root.mid - root.t / 2;
        const c = root.t / 2;
        const a0 = -Math.PI / 2;
        const a1 = a0 + Math.PI * 2 * Math.min(frac, 0.9999);
        const large = frac > 0.5 ? 1 : 0;
        const p = (rad, a) => `${(root.cx + rad * Math.cos(a)).toFixed(2)} ${(root.cy + rad * Math.sin(a)).toFixed(2)}`;
        return `M ${p(R, a0)} A ${R} ${R} 0 ${large} 1 ${p(R, a1)} ` + `A ${c} ${c} 0 0 1 ${p(r, a1)} ` + `A ${r} ${r} 0 ${large} 0 ${p(r, a0)} ` + `A ${c} ${c} 0 0 1 ${p(R, a0)} Z`;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.track
            strokeWidth: root.t
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.mid
                radiusY: root.mid
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            strokeWidth: -1
            // The conical gradient runs counter-clockwise from its angle, and
            // the ring fills clockwise from the top: so it starts at the top
            // and the stops are laid out from the far end back. Nudged past
            // the top by the width of the round start cap, which otherwise
            // straddles the seam and picks up the END colour.
            fillGradient: ConicalGradient {
                centerX: root.cx
                centerY: root.cy
                angle: 90 + (root.mid > 0 ? (root.t / 2) / root.mid * 180 / Math.PI : 0)

                GradientStop {
                    position: 0
                    color: root.to
                }
                GradientStop {
                    position: Math.max(0.001, 1 - root.v)
                    color: root.to
                }
                GradientStop {
                    position: 1
                    color: root.from
                }
            }

            PathSvg {
                path: root.v > 0.004 ? root.sector(root.v) : ""
            }
        }
    }
}
