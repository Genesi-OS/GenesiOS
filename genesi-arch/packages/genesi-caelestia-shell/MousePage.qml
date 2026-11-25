//
// MousePage.qml — pointer speed inside caelestia's own settings.
//
// caelestia's Nexus has no mouse page at all: not shipped, not even commented
// out in PageRegistry the way Display is. So this adds the registry entry as
// well as the page, which is why the override is wider than the Updates one.
//
// ── Written in caelestia's design language on purpose ────────────────────────
//
// PageBase / SliderRow / SelectRow / InfoRow / SectionHeader with Tokens and
// Colours — not one Genesi component. The colours here retint live from the
// wallpaper and our fixed emerald would fight them. The page is Genesi by what
// it DOES, not by how it looks. Same reasoning as UpdatesPage.qml.
//
// ── Why everything goes through genesi-input ─────────────────────────────────
//
// Pointer speed is a different setting per session, applied through a different
// mechanism, to a device that has to be identified first. That logic lives in
// genesi-input so the KDE side and a terminal get the same behaviour, and so
// this file stays a view. It is also why the page can honestly say WHICH
// device it is talking about — the thing Plasma's slider could not.
//
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // -1 .. 1, where 0 is the hardware's own speed. The same range and meaning
    // on Hyprland and on libinput, so the number means one thing everywhere.
    property real speed: 0
    property string accel: ""
    property string sessionKind: ""
    property var pointers: []
    property bool loaded: false

    // index 0 = adaptive, 1 = flat -- the order onSelected reads back.
    readonly property list<MenuItem> accelItems: [
        MenuItem {
            text: qsTr("Adaptive")
            icon: "trending_up"
        },
        MenuItem {
            text: qsTr("Flat")
            icon: "trending_flat"
        }
    ]

    title: qsTr("Mouse")

    function refresh(): void {
        readProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // One call, parsed into everything the page shows. `genesi-input list`
        // already prints the session kind and every pointer with its real
        // current speed, so asking twice would be asking the same question in
        // two ways and risking two answers.
        Process {
            id: readProc

            running: true
            command: ["sh", "-c", "genesi-input list 2>/dev/null; echo '__SHOW__'; genesi-input show 2>/dev/null"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n");
                    const devs = [];
                    let kind = "";
                    let pending = "";
                    let inShow = false;
                    for (const raw of lines) {
                        const line = raw.trim();
                        if (line === "__SHOW__") {
                            inShow = true;
                            continue;
                        }
                        if (line.startsWith("session:")) {
                            kind = line.substring(8).trim();
                            continue;
                        }
                        if (inShow) {
                            // "pointer speed +0.35 (adjusted)" or
                            // "Name: speed +0.35  acceleration adaptive"
                            const sm = line.match(/speed\s+([-+]?[0-9.]+)/);
                            if (sm)
                                root.speed = parseFloat(sm[1]);
                            const am = line.match(/acceleration\s+(\w+)/);
                            if (am && am[1] !== "—")
                                root.accel = am[1];
                            continue;
                        }
                        const dm = line.match(/^speed\s+([-+]?[0-9.—]+)\s+acceleration\s+(\S+)/);
                        if (dm && pending) {
                            devs.push({
                                name: pending,
                                speed: dm[1],
                                accel: dm[2]
                            });
                            pending = "";
                            continue;
                        }
                        // A device name is the line before its speed line, and
                        // is neither prose nor blank.
                        if (line.length > 0 && !line.startsWith("Every ")
                            && !line.startsWith("This is") && !line.startsWith("no ")
                            && !line.match(/^[a-z ,.'—]+$/))
                            pending = line;
                    }
                    root.pointers = devs;
                    root.sessionKind = kind;
                    root.loaded = true;
                }
            }
        }

        Process {
            id: applyProc

            // A fixed program with a computed numeric argument. Nothing the
            // user types reaches a shell: the slider produces a number and the
            // number is passed as one argv element.
            property real pending: 0

            command: ["genesi-input", "speed", applyProc.pending.toFixed(2)]
            onExited: root.refresh()
        }

        Process {
            id: accelProc

            property string profile: "adaptive"

            command: ["genesi-input", "accel", accelProc.profile]
            onExited: root.refresh()
        }

        // ── The one control that matters ─────────────────────────────────────
        //
        // genesi-input's range is -1 .. 1 and the slider's is 0 .. 1, so the
        // mapping happens here rather than in the tool: a CLI that took 0..1
        // and meant -1..1 would be lying to everyone who is not this page.
        SliderRow {
            Layout.fillWidth: true
            first: true
            icon: "mouse"
            label: qsTr("Pointer speed")
            value: (root.speed + 1) / 2
            valueLabel: root.speed === 0 ? qsTr("Default") : (root.speed > 0 ? "+" : "") + root.speed.toFixed(2)
            onMoved: v => {
                const s = Math.round((v * 2 - 1) * 20) / 20;   // 0.05 steps
                root.speed = s;
                applyProc.pending = s;
                applyProc.running = true;
            }
        }

        SelectRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Acceleration")
            subtext: root.accel === "flat" ? qsTr("Raw movement — the pointer travels the same distance however fast you move") : qsTr("The pointer travels further when you move faster")
            menuItems: root.accelItems
            active: root.accelItems[root.accel === "flat" ? 1 : 0]
            onSelected: item => {
                accelProc.profile = root.accelItems.indexOf(item) === 1 ? "flat" : "adaptive";
                accelProc.running = true;
            }
        }

        // ── Which device this is actually talking about ──────────────────────
        //
        // The reason a desktop's mouse slider can appear to do nothing is that
        // the desktop decides what counts as "a mouse", and a pointer it did
        // not classify never receives the value. Naming the devices turns that
        // from a mystery into a fact — and it is the one thing a settings page
        // can add over the CLI, because it is here that people go looking when
        // the slider seems dead.
        SectionHeader {
            visible: root.pointers.length > 0
            text: qsTr("Pointers found")
        }

        Repeater {
            model: root.pointers

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.pointers.length - 1
                label: modelData.name
                subtext: qsTr("Acceleration: %1").arg(modelData.accel)
                value: modelData.speed
            }
        }

        // Plasma Wayland has no per-device pointer API outside the compositor,
        // so there is nothing honest this page can offer there. Saying so beats
        // showing a slider that moves and changes nothing.
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.loaded && root.pointers.length === 0
            first: true
            last: true
            implicitHeight: emptyCol.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: emptyCol

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "mouse"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.icon.large
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.sessionKind === "wayland-other" ? qsTr("This session has no per-device pointer API outside the compositor, so its own mouse settings are the only place this can be changed.") : qsTr("No pointer devices were found.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }
    }
}
