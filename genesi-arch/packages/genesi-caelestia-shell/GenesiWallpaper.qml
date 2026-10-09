// GENESI — the wallpaper of ONE screen: caelestia's, or its own.
//
// Built by Background.qml in place of caelestia's `Wallpaper {}`, once per
// screen (patch_per_screen_wallpaper). It always holds caelestia's own
// Wallpaper underneath -- the default picture, or this screen's own picture
// when GenesiWallpaperState names one -- and lays a GIF or a video over it
// when that is what this screen shows. So a video that cannot play (no
// codec, a moved file) still leaves a wallpaper, never a black screen.
//
// A moving wallpaper is paused while a fullscreen window covers its screen:
// a game should not share the GPU with a loop nobody can see.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.launcher

Item {
    id: root

    readonly property string screenName: (QsWindow.window as QsWindow)?.screen?.name ?? ""
    readonly property var own: GenesiWallpaperState.forScreen(root.screenName)
    readonly property string kind: root.own?.kind ?? ""
    readonly property string path: root.own?.path ?? ""
    readonly property bool moving: root.kind === "video" || root.kind === "gif"

    // The launcher previews a wallpaper while its list is browsed. On the
    // screen it is open on; the others keep what they show.
    readonly property bool previewHere: Wallpapers.showPreview
        && (GenesiWallpaperState.previewScreen === "" || GenesiWallpaperState.previewScreen === root.screenName)

    readonly property var monitor: Hypr.monitorFor((QsWindow.window as QsWindow)?.screen)
    readonly property bool covered: root.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    // caelestia's own picture. Kept for a moving wallpaper too: it is what
    // shows while the video loads, and if it never does.
    Wallpaper {
        anchors.fill: parent
        source: root.previewHere ? Wallpapers.previewPath
            : root.kind === "image" && root.path !== "" ? root.path
            : Wallpapers.actualCurrent
    }

    AnimatedImage {
        anchors.fill: parent
        visible: root.kind === "gif" && status === Image.Ready && !root.previewHere
        source: root.kind === "gif" && root.path !== "" ? `file://${root.path}` : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        playing: !root.covered
    }

    // In a file of its own: it imports QtMultimedia, and a missing module
    // fails the file that imports it -- here, only the video.
    Loader {
        id: video

        anchors.fill: parent
        active: root.kind === "video" && root.path !== ""
        visible: !root.previewHere
        source: "GenesiWallpaperVideo.qml"
    }

    Binding {
        when: video.status === Loader.Ready
        target: video.item
        property: "path"
        value: root.path
    }

    Binding {
        when: video.status === Loader.Ready
        target: video.item
        property: "paused"
        value: root.covered
    }
}
