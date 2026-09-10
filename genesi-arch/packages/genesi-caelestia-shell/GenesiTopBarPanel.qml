// GENESI — the top bar's own settings, on the top bar.
//
// Everything about how the bar looks is here, and only here. Not in Genesi
// Center: you change a bar while looking at it, or you change it twice --
// once in a settings window, then again after seeing what it did.
//
// The Hub keeps exactly one control for this bar, the switch that turns it on.
// A second copy of these twenty settings in an app across the screen would be
// two places to look and two places to disagree.
//
// ── A card, not a screen ────────────────────────────────────────────────────
//
// The window covers the display so a click anywhere outside dismisses it, but
// it PAINTS a card in the corner under the button that opened it. A settings
// panel that blacks out the desktop hides the thing being configured, which
// for a bar is the entire point of the panel.
//
// ── Every control writes through genesi-center-set ──────────────────────────
//
// The same writer Genesi Center and the desktop menu use. It validates the key
// and the value and owns the file format, and it takes several keys in one
// invocation -- which matters here, because a section that wrote its rows one
// process at a time is the widget-drop race again with more rows.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property var cfg: contentItem.Config.topbar
        readonly property var tok: contentItem.Tokens

        // One screen only, the focused one. Two monitors would otherwise get
        // two panels, both holding the keyboard.
        readonly property bool mine: GenesiTopBarState.open
            && Hypr.monitorFor(win.modelData)?.id === Hypr.focusedMonitor?.id

        function set(key: string, value: var): void {
            Quickshell.execDetached(["genesi-center-set", "caelestia",
                                     `topbar.${key}`, String(value)]);
        }

        screen: modelData
        name: "genesi-topbar-panel"
        visible: win.mine

        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.mine ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // Dismiss. Declared first so the card is drawn on top of it and takes
        // its own clicks.
        MouseArea {
            anchors.fill: parent
            onClicked: GenesiTopBarState.hide()
        }

        StyledRect {
            id: card

            // Under the button that opened it, on the same edge the bar is on.
            // A panel that opens at the top while the bar is at the bottom
            // makes you look for the connection between the two.
            anchors.right: parent.right
            anchors.rightMargin: win.cfg.gap * 2
            anchors.top: win.cfg.position !== "bottom" ? parent.top : undefined
            anchors.bottom: win.cfg.position === "bottom" ? parent.bottom : undefined
            anchors.topMargin: win.cfg.height + win.cfg.gap * 3
            anchors.bottomMargin: win.cfg.height + win.cfg.gap * 3

            implicitWidth: 380
            implicitHeight: Math.min(win.height * 0.8,
                                     body.implicitHeight + win.tok.padding.large * 2)

            radius: win.tok.rounding.large
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

            opacity: win.mine ? 1 : 0
            scale: win.mine ? 1 : 0.96

            Behavior on opacity {
                Anim {}
            }
            Behavior on scale {
                Anim {}
            }

            // The card eats its own clicks so the dismisser behind it never
            // sees them. Without this every toggle closes the panel.
            MouseArea {
                anchors.fill: parent
            }

            focus: true
            Keys.onEscapePressed: GenesiTopBarState.hide()

            StyledFlickable {
                id: flick

                anchors.fill: parent
                anchors.margins: win.tok.padding.large
                contentHeight: body.implicitHeight
                clip: true

                ColumnLayout {
                    id: body

                    width: flick.width
                    spacing: win.tok.spacing.small

                    // ── Where ────────────────────────────────────────────────
                    Head {
                        text: qsTr("PLACE")
                    }

                    Choice {
                        label: qsTr("Edge")
                        options: [
                            {
                                id: "top",
                                label: qsTr("TOP")
                            },
                            {
                                id: "bottom",
                                label: qsTr("BOTTOM")
                            }
                        ]
                        current: win.cfg.position
                        onPicked: id => win.set("position", id)
                    }

                    Amount {
                        label: qsTr("Height")
                        from: 24
                        to: 72
                        value: win.cfg.height
                        onCommitted: v => win.set("height", Math.round(v))
                    }

                    Amount {
                        label: qsTr("Margin")
                        from: 0
                        to: 24
                        value: win.cfg.gap
                        onCommitted: v => win.set("gap", Math.round(v))
                    }

                    // ── Shape ────────────────────────────────────────────────
                    Head {
                        text: qsTr("SHAPE")
                    }

                    SwitchRow {
                        label: qsTr("Islands")
                        checked: win.cfg.islands
                        onToggled: v => win.set("islands", v)
                    }

                    SwitchRow {
                        label: qsTr("Background")
                        checked: win.cfg.background
                        onToggled: v => win.set("background", v)
                    }

                    Amount {
                        label: qsTr("Opacity")
                        enabled: win.cfg.background
                        from: 0
                        to: 100
                        value: win.cfg.backgroundOpacity
                        onCommitted: v => win.set("backgroundOpacity", Math.round(v))
                    }

                    Amount {
                        label: qsTr("Corners")
                        from: 0
                        to: 30
                        value: win.cfg.radius
                        onCommitted: v => win.set("radius", Math.round(v))
                    }

                    // ── Contents ─────────────────────────────────────────────
                    Head {
                        text: qsTr("CONTENTS")
                    }

                    Repeater {
                        // One list, so a control cannot exist for a thing the
                        // bar does not draw, or the other way round.
                        model: [
                            {
                                key: "showLogo",
                                label: qsTr("Genesi mark")
                            },
                            {
                                key: "showSidebarButton",
                                label: qsTr("Sidebar button")
                            },
                            {
                                key: "showWorkspaces",
                                label: qsTr("Workspaces")
                            },
                            {
                                key: "showActiveWindow",
                                label: qsTr("Window title")
                            },
                            {
                                key: "showClock",
                                label: qsTr("Clock")
                            },
                            {
                                key: "showDate",
                                label: qsTr("Date")
                            },
                            {
                                key: "showResources",
                                label: qsTr("Processor and memory")
                            },
                            {
                                key: "showStatus",
                                label: qsTr("Network and battery")
                            },
                            {
                                key: "showPower",
                                label: qsTr("Power")
                            },
                            {
                                key: "showConfigButton",
                                label: qsTr("This button")
                            }
                        ]

                        SwitchRow {
                            required property var modelData

                            label: modelData.label
                            checked: win.cfg[modelData.key] === true
                            onToggled: v => win.set(modelData.key, v)
                        }
                    }

                    // Turning off the button that opens this panel is a
                    // legitimate thing to want and a bad thing to do silently,
                    // so it says how to get back.
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: win.tok.spacing.small
                        visible: !win.cfg.showConfigButton
                        text: qsTr("With that button off, this panel opens from "
                                   + "Genesi Center → Bar.")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        component Head: StyledText {
            Layout.fillWidth: true
            Layout.topMargin: win.tok.spacing.medium
            font: Tokens.font.label.small
            color: Colours.palette.m3outline
        }

        // A labelled slider that writes when you LET GO, not while you drag.
        // Dragging a slider that writes on every frame is sixty processes a
        // second rewriting shell.json.
        component Amount: StyledRect {
            id: amount

            property string label: ""
            property real from: 0
            property real to: 100
            property real value: 0

            signal committed(real v)

            Layout.fillWidth: true
            implicitHeight: amountCol.implicitHeight + win.tok.padding.large * 2
            radius: win.tok.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
            opacity: amount.enabled ? 1 : 0.45

            ColumnLayout {
                id: amountCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: win.tok.padding.large
                spacing: win.tok.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: amount.label
                    }

                    StyledText {
                        text: Math.round(slider.value)
                        font: Tokens.font.mono.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledSlider {
                    id: slider

                    Layout.fillWidth: true
                    enabled: amount.enabled
                    from: amount.from
                    to: amount.to
                    value: amount.value
                    stepSize: 1

                    onPressedChanged: if (!pressed)
                        amount.committed(value)
                }
            }
        }

        component Choice: StyledRect {
            id: choice

            property string label: ""
            property var options: []
            property string current: ""

            signal picked(string id)

            Layout.fillWidth: true
            implicitHeight: choiceRow.implicitHeight + win.tok.padding.large * 2
            radius: win.tok.rounding.large
            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

            RowLayout {
                id: choiceRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: win.tok.padding.large
                spacing: win.tok.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: choice.label
                }

                Repeater {
                    model: choice.options

                    StyledRect {
                        id: opt

                        required property var modelData

                        readonly property bool on: opt.modelData.id === choice.current

                        implicitWidth: optText.implicitWidth + win.tok.padding.large * 2
                        implicitHeight: optText.implicitHeight + win.tok.padding.small * 2
                        radius: Tokens.rounding.full
                        color: opt.on ? Colours.palette.m3primary
                                      : Colours.palette.m3surfaceContainerHighest

                        Behavior on color {
                            CAnim {}
                        }

                        StyledText {
                            id: optText

                            anchors.centerIn: parent
                            text: opt.modelData.label
                            font: Tokens.font.label.small
                            color: opt.on ? Colours.palette.m3onPrimary
                                          : Colours.palette.m3onSurfaceVariant
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: choice.picked(opt.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
