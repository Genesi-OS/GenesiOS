// Dev stub: a modal with a title bar and the app's own ColumnLayout as content.
// default property alias is what lets `Kirigami.PromptDialog { ColumnLayout {} }`
// keep working -- the children are the dialog's body, exactly as upstream.
import QtQuick
import QtQuick.Controls as QQC2
QQC2.Dialog {
    id: root
    property string subtitle: ""
    property int preferredWidth: 420
    // Buttons the app supplies itself instead of using standardButtons. The
    // preview does not render them -- they are Kirigami.Actions, which is a
    // menu model rather than an Item -- but the property has to EXIST or the
    // whole file fails to load, which is what a stub is for.
    // list<QtObject>, not var: an object-list LITERAL in a declaration is
    // rejected for a singular property ("Cannot assign multiple values").
    property list<QtObject> customFooterActions
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
