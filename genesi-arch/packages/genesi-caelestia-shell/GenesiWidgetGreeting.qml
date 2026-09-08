// GENESI desktop widget: a greeting
//
// The one widget that is not a readout. It is on the wallpaper because a
// desktop that says your name once a day is a desktop somebody set up, and
// that is worth one line of text.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Quickshell
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    readonly property string who: Quickshell.env("USER") || Quickshell.env("USERNAME") || ""

    Column {
        spacing: 2

        StyledText {
            text: {
                const h = Time.hours;
                if (h < 5)
                    return qsTr("Still up?");
                if (h < 12)
                    return qsTr("Good morning");
                if (h < 18)
                    return qsTr("Good afternoon");
                return qsTr("Good evening");
            }
            font: Tokens.font.headline.medium
            color: Colours.palette.m3onSurface
        }
        StyledText {
            text: root.who
            font: Tokens.font.body.medium
            color: Colours.palette.m3primary
            visible: text !== ""
        }
    }
}
