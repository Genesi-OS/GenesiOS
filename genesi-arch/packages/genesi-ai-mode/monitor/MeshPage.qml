/*
 * Genesi AI Mode Monitor — Mesh page.
 *
 * Pool the GPU memory of several machines so a model that fits on none of them
 * individually still runs. This page is a FRONT-END ONLY: the daemon already
 * publishes state.json / peers.json, and `genesi-mesh` already owns every
 * privileged action, so nothing here re-implements mesh logic. That is what
 * keeps the GUI and the terminal from telling the user different stories.
 *
 * The page also says the two things that made a real test fail: discovery
 * cannot cross a VPN (so an empty peer list is expected there, not a fault),
 * and an integrated GPU contributes no dedicated VRAM.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var i18n

    property var st: ({})
    property var peers: []
    property bool available: true
    property string busyText: ""
    property string output: ""

    function refresh() {
        available = backend.meshAvailable()
        if (!available)
            return
        try { st = JSON.parse(backend.meshState()) } catch (e) { st = ({}) }
        try { peers = (JSON.parse(backend.meshPeers()).peers) || [] }
        catch (e) { peers = [] }
    }

    function admin(cmd, arg) {
        busyText = cmd
        output = backend.meshAdmin(cmd, arg || "")
        busyText = ""
        refresh()
    }

    Component.onCompleted: refresh()
    Timer { interval: 4000; running: root.visible; repeat: true; onTriggered: root.refresh() }

    QQC2.ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width - 40
            x: 20
            y: 16
            spacing: 14

            QQC2.Label {
                text: "Genesi Mesh"
                color: theme.white
                font.pixelSize: 24
                font.bold: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: theme.a(theme.white, 0.65)
                font.pixelSize: 12
                text: "Junte a memória de vídeo de várias máquinas para rodar um modelo "
                      + "que não caberia em nenhuma delas sozinha."
            }

            // ── genesi-mesh ausente ──────────────────────────────────────────
            Rectangle {
                visible: !root.available
                Layout.fillWidth: true
                implicitHeight: 64
                radius: 12
                color: theme.a(theme.red, 0.12)
                border.width: 1
                border.color: theme.a(theme.red, 0.5)
                QQC2.Label {
                    anchors.fill: parent
                    anchors.margins: 14
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    color: theme.white
                    font.pixelSize: 12
                    text: "O pacote genesi-mesh não está instalado.\n"
                          + "Instale com:  sudo pacman -S genesi-mesh"
                }
            }

            // ── esta máquina ─────────────────────────────────────────────────
            Rectangle {
                visible: root.available
                Layout.fillWidth: true
                implicitHeight: localCol.implicitHeight + 28
                radius: 14
                color: theme.a(theme.white, 0.04)
                border.width: 1
                border.color: theme.a(theme.white, 0.10)

                ColumnLayout {
                    id: localCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    QQC2.Label {
                        text: "Esta máquina"
                        color: theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 4
                        Layout.fillWidth: true

                        QQC2.Label { text: "Daemon"; color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label {
                            color: root.st.updated ? theme.greenBright : theme.red
                            font.pixelSize: 11
                            text: root.st.updated ? "ativo" : "parado — sudo systemctl enable --now genesi-meshd"
                        }

                        QQC2.Label { text: "GPU"; color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label {
                            color: theme.white
                            font.pixelSize: 11
                            text: (root.st.backend || "?") + " · " + (root.st.vram_mb || 0) + " MiB"
                                  + (root.st.integrated ? "  (integrada — é RAM do sistema)" : "")
                        }

                        QQC2.Label { text: "Endereço"; color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label { text: root.st.addr || "—"; color: theme.white; font.pixelSize: 11 }

                        QQC2.Label { text: "Backend RPC"; color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label {
                            font.pixelSize: 11
                            readonly property bool ok: root.st.capabilities
                                                       && root.st.capabilities.rpc_server
                                                       && root.st.capabilities.rpc_flag
                            color: ok ? theme.greenBright : theme.red
                            text: ok ? "disponível"
                                     : "ausente — instale genesi-llama-cpp (ou -cuda)"
                        }
                    }

                    // Compartilhar a GPU
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 10

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: theme.a(theme.white, 0.75)
                            font.pixelSize: 11
                            text: root.st.worker
                                  ? "Compartilhando esta GPU em " + (root.st.rpc_bind || "?")
                                    + ":" + (root.st.rpc_port || "?")
                                  : "Esta máquina NÃO está emprestando a GPU."
                        }

                        QQC2.Button {
                            text: root.st.worker ? "Parar de compartilhar" : "Compartilhar GPU"
                            enabled: root.busyText === ""
                            onClicked: root.admin("worker", root.st.worker ? "off" : "on")
                        }
                    }

                    // rpc-server tem ZERO autenticação. Dizer isso onde o botão está,
                    // não numa doc que ninguém abre.
                    QQC2.Label {
                        visible: root.st.worker
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.turboBright
                        font.pixelSize: 10
                        text: "O servidor RPC não tem autenticação nenhuma. Só compartilhe "
                              + "numa rede que você controla (LAN de casa ou VPN)."
                    }
                }
            }

            // ── peers ────────────────────────────────────────────────────────
            Rectangle {
                visible: root.available
                Layout.fillWidth: true
                implicitHeight: peerCol.implicitHeight + 28
                radius: 14
                color: theme.a(theme.white, 0.04)
                border.width: 1
                border.color: theme.a(theme.white, 0.10)

                ColumnLayout {
                    id: peerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    QQC2.Label {
                        text: "Máquinas (" + root.peers.length + ")"
                        color: theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Repeater {
                        model: root.peers
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: modelData.worker ? theme.greenBright
                                                        : theme.a(theme.white, 0.3)
                            }
                            QQC2.Label {
                                text: modelData.host || "?"
                                color: theme.white; font.pixelSize: 12
                                Layout.preferredWidth: 150
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                text: modelData.addr || ""
                                color: theme.a(theme.white, 0.55); font.pixelSize: 11
                                Layout.preferredWidth: 130
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                color: theme.a(theme.white, 0.75); font.pixelSize: 11
                                text: (modelData.backend || "?") + " · "
                                      + (modelData.vram_mb || 0) + " MiB"
                                      + (modelData.integrated ? "  [integrada]" : "")
                                      + (modelData.worker ? "" : "  (não compartilha)")
                            }
                        }
                    }

                    QQC2.Label {
                        visible: root.peers.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.55)
                        font.pixelSize: 11
                        // The exact trap a real test hit: everything configured
                        // correctly, list empty, and no hint that this is normal.
                        text: "Nenhuma outra máquina encontrada.\n\n"
                              + "A descoberta automática usa multicast, que NÃO atravessa VPN. "
                              + "Se as máquinas estão em redes diferentes (Tailscale/WireGuard), "
                              + "isso é esperado — registre o endereço da outra abaixo e as duas "
                              + "passam a se enxergar."
                    }

                    // Registrar peer por endereço (o caminho que funciona em VPN)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        QQC2.TextField {
                            id: peerAddr
                            Layout.fillWidth: true
                            placeholderText: "IP da outra máquina (ex.: 100.64.1.2)"
                            font.pixelSize: 12
                        }
                        QQC2.Button {
                            text: "Registrar máquina"
                            enabled: peerAddr.text.trim() !== "" && root.busyText === ""
                            onClicked: { root.admin("peer", peerAddr.text.trim()); peerAddr.text = "" }
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.45)
                        font.pixelSize: 10
                        text: "Faça isso nas DUAS máquinas."
                    }
                }
            }

            // ── mesh (segredo) ───────────────────────────────────────────────
            Rectangle {
                visible: root.available
                Layout.fillWidth: true
                implicitHeight: joinCol.implicitHeight + 28
                radius: 14
                color: theme.a(theme.white, 0.04)
                border.width: 1
                border.color: theme.a(theme.white, 0.10)

                ColumnLayout {
                    id: joinCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    QQC2.Label {
                        text: "Rede confiável"
                        color: theme.white; font.pixelSize: 14; font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.65)
                        font.pixelSize: 11
                        text: "Todas as máquinas compartilham UM segredo — é ele que faz "
                              + "uma reconhecer a outra. Crie na primeira, e cole nas demais. "
                              + "Ele autentica só a descoberta."
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        QQC2.Button {
                            text: "Criar mesh aqui"
                            enabled: root.busyText === ""
                            onClicked: root.admin("init", "")
                        }
                        QQC2.Button {
                            text: "Ver segredo"
                            enabled: root.busyText === ""
                            onClicked: root.admin("show-secret", "")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        QQC2.TextField {
                            id: secretField
                            Layout.fillWidth: true
                            placeholderText: "cole aqui o segredo da primeira máquina"
                            font.pixelSize: 12
                        }
                        QQC2.Button {
                            text: "Entrar"
                            enabled: secretField.text.trim().length >= 32 && root.busyText === ""
                            onClicked: { root.admin("join", secretField.text.trim()); secretField.text = "" }
                        }
                    }
                }
            }

            // ── saída dos comandos ───────────────────────────────────────────
            Rectangle {
                visible: root.output !== ""
                Layout.fillWidth: true
                implicitHeight: outLabel.implicitHeight + 26
                radius: 12
                color: theme.a(theme.white, 0.05)
                border.width: 1
                border.color: theme.a(theme.white, 0.10)
                QQC2.Label {
                    id: outLabel
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: 13
                    wrapMode: Text.WordWrap
                    color: theme.a(theme.white, 0.85)
                    font.family: "monospace"
                    font.pixelSize: 11
                    text: root.output
                }
            }

            RowLayout {
                visible: root.available
                Layout.fillWidth: true
                Layout.bottomMargin: 20
                spacing: 8
                QQC2.Button {
                    text: "Diagnóstico"
                    onClicked: root.output = backend.meshDoctor()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
