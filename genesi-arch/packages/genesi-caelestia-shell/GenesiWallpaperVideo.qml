// GENESI — a video wallpaper: looped, silent, cropped to fill the screen.
//
// Loaded by GenesiWallpaper only when a screen's wallpaper is a video, so
// QtMultimedia (qt6-multimedia, with its ffmpeg backend for decoding) is
// asked for only then. Hardware decoding is whatever the ffmpeg backend
// finds (VA-API on most GPUs).
import QtQuick
import QtMultimedia

Item {
    id: root

    property string path: ""
    property bool paused: false
    readonly property bool ready: player.playbackState === MediaPlayer.PlayingState
                                  || player.playbackState === MediaPlayer.PausedState

    // Hidden until the first frame, so the picture underneath shows instead
    // of a black rectangle while the file opens.
    visible: root.ready

    MediaPlayer {
        id: player

        source: root.path !== "" ? `file://${root.path}` : ""
        loops: MediaPlayer.Infinite
        videoOutput: output
        // No audioOutput: a wallpaper never makes a sound.
        onSourceChanged: if (!root.paused && source.toString() !== "") play()
    }

    VideoOutput {
        id: output

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    onPausedChanged: root.paused ? player.pause() : player.play()
    Component.onCompleted: if (!root.paused && root.path !== "") player.play()
}
