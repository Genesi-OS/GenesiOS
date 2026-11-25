/*
 * SnapshotsPage — the undo button for the whole system.
 *
 * Everything here goes through `genesi-snapshots`, which already prints JSON
 * for exactly this. Nothing in this page reads btrfs or snapper itself: two
 * readers of one fact eventually disagree, and here the fact is "can this
 * machine be rolled back", which is not a thing to be vague about.
 *
 * Rollback is deliberately NOT a button on this page. It reboots into another
 * root, and it belongs behind the tool that can explain what is about to
 * happen and confirm it -- not behind a card in a settings app that a stray
 * click can reach. Creating a snapshot is safe and is here.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})
    property bool working: false

    readonly property bool ready: page.d.available === true
    readonly property var snaps: page.d.snapshots || []
    readonly property var status: page.d.status || ({})

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "snapshots")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
            page.working = false;
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("snapshots")

    PageFrame {
        anchors.fill: parent
        index: "04"
        group: qsTr("System")
        title: qsTr("Snapshots")
        blurb: qsTr("A copy of the whole system, taken before every package "
                    + "change and whenever you ask. If an update breaks "
                    + "something, the last good one is in the boot menu.")
        note: page.ready
              ? (page.d.configured
                 ? qsTr("%1 snapshot(s)").arg(page.snaps.length)
                 : qsTr("snapper is not configured on this machine"))
              : qsTr("genesi-snapshots is not installed")
        noteWarn: !page.ready || !page.d.configured

        // ── Take one ─────────────────────────────────────────────────────────
        Panel {
            width: parent.width
            height: 92
            visible: page.ready && page.d.configured

            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 20
                width: parent.width - 220
                spacing: 5

                Text {
                    text: qsTr("Take one now")
                    color: Tokens.textHi
                    font.family: Tokens.sans
                    font.pixelSize: 15
                }
                Text {
                    width: parent.width
                    text: qsTr("Worth doing before you change something by hand. "
                               + "Package installs already take their own.")
                    color: Tokens.textDim
                    font.family: Tokens.sans
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.rightMargin: 20
                width: 160
                height: 32
                radius: Tokens.radiusSm
                color: page.working ? Tokens.accentDeep
                                    : (snapHov.hovered ? Tokens.cardHi : "transparent")
                border.width: 1
                border.color: snapHov.hovered || page.working ? Tokens.accentDim : Tokens.line
                Behavior on color { ColorAnimation { duration: Tokens.quick } }

                Text {
                    anchors.centerIn: parent
                    text: page.working ? qsTr("TAKING…") : qsTr("TAKE A SNAPSHOT")
                    color: page.working ? Tokens.accent : Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    font.letterSpacing: 1
                }
                HoverHandler { id: snapHov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (page.working || !page.backend)
                            return;
                        // The flag is cleared when the re-read comes back, not
                        // on a timer: the button says "taking" for exactly as
                        // long as it is taking.
                        page.working = true;
                        page.backend.act(["genesi-snapshots", "create",
                                          "Genesi Center"], "snapshots");
                    }
                }
            }
        }

        // ── The list ─────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && page.snaps.length > 0

            SectionHead { index: "—"; text: qsTr("Taken") }

            Panel {
                width: parent.width
                height: snapCol.implicitHeight + 22

                Column {
                    id: snapCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 11
                    spacing: 0

                    Row {
                        width: parent.width
                        height: 22
                        Text {
                            width: 54
                            text: "#"
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            width: parent.width - 240
                            text: qsTr("DESCRIPTION")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            width: 186
                            horizontalAlignment: Text.AlignRight
                            text: qsTr("WHEN")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                    }

                    Repeater {
                        // Newest first, and only as many as read at a glance.
                        // The full list is `genesi-snapshots list`, which is
                        // where someone hunting a specific one should be.
                        model: page.snaps.slice(0, 14)
                        delegate: Item {
                            required property var modelData
                            required property int index

                            width: snapCol.width
                            height: 26

                            Rectangle {
                                anchors.fill: parent
                                color: index % 2 === 0 ? "transparent" : Tokens.cardHi
                                opacity: 0.5
                            }
                            Row {
                                anchors.fill: parent
                                Text {
                                    width: 54
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.number !== undefined
                                          ? String(modelData.number) : "—"
                                    color: Tokens.accentDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: parent.width - 240
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.description || modelData.type || "—"
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: 186
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.date || "—"
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

        // ── Rolling back ─────────────────────────────────────────────────────
        Panel {
            width: parent.width
            height: 108
            visible: page.ready && page.d.configured

            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 20
                width: parent.width - 220
                spacing: 5

                Text {
                    text: qsTr("Going back")
                    color: Tokens.textHi
                    font.family: Tokens.sans
                    font.pixelSize: 15
                }
                Text {
                    width: parent.width
                    text: qsTr("Every snapshot is an entry in the boot menu, so a "
                               + "machine that will not start can still be "
                               + "recovered without this app. Rolling back from a "
                               + "running system is done in the Snapshots tool, "
                               + "which asks before it reboots you into another "
                               + "root.")
                    color: Tokens.textDim
                    font.family: Tokens.sans
                    font.pixelSize: 11
                    lineHeight: 1.4
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.rightMargin: 20
                width: 160
                height: 32
                radius: Tokens.radiusSm
                color: rollHov.hovered ? Tokens.cardHi : "transparent"
                border.width: 1
                border.color: rollHov.hovered ? Tokens.accentDim : Tokens.line
                Behavior on color { ColorAnimation { duration: Tokens.quick } }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("OPEN SNAPSHOTS")
                    color: Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    font.letterSpacing: 1
                }
                HoverHandler { id: rollHov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: if (page.backend)
                        page.backend.launch(["genesi-snapshots-gui"])
                }
            }
        }
    }
}
