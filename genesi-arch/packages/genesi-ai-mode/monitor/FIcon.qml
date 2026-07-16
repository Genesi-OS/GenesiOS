/*
 * Genesi AI Mode Monitor — icon primitive for the Automations canvas (copied
 * from Forge). Renders a bundled feather-style SVG (monitor/icons/*.svg) tinted
 * via Kirigami.Icon mask mode (software-backend safe).
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
