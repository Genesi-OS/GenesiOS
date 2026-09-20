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

    // Image for a still, AnimatedImage for a GIF. Nineteen of the collection
    // login screens have a VIDEO for a background and no still in them at
    // all, and what their author publishes as a preview is an animated GIF --
    // so a card drawing only the first frame would be showing a still of a
    // thing whose whole point is that it moves.
    readonly property bool moving: root.thumb.toLowerCase().endsWith(".gif")

    Image {
        id: picture

        anchors.fill: parent
        source: root.moving ? "" : root.thumb
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: !root.moving && source !== "" && status === Image.Ready
                 && !root.spec.blur
    }

    AnimatedImage {
        id: motion

        anchors.fill: parent
        source: root.moving ? root.thumb : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false            // a shelf of cached GIFs is a shelf of memory
        speed: 0.75
        visible: root.moving && status === AnimatedImage.Ready
                 && !root.spec.blur
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
        visible: !picture.visible && !motion.visible && root.thumb === ""
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
        height: parent.height * (root.kind === "bar" ? 0.34
                                                    : (root.detailed ? 0.46 : 0.42))
        width: Math.min(height / 0.6, parent.width * 0.78)
        x: parent.width - width - parent.width * 0.05
        y: parent.height * (root.kind === "bar" ? 0.13 : 0.1)

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

            // The bar, down the left edge, as caelestia puts it. For the
            // `bar` shelf this is replaced by the real one below -- fifteen
            // cards drawn from one generic picture were fifteen identical
            // cards.
            Rectangle {
                id: sideBar

                visible: root.kind !== "bar"

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

    // ── The bar this preset actually is ─────────────────────────
    //
    // Drawn from `entries`, which is the preset's own list, in its own
    // order, at its own width and spacing. So the thin one is thin,
    // the one with the clock at the top has the clock at the top, and
    // the two with pills have pills. A `spacer` is what pushes the
    // rest apart, exactly as it does in the real bar.
    Rectangle {
        id: realBar

        readonly property var entries: root.spec.entries ?? []
        readonly property int spacerCount: {
            let n = 0;
            for (const e of realBar.entries)
                if (e === "spacer")
                    n += 1;
            return n;
        }
        // The preset's width is in real pixels on a real screen; the
        // card is a small drawing of one, so it scales with it.
        // One width for all of them, because caelestia has one width: the
        // bar's thickness is not a bar setting. What tells these cards apart
        // is what is IN the bar and how it is drawn.
        readonly property real w: root.u * 12

        visible: root.kind === "bar" && realBar.entries.length > 0
        // Left, and stopping well above the words: the card's name and its
        // button live in the bottom-left, and a bar drawn behind them is a
        // bar nobody can read. Cut off at the bottom still reads as a bar.
        x: root.u * 7
        y: root.u * 6
        width: Math.max(root.u * 7, realBar.w)
        height: parent.height * (root.detailed ? 0.62 : 0.40)
        radius: root.u * 3.4
        color: Qt.alpha(root.surface, root.spec.hidden === true ? 0.35 : 0.95)
        border.width: root.spec.pills === true ? 0 : Math.max(1, root.u * 0.3)
        border.color: Qt.alpha(root.accent, 0.35)
        clip: true

        Column {
            id: stack

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: root.u * 3
            anchors.bottomMargin: root.u * 3
            spacing: root.u * (root.spec.compact === true ? 2.2 : 3.5)

            Repeater {
                model: realBar.entries

                Item {
                    id: slot

                    required property string modelData
                    required property int index

                    readonly property bool isSpacer: modelData === "spacer"
                    // A spacer is the thing that pushes; giving it the
                    // leftover height is what makes "centred" look
                    // centred and "clock first" look top-heavy.
                    readonly property real unit: root.u * 6.5

                    width: realBar.width - root.u * 3
                    height: slot.isSpacer ? Math.max(0, stack.height
                                - stack.spacing * (realBar.entries.length - 1)
                                - slot.unit * (realBar.entries.length
                                    - realBar.spacerCount))
                                / Math.max(1, realBar.spacerCount)
                              : slot.unit

                    // The pill some presets put behind a module.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: !slot.isSpacer && root.spec.pills === true
                                 && (slot.modelData === "clock"
                                     || slot.modelData === "tray")
                        width: parent.width
                        height: slot.unit
                        radius: height / 2.4
                        color: Qt.alpha(root.bg, 0.85)
                    }

                    // The module itself. Shapes, not icons: a dot for
                    // a workspace, a bar for the clock, a row of small
                    // marks for the tray.
                    Loader {
                        anchors.centerIn: parent
                        active: !slot.isSpacer
                        sourceComponent: slot.modelData === "workspaces"
                                         ? workspacesBit
                                         : (slot.modelData === "clock"
                                            ? clockBit : plainBit)

                        Component {
                            id: workspacesBit

                            Column {
                                spacing: root.u * 1.8

                                Repeater {
                                    model: root.spec.windows === true ? 4 : 3

                                    Rectangle {
                                        required property int index

                                        width: index === 0 && root.spec.trail === true
                                               ? root.u * 6 : root.u * 3.4
                                        height: root.u * 3.4
                                        radius: height / 2
                                        color: index === 0 ? root.accent
                                                           : Qt.alpha(root.ink, 0.45)
                                    }
                                }
                            }
                        }

                        Component {
                            id: clockBit

                            Column {
                                spacing: root.u * 1.4

                                Rectangle {
                                    width: root.u * 8
                                    height: root.u * 2.6
                                    radius: height / 2
                                    color: root.accent3
                                }
                                Rectangle {
                                    visible: root.spec.date === true
                                    width: root.u * 5.5
                                    height: root.u * 2
                                    radius: height / 2
                                    color: Qt.alpha(root.ink, 0.5)
                                }
                            }
                        }

                        Component {
                            id: plainBit

                            Rectangle {
                                width: slot.modelData === "logo"
                                       ? root.u * 5 : root.u * 3.8
                                height: width
                                radius: slot.modelData === "logo" ? width / 2
                                                                  : root.u * 0.4
                                color: slot.modelData === "logo"
                                       ? root.accent : Qt.alpha(root.ink, 0.55)
                            }
                        }
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
                 || (root.kind === "login" && !picture.visible
                     && !motion.visible)
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

        // The logo, at the size the config actually asks for. "none" draws
        // nothing, which is the whole point of the card called Sem logo.
        Item {
            id: logo

            readonly property string kind: root.spec.logo ?? "full"
            readonly property real side: logo.kind === "small" ? root.u * 13
                                       : (logo.kind === "image" ? root.u * 26
                                                                : root.u * 20)

            visible: logo.kind !== "none"
            x: root.u * 4
            y: root.u * 9
            width: logo.visible ? logo.side : 0
            height: logo.side

            // An image logo is a picture, so it draws as one.
            Rectangle {
                anchors.fill: parent
                visible: logo.kind === "image"
                radius: root.u * 1.5
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha(root.accent, 0.75)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(root.accent3, 0.35)
                    }
                }
            }

            // Everything else is ASCII art, which reads as rows of blocks.
            Column {
                anchors.centerIn: parent
                visible: logo.kind !== "image"
                spacing: Math.max(1, root.u * 0.9)

                Repeater {
                    model: logo.kind === "small" ? 5 : 8

                    Row {
                        required property int index

                        spacing: Math.max(1, root.u * 0.7)

                        Repeater {
                            // A diamond, so it reads as a drawing rather than
                            // as a block of text.
                            model: (logo.kind === "small" ? 5 : 8)
                                   - Math.abs(index - (logo.kind === "small" ? 2 : 3.5)) * 1.4

                            Rectangle {
                                required property int index

                                width: Math.max(1, root.u * 1.5)
                                height: width
                                radius: width / 3
                                // Varied, but NOT random: a Math.random() in
                                // a binding re-rolls every time the binding
                                // re-evaluates, and the logo flickers.
                                color: Qt.alpha(Tokens.accent,
                                                0.55 + 0.4 * ((index * 7) % 5) / 4)
                            }
                        }
                    }
                }
            }
        }

        // The lines, beside the logo rather than under it, because that is
        // where fastfetch puts them.
        Column {
            x: logo.visible ? logo.x + logo.width + root.u * 4 : root.u * 4
            y: root.u * 9
            spacing: root.u * 1.6

            Repeater {
                model: root.spec.lines ?? []

                Row {
                    required property string modelData

                    spacing: root.u * 1.4

                    // fastfetch writes "key  value", and the key is the part
                    // the colour settings recolour. Splitting it here is what
                    // makes the green one look green.
                    Text {
                        text: root.spec.keyed === false ? ""
                              : modelData.split(/\s{2,}/)[0]
                        visible: text !== ""
                        color: Tokens.accent
                        font.family: Tokens.mono
                        font.pixelSize: Math.max(7, root.u * 4.6)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: root.spec.keyed === false ? modelData
                              : (modelData.split(/\s{2,}/).slice(1).join(" "))
                        color: Tokens.a(Tokens.textHi, 0.8)
                        font.family: Tokens.mono
                        font.pixelSize: Math.max(7, root.u * 4.6)
                    }
                }
            }
        }
    }

    // A wallpaper card is only the picture, but it still says what it is when
    // the picture has not arrived.
    Column {
        anchors.centerIn: parent
        visible: root.kind === "image" && !picture.visible && !motion.visible
        spacing: root.u * 3

        Leaf {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.u * 16
            height: root.u * 16
            colour: Qt.alpha(Tokens.accentSoft, 0.5)
        }
    }
}
