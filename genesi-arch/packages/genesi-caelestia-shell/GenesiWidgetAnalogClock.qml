// GENESI desktop widget: an analogue clock.
//
// A dial with sixty marks, the hours picked out, hands with rounded ends, and
// the second hand in the widget's second colour. Drawn with shapes and
// rectangles at its real size, so it is as sharp at twice the size as at once.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    readonly property real dial: 160 * w.s

    Item {
        width: w.dial
        height: w.dial

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(w.ink, 0.03)
            border.width: 2 * w.s
            border.color: Qt.alpha(w.accent, 0.35)
        }

        Repeater {
            model: 60

            Item {
                id: mark

                required property int index
                readonly property bool hour: mark.index % 5 === 0

                anchors.fill: parent
                rotation: mark.index * 6

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7 * w.s
                    width: (mark.hour ? 3 : 1.5) * w.s
                    height: (mark.hour ? 11 : 5) * w.s
                    radius: width / 2
                    color: mark.hour ? w.accent : Qt.alpha(w.inkFaint, 0.6)
                }
            }
        }

        Hand {
            length: w.dial * 0.26
            thickness: 6 * w.s
            colour: w.ink
            angle: (Time.hours % 12) * 30 + Time.minutes * 0.5
        }
        Hand {
            length: w.dial * 0.36
            thickness: 4 * w.s
            colour: w.ink
            angle: Time.minutes * 6 + Time.seconds * 0.1
        }
        Hand {
            length: w.dial * 0.4
            thickness: 2 * w.s
            tail: w.dial * 0.08
            colour: w.accent2
            angle: Time.seconds * 6
        }

        Rectangle {
            anchors.centerIn: parent
            width: 12 * w.s
            height: 12 * w.s
            radius: width / 2
            color: w.accent2
            border.width: 3 * w.s
            border.color: Qt.alpha(Colours.palette.m3surface, 0.9)
        }
    }

    component Hand: Item {
        id: hand

        required property real length
        required property real thickness
        required property color colour
        required property real angle
        property real tail: 0

        anchors.fill: parent
        rotation: hand.angle

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - hand.length
            width: hand.thickness
            height: hand.length + hand.tail
            radius: width / 2
            color: hand.colour
        }
    }
}
