/*
 * Genesi AI Mode Monitor — Model Advisor + downloader + GGUF library.
 * Shows `genesi-ai-mode advise` (which model fits 100% on this GPU/CPU), lets
 * you pull a model straight from the app (Ollama /api/pull) — no terminal — and
 * use ANY .gguf on the machine (a Hugging Face download, dragged onto the
 * window) without importing it into Ollama first.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QQD
import org.kde.kirigami as Kirigami

Kirigami.Page {
    id: page
    title: "Models"
    padding: 0

    // appTheme, not `theme`: a component that HAS a `theme` property
    // (GButton, StudioCard, StatusBanner, GlassCard) resolves a bare
    // `theme` on the right-hand side to its own UNSET property, not to
    // this id -- so `theme: appTheme` binds the property to itself and every
    // sibling binding reading appTheme.x gets undefined.
    Theme { id: appTheme }
    // Shared I18n instance passed in from Main (keeps the language switch in sync).
    property var i18n
    property bool pulling: false

    // Did the advisor FAIL, as opposed to having nothing to say? The backend
    // returns "" when the CLI is simply not installed and an "error ..." line
    // only when a real call went wrong, so the two states are distinguishable
    // without guessing.
    readonly property bool advFailed: area.text.indexOf("error querying the advisor") === 0

    // ── local GGUF library ──
    // Emitted when the user picks a GGUF to run: Main switches Turbo to it.
    // GGUF models only work through Turbo (llama-server loads the file directly;
    // Ollama's chat API only knows its own registry), so Main turns Turbo on.
    signal useGguf(string path, string label)

    property var ggufModels: []
    property bool ggufImporting: false
    property string ggufStatus: ""
    property string ggufError: ""
    // The GGUF currently selected for Turbo, so the list can show which is live.
    property string activeGguf: ""

    function refreshGguf() { backend.loadGgufModels() }
    function addGguf(src) {
        if (page.ggufImporting || !src || src.length === 0)
            return
        page.ggufImporting = true
        page.ggufError = ""
        page.ggufStatus = i18n.t("gguf.adding")
        backend.importGguf(src, false)
    }
    // Colour + short label for how a model will actually run on this machine.
    function fitColor(fit) {
        if (fit === "gpu")   return appTheme.green
        if (fit === "moe")   return appTheme.turbo
        if (fit === "spill") return appTheme.sevLow
        return appTheme.blue
    }
    function fitLabel(fit) {
        if (fit === "gpu")   return i18n.t("gguf.fitGpu")
        if (fit === "moe")   return i18n.t("gguf.fitMoe")
        if (fit === "spill") return i18n.t("gguf.fitSpill")
        return i18n.t("gguf.fitCpu")
    }

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: appTheme.bgTop }
            GradientStop { position: 1.0; color: appTheme.bgBottom }
        }
    }

    function reload() { area.text = backend.advise() }
    function pull() {
        var m = modelInput.text.trim()
        if (page.pulling || m.length === 0)
            return
        page.pulling = true
        status.text = i18n.t("adv.startingPre") + m + " …"
        backend.pullModel(m)
    }

    Component.onCompleted: { reload(); page.refreshGguf() }

    Connections {
        target: backend
        function onPullStatus(s) { status.text = s }
        function onPullDone(ok) {
            page.pulling = false
            if (ok) {
                backend.loadModels()
                modelInput.text = ""
            }
        }
        function onGgufModels(jsonStr) {
            var arr = []
            try { arr = JSON.parse(jsonStr) } catch (e) {}
            page.ggufModels = arr
        }
        function onGgufImportStatus(s) { page.ggufStatus = s }
        function onGgufImportDone(ok, msg) {
            page.ggufImporting = false
            page.ggufStatus = ok ? i18n.t("gguf.added") + " " + msg : ""
            page.ggufError = ok ? "" : msg
            if (ok)
                ggufUrl.text = ""
        }
    }

    // Pick a .gguf from disk. nameFilters keeps the dialog honest — Genesi serves
    // GGUF weights, not safetensors.
    QQD.FileDialog {
        id: ggufDialog
        title: i18n.t("gguf.pick")
        nameFilters: ["GGUF models (*.gguf)"]
        onAccepted: page.addGguf(selectedFile.toString())
    }

    // Drag a .gguf straight from the file manager / browser download onto the page.
    DropArea {
        anchors.fill: parent
        z: 100
        onEntered: function (drag) {
            drag.accepted = drag.hasUrls && drag.urls.length > 0
                && drag.urls[0].toString().toLowerCase().endsWith(".gguf")
        }
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length > 0)
                page.addGguf(drop.urls[0].toString())
        }
        Rectangle {
            anchors.fill: parent
            visible: parent.containsDrag
            radius: 16
            color: appTheme.a(appTheme.green, 0.10)
            border.width: 2
            border.color: appTheme.a(appTheme.green, 0.55)
            QQC2.Label {
                anchors.centerIn: parent
                text: i18n.t("gguf.drop")
                font.bold: true
                font.pixelSize: 16
                color: appTheme.greenBright
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // ── Download bar ──
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: dlCol.implicitHeight + Kirigami.Units.largeSpacing * 2
            accent: appTheme.green
            active: page.pulling

            ColumnLayout {
                id: dlCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        width: 40; height: 40; radius: 12
                        color: appTheme.a(appTheme.green, 0.12)
                        border.color: appTheme.a(appTheme.green, 0.4); border.width: 1
                        Kirigami.Icon { anchors.centerIn: parent; source: "download"; width: 20; height: 20; color: appTheme.greenBright }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 21
                        color: appTheme.card
                        border.width: 1
                        border.color: modelInput.activeFocus ? appTheme.green : appTheme.line
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        QQC2.TextField {
                            id: modelInput
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            color: appTheme.textHi
                            placeholderText: i18n.t("adv.placeholder")
                            placeholderTextColor: appTheme.textLo
                            enabled: !page.pulling
                            onAccepted: page.pull()
                        }
                    }

                    Rectangle {
                        id: pullBtn
                        readonly property bool hasModel: modelInput.text.trim().length > 0
                        readonly property bool canPull: !page.pulling && hasModel
                        implicitWidth: pullLbl.implicitWidth + 34
                        implicitHeight: 42
                        radius: 21
                        color: page.pulling ? appTheme.a(appTheme.green, 0.22)
                             : (hasModel ? appTheme.a(appTheme.green, 0.18) : appTheme.a(appTheme.textHi, 0.10))
                        border.width: 1
                        border.color: page.pulling || hasModel ? appTheme.a(appTheme.green, 0.44) : appTheme.line
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            QQC2.Label {
                                text: page.pulling ? "..." : "↓"
                                font.bold: true
                                font.pixelSize: 18
                                color: page.pulling || pullBtn.hasModel ? appTheme.greenBright : appTheme.textLo
                            }
                            QQC2.Label {
                                id: pullLbl
                                text: page.pulling ? i18n.t("adv.downloading") : i18n.t("adv.download")
                                font.bold: true
                                color: page.pulling || pullBtn.hasModel ? appTheme.textHi : appTheme.textLo
                            }
                        }
                        MouseArea { anchors.fill: parent; enabled: pullBtn.canPull; cursorShape: Qt.PointingHandCursor; onClicked: page.pull() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: status.text.length > 0 || page.pulling
                    implicitHeight: 34
                    radius: 10
                    color: appTheme.a(appTheme.green, page.pulling ? 0.14 : 0.08)
                    border.width: 1
                    border.color: appTheme.a(appTheme.green, page.pulling ? 0.40 : 0.22)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        QQC2.BusyIndicator {
                            running: page.pulling
                            visible: page.pulling
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                        }
                        QQC2.Label {
                            id: status
                            Layout.fillWidth: true
                            text: ""
                            color: appTheme.textHi
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ── Local GGUF library ──
        // The point of this card: a model downloaded from Hugging Face is usable
        // here directly. That matters most for MoE models — the quants that make
        // a 30B-A3B fast on a small card live on HF, and Ollama's runner doesn't
        // expose the expert-offload flag Turbo uses to run them.
        GlassCard {
            Layout.fillWidth: true
            Layout.preferredHeight: ggufCol.implicitHeight + Kirigami.Units.largeSpacing * 2
            accent: appTheme.green
            active: page.ggufImporting

            ColumnLayout {
                id: ggufCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: "folder-download"
                        color: appTheme.greenBright
                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                    }
                    QQC2.Label {
                        text: i18n.t("gguf.title")
                        font.bold: true; font.pixelSize: 14; color: appTheme.textHi
                    }
                    Rectangle {
                        visible: page.ggufModels.length > 0
                        implicitWidth: cntLbl.implicitWidth + 14; implicitHeight: 20
                        radius: 10
                        color: appTheme.a(appTheme.green, 0.16)
                        QQC2.Label {
                            id: cntLbl
                            anchors.centerIn: parent
                            text: page.ggufModels.length
                            font.pixelSize: 11; font.bold: true
                            color: appTheme.greenBright
                        }
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.ToolButton {
                        icon.name: "folder-open"
                        onClicked: backend.openGgufFolder()
                        QQC2.ToolTip.text: i18n.t("gguf.openFolder")
                        QQC2.ToolTip.visible: hovered
                    }
                    QQC2.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: page.refreshGguf()
                        QQC2.ToolTip.text: i18n.t("gguf.rescan")
                        QQC2.ToolTip.visible: hovered
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n.t("gguf.subtitle")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: appTheme.textLo
                }

                // Add: file picker, or paste a direct .gguf URL.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    GButton {
                        theme: appTheme
                        kind: "filled"
                        text: i18n.t("gguf.addFile")
                        accent: appTheme.green
                        enabled: !page.ggufImporting
                        onClicked: ggufDialog.open()
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 19
                        color: appTheme.card
                        border.width: 1
                        border.color: ggufUrl.activeFocus ? appTheme.green : appTheme.line
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        QQC2.TextField {
                            id: ggufUrl
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            background: null
                            color: appTheme.textHi
                            placeholderText: i18n.t("gguf.urlPlaceholder")
                            placeholderTextColor: appTheme.textLo
                            enabled: !page.ggufImporting
                            onAccepted: page.addGguf(text.trim())
                        }
                    }

                    GButton {
                        theme: appTheme
                        text: page.ggufImporting ? i18n.t("gguf.adding") : i18n.t("gguf.add")
                        accent: appTheme.green
                        enabled: !page.ggufImporting && ggufUrl.text.trim().length > 0
                        onClicked: page.addGguf(ggufUrl.text.trim())
                    }
                }

                // Import progress / failure.
                Rectangle {
                    Layout.fillWidth: true
                    visible: page.ggufImporting || page.ggufStatus.length > 0
                             || page.ggufError.length > 0
                    implicitHeight: 32
                    radius: 10
                    readonly property color tone: page.ggufError.length > 0 ? appTheme.red
                                                                            : appTheme.turbo
                    color: appTheme.a(tone, 0.10)
                    border.width: 1
                    border.color: appTheme.a(tone, 0.34)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        QQC2.BusyIndicator {
                            running: page.ggufImporting
                            visible: page.ggufImporting
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: page.ggufError.length > 0 ? page.ggufError : page.ggufStatus
                            color: page.ggufError.length > 0 ? appTheme.red : appTheme.textHi
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                // Empty state — tell the user where to put files.
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: page.ggufModels.length === 0 && !page.ggufImporting
                    text: i18n.t("gguf.empty")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    font.italic: true
                    color: appTheme.textLo
                }

                // The library itself.
                ListView {
                    id: ggufList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 260)
                    visible: page.ggufModels.length > 0
                    clip: true
                    spacing: 6
                    model: page.ggufModels
                    // QtQuick.Controls is imported qualified, so the ATTACHED type
                    // has to be qualified too — a bare `ScrollBar.vertical` is a
                    // "Non-existent attached object" load error, not a warning.
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                    delegate: Rectangle {
                        id: ggufRow
                        width: ggufList.width
                        implicitHeight: rowCol.implicitHeight + 16
                        radius: 12
                        readonly property bool isActive: page.activeGguf === modelData.path
                        color: isActive ? appTheme.a(appTheme.turbo, 0.12) : appTheme.card
                        border.width: 1
                        border.color: isActive ? appTheme.a(appTheme.turbo, 0.45) : appTheme.line

                        ColumnLayout {
                            id: rowCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                QQC2.Label {
                                    text: modelData.name
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: appTheme.textHi
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }
                                // MoE is the headline property on a small card —
                                // it is why a 30B model can be usable at all here.
                                Rectangle {
                                    visible: modelData.moe
                                    implicitWidth: moeLbl.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: 9
                                    color: appTheme.a(appTheme.turbo, 0.18)
                                    QQC2.Label {
                                        id: moeLbl
                                        anchors.centerIn: parent
                                        text: "MoE"
                                        font.pixelSize: 9; font.bold: true
                                        color: appTheme.greenBright
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    implicitWidth: fitLbl.implicitWidth + 14
                                    implicitHeight: 18
                                    radius: 9
                                    color: appTheme.a(page.fitColor(modelData.fit), 0.16)
                                    QQC2.Label {
                                        id: fitLbl
                                        anchors.centerIn: parent
                                        text: page.fitLabel(modelData.fit)
                                        font.pixelSize: 9; font.bold: true
                                        color: page.fitColor(modelData.fit)
                                    }
                                }
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                text: [modelData.params_b > 0 ? modelData.params_b + "B" : "",
                                       modelData.quant,
                                       modelData.size_gb + " GB",
                                       modelData.arch].filter(function (s) {
                                    return s && s.length > 0
                                }).join("  ·  ")
                                font.pixelSize: 10
                                color: appTheme.textMid
                                elide: Text.ElideRight
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.fit_detail || ""
                                wrapMode: Text.WordWrap
                                font.pixelSize: 10
                                color: appTheme.textLo
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 6
                                GButton {
                                    theme: appTheme
                                    kind: ggufRow.isActive ? "tonal" : "filled"
                                    text: ggufRow.isActive ? i18n.t("gguf.inUse")
                                                           : i18n.t("gguf.use")
                                    accent: appTheme.green
                                    enabled: !ggufRow.isActive
                                    onClicked: page.useGguf(modelData.path, modelData.name)
                                }
                                Item { Layout.fillWidth: true }
                                QQC2.ToolButton {
                                    // Only files Genesi itself copied in are
                                    // deletable — we never delete a download the
                                    // user parked somewhere else.
                                    visible: modelData.in_library
                                    icon.name: "edit-delete"
                                    onClicked: backend.removeGguf(modelData.path)
                                    QQC2.ToolTip.text: i18n.t("gguf.remove")
                                    QQC2.ToolTip.visible: hovered
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Advisor output ──
        GlassCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "help-about"; color: appTheme.green; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                    QQC2.Label { text: i18n.t("adv.title"); font.bold: true; font.pixelSize: 14; color: appTheme.textHi }
                    Item { Layout.fillWidth: true }
                    QQC2.ToolButton {
                        icon.name: "view-refresh"
                        onClicked: page.reload()
                        QQC2.ToolTip.text: i18n.t("adv.reload")
                        QQC2.ToolTip.visible: hovered
                    }
                }

                // An error is a STATE, not the advisor's answer. It used to be
                // rendered as the prose the advisor had produced, so a missing
                // CLI looked like advice about your hardware.
                Rectangle {
                    visible: page.advFailed
                    Layout.fillWidth: true
                    implicitHeight: advErrRow.implicitHeight + appTheme.sp4
                    radius: appTheme.rMd
                    color: appTheme.a(appTheme.red, 0.10)
                    border.width: 1
                    border.color: appTheme.a(appTheme.red, 0.35)
                    RowLayout {
                        id: advErrRow
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: appTheme.sp3; anchors.rightMargin: appTheme.sp3
                        spacing: appTheme.sp3
                        FIcon { name: "alert"; size: 16; color: appTheme.red }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: area.text
                            color: appTheme.textMid
                            font.pixelSize: appTheme.fsSmall
                            wrapMode: Text.WordWrap
                        }
                        GButton {
                            theme: appTheme
                            kind: "ghost"
                            text: i18n.t("adv.reload")
                            onClicked: page.reload()
                        }
                    }
                }

                QQC2.ScrollView {
                    visible: !page.advFailed && area.text.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    QQC2.TextArea {
                        id: area
                        readOnly: true
                        // WordWrap, not NoWrap. The advisor answers in
                        // sentences, and NoWrap sent every one of them off the
                        // right edge of a card that is already full width --
                        // including its failures, which is how "error querying
                        // the advisor: [WinError 2] The system cannot find the
                        // file specified" ended up as the page's only content.
                        wrapMode: Text.WordWrap
                        textFormat: TextEdit.PlainText
                        selectByMouse: true
                        font.family: appTheme.mono
                        font.pixelSize: appTheme.fsBody
                        color: appTheme.textMid
                        background: null
                    }
                }

                // Empty state. A blank card under a heading tells the user
                // nothing about whether it is loading, broken or simply has
                // nothing to say yet.
                ColumnLayout {
                    visible: area.text.length === 0 && !page.advFailed
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: appTheme.sp2
                    Item { Layout.fillHeight: true }
                    FIcon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "cpu"; size: 26; color: appTheme.a(appTheme.textLo, 0.55)
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: i18n.t("adv.empty")
                        color: appTheme.textLo
                        font.pixelSize: appTheme.fsSmall
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
