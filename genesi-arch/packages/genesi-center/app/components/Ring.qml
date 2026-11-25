/*
 * Ring — the storage donut.
 *
 * Segments are given as [{ gb, color }] and drawn in order clockwise from
 * twelve o'clock. The sweep animates from nothing on first paint, which is the
 * one place in this app where motion carries meaning rather than polish: a ring
 * that draws itself says the number was measured just now.
 */
import QtQuick
import ".."

Item {
    id: root

    property var segments: []
    property real total: 0
    property real thickness: 14
    property real progress: 0     // 0..1, animated by reveal()

    function reveal() {
        progress = 0;
        sweep.restart();
    }

    onSegmentsChanged: canvas.requestPaint()
    onProgressChanged: canvas.requestPaint()

    NumberAnimation {
        id: sweep
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Tokens.entrance
        easing.type: Easing.OutCubic
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const r = Math.min(width, height) / 2 - root.thickness / 2;
            if (r <= 0)
                return;

            // The track first, so a disk that is mostly empty still reads as a
            // ring rather than as a stray arc.
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.lineWidth = root.thickness;
            ctx.strokeStyle = Tokens.lineSoft;
            ctx.stroke();

            const total = root.total > 0 ? root.total : 1;
            let angle = -Math.PI / 2;
            for (const s of root.segments) {
                const frac = Math.max(0, (s.gb || 0) / total) * root.progress;
                if (frac <= 0)
                    continue;
                const end = angle + frac * Math.PI * 2;
                ctx.beginPath();
                ctx.arc(cx, cy, r, angle, end);
                ctx.lineWidth = root.thickness;
                ctx.lineCap = "butt";
                ctx.strokeStyle = s.color;
                ctx.stroke();
                angle = end;
            }
        }
    }
}
