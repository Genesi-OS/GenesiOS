// The leaf on Plasma: caelestia's GenesiLeaf and GenesiPetMind, unchanged,
// in the bottom-right corner above windows. Its senses come from the host
// instead of caelestia's services -- CPU and temperature from psutil, music
// from playerctl, idle from KDE's org.freedesktop.ScreenSaver, updates from
// checkupdates, the root disk -- and its state is the same genesi-pet.json,
// so its level and XP follow the person between desktops.
//
// Click: how it is doing. Right-click: nap for an hour, or put it away
// (switches the plugin off).
import QtQuick
import QtQuick.Window

Item {
    id: root

    property var pet: ({})
    property real xp: 0
    property int seenPlays: -1
    property var seenBest: ({})
    property bool loaded: false
    property real napUntil: 0
    property real happyUntil: 0
    property string lastMood: ""
    property var lines: []
    property var acts: []
    readonly property var st: host.stats
    readonly property var senses: ({
        now: Date.now(), happyUntil: root.happyUntil,
        cpu: root.st.cpu ?? 0, temp: root.st.temp ?? 0,
        playing: host.player.playing === true,
        idle: (root.st.idle === true) || Date.now() < root.napUntil,
        updates: root.st.updates ?? 0, disk: root.st.disk ?? 0, hour: root.st.hour ?? 12
    })
    readonly property string mood: mind.moodFor(root.senses)
    readonly property int level: mind.levelFor(root.xp)

    GenesiPetMind { id: mind }

    function say(text: var, ms: int, actions: var): void {
        root.lines = Array.isArray(text) ? text : [text];
        root.acts = actions ?? [];
        quiet.interval = ms;
        quiet.restart();
    }

    function save(): void {
        if (!root.loaded)
            return;
        const d = Object.assign({}, root.pet, {
            xp: Math.floor(root.xp), seenPlays: root.seenPlays, seenBest: root.seenBest
        });
        root.pet = d;
        host.writeState("genesi-pet.json", JSON.stringify(d, null, 2) + "\n");
    }

    function gain(amount: real): void {
        if (amount <= 0)
            return;
        const before = root.level;
        root.xp += amount;
        root.save();
        if (root.level > before)
            root.say(mind.t("I grew! Level %1 — %2", "Cresci! Nível %1 — %2")
                     .arg(root.level).arg(mind.title(root.level)), 6000);
    }

    function checkGames(): void {
        try {
            const g = JSON.parse(host.readState("genesi-games.json") || "{}");
            const plays = Object.values(g.plays ?? {}).reduce((a, b) => a + b, 0);
            if (root.seenPlays < 0) {
                root.seenPlays = plays;
                root.seenBest = g.best ?? {};
                root.save();
                return;
            }
            const got = mind.fromGames(plays, root.seenPlays, g.best ?? {}, root.seenBest);
            root.seenPlays = plays;
            root.seenBest = g.best ?? {};
            if (got.xp > 0) {
                root.happyUntil = Date.now() + 8000;
                root.gain(got.xp);
                if (got.line)
                    root.say(got.line, 4000);
            }
        } catch (e) {}
    }

    onMoodChanged: {
        if (!root.loaded)
            return;
        const line = mind.remark(root.lastMood, root.mood, root.senses);
        root.lastMood = root.mood;
        if (line)
            root.say(line, 5000);
    }

    Component.onCompleted: {
        try {
            root.pet = JSON.parse(host.readState("genesi-pet.json") || "{}");
        } catch (e) {
            root.pet = {};
        }
        root.xp = root.pet.xp ?? 0;
        root.seenPlays = root.pet.seenPlays ?? -1;
        root.seenBest = root.pet.seenBest ?? {};
        root.loaded = true;
        root.lastMood = root.mood;
        root.say([mind.greeting(new Date().getHours()),
                  mind.t("I'm your leaf. Click me any time.", "Sou sua folhinha. Clica em mim quando quiser.")], 6000);
        root.checkGames();
    }

    Timer {
        // A point of XP for every minute spent with the machine awake.
        interval: 60000
        repeat: true
        running: root.loaded
        onTriggered: if (!root.senses.idle) root.gain(1)
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.loaded
        onTriggered: root.checkGames()
    }

    Timer {
        id: quiet
        onTriggered: { root.lines = []; root.acts = []; }
    }

    // What takes the pointer: the leaf, and the bubble while it shows.
    function pushMask(): void {
        const w = root.Window.window;
        if (!w)
            return;
        const top = bubble.visible ? bubble.y : leaf.y;
        host.setInputRect(w, Math.min(leaf.x, bubble.x), top,
                          root.width - Math.min(leaf.x, bubble.x), root.height - top);
    }
    onLinesChanged: Qt.callLater(root.pushMask)
    onWidthChanged: Qt.callLater(root.pushMask)
    onHeightChanged: Qt.callLater(root.pushMask)

    Rectangle {
        id: bubble

        visible: root.lines.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: leaf.top
        anchors.bottomMargin: 8
        width: Math.min(260, col.implicitWidth + 24)
        height: col.implicitHeight + 18
        radius: 14
        color: host.palette.m3surfaceContainerHigh ?? "#16211d"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        Column {
            id: col

            anchors.centerIn: parent
            width: 236
            spacing: 6

            Repeater {
                model: root.lines
                Text {
                    required property var modelData
                    width: col.width
                    text: String(modelData)
                    wrapMode: Text.WordWrap
                    color: host.palette.m3onSurface ?? "#e6efe9"
                    font.pixelSize: 12
                }
            }
            Repeater {
                model: root.acts
                Rectangle {
                    required property var modelData
                    width: col.width
                    height: 26
                    radius: 8
                    color: act.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.text
                        color: host.palette.m3primary ?? "#39d98a"
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: act
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (modelData.key === "nap") {
                                root.napUntil = modelData.value === "true" ? Date.now() + 3600000 : 0;
                                root.say(modelData.value === "true" ? mind.t("Zzz... see you in an hour.", "Zzz... até daqui a uma hora.")
                                                                    : mind.t("I'm up!", "Acordei!"), 3000);
                            } else if (modelData.key === "off") {
                                host.turnOff("leaf");
                            }
                        }
                    }
                }
            }
        }
    }

    GenesiLeaf {
        id: leaf

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        size: 72
        pal: host.palette
        mood: root.mood
        level: root.level
        talking: root.lines.length > 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    const napping = Date.now() < root.napUntil;
                    root.say(mind.t("What shall we do?", "O que a gente faz?"), 8000, [
                        napping ? { key: "nap", value: "false", text: mind.t("Wake up", "Acordar") }
                                : { key: "nap", value: "true", text: mind.t("Nap for an hour", "Tirar um cochilo") },
                        { key: "off", value: "", text: mind.t("Put me away", "Me guardar") }
                    ]);
                } else {
                    leaf.hop();
                    root.say(mind.status(root.senses, root.xp), 7000);
                }
            }
        }
    }
}
