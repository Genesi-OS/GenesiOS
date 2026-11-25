// GENESI — a Material Symbol on a desktop widget, at its real size.
//
// The same reason as GenesiWText: MaterialIcon renders natively at a fixed
// size, and a transform made it blurry. The icon font is variable, so the
// optical size follows the pixel size as well -- a big icon is drawn with the
// big-size design, not the small one stretched.
import QtQuick
import Caelestia.Config

Text {
    id: root

    property real s: 1
    property real size: 24
    // 0 outlined, 1 filled.
    property real fill: 0

    font.family: Tokens.font.icon.medium.family || "Material Symbols Rounded"
    font.pixelSize: Math.max(1, Math.round(root.size * root.s))
    font.variableAxes: ({
            "FILL": root.fill,
            "opsz": Math.max(20, Math.min(48, root.size * root.s)),
            "wght": 400
        })
    renderType: font.pixelSize >= 30 ? Text.CurveRendering : Text.NativeRendering
    textFormat: Text.PlainText
}
