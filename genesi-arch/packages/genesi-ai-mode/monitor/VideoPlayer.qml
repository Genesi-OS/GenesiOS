/*
 * Genesi AI Mode Monitor — the Video page's player.
 *
 * Its own file, loaded by the page through a Loader, on purpose: the
 * QtMultimedia QML module ships in a separate package (qt6-multimedia plus a
 * backend), and an `import QtMultimedia` that fails takes the WHOLE file down
 * with it. Here it can only take the player down -- the page sees the
 * Loader's error and shows the clip's poster and an "Open in player" button
 * instead. ci/video-cli-test.py loads the page with this file broken to hold
 * that line.
 */
import QtQuick
import QtMultimedia

Item {
    id: root
    property url source
    property bool muted: false
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property real position: player.position
    readonly property real duration: player.duration
    readonly property bool failed: player.error !== MediaPlayer.NoError
    readonly property string errorText: player.errorString

    function toggle() { if (playing) player.pause(); else player.play() }
    function seek(frac) {
        if (player.duration > 0)
            player.position = Math.max(0, Math.min(1, frac)) * player.duration
    }
    function stop() { player.stop() }

    MediaPlayer {
        id: player
        source: root.source
        loops: MediaPlayer.Infinite
        videoOutput: output
        audioOutput: AudioOutput { muted: root.muted }
        onSourceChanged: if (root.source.toString() !== "") play()
    }
    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }
}
