/*
 * NavRow — one section in the rail.
 *
 * The selection is not a filled slab. A solid plate behind a row is the
 * cheapest way to show "you are here" and it reads as a button that got stuck
 * down; the reference this is measured against uses a bar and a wash instead,
 * and it is right. So: a 2px accent bar at the left edge, a gradient that
 * fades out across the row, the label lifted to full white, and a "//" that
 * appears only on the selected row -- the same mark the section headings use,
 * so being selected and being a heading rhyme.
 *
 * The tag on the right is the reference's device too, and it earns its place:
 * a second column of small, dim, fixed-width marks gives the rail a rhythm
 * that a single column of words does not have.
 */
import QtQuick
import ".."

Item {
    id: root

    property string label: ""
    property string tag: ""
    property bool current: false
    signal activated

    implicitHeight: 34

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        opacity: root.current ? 1 : (hover.hovered ? 1 : 0)
        Behavior on opacity { NumberAnimation { duration: Tokens.quick } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.current ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.16)
                                    : Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.05)
            }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Rectangle {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 2
        height: root.current ? parent.height - 8 : 0
        radius: 1
        color: Tokens.accent
        Behavior on height {
            NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic }
        }
    }

    Text {
        id: mark
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: "//"
        color: Tokens.accent
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsMicro
        opacity: root.current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.quick } }
    }

    Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        // Slides right to make room for the mark, rather than the mark pushing
        // it: a row that changes width when selected makes the whole rail twitch.
        anchors.leftMargin: root.current ? 32 : 14
        Behavior on anchors.leftMargin {
            NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic }
        }
        text: root.label
        color: root.current ? Tokens.textHi : (hover.hovered ? Tokens.textHi : Tokens.text)
        font.family: Tokens.sans
        font.pixelSize: 13
        Behavior on color { ColorAnimation { duration: Tokens.quick } }
    }

    Text {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: root.tag
        color: root.current ? Tokens.accentDim : Tokens.textFaint
        font.family: Tokens.mono
        font.pixelSize: 11
        Behavior on color { ColorAnimation { duration: Tokens.quick } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated() }
}
