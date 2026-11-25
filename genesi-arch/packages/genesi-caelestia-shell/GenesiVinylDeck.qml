// GENESI — the turntable: how the vinyl plugin looks and moves.
//
// Drawing only. GenesiVinyl.qml finds what is playing and hands this the
// title, the artist, the cover and how far through the track it is; this
// spins a record for it.
//
// ── Like a real one ───────────────────────────────────────────────────────
//
//   the platter spins UP when music starts and coasts DOWN when it stops,
//   instead of snapping between still and 33 rpm
//   the light on the record stays where the lamp is while the grooves turn
//   under it, which is most of why a spinning record looks like one
//   the tonearm swings onto the record when there is music, and creeps
//   inward through the track the way a real stylus follows the groove
//
// The spin is integrated by a FrameAnimation from a speed that eases, so
// pausing leaves the record where it stopped rather than jumping it back
// to zero the way restarting a RotationAnimator would.
//
// Plain QtQuick. The round cover uses QtQuick.Effects' mask, and only when
// there IS a cover -- ci/plugins-test.py draws the deck without one, on a
// renderer that has no shaders.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: deck

    property var pal: ({})
    property string sans: ""

    property bool playing: false
    property bool present: true
    property string title: ""
    property string artist: ""
    property string art: ""
    // 0 to 1 through the current track.
    property real progress: 0

    // Degrees per second at full speed: 33⅓ rpm.
    readonly property real fullSpeed: 200
    property real speed: deck.playing ? deck.fullSpeed : 0
    property real angle: 0

    signal toggle
    signal next
    signal previous

    // Where the arm rests, and where it sits through a track: off the record
    // when stopped, on the lead-in at the start, near the label at the end.
    function armAngle(playing: bool, progress: real): real {
        if (!playing)
            return -6;
        return 16 + Math.max(0, Math.min(1, progress)) * 13;
    }

    implicitWidth: 300
    implicitHeight: 220

    Behavior on speed {
        NumberAnimation {
            // Up faster than down: a motor starts, a platter coasts.
            duration: deck.playing ? 900 : 2200
            easing.type: deck.playing ? Easing.OutCubic : Easing.OutQuad
        }
    }

    FrameAnimation {
        running: deck.visible && deck.speed > 0.1
        onTriggered: deck.angle = (deck.angle + deck.speed * Math.min(frameTime, 0.05)) % 360
    }

    // ── The plinth ────────────────────────────────────────────────────────
    Rectangle {
        id: plinth

        anchors.fill: parent
        radius: 22
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(deck.pal.m3surfaceContainerHigh ?? "#2b292f", Qt.alpha("#8a5a33", 0.35)) }
            GradientStop { position: 1; color: Qt.tint(deck.pal.m3surfaceContainer ?? "#211f24", Qt.alpha("#5b3a22", 0.35)) }
        }
        border.width: 1
        border.color: Qt.alpha("#ffffff", 0.08)

        Rectangle {
            // A lip of light along the top edge.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.radius
            radius: parent.radius
            color: Qt.alpha("#ffffff", 0.05)
        }
    }

    // ── The platter and the record ────────────────────────────────────────
    Item {
        id: platter

        readonly property real r: Math.min(deck.width * 0.36, deck.height * 0.43)

        x: deck.width * 0.39 - platter.r
        y: deck.height * 0.5 - platter.r
        width: platter.r * 2
        height: platter.r * 2

        // The steel rim under the record.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8
            height: width
            radius: width / 2
            color: Qt.alpha("#c9ced6", 0.35)
        }

        Item {
            id: record

            anchors.fill: parent
            rotation: deck.angle
            opacity: deck.present ? 1 : 0.55

            Behavior on opacity {
                NumberAnimation { duration: 400 }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#101012"
            }

            // Grooves.
            Repeater {
                model: 9

                Rectangle {
                    required property int index

                    anchors.centerIn: parent
                    width: record.width * (0.94 - index * 0.058)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", index % 3 === 0 ? 0.07 : 0.035)
                }
            }

            // The label: the cover when there is one, the scheme's colour and
            // the first letter of the title when there is not. A small mark
            // near its edge is how the eye sees it turn.
            Rectangle {
                id: label

                anchors.centerIn: parent
                width: record.width * 0.4
                height: width
                radius: width / 2
                color: deck.pal.m3primary ?? "#7fd8a4"

                Text {
                    anchors.centerIn: parent
                    visible: deck.art === ""
                    text: deck.present && deck.title ? deck.title.charAt(0).toUpperCase() : "♪"
                    color: deck.pal.m3onPrimary ?? "#003921"
                    font.family: deck.sans
                    font.pixelSize: label.width * 0.42
                    font.weight: Font.Bold
                }
            }

            Loader {
                anchors.fill: label
                active: deck.art !== ""

                sourceComponent: Item {
                    Image {
                        id: cover

                        anchors.fill: parent
                        source: deck.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    Rectangle {
                        id: round

                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: cover
                        maskEnabled: true
                        maskSource: round
                        // A soft edge instead of a staircase round the cover.
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }
            }

            Rectangle {
                x: label.x + label.width * 0.78
                y: label.y + label.height * 0.47
                width: label.width * 0.08
                height: width
                radius: width / 2
                color: Qt.alpha("#ffffff", 0.55)
            }
        }

        // The lamp's reflection: fixed, while the record turns under it.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            rotation: -35
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.2; color: "transparent" }
                GradientStop { position: 0.42; color: Qt.alpha("#ffffff", 0.07) }
                GradientStop { position: 0.5; color: "transparent" }
                GradientStop { position: 0.62; color: Qt.alpha("#ffffff", 0.05) }
                GradientStop { position: 0.8; color: "transparent" }
            }
        }

        // The spindle.
        Rectangle {
            anchors.centerIn: parent
            width: 7
            height: 7
            radius: 3.5
            color: "#d8dce2"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: deck.toggle()
            onWheel: wheel => {
                if (wheel.angleDelta.y < 0)
                    deck.next();
                else if (wheel.angleDelta.y > 0)
                    deck.previous();
            }
        }
    }

    // ── The tonearm ───────────────────────────────────────────────────────
    Item {
        id: arm

        x: deck.width * 0.83
        y: deck.height * 0.12
        rotation: deck.armAngle(deck.playing, deck.progress)
        transformOrigin: Item.TopLeft

        Behavior on rotation {
            NumberAnimation { duration: 700; easing.type: Easing.InOutCubic }
        }

        // The pivot.
        Rectangle {
            x: -11
            y: -11
            width: 22
            height: 22
            radius: 11
            color: "#aab0b8"
            border.width: 3
            border.color: "#6c727a"
        }

        // The arm, down and slightly in toward the record.
        Rectangle {
            x: -2
            y: 4
            width: 4
            height: deck.height * 0.66
            radius: 2
            color: "#c9ced6"
        }

        // The headshell.
        Rectangle {
            x: -7
            y: deck.height * 0.66
            width: 14
            height: 22
            radius: 3
            rotation: 18
            color: "#9aa0a8"
        }
    }

    // ── What is playing ───────────────────────────────────────────────────
    Column {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 14
        anchors.bottomMargin: 12
        width: deck.width * 0.22
        spacing: 1

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: deck.present ? deck.title : ""
            elide: Text.ElideRight
            color: deck.pal.m3onSurface ?? "white"
            font.family: deck.sans
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: deck.present ? deck.artist : ""
            elide: Text.ElideRight
            color: deck.pal.m3onSurfaceVariant ?? "#cac4cf"
            font.family: deck.sans
            font.pixelSize: 10
        }
    }

    // A pilot light: green while it plays.
    Rectangle {
        x: 16
        y: parent.height - 20
        width: 7
        height: 7
        radius: 3.5
        color: deck.playing ? (deck.pal.m3primary ?? "#7fd8a4") : Qt.alpha("#ffffff", 0.18)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }
    }
}
