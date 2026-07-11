/*
 * Genesi Forge — per-stack brand mark. Draws a tinted disc with the stack's
 * brand colour and a monogram, so every project card carries a recognisable,
 * on-brand logo without shipping third-party trademark SVGs. `kind` selects the
 * monogram, `color` is the brand accent (both come from the backend's
 * detect_stack). Shader-free (software-backend / VM safe).
 */
import QtQuick
import org.kde.kirigami as Kirigami

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
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.14)
        border.width: 1.5
        border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.45)

        Text {
            anchors.centerIn: parent
            visible: root.mark.length > 0
            text: root.mark
            color: root.color
            font.family: "Rubik"
            font.bold: true
            font.pixelSize: root.size * (root.mark.length > 1 ? 0.34 : 0.44)
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            visible: root.mark.length === 0
            source: "vcs-branch"
            width: root.size * 0.5; height: width
            color: root.color
        }
    }
}
