// GENESI desktop widget: network throughput
//
// Down and up, each on its own line with its own arrow. One combined number
// is the thing that looks informative and answers no question anybody has.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    Column {
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("NETWORK")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }

        Repeater {
            model: [
                {
                    icon: "arrow_downward",
                    speed: 0
                },
                {
                    icon: "arrow_upward",
                    speed: 1
                }
            ]

            Row {
                id: line

                required property var modelData

                spacing: Tokens.spacing.small

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.modelData.icon
                    color: line.modelData.speed === 0 ? Colours.palette.m3primary : Colours.palette.m3tertiary
                    fontStyle: Tokens.font.icon.medium
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const raw = line.modelData.speed === 0 ? NetworkUsage.downloadSpeed : NetworkUsage.uploadSpeed;
                        const fmt = NetworkUsage.formatBytes(raw ?? 0);
                        return fmt ? `${fmt.value.toFixed(1)} ${fmt.unit}` : "0.0 B/s";
                    }
                    font: Tokens.font.body.large
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }
}
