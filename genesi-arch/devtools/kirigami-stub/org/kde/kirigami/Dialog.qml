// Referenced only for its button enum (standardButtons: Kirigami.Dialog.Cancel),
// never instantiated. QML forbids property names that start with a capital, so
// the values have to be a declared enum rather than properties.
import QtQuick
import QtQuick.Controls as QQC2
QQC2.Dialog {
    enum StandardButton {
        NoButton = 0,
        Ok = 1024,
        Cancel = 4194304,
        Close = 2097152,
        Apply = 33554432
    }
}
