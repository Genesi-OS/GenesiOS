// GENESI desktop widget: memory in use
//
// Used against total. Reported in KiB by the service, which is why the
// division by 1048576 is here rather than a formatter nobody can find.
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
            value: Memory.percentage
            fgColour: Colours.palette.m3secondary
            bgColour: Colours.palette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: "developer_board"
                color: Colours.palette.m3secondary
                fontStyle: Tokens.font.icon.medium
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: qsTr("MEMORY")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
            StyledText {
                text: Math.round(Memory.percentage * 100) + "%"
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: (Memory.used / 1048576).toFixed(1) + " / " + (Memory.total / 1048576).toFixed(0) + " GiB"
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
