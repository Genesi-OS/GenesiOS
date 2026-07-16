/*
 * Genesi AI Mode Monitor — button for the Automations canvas (copied from Forge).
 * API: theme, text, iconSource, kind (filled·tonal·ghost·danger), accent,
 * tooltip, clicked. `iconSource` accepts "icons/name.svg" or a bare "name".
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    property string text: ""
    property string iconSource: ""
    property string kind: "tonal"      // filled · tonal · ghost · danger
    property color accent: theme ? theme.green : "#1FBE6A"
    property string tooltip: ""
    signal clicked()

    readonly property bool danger: kind === "danger"
    readonly property color effAccent: danger ? (theme ? theme.red : "#E74C3C") : accent
    readonly property color fgColor: "#FFFFFF"

    readonly property color _base:   root.theme ? root.theme.card   : "#1a1d22"
    readonly property color _textHi: root.theme ? root.theme.textHi : "#ECEFF4"
    readonly property color _red:    root.theme ? root.theme.red    : "#E74C3C"
    readonly property color _line:   root.theme ? root.theme.lineHi : "#343a44"
    function _mix(a, b, p) { return Qt.rgba(a.r + (b.r - a.r) * p, a.g + (b.g - a.g) * p, a.b + (b.b - a.b) * p, 1) }

    readonly property url _iconUrl: {
        if (iconSource === "") return ""
        var n = iconSource
        var slash = n.lastIndexOf("/")
        if (slash >= 0) n = n.substring(slash + 1)
        if (n.indexOf(".svg") < 0) n += ".svg"
        return Qt.resolvedUrl("icons/" + n)
    }
    readonly property color _iconColor: kind === "filled" ? fgColor : (danger ? _red : effAccent)

    implicitHeight: 34
    implicitWidth: row.implicitWidth + (root.text ? 28 : 16)
    opacity: enabled ? 1.0 : 0.55

    scale: ma.pressed ? 0.96 : 1.0
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
            return root._mix(root._base, root.effAccent, ma.containsMouse ? 0.26 : 0.15)
        }
        border.width: kind === "filled" ? 0 : 1
        border.color: kind === "ghost" ? "transparent"
                    : root._mix(root._base, root.effAccent, danger ? 0.5 : 0.4)
        Behavior on color { ColorAnimation { duration: 130 } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: root.text ? 7 : 0
            Kirigami.Icon {
                visible: root._iconUrl != ""
                source: root._iconUrl
                isMask: true
                color: root._iconColor
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
            }
            QQC2.Label {
                visible: root.text.length > 0
                text: root.text
                font.pixelSize: 13
                font.bold: kind === "filled"
                color: kind === "filled" ? root.fgColor : (danger ? root._red : root._textHi)
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
