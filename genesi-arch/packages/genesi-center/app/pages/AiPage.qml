/*
 * AiPage — the local model, and the two things people ask to change about it.
 *
 * Genesi runs AI on the machine. That is the point, and it is also the thing
 * that makes this page different from a settings panel: there is a daemon with
 * real state, models that take gigabytes, and a GPU that either helps or does
 * not. So this reports first and offers second.
 *
 * Speech and the cloud key are real, and both are shaped so this page cannot
 * lie about them:
 *
 *   Kokoro   a ~340 MB download AND a Python environment to build, so the
 *            button opens a TERMINAL running `genesi-ai-voice install` rather
 *            than starting it invisibly behind a settings window with nowhere
 *            to show progress or to fail. The row reports what
 *            genesi-ai-voice says, including which step is outstanding.
 *
 *   API key  typed here, into a field that shows dots, and sent to
 *            `genesi-ai-key set` on STDIN -- never as an argument, so it
 *            never reaches a shell history or `ps`. The page never displays
 *            it back: what it shows is which provider, which model, and the
 *            last four characters, which is enough to tell two keys apart and
 *            not enough to be one.
 *
 *            An earlier version had no field at all, on the reasoning that a
 *            secret typed into a settings window is a secret in a screenshot.
 *            That reasoning stops at the field: dots are not screenshottable,
 *            and the alternative -- telling somebody to open a terminal and
 *            redirect a file into a command -- is not privacy, it is an
 *            unusable feature with a good excuse.
 *
 *   Usage    one request is one use, and local and hosted are counted apart.
 *            That separation is the whole point of the local/hosted split, so
 *            a single total would hide the only number worth watching.
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
    readonly property var usage: page.d.usage || ({})

    // The providers this page offers, and the only place their display names
    // live. ci/ai-cloud-test.py checks these ids against the table
    // genesi-ai-key validates against -- a name in one and not the other is a
    // button that reports an unknown provider, which is this project's oldest
    // kind of bug.
    readonly property var cloudProviders: [
        { id: "openai", label: qsTr("OpenAI · ChatGPT") },
        { id: "anthropic", label: qsTr("Anthropic · Claude") },
        { id: "gemini", label: qsTr("Google · Gemini") },
        { id: "groq", label: qsTr("Groq") },
        { id: "openrouter", label: qsTr("OpenRouter") },
        { id: "together", label: qsTr("Together") }
    ]
    // What the picker is on, before anything is saved. Follows whatever is
    // configured, so opening the page on a machine with a key set shows that
    // provider rather than an arbitrary first entry.
    property string picked: page.cloud.provider || "gemini"

    // What the last TEST said. It used to go to a terminal, which ran the
    // command, printed one line and closed with it -- reported as "the test
    // button opens an empty terminal and does nothing". The sentence was
    // always the useful part; a terminal was never the only place to put one.
    property string testResult: ""
    property bool testOk: false
    property bool testing: false

    readonly property int localCalls:
        (page.usage.local && page.usage.local.requests) || 0
    readonly property int cloudCalls: {
        const c = page.usage.cloud || {};
        let n = 0;
        for (const k in c)
            n += (c[k] && c[k].requests) || 0;
        return n;
    }

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

        function onCloudTested(message, ok) {
            page.testResult = message;
            page.testOk = ok;
            page.testing = false;
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
                        // Which STEP is outstanding, because there are two
                        // of them and they fail differently: an environment
                        // to build, and a model to fetch. The row used to say
                        // "needs kokoro-onnx, espeak-ng" under a button whose
                        // entire purpose is to provide those.
                        description: page.voice.ready
                            ? qsTr("Kokoro is installed and ready. Everything is "
                                   + "synthesised on this machine.")
                            : (page.voiceMissing !== ""
                               ? qsTr("Needs %1 first — the installer says "
                                      + "exactly how.").arg(page.voiceMissing)
                               : (page.voice.installed === true
                                  && page.voice.env_ready !== true
                                  ? qsTr("The model is here; the synthesiser "
                                         + "still has to be set up. The "
                                         + "installer does that, in its own "
                                         + "environment — nothing system-wide "
                                         + "is touched.")
                                  : qsTr("About %1 MB and a small Python "
                                         + "environment, both set up once and "
                                         + "run locally like everything else.")
                                    .arg(page.voice.download_mb || 340)))

                        Row {
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.voice.ready === true
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
                                    text: page.voice.ready
                                        ? qsTr("INSTALLED")
                                        : (page.voice.installed === true
                                           ? qsTr("FINISH SETUP")
                                           : qsTr("INSTALL KOKORO"))
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
                                    // download plus a pip install, either of
                                    // which can fail, and a settings window
                                    // has nowhere to show progress.
                                    //
                                    // Through inTerminal, which finds whichever
                                    // terminal is installed and keeps the
                                    // window open when the command ends. Both
                                    // halves were bugs: `foot` was named
                                    // outright, and a window that closes on
                                    // exit takes the error with it.
                                    onTapped: {
                                        if (!page.voice.ready && page.backend)
                                            page.backend.inTerminal(
                                                ["genesi-ai-voice", "install"]);
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
                            : qsTr("Everything runs on this machine. Add a key "
                                   + "below to send what you ask for to a "
                                   + "hosted model instead; the local one stays "
                                   + "the fallback for everything it cannot "
                                   + "reach.")

                        Row {
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.cloud.configured === true
                                width: 62; height: 26; radius: Tokens.radiusSm
                                color: testHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: testHov.hovered ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: page.testing ? qsTr("…") : qsTr("TEST")
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: testHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    // The useful part of a failed test is
                                    // WHICH failure -- 401 is a wrong key,
                                    // 404 a wrong model -- and that is a
                                    // sentence. It goes under this row now.
                                    // It used to go to a terminal, which
                                    // closed the moment the command ended.
                                    onTapped: {
                                        if (!page.backend || page.testing)
                                            return;
                                        page.testResult = "";
                                        page.testing = true;
                                        page.backend.testCloudKey();
                                    }
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: page.cloud.configured === true
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

                    // What the test answered. Not a toast: a 404 naming a
                    // model is worth reading twice, and something that fades
                    // cannot be.
                    Item {
                        width: parent.width
                        visible: page.testResult !== "" || page.testing
                        height: visible ? resultText.implicitHeight + 16 : 0

                        Text {
                            id: resultText
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 14; rightMargin: 14
                            }
                            wrapMode: Text.WordWrap
                            text: page.testing
                                  ? qsTr("asking the provider…")
                                  : page.testResult
                            color: page.testing ? Tokens.textDim
                                 : (page.testOk ? Tokens.accent : "#E58A7B")
                            font.family: Tokens.mono
                            font.pixelSize: 11
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("API key")
                        description: qsTr("Pick who it is for, paste the key, "
                                          + "save. It is sent to the tool on "
                                          + "its standard input, so it never "
                                          + "appears in a command line, in "
                                          + "`ps`, or in a shell history — and "
                                          + "this page never shows it back.")

                        Row {
                            spacing: 8

                            Select {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 168
                                options: page.cloudProviders
                                current: page.picked
                                onPicked: id => page.picked = id
                            }

                            Field {
                                id: keyField

                                anchors.verticalCenter: parent.verticalCenter
                                width: 190
                                height: 26
                                secret: true
                                placeholder: qsTr("paste key")
                                onAccepted: saveKey.save()
                            }

                            Rectangle {
                                id: saveKey
                                objectName: "saveKey"

                                function save() {
                                    if (keyField.text.trim() === ""
                                        || !page.backend)
                                        return;
                                    page.backend.setCloudKey(
                                        page.picked, "",
                                        page.cloud.use_for || "manual",
                                        keyField.text);
                                    // Cleared straight away. The field holds
                                    // a secret for exactly as long as it takes
                                    // to hand it over, and an app left open
                                    // for a week should not still have it on
                                    // screen behind the dots.
                                    keyField.clear();
                                }

                                anchors.verticalCenter: parent.verticalCenter
                                width: 60; height: 26; radius: Tokens.radiusSm
                                color: saveHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: keyField.text !== ""
                                              ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("SAVE")
                                    color: keyField.text !== "" ? Tokens.text
                                                                : Tokens.textFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: saveHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: saveKey.save() }
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        visible: page.cloud.configured === true
                        height: visible ? implicitHeight : 0
                        label: qsTr("What may use it")
                        description: qsTr("The helpers that fire on their own — "
                                          + "the fix offered after a failed "
                                          + "command — run several times a "
                                          + "minute in a busy terminal, and a "
                                          + "hosted model bills per request. "
                                          + "They stay on this machine unless "
                                          + "you say otherwise.")
                        last: true

                        Segmented {
                            options: [{ id: "manual", label: qsTr("What I ask for") },
                                      { id: "all", label: qsTr("Everything") }]
                            current: page.cloud.use_for || "manual"
                            onPicked: id => page.act(["genesi-ai-key", "for", id])
                        }
                    }
                }
            }

            // ── What has actually been sent where ────────────────────────
            //
            // Two numbers, never one. The point of the local/hosted split is
            // that the automatic helpers stay on the machine, and a single
            // total would hide the only question worth asking.
            Panel {
                width: parent.width
                height: 74

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 20
                    spacing: 34

                    Column {
                        spacing: 3
                        Text {
                            text: qsTr("ON THIS MACHINE")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            text: qsTr("%1 request(s)").arg(page.localCalls)
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 17
                            font.weight: Font.Light
                        }
                    }

                    Column {
                        spacing: 3
                        Text {
                            text: qsTr("SENT TO A PROVIDER")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            text: qsTr("%1 request(s)").arg(page.cloudCalls)
                            color: page.cloudCalls > 0 ? Tokens.accent
                                                       : Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 17
                            font.weight: Font.Light
                        }
                    }
                }

                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.rightMargin: 20
                    width: 210
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                    text: qsTr("One request is one use. A request that never "
                               + "landed is not counted as one.")
                    color: Tokens.textDim
                    font.family: Tokens.sans
                    font.pixelSize: 11
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
