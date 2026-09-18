// GENESI STORE — one thing you can put on your desktop.
//
// The card IS the preview. A store whose cards are all the same rectangle with
// a different word in it is a list, and nobody browses a list: a theme shows
// its colours, a wallpaper shows itself, a bar shows its own arrangement, a
// lock screen shows a lock screen, a fastfetch config shows a terminal. Five
// small drawings, one per `preview.kind`, and every one of them is drawn from
// the item's own data rather than from a screenshot somebody has to remember
// to retake.
import QtQuick
import ".."

Rectangle {
    id: root

    required property var item
    property string busy: ""
    property bool wide: false
    signal primary          // install / apply
    signal secondary        // revert
    signal opened

    readonly property var preview: item.preview ?? ({})
    readonly property bool applied: item.applied === true
    readonly property bool working: root.busy !== ""

    implicitWidth: root.wide ? 320 : 232
    // Tall enough for two lines of blurb plus the button: at 214 the second
    // line was being clipped, and a clipped sentence reads as a bug.
    implicitHeight: root.wide ? 256 : 226
    radius: Tokens.radius
    color: hover.hovered ? Tokens.cardHi : Tokens.card
    border.width: 1
    border.color: root.applied ? Tokens.a(Tokens.accent, 0.5) : Tokens.line
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: Tokens.quick
        }
    }

    // ── The picture ──────────────────────────────────────────────────────────
    Item {
        id: art

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.height * 0.52
        clip: true

        // A theme: its own surface, its own ink, its own three accents.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "swatches"
            color: root.preview.background ?? Tokens.card

            Row {
                anchors.centerIn: parent
                spacing: 10

                Repeater {
                    model: root.preview.colours ?? []

                    Rectangle {
                        required property string modelData

                        width: 34
                        height: 34
                        radius: 17
                        color: modelData
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: "Aa"
                color: root.preview.ink ?? Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: 17
            }
        }

        // A wallpaper: itself once it is here, its own colours before that.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "image"
            color: Tokens.bgDeep

            Image {
                id: shot

                anchors.fill: parent
                source: root.item.localPreview ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready
            }

            // Not downloaded yet: say so, rather than showing a grey hole.
            Column {
                anchors.centerIn: parent
                visible: !shot.visible
                spacing: 6

                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "decor"
                    size: 22
                    colour: Tokens.textFaint
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const bytes = root.item.assets?.picture?.bytes ?? 0;
                        return bytes >= 1048576 ? (Math.round(bytes / 1048576 * 10) / 10 + " MB") : (Math.round(bytes / 1024) + " KB");
                    }
                    color: Tokens.textFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
            }
        }

        // A bar arrangement: a bar, drawn.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "bar"
            color: Tokens.bgDeep

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                width: 26
                radius: 8
                color: Tokens.a(Tokens.accent, 0.1)
                border.width: 1
                border.color: Tokens.a(Tokens.accent, 0.3)

                Column {
                    anchors.centerIn: parent
                    spacing: 7

                    Repeater {
                        model: 3

                        Rectangle {
                            required property int index

                            width: index === 1 ? 12 : 7
                            height: width
                            radius: width / 2
                            color: index === 1 ? Tokens.accent : Tokens.a(Tokens.accentSoft, 0.4)
                        }
                    }
                }
            }
        }

        // A lock screen: a field and a clock, in its colours.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "lock" || root.preview.kind === "login"
            color: root.preview.background ?? "#0b120e"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "22:42"
                    color: root.preview.accent ?? Tokens.accentSoft
                    font.family: Tokens.sans
                    font.pixelSize: 26
                    font.weight: Font.Light
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 92
                    height: 20
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: root.preview.accent ?? Tokens.accentSoft

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Repeater {
                            model: 4

                            Rectangle {
                                width: 5
                                height: 5
                                radius: 2.5
                                color: root.preview.accent ?? Tokens.accentSoft
                            }
                        }
                    }
                }
            }

            // The login family says, on the card, that it will ask for a
            // password -- not after you press it.
            Chip {
                visible: root.item.needs_root === true
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                text: "sistema"
                tint: Tokens.warm
                selected: true
                interactive: false
            }
        }

        // A fastfetch config: a terminal.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "terminal"
            color: "#050907"

            Column {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 3

                Repeater {
                    model: root.preview.lines ?? []

                    Text {
                        required property string modelData

                        text: modelData
                        color: Tokens.accentSoft
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }
            }
        }

        // A whole desktop: the accent over the wallpaper it comes with.
        Rectangle {
            anchors.fill: parent
            visible: root.preview.kind === "rice"
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.darker(root.preview.accent ?? Tokens.accent, 3.4)
                }
                GradientStop {
                    position: 1
                    color: Tokens.bgDeep
                }
            }

            Leaf {
                anchors.centerIn: parent
                width: 54
                height: 54
                colour: root.preview.accent ?? Tokens.accent
                fill: 0.85
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: (root.item.includes ?? []).length + " peças"
                color: Tokens.a(Tokens.textHi, 0.8)
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
        }

        // Applied: the one state worth a badge.
        Rectangle {
            visible: root.applied
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            width: 26
            height: 26
            radius: 13
            color: Tokens.a(Tokens.bgDeep, 0.75)

            Glyph {
                anchors.centerIn: parent
                name: "applied"
                size: 16
                fill: 1
                colour: Tokens.accent
            }
        }
    }

    // ── The words ────────────────────────────────────────────────────────────
    // Bounded at the bottom by the button, not only at the top by the picture:
    // a two-line blurb was running under it.
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: art.bottom
        anchors.bottom: act.top
        anchors.margins: 12
        anchors.bottomMargin: 6
        spacing: 2
        clip: true

        Text {
            width: parent.width
            text: root.item.name ?? ""
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsCard
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.item.blurb ?? ""
            color: Tokens.textDim
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsLabel
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    // ── The button ───────────────────────────────────────────────────────────
    Rectangle {
        id: act

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        height: 32
        radius: Tokens.radiusSm
        color: root.working ? Tokens.a(Tokens.accent, 0.12)
                            : (root.applied ? "transparent"
                                            : (press.pressed ? Tokens.accentDeep
                                                             : Tokens.a(Tokens.accent, hover.hovered ? 0.24 : 0.14)))
        border.width: root.applied ? 1 : 0
        border.color: Tokens.line

        Row {
            anchors.centerIn: parent
            spacing: 7

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                name: root.applied ? "revert" : (root.item.needs_download ? "install" : "play")
                size: 15
                colour: root.applied ? Tokens.textDim : Tokens.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (root.working)
                        return root.busy + "…";
                    if (root.applied)
                        return qsTr("Remover");
                    return root.item.needs_download ? qsTr("Baixar e aplicar") : qsTr("Aplicar");
                }
                color: root.applied ? Tokens.textDim : Tokens.textHi
                font.family: Tokens.sans
                font.pixelSize: Tokens.fsLabel
                font.weight: Font.Medium
            }
        }

        TapHandler {
            id: press

            onTapped: root.applied ? root.secondary() : root.primary()
        }
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        onTapped: root.opened()
        gesturePolicy: TapHandler.WithinBounds
    }
}
