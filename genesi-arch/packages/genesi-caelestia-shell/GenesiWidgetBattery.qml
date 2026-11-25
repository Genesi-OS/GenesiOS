// GENESI desktop widget: battery.
//
// Drawn as a battery -- a cell with a terminal, filled with the charge -- and
// the only widget whose colour overrides yours: low charge turns it red,
// because a warning that follows the wallpaper's palette is a warning that
// can be green.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import qs.services

GenesiWidgetCard {
    id: w

    readonly property var dev: UPower.displayDevice
    readonly property real perc: w.dev?.percentage ?? 0
    readonly property bool charging: w.dev?.state === UPowerDeviceState.Charging
    readonly property bool low: w.perc < 0.2 && !w.charging
    readonly property color fillFrom: w.low ? Colours.palette.m3error : w.accent
    readonly property color fillTo: w.low ? Colours.palette.m3error : w.accent2

    visible: w.dev?.isLaptopBattery ?? false
    height: visible ? implicitHeight : 0

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWChip {
                s: w.s
                icon: w.charging ? "bolt" : "battery_full"
                tint: w.fillFrom
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: w.charging ? qsTr("CHARGING") : qsTr("BATTERY")
                color: w.inkFaint
            }
        }

        Row {
            spacing: 16 * w.s

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * w.s

                GenesiWGradText {
                    s: w.s
                    size: 46
                    fontWeight: Font.Light
                    text: Math.round(w.perc * 100)
                    from: w.fillFrom
                    to: w.fillTo
                }
                GenesiWText {
                    y: 10 * w.s
                    s: w.s
                    size: 18
                    text: "%"
                    color: w.inkDim
                }
            }

            // The cell.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * w.s

                Rectangle {
                    width: 96 * w.s
                    height: 42 * w.s
                    radius: 11 * w.s
                    color: "transparent"
                    border.width: 2 * w.s
                    border.color: Qt.alpha(w.ink, 0.35)

                    Rectangle {
                        x: 5 * w.s
                        y: 5 * w.s
                        width: Math.max(height * 0.5, (parent.width - 10 * w.s) * w.perc)
                        height: parent.height - 10 * w.s
                        radius: 6 * w.s
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: w.fillFrom
                            }
                            GradientStop {
                                position: 1
                                color: w.fillTo
                            }
                        }
                    }

                    GenesiWIcon {
                        anchors.centerIn: parent
                        visible: w.charging
                        s: w.s
                        size: 22
                        fill: 1
                        text: "bolt"
                        color: w.ink
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5 * w.s
                    height: 16 * w.s
                    radius: 2.5 * w.s
                    color: Qt.alpha(w.ink, 0.35)
                }
            }
        }

        GenesiWText {
            s: w.s
            size: 12
            color: w.inkDim
            text: {
                const d = w.dev;
                if (!d)
                    return "";
                const secs = w.charging ? d.timeToFull : d.timeToEmpty;
                if (!secs || secs <= 0)
                    return w.charging ? qsTr("charging") : "";
                const h = Math.floor(secs / 3600);
                const m = Math.floor((secs % 3600) / 60);
                const t = h > 0 ? qsTr("%1h %2m").arg(h).arg(m) : qsTr("%1m").arg(m);
                return w.charging ? qsTr("%1 until full").arg(t) : qsTr("%1 left").arg(t);
            }
        }
    }
}
