/*
 * AiPage — the local model, and the two things people ask to change about it.
 *
 * Genesi runs AI on the machine. That is the point, and it is also the thing
 * that makes this page different from a settings panel: there is a daemon with
 * real state, models that take gigabytes, and a GPU that either helps or does
 * not. So this reports first and offers second.
 *
 * Speech and the cloud key are real now, and both are shaped so this page
 * cannot lie about them:
 *
 *   Kokoro   a ~340 MB download, so the button opens a TERMINAL running
 *            `genesi-ai-voice install` rather than starting it invisibly
 *            behind a settings window with nowhere to show progress or to
 *            fail. The row reports what genesi-ai-voice says, including which
 *            dependency is missing.
 *
 *   API key  the page shows WHETHER one is set and which provider, never the
 *            key, and offers no field to type one into. A secret typed into a
 *            settings window is a secret in a screenshot; `genesi-ai-key set`
 *            reads it from stdin so it never reaches a shell history or `ps`
 *            either. Clearing and testing are safe, so those are here.
 *
 * An earlier version of this page had both as buttons over nothing: one opened
 * the AI Monitor with a flag the Monitor ignores, the other reported on a
 * config path nothing read. That is what these replaced.
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
    readonly property var voice: page.d.voice || ({})
    readonly property var cloud: page.d.cloud || ({})

    // What Kokoro is still waiting for, in one phrase. genesi-ai-voice
    // reports each missing piece with the command that installs it; the page
    // shows the names and leaves the commands to the terminal that will run
    // them.
    readonly property string voiceMissing:
        (page.voice.missing || []).map(m => m.name).join(", ")

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
                        description: page.voice.ready
                            ? qsTr("Kokoro is installed and ready. Everything is "
                                   + "synthesised on this machine.")
                            : (page.voice.installed
                               ? qsTr("The model is here but something it needs "
                                      + "is not: %1.").arg(page.voiceMissing)
                               : (page.voiceMissing !== ""
                                  ? qsTr("Needs %1 first — the installer says "
                                         + "exactly how.").arg(page.voiceMissing)
                                  : qsTr("About %1 MB, downloaded once and run "
                                         + "locally like everything else.")
                                    .arg(page.voice.download_mb || 340)))

                        Row {
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.voice.ready
                                width: 72; height: 26; radius: Tokens.radiusSm
                                color: sayHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: sayHov.hovered ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("SPEAK")
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: sayHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: if (page.backend)
                                        page.backend.launch(
                                            ["genesi-ai-voice", "say",
                                             qsTr("Genesi is listening.")])
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150; height: 26; radius: Tokens.radiusSm
                                color: page.voice.ready ? "transparent"
                                     : (voiceHov.hovered ? Tokens.cardHi : "transparent")
                                border.width: 1
                                border.color: page.voice.ready ? Tokens.accentDim
                                     : (voiceHov.hovered ? Tokens.accentDim : Tokens.line)
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }

                                Text {
                                    anchors.centerIn: parent
                                    text: page.voice.ready ? qsTr("INSTALLED")
                                                           : qsTr("INSTALL KOKORO")
                                    color: page.voice.ready ? Tokens.accent : Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler {
                                    id: voiceHov
                                    enabled: !page.voice.ready
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    // In a TERMINAL, on purpose. It is a 340 MB
                                    // download that can fail on the network or
                                    // on a missing dependency, and a settings
                                    // window has nowhere to show either.
                                    onTapped: {
                                        if (!page.voice.ready && page.backend)
                                            page.backend.launch(
                                                ["foot", "genesi-ai-voice",
                                                 "install"]);
                                    }
                                }
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Cloud model")
                        description: page.cloud.configured
                            ? qsTr("%1 · %2, key %3. Used for %4.")
                              .arg(page.cloud.provider || "")
                              .arg(page.cloud.model || "")
                              .arg(page.cloud.key_tail || "")
                              .arg(page.cloud.use_for === "all"
                                   ? qsTr("everything, including the helpers that "
                                          + "fire on their own")
                                   : qsTr("what you ask for; the automatic helpers "
                                          + "stay local"))
                            : qsTr("Everything runs on this machine. A key is set "
                                   + "in a terminal — this page will not ask you "
                                   + "to type a secret into a window that can be "
                                   + "screenshotted.")
                        last: true

                        Row {
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.cloud.configured
                                width: 62; height: 26; radius: Tokens.radiusSm
                                color: testHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: testHov.hovered ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("TEST")
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: testHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    // A terminal again: the useful part of a
                                    // failed test is WHICH failure -- 401 is a
                                    // wrong key, 404 a wrong model -- and that
                                    // is a sentence, not a light.
                                    onTapped: if (page.backend)
                                        page.backend.launch(["foot", "genesi-ai-key",
                                                             "test"])
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.cloud.configured
                                width: 62; height: 26; radius: Tokens.radiusSm
                                color: clearHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: clearHov.hovered ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("CLEAR")
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: clearHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: if (page.backend)
                                        page.backend.act(["genesi-ai-key", "clear"],
                                                         "ai")
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 116; height: 26; radius: Tokens.radiusSm
                                color: "transparent"
                                border.width: 1
                                border.color: page.cloud.configured ? Tokens.accentDim
                                                                    : Tokens.lineSoft
                                Text {
                                    anchors.centerIn: parent
                                    text: page.cloud.configured ? qsTr("KEY SET")
                                                                : qsTr("LOCAL ONLY")
                                    color: page.cloud.configured ? Tokens.accent
                                                                 : Tokens.textFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: !page.cloud.configured
                text: qsTr("genesi-ai-key set --provider openai < key.txt")
                color: Tokens.accentDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
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
