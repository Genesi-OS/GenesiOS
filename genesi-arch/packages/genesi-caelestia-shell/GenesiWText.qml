// GENESI — text on a desktop widget, drawn at the size it is shown.
//
// Every widget used to be built at one size and then SCALED by a transform.
// caelestia's StyledText renders with Text.NativeRendering, which rasterises
// each glyph at the font's own size -- so a widget scaled to 2x showed those
// glyphs stretched to twice their pixels, which is exactly "they get pixelated
// when you make them bigger".
//
// So nothing is scaled any more. Every widget carries `s`, and this multiplies
// the pixel size by it: a 2x widget asks the font for a 2x glyph. Large display
// numbers use CurveRendering, which is crisp at any size; body text stays
// hinted, which is sharper than curves at small sizes.
import QtQuick
import Caelestia.Config

Text {
    id: root

    property real s: 1
    property real size: 14
    property real tracking: 0

    font.family: Tokens.font.body.medium.family
    font.pixelSize: Math.max(1, Math.round(root.size * root.s))
    font.letterSpacing: root.tracking * root.s
    renderType: font.pixelSize >= 30 ? Text.CurveRendering : Text.NativeRendering
    textFormat: Text.PlainText
}
