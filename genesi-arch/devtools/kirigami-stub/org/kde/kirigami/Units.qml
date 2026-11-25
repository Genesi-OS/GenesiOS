// Dev stub. Values are Kirigami's own defaults at a 96dpi default font:
// gridUnit is the height of a line of text, and the two spacings are derived
// from it. Getting these right matters more than anything else here -- the
// whole app lays out in multiples of them.
pragma Singleton
import QtQuick
QtObject {
    readonly property int gridUnit: 18
    readonly property int smallSpacing: 4
    readonly property int largeSpacing: 8
    readonly property int mediumSpacing: 6
    readonly property int veryLongDuration: 400
    readonly property int longDuration: 200
    readonly property int shortDuration: 100
    readonly property int veryShortDuration: 50
    readonly property int iconSizes: 22
}
