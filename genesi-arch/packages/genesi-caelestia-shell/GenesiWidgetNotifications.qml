// GENESI desktop widget: recent notifications
//
// The last three that have not been dismissed. Three because a wallpaper is
// not an inbox: past three this stops being a glance and starts being a
// window you have to close.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    readonly property var recent: Notifs.notClosed.slice(0, 3)

    visible: root.recent.length > 0
    height: visible ? implicitHeight : 0

    Column {
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("NOTIFICATIONS")
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }

        Repeater {
            model: root.recent

            Column {
                id: notif

                required property var modelData

                spacing: 0

                Row {
                    spacing: Tokens.spacing.small

                    StyledText {
                        width: 216
                        text: notif.modelData?.summary ?? ""
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: notif.modelData?.timeStr ?? ""
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                    }
                }

                StyledText {
                    width: 260
                    text: notif.modelData?.body ?? ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }
    }
}
