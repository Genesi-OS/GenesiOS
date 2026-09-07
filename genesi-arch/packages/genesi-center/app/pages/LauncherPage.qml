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

            SectionHead { index: "—"; text: qsTr("The look") }

            // Two bodies for one panel. The sketches are the whole difference
            // and no sentence says it faster -- one is a strip at the bottom,
            // the other is a slab with a band across the top.
            Row {
                width: parent.width
                spacing: Tokens.gap

                Repeater {
                    model: [
                        { id: "caelestia", name: qsTr("caelestia"),
                          desc: qsTr("A prompt with the results stacked over it. "
                                     + "Upstream's, and the smaller one.") },
                        { id: "genesi", name: qsTr("Genesi"),
                          desc: qsTr("A wide slab: clock and weather, the "
                                     + "wallpaper behind the prompt, and the "
                                     + "results in columns.") }
                    ]
                    delegate: Panel {
                        id: layCard
                        required property var modelData

                        readonly property bool on:
                            (page.o.layout || "caelestia") === modelData.id

                        width: (parent.width - Tokens.gap) / 2
                        height: 116
                        ticks: false
                        interactive: true
                        hovered: layHov.hovered
                        color: on ? Tokens.cardHi : Tokens.card
                        border.color: on ? Tokens.accentDim
                                         : (layHov.hovered ? Tokens.accentDeep
                                                           : Tokens.line)

                        Rectangle {
                            id: laySketch
                            anchors { left: parent.left; top: parent.top }
                            anchors.margins: 16
                            width: 58
                            height: 38
                            radius: 3
                            color: "transparent"
                            border.width: 1
                            border.color: layCard.on ? Tokens.accentDim : Tokens.line

                            // caelestia: a narrow strip near the bottom.
                            Rectangle {
                                visible: layCard.modelData.id === "caelestia"
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - height - 4
                                width: parent.width - 22
                                height: 11
                                radius: 2
                                color: layCard.on ? Tokens.accent : Tokens.textFaint
                            }

                            // Genesi: a wide slab with a band across the top.
                            Rectangle {
                                visible: layCard.modelData.id === "genesi"
                                anchors.centerIn: parent
                                width: parent.width - 8
                                height: 22
                                radius: 2
                                color: "transparent"
                                border.width: 1
                                border.color: layCard.on ? Tokens.accent
                                                         : Tokens.textFaint

                                Rectangle {
                                    anchors {
                                        left: parent.left; right: parent.right
                                        top: parent.top
                                    }
                                    anchors.margins: 1
                                    height: 8
                                    color: layCard.on ? Tokens.accent : Tokens.textFaint
                                    opacity: 0.55
                                }
                            }
                        }

                        Column {
                            anchors {
                                left: laySketch.right; right: parent.right
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
                                    text: layCard.modelData.name
                                    color: layCard.on ? Tokens.textHi : Tokens.text
                                    font.family: Tokens.sans
                                    font.pixelSize: 13
                                    width: parent.width - 46
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: layCard.on
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
                                text: layCard.modelData.desc
                                color: Tokens.textDim
                                font.family: Tokens.sans
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        HoverHandler { id: layHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (!layCard.on)
                                    page.set("launcher.layout", layCard.modelData.id);
                            }
                        }
                    }
                }
            }

            // Everything below applies to the Genesi body only, so it is not
            // shown next to the other one. A page full of controls that quietly
            // do nothing is worse than a page that is honest about its shape.
            Panel {
                width: parent.width
                height: lookCol.implicitHeight + 8
                visible: (page.o.layout || "caelestia") === "genesi"

                Column {
                    id: lookCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Picture behind it")
                        description: qsTr("The desktop's own wallpaper follows "
                                          + "whatever you set it to. The Genesi "
                                          + "one stays put.")
                        Segmented {
                            options: [
                                { id: "", label: qsTr("NONE") },
                                { id: "wallpaper", label: qsTr("WALLPAPER") },
                                { id: "/usr/share/wallpapers/genesi/wallpaper.png",
                                  label: qsTr("GENESI") }
                            ]
                            current: page.o.background || ""
                            onPicked: id => page.set("launcher.background", id)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("How much it covers")
                        description: qsTr("Behind the prompt only, or behind the "
                                          + "results as well. Behind everything, "
                                          + "twenty app names have to stay "
                                          + "readable over a photograph.")
                        visible: (page.o.background || "") !== ""
                        Segmented {
                            options: [
                                { id: "header", label: qsTr("THE PROMPT") },
                                { id: "panel", label: qsTr("ALL OF IT") }
                            ]
                            current: page.o.backgroundExtent || "header"
                            onPicked: id => page.set("launcher.backgroundExtent", id)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Dim")
                        description: qsTr("How much of the panel's own colour is "
                                          + "laid over that picture. This is what "
                                          + "keeps the text readable.")
                        visible: (page.o.background || "") !== ""
                        Slider {
                            width: 220
                            from: 0; to: 100; step: 2; unit: "%"
                            value: page.num("backgroundDim", 78)
                            onReleased: v => page.set("launcher.backgroundDim", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Columns")
                        description: qsTr("How many columns the results fold into. "
                                          + "Results shown, below, still counts "
                                          + "ROWS — so two columns is twice the "
                                          + "list, not half of it.")
                        Slider {
                            width: 160
                            from: 1; to: 3; step: 1
                            value: page.num("columns", 2)
                            onReleased: v => page.set("launcher.columns", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Clock")
                        description: qsTr("The time, in the top left corner.")
                        Toggle {
                            checked: page.o.showClock !== false
                            onToggled: v => page.set("launcher.showClock", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Weather")
                        description: qsTr("The temperature and the date, top right. "
                                          + "Needs caelestia's weather service to "
                                          + "have a location.")
                        Toggle {
                            checked: page.o.showWeather !== false
                            onToggled: v => page.set("launcher.showWeather", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Card for what is selected")
                        description: qsTr("Names the thing Enter will open, with "
                                          + "its icon at a size you can actually "
                                          + "recognise.")
                        Toggle {
                            checked: page.o.showHero !== false
                            onToggled: v => page.set("launcher.showHero", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Mode buttons")
                        description: qsTr("Apps, actions, schemes and wallpapers as "
                                          + "buttons — the modes you otherwise "
                                          + "reach only by knowing what to type.")
                        last: true
                        Toggle {
                            checked: page.o.showChips !== false
                            onToggled: v => page.set("launcher.showChips", v)
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
                    id: groupRep
                    model: page.d.groups || []

                    // A tile whose only content was two lines of prose was the
                    // flattest thing on the page: the count -- the one number
                    // that differs between these cards -- was buried mid
                    // sentence in the same size and colour as the sentence. It
                    // is the reading, so it is set like one, and the row it
                    // hides behind is set like the command you would type.
                    delegate: Panel {
                        id: groupCard
                        required property var modelData
                        required property int index

                        width: groupGrid.cell
                        height: 88
                        interactive: true
                        hovered: groupHov.hovered
                        color: groupHov.hovered ? Tokens.cardHi : Tokens.card
                        tag: groupCard.index < 9 ? "0" + (groupCard.index + 1)
                                                 : String(groupCard.index + 1)

                        // The tiles arrive one after another, the same way the
                        // Overview telemetry does. Eight appearing together is
                        // a flash; eight in sequence is the page assembling.
                        opacity: 0
                        Component.onCompleted: groupIn.start()
                        SequentialAnimation {
                            id: groupIn
                            PauseAnimation { duration: groupCard.index * 60 }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: groupCard; property: "opacity"
                                    from: 0; to: 1
                                    duration: Tokens.normal; easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: groupBody; property: "anchors.leftMargin"
                                    from: 4; to: 16
                                    duration: Tokens.normal; easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Column {
                            id: groupBody
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            anchors.leftMargin: 16
                            anchors.rightMargin: 14
                            spacing: 6

                            // The prompt, drawn as a prompt: the prefix is the
                            // part you type and the part that is not the name,
                            // so it is coloured as punctuation and the name is
                            // not.
                            Row {
                                spacing: 0
                                Text {
                                    text: page.o.actionPrefix || ">"
                                    color: Tokens.accent
                                    font.family: Tokens.mono
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: groupCard.modelData.name
                                    color: Tokens.textHi
                                    font.family: Tokens.mono
                                    font.pixelSize: 14
                                }
                            }

                            Rectangle {
                                width: parent.width - 2
                                height: 1
                                color: groupHov.hovered ? Tokens.accentDeep : Tokens.lineSoft
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }

                            // A plain Item, not a Row: the unit sits on the
                            // number's BASELINE, and a positioner top-aligns
                            // its children instead -- which puts a 9px label
                            // level with the top of a 19px digit.
                            Item {
                                width: parent.width
                                height: groupCount.height

                                Text {
                                    id: groupCount
                                    text: groupCard.modelData.count
                                    color: groupHov.hovered ? Tokens.accent : Tokens.text
                                    font.family: Tokens.mono
                                    font.pixelSize: 19
                                    Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                }
                                Text {
                                    anchors.left: groupCount.right
                                    anchors.leftMargin: 6
                                    anchors.baseline: groupCount.baseline
                                    text: qsTr("entries · one row")
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fsMicro
                                    font.letterSpacing: 1.1
                                }
                            }
                        }

                        HoverHandler { id: groupHov }
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
