/*
 * Genesi Forge — dashboard stat tile: a tinted rounded icon badge on the left,
 * a big value and a caption on the right. Uses GlassCard for the surface depth.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

GlassCard {
    id: root
    property var theme
    property string icon: ""
    accent: theme ? theme.green : "#1FBE6A"
    property string value: "0"
    property string label: ""

    Layout.fillWidth: true
    implicitHeight: 92

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18; anchors.rightMargin: 18
        spacing: 15

        Rectangle {
            Layout.preferredWidth: 48; Layout.preferredHeight: 48
            radius: 13
            color: root.theme.a(root.accent, 0.16)
            border.width: 1
            border.color: root.theme.a(root.accent, 0.34)
            Kirigami.Icon {
                anchors.centerIn: parent
                source: root.icon
                width: 24; height: 24
                color: root.accent
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            QQC2.Label {
                text: root.value
                color: root.theme.textHi
                font.family: root.theme.display
                font.pixelSize: 26; font.bold: true
            }
            QQC2.Label {
                text: root.label
                color: root.theme.textMid
                font.pixelSize: 12
            }
        }
    }
}
