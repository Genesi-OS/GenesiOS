/*
 * Genesi Forge — per-stack brand mark: tinted disc with the stack's brand
 * colour and a monogram (or a git-branch glyph for plain repos). Shader-free.
 */
import QtQuick

Item {
    id: root
    property string kind: "git"
    property color color: "#8A94A6"
    property int size: 44
    implicitWidth: size
    implicitHeight: size

    readonly property var _marks: ({
        "next": "N", "react": "R", "node": "JS", "typescript": "TS",
        "javascript": "JS", "python": "Py", "flutter": "F", "html": "H5",
        "scss": "S", "vue": "V", "rust": "Rs", "go": "Go", "angular": "A",
        "svelte": "S", "php": "P", "ruby": "R", "git": ""
    })
    readonly property string mark: _marks[kind] !== undefined ? _marks[kind] : ""

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.13)
        border.width: 1.5
        border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.42)

        Text {
            anchors.centerIn: parent
            visible: root.mark.length > 0
            text: root.mark
            color: root.color
            font.family: "Rubik"
            font.bold: true
            font.pixelSize: root.size * (root.mark.length > 1 ? 0.33 : 0.42)
        }
        FIcon {
            anchors.centerIn: parent
            visible: root.mark.length === 0
            name: "git-branch"
            size: root.size * 0.46
            color: root.color
        }
    }
}
