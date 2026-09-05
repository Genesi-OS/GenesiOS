//
// shell.qml — the Genesi bar's Quickshell half.
//
// Everything that touches the system lives here; BarContent draws and knows
// nothing. That is why the whole visual layer can be rendered and reviewed
// without Quickshell (devtools/render-topbar.py), and it is the only reason
// this bar was not the first thing in the project shipped unseen.
//
// ── Why a CLI for the readings ───────────────────────────────────────────────
//
// Workspaces and the active window come from Quickshell's Hyprland module and
// the tray from its SystemTray module, because those are the two things it
// exists to provide and there is no sane way to get them otherwise.
//
// Volume, network and battery come from `genesi-topbar-data` instead. Not
// because Quickshell cannot do it, but because that is the shape the rest of
// Genesi already has -- genesi-display, genesi-bar, genesi-center-data all
// print JSON for a front end to draw -- and a reading that a terminal and the
// bar disagree about is a bug nobody can debug. It also means those readings
// are testable without a compositor.
//
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    property var readings: ({})

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            // Top edge, full width. `exclusiveZone` is the height so windows
            // tile below the bar rather than under it -- without it a maximised
            // window sits behind the bar and the clock is unreadable.
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 34
            exclusiveZone: 34
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "genesi-bar"

            Rectangle {
                anchors.fill: parent
                color: BarTokens.bg
                // One hairline at the bottom edge: the bar has to separate
                // itself from whatever wallpaper is behind it, and a border on
                // all four sides of a full-width strip is three borders too
                // many.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: BarTokens.line
                }
            }

            BarContent {
                anchors.fill: parent
                barHeight: 34

                workspaces: {
                    const out = [];
                    const active = Hyprland.focusedWorkspace
                                   ? Hyprland.focusedWorkspace.id : -1;
                    const live = {};
                    for (const w of Hyprland.workspaces.values)
                        live[w.id] = w;
                    // A fixed row of five, not "however many exist right now":
                    // a bar whose workspace block changes width as workspaces
                    // come and go drags everything beside it around.
                    for (let i = 1; i <= 5; i++) {
                        const w = live[i];
                        out.push({
                            id: i,
                            occupied: w !== undefined,
                            active: i === active,
                            windows: w ? (w.lastIpcObject
                                          ? w.lastIpcObject.windows : 0) : 0
                        });
                    }
                    return out;
                }

                activeWindow: Hyprland.activeToplevel
                              ? (Hyprland.activeToplevel.title || "") : ""

                clockText: clock.time
                dateText: clock.date

                trayItems: {
                    const out = [];
                    for (const item of SystemTray.items.values)
                        out.push({
                            id: item.id,
                            icon: item.icon,
                            tooltip: item.tooltip || item.title || item.id
                        });
                    return out;
                }

                status: root.readings

                onActivated: (what, arg) => {
                    if (what === "workspace")
                        Hyprland.dispatch("workspace " + arg);
                    else if (what === "session")
                        Quickshell.execDetached(["caelestia", "shell", "drawers",
                                                 "toggle", "session"]);
                    else if (what === "logo")
                        Quickshell.execDetached(["genesi-center"]);
                    else if (what === "status")
                        Quickshell.execDetached(["genesi-center"]);
                }
            }
        }
    }

    // ── The clock ────────────────────────────────────────────────────────────
    //
    // Its own timer rather than a per-second one shared with the readings: the
    // clock has to be correct on the minute and the readings do not, and a
    // single fast timer would wake a subprocess sixty times more often than
    // anything needs.
    QtObject {
        id: clock
        property string time: Qt.formatDateTime(new Date(), "HH:mm")
        property string date: Qt.formatDateTime(new Date(), "ddd, MMM d")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            clock.time = Qt.formatDateTime(new Date(), "HH:mm");
            clock.date = Qt.formatDateTime(new Date(), "ddd, MMM d");
        }
    }

    // ── The readings ─────────────────────────────────────────────────────────
    Process {
        id: readProc
        command: ["genesi-topbar-data"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.readings = JSON.parse(text);
                } catch (e) {
                    // Keep the last good values. A bar that empties itself
                    // because one read failed flickers on every hiccup.
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: readProc.running = true
    }
}
