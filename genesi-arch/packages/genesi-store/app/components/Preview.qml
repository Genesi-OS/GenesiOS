// GENESI STORE — what the thing actually looks like.
//
// One component, every shelf. A card is a picture of a desktop, and the
// picture is DRAWN from the item's own data: a theme's real palette, a
// wallpaper's real thumbnail (shipped with the package, so the shelf is a
// shelf of pictures before anything is downloaded), a bar preset's real
// module list, a lock screen's real colours.
//
// Why drawn and not screenshotted: a screenshot has to be retaken every time
// anything changes, and the first one nobody retakes is the one that starts
// lying. A drawing made of the item's data cannot go stale -- if the palette
// changes, the picture changes.
//
// The same component fills a 200px card and a 600px detail sheet: everything
// is a fraction of the height, so it is one drawing at two sizes rather than
// two drawings that drift apart.
import QtQuick
import QtQuick.Effects
import ".."

Item {
    id: root

    required property var spec          // the item's `preview` object
    property string thumbDir: ""        // where the shipped thumbnails live
    property string shotUrl: ""         // a screenshot fetched into the cache
    property bool detailed: false       // the sheet wants more furniture

    readonly property string kind: root.spec.kind ?? ""
    readonly property real u: height / 100     // one unit = 1% of the height

    readonly property color bg: root.spec.background ?? Tokens.bgDeep
    readonly property color surface: root.spec.surface ?? Qt.lighter(root.bg, 1.25)
    readonly property color ink: root.spec.ink ?? Tokens.textHi
    readonly property color accent: root.spec.accent
        ?? (root.spec.colours ? root.spec.colours[0] : Tokens.accent)
    readonly property color accent2: root.spec.colours && root.spec.colours.length > 1
        ? root.spec.colours[1] : root.accent
    readonly property color accent3: root.spec.colours && root.spec.colours.length > 2
        ? root.spec.colours[2] : root.accent2

    // thumbDir is already a url (see the backend), so this is a join and not
    // a guess about what a path looks like.
    // A fetched screenshot wins over a shipped thumbnail. The login screens
    // have no shipped thumbnail at all -- theirs is downloaded, because the
    // picture belongs to whoever made the theme -- so until it arrives this
    // is "" and the drawn login screen below stands in for it.
    readonly property string thumb: root.shotUrl !== "" ? root.shotUrl
        : (root.spec.thumb && root.thumbDir
           ? root.thumbDir + "/" + root.spec.thumb : "")

    clip: true

    // ── The wallpaper ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    Image {
        id: picture

        anchors.fill: parent
        source: root.thumb
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: source !== "" && status === Image.Ready && !root.spec.blur
    }

    // A lock screen shows the wallpaper the way a lock screen does: blurred.
    MultiEffect {
        anchors.fill: parent
        source: picture
        visible: root.spec.blur === true && picture.status === Image.Ready
        blurEnabled: true
        blur: 1
        blurMax: 24
        brightness: -0.25
        autoPaddingEnabled: false
    }

    // Nothing to show yet: the palette is the picture.
    Rectangle {
        anchors.fill: parent
        visible: !picture.visible && root.thumb === ""
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.lighter(root.bg, 1.35)
            }
            GradientStop {
                position: 1
                color: root.bg
            }
        }
    }

    // ── A desktop, drawn as a SCREEN on the wallpaper ───────────────────────
    //
    // Not full-bleed. The first version drew the bar and the window across the
    // whole card, which covered the picture the card is meant to be selling --
    // a wallpaper you cannot see behind a mock window is not a preview of
    // anything. A small screen, floating, says "this is your desktop" and
    // leaves the photograph visible around it.
    Item {
        id: screen

        readonly property bool shown: root.kind === "scheme" || root.kind === "desktop" || root.kind === "bar"

        // Sized off the SHORT side and capped, so the screen is a screen on a
        // wide card and still a screen on a square one -- a fraction of the
        // width alone made it a wall on the big cards.
        // Off the HEIGHT, not the width: a card is as tall as it is tall, and
        // a screen sized from the width grew into a wall on the big cards.
        visible: screen.shown
        height: parent.height * (root.detailed ? 0.46 : 0.42)
        width: Math.min(height / 0.6, parent.width * 0.78)
        x: parent.width - width - parent.width * 0.05
        y: parent.height * 0.1

        Rectangle {
            anchors.fill: glass
            anchors.margins: -root.u * 1.2
            radius: root.u * 3
            color: Qt.rgba(0, 0, 0, 0.35)
            z: -1
        }

        Rectangle {
            id: glass

            anchors.fill: parent
            radius: root.u * 2.2
            color: Qt.alpha(root.bg, 0.94)
            border.width: Math.max(1, root.u * 0.4)
            border.color: Qt.alpha(root.ink, 0.18)
            clip: true

            // The bar, down the left edge, as caelestia puts it.
            Rectangle {
                id: sideBar

                x: root.u * 1.4
                y: root.u * 1.4
                width: root.u * 4.4
                height: parent.height - root.u * 2.8
                radius: root.u * 1.6
                color: Qt.alpha(root.surface, 0.95)
                border.width: root.kind === "bar" ? Math.max(1, root.u * 0.4) : 0
                border.color: Qt.alpha(root.accent, 0.7)

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: root.u * 2
                    spacing: root.u * 1.8

                    Repeater {
                        model: root.kind === "bar" ? 4 : 3

                        Rectangle {
                            required property int index

                            width: root.u * (index === 0 ? 2.4 : 1.8)
                            height: width
                            radius: width / 2
                            color: index === 0 ? root.accent : Qt.alpha(root.ink, 0.5)
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.u * 1.6
                    width: root.u * 2.6
                    height: root.u * 1
                    radius: height / 2
                    color: Qt.alpha(root.ink, 0.6)
                }
            }

            // A window, which is what a colour scheme is judged on.
            Rectangle {
                x: root.u * 8.5
                y: root.u * 4
                width: parent.width - root.u * 12
                height: parent.height - root.u * 8
                radius: root.u * 1.8
                color: Qt.alpha(root.surface, 0.97)

                Row {
                    x: root.u * 2.2
                    y: root.u * 2.2
                    spacing: root.u * 1.2

                    Rectangle {
                        width: root.u * 1.6
                        height: root.u * 1.6
                        radius: width / 2
                        color: root.accent
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.u * 10
                        height: root.u * 1.2
                        radius: height / 2
                        color: Qt.alpha(root.ink, 0.7)
                    }
                }

                Column {
                    x: root.u * 2.2
                    y: root.u * 6.6
                    spacing: root.u * 1.5

                    Repeater {
                        model: [19, 14, 17]

                        Rectangle {
                            required property int modelData
                            required property int index

                            width: root.u * modelData
                            height: root.u * 1
                            radius: height / 2
                            color: index === 1 ? Qt.alpha(root.accent2, 0.95)
                                               : Qt.alpha(root.ink, 0.3)
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: root.u * 2.2
                    width: root.u * 8
                    height: root.u * 3
                    radius: root.u * 1
                    color: root.accent
                }
            }

            // A widget on the wallpaper of the little desktop: a clock, which
            // is the one everybody puts there.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.u * 2.4
                visible: root.kind !== "bar"
                width: root.u * 11
                height: root.u * 6
                radius: root.u * 1.4
                color: Qt.alpha(root.surface, 0.75)

                Column {
                    anchors.centerIn: parent
                    spacing: root.u * 0.9

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.u * 6.5
                        height: root.u * 1.8
                        radius: height / 2
                        color: root.accent3
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.u * 4
                        height: root.u * 0.9
                        radius: height / 2
                        color: Qt.alpha(root.ink, 0.5)
                    }
                }
            }
        }
    }

    // The palette itself, for the shelf where that IS the product.
    Row {
        visible: root.kind === "scheme" && (root.spec.colours ?? []).length > 0
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: root.u * 8
        spacing: root.u * 3

        Repeater {
            model: root.spec.colours ?? []

            Rectangle {
                required property string modelData

                width: root.u * 9
                height: root.u * 9
                radius: width / 2
                color: modelData
                border.width: Math.max(1, root.u * 0.5)
                border.color: Qt.alpha(root.ink, 0.18)
            }
        }
    }

    // ── A lock screen ────────────────────────────────────────────────────────
    //
    // A clock and four dots, drawn. For a session lock that is right: the card
    // is the wallpaper, blurred, with the shape of a lock screen on it.
    //
    // For a LOGIN screen it is right only when there is no photograph of the
    // real thing. The downloaded greeters ship their own screenshots, and
    // drawing Genesi's mock clock over somebody else's login screen would be
    // covering the one honest thing on the card with a lie about it.
    Column {
        anchors.centerIn: parent
        visible: root.kind === "lock"
                 || (root.kind === "login" && !picture.visible)
        spacing: root.u * 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "22:42"
            color: root.spec.accent ?? Tokens.accentSoft
            font.family: root.spec.mono === true ? Tokens.mono : Tokens.sans
            font.pixelSize: root.u * 22
            font.weight: Font.Light
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.u * 40
            height: root.u * 9
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: Math.max(1, root.u * 0.6)
            border.color: root.spec.accent ?? Tokens.accentSoft

            Row {
                anchors.centerIn: parent
                spacing: root.u * 2.4

                Repeater {
                    model: 4

                    Rectangle {
                        width: root.u * 2
                        height: root.u * 2
                        radius: width / 2
                        color: root.spec.accent ?? Tokens.accentSoft
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.detailed
            text: root.kind === "login" ? qsTr("antes da sessão") : qsTr("na sessão")
            color: Qt.alpha(root.spec.accent ?? Tokens.accentSoft, 0.7)
            font.family: Tokens.mono
            font.pixelSize: root.u * 4
            font.letterSpacing: root.u * 0.4
        }
    }

    // ── A terminal ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.u * 6
        visible: root.kind === "terminal"
        radius: root.u * 2.5
        color: "#060a08"
        border.width: 1
        border.color: Qt.alpha(Tokens.accent, 0.25)

        Row {
            x: root.u * 3
            y: root.u * 3
            spacing: root.u * 1.6

            Repeater {
                model: [Tokens.warm, Tokens.accentSoft, Tokens.accent]

                Rectangle {
                    required property color modelData

                    width: root.u * 2
                    height: root.u * 2
                    radius: width / 2
                    color: Qt.alpha(modelData, 0.8)
                }
            }
        }

        Column {
            x: root.u * 3
            y: root.u * 9
            spacing: root.u * 1.6

            Repeater {
                model: root.spec.lines ?? []

                Text {
                    required property string modelData

                    text: modelData
                    color: Tokens.accentSoft
                    font.family: Tokens.mono
                    font.pixelSize: Math.max(7, root.u * 5)
                }
            }
        }
    }

    // A wallpaper card is only the picture, but it still says what it is when
    // the picture has not arrived.
    Column {
        anchors.centerIn: parent
        visible: root.kind === "image" && !picture.visible
        spacing: root.u * 3

        Leaf {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.u * 16
            height: root.u * 16
            colour: Qt.alpha(Tokens.accentSoft, 0.5)
        }
    }
}
