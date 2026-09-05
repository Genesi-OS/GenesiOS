/*
 * StatusCluster — volume, network, battery, in one plate.
 *
 * One background behind the group rather than one per reading: three separate
 * pills for three related facts is three times the visual weight for no more
 * information.
 */
import QtQuick
import ".."

Rectangle {
    id: root
    property var status: ({})
    signal activated(string what)

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24
    radius: BarTokens.radius
    color: hov.hovered ? BarTokens.panel : "transparent"
    Behavior on color { ColorAnimation { duration: BarTokens.quick } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: [
                { key: "volume",  glyph: "vol", suffix: "%" },
                { key: "network", glyph: "net", suffix: "" },
                { key: "battery", glyph: "bat", suffix: "%" }
            ]
            delegate: Row {
                required property var modelData
                readonly property var value: root.status[modelData.key]
                visible: value !== undefined && value !== null
                spacing: 4

                Text {
                    text: modelData.glyph
                    color: BarTokens.textDim
                    font.family: BarTokens.mono
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: String(parent.value) + modelData.suffix
                    color: BarTokens.textHi
                    font.family: BarTokens.mono
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated("status") }
}
