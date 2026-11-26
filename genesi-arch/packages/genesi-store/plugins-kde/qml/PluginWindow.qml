// A plugin's window on Plasma: a wlr-layer-shell surface (KWin speaks it),
// placed by the compositor at an edge or corner, on the layer the plugin
// belongs to -- the leaf and the Game Center above windows, the weather and
// the turntable on the desktop, under them. PluginWindowPlain.qml is the same
// window without the layer, for where layer-shell is not there (and the tests).
import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

Window {
    id: win

    property string place: "bottom-right"   // top-left ... bottom-right, full, center
    property string layerName: "top"          // top | bottom | overlay
    property bool keyboard: false
    property bool passthrough: false
    property Component body

    color: "transparent"
    flags: win.passthrough ? (Qt.FramelessWindowHint | Qt.WindowTransparentForInput)
                           : Qt.FramelessWindowHint
    visible: true

    LayerShell.Window.scope: "genesi-plugins"
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.layer: win.layerName === "bottom" ? LayerShell.Window.LayerBottom
                           : win.layerName === "overlay" ? LayerShell.Window.LayerOverlay
                           : LayerShell.Window.LayerTop
    LayerShell.Window.keyboardInteractivity: win.keyboard
        ? LayerShell.Window.KeyboardInteractivityOnDemand
        : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.anchors: {
        const A = LayerShell.Window;
        if (win.place === "full")
            return A.AnchorTop | A.AnchorBottom | A.AnchorLeft | A.AnchorRight;
        if (win.place === "center")
            return 0;
        let a = 0;
        if (win.place.startsWith("top")) a |= A.AnchorTop;
        if (win.place.startsWith("bottom")) a |= A.AnchorBottom;
        if (win.place.endsWith("left")) a |= A.AnchorLeft;
        if (win.place.endsWith("right")) a |= A.AnchorRight;
        return a;
    }

    Loader {
        anchors.fill: parent
        sourceComponent: win.body
        focus: true
    }
}
