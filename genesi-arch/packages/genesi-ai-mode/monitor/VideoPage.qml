/*
 * Genesi AI Mode Monitor — Video page.
 *
 * Make a short clip from a description, animate a picture (the face in it
 * stays the face in the clip), put a person from a photo into a new scene,
 * restyle a video or continue one. All local, through stable-diffusion.cpp --
 * the same engine, model folder and LoRAs as the Image page.
 *
 * A FRONT END ONLY, like the Image page: `genesi-ai-video` owns the catalog,
 * the downloads and the runs, and the backend relays its JSON events here.
 * What a model can do is the catalog's `modes`, never decided on this page.
 *
 * The player lives in VideoPlayer.qml behind a Loader: QtMultimedia is its
 * own package, and a failed import must cost the player, not the page.
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
    // Overridable so the CI can load the page with the player broken.
    property url playerSource: Qt.resolvedUrl("VideoPlayer.qml")
    // The prompt box and whether the built-in player works, for the CI.
    property alias promptText: prompt.text
    readonly property bool playerWorks: stage.playerOk

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
    readonly property bool hasFfmpeg: status.ffmpeg === true
    property string engineState: ""

    // download / remove
    property string pullingId: ""
    property real pullFrac: 0
    property string pullText: ""
    property string pullPart: ""
    property string pullError: ""

    // a run
    property bool busy: false
    property string phase: ""
    property int step: 0
    property int steps: 0
    property real secPerStep: 0
    property string runStatus: ""
    property string runError: ""
    property bool runTurbo: false
    property double runStarted: 0
    property int elapsed: 0
    property string logText: ""
    property bool showLog: false
    property int runFrames: 0

    property var current: null            // gallery item shown in the player

    // the form
    property string mode: "text"          // text | image | subject | video
    property string videoAction: "extend" // video mode: extend | restyle
    property string modelId: ""
    property var variantPick: ({})
    property string imagePath: ""         // first frame (image) or the person (subject)
    property string imageName: ""
    property int imageW: 0
    property int imageH: 0
    property bool useEnd: false
    property string endPath: ""
    property string endName: ""
    property string videoPath: ""
    property string videoName: ""
    property real seconds: 0              // 0 = the model's default
    property string sizeKey: "480p"
    property string aspect: "16:9"
    property bool lockSeed: false
    property int seed: -1
    property int stepsOverride: 0
    property string negative: ""
    property bool turbo: true
    property bool pauseTurbo: true
    property bool lowMemory: true
    property bool lightVae: false
    property bool enhancing: false
    property string enhanceError: ""

    // LoRAs (the Image page's store)
    property var loras: []
    property var loraPick: ({})
    property bool loraGuideOpen: false
    property string loraTrigger: ""
    property string loraMsg: ""
    property bool loraBusy: false

    // the model browser
    property bool browserOpen: false
    property string filterTag: "all"

    function has(arr, x) { return arr && arr.indexOf(x) >= 0 }
    function modelInfo(id) {
        for (var i = 0; i < catalog.length; i++)
            if (catalog[i].id === id) return catalog[i]
        return null
    }
    // The engine mode this form asks for.
    function engineMode() {
        if (mode === "image") {
            var m = activeModel()
            return useEnd && m && has(m.modes, "flf2v") ? "flf2v" : "i2v"
        }
        if (mode === "subject") return "r2v"
        if (mode === "video") return videoAction === "restyle" ? "v2v" : "extend"
        return "t2v"
    }
    function fitsMode(m, md) {
        if (!m) return false
        if (md === "image") return has(m.modes, "i2v")
        if (md === "subject") return has(m.modes, "r2v")
        if (md === "video") return has(m.modes, videoAction === "restyle" ? "v2v" : "extend")
        return has(m.modes, "t2v")
    }
    function faceModes() { return mode === "image" || mode === "subject" }
    function activeModel() {
        var m = modelInfo(modelId)
        if (m && fitsMode(m, mode) && m.installed) return m
        var installed = catalog.filter(function (x) { return fitsMode(x, mode) && x.installed })
        if (installed.length) {
            // Animating a person: the one that keeps the face best first.
            if (faceModes())
                installed.sort(function (a, b) { return (b.identity || 0) - (a.identity || 0) })
            return installed[0]
        }
        return m && fitsMode(m, mode) ? m : null
    }
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
    // A Linux path starts with "/"; a drive letter (the Windows dev box and
    // CI preview) needs the third slash, or "D:" reads as a URL scheme.
    function fileUrl(p) { return !p ? "" : /^[A-Za-z]:/.test(p) ? "file:///" + p : "file://" + p }
    function vramBytes() { return (status.vram_mb || 0) * 1048576 }
    function ramGb() { return Math.round((status.ram_mb || 0) / 1024) }
    function fitsGpu(m) {
        var v = variantOf(m)
        return v && vramBytes() > 0 && v.gpu_size <= vramBytes() - 1536 * 1048576
    }
    function tagLabel(t) {
        return ({
            "fast": tr("Fast", "Rápido"), "heavy": tr("Heavy", "Pesado"),
            "light": tr("Light", "Leve"), "faces": tr("Faces", "Rostos"),
            "edit": tr("Edits video", "Edita vídeo"), "audio": tr("Sound", "Som"),
            "cinematic": tr("Cinematic", "Cinema"), "experimental": tr("Experimental", "Experimental")
        })[t] || t
    }
    function tagColor(t) {
        if (t === "fast" || t === "light") return appTheme.greenBright
        if (t === "heavy" || t === "experimental") return appTheme.turboBright
        if (t === "faces") return appTheme.purpleBright
        if (t === "audio") return appTheme.blue
        return appTheme.textMid
    }
    function modeLabel(md) {
        return ({
            "t2v": tr("text → video", "texto → vídeo"), "i2v": tr("image → video", "imagem → vídeo"),
            "flf2v": tr("first + last frame", "primeiro + último quadro"),
            "r2v": tr("person in a new scene", "pessoa numa cena nova"),
            "v2v": tr("restyles video", "muda estilo de vídeo"), "extend": tr("continues clips", "continua clipes")
        })[md] || md
    }
    function faceText(m) {
        if (!m || !m.face) return ""
        if (m.face === "subject")
            return (m.identity || 0) >= 3 ? tr("Best at keeping a person from a photo in a new scene", "O melhor pra manter uma pessoa de uma foto numa cena nova")
                                          : tr("Keeps a person from a photo in a new scene", "Mantém uma pessoa de uma foto numa cena nova")
        return (m.identity || 0) >= 3 ? tr("Best at keeping the face of your picture", "O melhor pra manter o rosto da sua imagem")
             : (m.identity || 0) === 2 ? tr("Keeps the face of your picture well", "Mantém bem o rosto da sua imagem")
             : tr("Starts from your picture — faces can drift", "Começa da sua imagem — rostos podem mudar")
    }
    function stars(n) { return "★★★".substring(0, n) + "☆☆☆".substring(0, 3 - n) }
    function browserModels() {
        var out = catalog.filter(function (m) {
            if (filterTag === "all") return true
            if (filterTag === "installed") return m.installed || m.partial
            if (filterTag === "fits") return fitsGpu(m)
            if (filterTag === "faces") return m.face !== ""
            if (filterTag === "i2v") return has(m.modes, "i2v")
            if (filterTag === "audio") return !!m.audio
            return has(m.tags, filterTag)
        })
        if (filterTag === "faces" || faceModes())
            out.sort(function (a, b) { return (b.identity || 0) - (a.identity || 0) })
        return out
    }
    function faceModels() {
        var out = catalog.filter(function (m) { return m.face !== "" && fitsMode(m, mode) })
        out.sort(function (a, b) { return (b.identity || 0) - (a.identity || 0) })
        return out
    }

    // ── length, size ──
    function fps(m) { return m ? (m.fps || 16) : 16 }
    function clipSeconds(m) {
        if (!m) return 3
        var s = seconds > 0 ? seconds : (m.default_seconds || 3)
        return Math.min(s, m.max_seconds || 5)
    }
    function frameCount(m) {
        if (!m) return 0
        var stepN = m.frame_step || 4
        var n = Math.round(clipSeconds(m) * fps(m))
        n = Math.max(stepN + 1, Math.floor((Math.max(1, n - 1) + stepN / 2) / stepN) * stepN + 1)
        var longest = Math.floor((m.max_seconds || 5) * fps(m) / stepN) * stepN + 1
        return Math.min(n, longest)
    }
    function sizesOf(m) { return m && m.sizes ? m.sizes : ["480p"] }
    function shapeFromAspect() { return mode === "text" || mode === "subject" }

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
        return ({ "wan-1.3b": "Wan 2.1 1.3B", "wan-5b": "Wan 2.2 5B", "wan-14b": "Wan 14B (2.1 / 2.2)",
                  "wan": tr("Wan (size unknown)", "Wan (tamanho desconhecido)"),
                  "sdxl": "SDXL", "sd15": "SD 1.5", "flux": "FLUX", "qwen": "Qwen-Image",
                  "zimage": "Z-Image" })[f] || tr("unknown base", "base desconhecida")
    }

    function phaseText() {
        if (phase === "load") return tr("Loading the model onto the GPU", "Carregando o modelo na GPU")
        if (phase === "encode") return tr("Reading your prompt", "Lendo o seu prompt")
        if (phase === "sample") return tr("Making the frames", "Criando os quadros")
        if (phase === "decode") return tr("Turning it into video", "Transformando em vídeo")
        if (phase === "finish") return tr("Saving as MP4", "Salvando em MP4")
        return runStatus || tr("Starting", "Iniciando")
    }
    function runFraction() {
        if (phase === "sample" && steps > 0) return 0.12 + 0.70 * (step / steps)
        if (phase === "load" && steps > 0) return 0.08 * (step / steps)
        if (phase === "encode") return 0.10
        if (phase === "decode") return 0.86
        if (phase === "finish") return 0.96
        return 0.02
    }

    function blockReason() {
        var m = activeModel()
        if (!m || !installedVariant(m)) return tr("Choose and download a model first.", "Escolha e baixe um modelo primeiro.")
        if ((mode === "image" || mode === "subject") && !imagePath)
            return mode === "image" ? tr("Choose the picture to animate first.", "Escolha a imagem pra animar primeiro.")
                                    : tr("Choose the photo of the person first.", "Escolha a foto da pessoa primeiro.")
        if (engineMode() === "flf2v" && !endPath) return tr("Choose the last frame too.", "Escolha o último quadro também.")
        if (mode === "video" && !hasFfmpeg) return tr("Editing a video needs ffmpeg: sudo pacman -S ffmpeg", "Editar vídeo precisa do ffmpeg: sudo pacman -S ffmpeg")
        if (mode === "video" && !videoPath) return tr("Choose a video first.", "Escolha um vídeo primeiro.")
        if (prompt.text.trim().length === 0) return tr("Write what should happen first.", "Escreva o que deve acontecer primeiro.")
        return ""
    }
    function canRun() { return !busy && engineReady && blockReason() === "" }

    function run() {
        if (!canRun()) return
        var m = activeModel()
        var v = installedVariant(m)
        var md = engineMode()
        var o = { model: m.id, variant: v.id, mode: md, prompt: prompt.text.trim(),
                  turbo: turbo, pauseTurbo: pauseTurbo, lowMemory: lowMemory,
                  lightVae: lightVae && !!m.light_vae, seconds: clipSeconds(m),
                  size: has(sizesOf(m), sizeKey) ? sizeKey : sizesOf(m)[0] }
        if (shapeFromAspect()) o.aspect = aspect
        if (md === "i2v" || md === "flf2v" || md === "r2v") o.image = imagePath
        if (md === "flf2v") o.endImage = endPath
        if (md === "v2v" || md === "extend") o.video = videoPath
        if (md === "v2v" && imagePath) o.image = imagePath
        if (stepsOverride > 0) o.steps = stepsOverride
        if (lockSeed && seed >= 0) o.seed = seed
        if (negative.trim().length) o.negative = negative.trim()
        var picked = []
        var ok = compatibleLoras(m)
        for (var i = 0; i < ok.length; i++)
            if (loraPick[ok[i].id] !== undefined)
                picked.push({ id: ok[i].id, weight: loraPick[ok[i].id] })
        o.loras = picked
        runError = ""; runStatus = ""; phase = ""; step = 0; steps = 0
        secPerStep = 0; showLog = false; logText = ""; runFrames = 0
        busy = true
        runStarted = Date.now(); elapsed = 0
        backend.setVideoPrefs(JSON.stringify({ model: m.id, mode: mode }))
        backend.generateVideo(JSON.stringify(o))
    }

    function setImage(url, which) {
        var r = {}
        try { r = JSON.parse(backend.prepareImageInput(url)) } catch (e) { r = { error: "?" } }
        if (r.error) { runError = r.error; return }
        if (which === "end") { endPath = r.path; endName = r.name; return }
        imagePath = r.path; imageName = r.name; imageW = r.width; imageH = r.height
        if (mode === "text" || mode === "video") mode = "image"
    }
    function setVideo(url) {
        var r = {}
        try { r = JSON.parse(backend.prepareVideoInput(url)) } catch (e) { r = { error: "?" } }
        if (r.error) { runError = r.error; return }
        videoPath = r.path; videoName = r.name
        mode = "video"
    }
    function isVideoUrl(u) { return /\.(mp4|mkv|webm|avi|mov|m4v|gif)$/i.test(u) }
    // A clip this page made, handed to "Edit a video" without a copy.
    function useClip(item, action) {
        if (!item) return
        videoPath = item.path
        videoName = item.path.substring(item.path.lastIndexOf("/") + 1)
        videoAction = action
        mode = "video"
        prompt.text = ""
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
        backend.pullVideoModel(m.id, v ? v.id : "")
    }
    function refresh() {
        backend.loadVideoInfo()
        backend.loadVideoGallery()
        backend.loadImageLoras()
    }

    Component.onCompleted: {
        try {
            var p = JSON.parse(backend.videoPrefs())
            turbo = p.turbo !== false
            if (p.model) modelId = p.model
            if (p.lowMemory === true || p.lowMemory === false) lowMemory = p.lowMemory
        } catch (e) {}
        if (visible) refresh()
    }
    onVisibleChanged: if (visible) refresh()
    onTurboChanged: backend.setVideoPrefs(JSON.stringify({ turbo: turbo }))
    // Small cards start in low-memory mode; a choice the user made sticks.
    onStatusChanged: {
        try {
            var p = JSON.parse(backend.videoPrefs())
            if (p.lowMemory === null || p.lowMemory === undefined)
                lowMemory = !(status.vram_mb >= 12288)
        } catch (e) {}
    }

    Timer {
        interval: 1000; repeat: true; running: root.busy
        onTriggered: root.elapsed = Math.round((Date.now() - root.runStarted) / 1000)
    }

    Connections {
        target: backend
        function onVideoInfo(js) {
            var o = {}
            try { o = JSON.parse(js) } catch (e) {}
            root.toolPresent = o.tool !== false
            root.status = o.status || ({})
            root.catalog = o.catalog || []
        }
        function onVideoGallery(js) {
            var arr = []
            try { arr = JSON.parse(js) } catch (e) {}
            root.gallery = arr
            if (!root.current && arr.length) root.current = arr[0]
        }
        function onVideoPullEvent(js) {
            var ev = {}
            try { ev = JSON.parse(js) } catch (e) { return }
            if (ev.event === "progress") {
                root.pullFrac = ev.steps ? ev.step / ev.steps : 0
                var what = ev.phase === "verify" ? root.tr("checking ", "conferindo ") : ""
                root.pullText = (root.pullPart ? root.pullPart + "  ·  " : "")
                    + what + (ev.file || "") + " — " + Math.round(root.pullFrac * 100) + "%"
                    + (ev.rate ? "  ·  " + (ev.rate / 1e6).toFixed(1) + " MB/s" : "")
            } else if (ev.event === "status") {
                var mm = /\((\d+\/\d+)\)\s*$/.exec(ev.text || "")
                root.pullPart = mm ? mm[1] : root.pullPart
                root.pullText = ev.text
            } else if (ev.event === "error") {
                root.pullError = ev.text
            }
        }
        function onVideoPullDone(ok, id, err) {
            root.pullingId = ""
            root.pullPart = ""
            root.pullFrac = 0
            root.pullText = ""
            if (!ok && err !== "cancelled") root.pullError = err
        }
        function onVideoEvent(js) {
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
                root.runFrames = ev.frames || 0
            } else if (ev.event === "done") {
                root.current = { path: ev.path, poster: ev.poster || "", seed: ev.seed,
                                 width: ev.width, height: ev.height, frames: ev.frames,
                                 fps: ev.fps, mode: root.engineMode(),
                                 audio: !!(root.activeModel() && root.activeModel().audio),
                                 prompt: prompt.text.trim(), seconds: ev.seconds }
                if (ev.seed !== undefined) root.seed = ev.seed
                if (ev.low_memory)
                    root.runStatus = root.tr("Made in low-memory mode (smaller size).",
                                             "Feito no modo econômico (tamanho menor).")
            } else if (ev.event === "error") {
                root.runError = ev.text === "cancelled" ? "" : ev.text
            }
        }
        function onVideoBusy(b) { root.busy = b }
        function onVideoPromptEnhanced(text, err) {
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
        function onImagePullDone(ok, id, err) {
            // The LoRA store is shared: only the import THIS page started.
            if (id !== "lora" || !root.loraBusy) return
            root.loraBusy = false
            root.loraMsg = ok ? root.tr("LoRA added.", "LoRA adicionada.") : err
            root.loraTrigger = ""
        }
    }

    QQD.FileDialog {
        id: imageDialog
        property string which: "start"
        title: which === "end" ? root.tr("Choose the last frame", "Escolha o último quadro")
                               : root.tr("Choose a picture", "Escolha uma imagem")
        nameFilters: [root.tr("Images", "Imagens") + " (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: root.setImage(selectedFile.toString(), which)
    }
    QQD.FileDialog {
        id: videoDialog
        title: root.tr("Choose a video", "Escolha um vídeo")
        nameFilters: [root.tr("Videos", "Vídeos") + " (*.mp4 *.mkv *.webm *.avi *.mov *.m4v *.gif)"]
        onAccepted: root.setVideo(selectedFile.toString())
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
        title: root.tr("Save video as", "Salvar vídeo como")
        fileMode: QQD.FileDialog.SaveFile
        nameFilters: ["MP4 (*.mp4)", "AVI (*.avi)"]
        onAccepted: if (root.current) backend.saveVideoAs(root.current.path, selectedFile.toString())
    }

    // Drop a picture (to animate) or a video (to continue) anywhere.
    DropArea {
        anchors.fill: parent
        z: 50
        enabled: !root.busy && !root.browserOpen && !root.loraGuideOpen
        onEntered: function (drag) { drag.accepted = drag.hasUrls && drag.urls.length > 0 }
        onDropped: function (drop) {
            if (!drop.hasUrls || drop.urls.length === 0) return
            var u = drop.urls[0].toString()
            if (root.isVideoUrl(u)) root.setVideo(u)
            else root.setImage(u, "start")
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
                text: root.tr("Drop a picture to animate it, or a video to continue it",
                              "Solte uma imagem pra animar, ou um vídeo pra continuar")
                font.bold: true; font.pixelSize: 16
                color: appTheme.greenBright
            }
        }
    }

    readonly property bool narrow: width < 980

    // Self-contained on purpose (see ImagePage): an inline component does not
    // see this file's ids.
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
    component SectionLabel: QQC2.Label {
        font.pixelSize: 10; font.letterSpacing: 1.1
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: 18
        columns: root.narrow ? 1 : 2
        columnSpacing: 16
        rowSpacing: 12

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                QQC2.Label {
                    text: root.tr("Video", "Vídeo")
                    color: appTheme.textHi
                    font.pixelSize: 24; font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: appTheme.textMid
                    font.pixelSize: 12
                    text: root.tr("Make a short clip from a description, bring a picture to life, or continue a video. Runs on your GPU — nothing leaves this computer.",
                                  "Crie um clipe curto a partir de uma descrição, dê vida a uma imagem, ou continue um vídeo. Roda na sua GPU — nada sai deste computador.")
                }
            }
            Chip {
                visible: root.engineReady && root.backendName !== ""
                text: root.tr("Engine: ", "Motor: ") + (root.backendName === "cuda" ? "CUDA"
                      : root.backendName === "vulkan" ? "Vulkan" : "CPU")
                tint: root.backendName === "cuda" ? appTheme.greenBright : appTheme.textMid
            }
        }

        // ── engine missing ──
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
                    text: root.tr("Install the engine", "Instale o motor")
                    color: appTheme.textHi; font.pixelSize: 16; font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textMid; font.pixelSize: 12
                    text: root.tr("Video uses the same engine as the Image page (stable-diffusion.cpp). Models are downloaded separately, only the ones you pick.",
                                  "O vídeo usa o mesmo motor da página Imagem (stable-diffusion.cpp). Os modelos são baixados à parte, só os que você escolher.")
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
                    QQC2.Label {
                        visible: root.engineState === "failed"
                        text: root.tr("Not installed — see the terminal for the reason.", "Não instalou — veja o motivo no terminal.")
                        color: appTheme.red; font.pixelSize: 11
                    }
                }
            }
        }

        // ── ffmpeg missing: MP4 and video editing need it ──
        Rectangle {
            visible: root.engineReady && root.status.ffmpeg === false
            Layout.fillWidth: true
            Layout.columnSpan: root.narrow ? 1 : 2
            implicitHeight: ffRow.implicitHeight + 18
            radius: appTheme.rMd
            color: appTheme.a(appTheme.turbo, 0.08)
            border.width: 1; border.color: appTheme.a(appTheme.turbo, 0.3)
            RowLayout {
                id: ffRow
                anchors.fill: parent; anchors.margins: 9
                spacing: 10
                FIcon { name: "alert"; size: 16; color: appTheme.turboBright }
                QQC2.Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textHi; font.pixelSize: 12
                    text: root.tr("ffmpeg is not installed: clips are saved as .avi, and \"Edit a video\" is off. Install it with: sudo pacman -S ffmpeg",
                                  "O ffmpeg não está instalado: os clipes ficam em .avi, e \"Editar um vídeo\" fica desligado. Instale com: sudo pacman -S ffmpeg")
                }
            }
        }

        // ════════════════════════ LEFT: the form ════════════════════════
        QQC2.ScrollView {
            id: formScroll
            Layout.preferredWidth: root.narrow ? -1 : 380
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
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "text",    icon: "star",  en: "From text",       pt: "De texto" },
                            { id: "image",   icon: "image", en: "Animate a picture", pt: "Animar imagem" },
                            { id: "subject", icon: "user",  en: "Person in a scene", pt: "Pessoa numa cena" },
                            { id: "video",   icon: "film",  en: "Edit a video",    pt: "Editar vídeo" }
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
                SectionLabel { color: appTheme.textLo; text: root.tr("MODEL", "MODELO") }
                Rectangle {
                    id: modelCard
                    readonly property var m: root.activeModel()
                    readonly property var v: root.installedVariant(m)
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
                                    root.filterTag = root.faceModes() ? "faces" : "all"
                                    root.browserOpen = true
                                }
                            }
                        }
                        Flow {
                            visible: !!(modelCard.m && modelCard.v)
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: modelCard.m && modelCard.v ? modelCard.m.tags : []
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
                            visible: root.faceModes() && !!modelCard.m && !!modelCard.v && !!modelCard.m.face
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textLo; font.pixelSize: 11
                            text: root.faceText(modelCard.m)
                        }
                    }
                }

                // ── animating a person: the models that keep the face, best first ──
                ColumnLayout {
                    visible: root.faceModes() && root.faceModels().length > 0
                    Layout.fillWidth: true
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        SectionLabel { color: appTheme.textLo;
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.tr("BEST AT KEEPING FACES", "MELHORES PRA MANTER ROSTOS")
                        }
                        QQC2.Label {
                            text: root.tr("See all", "Ver todos")
                            color: appTheme.greenBright; font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.filterTag = "faces"; root.browserOpen = true }
                            }
                        }
                    }
                    Repeater {
                        model: root.faceModels()
                        delegate: Rectangle {
                            id: fm
                            required property var modelData
                            readonly property bool sel: root.activeModel() && root.activeModel().id === modelData.id
                            readonly property var v: root.variantOf(modelData)
                            Layout.fillWidth: true
                            implicitHeight: fmRow.implicitHeight + 12
                            radius: appTheme.rSm
                            color: sel ? appTheme.a(appTheme.green, 0.12) : appTheme.surface
                            border.width: 1
                            border.color: sel ? appTheme.a(appTheme.green, 0.5) : appTheme.hairline
                            MouseArea {
                                anchors.fill: parent
                                enabled: fm.modelData.installed
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.modelId = fm.modelData.id
                            }
                            RowLayout {
                                id: fmRow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 9; anchors.rightMargin: 6
                                spacing: 8
                                QQC2.Label {
                                    text: root.stars(Math.max(1, fm.modelData.identity || 1))
                                    color: appTheme.turboBright; font.pixelSize: 12
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: fm.modelData.name
                                        color: appTheme.textHi; font.bold: true; font.pixelSize: 12
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: root.faceText(fm.modelData)
                                              + (fm.modelData.min_ram_gb ? "  ·  " + fm.modelData.min_ram_gb + " GB RAM" : "")
                                        color: appTheme.textMid; font.pixelSize: 10
                                    }
                                }
                                GButton {
                                    visible: !fm.modelData.installed
                                    theme: appTheme; kind: "tonal"; iconSource: "download"
                                    enabled: root.pullingId === "" && root.engineReady
                                    text: root.pullingId === fm.modelData.id
                                          ? (root.pullText || root.tr("Downloading…", "Baixando…"))
                                          : (fm.v ? root.gb(fm.v.download || fm.v.size) : root.tr("Download", "Baixar"))
                                    tooltip: root.tr("Download", "Baixar")
                                    onClicked: root.startPull(fm.modelData)
                                }
                                FIcon {
                                    visible: fm.sel
                                    name: "check"; size: 14; color: appTheme.greenBright
                                }
                            }
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        color: appTheme.textLo; font.pixelSize: 10
                        text: root.tr("Only animate people who agreed to it. Making someone appear to do or say what they did not is not allowed — see the LoRA guide.",
                                      "Só anime pessoas que concordaram. Fazer alguém parecer fazer ou dizer o que não fez não é permitido — veja o guia de LoRAs.")
                    }
                }

                // ── the picture: first frame, or the person ──
                SectionLabel { color: appTheme.textLo;
                    visible: root.mode === "image" || root.mode === "subject" || (root.mode === "video" && root.videoAction === "restyle")
                    text: root.mode === "image" ? root.tr("FIRST FRAME — THE PICTURE TO ANIMATE", "PRIMEIRO QUADRO — A IMAGEM PRA ANIMAR")
                        : root.mode === "subject" ? root.tr("THE PERSON OR OBJECT", "A PESSOA OU OBJETO")
                        : root.tr("REFERENCE PICTURE (OPTIONAL)", "IMAGEM DE REFERÊNCIA (OPCIONAL)")
                }
                Rectangle {
                    visible: root.mode === "image" || root.mode === "subject" || (root.mode === "video" && root.videoAction === "restyle")
                    Layout.fillWidth: true
                    implicitHeight: root.imagePath ? 92 : 74
                    radius: appTheme.rMd
                    color: imgMa.containsMouse ? appTheme.hover : appTheme.surface
                    border.width: 1
                    border.color: appTheme.hairline
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 10
                        spacing: 10
                        Image {
                            visible: root.imagePath !== ""
                            source: root.fileUrl(root.imagePath)
                            Layout.preferredWidth: 72; Layout.preferredHeight: 72
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 144; sourceSize.height: 144
                            asynchronous: true
                        }
                        FIcon {
                            visible: root.imagePath === ""
                            name: root.mode === "subject" ? "user" : "image"; size: 22; color: appTheme.textLo
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.imagePath ? root.imageName : root.tr("Choose or drop a picture", "Escolha ou solte uma imagem")
                                color: appTheme.textHi; font.pixelSize: 12; elide: Text.ElideMiddle
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.imagePath ? (root.imageW && root.imageH ? root.imageW + " × " + root.imageH : "")
                                    : root.mode === "subject" ? root.tr("A clear photo, the face well lit, works best", "Uma foto nítida, rosto bem iluminado, funciona melhor")
                                    : root.tr("The clip starts on exactly this frame", "O clipe começa exatamente nesse quadro")
                                color: appTheme.textLo; font.pixelSize: 10
                            }
                        }
                        GButton {
                            visible: root.imagePath !== ""
                            theme: appTheme; kind: "ghost"; iconSource: "x"
                            tooltip: root.tr("Remove", "Remover")
                            onClicked: { root.imagePath = ""; root.imageName = "" }
                        }
                    }
                    MouseArea {
                        id: imgMa
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { imageDialog.which = "start"; imageDialog.open() }
                    }
                }

                // ── image → video: optionally a last frame too ──
                ColumnLayout {
                    readonly property var m: root.activeModel()
                    visible: root.mode === "image" && !!m && root.has(m.modes, "flf2v")
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.tr("End on a picture of my own (first + last frame)", "Terminar numa imagem minha (primeiro + último quadro)")
                            color: appTheme.textMid; font.pixelSize: 12
                        }
                        GToggle {
                            theme: appTheme
                            checked: root.useEnd
                            onToggled: function (v) { root.useEnd = v }
                        }
                    }
                    Rectangle {
                        visible: root.useEnd
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: appTheme.rMd
                        color: endMa.containsMouse ? appTheme.hover : appTheme.surface
                        border.width: 1; border.color: appTheme.hairline
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8
                            spacing: 10
                            Image {
                                visible: root.endPath !== ""
                                source: root.fileUrl(root.endPath)
                                Layout.preferredWidth: 48; Layout.preferredHeight: 48
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96; sourceSize.height: 96
                                asynchronous: true
                            }
                            FIcon { visible: root.endPath === ""; name: "image"; size: 18; color: appTheme.textLo }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.endPath ? root.endName : root.tr("Choose the last frame", "Escolha o último quadro")
                                color: appTheme.textHi; font.pixelSize: 12; elide: Text.ElideMiddle
                            }
                        }
                        MouseArea {
                            id: endMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { imageDialog.which = "end"; imageDialog.open() }
                        }
                    }
                }

                // ── edit a video: what to do with it, and which one ──
                ColumnLayout {
                    visible: root.mode === "video"
                    Layout.fillWidth: true
                    spacing: 8
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        GPill {
                            icon: "arrow-down"
                            label: root.tr("Continue it", "Continuar")
                            active: root.videoAction === "extend"
                            onClicked: root.videoAction = "extend"
                        }
                        GPill {
                            icon: "refresh-cw"
                            label: root.tr("Restyle it", "Mudar o estilo")
                            active: root.videoAction === "restyle"
                            onClicked: root.videoAction = "restyle"
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        color: appTheme.textMid; font.pixelSize: 11
                        text: root.videoAction === "extend"
                            ? root.tr("Its last frame starts a new clip, and the two are joined into one longer video. Do it again to keep going.",
                                      "O último quadro dele começa um clipe novo, e os dois viram um vídeo mais longo. Repita pra continuar indo.")
                            : root.tr("Keeps the motion and framing of your video while the look follows your prompt (a VACE model).",
                                      "Mantém o movimento e o enquadramento do seu vídeo enquanto o visual segue o seu prompt (um modelo VACE).")
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: appTheme.rMd
                        color: vidMa.containsMouse ? appTheme.hover : appTheme.surface
                        border.width: 1; border.color: appTheme.hairline
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 10
                            spacing: 10
                            FIcon { name: "film"; size: 20; color: root.videoPath ? appTheme.greenBright : appTheme.textLo }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: root.videoPath ? root.videoName : root.tr("Choose or drop a video", "Escolha ou solte um vídeo")
                                    color: appTheme.textHi; font.pixelSize: 12; elide: Text.ElideMiddle
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: root.tr("MP4, MKV, WebM, AVI, MOV — or a clip from the gallery", "MP4, MKV, WebM, AVI, MOV — ou um clipe da galeria")
                                    color: appTheme.textLo; font.pixelSize: 10; elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            id: vidMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: videoDialog.open()
                        }
                    }
                }

                // ── prompt ──
                SectionLabel { color: appTheme.textLo;
                    text: root.mode === "image" || (root.mode === "video" && root.videoAction === "extend")
                        ? root.tr("WHAT HAPPENS NEXT", "O QUE ACONTECE")
                        : root.mode === "video" ? root.tr("HOW IT SHOULD LOOK", "COMO DEVE FICAR")
                        : root.tr("DESCRIBE THE CLIP", "DESCREVA O CLIPE")
                }
                Rectangle {
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
                        placeholderText: root.mode === "image"
                            ? root.tr("e.g. she turns to the camera and smiles, hair moving in the wind, slow push-in",
                                      "ex.: ela vira pra câmera e sorri, cabelo balançando no vento, câmera se aproximando devagar")
                            : root.mode === "subject"
                            ? root.tr("e.g. the man walks along a beach at sunset, tracking shot",
                                      "ex.: o homem caminha numa praia ao pôr do sol, câmera acompanhando")
                            : root.tr("e.g. a red fox runs through a snowy forest at sunrise, soft light, cinematic",
                                      "ex.: uma raposa vermelha corre numa floresta com neve ao amanhecer, luz suave, cinematográfico")
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
                    Layout.fillWidth: true
                    spacing: 8
                    GButton {
                        theme: appTheme
                        kind: "tonal"
                        iconSource: "zap"
                        enabled: !root.enhancing && prompt.text.trim().length > 0 && root.chatModel !== ""
                        text: root.enhancing ? root.tr("Improving…", "Melhorando…") : root.tr("Improve with AI", "Melhorar com IA")
                        tooltip: root.chatModel
                            ? root.tr("Your chat model rewrites the prompt in English: the motion in order, then the camera.",
                                      "Seu modelo de chat reescreve o prompt em inglês: o movimento em ordem, depois a câmera.")
                            : root.tr("Needs a chat model — download one in Models.", "Precisa de um modelo de chat — baixe um em Modelos.")
                        onClicked: {
                            root.enhancing = true
                            root.enhanceError = ""
                            backend.enhanceVideoPrompt(root.chatModel, prompt.text, root.engineMode())
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

                // ── length ──
                ColumnLayout {
                    readonly property var m: root.activeModel()
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: root.mode === "video" && root.videoAction === "extend"
                                  ? root.tr("Length to add", "Duração a acrescentar") : root.tr("Length", "Duração")
                            color: appTheme.textMid; font.pixelSize: 12
                        }
                        QQC2.Label {
                            readonly property var m: root.activeModel()
                            text: m ? root.clipSeconds(m).toFixed(1) + " s  ·  " + root.frameCount(m) + " "
                                      + root.tr("frames", "quadros") + " @ " + root.fps(m) + " fps" : ""
                            color: appTheme.textHi; font.pixelSize: 12; font.bold: true
                        }
                    }
                    QQC2.Slider {
                        readonly property var m: root.activeModel()
                        Layout.fillWidth: true
                        from: 1; to: m ? (m.max_seconds || 5) : 5; stepSize: 0.5
                        value: m ? root.clipSeconds(m) : 3
                        onMoved: root.seconds = value
                    }
                }

                // ── size and shape ──
                SectionLabel { color: appTheme.textLo; text: root.tr("SIZE", "TAMANHO") }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.sizesOf(root.activeModel())
                        delegate: GPill {
                            required property var modelData
                            label: modelData
                            active: root.sizeKey === modelData || (root.sizesOf(root.activeModel()).indexOf(root.sizeKey) < 0 && modelData === "480p")
                            onClicked: root.sizeKey = modelData
                        }
                    }
                    Repeater {
                        model: root.shapeFromAspect() ? ["16:9", "9:16", "1:1"] : []
                        delegate: GPill {
                            required property var modelData
                            label: modelData
                            active: root.aspect === modelData
                            onClicked: root.aspect = modelData
                        }
                    }
                }
                QQC2.Label {
                    visible: !root.shapeFromAspect()
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textLo; font.pixelSize: 10
                    text: root.tr("The clip keeps the shape of your picture or video.", "O clipe mantém o formato da sua imagem ou vídeo.")
                }

                // ── LoRAs (the Image page's store, filtered by base) ──
                Rectangle {
                    id: loraCard
                    readonly property var m: root.activeModel()
                    readonly property var ok: root.compatibleLoras(m)
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
                            text: loraCard.m && loraCard.m.lora_families && loraCard.m.lora_families.length === 0
                                ? root.tr("This model does not take LoRAs yet.", "Esse modelo ainda não aceita LoRAs.")
                                : root.loras.length === 0
                                ? root.tr("A LoRA adds a style, a motion or a character on top of a model. You download them yourself and import them here.",
                                          "Uma LoRA adiciona um estilo, um movimento ou um personagem em cima de um modelo. Você baixa por fora e importa aqui.")
                                : root.tr("None of your LoRAs fit this model. A video LoRA only works on the Wan size it was made for: 1.3B, 5B or 14B.",
                                          "Nenhuma das suas LoRAs serve pra esse modelo. Uma LoRA de vídeo só funciona no tamanho de Wan pra qual foi feita: 1.3B, 5B ou 14B.")
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

                // ── Turbo: the model's distillation LoRA ──
                Rectangle {
                    id: turboCard
                    readonly property var m: root.activeModel()
                    readonly property bool can: !!m && !!m.turbo && m.turbo.kind === "lora"
                    Layout.fillWidth: true
                    implicitHeight: turboCol.implicitHeight + 18
                    radius: appTheme.rMd
                    color: root.turbo && can ? appTheme.a(appTheme.turbo, 0.10) : appTheme.surface
                    border.width: 1
                    border.color: root.turbo && can ? appTheme.a(appTheme.turbo, 0.40) : appTheme.hairline
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
                                enabled: turboCard.can
                                opacity: enabled ? 1 : 0.4
                                checked: root.turbo
                                onToggled: function (v) { root.turbo = v }
                            }
                        }
                        QQC2.Label {
                            readonly property var m: root.activeModel()
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textMid; font.pixelSize: 11
                            text: !m ? ""
                                : m.turbo.kind !== "lora" ? root.tr("This model is already distilled: it runs in " + m.defaults.steps + " steps.",
                                                                    "Esse modelo já é destilado: roda em " + m.defaults.steps + " passos.")
                                : root.turbo ? root.tr("Lightning LoRA: " + m.turbo.steps + " steps instead of " + m.defaults.steps + " — several times faster, a little less detail.",
                                                       "LoRA Lightning: " + m.turbo.steps + " passos em vez de " + m.defaults.steps + " — várias vezes mais rápido, um pouco menos de detalhe.")
                                : root.tr("Off: the full " + m.defaults.steps + " steps, the best quality.",
                                          "Desligado: os " + m.defaults.steps + " passos completos, a melhor qualidade.")
                        }
                    }
                }

                // ── low memory ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: lowCol.implicitHeight + 18
                    radius: appTheme.rMd
                    color: root.lowMemory ? appTheme.a(appTheme.green, 0.06) : appTheme.surface
                    border.width: 1
                    border.color: root.lowMemory ? appTheme.a(appTheme.green, 0.30) : appTheme.hairline
                    ColumnLayout {
                        id: lowCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            FIcon { name: "cpu"; size: 14; color: root.lowMemory ? appTheme.greenBright : appTheme.textLo }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: root.tr("Low-memory mode", "Modo de pouca memória")
                                color: appTheme.textHi; font.bold: true; font.pixelSize: 12
                            }
                            GToggle {
                                theme: appTheme
                                checked: root.lowMemory
                                onToggled: function (v) {
                                    root.lowMemory = v
                                    backend.setVideoPrefs(JSON.stringify({ lowMemory: v }))
                                }
                            }
                        }
                        QQC2.Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: appTheme.textMid; font.pixelSize: 11
                            text: root.tr("Keeps the weights in RAM and moves them to the GPU piece by piece, and decodes in tiles. Slower, but fits cards with little VRAM"
                                          + (root.status.vram_mb ? " (yours: " + Math.round(root.status.vram_mb / 1024) + " GB)" : "") + ". If a run still runs out of memory, it retries by itself at 480p.",
                                          "Deixa os pesos na RAM e manda pra GPU aos pedaços, e decodifica em blocos. Mais lento, mas cabe em placas com pouca VRAM"
                                          + (root.status.vram_mb ? " (a sua: " + Math.round(root.status.vram_mb / 1024) + " GB)" : "") + ". Se ainda faltar memória, tenta de novo sozinho em 480p.")
                        }
                        RowLayout {
                            readonly property var m: root.activeModel()
                            visible: !!m && !!m.light_vae
                            Layout.fillWidth: true
                            QQC2.Label {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: root.tr("Light decoder (22 MB, much less memory, a bit softer)", "Decodificador leve (22 MB, bem menos memória, um pouco mais suave)")
                                color: appTheme.textMid; font.pixelSize: 11
                            }
                            GToggle {
                                theme: appTheme
                                checked: root.lightVae
                                onToggled: function (v) { root.lightVae = v }
                            }
                        }
                    }
                }

                // ── advanced ──
                QQC2.Label {
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
                    visible: open
                    Layout.fillWidth: true
                    spacing: 10
                    QQC2.TextField {
                        readonly property var m: root.activeModel()
                        visible: !!m && m.defaults && m.defaults.cfg > 1 && !(root.turbo && m.turbo.kind === "lora")
                        Layout.fillWidth: true
                        text: root.negative
                        placeholderText: root.tr("What to avoid (negative prompt) — the model's own list is used when empty",
                                                 "O que evitar (prompt negativo) — a lista do próprio modelo é usada se vazio")
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
                            text: root.tr("Pause the chat Turbo while making the clip (frees the GPU)",
                                          "Pausar o Turbo do chat enquanto faz o clipe (libera a GPU)")
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
                    iconSource: root.busy ? "square" : "play"
                    enabled: root.busy || root.canRun()
                    text: root.busy ? root.tr("Cancel", "Cancelar")
                        : root.mode === "video" && root.videoAction === "extend" ? root.tr("Continue the clip", "Continuar o clipe")
                        : root.mode === "video" ? root.tr("Restyle the clip", "Mudar o estilo do clipe")
                        : root.mode === "image" ? root.tr("Animate", "Animar")
                        : root.tr("Make the clip", "Criar o clipe")
                    tooltip: root.busy ? "" : root.tr("Ctrl+Enter in the prompt", "Ctrl+Enter no prompt")
                    onClicked: root.busy ? backend.cancelVideo() : root.run()
                }
                QQC2.Label {
                    visible: !root.busy && !root.canRun() && root.engineReady
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textLo; font.pixelSize: 11
                    text: root.blockReason()
                }
                QQC2.Label {
                    visible: !root.busy && root.canRun()
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: appTheme.textLo; font.pixelSize: 10
                    text: root.tr("A clip takes minutes, not seconds — longer on a small card. You can keep using the computer.",
                                  "Um clipe leva minutos, não segundos — mais numa placa pequena. Você pode continuar usando o computador.")
                }
                Item { Layout.preferredHeight: 8 }
            }
        }

        // ════════════════════════ RIGHT: player + gallery ════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 260
                radius: appTheme.rLg
                color: appTheme.a(appTheme.black, appTheme.dark ? 0.35 : 0.08)
                border.width: 1; border.color: appTheme.hairline
                clip: true

                readonly property bool playerOk: playerLoader.status === Loader.Ready && !!playerLoader.item
                                                 && !playerLoader.item.failed

                // The poster: while a clip runs, when there is no player, and
                // behind the player before its first frame.
                Image {
                    id: poster
                    anchors.fill: parent
                    anchors.margins: 12
                    source: root.current && root.current.poster ? root.fileUrl(root.current.poster) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    opacity: root.busy ? 0.35 : 1
                    visible: root.busy || !stage.playerOk
                }
                Loader {
                    id: playerLoader
                    anchors.fill: parent
                    anchors.margins: 12
                    active: !!root.current && !root.busy
                    source: active ? root.playerSource : ""
                    onLoaded: item.source = root.fileUrl(root.current ? root.current.path : "")
                }
                Connections {
                    target: root
                    function onCurrentChanged() {
                        if (playerLoader.item)
                            playerLoader.item.source = root.fileUrl(root.current ? root.current.path : "")
                    }
                }

                // no player: say so, and hand the clip to the system's player
                ColumnLayout {
                    visible: !!root.current && !root.busy && !stage.playerOk
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 40, 420)
                    spacing: 8
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: appTheme.textHi; font.pixelSize: 12
                        text: root.tr("The built-in player is not available (qt6-multimedia-ffmpeg). The clip is saved — open it in your video player.",
                                      "O player embutido não está disponível (qt6-multimedia-ffmpeg). O clipe está salvo — abra no seu player de vídeo.")
                        background: Rectangle { color: appTheme.a(appTheme.card, 0.85); radius: 8 }
                        padding: 8
                    }
                    GButton {
                        Layout.alignment: Qt.AlignHCenter
                        theme: appTheme; kind: "filled"; iconSource: "play"
                        text: root.tr("Open in player", "Abrir no player")
                        onClicked: backend.openImageExternally(root.current.path)
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 440)
                    visible: !root.current && !root.busy
                    spacing: 10
                    FIcon { Layout.alignment: Qt.AlignHCenter; name: "film"; size: 40; color: appTheme.textLo }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: appTheme.textMid; font.pixelSize: 13
                        text: !root.catalog.some(function (m) { return m.installed })
                            ? root.tr("Pick a model to start — Wan2.2 5B fits an 8 GB card; the 14B ones are the best at keeping faces.",
                                      "Escolha um modelo pra começar — o Wan2.2 5B cabe numa placa de 8 GB; os de 14B são os melhores pra manter rostos.")
                            : root.tr("Your clips appear here, and are saved in Videos › Genesi AI.",
                                      "Seus clipes aparecem aqui, e ficam salvos em Vídeos › Genesi AI.")
                    }
                    GButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !root.catalog.some(function (m) { return m.installed })
                        theme: appTheme; kind: "filled"; iconSource: "layout-grid"
                        text: root.tr("Browse models", "Ver modelos")
                        onClicked: { root.filterTag = "all"; root.browserOpen = true }
                    }
                }

                // progress over the clip
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
                                var s = Math.floor(root.elapsed / 60) + ":" + ("0" + (root.elapsed % 60)).slice(-2)
                                if (root.phase === "sample" && root.steps > 0) {
                                    s = root.tr("step ", "passo ") + root.step + "/" + root.steps + "  ·  " + s
                                    if (root.secPerStep > 0)
                                        s += "  ·  " + root.secPerStep.toFixed(1) + " s/" + root.tr("step", "passo")
                                }
                                if (root.runFrames > 0) s += "  ·  " + root.runFrames + " " + root.tr("frames", "quadros")
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

            // ── player controls ──
            RowLayout {
                visible: stage.playerOk && !root.busy
                Layout.fillWidth: true
                spacing: 8
                GButton {
                    theme: appTheme; kind: "ghost"
                    iconSource: playerLoader.item && playerLoader.item.playing ? "square" : "play"
                    tooltip: root.tr("Play / pause", "Tocar / pausar")
                    onClicked: if (playerLoader.item) playerLoader.item.toggle()
                }
                QQC2.Slider {
                    Layout.fillWidth: true
                    from: 0; to: 1
                    value: playerLoader.item && playerLoader.item.duration > 0
                           ? playerLoader.item.position / playerLoader.item.duration : 0
                    onMoved: if (playerLoader.item) playerLoader.item.seek(value)
                }
                QQC2.Label {
                    text: playerLoader.item ? (playerLoader.item.position / 1000).toFixed(1) + " / "
                                              + (playerLoader.item.duration / 1000).toFixed(1) + " s" : ""
                    color: appTheme.textMid; font.pixelSize: 11
                }
                GButton {
                    visible: !!root.current && !!root.current.audio
                    theme: appTheme; kind: "ghost"
                    text: playerLoader.item && playerLoader.item.muted ? root.tr("Sound off", "Sem som")
                                                                        : root.tr("Sound on", "Com som")
                    onClicked: if (playerLoader.item) playerLoader.item.muted = !playerLoader.item.muted
                }
            }

            // ── what went wrong ──
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
                                if (root.showLog) root.logText = backend.videoLog()
                            }
                        }
                        GButton {
                            theme: appTheme; kind: "ghost"; iconSource: "copy"
                            text: root.tr("Copy log", "Copiar log")
                            onClicked: backend.copyText(root.runError + "\n\n" + backend.videoLog())
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
                    theme: appTheme; iconSource: "arrow-down"
                    visible: root.catalog.some(function (m) { return m.installed && root.has(m.modes, "extend") })
                    text: root.tr("Continue this clip", "Continuar este clipe")
                    onClicked: root.useClip(root.current, "extend")
                }
                GButton {
                    theme: appTheme; iconSource: "refresh-cw"
                    visible: !!(root.current && root.current.mode === "t2v" && root.current.prompt)
                    text: root.tr("Variation", "Variação")
                    tooltip: root.tr("Same prompt, new seed", "Mesmo prompt, seed nova")
                    onClicked: {
                        root.reuse(root.current)
                        root.mode = "text"
                        root.lockSeed = false
                        root.run()
                    }
                }
                GButton {
                    theme: appTheme; iconSource: "save"
                    text: root.tr("Save as…", "Salvar como…")
                    onClicked: saveDialog.open()
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "external-link"
                    tooltip: root.tr("Open in the video player", "Abrir no player de vídeo")
                    onClicked: backend.openImageExternally(root.current.path)
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "folder"
                    tooltip: root.tr("Open the folder", "Abrir a pasta")
                    onClicked: backend.openVideoFolder()
                }
                GButton {
                    theme: appTheme; kind: "danger"; iconSource: "trash"
                    tooltip: root.tr("Delete", "Excluir")
                    onClicked: {
                        if (playerLoader.item) playerLoader.item.stop()
                        if (backend.deleteVideo(root.current.path)) root.current = null
                    }
                }
            }
            QQC2.Label {
                visible: root.current !== null && !root.busy && !!root.current && !!root.current.prompt
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: appTheme.textLo; font.pixelSize: 11
                text: root.current ? (root.current.prompt || "")
                      + (root.current.seed !== undefined ? "   ·   seed " + root.current.seed : "")
                      + (root.current.frames ? "   ·   " + root.current.frames + " " + root.tr("frames", "quadros") : "")
                      + (root.current.seconds ? "   ·   " + root.tr("made in ", "feito em ") + Math.round(root.current.seconds) + " s" : "") : ""
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
                    readonly property bool sel: !!(root.current && root.current.path === modelData.path)
                    width: 120; height: 88
                    radius: appTheme.rSm
                    color: appTheme.surface
                    border.width: sel ? 2 : 1
                    border.color: sel ? appTheme.green : appTheme.hairline
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        visible: !!thumb.modelData.poster
                        source: thumb.modelData.poster ? root.fileUrl(thumb.modelData.poster) : ""
                        sourceSize.width: 240; sourceSize.height: 176
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    FIcon {
                        anchors.centerIn: parent
                        visible: !thumb.modelData.poster
                        name: "film"; size: 22; color: appTheme.textLo
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                        visible: !!thumb.modelData.seconds_long
                        width: durLbl.implicitWidth + 8; height: 16; radius: 4
                        color: appTheme.a(appTheme.black, 0.65)
                        QQC2.Label {
                            id: durLbl
                            anchors.centerIn: parent
                            text: (thumb.modelData.seconds_long || 0).toFixed(1) + " s"
                            color: "white"; font.pixelSize: 9
                        }
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
                            text: root.tr("Video LoRAs — how to import", "LoRAs de vídeo — como importar")
                            color: appTheme.textHi; font.pixelSize: 20; font.bold: true
                        }
                        GButton { theme: appTheme; kind: "ghost"; iconSource: "x"; onClicked: root.loraGuideOpen = false }
                    }
                    Repeater {
                        model: [
                            { n: "1", en: "Find a LoRA on Civitai or Hugging Face. Check its BASE MODEL: Wan 2.1 1.3B, Wan 2.2 5B, or Wan 14B (Wan 2.1 14B and Wan 2.2 A14B share LoRAs). It only works on a model of that size.",
                                      pt: "Ache uma LoRA no Civitai ou no Hugging Face. Confira o BASE MODEL dela: Wan 2.1 1.3B, Wan 2.2 5B ou Wan 14B (o Wan 2.1 14B e o Wan 2.2 A14B usam as mesmas LoRAs). Ela só funciona num modelo desse tamanho." },
                            { n: "2", en: "Download the .safetensors file. Never a .ckpt or .pt: those can run code on your computer when loaded, and Genesi refuses them.",
                                      pt: "Baixe o arquivo .safetensors. Nunca .ckpt ou .pt: esses podem rodar código no seu computador quando abertos, e o Genesi recusa." },
                            { n: "3", en: "If the page lists trigger words, paste them below — Genesi adds them to your prompt when the LoRA is on.",
                                      pt: "Se a página da LoRA tiver palavras-gatilho (trigger words), cole abaixo — o Genesi coloca no seu prompt quando a LoRA estiver ligada." },
                            { n: "4", en: "Click Choose file. Genesi reads which Wan size the LoRA is for and shows it only on matching models. LoRAs are shared with the Image page.",
                                      pt: "Clique em Escolher arquivo. O Genesi lê pra qual tamanho de Wan a LoRA é e só mostra ela nos modelos que combinam. As LoRAs são as mesmas da página Imagem." },
                            { n: "5", en: "Switch it on in the LoRAs card and set its strength (0.6–1.0 is usual). On Wan2.2 A14B it is applied to both experts.",
                                      pt: "Ligue ela no card de LoRAs e ajuste a força (0,6–1,0 é o comum). No Wan2.2 A14B ela é aplicada nos dois especialistas." }
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
                                text: root.tr("• Only import files from sources you trust. .safetensors cannot run code, but a model can still be made to produce things you did not want.\n• Never animate a real person without their consent, never make anyone appear to do or say something they did not, and never make sexual or intimate content of a real person — it can be a crime, and Genesi's terms of use forbid it. Sexual content involving minors is forbidden, always.\n• Do not use clips to deceive, harass or impersonate anyone.\n• Respect each LoRA's and each model's licence (some forbid commercial use).\n• Everything runs on this computer: Genesi does not see, store or send your clips or prompts — and so you are responsible for what you make.",
                                              "• Só importe arquivos de fontes em que você confia. .safetensors não roda código, mas um modelo ainda pode ser feito pra gerar coisas que você não queria.\n• Nunca anime uma pessoa real sem o consentimento dela, nunca faça alguém parecer fazer ou dizer algo que não fez, e nunca faça conteúdo sexual ou íntimo de uma pessoa real — pode ser crime, e os termos de uso do Genesi proíbem. Conteúdo sexual envolvendo menores é proibido, sempre.\n• Não use clipes pra enganar, assediar ou se passar por alguém.\n• Respeite a licença de cada LoRA e de cada modelo (algumas proíbem uso comercial).\n• Tudo roda neste computador: o Genesi não vê, não guarda e não envia seus clipes nem seus prompts — por isso a responsabilidade pelo que você cria é sua.")
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
                        placeholderText: root.tr("Trigger words (optional), e.g. dolly zoom, anime style",
                                                 "Palavras-gatilho (opcional), ex.: dolly zoom, anime style")
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
                    SectionLabel { color: appTheme.textLo;
                        visible: root.loras.length > 0
                        text: root.tr("YOUR LORAS", "SUAS LORAS")
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
                        text: root.tr("Video models", "Modelos de vídeo")
                        color: appTheme.textHi; font.pixelSize: 20; font.bold: true
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
                                  + (root.status.vram_mb ? " (" + Math.round(root.status.vram_mb / 1024) + " GB)" : "")
                                  + ". Bigger models still run on a small card in low-memory mode, only slower — RAM is the limit.",
                                  "Cada modelo só é baixado quando você pedir. A variante escolhe tamanho × qualidade — a recomendada cabe na sua GPU"
                                  + (root.status.vram_mb ? " (" + Math.round(root.status.vram_mb / 1024) + " GB)" : "")
                                  + ". Modelos maiores ainda rodam numa placa pequena no modo de pouca memória, só mais devagar — o limite é a RAM.")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "all", en: "All", pt: "Todos" },
                            { id: "installed", en: "Downloaded", pt: "Baixados" },
                            { id: "fits", en: "Fit my GPU", pt: "Cabem na minha GPU" },
                            { id: "faces", en: "Keep faces", pt: "Mantêm rostos" },
                            { id: "i2v", en: "Image to video", pt: "Imagem pra vídeo" },
                            { id: "fast", en: "Fast", pt: "Rápidos" },
                            { id: "edit", en: "Edit video", pt: "Editam vídeo" },
                            { id: "audio", en: "With sound", pt: "Com som" }
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
                                        // How well it keeps a face from your picture.
                                        Chip {
                                            visible: !!card.modelData.face
                                            text: root.stars(Math.max(1, card.modelData.identity || 1)) + " "
                                                  + (card.modelData.face === "subject"
                                                     ? root.tr("KEEPS A PERSON FROM A PHOTO", "MANTÉM UMA PESSOA DA FOTO")
                                                     : (card.modelData.identity || 0) >= 3 ? root.tr("BEST FOR FACES", "MELHOR PRA ROSTOS")
                                                     : root.tr("KEEPS THE FACE", "MANTÉM O ROSTO"))
                                            tint: appTheme.turboBright
                                        }
                                        Repeater {
                                            model: card.modelData.tags.filter(function (t) { return t !== "faces" })
                                            delegate: Chip {
                                                required property var modelData
                                                text: root.tagLabel(modelData)
                                                tint: root.tagColor(modelData)
                                            }
                                        }
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Repeater {
                                            model: card.modelData.modes
                                            delegate: Chip {
                                                required property var modelData
                                                text: root.modeLabel(modelData)
                                                tint: appTheme.textLo
                                            }
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
                                            + "  ·  " + card.modelData.fps + " fps, " + root.tr("up to ", "até ") + card.modelData.max_seconds + " s"
                                            + (card.v ? "  ·  GPU " + root.gb(card.v.gpu_size) : "")
                                            + (card.ramShort ? "  ·  " + root.tr("needs " + card.modelData.min_ram_gb + " GB RAM (you have " + root.ramGb() + ")",
                                                                                 "precisa de " + card.modelData.min_ram_gb + " GB de RAM (você tem " + root.ramGb() + ")") : "")
                                    }
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
                                    // A Binding, not `currentIndex:` (see ImagePage).
                                    Binding {
                                        target: variantBox
                                        property: "currentIndex"
                                        value: {
                                            for (var i = 0; i < card.modelData.variants.length; i++)
                                                if (card.v && card.modelData.variants[i].id === card.v.id) return i
                                            return 0
                                        }
                                    }
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
                                                onClicked: backend.cancelVideoPull()
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
                                            enabled: root.pullingId === ""
                                            text: (card.v && card.v.partial ? root.tr("Resume", "Continuar") : root.tr("Download", "Baixar"))
                                                  + (card.v ? " · " + root.gb(card.v.download || card.v.size) : "")
                                            onClicked: root.startPull(card.modelData)
                                        }
                                        GButton {
                                            theme: appTheme; kind: "filled"; iconSource: "check"
                                            visible: !!card.v && card.v.installed
                                            text: root.tr("Use", "Usar")
                                            onClicked: {
                                                root.modelId = card.modelData.id
                                                if (!root.fitsMode(card.modelData, root.mode)) {
                                                    var md = card.modelData.modes
                                                    root.mode = root.has(md, "i2v") ? "image" : root.has(md, "t2v") ? "text"
                                                              : root.has(md, "r2v") ? "subject" : "video"
                                                }
                                                root.browserOpen = false
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        GButton {
                                            theme: appTheme; kind: "ghost"; iconSource: "trash"
                                            visible: card.modelData.installed || card.modelData.partial
                                            enabled: root.pullingId === ""
                                            tooltip: root.tr("Delete the downloaded files", "Apagar os arquivos baixados")
                                            onClicked: backend.removeVideoModel(card.modelData.id, "")
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
