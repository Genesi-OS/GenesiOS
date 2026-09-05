/*
 * GridTexture — the fine mesh behind the centre of the page.
 *
 * The mockup's ground is not flat black: there is a faint square lattice under
 * the art and the telemetry, and it is what stops a very dark page from
 * reading as an empty void. It carries no information, which is exactly why it
 * is drawn rather than composed -- an image would be an asset to ship and
 * scale, and this is nine lines of Canvas.
 *
 * Two densities: a fine cell, and a heavier line every `major` cells. One grid
 * alone reads as graph paper; the second rhythm is what makes it read as an
 * instrument panel.
 */
import QtQuick
import ".."

Canvas {
    id: root

    property int cell: 22
    property int major: 4
    property real fine: 0.055
    property real bold: 0.10

    renderStrategy: Canvas.Cooperative
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const c = Tokens.accent;

        for (let pass = 0; pass < 2; pass++) {
            const step = pass === 0 ? root.cell : root.cell * root.major;
            ctx.beginPath();
            for (let x = 0; x <= width; x += step) {
                if (pass === 0 && (x % (root.cell * root.major)) === 0)
                    continue;   // the major pass draws this one
                ctx.moveTo(Math.floor(x) + 0.5, 0);
                ctx.lineTo(Math.floor(x) + 0.5, height);
            }
            for (let y = 0; y <= height; y += step) {
                if (pass === 0 && (y % (root.cell * root.major)) === 0)
                    continue;
                ctx.moveTo(0, Math.floor(y) + 0.5);
                ctx.lineTo(width, Math.floor(y) + 0.5);
            }
            ctx.lineWidth = 1;
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b,
                                      pass === 0 ? root.fine : root.bold);
            ctx.stroke();
        }
    }
}
