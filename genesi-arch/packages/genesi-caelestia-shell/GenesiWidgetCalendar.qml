// GENESI desktop widget: the month
//
// A real month grid, built from the first of the month rather than from a
// fixed six-by-seven of guesses. Today is the only marked cell, because a
// calendar with nothing marked is a table.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    readonly property date today: Time.date
    // The Sunday on or before the first of the month: where the grid starts.
    readonly property date start: {
        const first = new Date(root.today.getFullYear(), root.today.getMonth(), 1);
        return new Date(first.getFullYear(), first.getMonth(), 1 - first.getDay());
    }

    Column {
        spacing: Tokens.spacing.small

        StyledText {
            text: Qt.formatDateTime(root.today, "MMMM yyyy")
            font: Tokens.font.body.large
            color: Colours.palette.m3onSurface
        }

        Grid {
            columns: 7
            columnSpacing: 4
            rowSpacing: 3

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

                StyledText {
                    id: head

                    required property string modelData

                    width: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: head.modelData
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
            }

            Repeater {
                model: 42

                Item {
                    id: cell

                    required property int index

                    readonly property date day: new Date(root.start.getFullYear(), root.start.getMonth(), root.start.getDate() + cell.index)
                    readonly property bool thisMonth: cell.day.getMonth() === root.today.getMonth()
                    readonly property bool isToday: cell.thisMonth && cell.day.getDate() === root.today.getDate()

                    implicitWidth: 24
                    implicitHeight: 20

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: 22
                        implicitHeight: 18
                        radius: Tokens.rounding.small
                        color: cell.isToday ? Colours.palette.m3primary : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: cell.day.getDate()
                        font: Tokens.font.label.medium
                        color: {
                            if (cell.isToday)
                                return Colours.palette.m3onPrimary;
                            return cell.thisMonth ? Colours.palette.m3onSurface : Colours.palette.m3outline;
                        }
                    }
                }
            }
        }
    }
}
