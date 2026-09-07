/*
 * SettingsPage — this app's own settings, and where everything else lives.
 *
 * Deliberately small. The temptation with a page called Settings is to make it
 * the drawer for everything that did not fit elsewhere, and then it becomes
 * the page nobody can find anything in. Three things belong here: what this
 * app is, the two knobs that are about the app rather than the system, and
 * honest pointers to the tools that own the rest.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var core: ({})
    property var caps: ({})

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onDataReady(payload) {
            try {
                const d = JSON.parse(payload);
                if (d.core)
                    page.core = d.core;
            } catch (e) {}
        }
    }

    PageFrame {
        anchors.fill: parent
        index: "04"
        group: qsTr("System")
        title: qsTr("Settings")
        blurb: qsTr("What this app is, and where the things it does not do live. "
                    + "Every page here writes through a command you can also run "
                    + "in a terminal, which is why nothing it changes is trapped "
                    + "inside it.")
        note: page.core.version ? qsTr("Genesi Center · %1").arg(page.core.version)
                                : "Genesi Center"

        // ── The artwork ──────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("This app") }

            Panel {
                width: parent.width
                height: artCol.implicitHeight + 8

                Column {
                    id: artCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Overview artwork")
                        description: qsTr("Drop a tree.png or tree.svg in "
                                          + "~/.config/genesi/center/ and it "
                                          + "replaces the one on the Overview. "
                                          + "Reopen the window to see it — no "
                                          + "rebuild and no root.")
                        Text {
                            text: "~/.config/genesi/center/"
                            color: Tokens.accentDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Where the numbers come from")
                        description: qsTr("Nothing on any page is read by this app "
                                          + "directly. It runs genesi-center-data "
                                          + "and draws what comes back, so a "
                                          + "terminal and this window can never "
                                          + "disagree.")
                        last: true
                        Text {
                            text: "genesi-center-data"
                            color: Tokens.accentDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }
                }
            }
        }

        // ── The other tools ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("The rest of Genesi") }

            Grid {
                id: toolGrid
                width: parent.width
                columns: Math.max(1, Math.floor(width / 300))
                columnSpacing: Tokens.gap
                rowSpacing: Tokens.gap

                readonly property real cell:
                    (width - (columns - 1) * columnSpacing) / columns

                Repeater {
                    model: [
                        // NOT "genesi-update-center": that name is a polkit
                        // helper (genesi-update-center-apply) and a Plasma
                        // applet, never a command. The card opened nothing.
                        // The channel switcher is the real program.
                        { name: qsTr("Update channel"),
                          desc: qsTr("Whether this machine follows stable or "
                                     + "testing, and what is waiting."),
                          run: ["genesi-channel-gui"] },
                        { name: qsTr("AI Monitor"),
                          desc: qsTr("What the model is doing, and what AI Mode "
                                     + "changed to help it."),
                          run: ["genesi-ai-monitor"] },
                        { name: qsTr("Snapshots"),
                          desc: qsTr("The full list, and rolling back."),
                          run: ["genesi-snapshots-gui"] }
                    ]
                    delegate: Panel {
                        id: toolCard
                        required property var modelData

                        width: toolGrid.cell
                        height: 104
                        interactive: true
                        hovered: toolHov.hovered

                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 16
                            spacing: 5

                            Text {
                                text: toolCard.modelData.name
                                color: toolHov.hovered ? Tokens.textHi : Tokens.text
                                font.family: Tokens.sans
                                font.pixelSize: 14
                            }
                            Text {
                                width: parent.width
                                text: toolCard.modelData.desc
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        // These cards LAUNCH a program, and nothing about them
                        // said so: a name, a sentence, and a pointer cursor you
                        // only find by hovering. The command it runs is the
                        // honest label for a launcher, so the card carries it,
                        // and the arrow steps out on hover.
                        Row {
                            anchors {
                                left: parent.left; bottom: parent.bottom
                            }
                            anchors.leftMargin: 16
                            anchors.bottomMargin: 13
                            spacing: 6

                            Text {
                                text: "▸"
                                color: toolHov.hovered ? Tokens.accent : Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }
                            Text {
                                text: toolCard.modelData.run[0]
                                color: toolHov.hovered ? Tokens.accentDim : Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 0.8
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }

                            // The whole row shifts right by 4px on hover. Small
                            // enough not to be an animation you watch, large
                            // enough that the card answers the pointer.
                            transform: Translate {
                                x: toolHov.hovered ? 4 : 0
                                Behavior on x {
                                    NumberAnimation {
                                        duration: Tokens.quick
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        HoverHandler { id: toolHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: if (page.backend)
                                page.backend.launch(toolCard.modelData.run)
                        }
                    }
                }
            }
        }

        // ── About ────────────────────────────────────────────────────────────
        Panel {
            width: parent.width
            height: 132

            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 24
                spacing: 20

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "../art/genesi-leaf.svg"
                    sourceSize: Qt.size(52, 52)
                    width: 52; height: 52
                    opacity: 0.9
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        text: page.core.name ? page.core.name : "Genesi OS"
                        color: Tokens.textHi
                        font.family: Tokens.sans
                        font.pixelSize: 20
                        font.weight: Font.Light
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("A living system. With you, for what comes next.")
                        color: Tokens.text
                        font.family: Tokens.sans
                        font.pixelSize: 12
                    }
                    Text {
                        // AGPL-3.0, which is what the project actually is.
                        text: qsTr("AGPL-3.0 · genesios.org")
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }
            }
        }
    }
}
