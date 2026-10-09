// GENESI — which wallpaper each screen shows, when it is not caelestia's.
//
// caelestia has ONE wallpaper (Wallpapers.current) for every screen. Genesi
// adds a map on top: a screen named in it shows its own picture, GIF or video;
// a screen that is not named shows caelestia's as before. The map is written
// by `genesi-wallpaper` (the Center's wallpaper section calls it) and only
// read here:
//
//     ${Paths.state}/genesi-wallpapers.json
//     { "screens": { "DP-1": {"path": "/…/a.mp4", "kind": "video"},
//                    "*":    {"path": "/…/b.gif", "kind": "gif"} } }
//
// "*" is every screen without an entry of its own -- how a video becomes the
// wallpaper everywhere without caelestia's own image path (which feeds the
// colour scheme) having to be a video.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property var screens: ({})

    // This screen's own wallpaper, or null for caelestia's.
    function forScreen(name: string): var {
        return root.screens[name] ?? root.screens["*"] ?? null;
    }

    FileView {
        id: file

        path: `${Paths.state}/genesi-wallpapers.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.screens = (d && typeof d.screens === "object" && d.screens) ? d.screens : {};
            } catch (e) {
                root.screens = {};
            }
        }
        onLoadFailed: root.screens = {}
    }

    Timer {
        // A watch cannot see a file that does not exist yet, and the first
        // `genesi-wallpaper set` creates it.
        interval: 3000
        repeat: true
        running: true
        onTriggered: file.reload()
    }
}
