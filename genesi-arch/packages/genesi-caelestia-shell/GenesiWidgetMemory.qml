// GENESI desktop widget: memory.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Services

GenesiWidgetCard {
    id: w

    property var hist: []

    Timer {
        running: true
        repeat: true
        interval: 1500
        triggeredOnStart: true
        onTriggered: {
            const h = w.hist.slice(-39);
            h.push(Memory.percentage);
            w.hist = h;
        }
    }

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 18 * w.s

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4 * w.s

                Row {
                    spacing: 8 * w.s

                    GenesiWChip {
                        s: w.s
                        icon: "memory_alt"
                        tint: w.accent
                    }
                    GenesiWText {
                        anchors.verticalCenter: parent.verticalCenter
                        s: w.s
                        size: 11
                        tracking: 1.6
                        font.weight: Font.DemiBold
                        text: qsTr("MEMORY")
                        color: w.inkFaint
                    }
                }

                Row {
                    spacing: 2 * w.s

                    GenesiWGradText {
                        s: w.s
                        size: 46
                        fontWeight: Font.Light
                        text: Math.round(Memory.percentage * 100)
                        from: w.accent
                        to: w.accent2
                    }
                    GenesiWText {
                        y: 10 * w.s
                        s: w.s
                        size: 18
                        text: "%"
                        color: w.inkDim
                    }
                }

                GenesiWText {
                    s: w.s
                    size: 12
                    text: qsTr("%1 of %2 GiB").arg((Memory.used / 1048576).toFixed(1)).arg((Memory.total / 1048576).toFixed(0))
                    color: w.inkDim
                }
            }

            GenesiWRing {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 84
                thickness: 8
                value: Memory.percentage
                from: w.accent
                to: w.accent2
                track: w.track

                GenesiWIcon {
                    anchors.centerIn: parent
                    s: w.s
                    size: 26
                    fill: 1
                    text: "memory_alt"
                    color: w.accent
                }
            }
        }

        GenesiWSpark {
            width: parent.width
            height: 34 * w.s
            s: w.s
            values: w.hist
            colour: w.accent2
        }
    }
}
