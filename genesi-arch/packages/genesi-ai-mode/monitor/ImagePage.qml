/*
 * Genesi AI Mode Monitor — Image page.
 *
 * Generate a picture from a description, edit one by describing the change,
 * or make one four times larger. All of it local, on the same GPU the chat
 * uses, through stable-diffusion.cpp.
 *
 * A FRONT END ONLY, like the Mesh page: `genesi-ai-image` owns the catalog,
 * the downloads and the engine, and the backend relays its JSON events here.
 * Nothing on this page decides what a model can do -- the catalog's `caps`
 * does -- so the page and the terminal cannot disagree about it.
 *
 * Nothing is installed until the user asks: the engine (genesi-sd-cpp) and
 * every model are a button press away, never a default.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QQD

Item {
    id: root
    property var i18n
    // The chat model the Monitor would use right now; "Improve with AI" asks it.
    property string chatModel: ""

    Theme { id: appTheme }

    function tr(en, pt) { return root.i18n && root.i18n.lang === "pt" ? pt : en }

    // ── state, filled from the backend ──
    property bool toolPresent: true
    property var status: ({})
    property var catalog: []
    property var gallery: []
    readonly property bool engineReady: status.engine_installed === true
    readonly property bool anyModel: catalog.some(function (m) { return m.installed && m.caps.indexOf("generate") >= 0 })
    property string engineState: ""       // terminal | installing | ready | failed

    // download
    property string pullingId: ""
    property real pullFrac: 0
    property string pullText: ""
    property string pullPart: ""          // "2/3": which file of the model
    property string pullError: ""

    // a run
    property bool busy: false
    property string phase: ""
    property int step: 0
    property int steps: 0
    property real secPerStep: 0
    property string runStatus: ""
    property string runError: ""
    property double runStarted: 0
    property int elapsed: 0

    // what is shown in the preview
    property var current: null            // gallery item {path, prompt, seed, mode, ...}

    // the form
    property string mode: "generate"      // generate | edit | upscale
    property string modelId: "flux2-klein"
    property string refPath: ""
    property string refName: ""
    property int refW: 0
    property int refH: 0
    property int aspect: 0
    property bool lockSeed: false
    property int seed: -1
    property int stepsOverride: 0
    property bool pauseTurbo: true
    property bool enhancing: false
    property string enhanceError: ""

    readonly property var aspects: [
        { label: "1:1",  w: 1024, h: 1024 },
        { label: "4:3",  w: 1152, h: 864 },
        { label: "3:4",  w: 864,  h: 1152 },
        { label: "16:9", w: 1344, h: 768 },
        { label: "9:16", w: 768,  h: 1344 }
    ]

    function modelInfo(id) {
        for (var i = 0; i < catalog.length; i++)
            if (catalog[i].id === id) return catalog[i]
        return null
    }
    // Models offered for the current mode, the recommended one first.
    function modelsForMode() {
        var out = catalog.filter(function (m) { return m.caps.indexOf(root.mode) >= 0 })
        out.sort(function (a, b) { return (b.recommended ? 1 : 0) - (a.recommended ? 1 : 0) })
        return out
    }
    function activeModel() {
        if (mode === "upscale") return modelInfo("upscaler")
        var m = modelInfo(modelId)
        if (m && m.caps.indexOf(mode) >= 0) return m
        var list = modelsForMode()
        for (var i = 0; i < list.length; i++) if (list[i].installed) return list[i]
        return list.length ? list[0] : null
    }
    function gb(bytes) { return (bytes / 1e9).toFixed(bytes >= 1e10 ? 0 : 1) + " GB" }
    function fileUrl(p) { return p ? "file://" + p : "" }

    function refresh() {
        backend.loadImageInfo()
        backend.loadImageGallery()
    }

    function phaseText() {
        if (phase === "download") return tr("Downloading", "Baixando")
        if (phase === "load") return tr("Loading the model onto the GPU", "Carregando o modelo na GPU")
        if (phase === "encode") return tr("Reading your prompt", "Lendo o seu prompt")
        if (phase === "sample") return tr("Drawing", "Desenhando")
        if (phase === "decode") return tr("Finishing the picture", "Finalizando a imagem")
        if (phase === "upscale") return tr("Enlarging", "Ampliando")
        return runStatus || tr("Starting", "Iniciando")
    }
    function runFraction() {
        if (phase === "sample" && steps > 0) return 0.15 + 0.75 * (step / steps)
        if (phase === "upscale" && steps > 0) return step / steps
        if (phase === "load" && steps > 0) return 0.10 * (step / steps)
        if (phase === "encode") return 0.12
        if (phase === "decode") return 0.94
        return 0.02
    }

    function canRun() {
        if (busy || !engineReady) return false
        var m = activeModel()
        if (!m || !m.installed) return false
        if (mode !== "generate" && !refPath) return false
        if (mode !== "upscale" && prompt.text.trim().length === 0) return false
        return true
    }

    function run() {
        if (!canRun()) return
        var m = activeModel()
        var a = aspects[aspect]
        var o = { mode: mode, model: m.id, pauseTurbo: pauseTurbo }
        if (mode !== "upscale") {
            o.prompt = prompt.text.trim()
            if (stepsOverride > 0) o.steps = stepsOverride
            if (lockSeed && seed >= 0) o.seed = seed
        }
        if (mode === "generate") { o.width = a.w; o.height = a.h }
        if (mode !== "generate") o.ref = refPath
        runError = ""; runStatus = ""; phase = ""; step = 0; steps = 0; secPerStep = 0
        busy = true
        runStarted = Date.now(); elapsed = 0
        backend.generateImage(JSON.stringify(o))
    }

    function setSource(url) {
        var r = {}
        try { r = JSON.parse(backend.prepareImageInput(url)) } catch (e) { r = { error: "?" } }
        if (r.error) { runError = r.error; return }
        refPath = r.path; refName = r.name; refW = r.width; refH = r.height
        if (mode === "generate") mode = "edit"
    }
    // A picture this page made, handed to Edit or Upscale without a copy.
    function useAsSource(item, newMode) {
        if (!item) return
        refPath = item.path
        refName = item.path.substring(item.path.lastIndexOf("/") + 1)
        refW = item.width || 0; refH = item.height || 0
        mode = newMode
        if (newMode === "edit") prompt.text = ""
    }
    function show(item) {
        current = item
    }
    function reuse(item) {
        if (!item) return
        if (item.prompt) prompt.text = item.prompt
        if (item.seed !== undefined) { seed = item.seed }
    }

    // Every page is built when the Monitor starts, and this one's refresh runs
    // subprocesses (nvidia-smi among them) -- so only when it is looked at.
    Component.onCompleted: if (visible) refresh()
    onVisibleChanged: if (visible) refresh()

    Timer {
        interval: 1000; repeat: true; running: root.busy
        onTriggered: root.elapsed = Math.round((Date.now() - root.runStarted) / 1000)
    }

    Connections {
        target: backend
        function onImageInfo(js) {
            var o = {}
            try { o = JSON.parse(js) } catch (e) {}
            root.toolPresent = o.tool !== false
            root.status = o.status || ({})
            root.catalog = o.catalog || []
        }
        function onImageGallery(js) {
            var arr = []
            try { arr = JSON.parse(js) } catch (e) {}
            root.gallery = arr
            if (!root.current && arr.length) root.current = arr[0]
        }
        function onImagePullEvent(js) {
            var ev = {}
            try { ev = JSON.parse(js) } catch (e) { return }
            if (ev.event === "progress") {
                root.pullFrac = ev.steps ? ev.step / ev.steps : 0
                var what = ev.phase === "verify" ? root.tr("checking ", "conferindo ") : ""
                root.pullText = (root.pullPart ? root.pullPart + "  ·  " : "")
                    + what + ev.file + " — " + Math.round(root.pullFrac * 100) + "%"
                    + (ev.rate ? "  ·  " + (ev.rate / 1e6).toFixed(1) + " MB/s" : "")
            } else if (ev.event === "status") {
                // "file.gguf (2/3)": the bar restarts per file, so say which.
                var m = /\((\d+\/\d+)\)\s*$/.exec(ev.text || "")
                root.pullPart = m ? m[1] : ""
                root.pullText = ev.text
            } else if (ev.event === "error") {
                root.pullError = ev.text
            }
        }
        function onImagePullDone(ok, id, err) {
            root.pullingId = ""
            root.pullPart = ""
            root.pullFrac = 0
            root.pullText = ""
            if (!ok && err !== "cancelled") root.pullError = err
        }
        function onImageEvent(js) {
            var ev = {}
            try { ev = JSON.parse(js) } catch (e) { return }
            if (ev.event === "status") root.runStatus = ev.text
            else if (ev.event === "phase") { root.phase = ev.phase }
            else if (ev.event === "progress") {
                root.phase = ev.phase; root.step = ev.step; root.steps = ev.steps
                if (ev.sec_per_step) root.secPerStep = ev.sec_per_step
            } else if (ev.event === "start") {
                if (ev.seed !== undefined) root.seed = ev.seed
            } else if (ev.event === "done") {
                root.current = { path: ev.path, seed: ev.seed, width: ev.width,
                                 height: ev.height, mode: root.mode,
                                 prompt: root.mode === "upscale" ? "" : prompt.text.trim(),
                                 seconds: ev.seconds }
                if (ev.seed !== undefined) root.seed = ev.seed
            } else if (ev.event === "error") {
                root.runError = ev.text === "cancelled" ? "" : ev.text
            }
        }
        function onImageBusy(b) { root.busy = b }
        function onImagePromptEnhanced(text, err) {
            root.enhancing = false
            root.enhanceError = err
            if (text) prompt.text = text
        }
        function onImageEngineStatus(s) {
            root.engineState = s
            if (s === "ready") root.refresh()
        }
    }

    QQD.FileDialog {
        id: pickDialog
        title: root.tr("Choose a picture", "Escolha uma imagem")
        nameFilters: [root.tr("Images", "Imagens") + " (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: root.setSource(selectedFile.toString())
    }
    QQD.FileDialog {
        id: saveDialog
        title: root.tr("Save picture as", "Salvar imagem como")
        fileMode: QQD.FileDialog.SaveFile
        nameFilters: ["PNG (*.png)"]
        onAccepted: if (root.current) backend.saveImageAs(root.current.path, selectedFile.toString())
    }

    // Drop a picture anywhere on the page: it becomes the one to edit.
    DropArea {
        anchors.fill: parent
        z: 50
        enabled: !root.busy
        onEntered: function (drag) { drag.accepted = drag.hasUrls && drag.urls.length > 0 }
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length > 0) root.setSource(drop.urls[0].toString())
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            visible: parent.containsDrag
            radius: appTheme.rLg
            color: appTheme.a(appTheme.green, 0.10)
            border.width: 2
            border.color: appTheme.a(appTheme.green, 0.55)
            QQC2.Label {
                anchors.centerIn: parent
                text: root.tr("Drop to edit this picture", "Solte para editar esta imagem")
                font.bold: true; font.pixelSize: 16
                color: appTheme.greenBright
            }
        }
    }

    readonly property bool narrow: width < 980

    GridLayout {
        anchors.fill: parent
        anchors.margins: 18
        columns: root.narrow ? 1 : 2
        columnSpacing: 16
        rowSpacing: 14

        // ── header, above both columns ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            spacing: 4
            QQC2.Label {
                text: root.tr("Image", "Imagem")
                color: appTheme.textHi
                font.pixelSize: 24; font.bold: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: appTheme.textMid
                font.pixelSize: 12
                text: root.tr("Create a picture from a description, or change one by saying what to change. Runs on your GPU — nothing leaves this computer.",
                              "Crie uma imagem a partir de uma descrição, ou mude uma dizendo o que mudar. Roda na sua GPU — nada sai deste computador.")
            }
        }

        // ── engine missing: the one thing to do first ──
        // Above both columns, so a narrow window shows it before the form
        // rather than under it. Invisible items take no cell in a GridLayout.
        Rectangle {
            visible: !root.engineReady
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            implicitHeight: engCol.implicitHeight + 36
            radius: appTheme.rLg
            color: appTheme.surface
            border.width: 1; border.color: appTheme.hairline
            ColumnLayout {
                id: engCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 18
                spacing: 10
                QQC2.Label {
                    text: root.tr("Install the image engine", "Instale o motor de imagens")
                    color: appTheme.textHi; font.pixelSize: 16; font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textMid; font.pixelSize: 12
                    text: root.tr("Genesi draws pictures with stable-diffusion.cpp, the same family of engine that runs your chat models. It is a small package (genesi-sd-cpp); the models are downloaded separately, only the ones you pick.",
                                  "O Genesi desenha imagens com o stable-diffusion.cpp, o mesmo tipo de motor que roda seus modelos de chat. É um pacote pequeno (genesi-sd-cpp); os modelos são baixados à parte, só os que você escolher.")
                }
                RowLayout {
                    spacing: 10
                    GButton {
                        theme: appTheme; kind: "filled"; iconSource: "download"
                        enabled: root.engineState !== "terminal" && root.engineState !== "installing"
                        text: root.engineState === "terminal" ? root.tr("Follow the terminal…", "Siga o terminal…")
                            : root.engineState === "installing" ? root.tr("Installing…", "Instalando…")
                            : root.tr("Install", "Instalar")
                        onClicked: backend.installImageEngine()
                    }
                    QQC2.Label {
                        visible: root.engineState === "failed"
                        text: root.tr("Not installed — try: sudo pacman -S genesi-sd-cpp", "Não instalou — tente: sudo pacman -S genesi-sd-cpp")
                        color: appTheme.red; font.pixelSize: 11
                    }
                }
            }
        }

        // ════════════════════════ LEFT: the form ════════════════════════
        QQC2.ScrollView {
            id: formScroll
            Layout.preferredWidth: root.narrow ? -1 : 360
            Layout.fillWidth: root.narrow
            Layout.fillHeight: !root.narrow
            Layout.preferredHeight: root.narrow ? Math.min(form.implicitHeight, root.height * 0.55) : -1
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: form
                width: formScroll.availableWidth
                spacing: 12

                // ── mode ──
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "generate", icon: "star",     en: "Generate", pt: "Gerar" },
                            { id: "edit",     icon: "edit",     en: "Edit",     pt: "Editar" },
                            { id: "upscale",  icon: "maximize", en: "Upscale",  pt: "Ampliar" }
                        ]
                        delegate: GPill {
                            required property var modelData
                            icon: modelData.icon
                            label: root.tr(modelData.en, modelData.pt)
                            active: root.mode === modelData.id
                            onClicked: if (!root.busy) root.mode = modelData.id
                        }
                    }
                }

                // ── model ──
                QQC2.Label {
                    visible: root.mode !== "upscale"
                    text: root.tr("MODEL", "MODELO")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Repeater {
                    model: root.mode === "upscale" ? [] : root.modelsForMode()
                    delegate: Rectangle {
                        id: mrow
                        required property var modelData
                        readonly property bool sel: root.activeModel() && root.activeModel().id === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: mcol.implicitHeight + 18
                        radius: appTheme.rMd
                        color: sel ? appTheme.a(appTheme.green, 0.12) : appTheme.surface
                        border.width: 1
                        border.color: sel ? appTheme.a(appTheme.green, 0.45) : appTheme.hairline
                        ColumnLayout {
                            id: mcol
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 10
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                QQC2.Label {
                                    text: mrow.modelData.name
                                    color: appTheme.textHi; font.bold: true; font.pixelSize: 13
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                QQC2.Label {
                                    visible: mrow.modelData.recommended
                                    text: root.tr("recommended", "recomendado")
                                    color: appTheme.accentText; font.pixelSize: 10
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.i18n && root.i18n.lang === "pt" ? mrow.modelData.summary.pt : mrow.modelData.summary.en
                                color: appTheme.textMid; font.pixelSize: 11
                            }
                            QQC2.Label {
                                text: mrow.modelData.license + "  ·  " + root.gb(mrow.modelData.size)
                                      + (mrow.modelData.installed ? "  ·  " + root.tr("downloaded", "baixado") : "")
                                color: appTheme.textLo; font.pixelSize: 10
                            }
                            // download / progress
                            RowLayout {
                                visible: !mrow.modelData.installed
                                Layout.fillWidth: true
                                spacing: 8
                                GButton {
                                    theme: appTheme
                                    visible: root.pullingId !== mrow.modelData.id
                                    enabled: root.pullingId === ""
                                    kind: "filled"
                                    iconSource: "download"
                                    text: mrow.modelData.partial ? root.tr("Resume download", "Continuar download")
                                                                 : root.tr("Download", "Baixar") + " (" + root.gb(mrow.modelData.size) + ")"
                                    onClicked: {
                                        root.pullError = ""
                                        root.pullingId = mrow.modelData.id
                                        root.modelId = mrow.modelData.id
                                        backend.pullImageModel(mrow.modelData.id)
                                    }
                                }
                                ColumnLayout {
                                    visible: root.pullingId === mrow.modelData.id
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Rectangle {
                                        Layout.fillWidth: true; implicitHeight: 6; radius: 3
                                        color: appTheme.a(appTheme.textHi, 0.08)
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(1, root.pullFrac))
                                            height: parent.height; radius: 3
                                            color: appTheme.green
                                            Behavior on width { NumberAnimation { duration: 300 } }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: root.pullText || root.tr("starting…", "iniciando…")
                                            color: appTheme.textMid; font.pixelSize: 10
                                            elide: Text.ElideMiddle
                                        }
                                        GButton {
                                            theme: appTheme; kind: "ghost"; iconSource: "x"
                                            tooltip: root.tr("Stop (resumes later)", "Parar (continua depois)")
                                            onClicked: backend.cancelImagePull()
                                        }
                                    }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            enabled: mrow.modelData.installed
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.modelId = mrow.modelData.id
                        }
                    }
                }

                // upscaler download (Upscale mode has no picker, one model)
                Rectangle {
                    readonly property var up: root.modelInfo("upscaler")
                    visible: root.mode === "upscale" && up && !up.installed
                    Layout.fillWidth: true
                    implicitHeight: upCol.implicitHeight + 20
                    radius: appTheme.rMd
                    color: appTheme.surface
                    border.width: 1; border.color: appTheme.hairline
                    ColumnLayout {
                        id: upCol
                        anchors.fill: parent; anchors.margins: 10
                        spacing: 6
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.tr("Upscaling needs Real-ESRGAN 4× (67 MB, BSD licence).",
                                          "Ampliar precisa do Real-ESRGAN 4× (67 MB, licença BSD).")
                            color: appTheme.textMid; font.pixelSize: 11
                        }
                        GButton {
                            theme: appTheme; kind: "filled"; iconSource: "download"
                            enabled: root.pullingId === ""
                            text: root.pullingId === "upscaler" ? root.pullText || root.tr("Downloading…", "Baixando…")
                                                                : root.tr("Download", "Baixar")
                            onClicked: { root.pullError = ""; root.pullingId = "upscaler"; backend.pullImageModel("upscaler") }
                        }
                    }
                }

                QQC2.Label {
                    visible: root.pullError !== ""
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.pullError
                    color: appTheme.red; font.pixelSize: 11
                }

                // ── source picture (edit / upscale) ──
                QQC2.Label {
                    visible: root.mode !== "generate"
                    text: root.mode === "edit" ? root.tr("PICTURE TO EDIT", "IMAGEM PARA EDITAR")
                                               : root.tr("PICTURE TO ENLARGE", "IMAGEM PARA AMPLIAR")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Rectangle {
                    visible: root.mode !== "generate"
                    Layout.fillWidth: true
                    implicitHeight: root.refPath ? 92 : 74
                    radius: appTheme.rMd
                    color: srcMa.containsMouse ? appTheme.hover : appTheme.surface
                    border.width: 1
                    border.color: appTheme.hairline
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 10
                        spacing: 10
                        Image {
                            visible: root.refPath !== ""
                            source: root.fileUrl(root.refPath)
                            Layout.preferredWidth: 72; Layout.preferredHeight: 72
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 144; sourceSize.height: 144
                            asynchronous: true
                        }
                        FIcon {
                            visible: root.refPath === ""
                            name: "image"; size: 22; color: appTheme.textLo
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.refPath ? root.refName : root.tr("Choose or drop a picture", "Escolha ou solte uma imagem")
                                color: appTheme.textHi; font.pixelSize: 12; elide: Text.ElideMiddle
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.refPath ? (root.refW && root.refH ? root.refW + " × " + root.refH : "")
                                                   : root.tr("PNG, JPEG, WebP — or use one from the gallery", "PNG, JPEG, WebP — ou use uma da galeria")
                                color: appTheme.textLo; font.pixelSize: 10; elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: srcMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pickDialog.open()
                    }
                }

                // ── prompt ──
                QQC2.Label {
                    visible: root.mode !== "upscale"
                    text: root.mode === "edit" ? root.tr("WHAT TO CHANGE", "O QUE MUDAR")
                                               : root.tr("DESCRIBE THE PICTURE", "DESCREVA A IMAGEM")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Rectangle {
                    visible: root.mode !== "upscale"
                    Layout.fillWidth: true
                    implicitHeight: Math.max(110, prompt.implicitHeight + 16)
                    radius: appTheme.rMd
                    color: appTheme.surface
                    border.width: 1
                    border.color: prompt.activeFocus ? appTheme.a(appTheme.green, 0.55) : appTheme.hairline
                    QQC2.TextArea {
                        id: prompt
                        anchors.fill: parent
                        anchors.margins: 4
                        wrapMode: TextEdit.Wrap
                        color: appTheme.textHi
                        font.pixelSize: 13
                        background: Item {}
                        placeholderText: root.mode === "edit"
                            ? root.tr("e.g. make it night with neon lights, keep the people as they are",
                                      "ex.: deixa de noite com luzes neon, mantém as pessoas como estão")
                            : root.tr("e.g. a red fox in a snowy forest at sunrise, soft light, photo",
                                      "ex.: uma raposa vermelha numa floresta com neve ao amanhecer, luz suave, foto")
                        placeholderTextColor: appTheme.textLo
                        Keys.onPressed: function (ev) {
                            if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)
                                    && (ev.modifiers & Qt.ControlModifier)) {
                                root.run(); ev.accepted = true
                            }
                        }
                    }
                }
                RowLayout {
                    visible: root.mode !== "upscale"
                    Layout.fillWidth: true
                    spacing: 8
                    GButton {
                        theme: appTheme
                        kind: "tonal"
                        iconSource: "zap"
                        enabled: !root.enhancing && prompt.text.trim().length > 0 && root.chatModel !== ""
                        text: root.enhancing ? root.tr("Improving…", "Melhorando…") : root.tr("Improve with AI", "Melhorar com IA")
                        tooltip: root.chatModel
                            ? root.tr("Your chat model rewrites the prompt in English, with the detail image models respond to.",
                                      "Seu modelo de chat reescreve o prompt em inglês, com o detalhe que modelos de imagem entendem.")
                            : root.tr("Needs a chat model — download one in Models.", "Precisa de um modelo de chat — baixe um em Modelos.")
                        onClicked: {
                            root.enhancing = true
                            root.enhanceError = ""
                            backend.enhanceImagePrompt(root.chatModel, prompt.text, root.mode)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                QQC2.Label {
                    visible: root.enhanceError !== ""
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.enhanceError
                    color: appTheme.red; font.pixelSize: 11
                }

                // ── shape (generate only; an edit keeps the source's shape) ──
                QQC2.Label {
                    visible: root.mode === "generate"
                    text: root.tr("SHAPE", "FORMATO")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Flow {
                    visible: root.mode === "generate"
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.aspects
                        delegate: GPill {
                            required property var modelData
                            required property int index
                            label: modelData.label
                            active: root.aspect === index
                            onClicked: root.aspect = index
                        }
                    }
                }

                // ── advanced ──
                QQC2.Label {
                    visible: root.mode !== "upscale"
                    text: (advanced.open ? "▾ " : "▸ ") + root.tr("Advanced", "Avançado")
                    color: appTheme.textMid; font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: advanced.open = !advanced.open
                    }
                }
                ColumnLayout {
                    id: advanced
                    property bool open: false
                    visible: open && root.mode !== "upscale"
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: root.tr("Steps", "Passos")
                            color: appTheme.textMid; font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                        QQC2.SpinBox {
                            from: 0; to: 50
                            value: root.stepsOverride
                            onValueModified: root.stepsOverride = value
                            textFromValue: function (v) { return v === 0 ? root.tr("auto", "auto") : String(v) }
                            valueFromText: function (t) { var n = parseInt(t); return isNaN(n) ? 0 : n }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: root.tr("Keep the same seed", "Manter a mesma seed")
                            color: appTheme.textMid; font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                        GToggle {
                            theme: appTheme
                            checked: root.lockSeed
                            onToggled: function (v) { root.lockSeed = v }
                        }
                    }
                    QQC2.TextField {
                        visible: root.lockSeed
                        Layout.fillWidth: true
                        text: root.seed >= 0 ? String(root.seed) : ""
                        placeholderText: root.tr("seed (a number)", "seed (um número)")
                        validator: IntValidator { bottom: 0; top: 2147483647 }
                        onEditingFinished: root.seed = text === "" ? -1 : parseInt(text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.tr("Pause Turbo while drawing (frees the GPU, much faster)",
                                          "Pausar o Turbo enquanto desenha (libera a GPU, bem mais rápido)")
                            color: appTheme.textMid; font.pixelSize: 12
                        }
                        GToggle {
                            theme: appTheme
                            checked: root.pauseTurbo
                            onToggled: function (v) { root.pauseTurbo = v }
                        }
                    }
                }

                // ── go ──
                GButton {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    theme: appTheme
                    kind: root.busy ? "danger" : "filled"
                    iconSource: root.busy ? "square" : (root.mode === "upscale" ? "maximize" : "star")
                    enabled: root.busy || root.canRun()
                    text: root.busy ? root.tr("Cancel", "Cancelar")
                        : root.mode === "edit" ? root.tr("Apply the change", "Aplicar a mudança")
                        : root.mode === "upscale" ? root.tr("Enlarge 4×", "Ampliar 4×")
                        : root.tr("Generate", "Gerar")
                    tooltip: root.busy ? "" : root.tr("Ctrl+Enter in the prompt", "Ctrl+Enter no prompt")
                    onClicked: root.busy ? backend.cancelImage() : root.run()
                }
                QQC2.Label {
                    visible: !root.busy && !root.canRun() && root.engineReady
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textLo; font.pixelSize: 11
                    text: {
                        var m = root.activeModel()
                        if (!m || !m.installed) return root.tr("Download a model above first.", "Baixe um modelo acima primeiro.")
                        if (root.mode !== "generate" && !root.refPath) return root.tr("Choose a picture first.", "Escolha uma imagem primeiro.")
                        if (root.mode !== "upscale") return root.tr("Write what you want first.", "Escreva o que você quer primeiro.")
                        return ""
                    }
                }
                Item { Layout.preferredHeight: 8 }
            }
        }

        // ════════════════════════ RIGHT: picture + gallery ════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ── the picture ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 260
                radius: appTheme.rLg
                color: appTheme.a(appTheme.black, appTheme.dark ? 0.25 : 0.06)
                border.width: 1; border.color: appTheme.hairline
                clip: true

                Image {
                    id: preview
                    anchors.fill: parent
                    anchors.margins: 12
                    source: root.current ? root.fileUrl(root.current.path) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true; mipmap: true
                    opacity: root.busy ? 0.35 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                // nothing yet
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 420)
                    visible: !root.current && !root.busy
                    spacing: 8
                    FIcon { Layout.alignment: Qt.AlignHCenter; name: "image"; size: 40; color: appTheme.textLo }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: appTheme.textMid; font.pixelSize: 13
                        text: !root.anyModel
                            ? root.tr("Download a model on the left to start. FLUX.2 klein is the one to try first: it generates and edits.",
                                      "Baixe um modelo à esquerda para começar. O FLUX.2 klein é o primeiro a testar: ele gera e edita.")
                            : root.tr("Your pictures appear here, and are saved in Pictures › Genesi AI.",
                                      "Suas imagens aparecem aqui, e ficam salvas em Imagens › Genesi AI.")
                    }
                }

                // progress over the picture
                Rectangle {
                    visible: root.busy
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 380)
                    height: progCol.implicitHeight + 32
                    radius: appTheme.rLg
                    color: appTheme.a(appTheme.card, 0.92)
                    border.width: 1; border.color: appTheme.lineHi
                    ColumnLayout {
                        id: progCol
                        anchors.fill: parent; anchors.margins: 16
                        spacing: 8
                        QQC2.Label {
                            text: root.phaseText()
                            color: appTheme.textHi; font.pixelSize: 14; font.bold: true
                        }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 8; radius: 4
                            color: appTheme.a(appTheme.textHi, 0.08)
                            Rectangle {
                                width: parent.width * root.runFraction()
                                height: parent.height; radius: 4
                                color: appTheme.green
                                Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            color: appTheme.textMid; font.pixelSize: 11
                            text: {
                                var s = root.elapsed + " s"
                                if (root.phase === "sample" && root.steps > 0) {
                                    s = root.tr("step ", "passo ") + root.step + "/" + root.steps + "  ·  " + s
                                    if (root.secPerStep > 0)
                                        s += "  ·  " + root.secPerStep.toFixed(1) + " s/" + root.tr("step", "passo")
                                }
                                return s
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                visible: root.runError !== ""
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: root.runError
                color: appTheme.red; font.pixelSize: 12
            }

            // ── what to do with it ──
            Flow {
                visible: root.current !== null && !root.busy
                Layout.fillWidth: true
                spacing: 8
                GButton {
                    theme: appTheme; iconSource: "edit"
                    visible: root.catalog.some(function (m) { return m.installed && m.caps.indexOf("edit") >= 0 })
                    text: root.tr("Edit this", "Editar esta")
                    onClicked: root.useAsSource(root.current, "edit")
                }
                GButton {
                    theme: appTheme; iconSource: "refresh-cw"
                    visible: root.current && root.current.mode === "generate" && !!root.current.prompt
                    text: root.tr("Variation", "Variação")
                    tooltip: root.tr("Same prompt, new seed", "Mesmo prompt, seed nova")
                    onClicked: {
                        root.reuse(root.current)
                        root.mode = "generate"
                        root.lockSeed = false
                        root.run()
                    }
                }
                GButton {
                    theme: appTheme; iconSource: "maximize"
                    text: root.tr("Enlarge 4×", "Ampliar 4×")
                    onClicked: root.useAsSource(root.current, "upscale")
                }
                GButton {
                    theme: appTheme; iconSource: "copy"
                    text: root.tr("Copy", "Copiar")
                    onClicked: backend.copyImage(root.current.path)
                }
                GButton {
                    theme: appTheme; iconSource: "save"
                    text: root.tr("Save as…", "Salvar como…")
                    onClicked: saveDialog.open()
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "external-link"
                    tooltip: root.tr("Open in the image viewer", "Abrir no visualizador")
                    onClicked: backend.openImageExternally(root.current.path)
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "folder"
                    tooltip: root.tr("Open the folder", "Abrir a pasta")
                    onClicked: backend.openImageFolder()
                }
                GButton {
                    theme: appTheme; kind: "danger"; iconSource: "trash"
                    tooltip: root.tr("Delete", "Excluir")
                    onClicked: {
                        if (backend.deleteImage(root.current.path)) root.current = null
                    }
                }
            }
            QQC2.Label {
                visible: root.current !== null && !root.busy && !!root.current && !!root.current.prompt
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: appTheme.textLo; font.pixelSize: 11
                text: root.current ? (root.current.prompt || "")
                      + (root.current.seed !== undefined ? "   ·   seed " + root.current.seed : "")
                      + (root.current.seconds ? "   ·   " + root.current.seconds + " s" : "") : ""
            }

            // ── gallery ──
            ListView {
                visible: root.gallery.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: root.gallery
                delegate: Rectangle {
                    id: thumb
                    required property var modelData
                    readonly property bool sel: root.current && root.current.path === modelData.path
                    width: 88; height: 88
                    radius: appTheme.rSm
                    color: appTheme.surface
                    border.width: sel ? 2 : 1
                    border.color: sel ? appTheme.green : appTheme.hairline
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: root.fileUrl(thumb.modelData.path)
                        sourceSize.width: 176; sourceSize.height: 176
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: root.show(thumb.modelData)
                        onDoubleClicked: { root.show(thumb.modelData); root.reuse(thumb.modelData) }
                        hoverEnabled: true
                        QQC2.ToolTip.visible: containsMouse && !!thumb.modelData.prompt
                        QQC2.ToolTip.text: thumb.modelData.prompt || ""
                        QQC2.ToolTip.delay: 500
                    }
                }
            }
        }
    }
}
