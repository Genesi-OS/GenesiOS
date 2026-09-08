// GENESI desktop widget: disk in use
//
// The primary disk, the one caelestia already decides for the dashboard --
// so the two never disagree about which disk the desktop means.
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
            value: Storage.primaryDisk?.perc ?? 0
            fgColour: Colours.palette.m3tertiary
            bgColour: Colours.palette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: "hard_drive"
                color: Colours.palette.m3tertiary
                fontStyle: Tokens.font.icon.medium
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: qsTr("STORAGE")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
            StyledText {
                text: Math.round((Storage.primaryDisk?.perc ?? 0) * 100) + "%"
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: {
                    const d = Storage.primaryDisk;
                    if (!d)
                        return qsTr("no disk");
                    return ((d.total - d.used) / 1048576).toFixed(0) + qsTr(" GiB free");
                }
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
