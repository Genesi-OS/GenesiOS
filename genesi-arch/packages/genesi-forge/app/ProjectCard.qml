/*
 * Genesi Forge — project card for the hub grid. Brand logo + star, name, path,
 * stack badge and a footer with the current branch and last-commit age.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

GlassCard {
    id: root
    property var theme
    property var project
    signal opened()
    signal starToggled()

    Layout.fillWidth: true
    implicitHeight: 150
    accent: theme ? theme.green : "#1FBE6A"

    function fmtAgo(epoch) {
        if (!epoch) return "no commits"
        var s = Math.max(1, Math.floor(Date.now() / 1000) - epoch)
        if (s < 60) return s + "s ago"
        var m = Math.floor(s / 60); if (m < 60) return m + "m ago"
        var h = Math.floor(m / 60); if (h < 24) return h + "h ago"
        var d = Math.floor(h / 24); if (d < 30) return d + "d ago"
        var mo = Math.floor(d / 30); if (mo < 12) return mo + "mo ago"
        return Math.floor(mo / 12) + "y ago"
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            TechLogo {
                kind: root.project.stackKind
                color: root.project.stackColor
                size: 46
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                radius: 8
                color: star.containsMouse ? root.theme.cardHi : "transparent"
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: root.project.starred ? "rating" : "rating-unrated"
                    width: 17; height: 17
                    color: root.project.starred ? root.theme.turboBright : root.theme.textLo
                }
                MouseArea {
                    id: star
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.starToggled()
                }
            }
        }

        Item { Layout.fillHeight: true }

        QQC2.Label {
            text: root.project.name
            color: root.theme.textHi
            font.family: root.theme.display
            font.pixelSize: 17; font.bold: true
            Layout.fillWidth: true; elide: Text.ElideRight
        }
        QQC2.Label {
            text: root.project.shortPath
            color: root.theme.textLo
            font.pixelSize: 12
            Layout.fillWidth: true; elide: Text.ElideMiddle
        }

        Item { Layout.preferredHeight: 10 }

        Rectangle {
            Layout.preferredWidth: badge.implicitWidth + 20
            Layout.preferredHeight: 24
            radius: 7
            color: root.theme.a(root.project.stackColor, 0.14)
            border.width: 1
            border.color: root.theme.a(root.project.stackColor, 0.32)
            QQC2.Label {
                id: badge
                anchors.centerIn: parent
                text: root.project.stack
                color: Qt.lighter(root.project.stackColor, root.theme.dark ? 1.25 : 1.0)
                font.pixelSize: 11; font.bold: true
            }
        }

        Item { Layout.preferredHeight: 12 }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.line }
        Item { Layout.preferredHeight: 10 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Kirigami.Icon { source: "vcs-branch"; width: 14; height: 14
                color: root.project.hasGit ? root.theme.greenBright : root.theme.textLo }
            QQC2.Label {
                text: root.project.hasGit ? (root.project.branch || "—") : "no git"
                color: root.theme.textMid; font.pixelSize: 12
            }
            Item { Layout.fillWidth: true }
            QQC2.Label {
                visible: root.project.changed > 0
                text: root.project.changed + " changed"
                color: root.theme.turboBright; font.pixelSize: 11; font.bold: true
            }
            Kirigami.Icon { visible: root.project.changed === 0; source: "appointment-new"
                width: 13; height: 13; color: root.theme.textLo }
            QQC2.Label {
                visible: root.project.changed === 0
                text: root.fmtAgo(root.project.lastTime)
                color: root.theme.textLo; font.pixelSize: 11
            }
        }
    }
}
