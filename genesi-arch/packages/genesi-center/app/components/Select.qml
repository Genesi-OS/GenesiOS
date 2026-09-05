/*
 * Select — one of many, from a list too long to show at once.
 *
 * Deliberately plain: a field that opens a list under itself. Resolutions are
 * the case this exists for, and a panel can advertise twenty.
 */
import QtQuick
import ".."

Item {
    id: root
    property var options: []       // [{ id, label }]
    property string current: ""
    property int maxShown: 7
    signal picked(string id)

    implicitWidth: 210
    implicitHeight: 28

    function labelOf(id) {
        for (const o of root.options)
            if (o.id === id)
                return o.label;
        return id;
    }

    Rectangle {
        id: field
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Tokens.card
        border.width: 1
        border.color: list.visible ? Tokens.accentDim : Tokens.line
        Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

        Text {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: root.labelOf(root.current)
            color: Tokens.textHi
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
        }
        Text {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: list.visible ? "^" : "v"
            color: Tokens.textDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: list.visible = !list.visible }
    }

    Rectangle {
        id: list
        visible: false
        z: 10
        anchors { left: parent.left; right: parent.right; top: field.bottom; topMargin: 4 }
        height: Math.min(root.options.length, root.maxShown) * 24 + 8
        radius: Tokens.radiusSm
        color: Tokens.panel
        border.width: 1
        border.color: Tokens.line

        ListView {
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            model: root.options
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 24
                radius: 3
                color: modelData.id === root.current ? Tokens.accentDeep
                                                     : (h.hovered ? Tokens.cardHi : "transparent")
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: modelData.label
                    color: Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
                HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        root.picked(modelData.id);
                        list.visible = false;
                    }
                }
            }
        }
    }
}
