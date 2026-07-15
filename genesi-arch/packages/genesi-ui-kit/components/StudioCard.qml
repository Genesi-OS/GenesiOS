import QtQuick

Rectangle {
    id: card

    property color accent: "#1FBE6A"
    property bool active: false
    property bool interactive: true
    property bool wash: false
    property real entranceDelay: -1

    readonly property color base: "#181B1F"
    readonly property color white: "#FFFFFF"
    readonly property color line: "#2A2F35"
    readonly property color lineHi: "#394049"
    function mix(a, b, p) {
        return Qt.rgba(a.r + (b.r - a.r) * p,
                       a.g + (b.g - a.g) * p,
                       a.b + (b.b - a.b) * p, 1)
    }

    property real hoverAmount: interactive && hover.hovered ? 1 : 0
    Behavior on hoverAmount { NumberAnimation { duration: 140 } }

    radius: 8
    gradient: Gradient {
        GradientStop { position: 0; color: card.mix(card.base, card.white, 0.045 + card.hoverAmount * 0.025) }
        GradientStop { position: 1; color: card.mix(card.base, card.white, 0.008 + card.hoverAmount * 0.015) }
    }
    border.width: active ? 1.5 : 1
    border.color: active ? accent : (hover.hovered && interactive ? lineHi : line)
    Behavior on border.color { ColorAnimation { duration: 140 } }

    transform: Translate {
        y: card.interactive && hover.hovered ? -1 : 0
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: card.wash
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.11) }
            GradientStop { position: 0.72; color: "transparent" }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }

    opacity: 1
    Component.onCompleted: {
        if (entranceDelay >= 0) {
            opacity = 0
            entrance.start()
        }
    }
    SequentialAnimation {
        id: entrance
        PauseAnimation { duration: Math.max(0, card.entranceDelay) }
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; from: 0.985; to: 1; duration: 240; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler { id: hover }
}
