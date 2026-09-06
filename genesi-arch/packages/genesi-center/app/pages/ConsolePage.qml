/*
 * ConsolePage — commands you invent, in every shell on the machine.
 *
 * Name a command and say what it runs; it becomes a real function in bash, zsh
 * AND fish. That last one is the whole reason this goes through
 * `genesi-console` rather than appending a line to a file: fish is not POSIX,
 * `foo() { ...; }` is a syntax error there, and fish does not read
 * /etc/profile.d at all. One definition, three generated files, so the shells
 * cannot drift.
 *
 * It works from a terminal too -- `genesi-console add up "sudo pacman -Syu"`
 * is the same command this page runs. A shortcut that only exists inside a
 * settings app is not a shell command.
 *
 * The commands are NOT validated beyond their name. What someone types runs in
 * their own shell as themselves, which is what a shell is for; the name is
 * checked because a bad one would break every new terminal, silently, for ever.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var commands: page.d.commands || []
    readonly property var shells: page.d.shells || []

    function reload() {
        if (page.backend)
            page.backend.ask("console");
    }

    function add() {
        if (page.backend && nameField.text.trim() !== ""
                && cmdField.text.trim() !== "") {
            page.backend.act(["genesi-console", "add", nameField.text.trim(),
                              cmdField.text.trim(), descField.text.trim()],
                             "console");
            nameField.clear();
            cmdField.clear();
            descField.clear();
        }
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "console")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: page.reload()

    PageFrame {
        anchors.fill: parent
        index: "04"
        group: qsTr("System")
        title: qsTr("Console")
        blurb: qsTr("Commands of your own, in every shell on this machine. They "
                    + "are written as functions rather than aliases, so they "
                    + "still take arguments — a command defined as “sudo pacman "
                    + "-Syu” accepts “--noconfirm” after it.")
        note: page.d.current
              ? qsTr("%1 command(s) · your shell is %2")
                .arg(page.commands.length).arg(page.d.current)
              : qsTr("%1 command(s)").arg(page.commands.length)

        // ── Define one ───────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("New command") }

            Panel {
                width: parent.width
                height: newCol.implicitHeight + 32

                Column {
                    id: newCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 16
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 10

                        Column {
                            width: 190
                            spacing: 5
                            Text {
                                text: qsTr("NAME")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1.4
                            }
                            Field {
                                id: nameField
                                width: parent.width
                                placeholder: "up"
                                onAccepted: page.add()
                            }
                        }

                        Column {
                            width: parent.width - 190 - 10
                            spacing: 5
                            Text {
                                text: qsTr("RUNS")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1.4
                            }
                            Field {
                                id: cmdField
                                width: parent.width
                                placeholder: "sudo pacman -Syu"
                                onAccepted: page.add()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10

                        Column {
                            width: parent.width - 130 - 10
                            spacing: 5
                            Text {
                                text: qsTr("NOTE (OPTIONAL)")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1.4
                            }
                            Field {
                                id: descField
                                width: parent.width
                                mono: false
                                placeholder: qsTr("what it is for")
                                onAccepted: page.add()
                            }
                        }

                        Item {
                            width: 130
                            height: 32 + 5 + 12

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 32
                                radius: Tokens.radiusSm
                                readonly property bool armed:
                                    nameField.text.trim() !== ""
                                    && cmdField.text.trim() !== ""
                                color: armed ? (addHov.hovered ? Tokens.cardHi
                                                               : "transparent")
                                             : "transparent"
                                border.width: 1
                                border.color: armed ? Tokens.accentDim : Tokens.lineSoft
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("DEFINE")
                                    color: parent.armed ? Tokens.text : Tokens.textFaint
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1.4
                                }
                                HoverHandler {
                                    id: addHov
                                    enabled: parent.armed
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler { onTapped: page.add() }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("A name has to be usable as a shell function: letters, "
                           + "digits, - and _, starting with a letter. Names that "
                           + "already mean something — cd, rm, sudo — are refused, "
                           + "because redefining those from a settings window is a "
                           + "trap you set for yourself.")
                color: Tokens.textDim
                font.family: Tokens.sans
                font.pixelSize: 11
                lineHeight: 1.4
                wrapMode: Text.WordWrap
            }
        }

        // ── The commands ─────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.commands.length > 0

            SectionHead { index: "—"; text: qsTr("Defined") }

            Repeater {
                model: page.commands
                delegate: Panel {
                    id: cmdCard
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 76
                    hovered: cmdHov.hovered

                    Column {
                        anchors {
                            left: parent.left; verticalCenter: parent.verticalCenter
                        }
                        anchors.leftMargin: 16
                        width: parent.width - 130
                        spacing: 4

                        Row {
                            spacing: 10
                            Text {
                                text: cmdCard.modelData.name
                                color: Tokens.accent
                                font.family: Tokens.mono
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cmdCard.modelData.description !== ""
                                text: cmdCard.modelData.description
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            width: parent.width
                            text: cmdCard.modelData.command
                            color: Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        anchors.rightMargin: 16
                        width: 96
                        height: 26
                        radius: Tokens.radiusSm
                        color: delHov.hovered ? Tokens.cardHi : "transparent"
                        border.width: 1
                        border.color: delHov.hovered ? Tokens.accentDim : Tokens.line
                        Behavior on color { ColorAnimation { duration: Tokens.quick } }

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("REMOVE")
                            color: delHov.hovered ? Tokens.textHi : Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1
                        }
                        HoverHandler { id: delHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: if (page.backend)
                                page.backend.act(["genesi-console", "remove",
                                                  String(cmdCard.modelData.name)],
                                                 "console")
                        }
                    }

                    HoverHandler { id: cmdHov }
                }
            }
        }

        // ── The shells ───────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("Where they work") }

            Panel {
                width: parent.width
                height: 100

                Row {
                    anchors { left: parent.left; top: parent.top }
                    anchors.margins: 16
                    spacing: 10

                    Repeater {
                        model: page.shells
                        delegate: Rectangle {
                            required property var modelData

                            width: shellName.implicitWidth + 34
                            height: 26
                            radius: Tokens.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: modelData.wired ? Tokens.accentDim : Tokens.line

                            Row {
                                anchors.centerIn: parent
                                spacing: 7
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6; height: 6; radius: 3
                                    color: modelData.wired ? Tokens.accent : Tokens.textFaint
                                }
                                Text {
                                    id: shellName
                                    text: modelData.name
                                    color: modelData.wired ? Tokens.textHi : Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsLabel
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.margins: 16
                    // The one thing people will otherwise report as a bug: the
                    // command exists, and their open terminal has never heard
                    // of it.
                    text: qsTr("Open a new terminal to use a command you just "
                               + "defined — a shell reads these once, when it "
                               + "starts. fish picks them up on its own; bash and "
                               + "zsh get one line added to their rc file, once.")
                    color: Tokens.textDim
                    font.family: Tokens.sans
                    font.pixelSize: 11
                    lineHeight: 1.4
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
