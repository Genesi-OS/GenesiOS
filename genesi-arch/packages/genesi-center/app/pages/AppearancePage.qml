/*
 * AppearancePage — the frame round the desktop, the colours, the shaders.
 *
 * The frame is the biggest visual lever caelestia has and the least obvious:
 * `border.thickness` is what makes the desktop sit flush against the screen
 * edge or float as a rounded card, AND it is where the bar's padding comes
 * from, so the two move together whether or not anyone says so. That is why it
 * is at the top of this page with a preview, rather than a slider in a list.
 *
 * Colour schemes and shaders are LISTED, never invented. A picker offering a
 * scheme caelestia does not have is a click that fails in silence, which is the
 * shape of failure this whole app was written against — so what is not
 * installed is not offered.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var border_: page.d.border || ({})
    readonly property var scales: page.d.scales || ({})
    readonly property var glass: page.d.transparency || ({})
    readonly property var fonts: page.d.fonts || ({})
    readonly property bool ready: page.d.available === true

    // A scale is stored as a multiplier and shown as a percentage: 1.15 means
    // nothing to anyone, "115%" is a size.
    function pct(key, fallback) {
        const v = page.scales[key];
        return Math.round(((v === undefined || v === null) ? fallback : v) * 100);
    }

    function num(key, fallback) {
        const v = page.border_[key];
        return (v === undefined || v === null) ? fallback : Number(v);
    }

    function set(path, value) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "caelestia", path, String(value)],
                             "appearance");
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "appearance")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("appearance")

    PageFrame {
        anchors.fill: parent
        index: "03"
        group: qsTr("Desktop")
        title: qsTr("Appearance")
        blurb: qsTr("The frame the whole desktop sits inside, and the colours "
                    + "everything takes from. The frame is also where the bar "
                    + "gets its padding — thicken it and the rail breathes with "
                    + "it, which is why the two are on one page.")
        note: page.ready ? qsTr("%1 scheme(s) · %2 shader(s)")
                           .arg((page.d.schemes || []).length)
                           .arg((page.d.shaders || []).length)
                         : qsTr("no caelestia config found")
        noteWarn: !page.ready

        // ── The frame ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("The frame") }

            Row {
                width: parent.width
                spacing: Tokens.gap

                Panel {
                    width: 260
                    height: frameCol.implicitHeight + 8

                    // The desktop, at the thickness and rounding set below. The
                    // bar is drawn on its edge because that is where it is, and
                    // because seeing it move is the point of the preview.
                    Item {
                        anchors.fill: parent
                        anchors.margins: 18

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: Tokens.bg
                            border.width: 1
                            border.color: Tokens.lineSoft
                        }

                        Rectangle {
                            id: deskPreview
                            anchors.fill: parent
                            anchors.margins: Math.round(page.num("thickness", 10) / 2.2)
                            radius: Math.round(page.num("rounding", 25) / 2.2)
                            color: Tokens.card
                            border.width: 1
                            border.color: Tokens.accentDeep
                            // The preview fades too. A see-through slider whose
                            // picture stays solid is a slider you have to apply
                            // to find out about.
                            opacity: Math.max(0.15, page.num("opacity", 100) / 100)
                            Behavior on opacity {
                                NumberAnimation { duration: Tokens.quick }
                            }

                            Behavior on anchors.margins {
                                NumberAnimation { duration: Tokens.quick }
                            }
                            Behavior on radius {
                                NumberAnimation { duration: Tokens.quick }
                            }

                            Rectangle {
                                anchors {
                                    left: parent.left; top: parent.top
                                    bottom: parent.bottom; margins: 4
                                }
                                width: 8
                                radius: 4
                                color: Tokens.accentDim
                            }
                        }
                    }
                }

                Panel {
                    width: parent.width - 260 - Tokens.gap
                    height: frameCol.implicitHeight + 8

                    Column {
                        id: frameCol
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 4

                        SettingRow {
                            width: parent.width
                            label: qsTr("Thickness")
                            description: qsTr("0 puts the desktop hard against the "
                                              + "screen edge. It is also the bar's "
                                              + "padding.")
                            Slider {
                                width: 220
                                from: 0; to: 30; step: 1; unit: "px"
                                value: page.num("thickness", 10)
                                onReleased: v => page.set("border.thickness", v)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Corner rounding")
                            description: qsTr("How round the desktop's own corners "
                                              + "are. With a thick frame this is "
                                              + "what makes it read as a card.")
                            Slider {
                                width: 220
                                from: 0; to: 50; step: 1; unit: "px"
                                value: page.num("rounding", 25)
                                onReleased: v => page.set("border.rounding", v)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("See-through")
                            description: qsTr("caelestia paints the frame and the "
                                              + "bar's ground as one surface, so "
                                              + "this fades both — which is the "
                                              + "glass look, and worth knowing "
                                              + "before you reach for it.")
                            Slider {
                                width: 220
                                from: 15; to: 100; step: 1; unit: "%"
                                value: page.num("opacity", 100)
                                onReleased: v => page.set("border.opacity", v)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Corner smoothing")
                            description: qsTr("Squircle rather than a plain radius. "
                                              + "Subtle, and only visible at larger "
                                              + "roundings.")
                            last: true
                            Slider {
                                width: 220
                                from: 0; to: 40; step: 1
                                value: page.num("smoothing", 20)
                                onReleased: v => page.set("border.smoothing", v)
                            }
                        }
                    }
                }
            }
        }

        // ── Shape and scale ──────────────────────────────────────────────────
        //
        // Four sliders that each multiply a whole family of values inside the
        // shell rather than setting one number. They are the difference
        // between a settings page and a personality: rounding takes every
        // corner at once, spacing and padding every gap, type every size.
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Shape and scale") }

            Row {
                width: parent.width
                spacing: Tokens.gap

                // A card drawn at the settings below it, so the numbers have
                // something to be about.
                Panel {
                    id: shapePreview
                    // Already a drawing of a frame. Corner ticks here would be
                    // the second frame inside 232px.
                    ticks: false
                    width: 232
                    height: shapeCol.implicitHeight + 8

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 20
                        radius: Math.round(14 * page.pct("rounding", 1) / 100)
                        color: Tokens.card
                        border.width: 1
                        border.color: Tokens.accentDeep
                        opacity: page.glass.enabled
                                 ? Math.max(0.35, page.glass.base || 0.85) : 1
                        Behavior on radius { NumberAnimation { duration: Tokens.quick } }
                        Behavior on opacity { NumberAnimation { duration: Tokens.quick } }

                        Column {
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top
                            }
                            anchors.margins: Math.round(
                                14 * page.pct("padding", 1) / 100)
                            spacing: Math.round(10 * page.pct("spacing", 1) / 100)

                            Text {
                                text: qsTr("Sample")
                                color: Tokens.textHi
                                font.family: Tokens.sans
                                font.pixelSize: Math.round(
                                    15 * page.pct("font", 1) / 100)
                            }
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    width: 120 - index * 22
                                    height: Math.round(
                                        8 * page.pct("font", 1) / 100)
                                    radius: Math.round(
                                        4 * page.pct("rounding", 1) / 100)
                                    color: index === 0 ? Tokens.accentDim
                                                       : Tokens.lineSoft
                                    Behavior on radius {
                                        NumberAnimation { duration: Tokens.quick }
                                    }
                                }
                            }
                        }
                    }
                }

                Panel {
                    width: parent.width - shapePreview.width - Tokens.gap
                    height: shapeCol.implicitHeight + 8

                    Column {
                        id: shapeCol
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 4

                        SettingRow {
                            width: parent.width
                            label: qsTr("Corners")
                            description: qsTr("Every rounded corner in the shell "
                                              + "at once — the bar, the launcher, "
                                              + "every panel. 0 is square.")
                            Slider {
                                width: 220
                                from: 0; to: 200; step: 5; unit: "%"
                                value: page.pct("rounding", 1)
                                onReleased: v => page.set(
                                    "appearance.rounding.scale", v / 100)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Breathing room")
                            description: qsTr("The gaps between things.")
                            Slider {
                                width: 220
                                from: 50; to: 200; step: 5; unit: "%"
                                value: page.pct("spacing", 1)
                                onReleased: v => page.set(
                                    "appearance.spacing.scale", v / 100)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Inner padding")
                            description: qsTr("The space inside a panel, before "
                                              + "its contents start.")
                            Slider {
                                width: 220
                                from: 50; to: 200; step: 5; unit: "%"
                                value: page.pct("padding", 1)
                                onReleased: v => page.set(
                                    "appearance.padding.scale", v / 100)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Type size")
                            description: qsTr("Deliberately a narrow range: the "
                                              + "bar is sized around its own text, "
                                              + "and type that outgrows it is hard "
                                              + "to undo from inside a window that "
                                              + "grew with it.")
                            Slider {
                                width: 220
                                from: 80; to: 140; step: 5; unit: "%"
                                value: page.pct("font", 1)
                                onReleased: v => page.set(
                                    "appearance.font.scale", v / 100)
                            }
                        }
                        SettingRow {
                            width: parent.width
                            label: qsTr("Animation speed")
                            description: qsTr("Higher is slower. 0 turns the "
                                              + "shell's own animations off, which "
                                              + "is the first thing to try on a "
                                              + "machine that feels heavy.")
                            last: true
                            Slider {
                                width: 220
                                from: 0; to: 250; step: 10; unit: "%"
                                value: page.pct("anim", 1)
                                onReleased: v => page.set(
                                    "appearance.anim.durations.scale", v / 100)
                            }
                        }
                    }
                }
            }
        }

        // ── Glass ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Glass") }

            Panel {
                width: parent.width
                height: glassCol.implicitHeight + 8

                Column {
                    id: glassCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Translucent surfaces")
                        description: qsTr("caelestia's own, and different from the "
                                          + "frame's see-through above: this fades "
                                          + "the panels — the launcher, the "
                                          + "dashboard, the popouts — rather than "
                                          + "the desktop's edge.")
                        Toggle {
                            checked: page.glass.enabled === true
                            onToggled: v => page.set(
                                "appearance.transparency.enabled", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Panels")
                        opacity: page.glass.enabled ? 1 : 0.4
                        Slider {
                            width: 220
                            enabled: page.glass.enabled === true
                            from: 30; to: 100; step: 1; unit: "%"
                            value: Math.round((page.glass.base === undefined
                                               ? 0.85 : page.glass.base) * 100)
                            onReleased: v => page.set(
                                "appearance.transparency.base", v / 100)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Cards inside them")
                        description: qsTr("The layer above a panel — a card, a "
                                          + "row. Lower makes the depth obvious.")
                        opacity: page.glass.enabled ? 1 : 0.4
                        last: true
                        Slider {
                            width: 220
                            enabled: page.glass.enabled === true
                            from: 0; to: 100; step: 1; unit: "%"
                            value: Math.round((page.glass.layers === undefined
                                               ? 0.4 : page.glass.layers) * 100)
                            onReleased: v => page.set(
                                "appearance.transparency.layers", v / 100)
                        }
                    }
                }
            }
        }

        // ── Type ─────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && (page.fonts.available || []).length > 0

            SectionHead { index: "—"; text: qsTr("Type") }

            Panel {
                width: parent.width
                height: fontCol.implicitHeight + 8

                Column {
                    id: fontCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Interface")
                        description: qsTr("Everything that is not code. Listed from "
                                          + "fc-list, so every name here is a font "
                                          + "this machine can actually draw.")
                        Select {
                            width: 240
                            options: (page.fonts.available || [])
                                     .map(f => ({ id: f, label: f }))
                            current: page.fonts.body || ""
                            onPicked: id => page.set("appearance.font.body.family", id)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Monospace")
                        description: qsTr("The clock, the terminal readouts, "
                                          + "anything in columns.")
                        last: true
                        Select {
                            width: 240
                            options: (page.fonts.available || [])
                                     .map(f => ({ id: f, label: f }))
                            current: page.fonts.mono || ""
                            onPicked: id => page.set("appearance.font.mono.family", id)
                        }
                    }
                }
            }
        }

        // ── Colour ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && (page.d.schemes || []).length > 0

            SectionHead { index: "—"; text: qsTr("Colour scheme") }

            Grid {
                id: schemeGrid
                width: parent.width
                columns: Math.max(2, Math.floor(width / 170))
                columnSpacing: Tokens.gap
                rowSpacing: Tokens.gap

                readonly property real cell:
                    (width - (columns - 1) * columnSpacing) / columns

                Repeater {
                    model: page.d.schemes || []
                    delegate: Panel {
                        id: schemeCard
                        required property var modelData
                        required property int index

                        width: schemeGrid.cell
                        height: 54
                        // No corner ticks: the lozenge already marks this card,
                        // and on 54px the two land within 20px of each other and
                        // read as one smudge.
                        ticks: false
                        interactive: true
                        hovered: schemeHov.hovered
                        color: schemeHov.hovered ? Tokens.cardHi : Tokens.card

                        // A scheme name is an identifier -- "catppuccin",
                        // "rosepine" -- not prose, so it is set as one. The
                        // lozenge in front is what turns a wall of twenty
                        // identical name-cards into a list you can aim at, and
                        // the arrow says the card DOES something, which a name
                        // sitting in a box does not.
                        Text {
                            id: schemeMark
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            anchors.leftMargin: 14
                            text: "◈"
                            color: schemeHov.hovered ? Tokens.accent : Tokens.accentDeep
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            Behavior on color { ColorAnimation { duration: Tokens.quick } }
                        }

                        Text {
                            anchors {
                                left: schemeMark.right; right: schemeArrow.left
                                verticalCenter: parent.verticalCenter
                            }
                            anchors.leftMargin: 9
                            anchors.rightMargin: 8
                            text: schemeCard.modelData
                            color: schemeHov.hovered ? Tokens.textHi : Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            id: schemeArrow
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            anchors.rightMargin: 14
                            text: "→"
                            color: Tokens.accent
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            opacity: schemeHov.hovered ? 1 : 0
                            transform: Translate {
                                x: schemeHov.hovered ? 0 : -5
                                Behavior on x {
                                    NumberAnimation {
                                        duration: Tokens.quick
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: Tokens.quick } }
                        }

                        HoverHandler { id: schemeHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            // caelestia re-themes everything from here: the
                            // shell, GTK, Qt and the terminal. Which is why it
                            // goes through its own CLI rather than this writing
                            // a colour anywhere itself.
                            onTapped: {
                                if (page.backend)
                                    page.backend.act(["caelestia", "scheme", "set",
                                                      "-n", String(schemeCard.modelData)],
                                                     "appearance");
                            }
                        }
                    }
                }
            }
        }

        // ── Wallpaper ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Wallpaper") }

            Panel {
                width: parent.width
                height: 78

                Column {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 16
                    width: parent.width - 190
                    spacing: 4

                    Text {
                        text: qsTr("IN USE")
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.4
                    }
                    Text {
                        width: parent.width
                        text: page.d.wallpaper ? String(page.d.wallpaper)
                                               : qsTr("none set")
                        color: page.d.wallpaper ? Tokens.textHi : Tokens.textDim
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }

                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.rightMargin: 16
                    width: 160
                    height: 28
                    radius: Tokens.radiusSm
                    color: wallHov.hovered ? Tokens.cardHi : "transparent"
                    border.width: 1
                    border.color: wallHov.hovered ? Tokens.accentDim : Tokens.line
                    Behavior on color { ColorAnimation { duration: Tokens.quick } }

                    Text {
                        anchors.centerIn: parent
                        // The launcher already has a wallpaper picker with
                        // thumbnails. Building a second one here would be a
                        // worse copy that can disagree with it.
                        text: qsTr("PICK IN THE LAUNCHER")
                        color: Tokens.text
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1
                    }
                    HoverHandler { id: wallHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: if (page.backend)
                            page.backend.launch(["caelestia", "shell", "drawers",
                                                 "toggle", "launcher"])
                    }
                }
            }
        }

        // ── Shaders ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && (page.d.shaders || []).length > 0

            SectionHead { index: "—"; text: qsTr("Screen shaders") }

            Panel {
                width: parent.width
                height: shaderFlow.implicitHeight + 32

                Flow {
                    id: shaderFlow
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 16
                    spacing: 8

                    // "Off" first, always. A shader you cannot turn off is a
                    // screen you have to log out of, and hyprshade's own `off`
                    // is the only thing that clears it.
                    Rectangle {
                        readonly property bool on: !page.d.shader_on

                        width: offLabel.implicitWidth + 24
                        height: 26
                        radius: Tokens.radiusSm
                        color: on ? Tokens.accentDeep
                                  : (offHov.hovered ? Tokens.cardHi : "transparent")
                        border.width: 1
                        border.color: on ? Tokens.accentDim
                                         : (offHov.hovered ? Tokens.accentDim : Tokens.line)
                        Behavior on color { ColorAnimation { duration: Tokens.quick } }

                        Text {
                            id: offLabel
                            anchors.centerIn: parent
                            text: qsTr("off")
                            color: parent.on ? Tokens.textHi : Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                        HoverHandler { id: offHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: if (page.backend)
                                page.backend.act(["hyprshade", "off"], "appearance")
                        }
                    }

                    Repeater {
                        model: page.d.shaders || []
                        delegate: Rectangle {
                            id: shaderChip
                            required property var modelData

                            readonly property bool on: page.d.shader_on === modelData

                            width: shaderLabel.implicitWidth + 24
                            height: 26
                            radius: Tokens.radiusSm
                            color: on ? Tokens.accentDeep
                                      : (shHov.hovered ? Tokens.cardHi : "transparent")
                            border.width: 1
                            border.color: on ? Tokens.accentDim
                                             : (shHov.hovered ? Tokens.accentDim : Tokens.line)
                            Behavior on color { ColorAnimation { duration: Tokens.quick } }

                            Text {
                                id: shaderLabel
                                anchors.centerIn: parent
                                text: shaderChip.modelData
                                color: shaderChip.on ? Tokens.textHi
                                                     : (shHov.hovered ? Tokens.textHi : Tokens.text)
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                            }
                            HoverHandler { id: shHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                // `hyprshade on <name>`, the same command the
                                // `>shader` launcher rows run. One command for
                                // both, so they cannot disagree about what is
                                // applied.
                                onTapped: if (page.backend)
                                    page.backend.act(["hyprshade", "on",
                                                      String(shaderChip.modelData)],
                                                     "appearance")
                            }
                        }
                    }
                }
            }
        }
    }
}
