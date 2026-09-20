// GENESI STORE — one thing you can put on your desktop.
//
// The picture fills the card and the words sit ON it, in a gradient that
// starts where the text starts. The first version stacked a picture, a title,
// a line of description and a button in four horizontal bands, which is a form
// with a thumbnail at the top: correct, and nothing anybody wants to look at.
//
// The card carries one action, and it is the one the item is in for: Apply,
// or Download and apply when something has to come down first. Everything
// else -- what it changes, what it comes with, reverting -- is in the sheet a
// click away, because a card with four buttons on it is a settings row.
import QtQuick
import ".."

Rectangle {
    id: root

    required property var item
    property string thumbDir: ""
    property string busy: ""
    // The mosaic hands this in: a tall card gets a bigger title and room for
    // the blurb, a small one gets the name alone.
    property bool large: false

    signal primary
    signal opened

    readonly property var preview: item.preview ?? ({})
    // Filled in when the screenshot lands. The delegate only exists while the
    // card is near the viewport, so asking here IS asking lazily.
    property string shot: ""
    property string motion: ""

    Component.onCompleted: {
        if (root.preview.shot) {
            root.shot = store.previewPath(root.item.id);
            store.fetchPreview(root.item.id);
        }
        if (root.preview.shot && root.preview.shot.motion) {
            root.motion = store.motionPath(root.item.id);
        }
    }

    Connections {
        target: store

        function onPreviewReady(ident, url) {
            if (ident === root.item.id)
                root.shot = url;
        }

        function onMotionReady(ident, url) {
            if (ident === root.item.id)
                root.motion = url;
        }
    }
    readonly property bool applied: item.applied === true
    readonly property bool working: root.busy !== ""
    readonly property bool needsDownload: root.item.needs_download === true

    radius: Tokens.radius
    color: Tokens.card
    border.width: 1
    border.color: root.applied ? Tokens.a(Tokens.accent, 0.55)
                               : (hover.hovered ? Tokens.a(Tokens.accentSoft, 0.25) : Tokens.line)
    clip: true

    Behavior on border.color {
        ColorAnimation {
            duration: Tokens.quick
        }
    }

    // ── The picture, which is the card ───────────────────────────────────────
    Preview {
        id: art

        anchors.fill: parent
        spec: root.preview
        thumbDir: root.thumbDir
        shotUrl: root.shot
        motionSrc: root.motion
        // Only the card under the pointer plays. Thirty-five running GIFs is
        // a shelf that sounds like a laptop taking off.
        animate: hover.hovered
        // A hair of zoom under the pointer: enough to feel alive, not enough
        // to make the text move.
        scale: hover.hovered ? 1.03 : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
    }

    // The words need a floor to stand on, and a gradient is the only one that
    // does not cut the picture in half.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.large ? parent.height * 0.62 : parent.height * 0.56
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 0.45
                color: Qt.rgba(0.02, 0.05, 0.03, 0.78)
            }
            GradientStop {
                position: 1
                color: Qt.rgba(0.02, 0.05, 0.03, 0.96)
            }
        }
    }

    // ── What it is ───────────────────────────────────────────────────────────
    Column {
        id: words

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.large ? 16 : 12
        anchors.bottomMargin: root.large ? 16 : 12
        spacing: 3

        Text {
            text: (root.item.kindLabel ?? "").toUpperCase()
            visible: text !== ""
            color: Tokens.a(Tokens.accentSoft, 0.85)
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.6
        }

        Text {
            width: parent.width
            text: root.item.name ?? ""
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: root.large ? Tokens.fsTitle : Tokens.fsCard
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        // Whose it is. Only for what came from outside Genesi -- putting
        // "por Genesi" on Genesi's own cards is noise, and the point of this
        // line is that somebody else's work is labelled as theirs without
        // having to open the sheet to find out.
        Text {
            width: parent.width
            visible: text !== ""
            text: root.item.author && root.item.author !== "Genesi"
                  ? qsTr("por %1").arg(root.item.author) : ""
            color: Tokens.a(Tokens.textHi, 0.62)
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsMicro
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: root.large
            text: root.item.blurb ?? ""
            color: Tokens.a(Tokens.textHi, 0.72)
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsLabel
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item {
            width: 1
            height: 4
        }

        // The one action, and what it will cost.
        Row {
            spacing: 8

            Rectangle {
                id: act

                width: label.implicitWidth + (glyph.visible ? 46 : 28)
                height: 32
                radius: Tokens.radiusSm
                color: {
                    if (root.working)
                        return Tokens.a(Tokens.accentSoft, 0.2);
                    if (root.applied)
                        return Tokens.a(Tokens.bgDeep, 0.6);
                    return tap.pressed ? Tokens.accentDeep
                                       : Tokens.a(Tokens.accent, hover.hovered ? 0.92 : 0.16);
                }
                border.width: root.applied ? 1 : 0
                border.color: Tokens.a(Tokens.accentSoft, 0.4)

                Behavior on color {
                    ColorAnimation {
                        duration: Tokens.quick
                    }
                }

                Glyph {
                    id: glyph

                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.applied ? "applied" : (root.needsDownload ? "install" : "play")
                    size: 15
                    fill: root.applied ? 1 : 0
                    colour: {
                        if (root.applied)
                            return Tokens.accent;
                        return hover.hovered && !root.working ? Tokens.bgDeep : Tokens.accent;
                    }
                }

                Text {
                    id: label

                    anchors.left: glyph.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.working)
                            return root.busy + "…";
                        if (root.applied)
                            return qsTr("Em uso");
                        return root.needsDownload ? qsTr("Baixar") : qsTr("Aplicar");
                    }
                    color: root.applied ? Tokens.accentSoft
                                        : (hover.hovered && !root.working ? Tokens.bgDeep : Tokens.textHi)
                    font.family: Tokens.sans
                    font.pixelSize: Tokens.fsLabel
                    font.weight: Font.Medium
                }

                TapHandler {
                    id: tap

                    onTapped: root.primary()
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // What it weighs, when it weighs anything.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.needsDownload
                       && (root.item.assets?.picture?.bytes ?? root.item.download ?? 0) > 0
                text: {
                    // A wallpaper's weight is its asset; a login screen's
                    // is the theme archive, which is `download`. Reading only
                    // the first made every login card say "0 KB" beside a
                    // button about to fetch seventeen megabytes.
                    const bytes = root.item.assets?.picture?.bytes
                                ?? root.item.download ?? 0;
                    return bytes >= 1048576 ? (Math.round(bytes / 1048576 * 10) / 10 + " MB")
                                            : (Math.round(bytes / 1024) + " KB");
                }
                color: Tokens.a(Tokens.textHi, 0.55)
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
        }
    }

    // ── Badges ───────────────────────────────────────────────────────────────
    Rectangle {
        visible: root.applied
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 10
        width: applied.implicitWidth + 26
        height: 24
        radius: 12
        color: Tokens.a(Tokens.accentDeep, 0.9)

        Glyph {
            id: appliedGlyph

            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            name: "applied"
            size: 12
            fill: 1
            colour: Tokens.textHi
        }
        Text {
            id: applied

            anchors.left: appliedGlyph.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("em uso")
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsMicro
        }
    }

    // The ones that will ask for a password say so on the card.
    Rectangle {
        visible: root.item.needs_root === true
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        width: rootLabel.implicitWidth + 26
        height: 24
        radius: 12
        color: Tokens.a(Tokens.warm, 0.22)
        border.width: 1
        border.color: Tokens.a(Tokens.warm, 0.5)

        Glyph {
            id: rootGlyph

            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            name: "root"
            size: 12
            colour: Tokens.warm
        }
        Text {
            id: rootLabel

            anchors.left: rootGlyph.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("sistema")
            color: Tokens.warm
            font.family: Tokens.sans
            font.pixelSize: Tokens.fsMicro
        }
    }

    // ── Everything else is one click away ────────────────────────────────────
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        visible: hover.hovered && root.item.needs_root !== true
        width: 28
        height: 28
        radius: 14
        color: Tokens.a(Tokens.bgDeep, 0.72)

        Glyph {
            anchors.centerIn: parent
            name: "more"
            size: 16
            colour: Tokens.textHi
        }

        TapHandler {
            onTapped: root.opened()
        }
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hover.hovered && root.motion === ""
                && root.preview.shot && root.preview.shot.motion)
                store.fetchMotion(root.item.id);
        }
    }
    TapHandler {
        onTapped: root.opened()
        gesturePolicy: TapHandler.WithinBounds
    }
}
