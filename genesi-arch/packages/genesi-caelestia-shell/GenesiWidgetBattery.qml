// GENESI desktop widget: battery
//
// Charge, and how long it has left. Draws nothing at all on a desktop: a
// battery widget reading 100% for ever is a widget that has never once been
// worth looking at.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Quickshell.Services.UPower
import qs.components
import qs.components.controls
import qs.services

GenesiWidgetCard {
    id: root

    readonly property var dev: UPower.displayDevice

    visible: root.dev?.isLaptopBattery ?? false
    height: visible ? implicitHeight : 0

    Row {
        spacing: Tokens.spacing.large

        CircularProgress {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 62
            strokeWidth: 6
            value: root.dev?.percentage ?? 0
            fgColour: (root.dev?.percentage ?? 1) < 0.2 ? Colours.palette.m3error : Colours.palette.m3primary
            bgColour: Colours.palette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                text: root.dev?.state === UPowerDeviceState.Charging ? "bolt" : "battery_full"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: qsTr("BATTERY")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
            StyledText {
                text: Math.round((root.dev?.percentage ?? 0) * 100) + "%"
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: {
                    const d = root.dev;
                    if (!d)
                        return "";
                    const secs = d.state === UPowerDeviceState.Charging ? d.timeToFull : d.timeToEmpty;
                    if (!secs || secs <= 0)
                        return d.state === UPowerDeviceState.Charging ? qsTr("charging") : "";
                    const h = Math.floor(secs / 3600);
                    const m = Math.floor((secs % 3600) / 60);
                    return h > 0 ? qsTr("%1h %2m left").arg(h).arg(m) : qsTr("%1m left").arg(m);
                }
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
