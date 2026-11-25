// GENESI desktop widget: network.
//
// Down and up side by side, each with its own line. The lines are scaled to the
// busiest moment in the window, so a quiet connection still draws a shape and
// a download does not flatten everything else into the floor.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    property var down: []
    property var up: []

    function norm(vs: var): var {
        // A quarter of headroom, so the busiest moment is not a line pressed
        // against the top edge.
        const peak = Math.max(1024, ...vs) * 1.25;
        return vs.map(v => v / peak);
    }

    function speed(raw: real): string {
        const f = NetworkUsage.formatBytes(raw ?? 0);
        return f ? `${f.value.toFixed(f.value < 10 ? 1 : 0)} ${f.unit}` : "0 B/s";
    }

    Timer {
        running: true
        repeat: true
        interval: 1500
        triggeredOnStart: true
        onTriggered: {
            const d = w.down.slice(-39);
            d.push(NetworkUsage.downloadSpeed ?? 0);
            w.down = d;
            const u = w.up.slice(-39);
            u.push(NetworkUsage.uploadSpeed ?? 0);
            w.up = u;
        }
    }

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWChip {
                s: w.s
                icon: "network_check"
                tint: w.accent
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: qsTr("NETWORK")
                color: w.inkFaint
            }
        }

        Row {
            spacing: 22 * w.s

            Repeater {
                model: [
                    {
                        "down": true
                    },
                    {
                        "down": false
                    }
                ]

                Column {
                    id: col

                    required property var modelData
                    readonly property color tint: col.modelData.down ? w.accent : w.accent2

                    spacing: 4 * w.s

                    Row {
                        spacing: 4 * w.s

                        GenesiWIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            s: w.s
                            size: 18
                            fill: 1
                            text: col.modelData.down ? "south" : "north"
                            color: col.tint
                        }
                        GenesiWText {
                            anchors.verticalCenter: parent.verticalCenter
                            s: w.s
                            size: 11
                            tracking: 1.2
                            text: col.modelData.down ? qsTr("DOWN") : qsTr("UP")
                            color: w.inkFaint
                        }
                    }

                    GenesiWText {
                        s: w.s
                        size: 22
                        font.weight: Font.Light
                        text: w.speed(col.modelData.down ? NetworkUsage.downloadSpeed : NetworkUsage.uploadSpeed)
                        color: w.ink
                    }

                    GenesiWSpark {
                        width: 118 * w.s
                        height: 30 * w.s
                        s: w.s
                        values: w.norm(col.modelData.down ? w.down : w.up)
                        colour: col.tint
                    }
                }
            }
        }
    }
}
