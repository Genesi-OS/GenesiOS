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
    property var usage: ({ running: false, pooling: false, endpoints: [] })
    property var turbo: ({ source: "auto", url: "", options: [] })
    property bool available: true
    property string busyText: ""
    property string output: ""

    // Reserva por GPU para KV cache/ativações — o MESMO 1.2 GB que o
    // genesi_mesh_common usa. Se divergir, a página diz que cabe um modelo que
    // o planejador vai recusar, e o usuário fica sem entender qual dos dois
    // está mentindo.
    readonly property real overheadMb: 1.2 * 1024

    function refresh() {
        available = backend.meshAvailable()
        if (!available)
            return
        try { st = JSON.parse(backend.meshState()) } catch (e) { st = ({}) }
        try { peers = (JSON.parse(backend.meshPeers()).peers) || [] }
        catch (e) { peers = [] }
        try { usage = JSON.parse(backend.meshUsage()) }
        catch (e) { usage = ({ running: false, pooling: false, endpoints: [] }) }
        try { turbo = JSON.parse(backend.turboSources()) }
        catch (e) { turbo = ({ source: "auto", url: "", options: [] }) }
    }

    // free_mb ausente = a máquina não consegue medir, e aí a capacidade é a
    // única resposta possível. Ausente NÃO é zero: tratar como zero faria toda
    // máquina antiga parecer permanentemente cheia.
    function knowsFree(o) {
        return o && o.free_mb !== undefined && o.free_mb !== null
    }

    // O que dá pra ALOCAR, que é o que decide se o pool funciona. Capacidade é
    // o número que engana: uma placa de 8 GB ocupada continua sendo de 8 GB.
    function usableMb(o) {
        if (!o) return 0
        var have = knowsFree(o) ? o.free_mb : (o.vram_mb || 0)
        return Math.max(have - overheadMb, 0)
    }

    function vramText(o) {
        if (!o) return "—"
        if (!knowsFree(o)) return (o.vram_mb || 0) + " MiB"
        return o.free_mb + " livres de " + (o.vram_mb || 0) + " MiB"
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
            // ── uso agora ────────────────────────────────────────────────────
            // `peers` diz que um mesh EXISTE; isto diz se ele está sendo USADO.
            // São perguntas diferentes e a segunda é a que o usuário da máquina
            // cliente tem — ele liga o Turbo e quer saber se a GPU da outra
            // máquina entrou. Lido do processo llama-server vivo, então vale
            // mesmo quando o Turbo caiu pro modo local sozinho.
            Rectangle {
                visible: root.available && root.usage.running
                Layout.fillWidth: true
                implicitHeight: useCol.implicitHeight + 28
                radius: 14
                color: root.usage.pooling ? theme.a(theme.greenBright, 0.10)
                                          : theme.a(theme.white, 0.04)
                border.width: 1
                border.color: root.usage.pooling ? theme.a(theme.greenBright, 0.45)
                                                 : theme.a(theme.white, 0.10)

                ColumnLayout {
                    id: useCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 6

                    QQC2.Label {
                        text: root.usage.pooling ? "Turbo está usando o mesh"
                                                 : "Turbo está rodando local"
                        color: root.usage.pooling ? theme.greenBright : theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    QQC2.Label {
                        visible: root.usage.pooling
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.white
                        font.pixelSize: 11
                        text: "Camadas do modelo estão na GPU de: "
                              + root.usage.endpoints.join(", ")
                    }

                    QQC2.Label {
                        visible: root.usage.pooling
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.55)
                        font.pixelSize: 10
                        // O trade-off precisa aparecer junto do estado, ou o
                        // usuário conclui que o mesh deixou tudo mais lento sem
                        // motivo. Ele deixa mesmo — em troca de rodar.
                        text: "As ativações atravessam a rede a cada token, então "
                              + "isso troca velocidade pela possibilidade de rodar "
                              + "um modelo que não caberia aqui."
                    }

                    QQC2.Label {
                        visible: !root.usage.pooling
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.65)
                        font.pixelSize: 11
                        // Sem isto, "rodando local" com um worker à vista parece
                        // defeito. Quase sempre não é.
                        text: root.peers.length === 0
                              ? "Nenhuma outra máquina visível — o mesh não tinha como entrar."
                              : "O modelo coube nesta máquina, ou nenhum worker tinha "
                                + "VRAM livre suficiente. O diagnóstico abaixo diz qual dos dois."
                    }
                }
            }

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
                            // Vermelho quando não há o que emprestar. A placa
                            // continua do mesmo tamanho, e é exatamente esse
                            // número que fazia o pool falhar sem explicação.
                            color: (root.st.worker && root.knowsFree(root.st)
                                    && root.usableMb(root.st) <= 0)
                                   ? theme.red : theme.white
                            font.pixelSize: 11
                            text: (root.st.backend || "?") + " · " + root.vramText(root.st)
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

                    // Compartilhar o Turbo inteiro por HTTP. É a outra forma de
                    // emprestar a GPU, e quase sempre a melhor: emprestar VRAM
                    // manda ativação de camada a cada token, isto manda texto.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 10

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: theme.a(theme.white, 0.75)
                            font.pixelSize: 11
                            text: root.st.turbo_serving
                                  ? "Servindo o Turbo para a rede"
                                    + (root.st.turbo_model ? " — " + root.st.turbo_model : "")
                                  : "Esta máquina NÃO está servindo o Turbo. Prefira isto a "
                                    + "emprestar VRAM quando o modelo couber aqui: o pool "
                                    + "manda ativação de camada a cada token, isto manda texto."
                        }

                        QQC2.Button {
                            text: root.st.turbo_serving ? "Parar de servir" : "Servir Turbo"
                            enabled: root.busyText === ""
                            onClicked: root.admin("serve", root.st.turbo_serving ? "off" : "on")
                        }
                    }

                    QQC2.Label {
                        visible: root.st.turbo_serving
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.turboBright
                        font.pixelSize: 10
                        text: "O Turbo também não tem autenticação. Quem alcançar a porta "
                              + "11435 usa esta GPU."
                    }
                }
            }

            // ── Onde a IA roda ──────────────────────────────────────────────
            // A escolha que faltava. `serve` decide o que esta máquina OFERECE;
            // isto decide o que ela USA. Automático é um bom padrão e um péssimo
            // comportamento único: quem quer a IA na máquina à frente dele, ou
            // presa numa específica, não está mal configurado.
            FCard {
                Layout.fillWidth: true
                visible: root.available

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    QQC2.Label {
                        text: "Onde a IA roda"
                        color: theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.6)
                        font.pixelSize: 11
                        text: "Escolha qual Turbo os apps DESTA máquina usam. "
                              + "Em uso agora: " + (root.turbo.url || "—")
                    }

                    Repeater {
                        model: root.turbo.options || []

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            QQC2.Label {
                                Layout.preferredWidth: 14
                                color: theme.greenBright
                                text: modelData.effective ? "●" : ""
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: modelData.available ? theme.white
                                                           : theme.a(theme.white, 0.4)
                                font.pixelSize: 11
                                text: (modelData.key === "local" ? "Esta máquina"
                                                                 : modelData.label)
                                      + (modelData.model ? " — " + modelData.model : "")
                                      + (modelData.available ? "" : "  (não está servindo)")
                            }

                            QQC2.Button {
                                text: modelData.selected ? "em uso" : "usar"
                                enabled: root.busyText === "" && !modelData.selected
                                         && modelData.available
                                onClicked: root.admin("use", modelData.key)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 10

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: theme.a(theme.white, 0.6)
                            font.pixelSize: 10
                            text: root.turbo.source === "auto"
                                  ? "Automático: usa o Turbo desta máquina se houver, "
                                    + "senão o de um peer que esteja servindo."
                                  : "Fixado em \"" + root.turbo.source + "\"."
                        }

                        QQC2.Button {
                            visible: root.turbo.source !== "auto"
                            text: "Voltar ao automático"
                            enabled: root.busyText === ""
                            onClicked: root.admin("use", "auto")
                        }
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
                                // Um worker cheio some do pool sem aviso. Marcar
                                // aqui é a diferença entre "o mesh está quebrado"
                                // e "aquela máquina está ocupada agora".
                                readonly property bool noRoom:
                                    modelData.worker && root.knowsFree(modelData)
                                    && root.usableMb(modelData) <= 0
                                color: noRoom ? theme.red : theme.a(theme.white, 0.75)
                                font.pixelSize: 11
                                text: (modelData.backend || "?") + " · "
                                      + root.vramText(modelData)
                                      + (modelData.integrated ? "  [integrada]" : "")
                                      + (modelData.worker ? "" : "  (não compartilha)")
                                      + (noRoom ? "  [sem espaço agora]" : "")
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
