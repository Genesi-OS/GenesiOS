// GENESI desktop widget: the latest notifications.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    readonly property var recent: (Notifs.notClosed || []).slice(0, 3)

    visible: w.recent.length > 0
    height: visible ? implicitHeight : 0

    Column {
        spacing: 12 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWChip {
                s: w.s
                icon: "notifications"
                tint: w.accent
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: qsTr("NOTIFICATIONS")
                color: w.inkFaint
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, count.implicitWidth + 10 * w.s)
                height: 18 * w.s
                radius: height / 2
                color: w.accent

                GenesiWText {
                    id: count

                    anchors.centerIn: parent
                    s: w.s
                    size: 10
                    font.weight: Font.Bold
                    text: (Notifs.notClosed || []).length
                    color: Colours.palette.m3surface
                }
            }
        }

        Repeater {
            model: w.recent

            Row {
                id: item

                required property var modelData
                required property int index

                spacing: 10 * w.s

                // A bar in the accent colour, fading down the list: the newest
                // is the brightest.
                Rectangle {
                    width: 3 * w.s
                    height: text.implicitHeight
                    radius: width / 2
                    color: Qt.alpha(item.index === 0 ? w.accent : w.accent2, 1 - item.index * 0.3)
                }

                Column {
                    id: text

                    spacing: 1 * w.s

                    Row {
                        spacing: 8 * w.s

                        GenesiWText {
                            width: 230 * w.s
                            s: w.s
                            size: 14
                            font.weight: Font.Medium
                            text: item.modelData?.summary ?? ""
                            color: w.ink
                            elide: Text.ElideRight
                        }
                        GenesiWText {
                            anchors.verticalCenter: parent.verticalCenter
                            s: w.s
                            size: 11
                            text: item.modelData?.timeStr ?? ""
                            color: w.inkFaint
                        }
                    }
                    GenesiWText {
                        width: 270 * w.s
                        s: w.s
                        size: 12
                        text: item.modelData?.body ?? ""
                        color: w.inkDim
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
            }
        }
    }
}
