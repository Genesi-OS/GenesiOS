/*
 * Genesi Forge — project Overview tab. Keeps the classic Forge dashboard: git
 * stat tiles, the latest commit, the core git actions and detected integrations.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.ScrollView {
    id: root
    property var theme
    property var project
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.topMargin: 26
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Label { text: root.project ? root.project.name : ""; color: root.theme.textHi
                    font.family: root.theme.display; font.pixelSize: 26; font.bold: true }
                QQC2.Label { text: root.project ? (root.project.slug || root.project.shortPath) : ""
                    color: root.theme.textMid; font.pixelSize: 13; elide: Text.ElideMiddle; Layout.fillWidth: true }
            }
            GButton { theme: root.theme; kind: "filled"; text: "Open in Code"; iconSource: "code-context"
                visible: root.project; onClicked: backend.openCode(root.project.path) }
            GButton { theme: root.theme; kind: "tonal"; iconSource: "utilities-terminal"; tooltip: "Open terminal"
                visible: root.project; onClicked: backend.openTerminal(root.project.path) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28
            spacing: 14
            Repeater {
                model: root.project ? [
                    { label: "Branch",    value: root.project.branch || "—", color: root.theme.greenBright },
                    { label: "Staged",    value: String(root.project.staged),   color: root.theme.blue },
                    { label: "Modified",  value: String(root.project.modified), color: root.theme.turbo },
                    { label: "Untracked", value: String(root.project.untracked),color: root.theme.textHi }
                ] : []
                delegate: GlassCard {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 82
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 2
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: modelData.value; color: modelData.color
                            font.family: root.theme.display; font.pixelSize: 22; font.bold: true }
                        QQC2.Label { Layout.alignment: Qt.AlignHCenter; text: modelData.label; color: root.theme.textLo; font.pixelSize: 11 }
                    }
                }
            }
        }

        GlassCard {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28
            implicitHeight: 118
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 6
                QQC2.Label { text: "Latest commit"; color: root.theme.textLo; font.pixelSize: 11; font.bold: true }
                QQC2.Label { text: root.project ? (root.project.lastSubject || "No commits yet") : ""
                    color: root.theme.textHi; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                QQC2.Label { text: root.project ? root.project.lastHash : ""; color: root.theme.greenBright; font.family: "monospace" }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28
            GButton { theme: root.theme; kind: "tonal"; text: "Fetch"; iconSource: "vcs-update-required"
                visible: root.project && root.project.hasGit; onClicked: backend.fetch(root.project.path) }
            GButton { theme: root.theme; kind: "tonal"; text: "Pull FF"; iconSource: "go-down"
                visible: root.project && root.project.hasGit; onClicked: backend.pull(root.project.path) }
            GButton { theme: root.theme; kind: "tonal"; text: "Push"; iconSource: "go-up"
                visible: root.project && root.project.hasGit; onClicked: backend.push(root.project.path) }
            Item { Layout.fillWidth: true }
            GButton { theme: root.theme; kind: "ghost"; text: "Repository"; iconSource: "internet-web-browser"
                visible: root.project && root.project.web; onClicked: backend.openUrl(root.project.web) }
        }

        StatusBanner {
            visible: root.project && !root.project.hasGit
            theme: root.theme; accent: root.theme.turbo; icon: "dialog-information"
            title: "Not a git repository yet"
            body: "Initialize git and create a GitHub repo from the Forge Canvas GitHub Sync node."
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.bottomMargin: 26
            spacing: 8
            QQC2.Label { text: "Integrations"; color: root.theme.textHi; font.family: root.theme.display; font.pixelSize: 16; font.bold: true }
            Repeater {
                model: root.project ? root.project.integrations : []
                delegate: Rectangle {
                    Layout.fillWidth: true; implicitHeight: 58; radius: 12
                    color: root.theme.card; border.width: 1; border.color: root.theme.line
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                        Kirigami.Icon { source: modelData.name === "Docker" ? "docker" : "cloud-status"; width: 22; height: 22; color: root.theme.greenBright }
                        ColumnLayout { Layout.fillWidth: true; spacing: 0
                            QQC2.Label { text: modelData.name; color: root.theme.textHi; font.bold: true; font.pixelSize: 13 }
                            QQC2.Label { text: modelData.detail; color: root.theme.textLo; font.pixelSize: 11 }
                        }
                        GButton { visible: modelData.url !== ""; theme: root.theme; kind: "ghost"; text: "Dashboard"; iconSource: "internet-web-browser"
                            onClicked: backend.openUrl(modelData.url) }
                    }
                }
            }
            QQC2.Label {
                visible: root.project && root.project.integrations.length === 0
                text: "No integrations detected yet."
                color: root.theme.textLo; font.pixelSize: 12
            }
        }
    }
}
