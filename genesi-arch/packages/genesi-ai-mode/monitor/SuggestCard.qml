/*
 * Genesi AI Mode Monitor — one suggestion on the chat's empty state.
 *
 * An empty chat that says only "ask me something" puts the whole burden of
 * knowing what the thing can do on the person who just opened it. These say it
 * instead: a name, one sentence of what it is for, and the part of Genesi it
 * reaches. Clicking one fills the composer rather than sending it, so the
 * suggestion is a starting point the user edits, not a decision made for them.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Rectangle {
    id: root

    // Its own Theme, like every page in this app, rather than one passed in.
    // Theme is a stateless Item holding constants, so an instance costs
    // nothing -- and a property assigned from OUTSIDE is not set yet while the
    // object's own children are being created, which a delegate built by a
    // Repeater hits every time ("Cannot read property of undefined").
    Theme { id: theme }
    property string icon: "bot"
    property color tint: theme.green
    property string title: ""
    property string body: ""
    property string tag: ""
    signal picked()

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 132
    radius: theme.rLg
    color: ma.containsMouse ? theme.hover : theme.surface
    border.width: 1
    border.color: ma.containsMouse ? theme.a(root.tint, 0.45) : theme.hairline
    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.sp4
        spacing: theme.sp2

        RowLayout {
            Layout.fillWidth: true
            spacing: theme.sp2
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: theme.rSm
                color: theme.a(root.tint, 0.16)
                FIcon {
                    anchors.centerIn: parent
                    name: root.icon
                    size: 14
                    color: root.tint
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: root.title
                color: theme.textHi
                font.pixelSize: theme.fsBody
                font.bold: true
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.body
            color: theme.textLo
            font.pixelSize: theme.fsSmall
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.tag
            color: theme.a(theme.textLo, 0.75)
            font.pixelSize: theme.fsMicro
            elide: Text.ElideRight
        }
    }
}
