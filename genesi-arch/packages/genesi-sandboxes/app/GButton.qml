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

    implicitHeight: 34
    implicitWidth: row.implicitWidth + (root.text ? 28 : 18)
    opacity: enabled ? 1.0 : 0.45

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
                return ma.containsMouse ? root.theme.a(root.effAccent, 0.16) : "transparent"
            if (danger)
                return ma.containsMouse ? root.theme.a(root.effAccent, 0.22) : root.theme.a(root.effAccent, 0.10)
            // tonal
            return ma.containsMouse ? root.theme.a(root.effAccent, 0.26) : root.theme.a(root.effAccent, 0.14)
        }
        border.width: kind === "filled" ? 0 : 1
        border.color: danger ? root.theme.a(root.effAccent, 0.55)
                    : (kind === "ghost" ? "transparent" : root.theme.a(root.effAccent, 0.45))
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
                color: kind === "filled" ? "#08130E" : root.effAccent
            }
            QQC2.Label {
                visible: root.text.length > 0
                text: root.text
                font.pixelSize: 13
                font.bold: kind === "filled"
                color: kind === "filled" ? "#08130E"
                     : (danger ? root.theme.red : (root.theme ? root.theme.textHi : "#EAEEF2"))
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
