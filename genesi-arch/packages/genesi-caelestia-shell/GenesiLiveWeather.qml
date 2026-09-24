// GENESI — live weather: when it rains outside, it rains on the wallpaper.
//
// A plugin (GenesiPluginSwitch, "live-weather"): off until the Plugins shelf
// of Genesi Store turns it on, and gone entirely -- windows, timers, every
// drop -- when it is turned off again.
//
// The weather is caelestia's own Weather service: the same open-meteo
// reading the dashboard shows, for the same place, so the desktop and the
// dashboard never disagree about whether it is raining. This asks it to
// refresh every half hour; nothing else here touches the network.
//
// ── Under the windows, over the picture ───────────────────────────────────
//
// The BOTTOM layer: above the wallpaper, below every window. It is weather
// on the desktop, not weather on your editor. The window takes no input at
// all -- an empty mask -- so a click on the desktop still reaches the
// desktop menu and the widgets underneath. And it stops drawing whenever a
// fullscreen window covers the screen.
//
// ── Seeing it on a dry day ────────────────────────────────────────────────
//
//     caelestia shell liveWeather preview rain      (drizzle, storm, snow, fog)
//
// shows that sky for thirty seconds. A plugin whose whole effect depends on
// the weather needs a way to be seen on the day it is switched on.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    id: root

    property string preview: ""

    GenesiPluginSwitch {
        id: gate

        plugin: "live-weather"
    }

    IpcHandler {
        target: "liveWeather"

        function preview(kind: string): void {
            if (!gate.active)
                return;
            root.preview = kind;
            previewTimer.restart();
        }
    }

    Timer {
        id: previewTimer

        interval: 30000
        onTriggered: root.preview = ""
    }

    LazyLoader {
        active: gate.active

        Scope {
            Timer {
                interval: 30 * 60 * 1000
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: Weather.reload()
            }

            Variants {
                model: Screens.screens

                StyledWindow {
                    id: win

                    required property ShellScreen modelData

                    readonly property var monitor: Hypr.monitorFor(win.modelData)
                    readonly property bool fullscreen: win.monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

                    screen: win.modelData
                    name: "genesi-weather"

                    WlrLayershell.exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Bottom
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    color: "transparent"

                    anchors.top: true
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true

                    mask: Region {}

                    GenesiWeatherFx {
                        anchors.fill: parent
                        code: Weather.cc?.weatherCode ?? 0
                        forced: root.preview
                        running: !win.fullscreen
                        // A calm day leans a little; 40 km/h leans as far as
                        // it goes.
                        wind: Math.min(1, 0.15 + (Weather.windSpeed ?? 0) / 40)
                    }
                }
            }
        }
    }
}
