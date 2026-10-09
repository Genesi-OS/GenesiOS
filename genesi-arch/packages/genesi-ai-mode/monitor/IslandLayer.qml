// The AI island as a wlr-layer-shell surface: KDE Plasma, Niri, COSMIC,
// Sway, labwc (Budgie 10.10, Xfce on Wayland). Anchored to the top edge --
// the compositor centres it -- on the layer above windows, below whatever
// the desktop keeps at the top (a panel's exclusive zone is respected). It
// takes the keyboard only while the card's input is open.
import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

Window {
    id: win

    width: 640
    height: 470
    color: "transparent"
    visible: stage.shown
    title: "Genesi AI Island"

    LayerShell.Window.scope: "genesi-ai-island"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: stage.typing
        ? LayerShell.Window.KeyboardInteractivityExclusive
        : LayerShell.Window.KeyboardInteractivityNone

    IslandStage {
        id: stage

        anchors.fill: parent
        host: islandHost
    }
}
