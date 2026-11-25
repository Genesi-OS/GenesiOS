/*
 * Slider — a number you set by dragging, for the settings that are a quantity.
 *
 * Gaps, rounding, volume, the frame around the desktop: all of them are "how
 * much", and a text field for a value between 0 and 30 makes a person type
 * what they could have dragged.
 *
 * The one rule that matters here: `value` is a BINDING to whatever the system
 * reports, and dragging must not destroy it. QML kills a binding permanently
 * the moment anything writes the property imperatively, which is how a control
 * ends up showing the last thing that was dragged forever, ignoring the real
 * value underneath. So the drag writes `local` and the paint reads
 * `dragging ? local : value` -- the binding is never touched.
 *
 * `released` rather than a continuous signal: every one of these ends in a
 * subprocess, and a hyprctl per pixel of travel would be hundreds of them.
 */
import QtQuick
import ".."

Item {
    id: root

    property real from: 0
    property real to: 100
    property real value: 0
    property real step: 1
    property string unit: ""
    property bool enabled: true

    // Emitted when the drag ends, and on a click on the track.
    signal released(real value)

    implicitHeight: 26
    implicitWidth: 200

    property bool dragging: false
    property real local: root.value
    readonly property real shown: root.dragging ? root.local : root.value
    readonly property real frac: root.to > root.from
                                 ? Math.max(0, Math.min(1, (shown - from) / (to - from)))
                                 : 0

    function pick(x) {
        const w = Math.max(1, track.width);
        const raw = from + (to - from) * Math.max(0, Math.min(1, x / w));
        return Math.round(raw / step) * step;
    }

    Rectangle {
        id: track
        anchors { left: parent.left; right: readout.left; verticalCenter: parent.verticalCenter }
        anchors.rightMargin: 12
        height: 4
        radius: 2
        color: Tokens.lineSoft
        opacity: root.enabled ? 1 : 0.4

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * root.frac
            radius: 2
            color: root.enabled ? Tokens.accentDim : Tokens.textFaint
        }

        Rectangle {
            id: knob
            x: parent.width * root.frac - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: root.dragging || hov.hovered ? Tokens.accent : Tokens.textDim
            border.width: 1
            border.color: Tokens.bg
            Behavior on color { ColorAnimation { duration: Tokens.quick } }
            scale: root.dragging ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.quick } }
        }

        HoverHandler { id: hov; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -11
            anchors.bottomMargin: -11
            enabled: root.enabled
            onPressed: mouse => {
                root.local = root.pick(mouse.x);
                root.dragging = true;
            }
            onPositionChanged: mouse => {
                if (root.dragging)
                    root.local = root.pick(mouse.x);
            }
            onReleased: {
                root.dragging = false;
                root.released(root.local);
            }
        }
    }

    Text {
        id: readout
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 48
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.shown) + root.unit
        color: root.dragging ? Tokens.accent : Tokens.text
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsLabel
    }
}
