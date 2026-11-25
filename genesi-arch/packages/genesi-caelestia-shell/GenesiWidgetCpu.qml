// GENESI desktop widget: processor.
//
// The number you look at on purpose, the ring you catch out of the corner of
// an eye, and a line under both that says whether this is a spike or the way
// the machine has been all afternoon.
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
            h.push(Cpu.percentage);
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
                        icon: "memory"
                        tint: w.accent
                    }
                    GenesiWText {
                        anchors.verticalCenter: parent.verticalCenter
                        s: w.s
                        size: 11
                        tracking: 1.6
                        font.weight: Font.DemiBold
                        text: qsTr("PROCESSOR")
                        color: w.inkFaint
                    }
                }

                Row {
                    spacing: 2 * w.s

                    GenesiWGradText {
                        s: w.s
                        size: 46
                        fontWeight: Font.Light
                        text: Math.round(Cpu.percentage * 100)
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
                    text: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : Cpu.name
                    color: w.inkDim
                }
            }

            GenesiWRing {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 84
                thickness: 8
                value: Cpu.percentage
                from: w.accent
                to: w.accent2
                track: w.track

                GenesiWIcon {
                    anchors.centerIn: parent
                    s: w.s
                    size: 26
                    fill: 1
                    text: "developer_board"
                    color: w.accent
                }
            }
        }

        GenesiWSpark {
            width: parent.width
            height: 34 * w.s
            s: w.s
            values: w.hist
            colour: w.accent
        }
    }
}
