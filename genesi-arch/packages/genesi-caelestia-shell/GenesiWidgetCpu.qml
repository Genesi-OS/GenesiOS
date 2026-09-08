// GENESI desktop widget: processor load
//
// Load and temperature. The ring is the reading you catch out of the corner
// of an eye; the number is the one you look at on purpose.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

GenesiWidgetCard {
    Row {
        spacing: Tokens.spacing.large

        CircularProgress {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 62
            strokeWidth: 6
            value: Cpu.percentage
            fgColour: Colours.palette.m3primary
            bgColour: Colours.palette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: "memory"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: qsTr("CPU")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
            StyledText {
                text: Math.round(Cpu.percentage * 100) + "%"
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: Cpu.temperature > 0 ? Math.round(Cpu.temperature) + "°C" : Cpu.name
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
