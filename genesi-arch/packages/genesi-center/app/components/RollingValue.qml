/*
 * RollingValue — text that changes by moving, not by being replaced.
 *
 * For readings that are a STRING rather than a number: a transfer rate, an
 * uptime. A number can count to its new value and that is better; a string
 * cannot, and swapping it in place is the thing that makes a dashboard look
 * like a table being rewritten every few seconds.
 *
 * Two labels in a clipped box: the outgoing one rises and fades, the incoming
 * one arrives from below.
 */
import QtQuick
import ".."

Item {
    id: root

    property string value: ""
    property color color: Tokens.textHi
    property int pixelSize: Tokens.fsValue

    implicitWidth: Math.max(current.implicitWidth, previous.implicitWidth)
    implicitHeight: current.implicitHeight
    clip: true

    onValueChanged: {
        if (previous.text === "" && current.text === "") {
            current.text = value;   // first value: no roll, nothing to roll from
            return;
        }
        if (value === current.text)
            return;
        previous.text = current.text;
        current.text = value;
        roll.restart();
    }

    Text {
        id: previous
        y: 0
        color: root.color
        font.family: Tokens.mono
        font.pixelSize: root.pixelSize
        opacity: 0
    }

    Text {
        id: current
        y: 0
        color: root.color
        font.family: Tokens.mono
        font.pixelSize: root.pixelSize
    }

    ParallelAnimation {
        id: roll
        NumberAnimation {
            target: previous; property: "y"
            from: 0; to: -root.height
            duration: Tokens.normal; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: previous; property: "opacity"
            from: 1; to: 0
            duration: Tokens.normal
        }
        NumberAnimation {
            target: current; property: "y"
            from: root.height; to: 0
            duration: Tokens.normal; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: current; property: "opacity"
            from: 0; to: 1
            duration: Tokens.normal
        }
    }
}
