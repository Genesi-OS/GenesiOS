/*
 * Genesi AI Mode Monitor — Model Advisor + downloader.
 * Shows `genesi-ai-mode advise` (which model fits 100% on this GPU/CPU) and lets
 * you pull a model straight from the app (Ollama /api/pull) — no terminal.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page
    title: "Models"
    padding: 0

    Theme { id: theme }
    // Shared I18n instance passed in from Main (keeps the language switch in sync).
    property var i18n
    property bool pulling: false

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
        }
    }

    function reload() { area.text = backend.advise() }
    function pull() {
        var m = modelInput.text.trim()
        if (page.pulling || m.length === 0)
            return
        page.pulling = true
        status.text = i18n.t("adv.startingPre") + m + " …"
        backend.pullModel(m)
    }

    Component.onCompleted: reload()

    Connections {
        target: backend
        function onPullStatus(s) { status.text = s }
        function onPullDone(ok) {
            page.pulling = false
            if (ok) {
                backend.loadModels()
                modelInput.text = ""
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // ── Download bar ──
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: dlCol.implicitHeight + Kirigami.Units.largeSpacing * 2
            accent: theme.green
            active: page.pulling

            ColumnLayout {
                id: dlCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        width: 40; height: 40; radius: 12
                        color: theme.a(theme.green, 0.12)
                        border.color: theme.a(theme.green, 0.4); border.width: 1
                        Kirigami.Icon { anchors.centerIn: parent; source: "download"; width: 20; height: 20; color: theme.greenBright }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 21
                        color: theme.card
                        border.width: 1
                        border.color: modelInput.activeFocus ? theme.green : theme.line
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        QQC2.TextField {
                            id: modelInput
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            color: theme.textHi
                            placeholderText: i18n.t("adv.placeholder")
                            placeholderTextColor: theme.textLo
                            enabled: !page.pulling
                            onAccepted: page.pull()
                        }
                    }

                    Rectangle {
                        id: pullBtn
                        readonly property bool hasModel: modelInput.text.trim().length > 0
                        readonly property bool canPull: !page.pulling && hasModel
                        implicitWidth: pullLbl.implicitWidth + 34
                        implicitHeight: 42
                        radius: 21
                        color: page.pulling ? theme.a(theme.green, 0.22)
                             : (hasModel ? theme.a(theme.green, 0.18) : theme.a(theme.textHi, 0.10))
                        border.width: 1
                        border.color: page.pulling || hasModel ? theme.a(theme.green, 0.44) : theme.line
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            QQC2.Label {
                                text: page.pulling ? "..." : "↓"
                                font.bold: true
                                font.pixelSize: 18
                                color: page.pulling || pullBtn.hasModel ? theme.greenBright : theme.textLo
                            }
                            QQC2.Label {
                                id: pullLbl
                                text: page.pulling ? i18n.t("adv.downloading") : i18n.t("adv.download")
                                font.bold: true
                                color: page.pulling || pullBtn.hasModel ? theme.textHi : theme.textLo
                            }
                        }
                        MouseArea { anchors.fill: parent; enabled: pullBtn.canPull; cursorShape: Qt.PointingHandCursor; onClicked: page.pull() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: status.text.length > 0 || page.pulling
                    implicitHeight: 34
                    radius: 10
                    color: theme.a(theme.green, page.pulling ? 0.14 : 0.08)
                    border.width: 1
                    border.color: theme.a(theme.green, page.pulling ? 0.40 : 0.22)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        QQC2.BusyIndicator {
                            running: page.pulling
                            visible: page.pulling
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                        }
                        QQC2.Label {
                            id: status
                            Layout.fillWidth: true
                            text: ""
                            color: theme.textHi
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ── Advisor output ──
        GlassCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "help-about"; color: theme.green; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                    QQC2.Label { text: i18n.t("adv.title"); font.bold: true; font.pixelSize: 14; color: theme.textHi }
                    Item { Layout.fillWidth: true }
                    QQC2.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: page.reload()
                        QQC2.ToolTip.text: i18n.t("adv.reload")
                        QQC2.ToolTip.visible: hovered
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    QQC2.TextArea {
                        id: area
                        readOnly: true
                        wrapMode: TextEdit.NoWrap
                        textFormat: TextEdit.PlainText
                        font.family: "monospace"
                        color: theme.textMid
                        background: null
                    }
                }
            }
        }
    }
}
