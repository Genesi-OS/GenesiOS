// Dev stub for the ATTACHED Kirigami.Theme. A QML singleton reads with the same
// syntax (Kirigami.Theme.backgroundColor), which is all the app ever uses.
// Values match a dark Breeze so theme.dark resolves true, as it does on the
// real desktop.
pragma Singleton
import QtQuick
QtObject {
    readonly property color backgroundColor: "#1b1e20"
    readonly property color textColor: "#fcfcfc"
    readonly property color highlightColor: "#3daee9"
    readonly property color disabledTextColor: "#7f8c8d"
    readonly property color negativeTextColor: "#e74c3c"
    readonly property color positiveTextColor: "#27ae60"
}
