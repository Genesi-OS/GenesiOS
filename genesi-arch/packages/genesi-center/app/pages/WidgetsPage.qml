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

    readonly property var corners: [
        { id: "", label: qsTr("Where it prefers") },
        { id: "top-left", label: qsTr("Top left") },
        { id: "top-centre", label: qsTr("Top centre") },
        { id: "top-right", label: qsTr("Top right") },
        { id: "mid-left", label: qsTr("Middle left") },
        { id: "centre", label: qsTr("Centre") },
        { id: "mid-right", label: qsTr("Middle right") },
        { id: "bottom-left", label: qsTr("Bottom left") },
        { id: "bottom-centre", label: qsTr("Bottom centre") },
        { id: "bottom-right", label: qsTr("Bottom right") },
        // Not pickable in the usual sense -- it is what a widget becomes when
        // it is dragged on the desktop. It is in the list so a dragged widget
        // says where it is rather than showing a blank.
        { id: "free", label: qsTr("Where you dropped it") }
    ]

    // The names and the one line under each. Copy lives with the page that
    // shows it, not in the data plane, which reports config and nothing else.
    readonly property var widgetText: ({
        "weather": [qsTr("Weather"), qsTr("Now: the glyph, the temperature and what it actually feels like.")],
        "forecast": [qsTr("Forecast"), qsTr("Four days. Five is a table and three is not a forecast.")],
        "media": [qsTr("Now playing"), qsTr("Art, title, artist and how far through. Hidden when nothing is.")],
        "cpu": [qsTr("Processor"), qsTr("Load as a ring, with the temperature under it.")],
        "memory": [qsTr("Memory"), qsTr("Used against total, in GiB.")],
        "storage": [qsTr("Storage"), qsTr("The primary disk, and how much of it is left.")],
        "network": [qsTr("Network"), qsTr("Down and up, each on its own line.")],
        "battery": [qsTr("Battery"), qsTr("Charge and time left. Draws nothing on a desktop.")],
        "calendar": [qsTr("Calendar"), qsTr("The month, with today marked.")],
        "analogClock": [qsTr("Analogue clock"), qsTr("Hands. The digital one is better read; this one is better looked at.")],
        "workspaces": [qsTr("Workspaces"), qsTr("One pill each: filled when occupied, wide when active.")],
        "notifications": [qsTr("Notifications"), qsTr("The last three still open. A wallpaper is not an inbox.")],
        "uptime": [qsTr("Uptime"), qsTr("How long since the machine came up.")],
        "greeting": [qsTr("Greeting"), qsTr("Your name, and the time of day. The one that is not a readout.")]
    })

    function widgetName(id) {
        const e = page.widgetText[id];
        return e ? e[0] : id;
    }

    function widgetBlurb(id) {
        const e = page.widgetText[id];
        return e ? e[1] : "";
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
                    // Same reason as shapePreview: this card IS a diagram.
                    ticks: false
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

        // ── What Genesi adds ─────────────────────────────────────────────────
        //
        // Fourteen rows drawn from one list rather than fourteen hand-written
        // blocks. A page that repeats itself fourteen times is a page where the
        // fifteenth widget gets a row that is subtly different from the others.
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("The dock") }

            Panel {
                width: parent.width
                height: dockCol.implicitHeight + 8

                Column {
                    id: dockCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Show the dock")
                        description: qsTr("The open applications as icons along "
                                          + "the bottom edge, grouped one icon "
                                          + "per application. It sits above "
                                          + "windows, so it is there when you "
                                          + "need it.")
                        Toggle {
                            checked: (page.d.dock || ({})).enabled === true
                            onToggled: v => page.set("dock.enabled", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Icon size")
                        visible: (page.d.dock || ({})).enabled === true
                        Slider {
                            width: 200
                            from: 24; to: 96; step: 4; unit: "px"
                            value: page.num(page.d.dock || ({}), "iconSize", 44)
                            onReleased: v => page.set("dock.iconSize", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("The flow")
                        description: qsTr("Lights running along a track between "
                                          + "one icon and the next. Decoration, "
                                          + "and the thing that makes a row of "
                                          + "icons feel like part of a desktop.")
                        visible: (page.d.dock || ({})).enabled === true
                        Toggle {
                            checked: (page.d.dock || ({})).flow !== false
                            onToggled: v => page.set("dock.flow", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Hide it when nothing is open")
                        description: qsTr("An empty dock is a bar with nothing "
                                          + "in it.")
                        visible: (page.d.dock || ({})).enabled === true
                        Toggle {
                            checked: (page.d.dock || ({})).hideWhenEmpty !== false
                            onToggled: v => page.set("dock.hideWhenEmpty", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("A bar behind the icons")
                        description: qsTr("Off, the icons float on the desktop "
                                          + "with nothing behind them — which "
                                          + "is not the same as a bar at zero: "
                                          + "no bar means no edge either.")
                        visible: (page.d.dock || ({})).enabled === true
                        Toggle {
                            checked: (page.d.dock || ({})).background !== false
                            onToggled: v => page.set("dock.background", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("How solid that bar is")
                        visible: (page.d.dock || ({})).enabled === true
                                 && (page.d.dock || ({})).background !== false
                        Slider {
                            width: 200
                            from: 0; to: 100; step: 2; unit: "%"
                            value: page.num(page.d.dock || ({}), "backgroundOpacity", 82)
                            onReleased: v => page.set("dock.backgroundOpacity", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("The bar's corners")
                        visible: (page.d.dock || ({})).enabled === true
                                 && (page.d.dock || ({})).background !== false
                        Slider {
                            width: 200
                            from: 0; to: 40; step: 2; unit: "px"
                            value: page.num(page.d.dock || ({}), "radius", 28)
                            onReleased: v => page.set("dock.radius", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("The icons' corners")
                        description: qsTr("Past half an icon's width it is a "
                                          + "circle, and stays one.")
                        visible: (page.d.dock || ({})).enabled === true
                        Slider {
                            width: 200
                            from: 0; to: 32; step: 2; unit: "px"
                            value: page.num(page.d.dock || ({}), "iconRadius", 16)
                            onReleased: v => page.set("dock.iconRadius", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Space between icons")
                        description: qsTr("Also how far the flow has to run.")
                        visible: (page.d.dock || ({})).enabled === true
                        Slider {
                            width: 200
                            from: 0; to: 80; step: 4; unit: "px"
                            value: page.num(page.d.dock || ({}), "spacing", 28)
                            onReleased: v => page.set("dock.spacing", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Padding inside the bar")
                        visible: (page.d.dock || ({})).enabled === true
                        last: true
                        Slider {
                            width: 200
                            from: 0; to: 40; step: 2; unit: "px"
                            value: page.num(page.d.dock || ({}), "padding", 16)
                            onReleased: v => page.set("dock.padding", v)
                        }
                    }
                }
            }

            SectionHead { index: "—"; text: qsTr("What Genesi adds") }

            Panel {
                width: parent.width
                height: cardsRow.implicitHeight + 8

                Column {
                    id: cardsRow
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Cards behind them")
                        description: qsTr("Off, they float on the wallpaper the "
                                          + "way the clock does. On, they stay "
                                          + "readable over a busy picture — "
                                          + "which is most pictures.")
                        last: true
                        Toggle {
                            checked: page.d.cards !== false
                            onToggled: v => page.set("background.widgets.cards", v)
                        }
                    }
                }
            }

            Grid {
                id: wGrid
                width: parent.width
                columns: Math.max(1, Math.floor(width / 330))
                columnSpacing: Tokens.gap
                rowSpacing: Tokens.gap

                readonly property real cell:
                    (width - (columns - 1) * columnSpacing) / columns

                Repeater {
                    model: page.d.widgets || []

                    delegate: Panel {
                        id: wCard
                        required property var modelData
                        required property int index

                        readonly property bool on: modelData.enabled === true

                        width: wGrid.cell
                        height: 60 + (on ? 74 : 0)
                        interactive: true
                        hovered: wHov.hovered
                        color: on ? Tokens.cardHi : Tokens.card
                        tag: wCard.index < 9 ? "0" + (wCard.index + 1)
                                             : String(wCard.index + 1)

                        Behavior on height {
                            NumberAnimation {
                                duration: Tokens.normal
                                easing.type: Easing.OutCubic
                            }
                        }

                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14
                            anchors.rightMargin: 34
                            spacing: 3

                            Text {
                                text: page.widgetName(wCard.modelData.name)
                                color: wCard.on ? Tokens.textHi : Tokens.text
                                font.family: Tokens.sans
                                font.pixelSize: 13
                            }
                            Text {
                                width: parent.width
                                text: page.widgetBlurb(wCard.modelData.name)
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                            }
                        }

                        Toggle {
                            anchors { right: parent.right; top: parent.top }
                            anchors.rightMargin: 14
                            anchors.topMargin: 28
                            checked: wCard.on
                            onToggled: v => page.set("background.widgets."
                                                     + wCard.modelData.name
                                                     + ".enabled", v)
                        }

                        // Position and size appear only once the widget is on.
                        // Controls for something that is not drawn are controls
                        // that appear to do nothing.
                        Column {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            anchors.margins: 14
                            spacing: 8
                            visible: wCard.on
                            opacity: wCard.on ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: Tokens.quick } }

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("WHERE")
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1.1
                                    width: 48
                                }
                                Select {
                                    width: parent.width - 56
                                    options: page.corners
                                    current: wCard.modelData.position || ""
                                    onPicked: id => page.set("background.widgets."
                                                             + wCard.modelData.name
                                                             + ".position", id)
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("SIZE")
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1.1
                                    width: 48
                                }
                                Slider {
                                    width: parent.width - 56
                                    // Percent, not a multiplier: this Slider
                                    // draws whole numbers, and 0.5 to 2.0 in
                                    // steps of 0.1 would read "1x" at nearly
                                    // every stop. The shell wants the
                                    // multiplier, so the conversion happens on
                                    // the way out.
                                    from: 50; to: 200; step: 10; unit: "%"
                                    value: Math.round(Number(wCard.modelData.scale || 1) * 100)
                                    onReleased: v => page.set("background.widgets."
                                                              + wCard.modelData.name
                                                              + ".scale", v / 100)
                                }
                            }
                        }

                        HoverHandler { id: wHov }
                    }
                }
            }
        }

    }
}
