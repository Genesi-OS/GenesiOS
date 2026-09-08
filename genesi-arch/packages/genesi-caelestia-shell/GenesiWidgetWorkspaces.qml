// GENESI desktop widget: the workspaces
//
// One pill per workspace: filled when it holds windows, wide and bright when
// it is the one you are on. Reads at a glance from across the desk, which is
// the only thing a desktop widget is for.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    Row {
        spacing: Tokens.spacing.small

        Repeater {
            model: Hypr.workspaces?.values ?? []

            StyledRect {
                id: ws

                required property var modelData

                readonly property bool active: ws.modelData?.id === Hypr.activeWsId
                readonly property bool occupied: (ws.modelData?.toplevels?.values?.length ?? 0) > 0

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: ws.active ? 30 : 12
                implicitHeight: 12
                radius: Tokens.rounding.full
                color: {
                    if (ws.active)
                        return Colours.palette.m3primary;
                    return ws.occupied ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3surfaceContainerHighest;
                }

                Behavior on implicitWidth {
                    Anim {}
                }
                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
