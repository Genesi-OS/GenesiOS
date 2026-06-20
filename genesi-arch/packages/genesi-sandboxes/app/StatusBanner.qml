/*
 * Genesi design kit — inline status banner (replaces the flat Kirigami.Inline-
 * Message). Accent-tinted glass strip with an icon, title + body, and an
 * optional action button (e.g. "Start Docker"). Set `visible` from the caller.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Rectangle {
    id: banner

    property var theme
    property color accent: theme ? theme.turbo : "#E67E22"
    property string icon: "dialog-information"
    property string title: ""
    property string body: ""
    property string action: ""
    property string actionIcon: ""
    property bool busy: false
    signal actionClicked()

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.largeSpacing
    Layout.rightMargin: Kirigami.Units.largeSpacing
    Layout.preferredHeight: row.implicitHeight + Kirigami.Units.largeSpacing * 2

    radius: 14
    color: theme.a(accent, 0.10)
    border.width: 1
    border.color: theme.a(accent, 0.45)

    RowLayout {
        id: row
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            width: 38; height: 38; radius: 11
            color: banner.theme.a(banner.accent, 0.16)
            Layout.alignment: Qt.AlignTop
            Kirigami.Icon { anchors.centerIn: parent; source: banner.icon; width: 20; height: 20; color: banner.accent }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            QQC2.Label { text: banner.title; font.bold: true; font.pixelSize: 14; color: banner.theme.textHi }
            QQC2.Label {
                Layout.fillWidth: true
                text: banner.body
                wrapMode: Text.WordWrap
                color: banner.theme.textMid
                font.pixelSize: 12
                font.family: banner.body.indexOf("sudo ") >= 0 ? "monospace" : Qt.application.font.family
            }
        }

        GButton {
            theme: banner.theme
            kind: "filled"
            accent: banner.accent
            text: banner.action
            iconSource: banner.actionIcon
            visible: banner.action.length > 0
            enabled: !banner.busy
            Layout.alignment: Qt.AlignVCenter
            onClicked: banner.actionClicked()
        }
    }
}
