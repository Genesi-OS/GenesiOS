// GENESI desktop widget: weather.
//
// The temperature is the headline, set big and light the way a weather app
// sets it, with the condition's icon filled beside it. Everything else is one
// quiet line underneath.
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

GenesiWidgetCard {
    id: w

    Row {
        spacing: 16 * w.s

        GenesiWIcon {
            anchors.verticalCenter: parent.verticalCenter
            s: w.s
            size: 64
            fill: 1
            text: Weather.icon
            color: w.accent
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            GenesiWGradText {
                s: w.s
                size: 54
                fontWeight: Font.Light
                text: Weather.temp
                from: w.accent
                to: w.accent2
            }
            GenesiWText {
                s: w.s
                size: 15
                font.weight: Font.Medium
                text: Weather.description
                color: w.ink
            }
            GenesiWText {
                s: w.s
                size: 12
                text: qsTr("Feels like %1").arg(Weather.feelsLike)
                color: w.inkFaint
            }
        }
    }
}
