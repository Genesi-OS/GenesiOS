/*
 * Genesi AI Mode Monitor — chat message bubble.
 * role: "user" | "ai" | "error". Sizes to content up to ~74% width and aligns
 * to the correct side, with an avatar and an optional stats line for AI replies.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: b

    property string role: "ai"
    property string body: ""
    property string stats: ""

    readonly property bool isUser: role === "user"
    readonly property bool isError: role === "error"

    width: ListView.view ? ListView.view.width : 600
    implicitHeight: row.implicitHeight + 12

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        layoutDirection: b.isUser ? Qt.RightToLeft : Qt.LeftToRight

        // avatar
        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 34; height: 34; radius: 17
            color: b.isUser ? "#1D9E75"
                 : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.18)
                 : "#16271F"
            border.width: 1
            border.color: b.isUser ? "transparent"
                        : b.isError ? "#E74C3C" : "#2A463B"
            QQC2.Label {
                anchors.centerIn: parent
                text: b.isUser ? "🧑" : (b.isError ? "⚠" : "🤖")
                font.pixelSize: 15
                color: b.isError ? "#E74C3C" : "#EAF3EF"
            }
        }

        // bubble
        Rectangle {
            id: bubble
            Layout.alignment: Qt.AlignTop
            radius: 16
            implicitWidth: Math.min(Math.max(txt.implicitWidth, statsLbl.visible ? statsLbl.implicitWidth : 0) + 28, b.width * 0.74)
            implicitHeight: content.implicitHeight + 20
            color: b.isUser ? "#15694F"
                 : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.10)
                 : "#13241D"
            border.width: 1
            border.color: b.isUser ? Qt.rgba(52/255, 211/255, 153/255, 0.35)
                        : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.5)
                        : "#223A30"

            Column {
                id: content
                x: 14; y: 10
                width: bubble.width - 28
                spacing: 5

                QQC2.Label {
                    id: txt
                    width: parent.width
                    text: b.body.length > 0 ? b.body : "…"
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: b.isError ? "#F1B0A8" : "#EAF3EF"
                    lineHeight: 1.15
                }

                QQC2.Label {
                    id: statsLbl
                    width: parent.width
                    visible: b.stats.length > 0
                    text: b.stats
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: "#7FB8A2"
                }
            }
        }

        // spacer that pushes the cluster to one side
        Item { Layout.fillWidth: true }
    }
}
