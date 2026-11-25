import QtQuick
import ".."

Text {
    property bool dim: false
    color: dim ? BarTokens.text : BarTokens.textHi
    font.family: BarTokens.sans
    font.pixelSize: 12
    elide: Text.ElideRight
}
