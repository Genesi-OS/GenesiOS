// GENESI STORE — the page for one thing.
//
// A card can say what something is. This says what it will DO: the big
// preview, where it came from, and -- the part a store usually hides -- the
// exact list of what applying it changes, written from the item's own actions
// rather than from a paragraph somebody remembered to update.
//
// It is also where Revert lives. Not on the card: undoing is a decision, and a
// decision belongs on the page you opened deliberately.
import QtQuick
import QtQuick.Controls as QQC2
import ".."

Item {
    id: root

    property var item: null
    property string thumbDir: ""
    property string busy: ""
    property var resolve: null        // id -> item, for a collection's parts

    // The screenshot, asked for when the sheet opens. The card usually got
    // there first and this is a cache hit, but a sheet can be reached from
    // search without its card ever having been drawn.
    property string shot: ""

    onItemChanged: {
        root.shot = "";
        if (root.item && (root.item.preview ?? ({})).shot) {
            root.shot = store.previewPath(root.item.id);
            store.fetchPreview(root.item.id);
        }
    }

    Connections {
        target: store

        function onPreviewReady(ident, url) {
            if (root.item && ident === root.item.id)
                root.shot = url;
        }
    }

    signal apply
    signal revert
    signal closed
    signal openItem(string ident)

    readonly property bool applied: root.item && root.item.applied === true
    readonly property var parts: {
        const out = [];
        if (!root.item || !root.resolve)
            return out;
        for (const ident of (root.item.includes ?? [])) {
            const part = root.resolve(ident);
            if (part)
                out.push(part);
        }
        return out;
    }

    // What this will change, in plain words, straight off the actions.
    readonly property var changes: {
        const out = [];
        if (!root.item)
            return out;
        for (const action of (root.item.actions ?? [])) {
            if (action.action === "scheme")
                out.push(qsTr("As cores de tudo: barra, janelas, terminal e apps."));
            else if (action.action === "wallpaper")
                out.push(qsTr("O papel de parede."));
            else if (action.action === "bar")
                out.push(qsTr("O arranjo da barra."));
            else if (action.action === "file")
                out.push(qsTr("O arquivo %1 (o anterior é guardado).").arg(action.path));
            else if (action.action === "package")
                out.push(qsTr("Instala %1, que é o que trava a sessão — pede a sua senha.").arg(action.name));
            else if (action.action === "login")
                out.push(qsTr("A tela de login do sistema — pede a sua senha."));
            else if (action.action === "greeter") {
                out.push(qsTr("A tela de login do sistema — pede a sua senha."));
                if (root.item.download)
                    out.push(qsTr("Baixa %1 MB e confere byte a byte antes de instalar.")
                             .arg(Math.round(root.item.download / 1048576)));
                out.push(qsTr("Instala em /usr/share/sddm/themes. Não mexe na sua sessão."));
            }
            else if (action.action === "config")
                out.push(qsTr("Algumas configurações do shell."));
        }
        for (const part of root.parts)
            out.push(qsTr("Inclui: %1").arg(part.name));
        return out;
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.item ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Tokens.normal
        }
    }

    // Anything outside closes it.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.03, 0.02, 0.72)

        TapHandler {
            onTapped: root.closed()
        }
    }

    Rectangle {
        id: sheet

        anchors.centerIn: parent
        width: Math.min(880, parent.width - 80)
        height: Math.min(640, parent.height - 60)
        radius: Tokens.radiusLg
        color: Tokens.bg
        border.width: 1
        border.color: Tokens.line

        // Its own clicks stay in.
        TapHandler {
            gesturePolicy: TapHandler.WithinBounds
        }

        // ── The preview, big ─────────────────────────────────────────────────
        Preview {
            id: art

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height * 0.46
            spec: root.item ? (root.item.preview ?? ({})) : ({})
            thumbDir: root.thumbDir
            // Without this the sheet draws the generic login screen over a
            // theme whose photograph is already in the cache -- the card got
            // it right and the page you open to LOOK at the thing did not.
            shotUrl: root.shot
            detailed: true
        }

        Rectangle {
            anchors.left: art.left
            anchors.right: art.right
            anchors.bottom: art.bottom
            height: 90
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "transparent"
                }
                GradientStop {
                    position: 1
                    color: Tokens.bg
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            width: 32
            height: 32
            radius: 16
            color: Tokens.a(Tokens.bgDeep, 0.7)

            Glyph {
                anchors.centerIn: parent
                name: "close"
                size: 17
                colour: Tokens.textHi
            }
            TapHandler {
                onTapped: root.closed()
            }
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
        }

        // ── What it is, and what it will do ──────────────────────────────────
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: art.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.topMargin: 4

            Column {
                id: head

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 4

                Text {
                    text: (root.item ? (root.item.kindLabel ?? "") : "").toUpperCase()
                    color: Tokens.accentSoft
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    font.letterSpacing: 1.8
                }
                Text {
                    width: parent.width
                    text: root.item ? root.item.name : ""
                    color: Tokens.textHi
                    font.family: Tokens.sans
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.item ? root.item.blurb : ""
                    color: Tokens.text
                    font.family: Tokens.sans
                    font.pixelSize: Tokens.fsBody
                    wrapMode: Text.WordWrap
                }

                // Where it came from. A store that does not say is a store
                // asking to be trusted twice -- and this sits in the header,
                // not at the end of the list, because at the end of the list
                // it was below the fold on every item long enough to matter.
                Text {
                    width: parent.width
                    visible: text !== ""
                    topPadding: 2
                    text: {
                        if (!root.item || !root.item.author)
                            return "";
                        let line = qsTr("Por %1").arg(root.item.author);
                        if (root.item.license)
                            line += "  ·  " + root.item.license;
                        if (root.item.source)
                            line += "  ·  " + root.item.source;
                        return line;
                    }
                    color: Tokens.textFaint
                    font.family: Tokens.sans
                    font.pixelSize: Tokens.fsLabel
                    elide: Text.ElideRight
                }
            }

            QQC2.ScrollView {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: head.bottom
                anchors.topMargin: 16
                anchors.bottom: wayBack.visible ? wayBack.top : actions.top
                anchors.bottomMargin: 14
                contentWidth: availableWidth
                clip: true

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        text: qsTr("O QUE ISSO MUDA")
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.6
                    }

                    Repeater {
                        model: root.changes

                        Row {
                            required property string modelData

                            spacing: 9

                            Leaf {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13
                                height: 13
                                colour: Tokens.a(Tokens.accent, 0.8)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: Tokens.text
                                font.family: Tokens.sans
                                font.pixelSize: Tokens.fsBody
                            }
                        }
                    }

                    // A collection shows its parts as cards you can open.
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: root.parts.length > 0

                        Repeater {
                            model: root.parts

                            Rectangle {
                                required property var modelData

                                width: 168
                                height: 96
                                radius: Tokens.radiusSm
                                color: Tokens.card
                                border.width: 1
                                border.color: Tokens.line
                                clip: true

                                Preview {
                                    anchors.fill: parent
                                    spec: modelData.preview ?? ({})
                                    thumbDir: root.thumbDir
                                    shotUrl: modelData.preview && modelData.preview.shot
                                             ? store.previewPath(modelData.id) : ""
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 30
                                    color: Qt.rgba(0.02, 0.05, 0.03, 0.85)

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData.name
                                        color: Tokens.textHi
                                        font.family: Tokens.sans
                                        font.pixelSize: Tokens.fsLabel
                                        elide: Text.ElideRight
                                    }
                                }

                                TapHandler {
                                    onTapped: root.openItem(modelData.id)
                                }
                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }
                }
            }

            // ── The way back ─────────────────────────────────────────────────
            //
            // A login screen is the only thing in this store that can leave
            // somebody with a machine they cannot get into, and the moment
            // they would need these two lines is the one moment they cannot
            // read them. So they are here, before, on the page where the
            // decision is made.
            //
            // Outside the scrolling column on purpose: in it, on a sheet this
            // size, the command was the part that fell below the fold.
            Rectangle {
                id: wayBack

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: actions.top
                anchors.bottomMargin: 14
                height: visible ? wayOut.implicitHeight + 24 : 0
                visible: !!(root.item && root.item.needs_root)
                radius: Tokens.radiusSm
                color: Tokens.a(Tokens.accent, 0.06)
                border.width: 1
                border.color: Tokens.a(Tokens.accent, 0.22)

                Column {
                    id: wayOut

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 5

                    Text {
                        text: qsTr("SE ELA NÃO ABRIR")
                        color: Tokens.a(Tokens.accent, 0.85)
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.6
                    }
                    Text {
                        width: wayOut.width
                        text: qsTr("Ctrl+Alt+F2 abre um terminal de texto. Entre com o "
                                   + "seu usuário e rode a linha abaixo — ela apaga a "
                                   + "escolha e devolve a tela que veio com o sistema.")
                        color: Tokens.text
                        font.family: Tokens.sans
                        font.pixelSize: Tokens.fsLabel
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: wayOut.width
                        text: "sudo rm /etc/sddm.conf.d/50-genesi-store.conf"
                        color: Tokens.textHi
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsLabel
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            // ── Apply, revert ────────────────────────────────────────────────
            Row {
                id: actions

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 10

                Rectangle {
                    width: 190
                    height: 44
                    radius: Tokens.radiusSm
                    color: root.busy !== "" ? Tokens.a(Tokens.accentSoft, 0.2)
                                            : (applyTap.pressed ? Tokens.accentDeep : Tokens.accent)

                    Row {
                        anchors.centerIn: parent
                        spacing: 9

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.item && root.item.needs_download ? "install" : "play"
                            size: 17
                            colour: Tokens.bgDeep
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.busy !== "")
                                    return root.busy + "…";
                                if (root.item && root.item.needs_download)
                                    return qsTr("Baixar e aplicar");
                                return root.applied ? qsTr("Aplicar de novo") : qsTr("Aplicar");
                            }
                            color: Tokens.bgDeep
                            font.family: Tokens.sans
                            font.pixelSize: Tokens.fsBody
                            font.weight: Font.DemiBold
                        }
                    }

                    TapHandler {
                        id: applyTap

                        onTapped: root.apply()
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Rectangle {
                    visible: root.applied
                    width: 150
                    height: 44
                    radius: Tokens.radiusSm
                    color: "transparent"
                    border.width: 1
                    border.color: Tokens.line

                    Row {
                        anchors.centerIn: parent
                        spacing: 9

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "revert"
                            size: 16
                            colour: Tokens.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Desfazer")
                            color: Tokens.text
                            font.family: Tokens.sans
                            font.pixelSize: Tokens.fsBody
                        }
                    }

                    TapHandler {
                        onTapped: root.revert()
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.closed()
}
