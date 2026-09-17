// GENESI desktop widget: the next four days.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWChip {
                s: w.s
                icon: "partly_cloudy_day"
                tint: w.accent
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: qsTr("FORECAST")
                color: w.inkFaint
            }
        }

        Row {
            spacing: 8 * w.s

            Repeater {
                model: (Weather.forecast || []).slice(0, 4)

                Rectangle {
                    id: day

                    required property var modelData
                    required property int index

                    width: 70 * w.s
                    height: col.implicitHeight + 20 * w.s
                    radius: 16 * w.s
                    color: day.index === 0 ? Qt.alpha(w.accent, 0.14) : Qt.alpha(w.ink, 0.04)
                    border.width: day.index === 0 ? 1 : 0
                    border.color: Qt.alpha(w.accent, 0.35)

                    Column {
                        id: col

                        anchors.centerIn: parent
                        spacing: 4 * w.s

                        GenesiWText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            s: w.s
                            size: 12
                            font.weight: Font.Medium
                            text: day.modelData?.date ? Qt.formatDateTime(new Date(day.modelData.date), "ddd") : "--"
                            color: day.index === 0 ? w.ink : w.inkDim
                        }
                        GenesiWIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            s: w.s
                            size: 30
                            fill: 1
                            text: day.modelData?.icon ?? "cloud"
                            color: day.index === 0 ? w.accent : w.accent2
                        }
                        GenesiWText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            s: w.s
                            size: 16
                            text: Weather.formatTemp(day.modelData?.maxTempC)
                            color: w.ink
                        }
                    }
                }
            }
        }
    }
}
