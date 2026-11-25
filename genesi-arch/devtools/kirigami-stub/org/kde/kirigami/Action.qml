// Dev stub for Kirigami.Action — a QtObject carrying the fields an action
// declares. Nothing here executes them: the preview is for layout, and a menu
// that renders is enough to see the layout it lives in.
import QtQuick
QtObject {
    property string text: ""
    // `icon.name:` is a grouped assignment, so icon has to be an object with
    // a name -- a plain string property would be rejected at load time.
    readonly property IconGroup icon: IconGroup {}
    property string tooltip: ""
    property bool checkable: false
    property bool checked: false
    property bool enabled: true
    property bool visible: true
    property var children: []
    signal triggered()
}
