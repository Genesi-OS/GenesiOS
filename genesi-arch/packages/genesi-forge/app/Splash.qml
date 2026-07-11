/*
 * Genesi Forge — opening animation. The forge mark blooms in with a soft ring,
 * "Genesi Forge" rises word by word, an emerald underline sweeps across, then
 * the whole splash lifts and fades to reveal the hub. Pure property animation
 * (opacity / scale / width) — no shaders, so it plays on the software backend.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var theme
    signal finished()
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.theme.bgTop }
            GradientStop { position: 1.0; color: root.theme.bgBottom }
        }
    }

    Item {
        id: stage
        anchors.centerIn: parent
        width: 460; height: 260
        opacity: 1

        // Expanding brand ring behind the mark.
        Rectangle {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 128; height: 128; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.theme.a(root.theme.green, 0.0)
            scale: 0.7
        }

        // The forge mark.
        Item {
            id: mark
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 128; height: 128
            opacity: 0
            scale: 0.6
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: root.theme.a(root.theme.green, 0.10)
                border.width: 1.5; border.color: root.theme.a(root.theme.green, 0.4)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                source: "genesi-forge"
                width: 74; height: 74
                color: root.theme.greenBright
            }
        }

        // Word-mark.
        RowLayout {
            id: words
            anchors.horizontalCenter: parent.horizontalCenter
            y: 158
            spacing: 12
            Text {
                id: w1
                text: "Genesi"
                color: root.theme.textHi
                font.family: root.theme.display; font.pixelSize: 44; font.bold: true
                opacity: 0
                transform: Translate { id: t1; y: 18 }
            }
            Text {
                id: w2
                text: "Forge"
                color: root.theme.greenBright
                font.family: root.theme.display; font.pixelSize: 44; font.bold: true
                opacity: 0
                transform: Translate { id: t2; y: 18 }
            }
        }

        // Sweeping underline.
        Rectangle {
            id: underline
            anchors.top: words.bottom; anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            height: 3; radius: 2; width: 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.theme.a(root.theme.green, 0.0) }
                GradientStop { position: 0.5; color: root.theme.green }
                GradientStop { position: 1.0; color: root.theme.a(root.theme.green, 0.0) }
            }
        }

        Text {
            id: tagline
            anchors.top: underline.bottom; anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Your project hub"
            color: root.theme.textMid
            font.family: root.theme.sans; font.pixelSize: 15
            opacity: 0
        }
    }

    SequentialAnimation {
        id: intro
        running: true
        ParallelAnimation {
            NumberAnimation { target: mark; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: mark; property: "scale"; from: 0.6; to: 1; duration: 520; easing.type: Easing.OutBack }
            NumberAnimation { target: ring; property: "scale"; from: 0.7; to: 1.35; duration: 900; easing.type: Easing.OutCubic }
            SequentialAnimation {
                ColorAnimation { target: ring; property: "border.color"; to: root.theme.a(root.theme.green, 0.45); duration: 400 }
                ColorAnimation { target: ring; property: "border.color"; to: root.theme.a(root.theme.green, 0.0); duration: 620 }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: w1; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: t1; property: "y"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: w2; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: t2; property: "y"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: underline; property: "width"; to: 300; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: tagline; property: "opacity"; to: 1; duration: 480; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 620 }
        ParallelAnimation {
            NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 460; easing.type: Easing.InCubic }
            NumberAnimation { target: stage; property: "scale"; from: 1; to: 1.08; duration: 520; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 460; easing.type: Easing.InCubic }
        }
        ScriptAction { script: root.finished() }
    }
}
