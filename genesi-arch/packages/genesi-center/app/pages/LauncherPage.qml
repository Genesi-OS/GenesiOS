/*
 * LauncherPage — the thing that opens on SUPER, and what Genesi puts in it.
 *
 * The rows are counted by GROUP, not flat. `>bar` and `>shader` each collapse a
 * dozen entries behind one row, and that grouping was not decoration: without
 * it the launcher opened onto a wall of shader names with the applications
 * buried underneath. A flat total would say fifty when it opens with twenty.
 *
 * There is no editor for the rows here. They are shipped as part of
 * shell.json's launcher section and merged into a user's config by ownership on
 * upgrade -- an editor in this app would have to write into that merge, and the
 * first upgrade would either lose the edit or refuse to update the shipped set.
 * Saying so is better than a control that silently loses work.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var o: page.d.options || ({})
    readonly property bool ready: page.d.available === true

    function set(path, value) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "caelestia", path, String(value)],
                             "launcher");
    }

    function num(key, fallback) {
        const v = page.o[key];
        return (v === undefined || v === null) ? fallback : Number(v);
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "launcher")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("launcher")

    PageFrame {
        anchors.fill: parent
        index: "03"
        group: qsTr("Desktop")
        title: qsTr("Launcher")
        blurb: qsTr("How the launcher behaves, and the actions Genesi adds to it. "
                    + "Type %1 in it to reach those instead of applications.")
                    .arg(page.o.actionPrefix || ">")
        note: page.ready
              ? qsTr("%1 row(s) at the prompt · %2 behind a group")
                .arg(page.d.actions_top || 0)
                .arg((page.d.groups || []).reduce((a, g) => a + g.count, 0))
              : qsTr("no caelestia config found")
        noteWarn: !page.ready

        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Where it opens") }

            Row {
                width: parent.width
                spacing: Tokens.gap

                Repeater {
                    model: [
                        { id: "bottom", name: qsTr("From the bottom"),
                          desc: qsTr("Slides up from the screen edge. What "
                                     + "caelestia does.") },
                        { id: "centre", name: qsTr("In the middle"),
                          desc: qsTr("Floats mid-screen, over whatever is "
                                     + "behind it.") }
                    ]
                    delegate: Panel {
                        id: posCard
                        required property var modelData

                        readonly property bool on:
                            (page.o.position || "bottom") === modelData.id

                        width: (parent.width - Tokens.gap) / 2
                        height: 104
                        interactive: true
                        hovered: posHov.hovered
                        color: on ? Tokens.cardHi : Tokens.card
                        border.color: on ? Tokens.accentDim
                                         : (posHov.hovered ? Tokens.accentDeep
                                                           : Tokens.line)

                        // A drawing of where it lands, because that is the
                        // whole difference and no sentence says it faster.
                        Rectangle {
                            id: posSketch
                            anchors { left: parent.left; top: parent.top }
                            anchors.margins: 16
                            width: 58
                            height: 38
                            radius: 3
                            color: "transparent"
                            border.width: 1
                            border.color: posCard.on ? Tokens.accentDim : Tokens.line

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                // One anchor, moved -- never swapped for
                                // undefined. Same rule as the real launcher.
                                y: posCard.modelData.id === "centre"
                                   ? (parent.height - height) / 2
                                   : parent.height - height - 4
                                width: parent.width - 14
                                height: 9
                                radius: 2
                                color: posCard.on ? Tokens.accent : Tokens.textFaint
                                Behavior on y { NumberAnimation { duration: Tokens.quick } }
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }
                        }

                        Column {
                            anchors {
                                left: posSketch.right; right: parent.right
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
                                    text: posCard.modelData.name
                                    color: posCard.on ? Tokens.textHi : Tokens.text
                                    font.family: Tokens.sans
                                    font.pixelSize: 13
                                    width: parent.width - 46
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: posCard.on
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("IN USE")
                                    color: Tokens.accent
                                    font.family: Tokens.mono
                                    font.pixelSize: 8
                                    font.letterSpacing: 1
                                }
                            }
                            Text {
                                width: parent.width
                                text: posCard.modelData.desc
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        HoverHandler { id: posHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (!posCard.on)
                                    page.set("launcher.position",
                                             posCard.modelData.id);
                            }
                        }
                    }
                }
            }

            Panel {
                width: parent.width
                height: widthCol.implicitHeight + 8

                Column {
                    id: widthCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Width")
                        description: qsTr("0 lets it size itself to the results. "
                                          + "A fixed width stops it resizing as "
                                          + "you type, which is the thing people "
                                          + "notice.")
                        last: true
                        Slider {
                            width: 240
                            from: 0; to: 1200; step: 20; unit: "px"
                            value: page.num("width", 0)
                            onReleased: v => page.set("launcher.width", v)
                        }
                    }
                }
            }

            SectionHead { index: "—"; text: qsTr("Behaviour") }

            Panel {
                width: parent.width
                height: optCol.implicitHeight + 8

                Column {
                    id: optCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Results shown")
                        description: qsTr("How many matches fit before the list "
                                          + "scrolls. More is not better: past a "
                                          + "screenful you are reading, not picking.")
                        Slider {
                            width: 220
                            from: 4; to: 16; step: 1
                            value: page.num("maxShown", 8)
                            onReleased: v => page.set("launcher.maxShown", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Wallpaper thumbnails")
                        description: qsTr("How many wallpapers the picker shows at "
                                          + "once.")
                        Slider {
                            width: 220
                            from: 4; to: 24; step: 1
                            value: page.num("maxWallpapers", 9)
                            onReleased: v => page.set("launcher.maxWallpapers", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Vim keys")
                        description: qsTr("Ctrl+J and Ctrl+K move through the list "
                                          + "as well as the arrow keys.")
                        Toggle {
                            checked: page.o.vimKeybinds === true
                            onToggled: v => page.set("launcher.vimKeybinds", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Open on hover")
                        description: qsTr("The launcher appears when the pointer "
                                          + "reaches the screen edge.")
                        Toggle {
                            checked: page.o.showOnHover === true
                            onToggled: v => page.set("launcher.showOnHover", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Allow shutdown and reboot from the prompt")
                        description: qsTr("Off by default. These are one keystroke "
                                          + "and one Enter away from whatever you "
                                          + "were typing.")
                        last: true
                        Toggle {
                            checked: page.o.enableDangerousActions === true
                            onToggled: v => page.set("launcher.enableDangerousActions", v)
                        }
                    }
                }
            }
        }

        // ── The groups ───────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && (page.d.groups || []).length > 0

            SectionHead { index: "—"; text: qsTr("What Genesi adds") }

            Grid {
                id: groupGrid
                width: parent.width
                columns: Math.max(2, Math.floor(width / 220))
                columnSpacing: Tokens.gap
                rowSpacing: Tokens.gap

                readonly property real cell:
                    (width - (columns - 1) * columnSpacing) / columns

                Repeater {
                    model: page.d.groups || []
                    delegate: Panel {
                        required property var modelData
                        width: groupGrid.cell
                        height: 74

                        Column {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            anchors.leftMargin: 16
                            spacing: 4

                            Text {
                                text: (page.o.actionPrefix || ">") + modelData.name
                                color: Tokens.textHi
                                font.family: Tokens.mono
                                font.pixelSize: 14
                            }
                            Text {
                                text: qsTr("%1 entries behind one row").arg(modelData.count)
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("These rows are part of what Genesi installs. They are "
                           + "merged into your config by name on every upgrade, so "
                           + "yours are kept and ours stay current — which is also "
                           + "why there is no editor for them here: anything this "
                           + "page wrote would be fought over by that merge.")
                color: Tokens.textDim
                font.family: Tokens.sans
                font.pixelSize: 11
                lineHeight: 1.4
                wrapMode: Text.WordWrap
            }
        }
    }
}
