/*
 * ResourcesPage — where the machine's time and memory are actually going.
 *
 * Per-core, not one average. An average cannot tell a busy machine from a
 * single pinned core, and a single pinned core is the shape of the problem
 * people open a monitor to find -- one runaway thread on a sixteen-thread box
 * shows as 6%.
 *
 * The process list is sorted by CPU and shows both readings, because the two
 * questions people arrive with -- "what is making the fan loud" and "what ate
 * my memory" -- have different answers and switching lists to find out is
 * worse than reading two columns.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var cores: page.d.per_core || []
    readonly property var mem: page.d.memory || ({})
    readonly property var procs: page.d.processes || []
    readonly property var mounts: page.d.mounts || []

    function ask() {
        if (page.backend)
            page.backend.ask("resources");
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "resources")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: page.ask()

    // Its own timer rather than riding the Overview's tick: this section sleeps
    // to sample every core, so it must not run while the page is not on screen.
    Timer {
        interval: 3000
        running: page.visible
        repeat: true
        onTriggered: page.ask()
    }

    PageFrame {
        anchors.fill: parent
        index: "01"
        group: qsTr("Overview")
        title: qsTr("Resources")
        blurb: qsTr("Every core on its own, the memory behind the one number the "
                    + "Overview shows, and what is spending them. Sampled while "
                    + "this page is open and stopped as soon as it is not.")
        note: page.d.load
              ? qsTr("load %1  %2  %3").arg(page.d.load[0].toFixed(2))
                                       .arg(page.d.load[1].toFixed(2))
                                       .arg(page.d.load[2].toFixed(2))
              : qsTr("sampling…")

        // ── Cores ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("Processor") }

            Panel {
                width: parent.width
                height: coreGrid.implicitHeight + 32

                Grid {
                    id: coreGrid
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 16
                    columns: Math.max(2, Math.floor(width / 108))
                    columnSpacing: 10
                    rowSpacing: 10

                    readonly property real cell:
                        (width - (columns - 1) * columnSpacing) / columns

                    Repeater {
                        model: page.cores
                        delegate: Item {
                            required property var modelData
                            required property int index

                            width: coreGrid.cell
                            height: 34

                            Text {
                                id: coreName
                                anchors { left: parent.left; top: parent.top }
                                text: "CPU" + (index < 10 ? "0" : "") + index
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                            }
                            Text {
                                anchors { right: parent.right; top: parent.top }
                                text: modelData + "%"
                                color: modelData > 80 ? Tokens.accent : Tokens.text
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 6
                                radius: 3
                                color: Tokens.lineSoft

                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * Math.max(0, Math.min(100, modelData)) / 100
                                    radius: 3
                                    color: modelData > 80 ? Tokens.accent : Tokens.accentDim
                                    // The width is a BINDING to the reading, so
                                    // the bar has to be animated with a
                                    // Behavior. Animating it imperatively would
                                    // destroy that binding on the first tick and
                                    // the bar would freeze at whatever it showed.
                                    Behavior on width {
                                        NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Memory ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("Memory") }

            Row {
                width: parent.width
                spacing: Tokens.gap

                Panel {
                    width: (parent.width - Tokens.gap) / 2
                    height: 96

                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 16
                        spacing: 10

                        Row {
                            width: parent.width
                            Text {
                                text: qsTr("RAM")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                font.letterSpacing: 1.4
                                width: parent.width - 120
                            }
                            Text {
                                width: 120
                                horizontalAlignment: Text.AlignRight
                                text: page.mem.total_mb
                                      ? qsTr("%1 / %2 GB")
                                        .arg((page.mem.used_mb / 1024).toFixed(1))
                                        .arg((page.mem.total_mb / 1024).toFixed(1))
                                      : "—"
                                color: Tokens.text
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsLabel
                            }
                        }
                        Text {
                            text: (page.mem.percent === null
                                   || page.mem.percent === undefined)
                                  ? "—" : page.mem.percent + "%"
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 26
                            font.weight: Font.Light
                        }
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Tokens.lineSoft
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * Math.max(0, Math.min(100, page.mem.percent || 0)) / 100
                                radius: 3
                                color: Tokens.accentDim
                                Behavior on width { NumberAnimation { duration: Tokens.normal } }
                            }
                        }
                    }
                }

                Panel {
                    width: (parent.width - Tokens.gap) / 2
                    height: 96

                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 16
                        spacing: 10

                        Text {
                            text: qsTr("SWAP")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            // No swap at all and swap we could not read are
                            // different answers, so they are different words.
                            text: page.d.swap_total_mb === null
                                  || page.d.swap_total_mb === undefined
                                  ? "—"
                                  : (page.d.swap_total_mb === 0
                                     ? qsTr("none")
                                     : qsTr("%1 / %2 GB")
                                       .arg((page.d.swap_used_mb / 1024).toFixed(1))
                                       .arg((page.d.swap_total_mb / 1024).toFixed(1)))
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 26
                            font.weight: Font.Light
                        }
                        Text {
                            text: page.d.swap_total_mb > 0
                                  ? qsTr("in use when RAM runs short")
                                  : qsTr("this machine runs on RAM alone")
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }
                }
            }
        }

        // ── Processes ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10

            SectionHead { index: "—"; text: qsTr("What is spending it") }

            Panel {
                width: parent.width
                height: procCol.implicitHeight + 28

                Column {
                    id: procCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 14
                    spacing: 0

                    Row {
                        width: parent.width
                        height: 22
                        Text {
                            width: parent.width - 210
                            text: qsTr("PROCESS")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            width: 60; horizontalAlignment: Text.AlignRight
                            text: qsTr("CPU")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            width: 70; horizontalAlignment: Text.AlignRight
                            text: qsTr("MEMORY")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                        Text {
                            width: 80; horizontalAlignment: Text.AlignRight
                            text: qsTr("RSS")
                            color: Tokens.textFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 1.4
                        }
                    }

                    Repeater {
                        // Twelve, not the twenty-five the reader returns: past
                        // that it is a process list, and a process list is a
                        // different tool.
                        model: page.procs.slice(0, 12)
                        delegate: Item {
                            required property var modelData
                            required property int index

                            width: procCol.width
                            height: 24

                            Rectangle {
                                anchors.fill: parent
                                color: index % 2 === 0 ? "transparent" : Tokens.cardHi
                                opacity: 0.5
                            }
                            Row {
                                anchors.fill: parent
                                Text {
                                    width: parent.width - 210
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: 60; horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.cpu.toFixed(1) + "%"
                                    color: modelData.cpu > 20 ? Tokens.accent : Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: 70; horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.mem.toFixed(1) + "%"
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: 80; horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.rss_mb + " MB"
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

        // ── Mounts ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.mounts.length > 0

            SectionHead { index: "—"; text: qsTr("Filesystems") }

            Grid {
                id: mountGrid
                width: parent.width
                columns: Math.max(1, Math.floor(width / 300))
                columnSpacing: Tokens.gap
                rowSpacing: Tokens.gap

                readonly property real cell:
                    (width - (columns - 1) * columnSpacing) / columns

                Repeater {
                    model: page.mounts
                    delegate: Panel {
                        required property var modelData
                        width: mountGrid.cell
                        height: 72

                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14
                            spacing: 8

                            Row {
                                width: parent.width
                                Text {
                                    width: parent.width - 110
                                    text: modelData.path
                                    color: Tokens.textHi
                                    font.family: Tokens.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                                Text {
                                    width: 110; horizontalAlignment: Text.AlignRight
                                    text: qsTr("%1 / %2 GB").arg(modelData.used_gb)
                                                            .arg(modelData.total_gb)
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 10
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Tokens.lineSoft
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100
                                    radius: 3
                                    color: modelData.percent > 90 ? Tokens.accent : Tokens.accentDim
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
