// GENESI desktop widget: the weather
//
// Conditions now: the glyph, the temperature at a size you can read across a
// room, and what it actually feels like -- which is the number people
// wanted when they looked.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    Row {
        spacing: Tokens.spacing.large

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.icon
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.6).build()
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: Weather.temp
                font: Tokens.font.headline.large
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: Weather.description
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: qsTr("Feels like %1").arg(Weather.feelsLike)
                font: Tokens.font.label.medium
                color: Colours.palette.m3outline
            }
        }
    }
}
