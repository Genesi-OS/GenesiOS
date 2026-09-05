/*
 * PageFrame — the shape every page shares.
 *
 * A numbered rule, a light title, a paragraph saying what the page is for, a
 * status line, then a scrolling column. Three pages had already been written
 * before this existed and each carried its own copy of that; by the eleventh
 * the copies would have drifted, and a settings app whose pages have slightly
 * different margins reads as several apps stapled together.
 *
 * `note` is where a page says what it could not do -- the session has no
 * compositor, the tool is not installed. It is deliberately part of the frame
 * rather than left to each page, because a page that fails silently is the
 * exact failure this whole app was built to stop repeating.
 */
import QtQuick
import ".."

Item {
    id: root

    property string index: "01"
    property string group: ""
    property string title: ""
    property string blurb: ""
    property string note: ""
    property bool noteWarn: false
    property alias spacing: col.spacing
    property alias flick: scroll

    default property alias content: col.data

    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        spacing: 8

        SectionHead { index: root.index; text: root.group }

        Text {
            text: root.title
            color: Tokens.textHi
            font.family: Tokens.sans
            font.pixelSize: 34
            font.weight: Font.Light
        }
        Text {
            width: Math.max(240, parent.width - 320)
            text: root.blurb
            color: Tokens.text
            font.family: Tokens.sans
            font.pixelSize: 12
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
        Text {
            visible: root.note !== ""
            text: root.note
            color: root.noteWarn ? Tokens.textDim : Tokens.accentDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            font.letterSpacing: 1.2
        }
    }

    Flickable {
        id: scroll
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 18
        anchors.bottomMargin: 24
        clip: true
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 18
        }
    }
}
