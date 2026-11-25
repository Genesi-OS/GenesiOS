/*
 * Sparkline — a rolling history drawn as a filled line.
 *
 * Canvas rather than a chart library: this draws one polyline and one gradient,
 * a library would be a dependency for that, and Canvas is in QtQuick already.
 *
 * It keeps its own history. The page hands it one number at a time via push(),
 * which is what a telemetry tick actually produces -- asking the page to keep
 * an array per tile would put the same bookkeeping in six places.
 */
import QtQuick
import ".."

Item {
    id: root

    property int slots: 40
    property real minimum: 0
    property real maximum: 100
    property color stroke: Tokens.accent
    property var values: []

    function push(v) {
        if (v === null || v === undefined || isNaN(v))
            return;
        const next = values.slice();
        next.push(Number(v));
        while (next.length > slots)
            next.shift();
        values = next;
        canvas.requestPaint();
    }

    function seed(v) {
        // A tile with one sample draws a dot in the corner and reads as broken.
        // Filling the history with the first reading means the line starts flat
        // and true, then diverges as real samples arrive.
        if (v === null || v === undefined || isNaN(v))
            return;
        const next = [];
        for (let i = 0; i < slots; i++)
            next.push(Number(v));
        values = next;
        canvas.requestPaint();
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = root.values.length;
            if (n < 2)
                return;

            const span = Math.max(1e-6, root.maximum - root.minimum);
            const stepX = width / (root.slots - 1);
            const y = v => height - ((Math.max(root.minimum, Math.min(root.maximum, v)) - root.minimum) / span) * height;
            // Right-aligned: a partly filled history should grow leftward from
            // "now" rather than stretch to fit, or the line's slope would lie
            // while the buffer fills.
            const x0 = width - (n - 1) * stepX;

            ctx.beginPath();
            ctx.moveTo(x0, y(root.values[0]));
            for (let i = 1; i < n; i++)
                ctx.lineTo(x0 + i * stepX, y(root.values[i]));

            const line = ctx.currentPath;
            ctx.lineWidth = 1.4;
            ctx.strokeStyle = root.stroke;
            ctx.stroke();

            ctx.lineTo(width, height);
            ctx.lineTo(x0, height);
            ctx.closePath();
            const g = ctx.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0, Qt.rgba(root.stroke.r, root.stroke.g, root.stroke.b, 0.22));
            g.addColorStop(1, Qt.rgba(root.stroke.r, root.stroke.g, root.stroke.b, 0.0));
            ctx.fillStyle = g;
            ctx.fill();
        }
    }
}
