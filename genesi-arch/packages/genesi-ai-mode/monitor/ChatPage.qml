/*
 * Genesi AI Mode Monitor — Chat page.
 * Renders the conversation as styled bubbles (user / AI / error). Talks to the
 * Python backend, which routes to Ollama (/api/generate) or the Turbo server
 * (llama-server /completion) and streams tokens back with verbose stats.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page
    title: "Chat com a IA"
    padding: 0

    Theme { id: theme }

    property bool busy: false
    property int currentAi: -1

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
        }
    }

    Component.onCompleted: backend.loadModels()

    function send() {
        var q = input.text.trim()
        if (page.busy || q.length === 0 || modelCombo.currentText.length === 0)
            return
        chatModel.append({ "role": "user", "body": q, "stats": "" })
        chatModel.append({ "role": "ai", "body": "", "stats": "" })
        page.currentAi = chatModel.count - 1
        page.busy = true
        statsLabel.text = "gerando…"
        backend.sendPrompt(modelCombo.currentText, q)
        input.text = ""
        chatList.positionViewAtEnd()
    }

    Connections {
        target: backend
        function onTurboStatus(s) { statsLabel.text = s }
        function onTurboNeedsInstall(need) { /* handled in Main.qml */ }
        function onModelsLoaded(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            modelCombo.model = arr
            if (arr.length > 0 && modelCombo.currentIndex < 0)
                modelCombo.currentIndex = 0
            noModels.visible = arr.length === 0
        }
        function onChatToken(t) {
            if (page.currentAi < 0) return
            chatModel.setProperty(page.currentAi, "body", chatModel.get(page.currentAi).body + t)
            chatList.positionViewAtEnd()
        }
        function onChatDone(stats) {
            if (page.currentAi >= 0 && stats.length > 0)
                chatModel.setProperty(page.currentAi, "stats", stats)
            statsLabel.text = stats.length > 0 ? stats : "pronto"
            page.busy = false
            page.currentAi = -1
            chatList.positionViewAtEnd()
        }
        function onChatError(e) {
            if (page.currentAi >= 0 && chatModel.get(page.currentAi).body.length === 0)
                chatModel.remove(page.currentAi)   // drop the empty AI placeholder
            chatModel.append({ "role": "error", "body": e + "  — o Ollama está rodando?", "stats": "" })
            statsLabel.text = "erro"
            page.busy = false
            page.currentAi = -1
            chatList.positionViewAtEnd()
        }
    }

    ListModel { id: chatModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top bar: model picker + live status ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: theme.a(theme.bgTop, 0.6)
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label { text: "Modelo"; color: theme.textMid; font.pixelSize: 12 }
                QQC2.ComboBox {
                    id: modelCombo
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: backend.loadModels()
                    QQC2.ToolTip.text: "Recarregar modelos"
                    QQC2.ToolTip.visible: hovered
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    id: statsLabel
                    text: ""
                    color: theme.greenBright
                    font.bold: true
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                }
            }
        }

        Kirigami.InlineMessage {
            id: noModels
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: false
            type: Kirigami.MessageType.Warning
            text: "Nenhum modelo do Ollama encontrado. Rode `ollama pull llama3.2` " +
                  "e confira se o serviço está ativo (`systemctl enable --now ollama`)."
        }

        // ── Conversation ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // empty-state
            ColumnLayout {
                anchors.centerIn: parent
                visible: chatModel.count === 0
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72; height: 72; radius: 20
                    color: theme.a(theme.green, 0.10)
                    border.color: theme.a(theme.green, 0.35); border.width: 1
                    QQC2.Label { anchors.centerIn: parent; text: "💬"; font.pixelSize: 34 }
                }
                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Converse com a IA local"
                    font.bold: true; font.pixelSize: 16; color: theme.textHi
                }
                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Roda 100% no seu hardware. Pergunte algo abaixo 👇"
                    color: theme.textLo
                }
            }

            ListView {
                id: chatList
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                clip: true
                spacing: 6
                model: chatModel
                cacheBuffer: 4000
                boundsBehavior: Flickable.StopAtBounds
                delegate: ChatBubble {
                    width: ListView.view.width
                    role: model.role
                    body: model.body
                    stats: model.stats
                }
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            }
        }

        // ── Input bar ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: inputRow.implicitHeight + Kirigami.Units.largeSpacing
            color: theme.a(theme.bgTop, 0.6)
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.line }

            RowLayout {
                id: inputRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                anchors.topMargin: Kirigami.Units.smallSpacing
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 21
                    color: theme.card
                    border.width: 1
                    border.color: input.activeFocus ? theme.green : theme.line
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    QQC2.TextField {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        verticalAlignment: TextInput.AlignVCenter
                        background: null
                        color: theme.textHi
                        placeholderText: "Pergunte algo à IA…"
                        placeholderTextColor: theme.textLo
                        enabled: !page.busy
                        onAccepted: page.send()
                    }
                }

                // stop (while generating)
                Rectangle {
                    visible: page.busy
                    width: 42; height: 42; radius: 21
                    color: stopMa.containsMouse ? theme.a(theme.red, 0.25) : theme.a(theme.red, 0.15)
                    border.color: theme.red; border.width: 1
                    Kirigami.Icon { anchors.centerIn: parent; source: "media-playback-stop"; width: 18; height: 18; color: theme.red }
                    MouseArea { id: stopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: backend.stopChat() }
                }

                // send
                Rectangle {
                    width: 42; height: 42; radius: 21
                    readonly property bool canSend: !page.busy && input.text.trim().length > 0
                    color: canSend ? theme.green : theme.a(theme.textHi, 0.10)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: "document-send"
                        width: 18; height: 18
                        color: parent.canSend ? "#08130E" : theme.textLo
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.canSend
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.send()
                    }
                }
            }
        }
    }
}
