/*
 * Genesi AI Mode Monitor — Image page.
 *
 * Generate a picture from a description, edit one (by instruction, or by
 * redrawing it with any generation model), or make one four times larger.
 * All of it local, on the same GPU the chat uses, through stable-diffusion.cpp.
 *
 * A FRONT END ONLY, like the Mesh page: `genesi-ai-image` owns the catalog,
 * the downloads, the engine and the warm server, and the backend relays its
 * JSON events here. Nothing on this page decides what a model can do -- the
 * catalog's `caps` does -- so the page and the terminal cannot disagree.
 *
 * Nothing is installed until the user asks: the engine and every model are a
 * button press away, never a default.
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
    function loc(o) { return o ? (root.i18n && root.i18n.lang === "pt" ? o.pt : o.en) : "" }

    // ── state, filled from the backend ──
    property bool toolPresent: true
    property var status: ({})
    property var catalog: []
    property var gallery: []
    readonly property bool engineReady: status.engine_installed === true
    readonly property string backendName: status.backend || ""
    readonly property bool warmRunning: !!(status.warm && status.warm.running)
    property string engineState: ""       // terminal | installing | ready | failed

    // download / remove / import / optimize
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
    property string runErrorCode: ""
    property bool runTurbo: false
    property double runStarted: 0
    property int elapsed: 0
    property string logText: ""
    property bool showLog: false

    property var current: null            // gallery item shown in the preview

    // the form
    property string mode: "generate"      // generate | edit | upscale
    property string modelId: ""
    property var variantPick: ({})        // model id -> variant id the user chose
    property string refPath: ""
    property string refName: ""
    property int refW: 0
    property int refH: 0
    property int aspect: 0
    property bool lockSeed: false
    property int seed: -1
    property int stepsOverride: 0
    property real strength: 0.6
    property string negative: ""
    property bool turbo: true
    property bool pauseTurbo: true
    property bool enhancing: false
    property string enhanceError: ""

    // "only this part": a mask painted on the picture being edited. Strokes
    // are kept in 0..1 picture coordinates, so resizing the window does not
    // move what was painted.
    property bool maskOn: false
    property var strokes: []              // [{erase, size, pts: [[x, y], ...]}]
    property real brushSize: 0.07         // of the picture's short side
    property bool eraseMode: false
    property bool maskInvert: false
    property bool protectFaces: false

    // LoRAs the user imported (Generate only)
    property var loras: []
    property var loraPick: ({})           // lora id -> weight, for the ones switched on
    property bool loraGuideOpen: false
    property string loraTrigger: ""
    property string loraMsg: ""
    property bool loraBusy: false

    // the model browser
    property bool browserOpen: false
    property string filterTag: "all"

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
    function has(arr, x) { return arr && arr.indexOf(x) >= 0 }
    // Which models a mode offers. Edit takes both kinds of editor: the ones
    // that follow an instruction, and every generation model that can redraw
    // a picture (img2img) -- the uncensored ones among them.
    function fitsMode(m, md) {
        if (md === "upscale") return has(m.caps, "upscale")
        if (md === "edit") return has(m.caps, "edit") || has(m.caps, "img2img")
        return has(m.caps, "generate")
    }
    function modelsForMode(md) {
        return catalog.filter(function (m) { return fitsMode(m, md) })
    }
    function activeModel() {
        var m = modelInfo(modelId)
        if (m && fitsMode(m, mode) && m.installed) return m
        var list = modelsForMode(mode)
        var installed = list.filter(function (x) { return x.installed })
        if (installed.length) {
            // An instruction editor first in Edit: it is what "edit" means to
            // most people; img2img is the fallback.
            if (mode === "edit") {
                var instr = installed.filter(function (x) { return has(x.caps, "edit") })
                if (instr.length) return instr[0]
            }
            return installed[0]
        }
        return m && fitsMode(m, mode) ? m : null
    }
    function editKind(m) { return m && has(m.caps, "edit") ? "edit" : "img2img" }
    function variantOf(m) {
        if (!m) return null
        var want = variantPick[m.id] || m.active_variant
        for (var i = 0; i < m.variants.length; i++)
            if (m.variants[i].id === want) return m.variants[i]
        return m.variants[0]
    }
    function installedVariant(m) {
        if (!m) return null
        var v = variantOf(m)
        if (v && v.installed) return v
        for (var i = 0; i < m.variants.length; i++)
            if (m.variants[i].installed) return m.variants[i]
        return null
    }
    function gb(bytes) {
        if (bytes < 1e9) return Math.max(1, Math.round(bytes / 1e6)) + " MB"
        return (bytes / 1e9).toFixed(bytes >= 1e10 ? 0 : 1) + " GB"
    }
    function fileUrl(p) { return p ? "file://" + p : "" }
    function vramBytes() { return (status.vram_mb || 0) * 1048576 }
    function ramGb() { return Math.round((status.ram_mb || 0) / 1024) }
    function fitsGpu(m) {
        var v = variantOf(m)
        return v && vramBytes() > 0 && v.gpu_size <= vramBytes() - 1536 * 1048576
    }
    function tagLabel(t) {
        return ({
            "unfiltered": tr("Unfiltered", "Sem filtro"), "fast": tr("Fast", "Rápido"),
            "heavy": tr("Heavy", "Pesado"), "photo": tr("Photo", "Foto"),
            "anime": "Anime", "text": tr("Text", "Texto"), "edit": tr("Edits", "Edita"),
            "noncommercial": tr("Non-commercial", "Não-comercial"),
            "custom": tr("Yours", "Seu"), "sdxl": "SDXL", "sd15": "SD 1.5"
        })[t] || t
    }
    function tagColor(t) {
        if (t === "unfiltered") return appTheme.red
        if (t === "fast") return appTheme.greenBright
        if (t === "heavy" || t === "noncommercial") return appTheme.turboBright
        if (t === "custom") return appTheme.purpleBright
        return appTheme.textMid
    }
    function browserModels() {
        return catalog.filter(function (m) {
            if (has(m.caps, "upscale") && filterTag !== "all" && filterTag !== "installed") return false
            if (filterTag === "all") return true
            if (filterTag === "installed") return m.installed || m.partial
            if (filterTag === "fits") return fitsGpu(m)
            if (filterTag === "editors") return has(m.caps, "edit") || has(m.caps, "img2img")
            return has(m.tags, filterTag)
        })
    }
    function turboText(m) {
        if (!m) return ""
        var parts = [tr("model stays loaded between pictures", "o modelo fica carregado entre uma imagem e outra")]
        if (m.turbo && m.turbo.kind === "lora")
            parts.push(tr("Lightning: " + (m.turbo.steps || 4) + " steps instead of " + m.defaults.steps,
                          "Lightning: " + (m.turbo.steps || 4) + " passos em vez de " + m.defaults.steps))
        else if (m.turbo && m.turbo.kind === "cache")
            parts.push(tr("step cache", "cache de passos"))
        if (backendName === "cuda")
            parts.push("CUDA + SageAttention")
        return parts.join(" · ")
    }

    function refresh() {
        backend.loadImageInfo()
        backend.loadImageGallery()
        backend.loadImageLoras()
    }

    // ── editors, ranked by how well they keep the original ──
    function instructionEditors() {
        var out = catalog.filter(function (m) { return has(m.caps, "edit") })
        out.sort(function (a, b) { return (b.identity || 0) - (a.identity || 0) })
        return out
    }
    function redrawEditors() {
        return catalog.filter(function (m) { return !has(m.caps, "edit") && has(m.caps, "img2img") })
    }
    function identityText(n) {
        if (n >= 3) return tr("Best at keeping faces and details", "O melhor pra manter rostos e detalhes")
        if (n === 2) return tr("Good balance of fidelity and speed", "Bom equilíbrio entre fidelidade e velocidade")
        return tr("Lightest — faces can drift", "O mais leve — rostos podem mudar")
    }
    function stars(n) { return "★★★".substring(0, n) + "☆☆☆".substring(0, 3 - n) }

    // ── LoRAs ──
    function compatibleLoras(m) {
        if (!m || !m.lora_families) return []
        return loras.filter(function (l) { return l.present !== false && has(m.lora_families, l.family) })
    }
    function setLora(id, on, weight) {
        var o = {}
        for (var k in loraPick) o[k] = loraPick[k]
        if (on) o[id] = weight === undefined ? (o[id] || 0.8) : weight
        else delete o[id]
        loraPick = o
    }
    function familyLabel(f) {
        return ({ "sdxl": "SDXL / Pony / Illustrious", "sd15": "SD 1.5", "flux": "FLUX",
                  "qwen": "Qwen-Image", "zimage": "Z-Image" })[f] || tr("unknown base", "base desconhecida")
    }

    function phaseText() {
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
        if (!m || !installedVariant(m)) return false
        if (mode !== "generate" && !refPath) return false
        if (mode !== "upscale" && prompt.text.trim().length === 0) return false
        return true
    }

    function run() {
        if (!canRun()) return
        var m = activeModel()
        var v = installedVariant(m)
        var a = aspects[aspect]
        var o = { model: m.id, variant: v.id, pauseTurbo: pauseTurbo, turbo: turbo }
        if (mode === "edit")
            o.protectFaces = protectFaces && !!status.faces_available
        if (mode === "generate") {
            var picked = []
            var ok = compatibleLoras(m)
            for (var i = 0; i < ok.length; i++)
                if (loraPick[ok[i].id] !== undefined)
                    picked.push({ id: ok[i].id, weight: loraPick[ok[i].id] })
            o.loras = picked
        }
        if (mode === "upscale") {
            o.mode = "upscale"
        } else {
            o.mode = mode === "edit" ? editKind(m) : "generate"
            o.prompt = prompt.text.trim()
            if (stepsOverride > 0) o.steps = stepsOverride
            if (lockSeed && seed >= 0) o.seed = seed
            if (negative.trim().length) o.negative = negative.trim()
            if (o.mode === "img2img") o.strength = strength
        }
        if (mode === "generate") { o.width = a.w; o.height = a.h }
        if (mode !== "generate") o.ref = refPath
        runError = ""; runErrorCode = ""; runStatus = ""; phase = ""; step = 0; steps = 0
        secPerStep = 0; showLog = false; logText = ""
        busy = true
        runStarted = Date.now(); elapsed = 0
        backend.setImagePrefs(JSON.stringify({ model: m.id, mode: mode }))
        // A painted area becomes the mask file, drawn at the picture's own size.
        if (mode === "edit" && maskOn && strokes.length > 0) {
            o.mask = backend.writeImageMask(JSON.stringify(strokes), refPath, maskInvert)
            if (!o.mask) {
                busy = false
                runError = tr("Could not save the painted area.", "Não deu pra salvar a área pintada.")
                return
            }
        }
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
    function reuse(item) {
        if (!item) return
        if (item.prompt) prompt.text = item.prompt
        if (item.seed !== undefined) seed = item.seed
    }
    function pickVariant(m, vid) {
        var o = {}
        for (var k in variantPick) o[k] = variantPick[k]
        o[m.id] = vid
        variantPick = o
    }
    function startPull(m) {
        pullError = ""
        pullingId = m.id
        var v = variantOf(m)
        backend.pullImageModel(m.id, v ? v.id : "")
    }

    onRefPathChanged: { strokes = []; maskInvert = false }

    Component.onCompleted: {
        try {
            var p = JSON.parse(backend.imagePrefs())
            turbo = p.turbo !== false
            if (p.model) modelId = p.model
        } catch (e) {}
        // Every page is built when the Monitor starts, and refreshing runs
        // subprocesses (nvidia-smi among them) -- only when it is looked at.
        if (visible) refresh()
    }
    onVisibleChanged: if (visible) refresh()
    onTurboChanged: backend.setImagePrefs(JSON.stringify({ turbo: turbo }))

    Timer {
        interval: 1000; repeat: true; running: root.busy
        onTriggered: root.elapsed = Math.round((Date.now() - root.runStarted) / 1000)
    }
    // The warm engine stops itself when idle; keep its chip honest.
    Timer {
        interval: 15000; repeat: true; running: root.visible && root.warmRunning && !root.busy
        onTriggered: backend.loadImageInfo()
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
                var what = ev.phase === "verify" ? root.tr("checking ", "conferindo ")
                         : ev.phase === "convert" ? root.tr("optimizing ", "otimizando ") : ""
                root.pullText = (root.pullPart ? root.pullPart + "  ·  " : "")
                    + what + (ev.file || "") + " — " + Math.round(root.pullFrac * 100) + "%"
                    + (ev.rate ? "  ·  " + (ev.rate / 1e6).toFixed(1) + " MB/s" : "")
            } else if (ev.event === "status") {
                // "file.gguf (2/3)": the bar restarts per file, so say which.
                var mm = /\((\d+\/\d+)\)\s*$/.exec(ev.text || "")
                root.pullPart = mm ? mm[1] : root.pullPart
                root.pullText = ev.text
            } else if (ev.event === "phase" && ev.phase === "convert") {
                root.pullFrac = 0
                root.pullText = root.tr("optimizing for your GPU (Q8)…", "otimizando pra sua GPU (Q8)…")
            } else if (ev.event === "error") {
                root.pullError = ev.text
            }
        }
        function onImagePullDone(ok, id, err) {
            if (id === "lora") {
                root.loraBusy = false
                root.loraMsg = ok ? root.tr("LoRA added.", "LoRA adicionada.") : err
                root.loraTrigger = ""
                return
            }
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
                root.runTurbo = !!ev.turbo
            } else if (ev.event === "done") {
                root.current = { path: ev.path, seed: ev.seed, width: ev.width,
                                 height: ev.height, mode: root.mode,
                                 prompt: root.mode === "upscale" ? "" : prompt.text.trim(),
                                 seconds: ev.seconds }
                if (ev.seed !== undefined) root.seed = ev.seed
                if (ev.low_memory)
                    root.runStatus = root.tr("Made in low-memory mode (smaller size).",
                                             "Feita no modo econômico (tamanho menor).")
            } else if (ev.event === "error") {
                root.runError = ev.text === "cancelled" ? "" : ev.text
                root.runErrorCode = ev.code || ""
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
        function onImageLoras(js) {
            var arr = []
            try { arr = JSON.parse(js) } catch (e) {}
            root.loras = arr
            root.loraBusy = false
        }
    }

    QQD.FileDialog {
        id: pickDialog
        title: root.tr("Choose a picture", "Escolha uma imagem")
        nameFilters: [root.tr("Images", "Imagens") + " (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: root.setSource(selectedFile.toString())
    }
    QQD.FileDialog {
        id: loraDialog
        title: root.tr("Choose a LoRA (.safetensors)", "Escolha uma LoRA (.safetensors)")
        nameFilters: ["LoRA (*.safetensors)"]
        onAccepted: {
            root.loraBusy = true
            root.loraMsg = root.tr("Adding…", "Adicionando…")
            backend.importImageLora(selectedFile.toString(), "", root.loraTrigger)
        }
    }
    QQD.FileDialog {
        id: saveDialog
        title: root.tr("Save picture as", "Salvar imagem como")
        fileMode: QQD.FileDialog.SaveFile
        nameFilters: ["PNG (*.png)"]
        onAccepted: if (root.current) backend.saveImageAs(root.current.path, selectedFile.toString())
    }
    QQD.FileDialog {
        id: importDialog
        title: root.tr("Add a checkpoint", "Adicionar um checkpoint")
        nameFilters: [root.tr("Checkpoints", "Checkpoints") + " (*.safetensors *.gguf)"]
        onAccepted: { root.pullError = ""; root.pullingId = "import"; backend.importImageModel(selectedFile.toString()) }
    }

    // Drop a picture anywhere on the page: it becomes the one to edit.
    DropArea {
        anchors.fill: parent
        z: 50
        enabled: !root.busy && !root.browserOpen
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

    // A small rounded tag. Self-contained on purpose: an inline component
    // does not see the ids of the file it is declared in, so `appTheme` here
    // would be a ReferenceError at run time, not at load.
    component Chip: Rectangle {
        property string text: ""
        property color tint: "#9aa4b2"
        implicitHeight: 18
        implicitWidth: chipLabel.implicitWidth + 12
        radius: 9
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.14)
        border.width: 1
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.35)
        QQC2.Label {
            id: chipLabel
            anchors.centerIn: parent
            text: parent.text
            color: parent.tint
            font.pixelSize: 9; font.bold: true
        }
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: 18
        columns: root.narrow ? 1 : 2
        columnSpacing: 16
        rowSpacing: 12

        // ── header, above both columns ──
        RowLayout {
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
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
            Chip {
                visible: root.engineReady && root.backendName !== ""
                text: root.tr("Engine: ", "Motor: ") + (root.backendName === "cuda" ? "CUDA"
                      : root.backendName === "vulkan" ? "Vulkan" : "CPU")
                tint: root.backendName === "cuda" ? appTheme.greenBright : appTheme.textMid
            }
            // The warm engine holds VRAM: say so, and offer it back.
            Rectangle {
                visible: root.warmRunning
                implicitHeight: 30
                implicitWidth: warmRow.implicitWidth + 16
                radius: 15
                color: appTheme.a(appTheme.turbo, 0.12)
                border.width: 1; border.color: appTheme.a(appTheme.turbo, 0.4)
                RowLayout {
                    id: warmRow
                    anchors.centerIn: parent
                    spacing: 8
                    FIcon { name: "zap"; size: 13; color: appTheme.turboBright }
                    QQC2.Label {
                        text: {
                            var m = root.modelInfo(root.status.warm ? root.status.warm.model : "")
                            return root.tr("Loaded: ", "Carregado: ") + (m ? m.name : "")
                        }
                        color: appTheme.textHi; font.pixelSize: 11
                    }
                    QQC2.Label {
                        text: root.tr("Free the GPU", "Liberar GPU")
                        color: appTheme.turboBright; font.pixelSize: 11; font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: backend.stopImageServer()
                        }
                    }
                }
            }
        }

        // ── engine missing: the one thing to do first ──
        Rectangle {
            visible: !root.engineReady
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            implicitHeight: engCol.implicitHeight + 32
            radius: appTheme.rLg
            color: appTheme.surface
            border.width: 1; border.color: appTheme.hairline
            ColumnLayout {
                id: engCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 16
                spacing: 8
                QQC2.Label {
                    text: root.tr("Install the image engine", "Instale o motor de imagens")
                    color: appTheme.textHi; font.pixelSize: 16; font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textMid; font.pixelSize: 12
                    text: root.status.nvidia
                        ? root.tr("You have an NVIDIA card: the CUDA engine is the fast one. The Vulkan engine works on any GPU.",
                                  "Você tem placa NVIDIA: o motor CUDA é o rápido. O motor Vulkan funciona em qualquer GPU.")
                        : root.tr("stable-diffusion.cpp, the same family of engine that runs your chat models. Models are downloaded separately, only the ones you pick.",
                                  "stable-diffusion.cpp, o mesmo tipo de motor que roda seus modelos de chat. Os modelos são baixados à parte, só os que você escolher.")
                }
                RowLayout {
                    spacing: 10
                    GButton {
                        theme: appTheme; kind: "filled"; iconSource: "download"
                        enabled: root.engineState !== "terminal" && root.engineState !== "installing"
                        text: root.engineState === "terminal" ? root.tr("Follow the terminal…", "Siga o terminal…")
                            : root.engineState === "installing" ? root.tr("Installing…", "Instalando…")
                            : root.status.nvidia ? root.tr("Install (CUDA)", "Instalar (CUDA)")
                            : root.tr("Install", "Instalar")
                        onClicked: backend.installImageEngine(root.status.nvidia ? "cuda" : "vulkan")
                    }
                    GButton {
                        theme: appTheme; kind: "ghost"
                        visible: !!root.status.nvidia
                        enabled: root.engineState !== "terminal" && root.engineState !== "installing"
                        text: root.tr("Vulkan instead", "Usar Vulkan")
                        onClicked: backend.installImageEngine("vulkan")
                    }
                    QQC2.Label {
                        visible: root.engineState === "failed"
                        text: root.tr("Not installed — see the terminal for the reason.", "Não instalou — veja o motivo no terminal.")
                        color: appTheme.red; font.pixelSize: 11
                    }
                }
            }
        }

        // ── NVIDIA on the Vulkan engine: the faster one is a click away ──
        Rectangle {
            visible: root.engineReady && !!root.status.nvidia && root.backendName !== "cuda"
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            implicitHeight: cudaRow.implicitHeight + 18
            radius: appTheme.rMd
            color: appTheme.a(appTheme.turbo, 0.08)
            border.width: 1; border.color: appTheme.a(appTheme.turbo, 0.3)
            RowLayout {
                id: cudaRow
                anchors.fill: parent; anchors.margins: 9
                spacing: 10
                FIcon { name: "zap"; size: 16; color: appTheme.turboBright }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textHi; font.pixelSize: 12
                    text: root.tr("Your NVIDIA card is running the Vulkan engine. The CUDA engine is faster and unlocks flash attention + SageAttention in Turbo.",
                                  "Sua placa NVIDIA está no motor Vulkan. O motor CUDA é mais rápido e libera flash attention + SageAttention no Turbo.")
                }
                GButton {
                    theme: appTheme; kind: "filled"; accent: appTheme.turbo
                    enabled: root.engineState !== "terminal" && root.engineState !== "installing"
                    text: root.engineState === "terminal" ? root.tr("Follow the terminal…", "Siga o terminal…")
                        : root.tr("Switch to CUDA", "Trocar pra CUDA")
                    onClicked: backend.installImageEngine("cuda")
                }
            }
        }

        // ════════════════════════ LEFT: the form ════════════════════════
        QQC2.ScrollView {
            id: formScroll
            Layout.preferredWidth: root.narrow ? -1 : 370
            Layout.fillWidth: root.narrow
            Layout.fillHeight: !root.narrow
            Layout.preferredHeight: root.narrow ? Math.min(form.implicitHeight, root.height * 0.55) : -1
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: form
                width: formScroll.availableWidth
                spacing: 11

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
                    text: root.tr("MODEL", "MODELO")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Rectangle {
                    id: modelCard
                    readonly property var m: root.activeModel()
                    readonly property var v: root.installedVariant(m)
                    visible: root.mode !== "edit"
                    Layout.fillWidth: true
                    implicitHeight: mcCol.implicitHeight + 20
                    radius: appTheme.rMd
                    color: m && v ? appTheme.a(appTheme.green, 0.10) : appTheme.surface
                    border.width: 1
                    border.color: m && v ? appTheme.a(appTheme.green, 0.40) : appTheme.hairline
                    ColumnLayout {
                        id: mcCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelCard.m && modelCard.v ? modelCard.m.name
                                    : root.tr("No model for this yet", "Nenhum modelo pra isso ainda")
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 13
                            }
                            GButton {
                                theme: appTheme
                                kind: modelCard.m && modelCard.v ? "ghost" : "filled"
                                iconSource: "layout-grid"
                                text: modelCard.m && modelCard.v ? root.tr("Change", "Trocar")
                                                               : root.tr("Choose a model", "Escolher modelo")
                                onClicked: {
                                    root.filterTag = root.mode === "edit" ? "editors" : "all"
                                    root.browserOpen = true
                                }
                            }
                        }
                        Flow {
                            visible: !!(modelCard.m && modelCard.v)
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: modelCard.m && modelCard.v ? modelCard.m.tags.filter(function (t) { return t !== "sdxl" }) : []
                                delegate: Chip {
                                    required property var modelData
                                    text: root.tagLabel(modelData)
                                    tint: root.tagColor(modelData)
                                }
                            }
                            Chip {
                                visible: !!modelCard.v
                                text: modelCard.v ? root.loc(modelCard.v.label) : ""
                                tint: appTheme.textLo
                            }
                        }
                        QQC2.Label {
                            visible: root.mode === "edit" && !!modelCard.m && !!modelCard.v
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textLo; font.pixelSize: 11
                            text: root.editKind(modelCard.m) === "edit"
                                ? root.tr("Edits by instruction: say what to change.", "Edita por instrução: diga o que mudar.")
                                : root.tr("Redraws your picture in the direction you describe — use the slider for how much.",
                                          "Redesenha sua imagem na direção que você descrever — o controle diz o quanto.")
                        }
                    }
                }

                // ── Edit: which editor -- the ones that KEEP the photo first ──
                ColumnLayout {
                    visible: root.mode === "edit"
                    Layout.fillWidth: true
                    spacing: 6
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        color: appTheme.textMid; font.pixelSize: 11
                        text: root.tr("Editors that keep the photo change only what you ask. The ones further down redraw the whole picture.",
                                      "Os editores que mantêm a foto mudam só o que você pede. Os de baixo redesenham a imagem inteira.")
                    }
                    Repeater {
                        model: root.instructionEditors()
                        delegate: Rectangle {
                            id: ed
                            required property var modelData
                            readonly property bool sel: root.activeModel() && root.activeModel().id === modelData.id
                            readonly property var v: root.variantOf(modelData)
                            readonly property bool ramShort: modelData.min_ram_gb > 0 && root.ramGb() > 0
                                                             && root.ramGb() < modelData.min_ram_gb
                            Layout.fillWidth: true
                            implicitHeight: edCol.implicitHeight + 16
                            radius: appTheme.rMd
                            color: sel ? appTheme.a(appTheme.green, 0.12) : appTheme.surface
                            border.width: 1
                            border.color: sel ? appTheme.a(appTheme.green, 0.5) : appTheme.hairline
                            ColumnLayout {
                                id: edCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 9
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.Label {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: ed.modelData.name
                                        color: appTheme.textHi; font.bold: true; font.pixelSize: 12
                                    }
                                    QQC2.Label {
                                        text: root.stars(ed.modelData.identity || 1)
                                        color: appTheme.turboBright; font.pixelSize: 12
                                    }
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    text: root.identityText(ed.modelData.identity || 1)
                                          + (ed.ramShort ? "  ·  " + root.tr("needs " + ed.modelData.min_ram_gb + " GB of RAM",
                                                                               "precisa de " + ed.modelData.min_ram_gb + " GB de RAM") : "")
                                    color: ed.ramShort ? appTheme.turboBright : appTheme.textMid; font.pixelSize: 10
                                }
                                RowLayout {
                                    visible: !ed.modelData.installed
                                    spacing: 6
                                    GButton {
                                        theme: appTheme; kind: "tonal"; iconSource: "download"
                                        enabled: root.pullingId === "" && root.engineReady
                                        text: root.pullingId === ed.modelData.id
                                              ? (root.pullText || root.tr("Downloading…", "Baixando…"))
                                              : root.tr("Download", "Baixar") + (ed.v ? " · " + root.gb(ed.v.download || ed.v.size) : "")
                                        onClicked: root.startPull(ed.modelData)
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                enabled: ed.modelData.installed
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.modelId = ed.modelData.id
                            }
                        }
                    }
                    // Redraw editors: present, but below and plainly labeled.
                    QQC2.Label {
                        readonly property var installedRedraw: root.redrawEditors().filter(function (x) { return x.installed })
                        visible: installedRedraw.length > 0
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        Layout.topMargin: 4
                        text: (redrawBox.open ? "▾ " : "▸ ") + root.tr("Redraw instead (style, variations — faces change)",
                                                                         "Redesenhar (estilo, variações — rostos mudam)")
                              + " (" + installedRedraw.length + ")"
                        color: appTheme.textLo; font.pixelSize: 11
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: redrawBox.open = !redrawBox.open }
                    }
                    Flow {
                        id: redrawBox
                        property bool open: false
                        visible: open
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.redrawEditors().filter(function (x) { return x.installed })
                            delegate: GPill {
                                required property var modelData
                                label: modelData.name
                                active: root.activeModel() && root.activeModel().id === modelData.id
                                onClicked: root.modelId = modelData.id
                            }
                        }
                    }
                    Rectangle {
                        visible: root.editKind(root.activeModel()) === "img2img" && !!root.activeModel()
                        Layout.fillWidth: true
                        implicitHeight: redrawWarn.implicitHeight + 14
                        radius: appTheme.rSm
                        color: appTheme.a(appTheme.turbo, 0.10)
                        border.width: 1; border.color: appTheme.a(appTheme.turbo, 0.35)
                        QQC2.Label {
                            id: redrawWarn
                            anchors.fill: parent; anchors.margins: 7
                            wrapMode: Text.WordWrap
                            color: appTheme.textHi; font.pixelSize: 11
                            text: root.tr("This model REDRAWS the picture: faces and details will change. To change just one part, paint it below — the rest stays exactly the same.",
                                          "Esse modelo REDESENHA a imagem: rostos e detalhes vão mudar. Pra mudar só uma parte, pinte ela abaixo — o resto fica exatamente igual.")
                        }
                    }
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

                // ── only this part: a painted mask, and kept faces ──
                Rectangle {
                    visible: root.mode === "edit" && root.refPath !== ""
                    Layout.fillWidth: true
                    implicitHeight: maskCol.implicitHeight + 18
                    radius: appTheme.rMd
                    color: root.maskOn ? appTheme.a(appTheme.green, 0.08) : appTheme.surface
                    border.width: 1
                    border.color: root.maskOn ? appTheme.a(appTheme.green, 0.40) : appTheme.hairline
                    ColumnLayout {
                        id: maskCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            FIcon { name: "edit"; size: 14; color: root.maskOn ? appTheme.greenBright : appTheme.textLo }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.tr("Change only a part", "Mudar só uma parte")
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 12
                            }
                            GToggle {
                                theme: appTheme
                                checked: root.maskOn
                                onToggled: function (v) { root.maskOn = v }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textMid; font.pixelSize: 11
                            text: root.maskOn
                                ? root.tr("Paint over the picture on the right. Only the painted area changes — everything else stays the original, pixel for pixel, at full resolution.",
                                          "Pinte em cima da imagem à direita. Só a área pintada muda — todo o resto continua a original, pixel por pixel, na resolução cheia.")
                                : root.tr("Off: the whole picture can change.", "Desligado: a imagem inteira pode mudar.")
                        }
                        Flow {
                            visible: root.maskOn
                            Layout.fillWidth: true
                            spacing: 6
                            GPill { icon: "edit"; label: root.tr("Brush", "Pincel"); active: !root.eraseMode; onClicked: root.eraseMode = false }
                            GPill { icon: "x"; label: root.tr("Eraser", "Borracha"); active: root.eraseMode; onClicked: root.eraseMode = true }
                            GPill { icon: "refresh-cw"; label: root.tr("Invert", "Inverter"); active: root.maskInvert; onClicked: { root.maskInvert = !root.maskInvert; maskCanvas.requestPaint() } }
                            GPill { icon: "trash"; label: root.tr("Clear", "Limpar"); onClicked: { root.strokes = []; maskCanvas.requestPaint() } }
                        }
                        RowLayout {
                            visible: root.maskOn
                            Layout.fillWidth: true
                            QQC2.Label { text: root.tr("Size", "Tamanho"); color: appTheme.textMid; font.pixelSize: 11 }
                            QQC2.Slider {
                                Layout.fillWidth: true
                                from: 0.015; to: 0.25
                                value: root.brushSize
                                onMoved: root.brushSize = value
                            }
                        }
                        // Faces: kept from the original, whatever the editor does.
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: root.tr("Keep faces exactly as they are", "Manter os rostos exatamente como estão")
                                color: root.status.faces_available ? appTheme.textMid : appTheme.textLo; font.pixelSize: 12
                            }
                            GToggle {
                                theme: appTheme
                                enabled: !!root.status.faces_available
                                opacity: enabled ? 1 : 0.4
                                checked: root.protectFaces && !!root.status.faces_available
                                onToggled: function (v) { root.protectFaces = v }
                            }
                        }
                        QQC2.Label {
                            visible: !root.status.faces_available
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textLo; font.pixelSize: 10
                            text: root.tr("Needs the face detector: sudo pacman -S python-opencv", "Precisa do detector de rostos: sudo pacman -S python-opencv")
                        }
                    }
                }

                // ── prompt ──
                QQC2.Label {
                    visible: root.mode !== "upscale"
                    text: root.mode !== "edit" ? root.tr("DESCRIBE THE PICTURE", "DESCREVA A IMAGEM")
                        : root.editKind(root.activeModel()) === "edit" ? root.tr("WHAT TO CHANGE", "O QUE MUDAR")
                        : root.tr("HOW IT SHOULD LOOK", "COMO DEVE FICAR")
                    color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                }
                Rectangle {
                    visible: root.mode !== "upscale"
                    Layout.fillWidth: true
                    implicitHeight: Math.max(104, prompt.implicitHeight + 16)
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
                            backend.enhanceImagePrompt(root.chatModel, prompt.text,
                                                       root.mode === "edit" ? root.editKind(root.activeModel()) : "generate")
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

                // ── how much an img2img edit may change ──
                ColumnLayout {
                    visible: root.mode === "edit" && root.editKind(root.activeModel()) === "img2img"
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: root.tr("How much to change", "Quanto mudar")
                            color: appTheme.textMid; font.pixelSize: 12
                        }
                        QQC2.Label {
                            text: Math.round(root.strength * 100) + "%"
                            color: appTheme.textHi; font.pixelSize: 12; font.bold: true
                        }
                    }
                    QQC2.Slider {
                        Layout.fillWidth: true
                        from: 0.2; to: 0.95; stepSize: 0.05
                        value: root.strength
                        onMoved: root.strength = value
                    }
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

                // ── LoRAs (Generate) ──
                Rectangle {
                    id: loraCard
                    readonly property var m: root.activeModel()
                    readonly property var ok: root.compatibleLoras(m)
                    visible: root.mode === "generate"
                    Layout.fillWidth: true
                    implicitHeight: loraCol.implicitHeight + 18
                    radius: appTheme.rMd
                    color: appTheme.surface
                    border.width: 1; border.color: appTheme.hairline
                    ColumnLayout {
                        id: loraCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            FIcon { name: "layers"; size: 14; color: appTheme.purpleBright }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: "LoRAs" + (loraCard.ok.length ? "  ·  " + loraCard.ok.length : "")
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 12
                            }
                            GButton {
                                theme: appTheme; kind: "ghost"; iconSource: "plus"
                                text: root.tr("Import", "Importar")
                                onClicked: root.loraGuideOpen = true
                            }
                        }
                        QQC2.Label {
                            visible: loraCard.ok.length === 0
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textMid; font.pixelSize: 11
                            text: root.loras.length === 0
                                ? root.tr("A LoRA adds a style or a look on top of a model (photorealism, film, illustration…). You download them yourself and import them here.",
                                          "Uma LoRA dá um estilo ou um visual em cima de um modelo (fotorrealismo, filme, ilustração…). Você baixa por fora e importa aqui.")
                                : root.tr("None of your LoRAs fit this model's base. A LoRA only works on the base it was made for.",
                                          "Nenhuma das suas LoRAs serve pra base desse modelo. Uma LoRA só funciona na base pra qual foi feita.")
                        }
                        Repeater {
                            model: loraCard.ok
                            delegate: ColumnLayout {
                                id: lr
                                required property var modelData
                                readonly property bool on: root.loraPick[modelData.id] !== undefined
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.CheckBox {
                                        checked: lr.on
                                        onToggled: root.setLora(lr.modelData.id, checked)
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: lr.modelData.name
                                        color: appTheme.textHi; font.pixelSize: 12
                                    }
                                    QQC2.Label {
                                        visible: lr.on
                                        text: (root.loraPick[lr.modelData.id] || 0).toFixed(2)
                                        color: appTheme.textMid; font.pixelSize: 11
                                    }
                                }
                                QQC2.Slider {
                                    visible: lr.on
                                    Layout.fillWidth: true
                                    from: 0.1; to: 1.5; stepSize: 0.05
                                    value: root.loraPick[lr.modelData.id] || 0.8
                                    onMoved: root.setLora(lr.modelData.id, true, value)
                                }
                                QQC2.Label {
                                    visible: lr.on && !!lr.modelData.trigger
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    text: root.tr("Trigger words added: ", "Palavras-gatilho adicionadas: ") + lr.modelData.trigger
                                    color: appTheme.textLo; font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                // ── Turbo ──
                Rectangle {
                    visible: root.mode !== "upscale"
                    Layout.fillWidth: true
                    implicitHeight: turboCol.implicitHeight + 18
                    radius: appTheme.rMd
                    color: root.turbo ? appTheme.a(appTheme.turbo, 0.10) : appTheme.surface
                    border.width: 1
                    border.color: root.turbo ? appTheme.a(appTheme.turbo, 0.40) : appTheme.hairline
                    ColumnLayout {
                        id: turboCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            FIcon { name: "zap"; size: 15; color: root.turbo ? appTheme.turboBright : appTheme.textLo }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: "Turbo"
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 13
                            }
                            GToggle {
                                theme: appTheme
                                checked: root.turbo
                                onToggled: function (v) { root.turbo = v }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textMid; font.pixelSize: 11
                            text: root.turbo ? root.turboText(root.activeModel())
                                : root.tr("Off: every picture loads the model from disk and gives the GPU back when done.",
                                          "Desligado: cada imagem carrega o modelo do disco e devolve a GPU ao terminar.")
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

                    QQC2.TextField {
                        readonly property var m: root.activeModel()
                        visible: !!m && m.defaults && m.defaults.cfg > 1
                        Layout.fillWidth: true
                        text: root.negative
                        placeholderText: root.tr("What to avoid (negative prompt)", "O que evitar (prompt negativo)")
                        onEditingFinished: root.negative = text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: root.tr("Steps", "Passos")
                            color: appTheme.textMid; font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                        QQC2.SpinBox {
                            from: 0; to: 60
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
                            text: root.tr("Pause the chat Turbo while drawing (frees the GPU)",
                                          "Pausar o Turbo do chat enquanto desenha (libera a GPU)")
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
                        if (!m || !root.installedVariant(m)) return root.tr("Choose and download a model first.", "Escolha e baixe um modelo primeiro.")
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
                    // While painting a mask, the picture being edited is shown.
                    readonly property bool masking: root.mode === "edit" && root.maskOn && root.refPath !== "" && !root.busy
                    source: masking ? root.fileUrl(root.refPath)
                          : (root.current ? root.fileUrl(root.current.path) : "")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true; mipmap: true
                    opacity: root.busy ? 0.35 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 440)
                    visible: !root.current && !root.busy && !preview.masking
                    spacing: 10
                    FIcon { Layout.alignment: Qt.AlignHCenter; name: "image"; size: 40; color: appTheme.textLo }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: appTheme.textMid; font.pixelSize: 13
                        text: !root.catalog.some(function (m) { return m.installed })
                            ? root.tr("Pick a model to start — there are fast ones, unfiltered ones, anime, photo, and editors.",
                                      "Escolha um modelo pra começar — tem rápidos, sem filtro, anime, foto e editores.")
                            : root.tr("Your pictures appear here, and are saved in Pictures › Genesi AI.",
                                      "Suas imagens aparecem aqui, e ficam salvas em Imagens › Genesi AI.")
                    }
                    GButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.catalog.some(function (m) { return m.installed })
                        theme: appTheme; kind: "filled"; iconSource: "layout-grid"
                        text: root.tr("Browse models", "Ver modelos")
                        onClicked: { root.filterTag = "all"; root.browserOpen = true }
                    }
                }

                // The mask, painted straight onto the picture.
                Canvas {
                    id: maskCanvas
                    visible: preview.masking
                    x: preview.x + (preview.width - preview.paintedWidth) / 2
                    y: preview.y + (preview.height - preview.paintedHeight) / 2
                    width: Math.max(1, preview.paintedWidth)
                    height: Math.max(1, preview.paintedHeight)
                    // Only for show: the mask file itself is drawn by the
                    // backend from root.strokes (writeImageMask).
                    property var live: null           // the stroke being drawn
                    readonly property color tint: appTheme.green
                    function strokeAll(ctx, change) {
                        var all = root.strokes.slice()
                        if (live) all.push(live)
                        var side = Math.min(width, height)
                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                        for (var i = 0; i < all.length; i++) {
                            var st = all[i]
                            // Shown layer: a stroke either adds the tint or cuts it away.
                            var cut = st.erase !== root.maskInvert
                            ctx.globalCompositeOperation = cut ? "destination-out" : "source-over"
                            ctx.strokeStyle = cut ? "#000000" : change
                            ctx.fillStyle = cut ? "#000000" : change
                            ctx.lineWidth = st.size * side
                            ctx.beginPath()
                            var p0 = st.pts[0]
                            if (st.pts.length === 1) {
                                ctx.arc(p0[0] * width, p0[1] * height, ctx.lineWidth / 2, 0, Math.PI * 2)
                                ctx.fill()
                                continue
                            }
                            ctx.moveTo(p0[0] * width, p0[1] * height)
                            for (var j = 1; j < st.pts.length; j++)
                                ctx.lineTo(st.pts[j][0] * width, st.pts[j][1] * height)
                            ctx.stroke()
                        }
                    }
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        // What the user sees: a tint over the area that will change.
                        var tinted = Qt.rgba(tint.r, tint.g, tint.b, 0.45)
                        if (root.maskInvert) {
                            ctx.fillStyle = tinted
                            ctx.fillRect(0, 0, width, height)
                        }
                        strokeAll(ctx, tinted)
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        function pt(mouse) { return [Math.max(0, Math.min(1, mouse.x / width)), Math.max(0, Math.min(1, mouse.y / height))] }
                        onPressed: function (mouse) {
                            maskCanvas.live = { erase: root.eraseMode, size: root.brushSize, pts: [pt(mouse)] }
                            maskCanvas.requestPaint()
                        }
                        onPositionChanged: function (mouse) {
                            if (!maskCanvas.live) return
                            maskCanvas.live.pts.push(pt(mouse))
                            maskCanvas.requestPaint()
                        }
                        onReleased: {
                            if (!maskCanvas.live) return
                            var s2 = root.strokes.slice()
                            s2.push(maskCanvas.live)
                            maskCanvas.live = null
                            root.strokes = s2
                            maskCanvas.requestPaint()
                        }
                    }
                    // Brush preview ring follows the pointer.
                    Rectangle {
                        id: brushRing
                        visible: brushHover.hovered
                        width: root.brushSize * Math.min(maskCanvas.width, maskCanvas.height)
                        height: width; radius: width / 2
                        x: brushHover.point.position.x - width / 2
                        y: brushHover.point.position.y - height / 2
                        color: "transparent"
                        border.width: 1.5
                        border.color: root.eraseMode ? appTheme.red : appTheme.greenBright
                    }
                    HoverHandler { id: brushHover }
                }
                QQC2.Label {
                    visible: preview.masking && root.strokes.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                    text: root.tr("Paint the area to change", "Pinte a área que vai mudar")
                    color: appTheme.textHi; font.pixelSize: 13; font.bold: true
                    background: Rectangle { color: appTheme.a(appTheme.card, 0.85); radius: 8 }
                    padding: 8
                }

                // progress over the picture
                Rectangle {
                    visible: root.busy
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 400)
                    height: progCol.implicitHeight + 32
                    radius: appTheme.rLg
                    color: appTheme.a(appTheme.card, 0.94)
                    border.width: 1; border.color: appTheme.lineHi
                    ColumnLayout {
                        id: progCol
                        anchors.fill: parent; anchors.margins: 16
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.phaseText()
                                color: appTheme.textHi; font.pixelSize: 14; font.bold: true
                            }
                            Chip { visible: root.runTurbo; text: "TURBO"; tint: appTheme.turboBright }
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
                        QQC2.Label {
                            visible: root.runStatus !== "" && root.phase !== ""
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textLo; font.pixelSize: 10
                            text: root.runStatus
                        }
                    }
                }
            }

            // ── what went wrong, with the engine's own words a click away ──
            Rectangle {
                visible: root.runError !== ""
                Layout.fillWidth: true
                implicitHeight: errCol.implicitHeight + 18
                radius: appTheme.rMd
                color: appTheme.a(appTheme.red, 0.08)
                border.width: 1; border.color: appTheme.a(appTheme.red, 0.35)
                ColumnLayout {
                    id: errCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 9
                    spacing: 6
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: root.runError
                        color: appTheme.textHi; font.pixelSize: 12
                    }
                    RowLayout {
                        spacing: 8
                        GButton {
                            theme: appTheme; kind: "ghost"; iconSource: "file-text"
                            text: root.showLog ? root.tr("Hide details", "Esconder detalhes") : root.tr("Show details", "Ver detalhes")
                            onClicked: {
                                root.showLog = !root.showLog
                                if (root.showLog) root.logText = backend.imageLog()
                            }
                        }
                        GButton {
                            theme: appTheme; kind: "ghost"; iconSource: "copy"
                            text: root.tr("Copy log", "Copiar log")
                            onClicked: backend.copyText(root.runError + "\n\n" + backend.imageLog())
                        }
                    }
                    QQC2.ScrollView {
                        visible: root.showLog
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        QQC2.TextArea {
                            readOnly: true
                            text: root.logText
                            font.family: appTheme.mono; font.pixelSize: 10
                            color: appTheme.textMid
                            wrapMode: TextEdit.WrapAnywhere
                            background: Rectangle { color: appTheme.a(appTheme.black, 0.25); radius: 6 }
                        }
                    }
                }
            }

            // ── what to do with it ──
            Flow {
                visible: root.current !== null && !root.busy
                Layout.fillWidth: true
                spacing: 8
                GButton {
                    theme: appTheme; iconSource: "edit"
                    visible: root.catalog.some(function (m) { return m.installed && (root.has(m.caps, "edit") || root.has(m.caps, "img2img")) })
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
                        hoverEnabled: true
                        onClicked: root.current = thumb.modelData
                        onDoubleClicked: { root.current = thumb.modelData; root.reuse(thumb.modelData) }
                        QQC2.ToolTip.visible: containsMouse && !!thumb.modelData.prompt
                        QQC2.ToolTip.text: thumb.modelData.prompt || ""
                        QQC2.ToolTip.delay: 500
                    }
                }
            }
        }
    }

    // ════════════════════════ LoRAs: how-to, warning, import, list ════════════════════════
    Rectangle {
        anchors.fill: parent
        visible: root.loraGuideOpen
        z: 85
        color: appTheme.a(appTheme.black, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.loraGuideOpen = false }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 760)
            height: Math.min(parent.height - 32, 760)
            radius: appTheme.rLg
            color: appTheme.card
            border.width: 1; border.color: appTheme.lineHi
            MouseArea { anchors.fill: parent }
            QQC2.ScrollView {
                id: guideScroll
                anchors.fill: parent
                anchors.margins: 18
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: guideScroll.availableWidth
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: root.tr("LoRAs — how to import", "LoRAs — como importar")
                            color: appTheme.textHi; font.pixelSize: 20; font.bold: true
                        }
                        GButton { theme: appTheme; kind: "ghost"; iconSource: "x"; onClicked: root.loraGuideOpen = false }
                    }
                    Repeater {
                        model: [
                            { n: "1", en: "Find a LoRA on Civitai or Hugging Face. Check its BASE MODEL: SDXL, Pony, Illustrious, FLUX, Qwen-Image or Z-Image. It only works on a model with that same base.",
                                      pt: "Ache uma LoRA no Civitai ou no Hugging Face. Confira o BASE MODEL dela: SDXL, Pony, Illustrious, FLUX, Qwen-Image ou Z-Image. Ela só funciona num modelo com essa mesma base." },
                            { n: "2", en: "Download the .safetensors file. Never a .ckpt or .pt: those can run code on your computer when loaded, and Genesi refuses them.",
                                      pt: "Baixe o arquivo .safetensors. Nunca .ckpt ou .pt: esses podem rodar código no seu computador quando abertos, e o Genesi recusa." },
                            { n: "3", en: "If the page lists trigger words, paste them below — Genesi adds them to your prompt when the LoRA is on.",
                                      pt: "Se a página da LoRA tiver palavras-gatilho (trigger words), cole abaixo — o Genesi coloca no seu prompt quando a LoRA estiver ligada." },
                            { n: "4", en: "Click Choose file. Genesi reads which base the LoRA is for and shows it only on matching models.",
                                      pt: "Clique em Escolher arquivo. O Genesi lê pra qual base a LoRA é e só mostra ela nos modelos que combinam." },
                            { n: "5", en: "In Generate, switch it on in the LoRAs card and set its strength (0.6–1.0 is usual).",
                                      pt: "No Gerar, ligue ela no card de LoRAs e ajuste a força (0,6–1,0 é o comum)." }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                width: 24; height: 24; radius: 12
                                color: appTheme.a(appTheme.green, 0.18)
                                QQC2.Label { anchors.centerIn: parent; text: modelData.n; color: appTheme.greenBright; font.bold: true; font.pixelSize: 12 }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: root.tr(modelData.en, modelData.pt)
                                color: appTheme.textHi; font.pixelSize: 12
                            }
                        }
                    }
                    // The warning, in full, before the button.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: warnCol.implicitHeight + 20
                        radius: appTheme.rMd
                        color: appTheme.a(appTheme.red, 0.08)
                        border.width: 1; border.color: appTheme.a(appTheme.red, 0.35)
                        ColumnLayout {
                            id: warnCol
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 10
                            spacing: 5
                            QQC2.Label {
                                text: root.tr("Use it legally and safely", "Use de forma legal e segura")
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 13
                            }
                            QQC2.Label {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: appTheme.textMid; font.pixelSize: 11
                                text: root.tr("• Only import files from sources you trust. A LoRA is a file from the internet; .safetensors cannot run code, but a model can still be made to produce things you did not want.\n• Never create sexual or intimate images of a real person without their consent, and never any sexual content involving minors — it is a crime and Genesi forbids it in its terms of use.\n• Do not use pictures to deceive, harass or impersonate anyone.\n• Respect each LoRA's licence (some forbid commercial use).\n• LoRAs work in Generate, not in edits of an existing photo.\n• Everything runs on this computer: Genesi does not see, store or send your pictures or prompts — and so you are responsible for what you make.",
                                              "• Só importe arquivos de fontes em que você confia. Uma LoRA é um arquivo da internet; .safetensors não roda código, mas um modelo ainda pode ser feito pra gerar coisas que você não queria.\n• Nunca crie imagens sexuais ou íntimas de uma pessoa real sem o consentimento dela, e jamais qualquer conteúdo sexual envolvendo menores — é crime e os termos de uso do Genesi proíbem.\n• Não use imagens pra enganar, assediar ou se passar por alguém.\n• Respeite a licença de cada LoRA (algumas proíbem uso comercial).\n• LoRAs funcionam no Gerar, não em edições de uma foto existente.\n• Tudo roda neste computador: o Genesi não vê, não guarda e não envia suas imagens nem seus prompts — por isso a responsabilidade pelo que você cria é sua.")
                            }
                        }
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: root.loraTrigger
                        color: appTheme.textHi
                        placeholderTextColor: appTheme.textLo
                        leftPadding: 10; rightPadding: 10
                        background: Rectangle {
                            implicitHeight: 34
                            radius: appTheme.rSm
                            color: appTheme.surface
                            border.width: 1; border.color: appTheme.hairline
                        }
                        placeholderText: root.tr("Trigger words (optional), e.g. film grain, kodak portra",
                                                 "Palavras-gatilho (opcional), ex.: film grain, kodak portra")
                        onTextEdited: root.loraTrigger = text
                    }
                    RowLayout {
                        spacing: 10
                        GButton {
                            theme: appTheme; kind: "filled"; iconSource: "plus"
                            enabled: !root.loraBusy
                            text: root.loraBusy ? root.tr("Adding…", "Adicionando…") : root.tr("Choose file (.safetensors)", "Escolher arquivo (.safetensors)")
                            onClicked: { root.loraMsg = ""; loraDialog.open() }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            visible: root.loraMsg !== ""
                            text: root.loraMsg
                            color: appTheme.textMid; font.pixelSize: 11
                        }
                    }
                    QQC2.Label {
                        visible: root.loras.length > 0
                        text: root.tr("YOUR LORAS", "SUAS LORAS")
                        color: appTheme.textLo; font.pixelSize: 10; font.letterSpacing: 1.1
                        Layout.topMargin: 6
                    }
                    Repeater {
                        model: root.loras
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: appTheme.rSm
                            color: appTheme.surface
                            border.width: 1; border.color: appTheme.hairline
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 8
                                spacing: 8
                                QQC2.Label {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: modelData.name
                                    color: appTheme.textHi; font.pixelSize: 12
                                }
                                Chip {
                                    text: root.familyLabel(modelData.family)
                                    tint: modelData.family ? appTheme.purpleBright : appTheme.turboBright
                                }
                                GButton {
                                    theme: appTheme; kind: "ghost"; iconSource: "trash"
                                    tooltip: root.tr("Remove", "Remover")
                                    onClicked: { root.setLora(modelData.id, false); backend.removeImageLora(modelData.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════ the model browser ════════════════════════
    Rectangle {
        anchors.fill: parent
        visible: root.browserOpen
        z: 80
        color: appTheme.a(appTheme.black, 0.55)
        // Swallow clicks so the page behind does not react (MouseArea, not
        // TapHandler: a TapHandler lets the press through).
        MouseArea { anchors.fill: parent; onClicked: root.browserOpen = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 1060)
            height: Math.min(parent.height - 32, 760)
            radius: appTheme.rLg
            color: appTheme.card
            border.width: 1; border.color: appTheme.lineHi
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: root.tr("Image models", "Modelos de imagem")
                        color: appTheme.textHi; font.pixelSize: 20; font.bold: true
                    }
                    GButton {
                        theme: appTheme; kind: "tonal"; iconSource: "plus"
                        enabled: root.pullingId === "" && root.engineReady
                        text: root.tr("Add my model", "Adicionar meu modelo")
                        tooltip: root.tr("Any SD 1.5 or SDXL checkpoint (.safetensors / .gguf) — Civitai models, Pony, Illustrious…",
                                         "Qualquer checkpoint SD 1.5 ou SDXL (.safetensors / .gguf) — modelos do Civitai, Pony, Illustrious…")
                        onClicked: importDialog.open()
                    }
                    GButton {
                        theme: appTheme; kind: "ghost"; iconSource: "x"
                        onClicked: root.browserOpen = false
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textMid; font.pixelSize: 11
                    text: root.tr("Each model downloads only when you ask. The variant picks size vs. quality — the recommended one fits your GPU"
                                  + (root.status.vram_mb ? " (" + Math.round(root.status.vram_mb / 1024) + " GB)" : "") + ".",
                                  "Cada modelo só é baixado quando você pedir. A variante escolhe tamanho × qualidade — a recomendada cabe na sua GPU"
                                  + (root.status.vram_mb ? " (" + Math.round(root.status.vram_mb / 1024) + " GB)" : "") + ".")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "all", en: "All", pt: "Todos" },
                            { id: "installed", en: "Downloaded", pt: "Baixados" },
                            { id: "fits", en: "Fit my GPU", pt: "Cabem na minha GPU" },
                            { id: "unfiltered", en: "Unfiltered", pt: "Sem filtro" },
                            { id: "fast", en: "Fast", pt: "Rápidos" },
                            { id: "editors", en: "Editing", pt: "Edição" },
                            { id: "photo", en: "Photo", pt: "Foto" },
                            { id: "anime", en: "Anime", pt: "Anime" },
                            { id: "text", en: "Text in image", pt: "Texto na imagem" }
                        ]
                        delegate: GPill {
                            required property var modelData
                            label: root.tr(modelData.en, modelData.pt)
                            active: root.filterTag === modelData.id
                            onClicked: root.filterTag = modelData.id
                        }
                    }
                }
                QQC2.Label {
                    visible: root.pullError !== ""
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.pullError
                    color: appTheme.red; font.pixelSize: 11
                }

                QQC2.ScrollView {
                    id: browserScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    Flow {
                        id: cards
                        width: browserScroll.availableWidth
                        spacing: 10
                        readonly property int cols: Math.max(1, Math.floor((width + 10) / 320))
                        readonly property real cardW: (width - (cols - 1) * 10) / cols
                        Repeater {
                            model: root.browserModels()
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                readonly property var v: root.variantOf(modelData)
                                readonly property bool pulling: root.pullingId === modelData.id
                                readonly property bool ramShort: modelData.min_ram_gb > 0 && root.ramGb() > 0
                                                                 && root.ramGb() < modelData.min_ram_gb
                                width: cards.cardW
                                implicitHeight: cardCol.implicitHeight + 22
                                radius: appTheme.rMd
                                color: appTheme.surface
                                border.width: 1
                                border.color: modelData.installed ? appTheme.a(appTheme.green, 0.40) : appTheme.hairline
                                ColumnLayout {
                                    id: cardCol
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 11
                                    spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: card.modelData.name
                                            color: appTheme.textHi; font.bold: true; font.pixelSize: 14
                                            elide: Text.ElideRight
                                        }
                                        Chip {
                                            visible: card.modelData.recommended
                                            text: root.tr("START HERE", "COMECE AQUI")
                                            tint: appTheme.greenBright
                                        }
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Repeater {
                                            model: card.modelData.tags.filter(function (t) { return t !== "sdxl" })
                                            delegate: Chip {
                                                required property var modelData
                                                text: root.tagLabel(modelData)
                                                tint: root.tagColor(modelData)
                                            }
                                        }
                                        Chip {
                                            text: root.has(card.modelData.caps, "edit") ? root.tr("edits by instruction", "edita por instrução")
                                                : root.has(card.modelData.caps, "img2img") ? root.tr("generates · redraws", "gera · redesenha")
                                                : root.has(card.modelData.caps, "upscale") ? root.tr("upscaler", "amplia")
                                                : root.tr("edit only", "só edita")
                                            tint: appTheme.textLo
                                        }
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: root.loc(card.modelData.summary)
                                        color: appTheme.textMid; font.pixelSize: 11
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        color: card.ramShort ? appTheme.turboBright : appTheme.textLo
                                        font.pixelSize: 10
                                        text: card.modelData.license
                                            + (card.v ? "  ·  GPU " + root.gb(card.v.gpu_size) : "")
                                            + (card.ramShort ? "  ·  " + root.tr("needs " + card.modelData.min_ram_gb + " GB RAM (you have " + root.ramGb() + ")",
                                                                                 "precisa de " + card.modelData.min_ram_gb + " GB de RAM (você tem " + root.ramGb() + ")") : "")
                                    }
                                    // variant: size vs. quality
                                    QQC2.ComboBox {
                                        id: variantBox
                                        visible: card.modelData.variants.length > 1
                                        Layout.fillWidth: true
                                        enabled: !card.pulling
                                        model: card.modelData.variants.map(function (x) {
                                            return root.loc(x.label) + "  ·  " + root.gb(x.installed ? x.size : (x.download || x.size))
                                                + (x.installed ? "  ✓" : "")
                                                + (x.recommended ? "  ·  " + root.tr("recommended", "recomendada") : "")
                                        })
                                        onActivated: function (i) { root.pickVariant(card.modelData, card.modelData.variants[i].id) }
                                    }
                                    // A Binding element, not `currentIndex:` on the box: a
                                    // ComboBox resets its index to 0 when its model arrives,
                                    // and that reset destroys a plain binding -- the box then
                                    // showed Q4 while Q8 was the variant in use.
                                    Binding {
                                        target: variantBox
                                        property: "currentIndex"
                                        value: {
                                            for (var i = 0; i < card.modelData.variants.length; i++)
                                                if (card.v && card.modelData.variants[i].id === card.v.id) return i
                                            return 0
                                        }
                                    }
                                    QQC2.Label {
                                        visible: !!card.v && card.v.converts && !card.v.installed
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        color: appTheme.textLo; font.pixelSize: 10
                                        text: root.tr("Optimized on your machine right after the download (7 GB → 4 GB, a few minutes).",
                                                      "Otimizado na sua máquina logo após o download (7 GB → 4 GB, alguns minutos).")
                                    }
                                    // download progress
                                    ColumnLayout {
                                        visible: card.pulling
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
                                    RowLayout {
                                        visible: !card.pulling
                                        Layout.fillWidth: true
                                        spacing: 6
                                        GButton {
                                            theme: appTheme; kind: "filled"; iconSource: "download"
                                            visible: !!card.v && !card.v.installed
                                            enabled: root.pullingId === "" && (root.engineReady || !card.v.converts)
                                            text: (card.v && card.v.partial ? root.tr("Resume", "Continuar") : root.tr("Download", "Baixar"))
                                                  + (card.v ? " · " + root.gb(card.v.download || card.v.size) : "")
                                            onClicked: root.startPull(card.modelData)
                                        }
                                        GButton {
                                            theme: appTheme; kind: "filled"; iconSource: "check"
                                            visible: !!card.v && card.v.installed && !root.has(card.modelData.caps, "upscale")
                                            text: root.tr("Use", "Usar")
                                            onClicked: {
                                                root.modelId = card.modelData.id
                                                if (!root.fitsMode(card.modelData, root.mode))
                                                    root.mode = root.has(card.modelData.caps, "generate") ? "generate" : "edit"
                                                root.browserOpen = false
                                            }
                                        }
                                        GButton {
                                            theme: appTheme; kind: "tonal"
                                            visible: card.modelData.custom && card.modelData.variants.length === 1 && card.modelData.installed
                                            enabled: root.pullingId === ""
                                            text: root.tr("Optimize (Q8)", "Otimizar (Q8)")
                                            tooltip: root.tr("Convert to GGUF Q8_0: about half the memory, same picture.",
                                                             "Converte pra GGUF Q8_0: cerca de metade da memória, mesma imagem.")
                                            onClicked: { root.pullingId = card.modelData.id; backend.optimizeImageModel(card.modelData.id, "q8_0") }
                                        }
                                        Item { Layout.fillWidth: true }
                                        GButton {
                                            theme: appTheme; kind: "ghost"; iconSource: "trash"
                                            visible: card.modelData.installed || card.modelData.partial
                                            enabled: root.pullingId === ""
                                            tooltip: card.modelData.custom ? root.tr("Remove from the list (your file stays)", "Tirar da lista (seu arquivo fica)")
                                                                           : root.tr("Delete the downloaded files", "Apagar os arquivos baixados")
                                            onClicked: backend.removeImageModel(card.modelData.id, "")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
