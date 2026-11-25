// GENESI — the leaf: how the desktop pet looks and moves.
//
// Drawing only. What the leaf FEELS is decided in GenesiPetMind from what
// the machine is doing; this is handed the answer as `mood` and shows it.
// Plain QtQuick and Shapes, so ci/plugins-test.py can draw every mood
// offscreen and look at it.
//
//   normal    sways on its stem, blinks now and then
//   happy     ^ ^ eyes, blushing, a little bounce
//   sleeping  eyes shut, darker, a slow "z" drifting up
//   hot       turning autumn at the edges, sweating
//   sick      yellowing, brown spots, a wobbly mouth
//   dancing   swings to the beat of whatever is playing
//
// ── Drawn in a 100 x 120 box and scaled ───────────────────────────────────
//
// Every coordinate below is in that one box, so the shape can be read as a
// drawing rather than as arithmetic on `size`. The CurveRenderer keeps the
// outline sharp at any scale, which is the point of drawing it at all
// instead of shipping a sprite that would blur at 2x.
//
// ── It grows ──────────────────────────────────────────────────────────────
//
// Level 3 brings a drop of dew, level 5 a flower at the stem, level 8 a
// golden edge. Growing is something a person should SEE happen, not read in
// a number.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: leaf

    property var pal: ({})
    property string mood: "normal"
    property int level: 1
    property bool talking: false
    // Where the pointer is, relative to the leaf's centre, from -1 to 1.
    // The eyes follow it a little.
    property point look: Qt.point(0, 0)
    property real size: 72

    readonly property color green: "#5cbf6e"
    readonly property color autumn: "#e0773a"
    readonly property color straw: "#d2c455"
    readonly property color ink: "#173a22"

    // Not readonly: a Behavior animates it, and a readonly property cannot
    // be written -- not even by an animation.
    property color body: {
        const base = Qt.tint(leaf.green, Qt.alpha(leaf.pal.m3primary ?? leaf.green, 0.3));
        if (leaf.mood === "hot")
            return Qt.tint(base, Qt.alpha(leaf.autumn, 0.78));
        if (leaf.mood === "sick")
            return Qt.tint(base, Qt.alpha(leaf.straw, 0.6));
        if (leaf.mood === "sleeping")
            return Qt.darker(base, 1.25);
        return base;
    }
    readonly property color edge: leaf.level >= 8 ? "#e6c35c" : Qt.darker(leaf.body, 1.45)

    function hop(): void {
        hopAnim.restart();
    }

    implicitWidth: leaf.size
    implicitHeight: leaf.size * 1.2

    Behavior on body {
        ColorAnimation { duration: 900 }
    }

    Item {
        id: art

        width: 100
        height: 120
        scale: leaf.size / 100
        transformOrigin: Item.TopLeft
        transform: [
            Translate {
                id: lift
            },
            Translate {
                id: bounce
            }
        ]

        // The whole leaf swings from where the stem meets the ground.
        Item {
            id: plant

            anchors.fill: parent
            transformOrigin: Item.Bottom

            SequentialAnimation on rotation {
                id: sway

                loops: Animation.Infinite
                running: leaf.visible && leaf.mood !== "dancing"
                NumberAnimation {
                    to: leaf.mood === "sleeping" ? 2 : 5
                    duration: leaf.mood === "sleeping" ? 2600 : 1700
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: leaf.mood === "sleeping" ? -2 : -5
                    duration: leaf.mood === "sleeping" ? 2600 : 1700
                    easing.type: Easing.InOutSine
                }
            }

            SequentialAnimation on rotation {
                loops: Animation.Infinite
                running: leaf.visible && leaf.mood === "dancing"
                NumberAnimation { to: 14; duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { to: -14; duration: 520; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0; duration: 260; easing.type: Easing.InQuad }
            }

            // Stem
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Qt.darker(leaf.body, 1.6)
                    strokeWidth: 4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 50
                    startY: 96
                    PathQuad { x: 44; y: 117; controlX: 50; controlY: 110 }
                }
            }

            // The blade, the midrib and the veins.
            Shape {
                id: blade

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: leaf.edge
                    strokeWidth: leaf.level >= 8 ? 3 : 2
                    joinStyle: ShapePath.RoundJoin
                    fillGradient: LinearGradient {
                        x1: 20
                        y1: 10
                        x2: 80
                        y2: 100
                        GradientStop { position: 0; color: Qt.lighter(leaf.body, 1.25) }
                        GradientStop { position: 1; color: leaf.body }
                    }
                    startX: 50
                    startY: 100
                    PathCubic { x: 50; y: 6; control1X: 6; control1Y: 88; control2X: 4; control2Y: 32 }
                    PathCubic { x: 50; y: 100; control1X: 96; control1Y: 32; control2X: 94; control2Y: 88 }
                }

                ShapePath {
                    strokeColor: Qt.alpha(Qt.darker(leaf.body, 1.5), 0.55)
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 50
                    startY: 97
                    PathQuad { x: 50; y: 16; controlX: 53; controlY: 56 }
                }

                ShapePath {
                    strokeColor: Qt.alpha(Qt.darker(leaf.body, 1.4), 0.35)
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 51
                    startY: 84
                    PathQuad { x: 27; y: 70; controlX: 38; controlY: 82 }
                    PathMove { x: 51; y: 84 }
                    PathQuad { x: 74; y: 70; controlX: 63; controlY: 82 }
                    PathMove { x: 51; y: 44 }
                    PathQuad { x: 31; y: 30; controlX: 40; controlY: 42 }
                    PathMove { x: 51; y: 44 }
                    PathQuad { x: 70; y: 30; controlX: 61; controlY: 42 }
                }
            }

            // Autumn creeping in from the edge, and the spots of a sick leaf.
            Repeater {
                model: leaf.mood === "sick" ? [[30, 38, 7], [68, 58, 5], [36, 80, 4]] : []

                Rectangle {
                    required property var modelData

                    x: modelData[0] - modelData[2]
                    y: modelData[1] - modelData[2]
                    width: modelData[2] * 2
                    height: modelData[2] * 1.7
                    radius: modelData[2]
                    color: Qt.alpha("#7a5a2a", 0.55)
                }
            }

            // ── The face ────────────────────────────────────────────────────
            Item {
                id: face

                x: 50 + leaf.look.x * 3
                y: 58 + leaf.look.y * 2

                Behavior on x {
                    NumberAnimation { duration: 180 }
                }
                Behavior on y {
                    NumberAnimation { duration: 180 }
                }

                Repeater {
                    model: [-1, 1]

                    Item {
                        id: eye

                        required property int modelData

                        x: eye.modelData * 12
                        y: 0

                        // Open: a tall dark oval with a glint.
                        Rectangle {
                            id: open

                            visible: leaf.mood !== "sleeping" && leaf.mood !== "happy"
                            x: -4
                            y: -6
                            width: 8
                            height: 11
                            radius: 4
                            color: leaf.ink
                            transform: Scale {
                                origin.y: 5.5
                                yScale: leaf.lid
                            }

                            Rectangle {
                                x: 4.5
                                y: 2
                                width: 2.6
                                height: 2.6
                                radius: 1.3
                                color: "white"
                            }
                        }

                        // Shut, asleep: a small downward curve.
                        Shape {
                            visible: leaf.mood === "sleeping"
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: leaf.ink
                                strokeWidth: 2
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                startX: -5
                                startY: 0
                                PathQuad { x: 5; y: 0; controlX: 0; controlY: 4 }
                            }
                        }

                        // Happy: ^
                        Shape {
                            visible: leaf.mood === "happy"
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: leaf.ink
                                strokeWidth: 2.4
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                startX: -5
                                startY: 2
                                PathLine { x: 0; y: -4 }
                                PathLine { x: 5; y: 2 }
                            }
                        }
                    }
                }

                // Blush, when it is pleased.
                Repeater {
                    model: leaf.mood === "happy" || leaf.mood === "dancing" ? [-1, 1] : []

                    Rectangle {
                        required property int modelData

                        x: modelData * 18 - 4
                        y: 5
                        width: 8
                        height: 4.5
                        radius: 2.25
                        color: Qt.alpha("#ff8fa3", 0.6)
                    }
                }

                // Mouth: a smile, a frown, or open while it talks.
                Shape {
                    visible: !leaf.talking && leaf.mood !== "sleeping"
                    y: 9
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: leaf.ink
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: -5
                        startY: 0
                        PathQuad {
                            x: 5
                            y: 0
                            controlX: 0
                            controlY: leaf.mood === "sick" ? -4 : leaf.mood === "hot" ? 1 : 5
                        }
                    }
                }

                Rectangle {
                    id: talkMouth

                    visible: leaf.talking || leaf.mood === "sleeping"
                    x: -3
                    y: 8
                    width: 6
                    height: leaf.mood === "sleeping" ? 3 : 5
                    radius: 3
                    color: leaf.ink

                    SequentialAnimation on height {
                        loops: Animation.Infinite
                        running: leaf.talking
                        NumberAnimation { to: 2; duration: 140 }
                        NumberAnimation { to: 6; duration: 140 }
                    }
                }
            }

            // Level 3: a drop of dew.
            Rectangle {
                visible: leaf.level >= 3
                x: 64
                y: 30
                width: 9
                height: 10
                radius: 4.5
                color: Qt.alpha("#cfefff", 0.8)
                border.width: 1
                border.color: Qt.alpha("#ffffff", 0.9)

                Rectangle {
                    x: 2
                    y: 2
                    width: 3
                    height: 3
                    radius: 1.5
                    color: "white"
                }
            }

            // Level 5: a flower where the stem starts.
            Item {
                visible: leaf.level >= 5
                x: 58
                y: 98

                Repeater {
                    model: 5

                    Rectangle {
                        required property int index

                        x: Math.cos(index * 2 * Math.PI / 5) * 4.5 - 3.5
                        y: Math.sin(index * 2 * Math.PI / 5) * 4.5 - 3.5
                        width: 7
                        height: 7
                        radius: 3.5
                        color: "#ffd6e7"
                    }
                }
                Rectangle {
                    x: -2.5
                    y: -2.5
                    width: 5
                    height: 5
                    radius: 2.5
                    color: "#f6c945"
                }
            }
        }

        // Sweat, falling off a hot leaf.
        Rectangle {
            id: sweat

            visible: leaf.mood === "hot"
            x: 80
            width: 6
            height: 8
            radius: 3
            color: "#8fd3ff"

            SequentialAnimation on y {
                loops: Animation.Infinite
                running: leaf.mood === "hot" && leaf.visible
                NumberAnimation { from: 22; to: 46; duration: 900; easing.type: Easing.InQuad }
                PauseAnimation { duration: 500 }
            }
        }

        // A "z", drifting up from a sleeping leaf.
        Text {
            id: zzz

            visible: leaf.mood === "sleeping"
            x: 78
            text: "z"
            color: Qt.alpha(leaf.pal.m3onSurface ?? "white", 0.8)
            font.pixelSize: 16
            font.weight: Font.Bold

            SequentialAnimation on y {
                loops: Animation.Infinite
                running: leaf.mood === "sleeping" && leaf.visible
                NumberAnimation { from: 20; to: -6; duration: 2200 }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: leaf.mood === "sleeping" && leaf.visible
                NumberAnimation { from: 1; to: 0; duration: 2200 }
            }
        }
    }

    // Blinking: now and then, never on a rhythm you could set a clock by.
    Timer {
        id: blinker

        interval: 3200
        repeat: true
        running: leaf.visible && (leaf.mood === "normal" || leaf.mood === "hot" || leaf.mood === "sick")
        onTriggered: {
            blinker.interval = 2200 + Math.random() * 4200;
            blink.restart();
        }
    }

    // Eyes close and open by squashing the open eye for a moment -- the
    // lid, a scale about its middle, so the glint goes with it.
    property real lid: 1

    SequentialAnimation {
        id: blink

        NumberAnimation { target: leaf; property: "lid"; to: 0.1; duration: 70 }
        NumberAnimation { target: leaf; property: "lid"; to: 1; duration: 90 }
    }

    // A hop and a happy bounce, each on a translation of its own: the
    // leaf's own x and y belong to whoever placed it, and two animations on
    // one property are two things fighting over it.
    SequentialAnimation {
        id: hopAnim

        NumberAnimation { target: lift; property: "y"; to: -leaf.size * 0.22; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: lift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }

    SequentialAnimation {
        loops: Animation.Infinite
        running: leaf.mood === "happy" && leaf.visible
        NumberAnimation { target: bounce; property: "y"; to: -4; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: bounce; property: "y"; to: 0; duration: 220; easing.type: Easing.InQuad }
        onStopped: bounce.y = 0
    }
}
