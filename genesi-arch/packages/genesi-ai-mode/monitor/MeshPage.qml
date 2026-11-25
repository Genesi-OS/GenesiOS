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
    property var local_: ({ turbo: null, ollama: [] })
    property bool available: true
    property string busyText: ""
    property string output: ""

    // Reserva por GPU para KV cache/ativações — o MESMO 1.2 GB que o
    // genesi_mesh_common usa. Se divergir, a página diz que cabe um modelo que
    // o planejador vai recusar, e o usuário fica sem entender qual dos dois
    // está mentindo.
    readonly property real overheadMb: 1.2 * 1024

    // Every line on this page was pt-BR only while the rest of the app follows
    // the language switch in the top bar. Same helper as the Image page.
    function tr(en, pt) { return root.i18n && root.i18n.lang === "pt" ? pt : en }

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
        try { local_ = JSON.parse(backend.localInference()) }
        catch (e) { local_ = ({ turbo: null, ollama: [] }) }
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
        return o.free_mb + root.tr(" free of ", " livres de ") + (o.vram_mb || 0) + " MiB"
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
                // Was hardcoded pt-BR while the rest of the app switches
                // language from the top bar, so an English user read this page
                // in Portuguese.
                text: root.i18n ? root.i18n.t("mesh.subtitle")
                                : "Pool the video memory of several machines to run a model that would not fit on any one of them."
            }

            // ── genesi-mesh ausente ──────────────────────────────────────────
            //
            // NOT an error. This was a red box with a red border, which is what
            // the app says when something has gone WRONG — and the only thing
            // that has happened is that an optional package is not installed.
            // Painting "you have not installed this yet" red is how people
            // learn to ignore red. It is an invitation: what it is, why you
            // would want it, and the command, ready to copy.
            Rectangle {
                visible: !root.available
                Layout.fillWidth: true
                implicitHeight: missingCol.implicitHeight + theme.sp5 * 2
                radius: theme.rLg
                color: theme.surface
                border.width: 1
                border.color: theme.hairline

                ColumnLayout {
                    id: missingCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: theme.sp5; anchors.rightMargin: theme.sp5
                    spacing: theme.sp3

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 46; height: 46; radius: theme.rMd
                        color: theme.a(theme.green, 0.12)
                        border.width: 1
                        border.color: theme.a(theme.green, 0.28)
                        FIcon {
                            anchors.centerIn: parent
                            name: "layers"; size: 20; color: theme.greenBright
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.i18n ? root.i18n.t("mesh.missingTitle")
                                        : "Mesh is not installed on this machine"
                        color: theme.textHi
                        font.pixelSize: theme.fsHead
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.i18n ? root.i18n.t("mesh.missingBody")
                                        : "It is an optional package. Install it on every machine you want to pool, then come back here."
                        color: theme.textLo
                        font.pixelSize: theme.fsSmall
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: theme.sp1
                        implicitWidth: cmdRow.implicitWidth + theme.sp4
                        implicitHeight: 38
                        radius: theme.rMd
                        color: theme.a(theme.textHi, 0.05)
                        border.width: 1
                        border.color: theme.hairline
                        RowLayout {
                            id: cmdRow
                            anchors.centerIn: parent
                            spacing: theme.sp3
                            QQC2.Label {
                                text: "sudo pacman -S genesi-mesh"
                                color: theme.textMid
                                font.family: theme.mono
                                font.pixelSize: theme.fsSmall
                            }
                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: theme.rSm
                                color: cpMa.containsMouse ? theme.a(theme.green, 0.18)
                                                          : "transparent"
                                FIcon {
                                    anchors.centerIn: parent
                                    name: "copy"; size: 13
                                    color: cpMa.containsMouse ? theme.accentText : theme.textLo
                                }
                                MouseArea {
                                    id: cpMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.copyToClipboard("sudo pacman -S genesi-mesh")
                                    QQC2.ToolTip.visible: containsMouse
                                    QQC2.ToolTip.text: root.i18n ? root.i18n.t("find.copy") : "Copy path"
                                }
                            }
                        }
                    }
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
                        text: root.usage.pooling ? root.tr("Turbo is using the mesh", "Turbo está usando o mesh")
                                                 : root.tr("Turbo is running locally", "Turbo está rodando local")
                        color: root.usage.pooling ? theme.greenBright : theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    QQC2.Label {
                        visible: !!root.usage.pooling
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.white
                        font.pixelSize: 11
                        text: root.tr("Model layers are on the GPU of: ", "Camadas do modelo estão na GPU de: ")
                              + root.usage.endpoints.join(", ")
                    }

                    QQC2.Label {
                        visible: !!root.usage.pooling
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.55)
                        font.pixelSize: 10
                        // O trade-off precisa aparecer junto do estado, ou o
                        // usuário conclui que o mesh deixou tudo mais lento sem
                        // motivo. Ele deixa mesmo — em troca de rodar.
                        text: root.tr("Activations cross the network on every token, so this trades "
                                      + "speed for being able to run a model that would not fit here.",
                                      "As ativações atravessam a rede a cada token, então "
                                      + "isso troca velocidade pela possibilidade de rodar "
                                      + "um modelo que não caberia aqui.")
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
                              ? root.tr("No other machine is visible, so the mesh had nothing to join.",
                                        "Nenhuma outra máquina visível — o mesh não tinha como entrar.")
                              : root.tr("The model fit on this machine, or no worker had enough free "
                                        + "VRAM. The diagnostics below say which.",
                                        "O modelo coube nesta máquina, ou nenhum worker tinha "
                                        + "VRAM livre suficiente. O diagnóstico abaixo diz qual dos dois.")
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
                        text: root.tr("This machine", "Esta máquina")
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
                            text: root.st.updated ? root.tr("running", "ativo")
                                                 : root.tr("stopped — sudo systemctl enable --now genesi-meshd",
                                                           "parado — sudo systemctl enable --now genesi-meshd")
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
                                  + (root.st.integrated ? root.tr("  (integrated — it is system RAM)", "  (integrada — é RAM do sistema)") : "")
                        }

                        QQC2.Label { text: root.tr("Address", "Endereço"); color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label { text: root.st.addr || "—"; color: theme.white; font.pixelSize: 11 }

                        QQC2.Label { text: "Backend RPC"; color: theme.a(theme.white, 0.55); font.pixelSize: 11 }
                        QQC2.Label {
                            font.pixelSize: 11
                            // !! because `a && a.b` is UNDEFINED, not false,
                            // when `a` is missing -- and QML cannot coerce
                            // undefined to bool: it warns and keeps whatever
                            // the property held before.
                            readonly property bool ok: !!(root.st.capabilities
                                                       && root.st.capabilities.rpc_server
                                                       && root.st.capabilities.rpc_flag)
                            color: ok ? theme.greenBright : theme.red
                            text: ok ? root.tr("available", "disponível")
                                     : root.tr("missing — install genesi-llama-cpp (or -cuda)",
                                               "ausente — instale genesi-llama-cpp (ou -cuda)")
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
                                  ? root.tr("Sharing this GPU on ", "Compartilhando esta GPU em ") + (root.st.rpc_bind || "?")
                                    + ":" + (root.st.rpc_port || "?")
                                  : root.tr("This machine is NOT lending its GPU.", "Esta máquina NÃO está emprestando a GPU.")
                        }

                        QQC2.Button {
                            text: root.st.worker ? root.tr("Stop sharing", "Parar de compartilhar") : root.tr("Share GPU", "Compartilhar GPU")
                            enabled: root.busyText === ""
                            onClicked: root.admin("worker", root.st.worker ? "off" : "on")
                        }
                    }

                    // rpc-server tem ZERO autenticação. Dizer isso onde o botão está,
                    // não numa doc que ninguém abre.
                    QQC2.Label {
                        visible: !!root.st.worker
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.turboBright
                        font.pixelSize: 10
                        text: root.tr("The RPC server has no authentication at all. Only share "
                                      + "on a network you control (home LAN or VPN).",
                                      "O servidor RPC não tem autenticação nenhuma. Só compartilhe "
                                      + "numa rede que você controla (LAN de casa ou VPN).")
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
                                  ? root.tr("Serving Turbo to the network", "Servindo o Turbo para a rede")
                                    + (root.st.turbo_model ? " — " + root.st.turbo_model : "")
                                  : root.tr("This machine is NOT serving Turbo. Prefer this to lending "
                                            + "VRAM when the model fits here: the pool sends layer "
                                            + "activations on every token, this sends text.",
                                            "Esta máquina NÃO está servindo o Turbo. Prefira isto a "
                                            + "emprestar VRAM quando o modelo couber aqui: o pool "
                                            + "manda ativação de camada a cada token, isto manda texto.")
                        }

                        QQC2.Button {
                            text: root.st.turbo_serving ? root.tr("Stop serving", "Parar de servir") : root.tr("Serve Turbo", "Servir Turbo")
                            enabled: root.busyText === ""
                            onClicked: root.admin("serve", root.st.turbo_serving ? "off" : "on")
                        }
                    }

                    QQC2.Label {
                        visible: !!root.st.turbo_serving
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.turboBright
                        font.pixelSize: 10
                        text: root.tr("Turbo has no authentication either. Anyone who can reach port "
                                      + "11435 uses this GPU.",
                                      "O Turbo também não tem autenticação. Quem alcançar a porta "
                                      + "11435 usa esta GPU.")
                    }
                }
            }

            // ── O que está carregado AQUI ───────────────────────────────────
            // Um modelo pode ficar residente por 15 min depois de um chat
            // fechado (keep-alive do Ollama), consumindo RAM e CPU. Isso não
            // aparecia em lugar nenhum: quem descobrisse, descobriria rodando
            // `ollama ps` por desconfiança.
            Rectangle {
                visible: root.available
                         && (root.local_.turbo || (root.local_.ollama || []).length > 0)
                Layout.fillWidth: true
                implicitHeight: loadCol.implicitHeight + 28
                radius: 14
                color: theme.a(theme.turboBright, 0.10)
                border.width: 1
                border.color: theme.a(theme.turboBright, 0.45)

                ColumnLayout {
                    id: loadCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 6

                    QQC2.Label {
                        text: root.tr("Running on this machine now", "Rodando nesta máquina agora")
                        color: theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    QQC2.Label {
                        visible: !!root.local_.turbo
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.white
                        font.pixelSize: 11
                        text: "Genesi Turbo — " + (root.local_.turbo || "")
                    }

                    Repeater {
                        model: root.local_.ollama || []
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: theme.white
                            font.pixelSize: 11
                            text: "Ollama — " + modelData.name + "  ·  "
                                  + modelData.gb + " GB  ·  " + modelData.where
                                  + (modelData.until ? root.tr("  ·  until ", "  ·  até ") + modelData.until : "")
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
                            text: root.tr("Ollama keeps the model loaded for 15 minutes after the "
                                          + "last request, even with the chat closed.",
                                          "O Ollama segura o modelo por 15 minutos depois do "
                                          + "último pedido, mesmo com o chat fechado.")
                        }

                        QQC2.Button {
                            visible: (root.local_.ollama || []).length > 0
                            text: root.tr("Unload", "Descarregar")
                            enabled: root.busyText === ""
                            onClicked: {
                                root.output = backend.stopLocalInference()
                                root.refresh()
                            }
                        }
                    }
                }
            }

            // ── Onde a IA roda ──────────────────────────────────────────────
            // A escolha que faltava. `serve` decide o que esta máquina OFERECE;
            // isto decide o que ela USA. Automático é um bom padrão e um péssimo
            // comportamento único: quem quer a IA na máquina à frente dele, ou
            // presa numa específica, não está mal configurado.
            // Same shape as every other section on this page: a Rectangle whose
            // implicitHeight follows its column. An FCard with `anchors.fill`
            // has NO height of its own -- the layout collapsed to zero while its
            // children kept painting, so this card drew straight on top of
            // "Máquinas".
            Rectangle {
                visible: root.available
                Layout.fillWidth: true
                implicitHeight: turboCol.implicitHeight + 28
                radius: 14
                color: theme.a(theme.white, 0.04)
                border.width: 1
                border.color: theme.a(theme.white, 0.10)

                ColumnLayout {
                    id: turboCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    QQC2.Label {
                        text: root.tr("Where the AI runs", "Onde a IA roda")
                        color: theme.white
                        font.pixelSize: 14
                        font.bold: true
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.6)
                        font.pixelSize: 11
                        text: root.tr("Choose which Turbo the apps on THIS machine use. In use now: ",
                                      "Escolha qual Turbo os apps DESTA máquina usam. Em uso agora: ")
                              + (root.turbo.url || "—")
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
                                text: (modelData.key === "local" ? root.tr("This machine", "Esta máquina")
                                                                 : modelData.label)
                                      + (modelData.model ? " — " + modelData.model : "")
                                      + (modelData.available ? "" : root.tr("  (not serving)", "  (não está servindo)"))
                            }

                            QQC2.Button {
                                text: modelData.selected ? root.tr("in use", "em uso") : root.tr("use", "usar")
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
                                  ? root.tr("Automatic: uses this machine's Turbo if there is one, "
                                            + "otherwise one from a peer that is serving.",
                                            "Automático: usa o Turbo desta máquina se houver, "
                                            + "senão o de um peer que esteja servindo.")
                                  : root.tr("Pinned to \"", "Fixado em \"") + root.turbo.source + "\"."
                        }

                        QQC2.Button {
                            visible: root.turbo.source !== "auto"
                            text: root.tr("Back to automatic", "Voltar ao automático")
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
                        text: root.tr("Machines (", "Máquinas (") + root.peers.length + ")"
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
                                      + (modelData.integrated ? root.tr("  [integrated]", "  [integrada]") : "")
                                      + (modelData.worker ? "" : root.tr("  (not sharing)", "  (não compartilha)"))
                                      + (noRoom ? root.tr("  [no room now]", "  [sem espaço agora]") : "")
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
                        text: root.tr("No other machine found.\n\n"
                                      + "Automatic discovery uses multicast, which does NOT cross a VPN. "
                                      + "If the machines are on different networks (Tailscale/WireGuard), "
                                      + "that is expected: register the other one's address below and the "
                                      + "two will see each other.",
                                      "Nenhuma outra máquina encontrada.\n\n"
                                      + "A descoberta automática usa multicast, que NÃO atravessa VPN. "
                                      + "Se as máquinas estão em redes diferentes (Tailscale/WireGuard), "
                                      + "isso é esperado — registre o endereço da outra abaixo e as duas "
                                      + "passam a se enxergar.")
                    }

                    // Registrar peer por endereço (o caminho que funciona em VPN)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        QQC2.TextField {
                            id: peerAddr
                            Layout.fillWidth: true
                            placeholderText: root.tr("Other machine's IP (e.g. 100.64.1.2)", "IP da outra máquina (ex.: 100.64.1.2)")
                            font.pixelSize: 12
                        }
                        QQC2.Button {
                            text: root.tr("Register machine", "Registrar máquina")
                            enabled: peerAddr.text.trim() !== "" && root.busyText === ""
                            onClicked: { root.admin("peer", peerAddr.text.trim()); peerAddr.text = "" }
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.45)
                        font.pixelSize: 10
                        text: root.tr("Do this on BOTH machines.", "Faça isso nas DUAS máquinas.")
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
                        text: root.tr("Trusted network", "Rede confiável")
                        color: theme.white; font.pixelSize: 14; font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: theme.a(theme.white, 0.65)
                        font.pixelSize: 11
                        text: root.tr("All machines share ONE secret: it is how they recognise each "
                                      + "other. Create it on the first one and paste it on the rest. "
                                      + "It only authenticates discovery.",
                                      "Todas as máquinas compartilham UM segredo — é ele que faz "
                                      + "uma reconhecer a outra. Crie na primeira, e cole nas demais. "
                                      + "Ele autentica só a descoberta.")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        QQC2.Button {
                            text: root.tr("Create mesh here", "Criar mesh aqui")
                            enabled: root.busyText === ""
                            onClicked: root.admin("init", "")
                        }
                        QQC2.Button {
                            text: root.tr("Show secret", "Ver segredo")
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
                            placeholderText: root.tr("paste the first machine's secret here", "cole aqui o segredo da primeira máquina")
                            font.pixelSize: 12
                        }
                        QQC2.Button {
                            text: root.tr("Join", "Entrar")
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
                    text: root.tr("Diagnostics", "Diagnóstico")
                    onClicked: root.output = backend.meshDoctor()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
