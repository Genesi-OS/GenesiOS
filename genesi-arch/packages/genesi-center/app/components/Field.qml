/*
 * Field — a single line of text someone types.
 *
 * NOT called TextField: QtQuick.Controls has one, and a component file that
 * takes a built-in's name shadows it for every file importing this directory.
 * That already happened here once with Row.qml, and it broke files that never
 * mentioned it.
 *
 * `accepted` carries the text rather than the caller reading `.text`, so a
 * page never has to reach into this to find out what was typed.
 */
import QtQuick
import ".."

Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property bool mono: true
    signal accepted(string value)

    implicitHeight: 32
    radius: Tokens.radiusSm
    color: Tokens.bg
    border.width: 1
    border.color: input.activeFocus ? Tokens.accentDim : Tokens.line
    Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

    function clear() {
        input.text = "";
    }

    TextInput {
        id: input

        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 10; rightMargin: 10
        }
        color: Tokens.textHi
        font.family: root.mono ? Tokens.mono : Tokens.sans
        font.pixelSize: Tokens.fsBody
        selectionColor: Tokens.accentDeep
        selectedTextColor: Tokens.textHi
        clip: true

        onAccepted: root.accepted(text)

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: root.placeholder
            color: Tokens.textFaint
            font: input.font
            elide: Text.ElideRight
        }
    }
}
