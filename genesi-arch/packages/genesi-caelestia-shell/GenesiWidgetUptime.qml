// GENESI desktop widget: how long the machine has been up.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

GenesiWidgetCard {
    id: w

    property real seconds: 0

    FileView {
        id: file

        path: "/proc/uptime"
        blockLoading: false
        onLoaded: {
            const first = parseFloat(text().trim().split(" ")[0]);
            if (!isNaN(first))
                w.seconds = first;
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
        spacing: 14 * w.s

        GenesiWChip {
            anchors.verticalCenter: parent.verticalCenter
            s: w.s
            size: 48
            icon: "timer"
            tint: w.accent
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            GenesiWText {
                s: w.s
                size: 11
                tracking: 1.6
                font.weight: Font.DemiBold
                text: qsTr("UP FOR")
                color: w.inkFaint
            }
            GenesiWGradText {
                s: w.s
                size: 34
                fontWeight: Font.Light
                from: w.accent
                to: w.accent2
                text: {
                    const t = w.seconds;
                    const d = Math.floor(t / 86400);
                    const h = Math.floor((t % 86400) / 3600);
                    const m = Math.floor((t % 3600) / 60);
                    if (d > 0)
                        return qsTr("%1d %2h").arg(d).arg(h);
                    if (h > 0)
                        return qsTr("%1h %2m").arg(h).arg(m);
                    return qsTr("%1m").arg(m);
                }
            }
        }
    }
}
