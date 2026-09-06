/*
 * DisplaysPage — the monitors, arranged and configured.
 *
 * Two halves, as the reference has them: a canvas on the left where the screens
 * are dragged into the shape they sit in on the desk, and the selected
 * screen's settings on the right.
 *
 * Everything goes through `genesi-display`, which is also what the launcher
 * entries, the keybinds and caelestia's own Display page call. The compositor
 * takes a WHOLE monitor line, so changing a resolution means rewriting scale,
 * refresh and position too, and getting the position wrong moves somebody's
 * second screen -- that belongs in one tool, not in three front-ends.
 *
 * Nothing here is applied until it is asked for. A settings page that writes on
 * every keystroke cannot be explored, and a display setting is the one kind you
 * most want to try: the worst case is a screen that does not come back.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var monitors: []
    property string selected: ""
    property bool busy: false

    readonly property var current: {
        for (const m of monitors)
            if (m.name === selected)
                return m;
        return monitors.length > 0 ? monitors[0] : null;
    }

    function refresh() {
        if (backend)
            backend.displays();
    }

    function run(args) {
        if (!backend)
            return;
        page.busy = true;
        backend.displayCmd(args);
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onDisplaysReady(payload) {
            let list = [];
            try {
                list = JSON.parse(payload);
            } catch (e) {
                list = [];
            }
            page.monitors = list;
            page.busy = false;
            if (page.selected === "" && list.length > 0) {
                // The focused screen is the one the person is looking at, which
                // is a better first selection than whichever came back first.
                let pick = list[0].name;
                for (const m of list)
                    if (m.focused)
                        pick = m.name;
                page.selected = pick;
            }
        }
    }

    Component.onCompleted: page.refresh()

    // ── Heading ──────────────────────────────────────────────────────────────
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 8

        SectionHead { index: "02"; text: qsTr("Devices") }

        Text {
            text: qsTr("Displays")
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: 34
            font.weight: Font.Light
        }
        Text {
            width: parent.width - 320
            text: qsTr("Drag the screens into the shape they sit in on your desk, then set "
                       + "resolution, refresh rate, scale and rotation for each. Changes "
                       + "apply to the running session and are kept for the next one.")
            color: Tokens.text
            font.family: Tokens.sans
            font.pixelSize: 12
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
        Text {
            text: page.monitors.length === 1
                  ? qsTr("1 display detected")
                  : qsTr("%1 displays detected").arg(page.monitors.length)
            color: Tokens.textDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.2
        }
    }

    // ── The desk ─────────────────────────────────────────────────────────────
    Panel {
        id: canvasCard
        anchors { left: parent.left; top: head.bottom; bottom: parent.bottom }
        anchors.leftMargin: 28
        anchors.topMargin: 18
        anchors.bottomMargin: 24
        width: parent.width - 400

        MonitorCanvas {
            anchors.fill: parent
            anchors.margins: 18
            anchors.bottomMargin: 34
            monitors: page.monitors
            selected: page.selected
            onPick: name => page.selected = name
            onMoved: (name, x, y) => page.run(["place", name, String(x), String(y)])
        }

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            anchors.bottomMargin: 12
            text: qsTr("Drag a screen to where it sits on your desk — edges snap")
            color: Tokens.textFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
        }
    }

    // ── The selected screen ──────────────────────────────────────────────────
    Panel {
        id: detail
        anchors { right: parent.right; top: head.bottom; bottom: parent.bottom }
        anchors.rightMargin: 28
        anchors.leftMargin: Tokens.gap
        anchors.topMargin: 18
        anchors.bottomMargin: 24
        width: 356
        clip: true

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 0

            Item {
                width: parent.width
                height: 42
                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: page.current ? ("// " + page.current.name + "_") : "//"
                    color: Tokens.accent
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsLabel
                    font.letterSpacing: 1.2
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    visible: page.current !== null && page.current.description !== ""
                    text: page.current ? page.current.description : ""
                    color: Tokens.textFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    elide: Text.ElideRight
                    width: 160
                    horizontalAlignment: Text.AlignRight
                }
                Rectangle {
                    // leftMargin/rightMargin, NOT `margins`: that sets the bottom
                    // one too and lifts the rule into the row, through the text.
                    anchors {
                        left: parent.left; right: parent.right
                        bottom: parent.bottom
                        leftMargin: 14; rightMargin: 14
                    }
                    height: 1
                    color: Tokens.lineSoft
                }
            }

            Row_MainScreen {
                width: parent.width
                enabled: page.current !== null
                // Reported by genesi-display, not inferred. Position 0,0 is
                // where the leftmost screen happens to sit and has nothing to
                // do with which one the desktop starts on.
                isPrimary: page.current ? page.current.primary === true : false
                onMakePrimary: page.run(["primary", page.current.name])
            }

            Row {
                id: modeRow
                width: parent.width
                height: 62
                Item {
                    width: parent.width
                    height: parent.height
                    Column {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        // Stop before the control. Without this the description
                        // ran the full width of the card and under it.
                        width: parent.width - 210
                        spacing: 2
                        Text {
                            text: qsTr("Resolution")
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 13
                        }
                        Text {
                            text: qsTr("Size and refresh rate the panel runs at")
                            color: Tokens.textDim
                            font.family: Tokens.sans
                            font.pixelSize: 11
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                    Select {
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        width: 178
                        options: page.current
                                 ? page.current.modes.map(m => ({
                                       id: m.id,
                                       label: m.width + " × " + m.height + "  ·  " + m.refresh + " Hz"
                                   }))
                                 : []
                        current: page.current ? page.current.mode : ""
                        onPicked: id => page.run(["mode", page.current.name, id])
                    }
                    Rectangle {
                        // leftMargin/rightMargin, NOT `margins`: that sets the
                        // bottom one too and lifts the rule 14px into the row,
                        // where it is drawn straight through the sentence under
                        // the heading. Same mistake SettingRow had.
                        anchors {
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            leftMargin: 14; rightMargin: 14
                        }
                        height: 1
                        color: Tokens.lineSoft
                    }
                }
            }

            Row {
                width: parent.width
                height: 58
                Item {
                    width: parent.width
                    height: parent.height
                    Column {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        // Stop before the control. Without this the description
                        // ran the full width of the card and under it.
                        width: parent.width - 210
                        spacing: 2
                        Text {
                            text: qsTr("Scale")
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 13
                        }
                        Text {
                            text: qsTr("How large everything is drawn")
                            color: Tokens.textDim
                            font.family: Tokens.sans
                            font.pixelSize: 11
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                    Segmented {
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        options: [
                            { id: "1",    label: "100%" },
                            { id: "1.25", label: "125%" },
                            { id: "1.5",  label: "150%" },
                            { id: "2",    label: "200%" }
                        ]
                        current: page.current ? String(page.current.scale) : ""
                        onPicked: id => page.run(["scale", page.current.name, id])
                    }
                    Rectangle {
                        // leftMargin/rightMargin, NOT `margins`: that sets the
                        // bottom one too and lifts the rule 14px into the row,
                        // where it is drawn straight through the sentence under
                        // the heading. Same mistake SettingRow had.
                        anchors {
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            leftMargin: 14; rightMargin: 14
                        }
                        height: 1
                        color: Tokens.lineSoft
                    }
                }
            }

            Row {
                width: parent.width
                height: 58
                Item {
                    width: parent.width
                    height: parent.height
                    Column {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        // Stop before the control. Without this the description
                        // ran the full width of the card and under it.
                        width: parent.width - 210
                        spacing: 2
                        Text {
                            text: qsTr("Rotation")
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 13
                        }
                        Text {
                            text: qsTr("Which way up the panel is mounted")
                            color: Tokens.textDim
                            font.family: Tokens.sans
                            font.pixelSize: 11
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                    Segmented {
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        options: [
                            { id: "0",   label: "0°" },
                            { id: "90",  label: "90°" },
                            { id: "180", label: "180°" },
                            { id: "270", label: "270°" }
                        ]
                        current: page.current && page.current.rotation !== null
                                 ? String(page.current.rotation) : ""
                        onPicked: id => page.run(["rotate", page.current.name, id])
                    }
                    Rectangle {
                        // leftMargin/rightMargin, NOT `margins`: that sets the
                        // bottom one too and lifts the rule 14px into the row,
                        // where it is drawn straight through the sentence under
                        // the heading. Same mistake SettingRow had.
                        anchors {
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            leftMargin: 14; rightMargin: 14
                        }
                        height: 1
                        color: Tokens.lineSoft
                    }
                }
            }
        }

        // The undo. It is at the bottom, on its own, because it is the only
        // control here that throws work away.
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.margins: 14
            spacing: 8

            Text {
                width: parent.width
                text: qsTr("Undo every resolution, scale, rotation and position set from "
                           + "here. Anything you wrote in hyprland.conf yourself is left "
                           + "alone.")
                color: Tokens.textDim
                font.family: Tokens.sans
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Rectangle {
                width: 132; height: 28; radius: Tokens.radiusSm
                color: reset.hovered ? Tokens.cardHi : "transparent"
                border.width: 1
                border.color: Tokens.line
                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                Text {
                    anchors.centerIn: parent
                    text: qsTr("RESET DISPLAYS")
                    color: Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
                HoverHandler { id: reset; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: page.run(["reset"]) }
            }
        }
    }

    // A row that is only ever one control, kept inline so the column above
    // reads as a list of settings rather than a list of layout scaffolding.
    component Row_MainScreen: Item {
        property bool isPrimary: false
        signal makePrimary

        height: 58
        Column {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: parent.width - 130
            spacing: 2
            Text {
                text: qsTr("Main screen")
                color: Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: 13
            }
            Text {
                width: parent.width
                text: qsTr("Where the desktop starts and full-screen apps open")
                color: Tokens.textDim
                font.family: Tokens.sans
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 92; height: 26; radius: Tokens.radiusSm
            visible: !parent.isPrimary
            color: mh.hovered ? Tokens.accentDeep : "transparent"
            border.width: 1
            border.color: Tokens.accentDim
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
            Text {
                anchors.centerIn: parent
                text: qsTr("SET")
                color: Tokens.accent
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: parent.parent.makePrimary() }
        }
        Text {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            visible: parent.isPrimary
            text: qsTr("PRIMARY")
            color: Tokens.accent
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.2
        }
        Rectangle {
            // leftMargin/rightMargin, NOT `margins`: that sets the bottom
            // one too and lifts the rule into the row, through the text.
            anchors {
                left: parent.left; right: parent.right
                bottom: parent.bottom
                leftMargin: 14; rightMargin: 14
            }
            height: 1
            color: Tokens.lineSoft
        }
    }
}
