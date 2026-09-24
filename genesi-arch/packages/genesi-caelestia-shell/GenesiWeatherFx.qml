// GENESI — the weather outside, falling on the wallpaper.
//
// Drawing only, like the leaf: GenesiLiveWeather.qml reads caelestia's
// Weather service and hands this a WMO weather code; `classify` turns the
// code into what to draw, and the rest draws it. Plain QtQuick, so
// ci/plugins-test.py can classify every code and draw every sky offscreen.
//
//   drizzle   a few thin streaks
//   rain      more, faster, leaning with the wind
//   storm     heavy rain and, now and then, lightning
//   snow      flakes that drift as they fall
//   fog       slow banks of haze
//   none      clear or cloudy: nothing at all -- a clear day is not weather
//             anybody wants drawn over their picture
//
// ── Each drop is its own small animation ──────────────────────────────────
//
// Not QtQuick.Particles: an emitter's look is an image and its motion a set
// of physics knobs, and a raindrop is a line at an angle that should read as
// rain at a glance and never as confetti. Two hundred rectangles each with
// one looping animation is cheap, exact, and stops completely when `running`
// is false -- which it is whenever a fullscreen window hides the desktop.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: fx

    property int code: 0
    property bool running: true
    // -1 to 1: how far the rain leans. From the wind speed, by the window.
    property real wind: 0.25
    // What is drawn, from the code -- or forced, for a preview.
    property string forced: ""

    readonly property var sky: fx.forced !== "" ? fx.skyOf(fx.forced) : fx.classify(fx.code)
    readonly property string kind: fx.sky.kind
    readonly property real intensity: fx.sky.intensity

    function skyOf(kind: string): var {
        const strength = { drizzle: 0.35, rain: 0.7, storm: 1, snow: 0.7, fog: 0.8, none: 0 };
        return { kind: kind, intensity: strength[kind] ?? 0 };
    }

    // WMO weather interpretation codes, as open-meteo reports them.
    function classify(code: int): var {
        if (code === 45 || code === 48)
            return { kind: "fog", intensity: code === 48 ? 1 : 0.7 };
        if (code >= 51 && code <= 57)
            return { kind: "drizzle", intensity: code >= 55 ? 0.5 : 0.3 };
        if (code >= 61 && code <= 67)
            return { kind: "rain", intensity: code === 65 || code === 67 ? 1 : code === 63 || code === 66 ? 0.7 : 0.45 };
        if (code >= 71 && code <= 77)
            return { kind: "snow", intensity: code === 75 ? 1 : code === 73 ? 0.7 : 0.45 };
        if (code >= 80 && code <= 82)
            return { kind: "rain", intensity: code === 82 ? 1 : code === 81 ? 0.75 : 0.5 };
        if (code === 85 || code === 86)
            return { kind: "snow", intensity: code === 86 ? 1 : 0.6 };
        if (code >= 95 && code <= 99)
            return { kind: "storm", intensity: 1 };
        return { kind: "none", intensity: 0 };
    }

    readonly property bool wet: fx.kind === "rain" || fx.kind === "drizzle" || fx.kind === "storm"
    readonly property int drops: fx.wet ? Math.round(40 + 190 * fx.intensity) : 0
    readonly property int flakes: fx.kind === "snow" ? Math.round(40 + 110 * fx.intensity) : 0

    // ── Rain ──────────────────────────────────────────────────────────────
    Repeater {
        model: fx.drops

        Rectangle {
            id: drop

            required property int index

            // Where along the top it starts, and how it varies: fixed per
            // drop, so the rain has texture instead of looking like a grid.
            readonly property real seed: ((drop.index * 7919) % 1000) / 1000
            readonly property real depth: 0.45 + ((drop.index * 104729) % 550) / 1000
            readonly property real fall: (fx.kind === "drizzle" ? 1500 : 820) / drop.depth

            // It travels along the angle it is drawn at, so the lean reads
            // as wind and not as a picture of tilted lines falling straight.
            x: drop.seed * (fx.width + 200) - 100 + drop.y * Math.tan(fx.wind * 18 * Math.PI / 180)
            width: fx.kind === "drizzle" ? 1 : 1.5 * drop.depth
            height: (fx.kind === "drizzle" ? 10 : 22) * drop.depth
            radius: width / 2
            rotation: -fx.wind * 18
            color: "#dcecff"
            opacity: (fx.kind === "drizzle" ? 0.28 : 0.38) * drop.depth

            NumberAnimation on y {
                running: fx.running && fx.visible
                loops: Animation.Infinite
                from: -40 - drop.seed * fx.height
                to: fx.height + 20
                duration: drop.fall * (1 + drop.seed * 0.3) * (1 + (fx.height + 40) / 900)
            }
        }
    }

    // ── Lightning ─────────────────────────────────────────────────────────
    Rectangle {
        id: flash

        anchors.fill: parent
        color: "#eef4ff"
        opacity: 0

        SequentialAnimation {
            id: strike

            NumberAnimation { target: flash; property: "opacity"; to: 0.32; duration: 60 }
            NumberAnimation { target: flash; property: "opacity"; to: 0.05; duration: 90 }
            NumberAnimation { target: flash; property: "opacity"; to: 0.24; duration: 50 }
            NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 420 }
        }

        Timer {
            interval: 9000
            repeat: true
            running: fx.running && fx.kind === "storm"
            onTriggered: {
                interval = 7000 + Math.random() * 16000;
                strike.restart();
            }
        }
    }

    // ── Snow ──────────────────────────────────────────────────────────────
    Repeater {
        model: fx.flakes

        Rectangle {
            id: flake

            required property int index

            readonly property real seed: ((flake.index * 7919) % 1000) / 1000
            readonly property real depth: 0.4 + ((flake.index * 104729) % 600) / 1000
            readonly property real home: flake.seed * fx.width

            width: 3 + 4 * flake.depth
            height: width
            radius: width / 2
            color: "white"
            opacity: 0.35 + 0.5 * flake.depth
            x: flake.home

            NumberAnimation on y {
                running: fx.running && fx.visible
                loops: Animation.Infinite
                from: -20 - flake.seed * fx.height
                to: fx.height + 10
                duration: (9000 + flake.seed * 5000) / flake.depth
            }
            SequentialAnimation on x {
                running: fx.running && fx.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: flake.home - 18 * flake.depth
                    to: flake.home + 18 * flake.depth + fx.wind * 30
                    duration: 2200 + flake.seed * 1800
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: flake.home + 18 * flake.depth + fx.wind * 30
                    to: flake.home - 18 * flake.depth
                    duration: 2200 + flake.seed * 1800
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    // ── Fog ───────────────────────────────────────────────────────────────
    Repeater {
        model: fx.kind === "fog" ? 4 : 0

        Rectangle {
            id: bank

            required property int index

            y: fx.height * (0.35 + bank.index * 0.16)
            width: fx.width * 0.9
            height: fx.height * 0.28
            radius: height / 2
            opacity: 0.1 * fx.intensity + 0.04
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: "#e8eef0" }
                GradientStop { position: 1; color: "transparent" }
            }

            SequentialAnimation on x {
                running: fx.running && fx.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: -fx.width * 0.35 + bank.index * 90
                    to: fx.width * 0.35 - bank.index * 60
                    duration: 38000 + bank.index * 9000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: fx.width * 0.35 - bank.index * 60
                    to: -fx.width * 0.35 + bank.index * 90
                    duration: 38000 + bank.index * 9000
                    easing.type: Easing.InOutSine
                }
            }
        }
    }
}
