// GENESI desktop widget: a big digital clock.
//
// The widget people put on a desktop more than any other, set as a display
// face: the hours and minutes huge and light in the widget's colours, the
// seconds small beside them, and the date underneath. It takes every option
// the editor has -- style, size, opacity, gradient -- which caelestia's own
// clock does not.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.services

GenesiWidgetCard {
    id: w

    readonly property bool twelve: GlobalConfig.services.useTwelveHourClock

    Column {
        spacing: -6 * w.s

        Row {
            spacing: 8 * w.s

            GenesiWGradText {
                s: w.s
                size: 96
                fontWeight: Font.Light
                tracking: -2
                from: w.accent
                to: w.accent2
                text: Qt.formatDateTime(Time.date, w.twelve ? "h:mm" : "HH:mm")
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 22 * w.s
                spacing: 2 * w.s

                GenesiWText {
                    visible: w.twelve
                    s: w.s
                    size: 16
                    font.weight: Font.DemiBold
                    text: Qt.formatDateTime(Time.date, "AP")
                    color: w.inkDim
                }
                GenesiWText {
                    s: w.s
                    size: 22
                    font.weight: Font.Light
                    text: Qt.formatDateTime(Time.date, "ss")
                    color: w.inkFaint
                }
            }
        }

        GenesiWText {
            leftPadding: 4 * w.s
            s: w.s
            size: 18
            font.weight: Font.Medium
            tracking: 0.5
            text: Qt.formatDateTime(Time.date, "dddd, d MMMM")
            color: w.ink
        }
    }
}
