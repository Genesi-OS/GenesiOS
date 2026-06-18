/*
 * Genesi AI Mode Monitor — chat message bubble.
 * role: "user" | "ai" | "error". Sizes to content up to ~74% width and aligns
 * to the correct side, with an avatar. AI replies show a rich stats panel
 * (speed, tokens, timings) parsed from the backend's JSON stats string.
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

    // Parsed stats (AI only). null when streaming or non-JSON (plain fallback).
    readonly property var statsData: {
        if (role !== "ai" || stats.length === 0) return null
        try { return JSON.parse(stats) } catch (e) { return null }
    }
    // Chips to show — only metrics that are present (> 0).
    readonly property var chipModel: {
        var d = statsData
        if (!d) return []
        var out = []
        if (d.eval)     out.push({ "value": "" + d.eval,      "label": "tokens" })
        if (d.prompt)   out.push({ "value": "" + d.prompt,    "label": "prompt" })
        if (d.gen_s)    out.push({ "value": d.gen_s + "s",    "label": "generation" })
        if (d.prompt_s) out.push({ "value": d.prompt_s + "s", "label": "read prompt" })
        if (d.load_s)   out.push({ "value": d.load_s + "s",   "label": "load" })
        if (d.total_s)  out.push({ "value": d.total_s + "s",  "label": "total time" })
        return out
    }

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
                 : "#22262A"
            border.width: 1
            border.color: b.isUser ? "transparent"
                        : b.isError ? "#E74C3C" : "#3A4146"
            Image {
                anchors.centerIn: parent
                source: Qt.resolvedUrl(b.isUser ? "icons/user.svg"
                                     : b.isError ? "icons/alert.svg" : "icons/bot.svg")
                sourceSize.width: 18; sourceSize.height: 18
                width: 18; height: 18
                smooth: true
            }
        }

        // bubble
        Rectangle {
            id: bubble
            Layout.alignment: Qt.AlignTop
            radius: 16
            implicitWidth: Math.min(Math.max(txt.implicitWidth, b.statsData ? 320 : 0) + 28, b.width * 0.74)
            implicitHeight: content.implicitHeight + 20
            color: b.isUser ? "#15694F"
                 : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.10)
                 : "#1F2225"
            border.width: 1
            border.color: b.isUser ? Qt.rgba(52/255, 211/255, 153/255, 0.35)
                        : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.5)
                        : "#31363B"

            Column {
                id: content
                x: 14; y: 10
                width: bubble.width - 28
                spacing: 8

                QQC2.Label {
                    id: txt
                    width: parent.width
                    text: b.body.length > 0 ? b.body : "…"
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: b.isError ? "#F1B0A8" : "#EAF3EF"
                    lineHeight: 1.15
                }

                // plain fallback (non-JSON stats string)
                QQC2.Label {
                    width: parent.width
                    visible: b.stats.length > 0 && b.statsData === null
                    text: b.stats
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: "#7FB8A2"
                }

                // ── rich stats panel ──
                Rectangle {
                    width: parent.width
                    visible: b.statsData !== null
                    radius: 11
                    color: Qt.rgba(0, 0, 0, 0.22)
                    border.color: "#223A30"; border.width: 1
                    implicitHeight: statsCol.implicitHeight + 18

                    Column {
                        id: statsCol
                        x: 11; y: 9
                        width: parent.width - 22
                        spacing: 9

                        // header: mode badge + headline speed
                        Item {
                            width: parent.width
                            height: 22
                            Rectangle {
                                id: modeBadge
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property bool turbo: b.statsData && b.statsData.mode === "turbo"
                                radius: 7; height: 22
                                width: badgeRow.implicitWidth + 16
                                color: turbo ? Qt.rgba(230/255, 126/255, 34/255, 0.18)
                                             : Qt.rgba(29/255, 158/255, 117/255, 0.16)
                                Row {
                                    id: badgeRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: Qt.resolvedUrl(modeBadge.turbo ? "icons/bolt.svg" : "icons/cpu.svg")
                                        sourceSize.width: 12; sourceSize.height: 12
                                        width: 12; height: 12; smooth: true
                                    }
                                    QQC2.Label {
                                        id: badgeLbl
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modeBadge.turbo ? "Turbo" : "Ollama"
                                        font.pixelSize: 10; font.bold: true
                                        color: modeBadge.turbo ? "#F8B24D" : "#34D399"
                                    }
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                QQC2.Label {
                                    text: b.statsData ? b.statsData.rate : ""
                                    font.bold: true; font.pixelSize: 17
                                    color: "#EAF3EF"
                                }
                                QQC2.Label {
                                    text: "tok/s"
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    font.pixelSize: 11
                                    color: "#7FB8A2"
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: "#1E382E" }

                        // metric chips
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: b.chipModel
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 8
                                    height: 36
                                    width: chipCol.implicitWidth + 18
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.color: "#1E382E"; border.width: 1
                                    Column {
                                        id: chipCol
                                        anchors.centerIn: parent
                                        spacing: 0
                                        QQC2.Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.value
                                            font.bold: true; font.pixelSize: 13
                                            color: "#EAF3EF"
                                        }
                                        QQC2.Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            font.pixelSize: 9
                                            color: "#7FB8A2"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // spacer that pushes the cluster to one side
        Item { Layout.fillWidth: true }
    }
}
