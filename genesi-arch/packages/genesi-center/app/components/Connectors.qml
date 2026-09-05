/*
 * Connectors — the hairlines from the readings to the artwork.
 *
 * The single most distinctive thing the reference does: thin lines leaving the
 * data and landing on the image, each ending in a small node. They carry no
 * information, and that is fine -- their job is to say that the picture and the
 * numbers are one composition rather than two panels side by side.
 *
 * Drawn, not composed: a Canvas polyline costs nothing and scales with the
 * window, where a set of positioned Rectangles would have to be re-laid out
 * every resize.
 *
 * `progress` draws them. Each line has its own slice of the sweep, so they
 * arrive in sequence rather than all at once -- one line appearing is a stroke,
 * five appearing together is a flash.
 */
import QtQuick
import ".."

Item {
    id: root

    // Each entry is fractions of this item's size: where the line starts, and
    // the node it ends on.
    property var links: []
    property real progress: 0
    property color stroke: Tokens.accentDim

    function draw() {
        root.progress = 0;
        sweep.restart();
    }

    onProgressChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    NumberAnimation {
        id: sweep
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Tokens.entrance * 2
        easing.type: Easing.OutCubic
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = root.links.length;
            if (n === 0 || width <= 0)
                return;

            for (let i = 0; i < n; i++) {
                const l = root.links[i];
                // Stagger: line i occupies the middle of the sweep offset by
                // its index, clamped so the last one still finishes.
                const slice = 1 / (n + 2);
                const t = Math.max(0, Math.min(1, (root.progress - i * slice) / (slice * 3)));
                if (t <= 0)
                    continue;

                const x1 = l.x1 * width, y1 = l.y1 * height;
                const x2 = l.x2 * width, y2 = l.y2 * height;
                // A short horizontal lead before the diagonal, so the line
                // leaves the data squarely and only then travels.
                const lead = Math.min(26, (x2 - x1) * 0.22);
                const cx = x1 + lead;

                const ex = x1 + (x2 - x1) * t;
                const ey = y1 + (y2 - y1) * t;

                ctx.beginPath();
                ctx.moveTo(x1, y1);
                if (ex > cx) {
                    ctx.lineTo(cx, y1);
                    ctx.lineTo(ex, ey);
                } else {
                    ctx.lineTo(ex, y1);
                }
                ctx.lineWidth = 1;
                ctx.strokeStyle = Qt.rgba(root.stroke.r, root.stroke.g, root.stroke.b, 0.70);
                ctx.stroke();

                if (t >= 1) {
                    ctx.beginPath();
                    ctx.arc(x2, y2, 2.4, 0, Math.PI * 2);
                    ctx.fillStyle = Tokens.accent;
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(x2, y2, 5.5, 0, Math.PI * 2);
                    ctx.strokeStyle = Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                              Tokens.accent.b, 0.28);
                    ctx.stroke();
                }
            }
        }
    }
}
