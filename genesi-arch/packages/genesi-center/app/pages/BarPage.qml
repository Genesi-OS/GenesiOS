/*
 * BarPage — which bar runs, and how it looks.
 *
 * Fifteen looks for caelestia's rail. A look is the bar's whole arrangement
 * PLUS the frame the desktop sits inside, because the frame is where the bar
 * takes its padding from -- they move together whether or not anyone says so,
 * and a preset that changed one and inherited the other would be blamed for
 * whatever the previous one left behind.
 *
 * ── The second bar ──────────────────────────────────────────────────────────
 *
 * Genesi has its own bar, across the top, and this page used to CHOOSE between
 * the two as separate Quickshell processes -- which is what broke caelestia,
 * because switching meant killing it. It is a window inside caelestia now, so
 * the question is no longer which shell runs: it is whether that bar is on,
 * which is one switch. Everything else about it is on the bar itself.
 *
 * Everything goes through `genesi-bar`, the same CLI the `>bar` launcher rows
 * call, so the app and the launcher can never disagree about what is applied.
 *
 * Caelestia only. The rail hides this section entirely on Plasma.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var presets: []
    property var shells: []
    property string currentId: ""
    property string shell: "caelestia"
    // The top bar's own state, from the `desktop` section. Only whether it is
    // on: the rest of its settings live on the bar.
    property var topbar: ({})

    function setTopbar(key, value) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "caelestia",
                              "topbar." + key, String(value)], "desktop");
    }

    // Whether the bar these looks apply to is the one on screen. It used to
    // mean "the caelestia SHELL is the one running", which stopped being a
    // question the moment the top bar became a window inside it. It means the
    // rail is visible, which is what the section below actually depends on.
    readonly property bool sideRail: (page.topbar || {}).enabled !== true

    function refresh() {
        if (backend)
            backend.barPresets();
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onBarPresetsReady(payload) {
            let d = { presets: [], current: "", shells: [], shell: "caelestia" };
            try {
                d = JSON.parse(payload);
            } catch (e) {}
            page.presets = d.presets || [];
            page.currentId = d.current || "";
            page.shells = d.shells || [];
            page.shell = d.shell || "caelestia";
        }

        function onSectionReady(name, payload) {
            if (name !== "desktop")
                return;
            try {
                page.topbar = JSON.parse(payload).topbar || ({});
            } catch (e) {}
        }
    }

    Component.onCompleted: {
        page.refresh();
        if (page.backend)
            page.backend.ask("desktop");
    }

    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 8

        SectionHead { index: "03"; text: qsTr("Desktop") }

        Text {
            text: qsTr("Bar")
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: 34
            font.weight: Font.Light
        }
        Text {
            width: parent.width - 320
            text: qsTr("Fifteen looks for the bar. Each is a complete "
                       + "arrangement plus the frame the desktop sits inside, so "
                       + "switching never leaves a piece of the last one behind — "
                       + "and the frame is where the bar takes its padding from, "
                       + "which is why the two travel together.")
            color: Tokens.text
            font.family: Tokens.sans
            font.pixelSize: 12
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 18
        anchors.bottomMargin: 24
        clip: true
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 18

            // ── The bar across the top ───────────────────────────────────
            //
            // One switch, and it is the only control for that bar in this app.
            // Everything else about it -- where it sits, how tall, what each
            // island carries -- is on the bar's own panel, because you change
            // a bar while looking at it or you change it twice.
            //
            // This used to be a chooser between two Quickshell PROCESSES, and
            // picking Genesi's ran `pkill -f caelestia`. The top bar is a
            // window inside caelestia now, so there is no longer a question of
            // which shell: there is a bar, and it is on or it is not.
            Column {
                width: parent.width
                spacing: 10

                SectionHead { index: "—"; text: qsTr("Top bar") }

                Panel {
                    width: parent.width
                    height: topCol.implicitHeight + 8

                    Column {
                        id: topCol
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 4

                        SettingRow {
                            width: parent.width
                            label: qsTr("A bar across the top")
                            description: qsTr("Three islands along the top edge "
                                              + "instead of caelestia's rail down "
                                              + "the left. Turning it on hides the "
                                              + "rail and reflows every drawer; "
                                              + "turning it off puts the rail back. "
                                              + "Nothing restarts either way.")
                            Toggle {
                                checked: (page.topbar || {}).enabled === true
                                onToggled: v => page.setTopbar("enabled", v)
                            }
                        }

                        Fact {
                            width: parent.width
                            label: qsTr("EVERYTHING ELSE")
                            value: qsTr("the tune button on the bar itself")
                        }
                    }
                }
            }

            // ── The looks ────────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 10

                // Dimmed rather than hidden when the top bar is running. The
                // looks still EXIST; they just do not apply to the bar on
                // screen, and taking them away would read as the app losing a
                // feature rather than as a consequence of the choice above.
                opacity: page.sideRail ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: Tokens.normal } }

                Row {
                    width: parent.width
                    spacing: 12

                    SectionHead {
                        // No rule: this head shares its Row with the status
                        // line beside it, and a rule would fill the row and
                        // push that off the end.
                        rule: false
                        index: "—"
                        text: qsTr("Looks for the side rail")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.sideRail
                              ? (page.currentId === ""
                                 ? qsTr("edited by hand — matches no look")
                                 : qsTr("in use: %1").arg(page.currentId))
                              : qsTr("the top bar is running — these apply to the rail")
                        color: page.sideRail && page.currentId !== ""
                               ? Tokens.accentDim : Tokens.textDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.2
                    }
                }

                Grid {
                    id: grid
                    width: parent.width
                    columns: Math.max(1, Math.floor(width / 290))
                    columnSpacing: Tokens.gap
                    rowSpacing: Tokens.gap

                    Repeater {
                        model: page.presets
                        delegate: Panel {
                            id: card
                            required property var modelData
                            required property int index

                            readonly property bool on: page.sideRail
                                                       && modelData.id === page.currentId

                            width: (grid.width - (grid.columns - 1) * Tokens.gap) / grid.columns
                            height: 126
                            interactive: page.sideRail
                            hovered: hov.hovered && page.sideRail
                            color: on ? Tokens.cardHi : Tokens.card
                            border.color: on ? Tokens.accentDim
                                             : (hov.hovered && page.sideRail
                                                ? Tokens.accentDeep : Tokens.line)

                            opacity: 0
                            Component.onCompleted: arrive.start()
                            SequentialAnimation {
                                id: arrive
                                PauseAnimation { duration: 140 + card.index * 40 }
                                NumberAnimation {
                                    target: card; property: "opacity"
                                    from: 0; to: 1
                                    duration: Tokens.normal; easing.type: Easing.OutCubic
                                }
                            }

                            Column {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: 14
                                spacing: 6

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: card.modelData.name
                                        color: card.on ? Tokens.textHi : Tokens.text
                                        font.family: Tokens.sans
                                        font.pixelSize: 13
                                        width: parent.width - 52
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: card.on
                                        text: qsTr("IN USE")
                                        color: Tokens.accent
                                        font.family: Tokens.mono
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: card.modelData.description
                                    color: Tokens.textDim
                                    font.family: Tokens.sans
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }

                            // The look, drawn rather than described: the rail's
                            // order laid flat, at the width the look sets,
                            // inside the frame it puts round the desktop. Drawn
                            // from the same JSON the shell reads, so it cannot
                            // go stale.
                            Item {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                anchors.margins: 14
                                height: 30

                                id: sketch

                                readonly property var frameCfg: card.modelData.border || ({})
                                // To scale: caelestia's default frame is 10px
                                // against a ~1080px screen, so a couple of
                                // pixels here is the honest size of it. A look
                                // that does not carry a frame gets the default,
                                // which is what applying it would do.
                                readonly property int framePx:
                                    Math.round(Math.min(8, (frameCfg.thickness === undefined
                                                            ? 10 : frameCfg.thickness) / 3.2))
                                readonly property int frameRound:
                                    Math.round(Math.min(10, (frameCfg.rounding === undefined
                                                             ? 25 : frameCfg.rounding) / 3.2))

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Tokens.lineSoft
                                }

                                Rectangle {
                                    id: desk
                                    anchors.fill: parent
                                    anchors.margins: sketch.framePx
                                    radius: sketch.frameRound
                                    color: Tokens.bg
                                    border.width: 1
                                    border.color: card.on ? Tokens.accentDeep : Tokens.lineSoft
                                }

                                Row {
                                    anchors.verticalCenter: desk.verticalCenter
                                    anchors.left: desk.left
                                    anchors.leftMargin: 4
                                    spacing: 2

                                    Repeater {
                                        model: card.modelData.entries || []
                                        delegate: Rectangle {
                                            required property var modelData
                                            // A look's own width, scaled: the
                                            // rail's default inner width is 40,
                                            // so 0 ("the theme's") draws as that.
                                            readonly property int w:
                                                Math.max(3, Math.round(
                                                    (card.modelData.width > 0
                                                     ? card.modelData.width : 40) / 9))
                                            width: modelData.id === "spacer"
                                                   ? 14 : (modelData.id === "workspaces"
                                                           ? w * 2 : w)
                                            height: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: 2
                                            opacity: modelData.enabled ? 1 : 0.22
                                            color: modelData.id === "spacer" ? "transparent"
                                                 : (card.on ? Tokens.accent : Tokens.textFaint)
                                            border.width: modelData.id === "spacer" ? 1 : 0
                                            border.color: Tokens.lineSoft
                                        }
                                    }
                                }
                            }

                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (page.backend && page.sideRail)
                                        page.backend.barApply(card.modelData.id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
