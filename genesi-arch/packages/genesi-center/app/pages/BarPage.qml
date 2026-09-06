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
 * Genesi has its own bar, across the top, and this page used to let you switch
 * to it. Doing so broke caelestia badly on hardware, so genesi-bar no longer
 * offers it and the chooser hides itself when there is only one bar to choose.
 * The switcher below is still here and still correct; it simply has nothing to
 * choose between until the top bar is fixed.
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

    readonly property bool sideRail: page.shell === "caelestia"

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
    }

    Component.onCompleted: page.refresh()

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

            // ── Which bar ────────────────────────────────────────────────────
            //
            // Hidden while there is only one to choose. The Genesi top bar is
            // withdrawn -- it broke caelestia on hardware -- and genesi-bar
            // stops listing a withdrawn shell, so this section disappears with
            // it rather than showing a chooser with one card in it.
            Column {
                width: parent.width
                spacing: 10
                visible: page.shells.length > 1

                SectionHead { index: "—"; text: qsTr("Which bar") }

                Row {
                    width: parent.width
                    spacing: Tokens.gap

                    Repeater {
                        model: page.shells

                        delegate: Panel {
                            id: shellCard
                            required property var modelData
                            required property int index

                            readonly property bool on: modelData.id === page.shell

                            width: (parent.width - Tokens.gap) / 2
                            height: 108
                            interactive: true
                            hovered: shov.hovered
                            color: on ? Tokens.cardHi : Tokens.card
                            border.color: on ? Tokens.accentDim
                                             : (shov.hovered ? Tokens.accentDeep : Tokens.line)

                            // A drawing of where the bar actually sits. It is
                            // the one thing a name cannot say, and the whole
                            // difference between the two.
                            Rectangle {
                                id: screenSketch
                                anchors { left: parent.left; top: parent.top }
                                anchors.margins: 16
                                width: 58
                                height: 38
                                radius: 3
                                color: "transparent"
                                border.width: 1
                                border.color: shellCard.on ? Tokens.accentDim : Tokens.line

                                // Two rectangles rather than one with switched
                                // anchors: flipping an anchor between a value
                                // and `undefined` is how a QML item ends up
                                // anchored to nothing and vanishes, and this
                                // sketch is the only thing on the card that
                                // says where the bar goes.
                                Rectangle {
                                    visible: shellCard.modelData.id === "genesi"
                                    anchors {
                                        left: parent.left; right: parent.right
                                        top: parent.top; margins: 3
                                    }
                                    height: 7
                                    radius: 2
                                    color: shellCard.on ? Tokens.accent : Tokens.textFaint
                                    Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                }
                                Rectangle {
                                    visible: shellCard.modelData.id !== "genesi"
                                    anchors {
                                        left: parent.left; top: parent.top
                                        bottom: parent.bottom; margins: 3
                                    }
                                    width: 7
                                    radius: 2
                                    color: shellCard.on ? Tokens.accent : Tokens.textFaint
                                    Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                }
                            }

                            Column {
                                anchors {
                                    left: screenSketch.right
                                    right: parent.right
                                    top: parent.top
                                }
                                anchors.leftMargin: 14
                                anchors.rightMargin: 16
                                anchors.topMargin: 16
                                spacing: 5

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        text: shellCard.modelData.name
                                        color: shellCard.on ? Tokens.textHi : Tokens.text
                                        font.family: Tokens.sans
                                        font.pixelSize: 13
                                        width: parent.width - 54
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: shellCard.on
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("RUNNING")
                                        color: Tokens.accent
                                        font.family: Tokens.mono
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: shellCard.modelData.description
                                    color: Tokens.textDim
                                    font.family: Tokens.sans
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Text {
                                anchors { left: parent.left; bottom: parent.bottom }
                                anchors.margins: 16
                                text: shellCard.modelData.id === "genesi"
                                      ? qsTr("open windows as app icons")
                                      : qsTr("fifteen looks, below")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                            }

                            opacity: 0
                            Component.onCompleted: shellArrive.start()
                            SequentialAnimation {
                                id: shellArrive
                                PauseAnimation { duration: shellCard.index * 70 }
                                NumberAnimation {
                                    target: shellCard; property: "opacity"
                                    from: 0; to: 1
                                    duration: Tokens.normal; easing.type: Easing.OutCubic
                                }
                            }

                            HoverHandler { id: shov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (page.backend && !shellCard.on)
                                        page.backend.barShell(shellCard.modelData.id);
                                }
                            }
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
                        index: "—"
                        text: page.shells.length > 1 ? qsTr("Looks for the side rail")
                                                     : qsTr("Looks")
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
