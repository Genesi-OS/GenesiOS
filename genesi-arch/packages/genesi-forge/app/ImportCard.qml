/*
 * Genesi Forge — dashed "Import Project" tile that closes the hub grid.
 * Matches ProjectCard's 208px footprint.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: root
    property var theme
    signal browse()

    Layout.fillWidth: true
    implicitHeight: 208

    Canvas {
        id: dash
        anchors.fill: parent
        property color stroke: ma.containsMouse ? root.theme.a(root.theme.green, 0.55)
                                                : root.theme.lineHi
        onStrokeChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = stroke
            ctx.lineWidth = 1.5
            ctx.setLineDash([7, 6])
            var r = 14, x = 1, y = 1, w = width - 2, h = height - 2
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
            ctx.stroke()
        }
    }
    Rectangle {
        anchors.fill: parent; radius: 14
        color: ma.containsMouse ? root.theme.a(root.theme.green, 0.05) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 4
        Rectangle {
            Layout.preferredWidth: 44; Layout.preferredHeight: 44
            radius: 22
            color: root.theme.a(root.theme.green, 0.12)
            border.width: 1.5; border.color: root.theme.a(root.theme.green, 0.4)
            FIcon { anchors.centerIn: parent; name: "plus"; size: 20; color: root.theme.greenBright }
        }
        Item { Layout.fillHeight: true }
        QQC2.Label { text: "Import Project"; color: root.theme.textHi
            font.family: root.theme.display; font.pixelSize: 17; font.bold: true }
        QQC2.Label { text: "Add a project that isn't tracked yet."
            color: root.theme.textLo; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Item { Layout.preferredHeight: 6 }
        QQC2.Label {
            text: "Browse Folder"
            color: root.theme.greenBright; font.pixelSize: 13; font.bold: true
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.browse()
    }
}
