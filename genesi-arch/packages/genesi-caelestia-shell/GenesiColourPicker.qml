// GENESI — pick a colour: a saturation/brightness square, a hue strip, a hex
// field and a row of presets.
//
// `colour` is what it shows; `picked(hex)` fires while dragging (for the live
// preview) and `committed(hex)` when the drag ends (for the write). The square
// and the strip are drawn with gradients, not images, so they are sharp at any
// scale and follow nothing but the hue.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root

    property color colour: "#8fd6ab"
    signal picked(string hex)
    signal committed(string hex)

    property real hue: 0
    property real sat: 0
    property real val: 1

    readonly property var presets: ["#ffffff", "#c7d2fe", "#7cc6ff", "#8fd6ab", "#ffd36e", "#ff8a5c", "#ff6fa8", "#c89bff"]

    function hexOf(c): string {
        const h = n => ("0" + Math.round(n * 255).toString(16)).slice(-2);
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    // Untyped on purpose: it is handed both colours and "#rrggbb" strings, and
    // Qt.darker(x, 1) turns either into a colour without a type annotation
    // deciding for it.
    function load(c): void {
        c = Qt.darker(c, 1);
        root.hue = c.hsvHue < 0 ? root.hue : c.hsvHue;
        root.sat = c.hsvSaturation;
        root.val = c.hsvValue;
    }

    function send(done: bool): void {
        const hex = root.hexOf(Qt.hsva(root.hue, root.sat, root.val, 1));
        root.picked(hex);
        if (done)
            root.committed(hex);
    }

    onColourChanged: if (!square.dragging && !strip.dragging) root.load(root.colour)
    Component.onCompleted: root.load(root.colour)

    spacing: 8

    // ── Saturation and brightness ────────────────────────────────────────────
    Rectangle {
        id: square

        property bool dragging: area.pressed

        width: parent.width
        height: 118
        radius: 10
        color: Qt.hsva(root.hue, 1, 1, 1)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: "white"
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(1, 1, 1, 0)
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0)
                }
                GradientStop {
                    position: 1
                    color: "black"
                }
            }
        }

        Rectangle {
            x: root.sat * parent.width - width / 2
            y: (1 - root.val) * parent.height - height / 2
            width: 14
            height: 14
            radius: 7
            color: "transparent"
            border.width: 2
            border.color: "white"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.4)
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            function at(mx: real, my: real): void {
                root.sat = Math.max(0, Math.min(1, mx / width));
                root.val = Math.max(0, Math.min(1, 1 - my / height));
                root.send(false);
            }
            onPressed: e => area.at(e.x, e.y)
            onPositionChanged: e => area.at(e.x, e.y)
            onReleased: root.send(true)
        }
    }

    // ── Hue ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: strip

        property bool dragging: hueArea.pressed

        width: parent.width
        height: 12
        radius: 6
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: "#ff0000"
            }
            GradientStop {
                position: 1 / 6
                color: "#ffff00"
            }
            GradientStop {
                position: 2 / 6
                color: "#00ff00"
            }
            GradientStop {
                position: 3 / 6
                color: "#00ffff"
            }
            GradientStop {
                position: 4 / 6
                color: "#0000ff"
            }
            GradientStop {
                position: 5 / 6
                color: "#ff00ff"
            }
            GradientStop {
                position: 1
                color: "#ff0000"
            }
        }

        Rectangle {
            x: root.hue * parent.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 18
            radius: 3
            color: "white"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)
        }

        MouseArea {
            id: hueArea

            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            function at(mx: real): void {
                root.hue = Math.max(0, Math.min(0.999, mx / width));
                if (root.sat < 0.05)
                    root.sat = 0.7;
                if (root.val < 0.1)
                    root.val = 0.9;
                root.send(false);
            }
            onPressed: e => hueArea.at(e.x)
            onPositionChanged: e => hueArea.at(e.x)
            onReleased: root.send(true)
        }
    }

    // ── Hex ──────────────────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: 30
        radius: 8
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: hex.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

        TextInput {
            id: hex

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Colours.palette.m3onSurface
            font.family: Tokens.font.body.medium.family
            font.pixelSize: 13
            selectByMouse: true
            maximumLength: 7
            text: root.hexOf(Qt.hsva(root.hue, root.sat, root.val, 1)).toUpperCase()
            validator: RegularExpressionValidator {
                regularExpression: /#?[0-9a-fA-F]{0,6}/
            }
            onAccepted: {
                let t = text.startsWith("#") ? text : "#" + text;
                if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                    root.load(t);
                    root.send(true);
                }
            }
        }
    }

    // ── Presets ──────────────────────────────────────────────────────────────
    Row {
        spacing: (parent.width - root.presets.length * 18) / Math.max(1, root.presets.length - 1)

        Repeater {
            model: root.presets

            Rectangle {
                id: preset

                required property string modelData

                width: 18
                height: 18
                radius: 9
                color: preset.modelData
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.25)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.load(preset.modelData);
                        root.send(true);
                    }
                }
            }
        }
    }
}
