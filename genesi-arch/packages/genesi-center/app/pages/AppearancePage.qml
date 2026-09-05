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
    readonly property bool ready: page.d.available === true

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
                        height: 52
                        interactive: true
                        hovered: schemeHov.hovered

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            anchors.leftMargin: 14
                            width: parent.width - 28
                            text: schemeCard.modelData
                            color: schemeHov.hovered ? Tokens.textHi : Tokens.text
                            font.family: Tokens.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
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
