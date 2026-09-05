/*
 * Genesi design kit — branded button (custom-drawn so it doesn't depend on the
 * flat Fusion QQC2 style). Variants via `kind`:
 *   "filled"  — solid accent (primary action)
 *   "tonal"   — translucent accent tint (default, secondary action)
 *   "ghost"   — transparent, accent on hover
 *   "danger"  — destructive (red tint, red on hover)
 * Optional `iconSource` (Kirigami.Icon name or path). Emits clicked().
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root

    // `theme` is the root Theme{} instance, passed in by the caller. `enabled`
    // is the built-in Item property — don't redeclare it.
    property var theme
    property string text: ""
    property string iconSource: ""
    property string kind: "tonal"
    property color accent: theme ? theme.green : "#1D9E75"
    property string tooltip: ""
    signal clicked()

    readonly property bool danger: kind === "danger"
    readonly property color effAccent: danger ? (theme ? theme.red : "#E74C3C") : accent
    // Contrast colour for text/icons painted ON a filled accent: black on a light
    // accent, white on a dark one. Works for any scheme accent (no fixed brand
    // green assumption) and any custom accent the caller passes in.
    //
    // NOT `onAccent`, which is what this was called and why filled buttons drew
    // their label in plain black. QML reads a name that is `on` followed by a
    // capital as a signal handler: with a literal value it is a load error, and
    // with an expression -- like this one -- it LOADS, the property exists, and
    // the binding is silently dropped, leaving an invalid colour. It went
    // unnoticed because black happens to be right on a light accent.
    readonly property color accentText: root.theme && root.theme.dark ? "#FFFFFF"
        : ((0.299 * effAccent.r + 0.587 * effAccent.g + 0.114 * effAccent.b) >= 0.6 ? "#0A0E12" : "#FFFFFF")

    // SELF-SUFFICIENT colours — never dereference `theme` in a colour binding.
    // When a GButton is used inside a delegate/Popup where the `theme` id doesn't
    // resolve, `theme` arrives null; a binding like `root.theme.mix(...)` then
    // THROWS, the Rectangle.color binding fails, and Qt falls back to the default
    // white fill — that's the "white pill with unreadable text" bug across the
    // apps (tonal/danger use blends; filled survived because it uses effAccent,
    // which already has a non-theme fallback). These locals blend/tint with a
    // dark fallback base so the button renders correctly with OR without a theme.
    readonly property color _base:   root.theme ? root.theme.card   : "#0d1623"
    readonly property color _textHi: root.theme ? root.theme.textHi : "#EAEEF2"
    readonly property color _red:    root.theme ? root.theme.red    : "#E74C3C"
    function _mix(a, b, p) { return Qt.rgba(a.r + (b.r - a.r) * p, a.g + (b.g - a.g) * p, a.b + (b.b - a.b) * p, 1) }

    implicitHeight: 34
    implicitWidth: row.implicitWidth + (root.text ? 28 : 18)
    // Keep disabled actions readable. Some Qt software-rendering paths flatten
    // translucent rectangles against white before applying Item opacity; a
    // very low opacity then produced the white-on-white buttons seen in VMs.
    opacity: enabled ? 1.0 : 0.72

    // Tactile press feedback (2D scale — software-backend safe, no shaders).
    scale: ma.pressed ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 9
        color: {
            if (kind === "filled")
                return ma.containsMouse ? Qt.lighter(root.effAccent, 1.12) : root.effAccent
            if (kind === "ghost")
                return ma.containsMouse ? root._mix(root._base, root.effAccent, 0.16) : "transparent"
            if (danger)
                return root._mix(root._base, root.effAccent, ma.containsMouse ? 0.28 : 0.14)
            // tonal
            return root._mix(root._base, root.effAccent, ma.containsMouse ? 0.30 : 0.17)
        }
        border.width: kind === "filled" ? 0 : 1
        // Opaque border blend (same reason as the fill) — a translucent border on
        // a rounded rect also mis-renders white on the software backend.
        border.color: kind === "ghost" ? "transparent"
                    : root._mix(root._base, root.effAccent, danger ? 0.55 : 0.45)
        Behavior on color { ColorAnimation { duration: 140 } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: root.text ? 7 : 0
            Kirigami.Icon {
                visible: root.iconSource.length > 0
                source: root.iconSource
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                color: kind === "filled" ? root.accentText : root.effAccent
            }
            QQC2.Label {
                visible: root.text.length > 0
                text: root.text
                font.pixelSize: 13
                font.bold: kind === "filled"
                color: kind === "filled" ? root.accentText
                     : (danger ? root._red : root._textHi)
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
        QQC2.ToolTip.text: root.tooltip
        QQC2.ToolTip.visible: root.tooltip.length > 0 && containsMouse
        QQC2.ToolTip.delay: 500
    }
}
