// Dev stub: a modal with a title bar and the app's own ColumnLayout as content.
// default property alias is what lets `Kirigami.PromptDialog { ColumnLayout {} }`
// keep working -- the children are the dialog's body, exactly as upstream.
import QtQuick
import QtQuick.Controls as QQC2
QQC2.Dialog {
    id: root
    property string subtitle: ""
    property int preferredWidth: 420
    default property alias content: body.data
    anchors.centerIn: parent
    modal: true
    width: preferredWidth
    contentItem: Item {
        implicitHeight: body.childrenRect.height + 8
        Item {
            id: body
            anchors.fill: parent
            anchors.margins: 4
        }
    }
}
