/*
 * Genesi Forge — sidebar navigation row. Active state fills with a soft emerald
 * wash + accent border and lifts the icon/label to the brand green.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property string icon: ""
    property string label: ""
    property bool active: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 46

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.active ? theme.mix(theme.card, theme.green, 0.16)
              : (ma.containsMouse ? theme.cardHi : "transparent")
        border.width: 1
        border.color: root.active ? theme.a(theme.green, 0.42) : "transparent"
        Behavior on color { ColorAnimation { duration: 130 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13; anchors.rightMargin: 12
            spacing: 12
            Kirigami.Icon {
                source: root.icon
                Layout.preferredWidth: 19; Layout.preferredHeight: 19
                color: root.active ? theme.greenBright : theme.textMid
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: root.label
                color: root.active ? theme.textHi : theme.textMid
                font.pixelSize: 14
                font.bold: root.active
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
