// GENESI desktop widget: an analogue clock
//
// Hands, not digits -- the digital one upstream already ships is better at
// being read, and this one is better at being looked at. The hour hand moves
// with the minutes, because an hour hand that jumps is the tell that a clock
// face was drawn by somebody who did not look at one.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    readonly property int size: 132

    Item {
        implicitWidth: root.size
        implicitHeight: root.size

        StyledRect {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
        }

        Repeater {
            model: 12

            Item {
                id: tick

                required property int index

                anchors.fill: parent
                rotation: tick.index * 30

                StyledRect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    implicitWidth: tick.index % 3 === 0 ? 3 : 2
                    implicitHeight: tick.index % 3 === 0 ? 10 : 6
                    radius: Tokens.rounding.full
                    color: tick.index % 3 === 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                }
            }
        }

        Hand {
            length: root.size * 0.28
            thickness: 4
            colour: Colours.palette.m3onSurface
            angle: (Time.hours % 12) * 30 + Time.minutes * 0.5
        }
        Hand {
            length: root.size * 0.38
            thickness: 3
            colour: Colours.palette.m3onSurface
            angle: Time.minutes * 6
        }
        Hand {
            length: root.size * 0.42
            thickness: 2
            colour: Colours.palette.m3primary
            angle: Time.seconds * 6
        }

        StyledRect {
            anchors.centerIn: parent
            implicitWidth: 8
            implicitHeight: 8
            radius: width / 2
            color: Colours.palette.m3primary
        }
    }

    component Hand: Item {
        id: hand

        required property real length
        required property real thickness
        required property color colour
        required property real angle

        anchors.fill: parent
        rotation: angle

        StyledRect {
            id: bar

            anchors.horizontalCenter: parent.horizontalCenter
            // Grown UPWARDS from the centre of the face, so rotating the item
            // that holds it sweeps the hand around the dial rather than
            // spinning it about its own middle.
            y: parent.height / 2 - height
            implicitWidth: hand.thickness
            implicitHeight: hand.length
            radius: Tokens.rounding.full
            color: hand.colour
        }
    }
}
