/*
 * BarPage — the caelestia bar, as ten named arrangements.
 *
 * The bar is already configuration rather than code: `bar.entries` is an
 * ordered list of ids with `spacer` among them, and the components carry two
 * dozen toggles besides. So a preset is a named section of shell.json, and this
 * page is a picker over `genesi-bar` — the same CLI the `>bar` launcher entries
 * call, so the app and the launcher can never disagree about what is applied.
 *
 * Caelestia only. The rail hides this section entirely on Plasma, because a
 * page that writes a shell.json nothing reads is a control that appears to work
 * and changes nothing.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var presets: []
    property string currentId: ""

    function refresh() {
        if (backend)
            backend.barPresets();
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onBarPresetsReady(payload) {
            let d = { presets: [], current: "" };
            try {
                d = JSON.parse(payload);
            } catch (e) {}
            page.presets = d.presets || [];
            page.currentId = d.current || "";
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
            text: qsTr("Ten arrangements of the bar. Picking one rewrites its whole "
                       + "section of shell.json, so a preset is a complete look rather "
                       + "than a patch, and the shell reloads as soon as it lands.")
            color: Tokens.text
            font.family: Tokens.sans
            font.pixelSize: 12
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
        Text {
            text: page.currentId === ""
                  ? qsTr("edited by hand — matches no preset")
                  : qsTr("in use: %1").arg(page.currentId)
            color: page.currentId === "" ? Tokens.textDim : Tokens.accentDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.2
        }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 18
        anchors.bottomMargin: 24
        clip: true
        contentHeight: grid.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

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

                    readonly property bool on: modelData.id === page.currentId

                    width: (grid.width - (grid.columns - 1) * Tokens.gap) / grid.columns
                    height: 118
                    interactive: true
                    hovered: hov.hovered
                    color: on ? Tokens.cardHi : Tokens.card
                    border.color: on ? Tokens.accentDim
                                     : (hov.hovered ? Tokens.accentDeep : Tokens.line)

                    opacity: 0
                    Component.onCompleted: arrive.start()
                    SequentialAnimation {
                        id: arrive
                        PauseAnimation { duration: card.index * 45 }
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

                    // A sketch of the arrangement: the bar is vertical, so this
                    // is its order laid flat, one block per entry. Worth more
                    // than a screenshot would be, because it is drawn from the
                    // same list the shell reads and so cannot go stale.
                    Row {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.margins: 14
                        height: 16
                        spacing: 3

                        Repeater {
                            model: card.modelData.entries || []
                            delegate: Rectangle {
                                required property var modelData
                                width: modelData.id === "spacer"
                                       ? 22 : (modelData.id === "workspaces" ? 26 : 12)
                                height: 8
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

                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (page.backend)
                                page.backend.barApply(card.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
