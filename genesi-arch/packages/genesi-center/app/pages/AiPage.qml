/*
 * AiPage — the local model, and the two things people ask to change about it.
 *
 * Genesi runs AI on the machine. That is the point, and it is also the thing
 * that makes this page different from a settings panel: there is a daemon with
 * real state, models that take gigabytes, and a GPU that either helps or does
 * not. So this reports first and offers second.
 *
 * Two things were asked for here and NEITHER is built yet: Kokoro speech, so
 * the assistant can talk, and an API key for a cloud model instead of the
 * local one. Nothing in Genesi installs Kokoro and nothing reads a key.
 *
 * They are listed, marked as not built, and NOT clickable. The first version
 * of this page had them as buttons: one opened the AI Monitor with a flag the
 * Monitor ignores, the other pointed at a config path nothing consults. Both
 * responded and did nothing -- the exact failure this app exists to argue
 * against, shipped inside it. A row that says "not built yet" is worth more
 * than a button that lies, and it is what someone reading this page needs in
 * order to plan around it.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var state: page.d.state || ({})
    readonly property bool ready: page.d.available === true
    readonly property var models: page.d.models || []

    function act(argv) {
        if (page.backend)
            page.backend.act(argv, "ai");
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "ai")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("ai")

    Timer {
        interval: 5000
        running: page.visible
        repeat: true
        onTriggered: if (page.backend) page.backend.ask("ai")
    }

    PageFrame {
        anchors.fill: parent
        index: "04"
        group: qsTr("System")
        title: qsTr("Local AI")
        blurb: qsTr("The daemon that gets out of the way when a model is running: "
                    + "it moves the governor, the scheduler and the GPU where "
                    + "they need to be, and puts them back afterwards.")
        note: page.ready
              ? qsTr("%1 model(s) on disk").arg(page.models.length)
              : qsTr("genesi-ai-mode is not installed")
        noteWarn: !page.ready

        // ── State ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("AI Mode") }

            Panel {
                width: parent.width
                height: 118

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 20
                    spacing: 18

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: page.state.active ? Tokens.accent : Tokens.textFaint
                        Behavior on color { ColorAnimation { duration: Tokens.normal } }

                        // A slow pulse while it is on, and nothing while it is
                        // off. It is the only thing on this page that says
                        // "something is happening right now".
                        SequentialAnimation on scale {
                            running: page.state.active === true
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.35; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: page.state.active ? qsTr("Engaged") : qsTr("Idle")
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 22
                            font.weight: Font.Light
                        }
                        Text {
                            text: page.state.active
                                  ? qsTr("tuned for the model that is running")
                                  : qsTr("watching for a model to start")
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }
                }

                Column {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.rightMargin: 20
                    spacing: 8

                    Text {
                        anchors.right: parent.right
                        text: qsTr("WHEN TO ENGAGE")
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.4
                    }
                    Segmented {
                        anchors.right: parent.right
                        options: [{ id: "auto", label: qsTr("Automatic") },
                                  { id: "on", label: qsTr("Always") },
                                  { id: "off", label: qsTr("Never") }]
                        current: page.state.force ? String(page.state.force) : "auto"
                        onPicked: id => page.act(["genesi-ai-mode", id])
                    }
                }
            }

            Panel {
                width: parent.width
                height: profCol.implicitHeight + 8

                Column {
                    id: profCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Intensity")
                        description: qsTr("How hard to push while a model runs. "
                                          + "Battery keeps the fans down and gives "
                                          + "up some speed for it.")
                        last: true
                        Segmented {
                            options: [{ id: "auto", label: qsTr("Auto") },
                                      { id: "max", label: qsTr("Max") },
                                      { id: "balanced", label: qsTr("Balanced") },
                                      { id: "battery", label: qsTr("Battery") }]
                            current: page.state.profile ? String(page.state.profile) : "auto"
                            onPicked: id => page.act(["genesi-ai-mode", "profile", id])
                        }
                    }
                }
            }
        }

        // ── Voice and cloud ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Voice and cloud") }

            Panel {
                width: parent.width
                height: extraCol.implicitHeight + 8

                Column {
                    id: extraCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Spoken answers")
                        description: qsTr("Kokoro would let the assistant read "
                                          + "its answers aloud, on this machine "
                                          + "like everything else. It is not "
                                          + "built yet — nothing here installs "
                                          + "it, so there is nothing to switch "
                                          + "on.")

                        Rectangle {
                            width: 110
                            height: 24
                            radius: Tokens.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: Tokens.lineSoft

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("NOT BUILT YET")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Cloud model")
                        description: qsTr("An API key would let answers come from "
                                          + "a hosted model instead of the local "
                                          + "one. Also not built: nothing in "
                                          + "Genesi reads a key today, so a field "
                                          + "to type one into would be a field "
                                          + "that swallows it.")
                        last: true

                        Rectangle {
                            width: 110
                            height: 24
                            radius: Tokens.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: Tokens.lineSoft

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("NOT BUILT YET")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1
                            }
                        }
                    }
                }
            }
        }

        // ── Models ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && page.models.length > 0

            SectionHead { index: "—"; text: qsTr("Models on this machine") }

            Panel {
                width: parent.width
                height: modelCol.implicitHeight + 26

                Column {
                    id: modelCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 13
                    spacing: 2

                    Repeater {
                        model: page.models
                        delegate: Row {
                            required property var modelData
                            width: modelCol.width
                            height: 22

                            Text {
                                width: parent.width - 90
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: Tokens.text
                                font.family: Tokens.mono
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: 90
                                horizontalAlignment: Text.AlignRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.size_gb !== null
                                      ? modelData.size_gb + " GB" : "—"
                                color: Tokens.textDim
                                font.family: Tokens.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
