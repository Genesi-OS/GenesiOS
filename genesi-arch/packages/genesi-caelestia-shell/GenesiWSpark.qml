// GENESI — a sparkline: the last minute or so of a reading, as a line and a
// fading area under it. A number says how busy the machine is now; the line
// says whether that is a spike or the way it has been all afternoon.
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real s: 1
    // Fractions, oldest first.
    property var values: []
    property color colour: "white"
    property real lineWidth: 2

    function points(closed: bool): string {
        const vs = root.values || [];
        if (vs.length < 2 || root.width <= 0 || root.height <= 0)
            return "";
        const w = root.width;
        const h = root.height;
        const lw = root.lineWidth * root.s;
        const step = w / (vs.length - 1);
        let d = "";
        for (let i = 0; i < vs.length; ++i) {
            const v = Math.max(0, Math.min(1, vs[i] || 0));
            const y = lw + (h - lw * 2) * (1 - v);
            d += (i === 0 ? "M " : " L ") + (i * step).toFixed(2) + " " + y.toFixed(2);
        }
        if (closed)
            d += ` L ${w.toFixed(2)} ${h.toFixed(2)} L 0 ${h.toFixed(2)} Z`;
        return d;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height

                GradientStop {
                    position: 0
                    color: Qt.alpha(root.colour, 0.32)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(root.colour, 0)
                }
            }

            PathSvg {
                path: root.points(true)
            }
        }

        ShapePath {
            strokeColor: root.colour
            strokeWidth: root.lineWidth * root.s
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.points(false)
            }
        }
    }
}
