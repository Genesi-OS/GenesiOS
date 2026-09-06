/*
 * WidgetsPage — what is drawn on the wallpaper.
 *
 * caelestia already ships two: a clock and an audio visualiser. Both are off
 * by default and, until this page, nothing could turn either on -- so in
 * practice they did not exist. That is the cheapest kind of feature to add:
 * the drawing is written, tested and shipped, and all that was missing was a
 * way to reach it.
 *
 * The clock takes one of nine positions, so this offers a nine-cell grid you
 * click rather than a dropdown of hyphenated words. It is the same information
 * and it is the difference between choosing a place and reading a list.
 *
 * Everything here is upstream's own config -- no patch, nothing added to
 * caelestia's C++ -- which after two withdrawn features is the point: these
 * settings cannot stop working because a patch of ours stopped applying.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var clock: page.d.clock || ({})
    readonly property var vis: page.d.visualiser || ({})
    readonly property bool ready: page.d.available === true

    function set(path, value) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "caelestia", path,
                              String(value)], "desktop");
    }

    function num(node, key, fallback) {
        const v = node[key];
        return (v === undefined || v === null) ? fallback : Number(v);
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "desktop")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("desktop")

    PageFrame {
        anchors.fill: parent
        index: "03"
        group: qsTr("Desktop")
        title: qsTr("Widgets")
        blurb: qsTr("What sits on the wallpaper itself. A clock you can put in "
                    + "any of nine places, and a visualiser that rises with "
                    + "whatever is playing — both drawn behind your windows, "
                    + "so they are there when the desktop is and gone when it "
                    + "is not.")
        note: page.ready
              ? qsTr("clock %1 · visualiser %2")
                .arg(page.clock.enabled ? qsTr("on") : qsTr("off"))
                .arg(page.vis.enabled ? qsTr("on") : qsTr("off"))
              : qsTr("no caelestia config found")
        noteWarn: !page.ready

        // ── The clock ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Clock") }

            Row {
                id: clockRow
                width: parent.width
                spacing: Tokens.gap

                // Both halves share ONE height, taken from whichever is
                // taller. Pinning the settings panel to the picker's height
                // clipped its last row -- the picker is a fixed square and the
                // settings are however many rows there are.
                readonly property int rowHeight:
                    Math.max(176, clockCol.implicitHeight + 8)

                // The nine positions, as a screen you click. A dropdown of
                // "middle-left / bottom-center" is the same data and none of
                // the meaning.
                Panel {
                    id: placer
                    width: 232
                    height: clockRow.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 18
                        radius: Tokens.radiusSm
                        color: Tokens.bg
                        border.width: 1
                        border.color: Tokens.lineSoft

                        Grid {
                            id: cells
                            anchors.fill: parent
                            anchors.margins: 6
                            columns: 3
                            rowSpacing: 4
                            columnSpacing: 4

                            readonly property var names: [
                                "top-left", "top-center", "top-right",
                                "middle-left", "middle-center", "middle-right",
                                "bottom-left", "bottom-center", "bottom-right"]

                            Repeater {
                                model: cells.names
                                delegate: Rectangle {
                                    id: cell
                                    required property var modelData

                                    readonly property bool on:
                                        (page.clock.position || "bottom-right")
                                        === modelData

                                    width: (cells.width - 8) / 3
                                    height: (cells.height - 8) / 3
                                    radius: 3
                                    color: on ? Tokens.accentDeep
                                              : (cellHov.hovered ? Tokens.cardHi
                                                                 : "transparent")
                                    border.width: 1
                                    border.color: on ? Tokens.accentDim
                                                     : (cellHov.hovered
                                                        ? Tokens.accentDeep
                                                        : Tokens.lineSoft)
                                    Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                    Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

                                    // A little clock face in the chosen cell,
                                    // so the grid shows the answer rather than
                                    // just recording it.
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        visible: cell.on && page.clock.enabled
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "09:41"
                                            color: Tokens.accent
                                            font.family: Tokens.mono
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: qsTr("Mon")
                                            color: Tokens.accentDim
                                            font.family: Tokens.mono
                                            font.pixelSize: 7
                                        }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: cell.on && !page.clock.enabled
                                        width: 5; height: 5; radius: 3
                                        color: Tokens.textFaint
                                    }

                                    HoverHandler { id: cellHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: page.set(
                                            "background.desktopClock.position",
                                            cell.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                Panel {
                    width: parent.width - placer.width - Tokens.gap
                    height: clockRow.rowHeight

                    Column {
                        id: clockCol
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 4

                        SettingRow {
                            width: parent.width
                            label: qsTr("Show the clock")
                            description: qsTr("Behind your windows, on the "
                                              + "wallpaper.")
                            Toggle {
                                checked: page.clock.enabled === true
                                onToggled: v => page.set(
                                    "background.desktopClock.enabled", v)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Size")
                            Slider {
                                width: 200
                                from: 40; to: 250; step: 5; unit: "%"
                                value: Math.round(page.num(page.clock, "scale", 1) * 100)
                                onReleased: v => page.set(
                                    "background.desktopClock.scale", v / 100)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Plate behind it")
                            description: qsTr("A translucent panel, for a "
                                              + "wallpaper busy enough to eat "
                                              + "the numbers.")
                            Toggle {
                                checked: page.clock.background === true
                                onToggled: v => page.set(
                                    "background.desktopClock.background.enabled", v)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Drop shadow")
                            last: true
                            Toggle {
                                checked: page.clock.shadow === true
                                onToggled: v => page.set(
                                    "background.desktopClock.shadow.enabled", v)
                            }
                        }
                    }
                }
            }

            Panel {
                width: parent.width
                height: invCol.implicitHeight + 8

                Column {
                    id: invCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Invert the colours")
                        description: qsTr("For a light wallpaper. The clock takes "
                                          + "its colour from the scheme, and on a "
                                          + "pale photograph that can vanish.")
                        last: true
                        Toggle {
                            checked: page.clock.invertColors === true
                            onToggled: v => page.set(
                                "background.desktopClock.invertColors", v)
                        }
                    }
                }
            }
        }

        // ── The visualiser ───────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Audio visualiser") }

            Panel {
                width: parent.width
                height: visCol.implicitHeight + 8

                Column {
                    id: visCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Show the visualiser")
                        description: qsTr("Bars along the bottom of the wallpaper "
                                          + "that move with whatever is playing.")
                        Toggle {
                            checked: page.vis.enabled === true
                            onToggled: v => page.set(
                                "background.visualiser.enabled", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Hide it when nothing is playing")
                        description: qsTr("Off means a flat line sits there in "
                                          + "silence.")
                        Toggle {
                            checked: page.vis.autoHide === true
                            onToggled: v => page.set(
                                "background.visualiser.autoHide", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Rounded bars")
                        Slider {
                            width: 200
                            from: 0; to: 300; step: 10; unit: "%"
                            value: Math.round(page.num(page.vis, "rounding", 1) * 100)
                            onReleased: v => page.set(
                                "background.visualiser.rounding", v / 100)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Gap between bars")
                        Slider {
                            width: 200
                            from: 0; to: 300; step: 10; unit: "%"
                            value: Math.round(page.num(page.vis, "spacing", 1) * 100)
                            onReleased: v => page.set(
                                "background.visualiser.spacing", v / 100)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Blur it")
                        description: qsTr("Softens the bars into the wallpaper "
                                          + "instead of sitting on top of it.")
                        last: true
                        Toggle {
                            checked: page.vis.blur === true
                            onToggled: v => page.set(
                                "background.visualiser.blur", v)
                        }
                    }
                }
            }
        }

        // ── The wallpaper underneath ─────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("The wallpaper") }

            Panel {
                width: parent.width
                height: wallCol.implicitHeight + 8

                Column {
                    id: wallCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Show the wallpaper")
                        description: qsTr("Off leaves the scheme's own background "
                                          + "colour, which is flatter and quicker "
                                          + "and what some people want.")
                        Toggle {
                            checked: page.d.wallpaper !== false
                            onToggled: v => page.set("background.wallpaperEnabled", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Change takes")
                        description: qsTr("How long a new wallpaper takes to "
                                          + "arrive. 0 uses the transition's own "
                                          + "timing.")
                        last: true
                        Slider {
                            width: 200
                            from: 0; to: 2500; step: 50; unit: "ms"
                            value: page.num(page.d, "transitionDuration", 0)
                            onReleased: v => page.set(
                                "background.transitionDuration", v)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("Which image, and how it arrives, are on the "
                           + "Appearance page — the picker there has thumbnails.")
                color: Tokens.textDim
                font.family: Tokens.sans
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
