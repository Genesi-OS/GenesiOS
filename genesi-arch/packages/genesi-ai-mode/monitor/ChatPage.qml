/*
 * Genesi AI Mode Monitor — Chat page.
 * Talks to the locally-running Ollama (/api/generate, streamed) via the Python
 * backend and shows the verbose generation stats (tokens/s, token counts, time)
 * so you can see AI Mode's effect while you chat. `backend` is a context
 * property set by genesi_ai_monitor.py, available to every loaded QML file.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page
    title: "Chat com a IA"

    readonly property color genesiGreen: "#1D9E75"
    property bool busy: false
    property string history: ""     // committed transcript
    property string current: ""     // streaming response buffer

    Component.onCompleted: backend.loadModels()

    function send() {
        var q = input.text.trim()
        if (page.busy || q.length === 0 || modelCombo.currentText.length === 0)
            return
        page.history += "🧑  " + q + "\n\n🤖  "
        page.current = ""
        transcript.text = page.history
        page.busy = true
        statsLabel.text = "gerando…"
        backend.sendPrompt(modelCombo.currentText, q)
        input.text = ""
    }

    function applyTurbo() {
        if (modelCombo.currentText.length > 0)
            backend.setTurbo(turboSwitch.checked, modelCombo.currentText)
    }

    Connections {
        target: backend
        function onTurboStatus(s) { statsLabel.text = s }
        function onModelsLoaded(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            modelCombo.model = arr
            if (arr.length > 0 && modelCombo.currentIndex < 0)
                modelCombo.currentIndex = 0
            noModels.visible = arr.length === 0
        }
        function onChatToken(t) {
            page.current += t
            transcript.text = page.history + page.current
            transcript.cursorPosition = transcript.length
        }
        function onChatDone(stats) {
            page.history += page.current + "\n"
            if (stats.length > 0)
                page.history += "   ⟦ " + stats + " ⟧\n"
            page.history += "\n"
            page.current = ""
            transcript.text = page.history
            statsLabel.text = stats.length > 0 ? stats : "pronto"
            page.busy = false
        }
        function onChatError(e) {
            page.history += "\n[erro: " + e + " — o Ollama está rodando?]\n\n"
            page.current = ""
            transcript.text = page.history
            statsLabel.text = "erro"
            page.busy = false
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label { text: "Modelo:"; opacity: 0.7 }
            QQC2.ComboBox {
                id: modelCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                onCurrentTextChanged: if (turboSwitch.checked) page.applyTurbo()
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                onClicked: backend.loadModels()
                QQC2.ToolTip.text: "Recarregar modelos"
                QQC2.ToolTip.visible: hovered
            }
            Item { Layout.fillWidth: true }
            QQC2.Switch {
                id: turboSwitch
                text: "⚡ Turbo"
                QQC2.ToolTip.text: "Speculative decoding — respostas 1.5–3× mais rápidas, mesma qualidade"
                QQC2.ToolTip.visible: hovered
                onToggled: page.applyTurbo()
            }
            QQC2.Label {
                id: statsLabel
                text: ""
                color: page.genesiGreen
                font.bold: true
            }
        }

        Kirigami.InlineMessage {
            id: noModels
            Layout.fillWidth: true
            visible: false
            type: Kirigami.MessageType.Warning
            text: "Nenhum modelo do Ollama encontrado. Rode `ollama pull llama3.2` " +
                  "e confira se o serviço está ativo (`systemctl enable --now ollama`)."
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.TextArea {
                id: transcript
                readOnly: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                placeholderText: "A conversa aparece aqui. Pergunte algo abaixo 👇"
            }
        }
    }

    footer: QQC2.Pane {
        RowLayout {
            anchors.fill: parent
            QQC2.TextField {
                id: input
                Layout.fillWidth: true
                placeholderText: "Pergunte algo à IA…"
                enabled: !page.busy
                onAccepted: page.send()
            }
            QQC2.Button {
                text: "Enviar"
                icon.name: "document-send"
                enabled: !page.busy && input.text.trim().length > 0
                onClicked: page.send()
            }
            QQC2.Button {
                text: "Parar"
                icon.name: "media-playback-stop"
                visible: page.busy
                onClicked: backend.stopChat()
            }
        }
    }
}
