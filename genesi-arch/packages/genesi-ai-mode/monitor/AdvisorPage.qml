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
    title: "Modelos"

    readonly property color genesiGreen: "#1D9E75"
    property bool pulling: false

    actions: [
        Kirigami.Action {
            text: "Recarregar"
            icon.name: "view-refresh"
            onTriggered: page.reload()
        }
    ]

    function reload() { area.text = backend.advise() }
    function pull() {
        var m = modelInput.text.trim()
        if (page.pulling || m.length === 0)
            return
        page.pulling = true
        status.text = "iniciando download de " + m + " …"
        backend.pullModel(m)
    }

    Component.onCompleted: reload()

    Connections {
        target: backend
        function onPullStatus(s) { status.text = s }
        function onPullDone(ok) {
            page.pulling = false
            if (ok) {
                backend.loadModels()      // refresh the chat model list
                modelInput.text = ""
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label { text: "Baixar:"; opacity: 0.7 }
            QQC2.TextField {
                id: modelInput
                Layout.fillWidth: true
                placeholderText: "ex: llama3.2:3b  ou  llama3.1:8b"
                enabled: !page.pulling
                onAccepted: page.pull()
            }
            QQC2.Button {
                text: page.pulling ? "Baixando…" : "Baixar"
                icon.name: "download"
                enabled: !page.pulling && modelInput.text.trim().length > 0
                onClicked: page.pull()
            }
        }

        QQC2.Label {
            id: status
            Layout.fillWidth: true
            visible: text.length > 0
            color: page.genesiGreen
            elide: Text.ElideRight
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
                background: null
            }
        }
    }
}
