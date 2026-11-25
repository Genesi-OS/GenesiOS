import QtQuick
import QtQuick.Controls as QQC2
Rectangle {
    id: root
    property string text: ""
    property int type: 0
    property bool showCloseButton: false
    implicitHeight: visible ? Math.max(34, label.implicitHeight + 16) : 0
    radius: 8
    color: type === 3 ? "#3a1c19" : type === 2 ? "#3a2f19" : "#16223a"
    border.width: 1
    border.color: type === 3 ? "#e74c3c" : type === 2 ? "#e6a23c" : "#27374f"
    QQC2.Label {
        id: label
        anchors.fill: parent
        anchors.margins: 8
        text: root.text
        wrapMode: Text.WordWrap
        color: "#e6edf6"
        font.pixelSize: 12
    }
}
