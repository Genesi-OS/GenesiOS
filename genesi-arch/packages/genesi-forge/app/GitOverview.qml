/*
 * Genesi Forge — project Overview: the full git panel from the v2 mock.
 * Header card (repo identity + branch + sync state), stat chips, a tabbed work
 * card (Changes with staging + diff viewer + commit box · History · File Tree ·
 * Compare) with Fetch/Pull/Push, an embedded terminal, and a right rail with
 * Repository info, Quick Actions, Branches and Recent Commits.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    property var project
    signal openBranches()

    property string tab: "changes"
    property var files: []
    property var log: []
    property var branches: []
    property var stashes: []
    property string selFile: ""
    property bool selStaged: false
    property var diffModel: []
    property var checkedMap: ({})
    property bool newBranchOpen: false
    property string compareText: ""

    function isChecked(f) { return checkedMap[f] === undefined ? true : checkedMap[f] }
    function setChecked(f, v) {
        var m = {}
        for (var k in checkedMap) m[k] = checkedMap[k]
        m[f] = v
        checkedMap = m
    }
    function checkedFiles() {
        var out = []
        for (var i = 0; i < files.length; i++)
            if (isChecked(files[i].file)) out.push(files[i].file)
        return out
    }
    function group(kind) {
        var out = []
        for (var i = 0; i < files.length; i++) {
            var f = files[i]
            var del = f.x === "D" || f.y === "D"
            var cat = f.untracked ? "new" : (del ? "del" : "mod")
            if (cat === kind) out.push(f)
        }
        return out
    }

    function refresh() {
        if (!project) return
        try { files = JSON.parse(backend.gitStatusList(project.path)) } catch (e) { files = [] }
        try { log = JSON.parse(backend.gitLog(project.path, 30)) } catch (e) { log = [] }
        try { branches = JSON.parse(backend.gitBranches(project.path)) } catch (e) { branches = [] }
        try { stashes = JSON.parse(backend.gitStashList(project.path)) } catch (e) { stashes = [] }
        var still = false
        for (var i = 0; i < files.length; i++) if (files[i].file === selFile) still = true
        if (!still) selFile = files.length ? files[0].file : ""
        loadDiff()
    }

    function loadDiff() {
        if (!project || selFile === "") { diffModel = []; return }
        var text = backend.gitDiff(project.path, selFile, selStaged)
        diffModel = buildDiff(text)
    }

    function buildDiff(text) {
        var rows = [], o = 0, n = 0
        var arr = text.split("\n")
        for (var i = 0; i < arr.length; i++) {
            var L = arr[i]
            if (L.indexOf("@@") === 0) {
                var m = L.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
                if (m) { o = parseInt(m[1]); n = parseInt(m[2]); rows.push({ t: "hunk", o: -1, n: -1, text: L }) }
            } else if (L.indexOf("+++") === 0 || L.indexOf("---") === 0 || L.indexOf("diff ") === 0
                       || L.indexOf("index ") === 0 || L.indexOf("new file") === 0
                       || L.indexOf("deleted") === 0 || L.indexOf("\\") === 0 || L === "") {
                // skip metadata
            } else if (L[0] === "+") {
                rows.push({ t: "add", o: -1, n: n++, text: L.substring(1) })
            } else if (L[0] === "-") {
                rows.push({ t: "del", o: o++, n: -1, text: L.substring(1) })
            } else {
                rows.push({ t: "ctx", o: o++, n: n++, text: L.substring(1) })
            }
            if (rows.length > 1200) break
        }
        return rows
    }

    function fmtAgo(epoch) {
        if (!epoch) return "—"
        var s = Math.max(1, Math.floor(Date.now() / 1000) - epoch)
        if (s < 60) return s + "s ago"
        var m = Math.floor(s / 60); if (m < 60) return m + "m ago"
        var h = Math.floor(m / 60); if (h < 24) return h + " hours ago"
        return Math.floor(h / 24) + " days ago"
    }

    onProjectChanged: refresh()
    Component.onCompleted: refresh()

    RowLayout {
        anchors.fill: parent
        spacing: 14

        // ═══════════ Main column ═══════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── Header card ────────────────────────────────────────────
            FCard {
                theme: root.theme
                Layout.fillWidth: true
                implicitHeight: 84
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18; anchors.rightMargin: 18
                    spacing: 14
                    TechLogo { kind: root.project ? root.project.stackKind : "git"
                        color: root.project ? root.project.stackColor : "#888"; size: 46 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 9
                            QQC2.Label { text: root.project ? root.project.name : ""; color: root.theme.textHi
                                font.family: root.theme.display; font.pixelSize: 19; font.bold: true }
                            Rectangle {
                                visible: root.project !== null
                                width: stackLbl.implicitWidth + 16; height: 20; radius: 6
                                color: root.theme.a(root.project ? root.project.stackColor : root.theme.green, 0.13)
                                QQC2.Label { id: stackLbl; anchors.centerIn: parent
                                    text: root.project ? root.project.stack : ""
                                    color: Qt.lighter(root.project ? root.project.stackColor : root.theme.green, 1.25)
                                    font.pixelSize: 10; font.bold: true }
                            }
                        }
                        QQC2.Label {
                            text: root.project ? (root.project.shortPath + "  ·  " + (root.project.hasGit ? "Git Repository" : "No git yet")) : ""
                            color: root.theme.textLo; font.pixelSize: 12
                            Layout.fillWidth: true; elide: Text.ElideMiddle
                        }
                    }
                    // Branch pill → opens the Branches page
                    Rectangle {
                        visible: root.project && root.project.hasGit
                        width: brRow.implicitWidth + 26; height: 34; radius: 9
                        color: brMa.containsMouse ? root.theme.cardHi : root.theme.card
                        border.width: 1; border.color: root.theme.lineHi
                        RowLayout {
                            id: brRow
                            anchors.centerIn: parent; spacing: 7
                            FIcon { name: "git-branch"; size: 13; color: root.theme.greenBright }
                            QQC2.Label { text: root.project ? root.project.branch : ""; color: root.theme.textHi; font.pixelSize: 12; font.bold: true }
                            FIcon { name: "chevron-down"; size: 12; color: root.theme.textLo }
                        }
                        MouseArea { id: brMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: root.openBranches() }
                    }
                    // Sync pill
                    Rectangle {
                        visible: root.project && root.project.hasGit
                        readonly property bool clean: root.project && root.project.ahead === 0 && root.project.behind === 0
                        width: syncRow.implicitWidth + 24; height: 34; radius: 9
                        color: root.theme.a(clean ? root.theme.green : root.theme.turbo, 0.13)
                        border.width: 1; border.color: root.theme.a(clean ? root.theme.green : root.theme.turbo, 0.35)
                        RowLayout {
                            id: syncRow
                            anchors.centerIn: parent; spacing: 6
                            FIcon { name: parent.parent.clean ? "check" : "refresh-cw"; size: 12
                                color: parent.parent.clean ? root.theme.greenBright : root.theme.turboBright }
                            QQC2.Label {
                                text: parent.parent.clean ? "Up to date"
                                    : ("↑" + root.project.ahead + " ↓" + root.project.behind)
                                color: parent.parent.clean ? root.theme.greenBright : root.theme.turboBright
                                font.pixelSize: 12; font.bold: true
                            }
                        }
                    }
                }
            }

            // ── Stat chips ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Repeater {
                    model: root.project ? [
                        { label: "Current Branch",      value: root.project.branch || "—" },
                        { label: "Last Commit",         value: root.project.lastHash || "—", sub: root.fmtAgo(root.project.lastTime) },
                        { label: "Uncommitted Changes", value: root.files.length + " files" },
                        { label: "Stashed Changes",     value: String(root.stashes.length) },
                        { label: "Remote",              value: root.project.remote ? "origin" : "none", dot: root.project.remote !== "" }
                    ] : []
                    delegate: FCard {
                        theme: root.theme
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        implicitHeight: 64
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            anchors.topMargin: 10; anchors.bottomMargin: 10
                            spacing: 2
                            QQC2.Label { text: modelData.label; color: root.theme.textLo; font.pixelSize: 10; font.bold: true }
                            RowLayout {
                                spacing: 7
                                Rectangle { visible: modelData.dot === true; width: 8; height: 8; radius: 4; color: root.theme.greenBright }
                                QQC2.Label { text: modelData.value; color: root.theme.textHi; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                QQC2.Label { visible: modelData.sub !== undefined; text: modelData.sub || ""; color: root.theme.textLo; font.pixelSize: 10 }
                            }
                        }
                    }
                }
            }

            // ── Work card: tabs + content ──────────────────────────────
            FCard {
                theme: root.theme
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // Tab bar + git actions
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [ { k: "changes", l: "Changes" }, { k: "history", l: "History" },
                                     { k: "tree", l: "File Tree" }, { k: "compare", l: "Compare" } ]
                            delegate: Rectangle {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: tabLbl.implicitWidth + 26
                                radius: 8
                                color: root.tab === modelData.k ? root.theme.mix(root.theme.card, root.theme.green, 0.18) : "transparent"
                                border.width: 1
                                border.color: root.tab === modelData.k ? root.theme.a(root.theme.green, 0.4) : "transparent"
                                QQC2.Label { id: tabLbl; anchors.centerIn: parent; text: modelData.l
                                    color: root.tab === modelData.k ? root.theme.textHi : root.theme.textMid
                                    font.pixelSize: 13; font.bold: root.tab === modelData.k }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.tab = modelData.k; if (modelData.k === "changes") root.refresh() } }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        GButton { theme: root.theme; kind: "ghost"; text: "Fetch"; iconSource: "icons/rotate-ccw.svg"
                            enabled: root.project && root.project.hasGit; onClicked: backend.fetch(root.project.path) }
                        GButton { theme: root.theme; kind: "filled"; text: "Pull"; iconSource: "icons/arrow-down.svg"
                            enabled: root.project && root.project.hasGit; onClicked: backend.pull(root.project.path) }
                        GButton { theme: root.theme; kind: "filled"; text: "Push"; iconSource: "icons/arrow-up.svg"
                            enabled: root.project && root.project.hasGit; onClicked: backend.push(root.project.path) }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.line }

                    StackLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        currentIndex: root.tab === "changes" ? 0 : root.tab === "history" ? 1 : root.tab === "tree" ? 2 : 3

                        // ── Changes: files + commit | diff ─────────────
                        RowLayout {
                            spacing: 12

                            ColumnLayout {
                                Layout.preferredWidth: 280
                                Layout.fillHeight: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.Label { text: "Changes (" + root.files.length + ")"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                                    QQC2.Label {
                                        text: "Select All"; color: root.theme.greenBright; font.pixelSize: 11; font.bold: true
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { var m = {}; for (var i = 0; i < root.files.length; i++) m[root.files[i].file] = true; root.checkedMap = m } }
                                    }
                                }

                                QQC2.ScrollView {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    contentWidth: availableWidth
                                    clip: true
                                    ColumnLayout {
                                        width: 264
                                        spacing: 3
                                        Repeater {
                                            model: [ { k: "mod", label: "Modified" }, { k: "new", label: "New Files" }, { k: "del", label: "Deleted" } ]
                                            delegate: ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                property var items: root.group(modelData.k)
                                                property string glabel: modelData.label
                                                property string gkind: modelData.k
                                                visible: items.length > 0
                                                QQC2.Label { text: parent.glabel + " (" + parent.items.length + ")"
                                                    color: root.theme.textLo; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
                                                Repeater {
                                                    model: parent.items
                                                    delegate: Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 32
                                                        radius: 7
                                                        color: root.selFile === modelData.file ? root.theme.mix(root.theme.card, root.theme.green, 0.14)
                                                             : (fMa.containsMouse ? root.theme.cardHi : "transparent")
                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8; anchors.rightMargin: 8
                                                            spacing: 8
                                                            Rectangle {
                                                                width: 15; height: 15; radius: 4
                                                                color: root.isChecked(modelData.file) ? root.theme.green : "transparent"
                                                                border.width: 1.5
                                                                border.color: root.isChecked(modelData.file) ? root.theme.green : root.theme.lineHi
                                                                FIcon { anchors.centerIn: parent; visible: root.isChecked(modelData.file); name: "check"; size: 10; color: "#FFFFFF" }
                                                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                                                    onClicked: root.setChecked(modelData.file, !root.isChecked(modelData.file)) }
                                                            }
                                                            QQC2.Label { text: modelData.file; color: root.theme.textMid; font.pixelSize: 11
                                                                Layout.fillWidth: true; elide: Text.ElideMiddle }
                                                            Rectangle {
                                                                width: 17; height: 17; radius: 5
                                                                readonly property color sc: modelData.untracked ? root.theme.green
                                                                    : (modelData.x === "D" || modelData.y === "D") ? root.theme.red : root.theme.turbo
                                                                color: root.theme.a(sc, 0.15)
                                                                QQC2.Label { anchors.centerIn: parent
                                                                    text: modelData.untracked ? "A" : (modelData.x === "D" || modelData.y === "D") ? "D" : "M"
                                                                    color: parent.sc; font.pixelSize: 9; font.bold: true }
                                                            }
                                                        }
                                                        MouseArea {
                                                            id: fMa
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 26
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: { root.selFile = modelData.file; root.selStaged = false; root.loadDiff() }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        QQC2.Label {
                                            visible: root.files.length === 0
                                            text: "Working tree clean ✨"
                                            color: root.theme.textLo; font.pixelSize: 12; Layout.topMargin: 10
                                        }
                                    }
                                }

                                // Commit box
                                QQC2.Label { text: "Commit Message"; color: root.theme.textLo; font.pixelSize: 10; font.bold: true }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 72
                                    radius: 9
                                    color: root.theme.cardHi
                                    border.width: 1; border.color: msgArea.activeFocus ? root.theme.a(root.theme.green, 0.5) : root.theme.lineHi
                                    QQC2.TextArea {
                                        id: msgArea
                                        anchors.fill: parent
                                        background: null
                                        wrapMode: TextEdit.Wrap
                                        color: root.theme.textHi
                                        font.pixelSize: 12
                                        placeholderText: "feat: describe your change"
                                        placeholderTextColor: root.theme.textLo
                                        selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                        Keys.onPressed: function(ev) {
                                            if ((ev.modifiers & Qt.ControlModifier) && (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter)) {
                                                commitBtn.clicked(); ev.accepted = true
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    id: commitBtn
                                    signal clicked()
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38
                                    radius: 9
                                    readonly property bool ready: msgArea.text.trim() !== "" && root.checkedFiles().length > 0
                                    color: ready ? (cbMa.containsMouse ? Qt.lighter(root.theme.green, 1.1) : root.theme.green) : root.theme.cardHi
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        QQC2.Label { text: "Commit Changes"; color: commitBtn.ready ? "#FFFFFF" : root.theme.textLo; font.pixelSize: 13; font.bold: true }
                                        Rectangle {
                                            width: kbd2.implicitWidth + 10; height: 18; radius: 4
                                            color: Qt.rgba(0, 0, 0, 0.25)
                                            QQC2.Label { id: kbd2; anchors.centerIn: parent; text: "Ctrl ⏎"
                                                color: commitBtn.ready ? "#DFFFEA" : root.theme.textLo; font.pixelSize: 9 }
                                        }
                                    }
                                    MouseArea { id: cbMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: commitBtn.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: commitBtn.clicked() }
                                    onClicked: {
                                        if (!ready) return
                                        var err = backend.commitFiles(root.project.path, msgArea.text, JSON.stringify(root.checkedFiles()))
                                        if (err === "") { msgArea.text = ""; root.refresh() }
                                        else { errToast.text = err; errToast.visible = true; errHide.restart() }
                                    }
                                }
                                QQC2.Label { id: errToast; visible: false; color: root.theme.red; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                Timer { id: errHide; interval: 5000; onTriggered: errToast.visible = false }
                            }

                            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.theme.line }

                            // Diff viewer
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 9
                                    FIcon { name: "file-text"; size: 14; color: root.theme.textMid }
                                    QQC2.Label { text: root.selFile || "No file selected"; color: root.theme.textHi
                                        font.family: root.theme.mono; font.pixelSize: 12; font.bold: true
                                        Layout.fillWidth: true; elide: Text.ElideMiddle }
                                    GButton { theme: root.theme; kind: "tonal"; text: "Stage File"; visible: root.selFile !== ""
                                        onClicked: { backend.stageFile(root.project.path, root.selFile); root.refresh() } }
                                    GButton { theme: root.theme; kind: "danger"; iconSource: "icons/rotate-ccw.svg"; tooltip: "Discard changes"
                                        visible: root.selFile !== ""
                                        onClicked: { backend.discardFile(root.project.path, root.selFile); root.refresh() } }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    radius: 10
                                    color: "#0c0d10"
                                    border.width: 1; border.color: root.theme.line
                                    clip: true
                                    ListView {
                                        id: diffList
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        clip: true
                                        model: root.diffModel
                                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                                        delegate: Rectangle {
                                            width: diffList.width
                                            height: modelData.t === "hunk" ? 24 : 19
                                            color: modelData.t === "add" ? root.theme.a(root.theme.green, 0.10)
                                                 : modelData.t === "del" ? root.theme.a(root.theme.red, 0.10)
                                                 : modelData.t === "hunk" ? root.theme.a(root.theme.blue, 0.08) : "transparent"
                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 0
                                                QQC2.Label { Layout.preferredWidth: 38; text: modelData.o >= 0 ? String(modelData.o) : ""
                                                    color: root.theme.textLo; font.family: root.theme.mono; font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignRight; rightPadding: 6 }
                                                QQC2.Label { Layout.preferredWidth: 38; text: modelData.n >= 0 ? String(modelData.n) : ""
                                                    color: root.theme.textLo; font.family: root.theme.mono; font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignRight; rightPadding: 6 }
                                                Rectangle { Layout.preferredWidth: 3; Layout.fillHeight: true
                                                    color: modelData.t === "add" ? root.theme.green
                                                         : modelData.t === "del" ? root.theme.red : "transparent" }
                                                QQC2.Label {
                                                    Layout.fillWidth: true
                                                    leftPadding: 8
                                                    text: modelData.text
                                                    color: modelData.t === "hunk" ? root.theme.blue
                                                         : modelData.t === "add" ? "#B8EFCE"
                                                         : modelData.t === "del" ? "#F1B8B0" : root.theme.textMid
                                                    font.family: root.theme.mono; font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        QQC2.Label {
                                            anchors.centerIn: parent
                                            visible: root.diffModel.length === 0
                                            text: root.selFile === "" ? "Select a file to see its diff" : "No changes to show"
                                            color: root.theme.textLo; font.pixelSize: 12
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.Label { text: root.diffModel.length ? "No more hunks" : ""; color: root.theme.textLo; font.pixelSize: 11; Layout.fillWidth: true }
                                    GButton { theme: root.theme; kind: "tonal"; text: "Stage All Changes"; iconSource: "icons/check.svg"
                                        enabled: root.files.length > 0
                                        onClicked: { for (var i = 0; i < root.files.length; i++) backend.stageFile(root.project.path, root.files[i].file); root.refresh() } }
                                }
                            }
                        }

                        // ── History ────────────────────────────────────
                        QQC2.ScrollView {
                            id: histScroll
                            contentWidth: availableWidth
                            clip: true
                            ColumnLayout {
                                width: histScroll.availableWidth
                                spacing: 6
                                Repeater {
                                    model: root.log
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        radius: 9
                                        color: hMa.containsMouse ? root.theme.cardHi : "transparent"
                                        border.width: 1; border.color: root.theme.line
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12; anchors.rightMargin: 12
                                            spacing: 12
                                            Rectangle {
                                                width: 30; height: 30; radius: 15
                                                color: root.theme.a(root.theme.green, 0.15)
                                                QQC2.Label { anchors.centerIn: parent; text: modelData.author.charAt(0).toUpperCase()
                                                    color: root.theme.greenBright; font.pixelSize: 12; font.bold: true }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                QQC2.Label { text: modelData.subject; color: root.theme.textHi; font.pixelSize: 13; font.bold: true
                                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                                QQC2.Label { text: modelData.author + "  ·  " + modelData.ago; color: root.theme.textLo; font.pixelSize: 11 }
                                            }
                                            QQC2.Label { text: modelData.hash; color: root.theme.greenBright; font.family: root.theme.mono; font.pixelSize: 11 }
                                        }
                                        MouseArea { id: hMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.copyText(modelData.hash) }
                                    }
                                }
                            }
                        }

                        // ── File Tree ──────────────────────────────────
                        QQC2.ScrollView {
                            id: treeScroll
                            contentWidth: availableWidth
                            clip: true
                            ColumnLayout {
                                width: treeScroll.availableWidth
                                spacing: 2
                                property var treeFiles: []
                                id: treeCol
                                Connections {
                                    target: root
                                    function onTabChanged() {
                                        if (root.tab === "tree" && root.project)
                                            try { treeCol.treeFiles = JSON.parse(backend.gitFiles(root.project.path)) } catch (e) { treeCol.treeFiles = [] }
                                    }
                                }
                                Repeater {
                                    model: treeCol.treeFiles
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        FIcon { name: "file-text"; size: 13; color: root.theme.textLo }
                                        QQC2.Label { text: modelData; color: root.theme.textMid; font.family: root.theme.mono
                                            font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                    }
                                }
                                QQC2.Label { visible: treeCol.treeFiles.length === 0; text: "Open this tab to list tracked files."
                                    color: root.theme.textLo; font.pixelSize: 12 }
                            }
                        }

                        // ── Compare ────────────────────────────────────
                        ColumnLayout {
                            spacing: 10
                            RowLayout {
                                spacing: 10
                                QQC2.ComboBox {
                                    id: cmpA
                                    Layout.preferredWidth: 180
                                    model: root.branches.map(function(b) { return b.name })
                                    background: Rectangle { radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi }
                                    contentItem: QQC2.Label { leftPadding: 12; verticalAlignment: Text.AlignVCenter
                                        text: cmpA.displayText; color: root.theme.textHi; font.pixelSize: 12 }
                                }
                                FIcon { name: "chevron-right"; size: 14; color: root.theme.textLo }
                                QQC2.ComboBox {
                                    id: cmpB
                                    Layout.preferredWidth: 180
                                    model: root.branches.map(function(b) { return b.name })
                                    currentIndex: root.branches.length > 1 ? 1 : 0
                                    background: Rectangle { radius: 9; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi }
                                    contentItem: QQC2.Label { leftPadding: 12; verticalAlignment: Text.AlignVCenter
                                        text: cmpB.displayText; color: root.theme.textHi; font.pixelSize: 12 }
                                }
                                GButton { theme: root.theme; kind: "tonal"; text: "Compare"
                                    onClicked: root.compareText = backend.gitCompare(root.project.path, cmpA.displayText, cmpB.displayText) }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 10; color: "#0c0d10"; border.width: 1; border.color: root.theme.line
                                QQC2.ScrollView {
                                    id: cmpScroll
                                    anchors.fill: parent; anchors.margins: 10
                                    contentWidth: availableWidth
                                    clip: true
                                    QQC2.Label {
                                        width: cmpScroll.availableWidth
                                        text: root.compareText || "Pick two branches and hit Compare."
                                        color: root.theme.textMid; font.family: root.theme.mono; font.pixelSize: 11
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Embedded terminal ──────────────────────────────────────
            ConsolePanel {
                theme: root.theme
                workdir: root.project ? root.project.path : ""
                Layout.fillWidth: true
                Layout.preferredHeight: 170
            }
        }

        // ═══════════ Right rail ═══════════
        QQC2.ScrollView {
            Layout.preferredWidth: 262
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: 250
                spacing: 12

                // Repository
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true
                    implicitHeight: repoCol.implicitHeight + 30
                    ColumnLayout {
                        id: repoCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 9
                        QQC2.Label { text: "Repository"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true }
                        Repeater {
                            model: root.project ? [
                                { l: "Current Branch", v: root.project.branch || "—", ic: "git-branch" },
                                { l: "Upstream", v: root.project.slug || "none", ic: "cloud" },
                                { l: "Status", v: (root.project.ahead === 0 && root.project.behind === 0) ? "Up to date"
                                                : ("↑" + root.project.ahead + " ↓" + root.project.behind), ic: "check" }
                            ] : []
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                QQC2.Label { text: modelData.l; color: root.theme.textLo; font.pixelSize: 10; font.bold: true }
                                RowLayout {
                                    spacing: 7
                                    FIcon { name: modelData.ic; size: 13; color: root.theme.greenBright }
                                    QQC2.Label { text: modelData.v; color: root.theme.textHi; font.pixelSize: 12; font.bold: true
                                        Layout.fillWidth: true; elide: Text.ElideMiddle }
                                }
                            }
                        }
                    }
                }

                // Quick Actions
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true
                    implicitHeight: qaCol.implicitHeight + 30
                    ColumnLayout {
                        id: qaCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 4
                        QQC2.Label { text: "Quick Actions"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true; Layout.bottomMargin: 4 }
                        Repeater {
                            model: [
                                { l: "View on GitHub",       ic: "github",        act: "web" },
                                { l: "Open in Genesi Code",  ic: "code",          act: "code" },
                                { l: "Open in Terminal",     ic: "terminal",      act: "term" },
                                { l: "Copy Clone URL",       ic: "copy",          act: "clone" },
                                { l: "Create Pull Request",  ic: "git-pull-request", act: "pr" },
                                { l: "Stash Changes",        ic: "archive",       act: "stash" }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 8
                                color: qaMa.containsMouse ? root.theme.cardHi : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9; anchors.rightMargin: 8
                                    spacing: 10
                                    FIcon { name: modelData.ic; size: 14; color: root.theme.textMid }
                                    QQC2.Label { text: modelData.l; color: root.theme.textHi; font.pixelSize: 12; Layout.fillWidth: true }
                                    FIcon { name: "chevron-right"; size: 12; color: root.theme.textLo; opacity: qaMa.containsMouse ? 1 : 0 }
                                }
                                MouseArea {
                                    id: qaMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var a = modelData.act
                                        if (a === "web") backend.openUrl(root.project.web)
                                        else if (a === "code") backend.openCode(root.project.path)
                                        else if (a === "term") backend.openTerminal(root.project.path)
                                        else if (a === "clone") backend.copyText(root.project.remote)
                                        else if (a === "pr") backend.openUrl(root.project.web + "/compare")
                                        else if (a === "stash") { backend.stashSave(root.project.path); root.refresh() }
                                    }
                                }
                            }
                        }
                    }
                }

                // Branches
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true
                    implicitHeight: brCol.implicitHeight + 30
                    ColumnLayout {
                        id: brCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Branches"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                            QQC2.Label {
                                text: "+ New Branch"; color: root.theme.greenBright; font.pixelSize: 11; font.bold: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.newBranchOpen = !root.newBranchOpen }
                            }
                        }
                        Rectangle {
                            visible: root.newBranchOpen
                            Layout.fillWidth: true; implicitHeight: 34
                            radius: 8; color: root.theme.cardHi; border.width: 1; border.color: root.theme.lineHi
                            QQC2.TextField {
                                anchors.fill: parent; anchors.leftMargin: 10
                                background: null
                                placeholderText: "feature/my-branch"; placeholderTextColor: root.theme.textLo
                                color: root.theme.textHi; font.pixelSize: 12
                                selectionColor: root.theme.green; selectedTextColor: root.theme.white
                                onAccepted: if (text.trim() !== "") {
                                    backend.createBranch(root.project.path, text.trim())
                                    text = ""; root.newBranchOpen = false; root.refresh()
                                }
                            }
                        }
                        Repeater {
                            model: root.branches.slice(0, 7)
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                color: modelData.current ? root.theme.mix(root.theme.card, root.theme.green, 0.14)
                                     : (bMa.containsMouse ? root.theme.cardHi : "transparent")
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9; anchors.rightMargin: 8
                                    spacing: 8
                                    FIcon { name: "git-branch"; size: 13
                                        color: modelData.current ? root.theme.greenBright : root.theme.textMid }
                                    QQC2.Label { text: modelData.name; color: modelData.current ? root.theme.textHi : root.theme.textMid
                                        font.pixelSize: 12; font.bold: modelData.current; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Rectangle {
                                        visible: modelData.name === "main" || modelData.name === "master"
                                        width: defLbl.implicitWidth + 10; height: 16; radius: 4
                                        color: root.theme.a(root.theme.blue, 0.14)
                                        QQC2.Label { id: defLbl; anchors.centerIn: parent; text: "Default"; color: root.theme.blue; font.pixelSize: 8; font.bold: true }
                                    }
                                    FIcon { visible: modelData.current; name: "check"; size: 12; color: root.theme.greenBright }
                                }
                                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!modelData.current) { backend.checkout(root.project.path, modelData.name); root.refresh() } }
                            }
                        }
                    }
                }

                // Recent Commits
                FCard {
                    theme: root.theme
                    Layout.fillWidth: true
                    implicitHeight: rcCol.implicitHeight + 30
                    ColumnLayout {
                        id: rcCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Recent Commits"; color: root.theme.textHi; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                            QQC2.Label {
                                text: "View All"; color: root.theme.greenBright; font.pixelSize: 11
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = "history" }
                            }
                        }
                        Repeater {
                            model: root.log.slice(0, 4)
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 9
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    color: root.theme.a(root.theme.green, 0.15)
                                    QQC2.Label { anchors.centerIn: parent; text: modelData.author.charAt(0).toUpperCase()
                                        color: root.theme.greenBright; font.pixelSize: 10; font.bold: true }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    QQC2.Label { text: modelData.subject; color: root.theme.textHi; font.pixelSize: 11
                                        Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                                    QQC2.Label { text: modelData.author + " · " + modelData.ago; color: root.theme.textLo; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
