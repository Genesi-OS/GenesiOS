/*
 * Genesi AI Mode Monitor — branded on/off switch for the Automations config
 * panel (copied from Forge). Emerald when on; shader-free. Emits toggled(checked).
 */
import QtQuick

Item {
    id: root
    property var theme
    property bool checked: true
    signal toggled(bool value)

    implicitWidth: 42
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.theme.green : root.theme.cardHi
        border.width: 1
        border.color: root.checked ? root.theme.greenBright : root.theme.lineHi
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: 18; height: 18; radius: 9
            color: "#ffffff"
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // Report the click; do NOT flip `checked` here.
        //
        // Every call site binds checked to the value it owns
        // (checked: root.activeEnabled) and writes that value back in
        // onToggled. Assigning to checked from inside DESTROYS that binding,
        // so from the first click onwards the switch stopped following the
        // model: selecting a disabled automation left the label reading
        // "Disabled" next to a switch still sitting in the on position.
        // The owner turns it; this only asks.
        onClicked: root.toggled(!root.checked)
    }
}
