// The turntable on Plasma: caelestia's GenesiVinylDeck on the desktop
// (under windows), playing whatever MPRIS player is active -- read and driven
// through playerctl by the host. Hidden while nothing plays a track.
import QtQuick
import QtQuick.Window

Item {
    id: root

    readonly property var p: host.player

    function pushMask(): void {
        const w = root.Window.window;
        if (w)
            host.setInputRect(w, holder.x, holder.y, holder.width, holder.height);
    }
    onWidthChanged: Qt.callLater(root.pushMask)
    Component.onCompleted: Qt.callLater(root.pushMask)

    Item {
        id: holder

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        width: Math.min(parent.width - 32, deck.implicitWidth)
        height: Math.min(parent.height - 32, deck.implicitHeight)
        opacity: root.p.present ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        GenesiVinylDeck {
            id: deck

            anchors.fill: parent
            pal: host.palette
            playing: root.p.playing === true
            present: root.p.present === true
            title: root.p.title ?? ""
            artist: root.p.artist ?? ""
            art: root.p.art ?? ""
            progress: root.p.progress ?? 0

            onToggle: host.playerCommand("play-pause")
            onNext: host.playerCommand("next")
            onPrevious: host.playerCommand("previous")
        }
    }
}
