// GENESI — the Retrospective, told as a story.
//
// Full-screen slides, one idea each, that advance on their own every few
// seconds -- the shape everybody already knows from a year-in-review. A
// click on the right half goes forward, the left half back; the arrows do
// the same, Space pauses, Esc closes.
//
// Plain QtQuick: GenesiWrapped.qml builds the slides (GenesiWrappedMath)
// and hands over the app names and icons it looked up, and this only
// shows them. ci/plugins-test.py steps through a whole story offscreen.
pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: story

    property var pal: ({})
    property string sans: ""
    property var slides: []
    // app class -> display name / icon url, looked up by the shell.
    property var names: ({})
    property var icons: ({})
    property bool portuguese: Qt.locale().name.startsWith("pt")

    property int at: 0
    property bool paused: false
    readonly property var slide: story.slides[story.at] ?? ({ kind: "none" })
    readonly property int dwell: 6500

    signal closed

    function t(en: string, pt: string): string {
        return story.portuguese ? pt : en;
    }

    function fmt(secs: real): string {
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        if (h === 0)
            return `${m}min`;
        return m ? `${h}h ${m}min` : `${h}h`;
    }

    function nameOf(app: string): string {
        return story.names[app] || app;
    }

    function go(step: int): void {
        const next = story.at + step;
        if (next >= story.slides.length) {
            story.closed();
            return;
        }
        story.at = Math.max(0, next);
        story.paused = false;
        clock.restart();
        story.enter();
    }

    function restart(): void {
        story.at = 0;
        story.paused = false;
        clock.restart();
        story.enter();
    }

    // Replays the entrance of whatever is on the slide now.
    signal enter

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Return)
            story.go(1);
        else if (event.key === Qt.Key_Left)
            story.go(-1);
        else if (event.key === Qt.Key_Space)
            story.paused = !story.paused;
        else if (event.key === Qt.Key_Escape)
            story.closed();
        else
            return;
        event.accepted = true;
    }

    Timer {
        id: clock

        interval: story.dwell
        running: story.visible && !story.paused && story.slides.length > 0
        onTriggered: story.go(1)
    }

    // ── The sky behind each slide ─────────────────────────────────────────
    readonly property var tints: [
        [story.pal.m3primary, story.pal.m3tertiary],
        [story.pal.m3tertiary, story.pal.m3secondary],
        [story.pal.m3secondary, story.pal.m3primary],
        [story.pal.m3error, story.pal.m3tertiary]
    ]
    readonly property var tint: story.tints[story.at % story.tints.length]

    Rectangle {
        anchors.fill: parent
        color: story.pal.m3surface ?? "#141318"
    }

    Repeater {
        model: 3

        Rectangle {
            id: blob

            required property int index

            width: story.width * (0.7 - blob.index * 0.15)
            height: width
            radius: width / 2
            color: story.tint[blob.index % 2] ?? "#7fd8a4"
            opacity: 0.22

            Behavior on color {
                ColorAnimation { duration: 900 }
            }

            SequentialAnimation on x {
                loops: Animation.Infinite
                running: story.visible
                NumberAnimation { from: -story.width * 0.2 + blob.index * 200; to: story.width * 0.5 - blob.index * 120; duration: 14000 + blob.index * 3000; easing.type: Easing.InOutSine }
                NumberAnimation { from: story.width * 0.5 - blob.index * 120; to: -story.width * 0.2 + blob.index * 200; duration: 14000 + blob.index * 3000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                running: story.visible
                NumberAnimation { from: -story.height * 0.2 + blob.index * 150; to: story.height * 0.45; duration: 11000 + blob.index * 2500; easing.type: Easing.InOutSine }
                NumberAnimation { from: story.height * 0.45; to: -story.height * 0.2 + blob.index * 150; duration: 11000 + blob.index * 2500; easing.type: Easing.InOutSine }
            }
        }
    }

    Rectangle {
        // A veil so text reads over any blob.
        anchors.fill: parent
        color: Qt.alpha(story.pal.m3surface ?? "#141318", 0.45)
    }

    // ── Progress, one segment a slide ─────────────────────────────────────
    Row {
        id: segments

        anchors.top: parent.top
        anchors.topMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(story.width - 80, 760)
        spacing: 6

        Repeater {
            model: story.slides.length

            Rectangle {
                id: seg

                required property int index

                width: (segments.width - (story.slides.length - 1) * segments.spacing) / Math.max(1, story.slides.length)
                height: 4
                radius: 2
                color: Qt.alpha(story.pal.m3onSurface ?? "white", 0.22)

                Rectangle {
                    height: parent.height
                    radius: 2
                    color: story.pal.m3onSurface ?? "white"
                    width: seg.index < story.at ? parent.width : seg.index > story.at ? 0 : parent.width * fill.value

                    QtObject {
                        id: fill

                        property real value: 0
                    }

                    NumberAnimation {
                        id: grow

                        target: fill
                        property: "value"
                        from: 0
                        to: 1
                        duration: story.dwell
                        paused: story.paused
                    }

                    Connections {
                        target: story

                        function onEnter(): void {
                            if (seg.index === story.at)
                                grow.restart();
                        }
                    }
                }
            }
        }
    }

    // ── The slide ─────────────────────────────────────────────────────────
    Item {
        id: stage

        anchors.centerIn: parent
        width: Math.min(story.width - 80, 900)
        height: Math.min(story.height - 200, 600)

        opacity: 0
        transform: Translate {
            id: rise
        }

        Connections {
            target: story

            function onEnter(): void {
                entrance.restart();
            }
        }

        ParallelAnimation {
            id: entrance

            NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
            NumberAnimation { target: rise; property: "y"; from: 40; to: 0; duration: 550; easing.type: Easing.OutCubic }
            NumberAnimation { target: counter; property: "value"; from: 0; to: story.slide.value ?? 0; duration: 1400; easing.type: Easing.OutCubic }
        }

        // A number that counts up to what the slide says.
        QtObject {
            id: counter

            property real value: 0
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 18

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: story.slide.title ?? ""
                wrapMode: Text.WordWrap
                color: story.pal.m3onSurface ?? "white"
                font.family: story.sans
                font.pixelSize: story.slide.kind === "intro" || story.slide.kind === "outro" || story.slide.kind === "rhythm" ? 58 : 30
                font.weight: Font.Bold
            }

            // The app, big.
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: story.slide.kind === "topapp" && source !== ""
                source: story.slide.kind === "topapp" ? (story.icons[story.slide.app] ?? "") : ""
                sourceSize.width: 128
                sourceSize.height: 128
                width: 128
                height: 128
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.kind === "topapp"
                text: story.nameOf(story.slide.app ?? "")
                color: story.tint[0] ?? "white"
                font.family: story.sans
                font.pixelSize: 54
                font.weight: Font.Black
            }

            // The big number.
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.value !== undefined
                text: story.fmt(counter.value)
                color: story.slide.kind === "topapp" ? (story.pal.m3onSurface ?? "white") : (story.tint[0] ?? "white")
                font.family: story.sans
                font.pixelSize: story.slide.kind === "topapp" ? 34 : 96
                font.weight: Font.Black
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.kind === "busiest"
                text: story.slide.day ?? ""
                color: story.pal.m3onSurface ?? "white"
                font.family: story.sans
                font.pixelSize: 40
                font.weight: Font.Bold
                font.capitalization: Font.Capitalize
            }

            // Top five: the name over a slim bar that grows, the time
            // beside it -- words never sit on a coloured fill, where half the
            // palettes would make them unreadable.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: story.slide.kind === "top5"
                width: Math.min(parent.width, 620)
                spacing: 16

                Repeater {
                    model: story.slide.kind === "top5" ? story.slide.apps : []

                    Item {
                        id: bar

                        required property var modelData
                        required property int index
                        readonly property real share: bar.modelData.secs / Math.max(1, story.slide.apps[0].secs)

                        width: parent.width
                        height: 44

                        Image {
                            id: barIcon

                            width: 40
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter
                            source: story.icons[bar.modelData.app] ?? ""
                            sourceSize.width: 40
                            sourceSize.height: 40
                        }

                        Text {
                            id: barTime

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            // Fixed, so every bar ends at the same place.
                            width: 110
                            horizontalAlignment: Text.AlignRight
                            text: story.fmt(bar.modelData.secs)
                            color: story.pal.m3onSurfaceVariant ?? "white"
                            font.family: story.sans
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Text {
                            id: barName

                            anchors.left: barIcon.right
                            anchors.leftMargin: 14
                            anchors.right: barTime.left
                            anchors.rightMargin: 14
                            y: 0
                            text: story.nameOf(bar.modelData.app)
                            elide: Text.ElideRight
                            color: story.pal.m3onSurface ?? "white"
                            font.family: story.sans
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            id: track

                            anchors.left: barName.left
                            anchors.right: barName.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            height: 10
                            radius: 5
                            color: Qt.alpha(story.pal.m3onSurface ?? "white", 0.1)

                            Rectangle {
                                id: fillBar

                                height: parent.height
                                radius: parent.radius
                                color: [story.pal.m3primary, story.pal.m3tertiary, story.pal.m3secondary,
                                        story.pal.m3error, story.pal.m3primary][bar.index] ?? "white"
                                width: 0

                                Connections {
                                    target: story

                                    function onEnter(): void {
                                        if (story.slide.kind === "top5")
                                            barGrow.restart();
                                    }
                                }

                                NumberAnimation {
                                    id: barGrow

                                    target: fillBar
                                    property: "width"
                                    from: 0
                                    to: Math.max(10, track.width * bar.share)
                                    duration: 900 + bar.index * 180
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }

            // The day in 24 bars.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: story.slide.kind === "rhythm"
                spacing: 5
                height: 150

                Repeater {
                    model: story.slide.kind === "rhythm" ? 24 : 0

                    Item {
                        id: hour

                        required property int index
                        readonly property real peak: Math.max(1, ...(story.slide.hours ?? [1]))

                        width: 18
                        height: 150

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            radius: 4
                            height: Math.max(3, 132 * (story.slide.hours?.[hour.index] ?? 0) / hour.peak)
                            color: hour.index >= 22 || hour.index < 5 ? (story.pal.m3tertiary ?? "white") : (story.pal.m3primary ?? "white")
                            opacity: 0.9
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.kind === "games"
                text: story.t("%1 games played", "%1 partidas").arg(story.slide.total ?? 0)
                color: story.tint[0] ?? "white"
                font.family: story.sans
                font.pixelSize: 72
                font.weight: Font.Black
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.kind === "games" && !!story.slide.favourite
                text: story.t("Your favourite: %1", "Seu favorito: %1").arg(story.slide.favourite ?? "")
                    + (story.slide.best !== undefined ? story.t(" · best %1", " · recorde %1").arg(story.slide.best) : "")
                color: story.pal.m3onSurface ?? "white"
                font.family: story.sans
                font.pixelSize: 24
            }

            GenesiLeaf {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: story.slide.kind === "leaf"
                size: 190
                pal: story.pal
                mood: "happy"
                level: story.slide.level ?? 1
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: story.slide.kind === "leaf"
                text: story.t("%1 · level %2", "%1 · nível %2").arg(story.slide.name ?? "").arg(story.slide.level ?? 1)
                color: story.tint[0] ?? "white"
                font.family: story.sans
                font.pixelSize: 36
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: !!story.slide.line
                text: story.slide.line ?? ""
                wrapMode: Text.WordWrap
                color: story.pal.m3onSurfaceVariant ?? "white"
                font.family: story.sans
                font.pixelSize: 22
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: story.slide.kind === "total" && story.slide.change !== null && story.slide.change !== undefined
                width: changeText.implicitWidth + 32
                height: 40
                radius: 20
                color: (story.slide.change ?? 0) >= 0 ? Qt.alpha(story.pal.m3primary ?? "white", 0.25) : Qt.alpha(story.pal.m3tertiary ?? "white", 0.25)

                Text {
                    id: changeText

                    anchors.centerIn: parent
                    text: (story.slide.change ?? 0) >= 0
                        ? story.t("+%1% on the last one", "+%1% que o anterior").arg(story.slide.change)
                        : story.t("%1% on the last one", "%1% que o anterior").arg(story.slide.change)
                    color: story.pal.m3onSurface ?? "white"
                    font.family: story.sans
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // Left half back, right half forward.
    MouseArea {
        anchors.fill: parent
        onClicked: mouse => story.go(mouse.x < story.width / 3 ? -1 : 1)
        onPressAndHold: story.paused = true
        onReleased: if (story.paused && !clock.running)
            story.paused = false
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        anchors.horizontalCenter: parent.horizontalCenter
        text: story.paused ? story.t("Paused · Space to carry on", "Pausado · Espaço para continuar")
            : story.t("Click or → to go on · ← back · Esc to close", "Clique ou → para seguir · ← volta · Esc fecha")
        color: Qt.alpha(story.pal.m3onSurface ?? "white", 0.55)
        font.family: story.sans
        font.pixelSize: 13
    }

    // The ×, for anybody who does not reach for Esc.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 22
        width: 40
        height: 40
        radius: 20
        color: closeArea.containsMouse ? Qt.alpha(story.pal.m3onSurface ?? "white", 0.16) : Qt.alpha(story.pal.m3onSurface ?? "white", 0.08)

        // Drawn, not a "✕" from whatever font has one.
        Repeater {
            model: [45, -45]

            Rectangle {
                required property int modelData

                anchors.centerIn: parent
                width: 18
                height: 2
                radius: 1
                rotation: modelData
                color: story.pal.m3onSurface ?? "white"
            }
        }

        MouseArea {
            id: closeArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: story.closed()
        }
    }
}
