// GENESI desktop widget: uptime
//
// Straight from /proc/uptime, reread once a minute. A shell-out to `uptime -p`
// would be a process every minute for ever to read a number that is already
// a file.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Quickshell.Io
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    property real seconds: 0

    FileView {
        id: file

        path: "/proc/uptime"
        blockLoading: false

        onLoaded: {
            const first = parseFloat(text().trim().split(" ")[0]);
            if (!isNaN(first))
                root.seconds = first;
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 60000
        triggeredOnStart: true
        onTriggered: file.reload()
    }

    Row {
        spacing: Tokens.spacing.large

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "schedule"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.2).build()
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: qsTr("UP FOR")
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }
            StyledText {
                text: {
                    const s = root.seconds;
                    const d = Math.floor(s / 86400);
                    const h = Math.floor((s % 86400) / 3600);
                    const m = Math.floor((s % 3600) / 60);
                    if (d > 0)
                        return qsTr("%1d %2h").arg(d).arg(h);
                    if (h > 0)
                        return qsTr("%1h %2m").arg(h).arg(m);
                    return qsTr("%1m").arg(m);
                }
                font: Tokens.font.headline.medium
                color: Colours.palette.m3onSurface
            }
        }
    }
}
