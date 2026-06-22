/*
 * Genesi AI Mode Monitor — chat message bubble.
 * role: "user" | "ai" | "error". Sizes to content up to ~74% width and aligns
 * to the correct side, with an avatar. AI replies show a rich stats panel
 * (speed, tokens, timings) parsed from the backend's JSON stats string.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: b

    property string role: "ai"
    property string body: ""
    property string stats: ""

    readonly property bool isUser: role === "user"
    readonly property bool isError: role === "error"

    // Follow the system scheme (see genesi-ui-kit/Theme.qml) — no fixed brand blue.
    readonly property color _bg: Kirigami.Theme.backgroundColor
    readonly property color _txt: Kirigami.Theme.textColor
    readonly property color _accent: Kirigami.Theme.highlightColor
    readonly property bool _dark: !((0.299 * _bg.r + 0.587 * _bg.g + 0.114 * _bg.b) >= 0.5)
    readonly property color _white: "#ffffff"
    readonly property color _black: "#000000"
    function _mix(c, o, p) { return Qt.rgba(c.r + (o.r - c.r) * p, c.g + (o.g - c.g) * p, c.b + (o.b - c.b) * p, 1) }
    function _a(c, v) { return Qt.rgba(c.r, c.g, c.b, v) }
    readonly property color _card:   _mix(_bg, _white, _dark ? 0.10 : 0.05)
    readonly property color _line:   _dark ? _mix(_bg, _white, 0.12) : _mix(_bg, _black, 0.12)
    readonly property color _txtMid: _mix(_txt, _bg, 0.40)

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
            color: b.isUser ? b._accent
                 : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.18)
                 : b._card
            border.width: 1
            border.color: b.isUser ? "transparent"
                        : b.isError ? "#E74C3C" : b._line
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
            color: b.isUser ? b._mix(b._accent, b._bg, 0.55)
                 : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.10)
                 : b._card
            border.width: 1
            border.color: b.isUser ? b._a(b._accent, 0.40)
                        : b.isError ? Qt.rgba(231/255, 76/255, 60/255, 0.5)
                        : b._line

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
                    color: b.isError ? "#F1B0A8" : b._txt
                    lineHeight: 1.15
                }

                // plain fallback (non-JSON stats string)
                QQC2.Label {
                    width: parent.width
                    visible: b.stats.length > 0 && b.statsData === null
                    text: b.stats
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                    color: b._txtMid
                }

                // ── rich stats panel ──
                Rectangle {
                    width: parent.width
                    visible: b.statsData !== null
                    radius: 11
                    color: Qt.rgba(0, 0, 0, 0.22)
                    border.color: b._line; border.width: 1
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
                                             : b._a(b._accent, 0.16)
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
                                        color: modeBadge.turbo ? "#F8B24D" : b._accent
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
                                    color: b._txt
                                }
                                QQC2.Label {
                                    text: "tok/s"
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    font.pixelSize: 11
                                    color: b._txtMid
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: b._line }

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
                                    border.color: b._line; border.width: 1
                                    Column {
                                        id: chipCol
                                        anchors.centerIn: parent
                                        spacing: 0
                                        QQC2.Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.value
                                            font.bold: true; font.pixelSize: 13
                                            color: b._txt
                                        }
                                        QQC2.Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            font.pixelSize: 9
                                            color: b._txtMid
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
