/*
 * WindowsPage — how a window is drawn and how it is spaced.
 *
 * Hyprland only, same as Input, and written the same way: applied now with
 * `hyprctl keyword`, kept in a Genesi drop-in the user's config sources.
 *
 * The preview at the top is drawn from the same numbers the sliders send, so
 * it cannot show a gap the compositor does not have. It exists because gaps
 * and rounding are the two settings nobody can judge from a number -- "8" is
 * meaningless and "this much space" is not.
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
                             "windows");
    }

    function num(key, fallback) {
        const v = page.o[key];
        return (v === undefined || v === null) ? fallback : Number(v);
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "windows")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("windows")

    PageFrame {
        anchors.fill: parent
        index: "03"
        group: qsTr("Desktop")
        title: qsTr("Windows")
        blurb: qsTr("Spacing, corners and borders — the geometry of every window "
                    + "on the desktop. The preview uses the same numbers the "
                    + "compositor has, so what you see is what is applied.")
        note: page.ready
              ? qsTr("%1 window(s) open across %2 workspace(s)")
                .arg(page.d.open_windows || 0).arg(page.d.workspaces || 0)
              : qsTr("no Hyprland session — nothing here can be applied")
        noteWarn: !page.ready

        // ── Preview ──────────────────────────────────────────────────────────
        Panel {
            width: parent.width
            height: 150
            visible: page.ready

            Rectangle {
                id: desk
                anchors.fill: parent
                anchors.margins: 16
                radius: Tokens.radiusSm
                color: Tokens.bg
                border.width: 1
                border.color: Tokens.lineSoft
                clip: true

                // Three windows in the layout Hyprland's dwindle gives them,
                // at the gaps and rounding actually set. The outer gap is the
                // margin, the inner gap is the space between.
                readonly property int go: Math.round(page.num("gaps_out", 20) / 2)
                readonly property int gi: Math.round(page.num("gaps_in", 5) / 2)
                readonly property int rd: Math.round(page.num("rounding", 10) / 2)
                readonly property int bw: Math.max(0, Math.round(page.num("border_size", 2)))

                Rectangle {
                    id: winA
                    anchors {
                        left: parent.left; top: parent.top; bottom: parent.bottom
                        leftMargin: desk.go; topMargin: desk.go; bottomMargin: desk.go
                    }
                    width: (desk.width - desk.go * 2 - desk.gi * 2) / 2
                    radius: desk.rd
                    color: Tokens.cardHi
                    border.width: desk.bw
                    border.color: Tokens.accentDim
                    opacity: page.num("active_opacity", 1)

                    Behavior on radius { NumberAnimation { duration: Tokens.quick } }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("active")
                        color: Tokens.accentDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        font.letterSpacing: 1.4
                    }
                }

                Rectangle {
                    anchors {
                        left: winA.right; right: parent.right; top: parent.top
                        leftMargin: desk.gi * 2; rightMargin: desk.go; topMargin: desk.go
                    }
                    height: (desk.height - desk.go * 2 - desk.gi * 2) / 2
                    radius: desk.rd
                    color: Tokens.card
                    border.width: desk.bw
                    border.color: Tokens.line
                    opacity: page.num("inactive_opacity", 1)
                    Behavior on radius { NumberAnimation { duration: Tokens.quick } }
                }

                Rectangle {
                    anchors {
                        left: winA.right; right: parent.right; bottom: parent.bottom
                        leftMargin: desk.gi * 2; rightMargin: desk.go; bottomMargin: desk.go
                    }
                    height: (desk.height - desk.go * 2 - desk.gi * 2) / 2
                    radius: desk.rd
                    color: Tokens.card
                    border.width: desk.bw
                    border.color: Tokens.line
                    opacity: page.num("inactive_opacity", 1)
                    Behavior on radius { NumberAnimation { duration: Tokens.quick } }
                }
            }
        }

        // ── Spacing ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Spacing and shape") }

            Panel {
                width: parent.width
                height: geomCol.implicitHeight + 8

                Column {
                    id: geomCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Gap between windows")
                        Slider {
                            width: 220
                            from: 0; to: 30; step: 1; unit: "px"
                            value: page.num("gaps_in", 5)
                            onReleased: v => page.set("general:gaps_in", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Gap at the screen edge")
                        description: qsTr("The bar's own space is separate from "
                                          + "this — it reserves its width and the "
                                          + "windows tile beside it.")
                        Slider {
                            width: 220
                            from: 0; to: 60; step: 2; unit: "px"
                            value: page.num("gaps_out", 20)
                            onReleased: v => page.set("general:gaps_out", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Corner rounding")
                        Slider {
                            width: 220
                            from: 0; to: 24; step: 1; unit: "px"
                            value: page.num("rounding", 10)
                            onReleased: v => page.set("decoration:rounding", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Border thickness")
                        last: true
                        Slider {
                            width: 220
                            from: 0; to: 8; step: 1; unit: "px"
                            value: page.num("border_size", 2)
                            onReleased: v => page.set("general:border_size", v)
                        }
                    }
                }
            }
        }

        // ── Transparency and blur ────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            visible: page.ready

            SectionHead { index: "—"; text: qsTr("Glass") }

            Panel {
                width: parent.width
                height: glassCol.implicitHeight + 8

                Column {
                    id: glassCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 4

                    SettingRow {
                        width: parent.width
                        label: qsTr("Focused window opacity")
                        Slider {
                            width: 220
                            from: 60; to: 100; step: 1; unit: "%"
                            value: Math.round(page.num("active_opacity", 1) * 100)
                            onReleased: v => page.set("decoration:active_opacity", v / 100)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Other windows")
                        description: qsTr("Dimming the windows you are not using is "
                                          + "the cheapest way to make the one you "
                                          + "are stand out.")
                        Slider {
                            width: 220
                            from: 40; to: 100; step: 1; unit: "%"
                            value: Math.round(page.num("inactive_opacity", 1) * 100)
                            onReleased: v => page.set("decoration:inactive_opacity", v / 100)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Blur what is behind")
                        description: qsTr("Costs GPU time on every frame. The first "
                                          + "thing to turn off on a machine that "
                                          + "feels sluggish.")
                        Toggle {
                            checked: page.num("blur", 1) > 0
                            onToggled: v => page.set("decoration:blur:enabled", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Blur strength")
                        // Dimmed rather than hidden: the control still exists,
                        // it just has nothing to act on while blur is off.
                        opacity: page.num("blur", 1) > 0 ? 1 : 0.4
                        Slider {
                            width: 220
                            enabled: page.num("blur", 1) > 0
                            from: 1; to: 16; step: 1
                            value: page.num("blur_size", 8)
                            onReleased: v => page.set("decoration:blur:size", v)
                        }
                    }
                    SettingRow {
                        width: parent.width
                        label: qsTr("Animations")
                        description: qsTr("Windows sliding and fading as they open, "
                                          + "close and move.")
                        last: true
                        Toggle {
                            checked: page.num("animations", 1) > 0
                            onToggled: v => page.set("animations:enabled", v)
                        }
                    }
                }
            }
        }
    }
}
