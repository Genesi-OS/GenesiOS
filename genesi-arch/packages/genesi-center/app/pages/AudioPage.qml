/*
 * AudioPage — outputs, inputs, and which one is default.
 *
 * Everything goes through wpctl, because wireplumber is what Genesi ships and
 * what genesi-audio drives. Two tools reading one server eventually disagree
 * about which device is default, and the default is the only thing this page
 * is really for.
 *
 * The card carries a warning nobody would guess at, and it is here because it
 * cost a week: a soft mixer can sit at 100% while the HARDWARE mixer underneath
 * is at zero, and then nothing plays at any volume. Genesi ships
 * `genesi-open-usb-mixer` for exactly that, and the button is on this page
 * rather than in a wiki nobody reads.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property bool ready: page.d.available === true
    readonly property var sinks: page.d.sinks || []
    readonly property var sources: page.d.sources || []

    function act(argv) {
        if (page.backend)
            page.backend.act(argv, "audio");
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "audio")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("audio")

    // Devices appear and vanish -- a headset plugged in, Bluetooth connecting.
    // Only while the page is visible, so it costs nothing anywhere else.
    Timer {
        interval: 4000
        running: page.visible
        repeat: true
        onTriggered: if (page.backend) page.backend.ask("audio")
    }

    PageFrame {
        anchors.fill: parent
        index: "02"
        group: qsTr("Devices")
        title: qsTr("Audio")
        blurb: qsTr("Every output and input wireplumber knows about. The starred "
                    + "one is where sound goes; clicking another moves it, and "
                    + "everything already playing follows.")
        note: page.ready
              ? qsTr("%1 output(s) · %2 input(s)").arg(page.sinks.length)
                                                  .arg(page.sources.length)
              : qsTr("wpctl did not answer — is pipewire running?")
        noteWarn: !page.ready

        // ── Outputs ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Output") }

            Repeater {
                model: page.sinks
                delegate: Panel {
                    id: sinkCard
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 92
                    interactive: !modelData.default
                    hovered: sinkHov.hovered
                    color: modelData.default ? Tokens.cardHi : Tokens.card
                    border.color: modelData.default ? Tokens.accentDim
                                                    : (sinkHov.hovered ? Tokens.accentDeep
                                                                       : Tokens.line)

                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 16
                        spacing: 10

                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                width: parent.width - 190
                                text: sinkCard.modelData.name
                                color: sinkCard.modelData.default ? Tokens.textHi : Tokens.text
                                font.family: Tokens.sans
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: sinkCard.modelData.default
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("DEFAULT")
                                color: Tokens.accent
                                font.family: Tokens.mono
                                font.pixelSize: 8
                                font.letterSpacing: 1
                            }
                            Text {
                                visible: sinkCard.modelData.muted
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("MUTED")
                                color: Tokens.textDim
                                font.family: Tokens.mono
                                font.pixelSize: 8
                                font.letterSpacing: 1
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 12

                            Slider {
                                width: parent.width - 96
                                anchors.verticalCenter: parent.verticalCenter
                                from: 0; to: 100; step: 1; unit: "%"
                                value: sinkCard.modelData.volume
                                onReleased: v => page.act(
                                    ["wpctl", "set-volume",
                                     String(sinkCard.modelData.id), (v / 100).toFixed(2)])
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                height: 26
                                radius: Tokens.radiusSm
                                color: muteHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: sinkCard.modelData.muted ? Tokens.accentDim
                                                                       : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }

                                Text {
                                    anchors.centerIn: parent
                                    text: sinkCard.modelData.muted ? qsTr("UNMUTE")
                                                                   : qsTr("MUTE")
                                    color: sinkCard.modelData.muted ? Tokens.accent
                                                                    : Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: muteHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: page.act(["wpctl", "set-mute",
                                                        String(sinkCard.modelData.id),
                                                        "toggle"])
                                }
                            }
                        }
                    }

                    HoverHandler { id: sinkHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (!sinkCard.modelData.default)
                                page.act(["wpctl", "set-default",
                                          String(sinkCard.modelData.id)]);
                        }
                    }
                }
            }
        }

        // ── Inputs ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && page.sources.length > 0

            SectionHead { index: "—"; text: qsTr("Input") }

            Panel {
                width: parent.width
                height: srcCol.implicitHeight + 8

                Column {
                    id: srcCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    Repeater {
                        model: page.sources
                        delegate: SettingRow {
                            required property var modelData
                            required property int index

                            width: srcCol.width
                            label: modelData.name
                            description: modelData.default
                                         ? qsTr("the microphone applications get")
                                         : ""
                            last: index === page.sources.length - 1

                            Slider {
                                width: 200
                                from: 0; to: 100; step: 1; unit: "%"
                                value: modelData.volume
                                onReleased: v => page.act(
                                    ["wpctl", "set-volume", String(modelData.id),
                                     (v / 100).toFixed(2)])
                            }
                        }
                    }
                }
            }
        }

        // ── The hardware mixer ───────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && page.d.mixer === true

            SectionHead { index: "—"; text: qsTr("When nothing plays at any volume") }

            Panel {
                width: parent.width
                height: 104

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        width: parent.width - 190
                        text: qsTr("Some sound cards keep a second, physical mixer "
                                   + "underneath this one. It can sit at zero "
                                   + "while everything here reads 100%, and then "
                                   + "nothing plays — no error, no clue. This "
                                   + "opens every playback control on every USB "
                                   + "card to full, and prints what it touched.")
                        color: Tokens.text
                        font.family: Tokens.sans
                        font.pixelSize: 11
                        lineHeight: 1.4
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom }
                    anchors.margins: 16
                    width: 172
                    height: 28
                    radius: Tokens.radiusSm
                    color: mixHov.hovered ? Tokens.cardHi : "transparent"
                    border.width: 1
                    border.color: mixHov.hovered ? Tokens.accentDim : Tokens.line
                    Behavior on color { ColorAnimation { duration: Tokens.quick } }

                    Text {
                        anchors.centerIn: parent
                        // NOT "open the mixer". Nothing opens: the tool walks
                        // the USB cards and turns their playback controls up.
                        // A button named for a window that never appears is a
                        // button that did nothing, which is how this was
                        // reported.
                        text: qsTr("TURN THE HARDWARE UP")
                        color: Tokens.text
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1
                    }
                    HoverHandler { id: mixHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        // In a terminal, because the output is the point. It
                        // prints a line per control it opened, and on a machine
                        // with silent audio that list is the diagnosis.
                        onTapped: if (page.backend)
                            page.backend.launch(["foot", "sh", "-c",
                                "genesi-open-usb-mixer; "
                                + "echo; echo 'Press enter to close'; read _"])
                    }
                }
            }
        }
    }
}
