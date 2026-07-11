/*
 * Genesi Forge — sidebar navigation row (bundled FIcon set). Active state
 * fills with a soft emerald wash + accent border.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property string icon: ""
    property string label: ""
    property bool active: false
    property bool compact: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: compact ? 38 : 44

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.active ? theme.mix(theme.card, theme.green, 0.18)
              : (ma.containsMouse ? theme.cardHi : "transparent")
        border.width: 1
        border.color: root.active ? theme.a(theme.green, 0.42) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 10
            spacing: 11
            FIcon {
                name: root.icon
                size: root.compact ? 15 : 17
                color: root.active ? theme.greenBright : theme.textMid
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: root.label
                color: root.active ? theme.textHi : theme.textMid
                font.pixelSize: root.compact ? 13 : 14
                font.bold: root.active
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
