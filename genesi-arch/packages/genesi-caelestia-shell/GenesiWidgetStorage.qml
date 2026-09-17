// GENESI desktop widget: storage.
//
// A disk fills over weeks, not seconds, so there is no line here -- just how
// full it is and how much is left, which is the only question anybody asks it.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Services

GenesiWidgetCard {
    id: w

    readonly property var disk: Storage.primaryDisk
    readonly property real perc: w.disk?.perc ?? 0

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWChip {
                s: w.s
                icon: "hard_drive"
                tint: w.accent
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: qsTr("STORAGE")
                color: w.inkFaint
            }
        }

        Row {
            spacing: 10 * w.s

            Row {
                spacing: 2 * w.s

                GenesiWGradText {
                    s: w.s
                    size: 46
                    fontWeight: Font.Light
                    text: Math.round(w.perc * 100)
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

            Column {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8 * w.s
                GenesiWText {
                    s: w.s
                    size: 13
                    text: w.disk ? qsTr("%1 GiB free").arg(((w.disk.total - w.disk.used) / 1048576).toFixed(0)) : qsTr("no disk")
                    color: w.ink
                }
                GenesiWText {
                    s: w.s
                    size: 11
                    text: w.disk ? qsTr("of %1 GiB").arg((w.disk.total / 1048576).toFixed(0)) : ""
                    color: w.inkFaint
                }
            }
        }

        // The bar, with the gradient running along it.
        Rectangle {
            width: 230 * w.s
            height: 10 * w.s
            radius: height / 2
            color: w.track

            Rectangle {
                width: Math.max(parent.height, parent.width * w.perc)
                height: parent.height
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: w.accent
                    }
                    GradientStop {
                        position: 1
                        color: w.accent2
                    }
                }
            }
        }
    }
}
