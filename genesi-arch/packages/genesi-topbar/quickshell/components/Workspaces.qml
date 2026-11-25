/*
 * Workspaces — horizontal, which is the whole reason this bar exists.
 *
 * An empty workspace is a dot. An occupied one is a pill holding the icon of
 * every window on it, and the active one is that pill filled with the accent.
 * So the row says which workspaces are in use, which one you are on, AND what
 * is running where -- without a single label.
 *
 * The icons arrive as resolved paths from shell.qml. This file knows nothing
 * about Hyprland or the desktop database, which is what lets the whole bar be
 * rendered and looked at without a compositor (devtools/render-topbar.py).
 *
 * A window whose class matches no desktop entry gets its first letter in a
 * rounded square instead. The alternative -- a broken-image glyph, or dropping
 * it -- makes the pill lie about how many windows are on the workspace.
 */
import QtQuick
import ".."

Row {
    id: root

    property var workspaces: []
    // Beyond this the pill stops being readable and starts being a strip.
    property int maxIcons: 4
    signal picked(int id)

    spacing: 5

    Repeater {
        model: root.workspaces

        delegate: Rectangle {
            id: ws
            required property var modelData

            readonly property bool active: modelData.active === true
            readonly property bool occupied: modelData.occupied === true
            readonly property var icons: (modelData.icons || []).slice(0, root.maxIcons)
            readonly property int extra: Math.max(
                0, (modelData.windows || 0) - ws.icons.length)

            // An occupied workspace whose icons have not resolved yet must not
            // collapse to an empty dot, so occupancy alone sets the minimum.
            readonly property int pad: ws.active ? 7 : 5
            readonly property int content:
                ws.icons.length > 0 ? row.implicitWidth
                                    : (ws.occupied ? 10 : 0)

            width: ws.occupied || ws.active ? ws.content + ws.pad * 2 : 8
            height: ws.occupied || ws.active ? 20 : 8
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter

            color: ws.active ? BarTokens.accent
                             : (ws.occupied ? BarTokens.accentDim
                                            : BarTokens.line)

            Behavior on width {
                NumberAnimation { duration: BarTokens.normal; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                NumberAnimation { duration: BarTokens.normal; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: BarTokens.quick } }

            scale: hov.hovered && !ws.active ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: BarTokens.quick } }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: ws.icons

                    delegate: Item {
                        id: mark
                        required property var modelData

                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: img

                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            source: mark.modelData.source || ""
                            visible: status === Image.Ready
                        }

                        // The fallback, for a window no desktop entry claims.
                        Rectangle {
                            anchors.fill: parent
                            visible: !img.visible
                            radius: 4
                            color: ws.active ? Qt.rgba(0, 0, 0, 0.22)
                                             : Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                anchors.centerIn: parent
                                text: (mark.modelData.name || "?").charAt(0).toUpperCase()
                                font.family: BarTokens.sans
                                font.pixelSize: 9
                                font.bold: true
                                color: ws.active ? BarTokens.accentText
                                                 : BarTokens.text
                            }
                        }

                        // Each icon fades in on its own rather than the pill
                        // popping to its new width with everything already
                        // there. Opening an app should look like one arriving.
                        opacity: 0
                        Component.onCompleted: opacity = 1
                        Behavior on opacity {
                            NumberAnimation { duration: BarTokens.normal }
                        }
                    }
                }

                // "and three more". Only when the count is over the cap.
                Text {
                    visible: ws.extra > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + ws.extra
                    font.family: BarTokens.sans
                    font.pixelSize: 9
                    font.bold: true
                    // textHi, not textDim: this sits on the filled pill, not
                    // on the bar's background, and the dim text was the same
                    // value as the fill it was printed on.
                    color: ws.active ? BarTokens.accentText : BarTokens.textHi
                }
            }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(ws.modelData.id) }
        }
    }
}
