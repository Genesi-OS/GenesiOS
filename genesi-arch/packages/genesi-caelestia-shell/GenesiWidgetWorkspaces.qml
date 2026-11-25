// GENESI desktop widget: the workspaces, as a row of pills.
//
// The active one is wide and lit with the widget's colours, the occupied ones
// are solid, the empty ones are rings -- readable at a glance from across the
// room, which is the only distance a desktop widget is read from.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    basePadding: 14

    Row {
        spacing: 8 * w.s

        Repeater {
            model: Hypr.workspaces?.values ?? []

            Rectangle {
                id: ws

                required property var modelData
                readonly property bool active: ws.modelData?.id === Hypr.activeWsId
                readonly property bool occupied: (ws.modelData?.toplevels?.values?.length ?? 0) > 0

                anchors.verticalCenter: parent.verticalCenter
                width: (ws.active ? 44 : 16) * w.s
                height: 16 * w.s
                radius: height / 2
                color: ws.occupied && !ws.active ? Qt.alpha(w.ink, 0.55) : "transparent"
                border.width: ws.active || ws.occupied ? 0 : 2 * w.s
                border.color: Qt.alpha(w.inkFaint, 0.7)
                gradient: ws.active ? active : null

                Gradient {
                    id: active

                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: w.accent
                    }
                    GradientStop {
                        position: 1
                        color: w.accent2
                    }
                }

                Behavior on width {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
