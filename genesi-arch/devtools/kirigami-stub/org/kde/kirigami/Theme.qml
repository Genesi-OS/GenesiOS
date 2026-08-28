// Dev stub for the ATTACHED Kirigami.Theme. A QML singleton reads with the same
// syntax (Kirigami.Theme.backgroundColor), which is all the app ever uses.
// Values match a dark Breeze so theme.dark resolves true, as it does on the
// real desktop.
pragma Singleton
import QtQuick
QtObject {
    // Genesi ships its own Plasma colour scheme, and several components take
    // their accent from Kirigami.Theme.highlightColor (ChatBubble does). Breeze
    // blue here made every preview look wrong in a way the app is not, so these
    // are Genesi's values, not stock Breeze's.
    readonly property color backgroundColor: "#0a1220"
    readonly property color textColor: "#e6edf6"
    readonly property color highlightColor: "#1FBE6A"
    readonly property color disabledTextColor: "#7f8c8d"
    readonly property color negativeTextColor: "#e74c3c"
    readonly property color positiveTextColor: "#27ae60"
}
