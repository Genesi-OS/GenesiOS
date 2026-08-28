// Same story as Dialog: referenced only as Kirigami.MessageType.Warning, so the
// values are a declared enum (QML property names cannot start with a capital).
import QtQuick
Item {
    enum Type {
        Information = 0,
        Positive = 1,
        Warning = 2,
        Error = 3
    }
}
