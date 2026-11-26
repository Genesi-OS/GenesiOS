// PluginWindow.qml without the layer surface: where layer-shell-qt is not
// available, and offscreen in ci/plugins-kde-test.py. Same properties.
import QtQuick
import QtQuick.Window

Window {
    id: win

    property string place: "bottom-right"
    property string layerName: "top"
    property bool keyboard: false
    property bool passthrough: false
    property Component body

    color: "transparent"
    flags: win.passthrough ? (Qt.FramelessWindowHint | Qt.WindowTransparentForInput)
                           : (Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
    visible: true

    Loader {
        anchors.fill: parent
        sourceComponent: win.body
        focus: true
    }
}
