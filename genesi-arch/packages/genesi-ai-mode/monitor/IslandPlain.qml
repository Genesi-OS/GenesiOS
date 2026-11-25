// The AI island as an ordinary window placed at the top centre: every X11
// desktop (Xfce, Cinnamon, LXDE, MATE, Budgie on X11) and GNOME on Wayland
// through XWayland, where a Wayland surface cannot ask for a position. A
// frameless tool window that stays on top and out of the taskbar; it asks
// for focus when the card's input opens.
import QtQuick
import QtQuick.Window

Window {
    id: win

    width: 640
    height: 470
    x: islandHost.placeX
    y: islandHost.placeY
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    visible: stage.shown
    title: "Genesi AI Island"

    IslandStage {
        id: stage

        anchors.fill: parent
        host: islandHost
        onTypingChanged: if (stage.typing) win.requestActivate()
    }
}
