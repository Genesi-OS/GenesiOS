/*
 * Genesi Forge — icon primitive. Renders one of the app's bundled feather-style
 * SVGs (app/icons/*.svg) tinted to any colour via Kirigami.Icon's mask mode
 * (software-backend safe — the tint is done on the QImage, no shaders).
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property string name: ""
    property color color: "#E8ECF1"
    property int size: 16
    implicitWidth: size
    implicitHeight: size

    Kirigami.Icon {
        anchors.fill: parent
        source: root.name !== "" ? Qt.resolvedUrl("icons/" + root.name + ".svg") : ""
        isMask: true
        color: root.color
        smooth: true
    }
}
