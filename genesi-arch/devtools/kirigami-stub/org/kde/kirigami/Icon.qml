// Dev stub for Kirigami.Icon. `source` is either a freedesktop icon NAME
// ("document-send") or a file/qrc URL. Windows has no icon theme, so a name
// renders as a tinted rounded square: the point of the preview is layout and
// colour, and a missing-image X would be a lie about the real desktop.
import QtQuick
Item {
    id: root
    property var source: ""
    property color color: "transparent"
    property bool isMask: false
    implicitWidth: 22
    implicitHeight: 22

    readonly property bool _isUrl: {
        var s = "" + root.source
        return s.indexOf("/") >= 0 || s.indexOf(":") >= 0 || s.indexOf(".") >= 0
    }

    Image {
        id: img
        anchors.fill: parent
        visible: root._isUrl && status === Image.Ready
        // Rebase a relative path onto the app directory: resolving it here
        // would resolve against the STUB's folder, which is not where the
        // app's icons live. genesiAppDir is set by devtools/preview.py.
        source: {
            if (!root._isUrl) return ""
            var s = "" + root.source
            if (s.indexOf(":") >= 0) return root.source
            return (typeof genesiAppDir !== "undefined") ? genesiAppDir + s : root.source
        }
        sourceSize.width: Math.max(1, root.width)
        sourceSize.height: Math.max(1, root.height)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Rectangle {
        anchors.centerIn: parent
        visible: !img.visible
        width: Math.max(6, Math.min(root.width, root.height) * 0.72)
        height: width
        radius: width * 0.28
        color: root.color !== "transparent" ? Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
                                            : "#556070"
    }
}
