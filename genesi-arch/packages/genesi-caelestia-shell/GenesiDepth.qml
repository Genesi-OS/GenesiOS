// GENESI — the wallpaper's subject, in front of the clock.
//
// The desktop is drawn in this order: wallpaper, visualiser, widgets, clock.
// Depth adds a fifth layer on top holding the SUBJECT of the wallpaper and
// nothing else, cut out with an alpha channel. The subject is therefore drawn
// twice -- once as part of the wallpaper underneath, once here -- and the
// clock and the widgets are in between.
//
// That is the entire trick, and it is worth being plain about it because the
// effect is usually sold as "3D": there is no depth map, no parallax, and
// nothing moves. There is one cut-out and a stacking order.
//
// ── The cutting is not done here ────────────────────────────────────────────
//
// `genesi-depth` does it: saliency, GrabCut, a feathered alpha, cached by the
// wallpaper's path, size, mtime and the settings used. This asks for a path
// and draws what comes back. Segmentation in QML would be segmentation on the
// render thread.
//
// A cutout takes between half a second and a few seconds the first time a
// wallpaper is seen and is instant afterwards, which is why the layer fades
// in rather than appearing: on a wallpaper change the new one arrives late,
// and a subject that pops into place a second after the picture behind it
// reads as a glitch.
//
// ── When nothing has a subject ─────────────────────────────────────────────
//
// genesi-depth exits non-zero when nothing in the picture stands out enough
// to cut out -- a texture, a gradient, an abstract. The layer stays empty and
// the desktop is exactly as it was. A cut-out of a speck drawn over the clock
// would be the worse answer, and it is the answer a tool that always returns
// something has to give.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    readonly property var cfg: Config.background.depth

    // What to cut. Read once into a property so the Process command and the
    // change handler cannot disagree about which wallpaper is current.
    readonly property string wallpaper: Wallpapers.current

    // The last cutout that arrived. Cleared on a wallpaper change rather than
    // left behind: the old subject over the new picture is the one failure
    // that looks deliberate.
    property string cutout: ""

    readonly property real strength: {
        switch (root.cfg.strength) {
        case "subtle":
            return 0.55;
        case "medium":
            return 0.8;
        }
        return 1;
    }

    readonly property int shadowSize: {
        switch (root.cfg.shadow) {
        case "soft":
            return 18;
        case "strong":
            return 34;
        }
        return 0;
    }

    readonly property int feather: {
        switch (root.cfg.edgeFade) {
        case "none":
            return 0;
        case "strong":
            return 6;
        }
        return 2;
    }

    function refresh(): void {
        root.cutout = "";
        if (!root.cfg.enabled || root.wallpaper === "")
            return;
        // A path, not a shell line: the wallpaper's name is somebody's file
        // name and it will one day contain a space, a quote or a dollar sign.
        cutter.command = ["genesi-depth", "cutout", root.wallpaper,
                          "--quality", root.cfg.quality,
                          "--feather", String(root.feather)];
        cutter.running = true;
    }

    anchors.fill: parent
    visible: root.cfg.enabled && root.cutout !== ""

    onWallpaperChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Connections {
        function onEnabledChanged(): void {
            root.refresh();
        }

        function onQualityChanged(): void {
            root.refresh();
        }

        function onEdgeFadeChanged(): void {
            root.refresh();
        }

        target: root.cfg
    }

    Process {
        id: cutter

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                // Only when it is really there. A non-zero exit still closes
                // the stream, and an empty or stale path assigned to an Image
                // source is a broken-image icon on the desktop.
                if (path !== "")
                    root.cutout = path;
            }
        }
    }

    Image {
        id: subject

        anchors.fill: parent
        // The same fill the wallpaper itself uses (CachingImage sets
        // PreserveAspectCrop). Anything else and the cut-out lands a few
        // pixels off the thing it was cut from, which is more obviously wrong
        // than no cutout at all.
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: root.cutout === "" ? "" : `file://${root.cutout}`

        opacity: status === Image.Ready ? root.strength : 0

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }

        layer.enabled: root.shadowSize > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.55)
            blurMax: root.shadowSize
            shadowBlur: 1
            shadowVerticalOffset: root.shadowSize / 3
        }
    }
}
