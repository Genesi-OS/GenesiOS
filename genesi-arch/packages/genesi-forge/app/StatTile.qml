/*
 * Genesi Forge — dashboard stat tile: tinted rounded icon badge, big value,
 * caption. Sits on FCard (graphite surface).
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

FCard {
    id: root
    property string icon: ""
    property string value: "0"
    property string label: ""

    Layout.fillWidth: true
    implicitHeight: 92

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18; anchors.rightMargin: 18
        spacing: 15

        Rectangle {
            Layout.preferredWidth: 46; Layout.preferredHeight: 46
            radius: 13
            color: root.theme.a(root.accent, 0.15)
            border.width: 1
            border.color: root.theme.a(root.accent, 0.32)
            FIcon { anchors.centerIn: parent; name: root.icon; size: 22; color: root.accent }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            QQC2.Label {
                text: root.value
                color: root.theme.textHi
                font.family: root.theme.display
                font.pixelSize: 25; font.bold: true
            }
            QQC2.Label {
                text: root.label
                color: root.theme.textMid
                font.pixelSize: 12
            }
        }
    }
}
