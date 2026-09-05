/*
 * InputPage — the keyboard and the pointer.
 *
 * Hyprland only. These are `input:*` options in its config; on Plasma the same
 * settings live somewhere else entirely, so the rail hides this page there
 * rather than showing controls that write to a file nothing reads.
 *
 * Every control writes through `genesi-center-set`, which does two things:
 * applies the change now with `hyprctl keyword`, and puts it in a Genesi-owned
 * drop-in so it survives a reload. Doing only the first is the setting that
 * forgets itself; doing only the second is a control that appears to do nothing.
 *
 * Nothing here assumes its own write worked -- the page re-reads afterwards and
 * shows what Hyprland reports. hyprctl accepts an option it does not know
 * without complaining, so "I set it" is not evidence that it is set.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})

    readonly property var o: page.d.options || ({})
    readonly property bool ready: page.d.available === true

    function set(option, value) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "hypr", option, String(value)],
                             "input");
    }

    function num(key, fallback) {
        const v = page.o[key];
        return (v === undefined || v === null) ? fallback : Number(v);
    }

    function flag(key) {
        return page.num(key, 0) ? true : false;
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "input")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("input")

    PageFrame {
        anchors.fill: parent
        index: "02"
        group: qsTr("Devices")
        title: qsTr("Input")
        blurb: qsTr("How the keyboard repeats and how the pointer moves. Each "
                    + "change applies at once and is written to a Genesi file "
                    + "your Hyprland config pulls in, so it is still there after "
                    + "a reload.")
        note: page.ready
              ? qsTr("%1 keyboard(s) · %2 pointer(s)")
                .arg((page.d.keyboards || []).length)
                .arg((page.d.mice || []).length)
              : qsTr("no Hyprland session — nothing here can be applied")
        noteWarn: !page.ready

        // ── Keyboard ─────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Keyboard") }

            Panel {
                width: parent.width
                height: kbCol.implicitHeight + 8

                Column {
                    id: kbCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Layout")
                        description: qsTr("The xkb layout in use. Several are written "
                                          + "comma-separated, and the compositor "
                                          + "switches between them.")
                        Text {
                            text: page.o.kb_layout ? String(page.o.kb_layout) : "us"
                            color: Tokens.textHi
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsLabel
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Repeat rate")
                        description: qsTr("Characters per second while a key is held.")
                        Slider {
                            width: 220
                            from: 10; to: 60; step: 1; unit: "/s"
                            value: page.num("repeat_rate", 25)
                            onReleased: v => page.set("input:repeat_rate", v)
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Repeat delay")
                        description: qsTr("How long a key must be held before it "
                                          + "starts repeating.")
                        Slider {
                            width: 220
                            from: 150; to: 800; step: 10; unit: "ms"
                            value: page.num("repeat_delay", 600)
                            onReleased: v => page.set("input:repeat_delay", v)
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Focus follows the pointer")
                        description: qsTr("Whether moving the pointer over a window "
                                          + "focuses it without a click.")
                        last: true
                        Toggle {
                            checked: page.num("follow_mouse", 1) > 0
                            onToggled: v => page.set("input:follow_mouse", v ? 1 : 0)
                        }
                    }
                }
            }
        }

        // ── Pointer ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Pointer") }

            Panel {
                width: parent.width
                height: ptrCol.implicitHeight + 8

                Column {
                    id: ptrCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Sensitivity")
                        description: qsTr("Hyprland's range is -1 to 1, where 0 is "
                                          + "the device's own speed. This is a "
                                          + "multiplier, not a DPI setting.")
                        Slider {
                            width: 220
                            from: -100; to: 100; step: 5; unit: "%"
                            // Sent to Hyprland as -1..1; shown as a percentage
                            // because "0.35" means nothing to anyone.
                            value: Math.round(page.num("sensitivity", 0) * 100)
                            onReleased: v => page.set("input:sensitivity", v / 100)
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Acceleration")
                        description: qsTr("Adaptive speeds up with fast movement. "
                                          + "Flat is one-to-one, which is what most "
                                          + "people want for aiming.")
                        Segmented {
                            options: [{ id: "adaptive", label: qsTr("Adaptive") },
                                      { id: "flat", label: qsTr("Flat") }]
                            current: page.o.accel_profile
                                     ? String(page.o.accel_profile) : "adaptive"
                            onPicked: id => page.set("input:accel_profile", id)
                        }
                    }

                    SettingRow {
                        width: parent.width
                        label: qsTr("Natural scrolling")
                        description: qsTr("The content follows your fingers rather "
                                          + "than the scrollbar.")
                        last: true
                        Toggle {
                            checked: page.flag("natural_scroll")
                            onToggled: v => page.set("input:natural_scroll", v)
                        }
                    }
                }
            }
        }

        // ── Touchpad ─────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            // Shown only when there is one. A touchpad section on a desktop is
            // three controls that do nothing, which is the whole failure this
            // app exists to stop.
            visible: page.ready && page.d.has_touchpad === true

            SectionHead { index: "—"; text: qsTr("Touchpad") }

            Panel {
                width: parent.width
                height: tpCol.implicitHeight + 8

                Column {
                    id: tpCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Tap to click")
                        Toggle {
                            checked: page.flag("tp_tap")
                            onToggled: v => page.set("input:touchpad:tap-to-click", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Natural scrolling")
                        Toggle {
                            checked: page.flag("tp_natural_scroll")
                            onToggled: v => page.set("input:touchpad:natural_scroll", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Ignore while typing")
                        description: qsTr("Stops the heel of your hand moving the "
                                          + "pointer mid-sentence.")
                        Toggle {
                            checked: page.flag("tp_dwt")
                            onToggled: v => page.set("input:touchpad:disable_while_typing", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Scroll speed")
                        last: true
                        Slider {
                            width: 220
                            from: 20; to: 300; step: 10; unit: "%"
                            value: Math.round(page.num("tp_scroll_factor", 1) * 100)
                            onReleased: v => page.set("input:touchpad:scroll_factor", v / 100)
                        }
                    }
                }
            }
        }

        // ── Devices ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready && (page.d.keyboards || []).length > 0

            SectionHead { index: "—"; text: qsTr("Attached") }

            Panel {
                width: parent.width
                height: devCol.implicitHeight + 28

                Column {
                    id: devCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 14
                    spacing: 6

                    Repeater {
                        model: (page.d.keyboards || []).concat(page.d.mice || [])
                        delegate: Row {
                            required property var modelData
                            width: devCol.width
                            spacing: 10

                            Text {
                                width: parent.width - 120
                                text: modelData.name || "—"
                                color: Tokens.text
                                font.family: Tokens.mono
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Text {
                                width: 110
                                horizontalAlignment: Text.AlignRight
                                text: modelData.layout ? String(modelData.layout)
                                                       : qsTr("pointer")
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
