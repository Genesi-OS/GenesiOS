/*
 * Genesi Forge — Secrets.
 *
 * Per-project environment variables whose VALUES live in the OS keyring rather
 * than in a .env sitting in the working tree. The panel never holds a value in
 * a property: reveal and copy each fetch on demand from the backend and the
 * revealed one is dropped as soon as the row collapses, so a screenshot or a
 * QML inspector cannot harvest the whole set.
 *
 * Forge is a Git client, which is why the git state of .env is surfaced right
 * here — the moment someone imports a .env is exactly the moment to notice it
 * is about to be committed.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs

Item {
    id: root
    property var theme
    property string projectPath: ""

    property bool available: true
    property var items: []
    property var gitState: ({ envFile: false, tracked: false, ignored: false })
    property string revealedKey: ""
    property string revealedValue: ""

    function reload() {
        if (!projectPath)
            return
        var res = JSON.parse(backend.listSecrets(projectPath))
        available = res.available
        items = res.items
        gitState = res.git
        revealedKey = ""
        revealedValue = ""
    }

    onProjectPathChanged: reload()
    Component.onCompleted: reload()

    FileDialog {
        id: envPicker
        title: "Choose a .env file"
        nameFilters: ["Environment files (.env *.env env*)", "All files (*)"]
        onAccepted: {
            var res = JSON.parse(backend.importEnv(root.projectPath, selectedFile.toString()))
            root.reload()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 14

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                QQC2.Label {
                    text: "Secrets"
                    color: root.theme.textHi
                    font.family: root.theme.display
                    font.pixelSize: 22
                    font.bold: true
                }
                QQC2.Label {
                    text: "Environment variables for this project, stored in the system keyring — not in a file in your repo."
                    color: root.theme.textMid
                    font.pixelSize: 11
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
            GButton {
                theme: root.theme
                kind: "tonal"
                text: "Import .env"
                iconSource: "icons/download.svg"
                enabled: root.available
                tooltip: "Read a .env file and move every variable into the keyring"
                onClicked: envPicker.open()
            }
            GButton {
                theme: root.theme
                kind: "filled"
                text: "Import from project"
                iconSource: "icons/folder.svg"
                enabled: root.available && root.gitState.envFile
                tooltip: root.gitState.envFile ? "Import the .env already in this project"
                                               : "This project has no .env file"
                onClicked: { backend.importEnv(root.projectPath, ""); root.reload() }
            }
        }

        // ── Keyring unavailable ─────────────────────────────────────────────
        FCard {
            theme: root.theme
            visible: !root.available
            Layout.fillWidth: true
            implicitHeight: banner.implicitHeight + 24
            accent: root.theme.red
            RowLayout {
                id: banner
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                FIcon { name: "lock"; color: root.theme.red; size: 18 }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: root.theme.textMid
                    font.pixelSize: 11
                    text: "The system keyring is not reachable, so secrets cannot be stored. "
                          + "Install libsecret and make sure a keyring service is running "
                          + "(KWallet on Plasma, gnome-keyring elsewhere)."
                }
            }
        }

        // ── .env is in the repo and git can see it ──────────────────────────
        FCard {
            theme: root.theme
            visible: root.gitState.envFile && !root.gitState.ignored
            Layout.fillWidth: true
            implicitHeight: gitWarn.implicitHeight + 24
            accent: root.gitState.tracked ? root.theme.red : root.theme.turbo
            RowLayout {
                id: gitWarn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                FIcon {
                    name: "shield"
                    color: root.gitState.tracked ? root.theme.red : root.theme.turboBright
                    size: 18
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    QQC2.Label {
                        color: root.theme.textHi
                        font.pixelSize: 12
                        font.bold: true
                        text: root.gitState.tracked
                              ? "This project's .env is tracked by git"
                              : "This project's .env is not ignored by git"
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: root.theme.textMid
                        font.pixelSize: 11
                        text: root.gitState.tracked
                              ? "It is already in the repository, so its contents can be pushed. Ignoring it also untracks it — commit that removal, and treat any secret it held as compromised."
                              : "One `git add .` away from being committed. Ignoring it now costs nothing."
                    }
                }
                GButton {
                    theme: root.theme
                    kind: "filled"
                    text: "Add to .gitignore"
                    iconSource: "icons/shield.svg"
                    onClicked: { backend.gitignoreEnv(root.projectPath); root.reload() }
                }
            }
        }

        // ── Add one by hand ─────────────────────────────────────────────────
        FCard {
            theme: root.theme
            Layout.fillWidth: true
            implicitHeight: 62
            enabled: root.available
            opacity: root.available ? 1 : 0.5
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                QQC2.TextField {
                    id: newKey
                    Layout.preferredWidth: 200
                    placeholderText: "KEY_NAME"
                    color: root.theme.textHi
                    font.family: root.theme.mono
                    font.pixelSize: 12
                    background: Rectangle {
                        radius: 7
                        color: root.theme.card
                        border.color: newKey.activeFocus ? root.theme.green : root.theme.line
                        border.width: 1
                    }
                }
                QQC2.TextField {
                    id: newValue
                    Layout.fillWidth: true
                    placeholderText: "value"
                    echoMode: TextInput.Password
                    color: root.theme.textHi
                    font.family: root.theme.mono
                    font.pixelSize: 12
                    background: Rectangle {
                        radius: 7
                        color: root.theme.card
                        border.color: newValue.activeFocus ? root.theme.green : root.theme.line
                        border.width: 1
                    }
                    onAccepted: addBtn.clicked()
                }
                GButton {
                    id: addBtn
                    theme: root.theme
                    kind: "filled"
                    text: "Add"
                    iconSource: "icons/plus.svg"
                    onClicked: {
                        if (!newKey.text.trim())
                            return
                        var res = JSON.parse(backend.setSecret(root.projectPath,
                                                               newKey.text, newValue.text))
                        if (res.ok) {
                            newKey.text = ""
                            newValue.text = ""
                            root.reload()
                        }
                    }
                }
            }
        }

        // ── The list ────────────────────────────────────────────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.items
                    delegate: FCard {
                        theme: root.theme
                        Layout.fillWidth: true
                        implicitHeight: 52
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            FIcon {
                                name: "lock"
                                color: modelData.resolved ? root.theme.greenBright : root.theme.red
                                size: 15
                            }

                            QQC2.Label {
                                text: modelData.key
                                color: root.theme.textHi
                                font.family: root.theme.mono
                                font.pixelSize: 12
                                Layout.preferredWidth: 210
                                elide: Text.ElideRight
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.family: root.theme.mono
                                font.pixelSize: 12
                                color: modelData.resolved ? root.theme.textMid : root.theme.red
                                text: !modelData.resolved
                                      ? "missing from the keyring"
                                      : (root.revealedKey === modelData.key
                                         ? root.revealedValue : "••••••••••••")
                            }

                            GButton {
                                theme: root.theme
                                kind: "tonal"
                                enabled: modelData.resolved
                                text: root.revealedKey === modelData.key ? "Hide" : "Reveal"
                                onClicked: {
                                    if (root.revealedKey === modelData.key) {
                                        root.revealedKey = ""
                                        root.revealedValue = ""
                                    } else {
                                        root.revealedValue = backend.revealSecret(
                                            root.projectPath, modelData.key)
                                        root.revealedKey = modelData.key
                                    }
                                }
                            }
                            GButton {
                                theme: root.theme
                                kind: "tonal"
                                iconSource: "icons/copy.svg"
                                enabled: modelData.resolved
                                tooltip: "Copy the value to the clipboard"
                                onClicked: backend.copySecret(root.projectPath, modelData.key)
                            }
                            GButton {
                                theme: root.theme
                                kind: "danger"
                                iconSource: "icons/trash.svg"
                                tooltip: "Delete this secret from the keyring"
                                onClicked: { backend.deleteSecret(root.projectPath, modelData.key); root.reload() }
                            }
                        }
                    }
                }

                QQC2.Label {
                    visible: root.items.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: root.theme.textLo
                    font.pixelSize: 12
                    text: root.gitState.envFile
                          ? "No secrets stored yet — this project has a .env, so \"Import from project\" will pull it in."
                          : "No secrets stored yet. Add one above, or import a .env file."
                }
            }
        }

        // ── Getting them back out ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.items.length > 0
            spacing: 8
            QQC2.Label {
                Layout.fillWidth: true
                color: root.theme.textLo
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                text: "Need them outside Forge? Copy shell exports for a terminal, or write a .env for tools that insist on the file."
            }
            GButton {
                theme: root.theme
                kind: "tonal"
                text: "Copy shell exports"
                iconSource: "icons/terminal.svg"
                tooltip: "export KEY='value' lines, ready to paste or eval"
                onClicked: backend.copyShellExport(root.projectPath)
            }
            GButton {
                theme: root.theme
                kind: "tonal"
                text: "Write .env"
                iconSource: "icons/file-text.svg"
                tooltip: "Write a .env in the project (mode 600)"
                onClicked: { backend.exportEnvFile(root.projectPath); root.reload() }
            }
        }
    }
}
