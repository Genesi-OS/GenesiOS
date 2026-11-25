// GENESI STORE — one stop on the rail.
//
// Icon only, with the name arriving on hover: the rail is a spine, and a spine
// with sixteen words on it is a menu. Selection is a filled leaf-green pill,
// because the rail is the one place the app says where you are.
import QtQuick
import ".."

Item {
    id: root

    property string icon: "square"
    property string label: ""
    property bool current: false
    // The window watches this and draws the name itself. Drawn HERE, inside
    // the rail, it was painted under the cards: the rail is an earlier
    // sibling, and no z on a child can lift it out of its parent's turn.
    readonly property alias hovered: hover.hovered
    signal activated

    implicitWidth: Tokens.railWidth
    implicitHeight: 52

    Rectangle {
        id: pill

        anchors.centerIn: parent
        width: 46
        height: 40
        radius: 13
        color: root.current ? Tokens.a(Tokens.accent, 0.16)
                            : (hover.hovered ? Tokens.a(Tokens.accent, 0.07) : "transparent")
        border.width: root.current ? 1 : 0
        border.color: Tokens.a(Tokens.accent, 0.45)

        Behavior on color {
            ColorAnimation {
                duration: Tokens.quick
            }
        }

        Glyph {
            anchors.centerIn: parent
            name: root.icon
            size: 19
            colour: root.current ? Tokens.accent : (hover.hovered ? Tokens.textHi : Tokens.textDim)
        }
    }

    // The selected stop also grows a sliver on the rail's edge, which is what
    // makes the column read as a spine rather than as a list of buttons.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: root.current ? 26 : 0
        radius: 2
        color: Tokens.accent

        Behavior on height {
            NumberAnimation {
                duration: Tokens.normal
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.activated()
    }
}
