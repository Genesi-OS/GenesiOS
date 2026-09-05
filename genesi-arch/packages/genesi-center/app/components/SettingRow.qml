/*
 * SettingRow — one setting: a name, a sentence saying what it does, and a
 * control.
 *
 * NOT called Row. QtQuick has a Row, and a component file named Row.qml in an
 * imported directory SHADOWS it for every file that imports that directory --
 * so every plain `Row { spacing: ... }` elsewhere in the app suddenly failed
 * with "cannot assign to non-existent property spacing". A component that
 * takes a built-in's name breaks files that never mentioned it.
 *
 * The description is not optional decoration. A settings page whose rows are
 * bare labels makes the reader guess, and the guess is usually "I had better
 * not touch this". One short line under the name is the difference between a
 * control panel and a list of switches.
 */
import QtQuick
import ".."

Item {
    id: root
    property string label: ""
    property string description: ""
    property bool last: false
    default property alias control: holder.data

    implicitHeight: Math.max(46, col.implicitHeight + 20)

    Column {
        id: col
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: 14
        width: parent.width - holder.width - 40
        spacing: 2

        Text {
            text: root.label
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: 13
        }
        Text {
            visible: root.description !== ""
            width: parent.width
            text: root.description
            color: Tokens.textDim
            font.family: Tokens.sans
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: holder
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: implicitWidth
        height: implicitHeight
    }

    Rectangle {
        visible: !root.last
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: 14
        height: 1
        color: Tokens.lineSoft
    }
}
