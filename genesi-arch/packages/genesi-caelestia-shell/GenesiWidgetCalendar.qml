// GENESI desktop widget: this month.
//
// The day is the headline -- the date is the thing a calendar on a desktop is
// looked at for -- and the month sits under it as a grid, with today lit in the
// widget's colours and the weekend a shade quieter.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    readonly property date today: Time.date
    readonly property date start: {
        const first = new Date(w.today.getFullYear(), w.today.getMonth(), 1);
        return new Date(first.getFullYear(), first.getMonth(), 1 - first.getDay());
    }
    readonly property real cell: 32 * w.s

    Column {
        spacing: 10 * w.s

        Row {
            spacing: 12 * w.s

            GenesiWGradText {
                s: w.s
                size: 48
                fontWeight: Font.Light
                text: String(w.today.getDate())
                from: w.accent
                to: w.accent2
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                GenesiWText {
                    s: w.s
                    size: 16
                    font.weight: Font.DemiBold
                    text: Qt.formatDateTime(w.today, "dddd")
                    color: w.ink
                }
                GenesiWText {
                    s: w.s
                    size: 13
                    text: Qt.formatDateTime(w.today, "MMMM yyyy")
                    color: w.inkDim
                }
            }
        }

        Grid {
            columns: 7
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: [0, 1, 2, 3, 4, 5, 6]

                GenesiWText {
                    id: head

                    required property int modelData

                    width: w.cell
                    height: 22 * w.s
                    horizontalAlignment: Text.AlignHCenter
                    s: w.s
                    size: 10
                    tracking: 1
                    font.weight: Font.DemiBold
                    text: Qt.locale().dayName(head.modelData, Locale.NarrowFormat)
                    color: w.inkFaint
                }
            }

            Repeater {
                model: 42

                Item {
                    id: day

                    required property int index
                    readonly property date date: new Date(w.start.getFullYear(), w.start.getMonth(), w.start.getDate() + day.index)
                    readonly property bool thisMonth: day.date.getMonth() === w.today.getMonth()
                    readonly property bool isToday: day.thisMonth && day.date.getDate() === w.today.getDate()
                    readonly property bool weekend: day.date.getDay() === 0 || day.date.getDay() === 6

                    width: w.cell
                    height: 28 * w.s

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26 * w.s
                        height: 26 * w.s
                        radius: width / 2
                        visible: day.isToday
                        gradient: Gradient {
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

                    GenesiWText {
                        anchors.centerIn: parent
                        s: w.s
                        size: 12
                        font.weight: day.isToday ? Font.Bold : Font.Normal
                        text: day.date.getDate()
                        color: {
                            if (day.isToday)
                                return Colours.palette.m3surface;
                            if (!day.thisMonth)
                                return Qt.alpha(w.inkFaint, 0.5);
                            return day.weekend ? w.inkDim : w.ink;
                        }
                    }
                }
            }
        }
    }
}
