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
    property string picked: "gemini"

    // What the last TEST said. It used to go to a terminal, which ran the
    // command, printed one line and closed with it -- reported as "the test
    // button opens an empty terminal and does nothing". The sentence was
    // always the useful part; a terminal was never the only place to put one.
    property string testResult: ""
    property bool testOk: false
    property bool testing: false
    // Which provider the result belongs to -- there is a TEST per provider
    // now, and a result drawn under the wrong one is worse than none.
    property string testProvider: ""

    readonly property var configured: page.cloud.providers || []
    // The default model for a provider, for the add row's placeholder.
    function defaultModel(id) {
        const known = page.cloud.known || [];
        for (const k of known)
            if (k.id === id)
                return k.model;
        return "";
    }
    function labelOf(id) {
        for (const p of page.cloudProviders)
            if (p.id === id)
                return p.label;
        return id;
    }

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
                        visible: page.voice.ready === true
                        height: visible ? implicitHeight : 0
                        label: qsTr("Voice language")
                        description: qsTr("Every language here runs from the "
                                          + "files already installed — "
                                          + "choosing one downloads nothing "
                                          + "and uses no more memory.")

                        Row {
                            spacing: 8

                            Select {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 190
                                options: (page.voice.languages || [])
                                         .map(l => ({ id: l.id, label: l.label }))
                                current: page.voice.language || ""
                                onPicked: id => page.act(["genesi-ai-voice", "set",
                                                          "--language", id])
                            }

                            Select {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150
                                options: {
                                    const ls = page.voice.languages || [];
                                    for (const l of ls)
                                        if (l.id === page.voice.language)
                                            return l.voices.map(v => ({ id: v, label: v }));
                                    return [];
                                }
                                current: page.voice.voice || ""
                                onPicked: id => page.act(["genesi-ai-voice", "set",
                                                          "--voice", id])
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Hosted models")
                        description: page.configured.length === 0
                            ? qsTr("Everything runs on this machine. Add a key "
                                   + "below to be able to switch a chat to a "
                                   + "provider's API — the AI Mode Monitor and "
                                   + "Quick Chat have a Local | API switch for it.")
                            : qsTr("One key per provider. Type the model the "
                                   + "way the provider names it. The one in use "
                                   + "is what the API side of a chat starts on.")
                    }

                    // One row per provider with a key.
                    Repeater {
                        model: page.configured

                        delegate: Column {
                            id: prow
                            required property var modelData
                            width: extraCol.width
                            spacing: 0

                            Item {
                                width: parent.width
                                height: 48

                                Column {
                                    anchors { left: parent.left; leftMargin: 14
                                              verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Text {
                                        text: page.labelOf(prow.modelData.provider)
                                        color: Tokens.textHi
                                        font.family: Tokens.sans
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        text: qsTr("key %1").arg(prow.modelData.key_tail || "")
                                        color: Tokens.textFaint
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fsMicro
                                    }
                                }

                                Row {
                                    anchors { right: parent.right; rightMargin: 14
                                              verticalCenter: parent.verticalCenter }
                                    spacing: 8

                                    // The model, typed. Saved on Enter -- a
                                    // half-typed name must not be written while
                                    // somebody is still typing it.
                                    Field {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 240
                                        height: 26
                                        text: prow.modelData.model || ""
                                        placeholder: page.defaultModel(prow.modelData.provider)
                                        onAccepted: value => page.act(
                                            ["genesi-ai-key", "model",
                                             prow.modelData.provider, value.trim()])
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 70; height: 26; radius: Tokens.radiusSm
                                        color: useHov.hovered && !prow.modelData.active
                                               ? Tokens.cardHi : "transparent"
                                        border.width: 1
                                        border.color: prow.modelData.active ? Tokens.accentDim
                                                                            : Tokens.line
                                        Text {
                                            anchors.centerIn: parent
                                            text: prow.modelData.active ? qsTr("IN USE")
                                                                        : qsTr("USE")
                                            color: prow.modelData.active ? Tokens.accent
                                                                         : Tokens.text
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fsMicro
                                            font.letterSpacing: 1
                                        }
                                        HoverHandler { id: useHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: if (!prow.modelData.active)
                                                page.act(["genesi-ai-key", "use",
                                                          prow.modelData.provider])
                                        }
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 62; height: 26; radius: Tokens.radiusSm
                                        color: tHov.hovered ? Tokens.cardHi : "transparent"
                                        border.width: 1
                                        border.color: tHov.hovered ? Tokens.accentDim : Tokens.line
                                        Text {
                                            anchors.centerIn: parent
                                            text: page.testing && page.testProvider === prow.modelData.provider
                                                  ? qsTr("…") : qsTr("TEST")
                                            color: Tokens.text
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fsMicro
                                            font.letterSpacing: 1
                                        }
                                        HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            // On the page, not in a terminal:
                                            // a terminal closed the moment the
                                            // command ended.
                                            onTapped: {
                                                if (!page.backend || page.testing)
                                                    return;
                                                page.testProvider = prow.modelData.provider;
                                                page.testResult = "";
                                                page.testing = true;
                                                page.backend.testCloudKey(prow.modelData.provider);
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 70; height: 26; radius: Tokens.radiusSm
                                        color: rmHov.hovered ? Tokens.cardHi : "transparent"
                                        border.width: 1
                                        border.color: Tokens.line
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("REMOVE")
                                            color: Tokens.textDim
                                            font.family: Tokens.mono
                                            font.pixelSize: Tokens.fsMicro
                                            font.letterSpacing: 1
                                        }
                                        HoverHandler { id: rmHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: page.act(["genesi-ai-key", "remove",
                                                                prow.modelData.provider])
                                        }
                                    }
                                }
                            }

                            // What this provider's test answered.
                            Text {
                                width: parent.width - 28
                                x: 14
                                visible: page.testProvider === prow.modelData.provider
                                         && (page.testResult !== "" || page.testing)
                                height: visible ? implicitHeight + 10 : 0
                                wrapMode: Text.WordWrap
                                text: page.testing ? qsTr("asking the provider…")
                                                   : page.testResult
                                color: page.testing ? Tokens.textDim
                                     : (page.testOk ? Tokens.accent : "#E58A7B")
                                font.family: Tokens.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: page.configured.length === 0 ? qsTr("Add an API key")
                                                            : qsTr("Add another")
                        description: qsTr("Pick the provider, type the model it "
                                          + "should answer with, paste the key. "
                                          + "The key goes to the tool on its "
                                          + "standard input, so it never "
                                          + "appears in a command line or a "
                                          + "shell history, and this page never "
                                          + "shows it back.")

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
                                id: newModel
                                anchors.verticalCenter: parent.verticalCenter
                                width: 190
                                height: 26
                                placeholder: page.defaultModel(page.picked)
                            }

                            Field {
                                id: keyField
                                anchors.verticalCenter: parent.verticalCenter
                                width: 170
                                height: 26
                                secret: true
                                placeholder: qsTr("paste key")
                                onAccepted: saveKey.save()
                            }

                            Rectangle {
                                id: saveKey
                                objectName: "saveKey"

                                function save() {
                                    if (keyField.text.trim() === "" || !page.backend)
                                        return;
                                    page.backend.setCloudKey(
                                        page.picked, newModel.text.trim(),
                                        page.cloud.use_for || "manual",
                                        keyField.text);
                                    // Cleared straight away: the field holds a
                                    // secret only as long as it takes to hand
                                    // it over.
                                    keyField.clear();
                                    newModel.clear();
                                }

                                anchors.verticalCenter: parent.verticalCenter
                                width: 60; height: 26; radius: Tokens.radiusSm
                                color: saveHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: keyField.text !== "" ? Tokens.accentDim : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("SAVE")
                                    color: keyField.text !== "" ? Tokens.text : Tokens.textFaint
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
