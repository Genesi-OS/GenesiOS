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
import qs.services
import qs.utils

Singleton {
    id: root

    property var screens: ({})

    // The screen the launcher's wallpaper list is open on while it previews,
    // so the preview shows THERE and not on every screen.
    property string previewScreen: ""

    // The launcher's >wallpaper. `screen` is the screen the launcher is open
    // on -- its own window's, read when the pick happens, so moving the
    // pointer to another screen afterwards changes nothing. One screen:
    // caelestia's own pick, colours and all. Several: genesi-wallpaper pick,
    // which changes only that screen (see its docstring).
    function pick(path: string, screen: string): void {
        if (Quickshell.screens.length <= 1 || screen === "")
            Wallpapers.setWallpaper(path);
        else
            Quickshell.execDetached(["genesi-wallpaper", "pick", path, "--monitor", screen]);
    }

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
