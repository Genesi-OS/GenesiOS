/*
 * Genesi AI Mode Monitor — the "Automations" tab. A thin wrapper that hosts the
 * Automations canvas (its own graphite CanvasTheme, self-contained) plus a small
 * toast. The canvas edits automation graphs; genesi-automationd runs them in the
 * background whether or not this window is open.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Item {
    id: page

    CanvasTheme { id: ctheme }

    Rectangle {
        anchors.fill: parent
        color: ctheme.bgBottom

        AutomationCanvas {
            anchors.fill: parent
            anchors.margins: 14
            theme: ctheme
            onToast: function(msg) {
                toastLabel.text = msg
                toast.opacity = 1.0
                toastTimer.restart()
            }
        }
    }

    // toast
    Rectangle {
        id: toast
        opacity: 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        radius: 10
        color: ctheme.cardHi
        border.width: 1; border.color: ctheme.a(ctheme.green, 0.5)
        implicitWidth: toastLabel.implicitWidth + 34
        implicitHeight: 40
        QQC2.Label {
            id: toastLabel
            anchors.centerIn: parent
            color: ctheme.textHi
            font.pixelSize: 12
        }
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.opacity = 0.0 }
    }
}
