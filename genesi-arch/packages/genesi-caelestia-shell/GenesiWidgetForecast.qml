// GENESI desktop widget: the forecast
//
// Four days, because five is a table and three is not a forecast. Each day is
// its glyph and its high, which is the pair people plan around.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    Column {
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("FORECAST")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }

        Row {
            spacing: Tokens.spacing.large

            Repeater {
                model: Weather.forecast.slice(0, 4)

                Column {
                    id: day

                    required property var modelData

                    spacing: 2

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: day.modelData?.date ? Qt.formatDateTime(new Date(day.modelData.date), "ddd") : "--"
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: day.modelData?.icon ?? "cloud"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.formatTemp(day.modelData?.maxTempC)
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}
