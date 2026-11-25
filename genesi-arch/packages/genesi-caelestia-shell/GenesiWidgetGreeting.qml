// GENESI desktop widget: a greeting.
//
// Typography and nothing else -- which is why its default look on a fresh
// install is the minimal style: a greeting in a box is a notification.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

GenesiWidgetCard {
    id: w

    readonly property string who: {
        const u = Quickshell.env("USER") || Quickshell.env("USERNAME") || "";
        return u ? u.charAt(0).toUpperCase() + u.slice(1) : "";
    }

    Column {
        spacing: 0

        GenesiWGradText {
            s: w.s
            size: 42
            fontWeight: Font.Light
            from: w.accent
            to: w.accent2
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
        }
        GenesiWText {
            s: w.s
            size: 20
            font.weight: Font.Medium
            text: w.who
            color: w.ink
            visible: text !== ""
        }
    }
}
