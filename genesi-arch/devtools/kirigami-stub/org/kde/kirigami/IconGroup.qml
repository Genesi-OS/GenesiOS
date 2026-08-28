// `icon.name:` is a GROUPED assignment: QML resolves `name` against the
// declared type of `icon`, so it has to be a named type with that property.
// A bare QtObject is rejected at load time.
import QtQuick
QtObject {
    property string name: ""
    property string source: ""
    property color color: "transparent"
}
