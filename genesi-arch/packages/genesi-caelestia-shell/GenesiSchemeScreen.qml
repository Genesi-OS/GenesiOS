// GENESI — the colour schemes, across the whole screen.
//
// The same fan of painted cards the launcher can show, on a layer-shell surface
// of its own: edge to edge, over everything, with the desktop dimmed behind it.
//
// ── Why this is a window and not a taller launcher ──────────────────────────
//
// A colour scheme is the one setting whose value IS a picture, and the launcher
// panel is the wrong frame for a picture: it is a fixed-width slab with a
// rounded edge, so the cards have to stay inside it, stay small enough that
// nine fit, and stop short of both ends. Every one of those is a compromise
// made for a list of applications.
//
// Given a screen instead, the fan runs off both sides, the middle card is big
// enough to judge from across the room, and the desktop behind it dims so the
// only thing lit is the thing being chosen.
//
// Which of the two you get is `launcher.schemePicker`, because the launcher
// version is still the right answer for somebody who reached this by typing.
//
// ── It takes the keyboard, and gives it back ────────────────────────────────
//
// Exclusive focus only while open. A layer-shell surface that keeps exclusive
// focus after it is hidden is a desktop that has stopped responding to the
// keyboard with nothing on screen to explain why.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
// The fan and the open/closed flag both live beside the launcher's own body,
// because that is the other place the fan is used. This file lives in
// modules/background instead, which is the one directory shell.qml already
// imports -- so instantiating the window costs no new import line up there.
import qs.modules.launcher
// Schemes -- the list, and which one is on. Upstream's singleton; there is no
// second copy of it here.
import qs.modules.launcher.services

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        // Only the screen with the pointer on it. Otherwise a two-monitor
        // desktop gets two full-screen pickers, both taking the keyboard, and
        // whichever one wins is a coin toss.
        readonly property bool mine: GenesiSchemeState.open
            && Hypr.monitorFor(win.modelData)?.id === Hypr.focusedMonitor?.id

        screen: modelData
        name: "genesi-schemes"
        visible: win.mine

        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.mine ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // The scrim. Not black: the scheme's own surface colour, so the
        // moment a card is applied the ground under it changes too and the
        // choice is visible before the window has closed.
        StyledRect {
            id: scrim

            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3surface, 0.93)
            opacity: win.mine ? 1 : 0

            Behavior on opacity {
                Anim {}
            }

            // Click anywhere that is not a card to leave. The fan's own cards
            // sit above this and take their clicks first.
            MouseArea {
                anchors.fill: parent
                onClicked: GenesiSchemeState.hide()
            }
        }

        Item {
            anchors.fill: parent
            opacity: scrim.opacity

            Column {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Tokens.padding.extraLarge * 2
                spacing: Tokens.spacing.small

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Colour scheme")
                    font: Tokens.font.title.large
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // What is on now, named. The marked card says which one it
                    // is only while it happens to be near the middle.
                    text: Schemes.currentScheme || qsTr("none")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // The fan, filling the middle of the screen. `edgeInset: 0` is the
            // whole difference from the launcher's version: the outermost cards
            // hang off both sides instead of stopping short of a panel edge.
            GenesiSchemeFlow {
                id: fan

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: win.height * 0.62

                // Proportional to the screen, clamped. A card sized off the
                // width alone is a postage stamp on an ultrawide and taller
                // than the screen on a 4:3.
                cardWidth: Math.max(172, Math.min(width / 4.6, height * 0.72))
                cardHeight: Math.round(cardWidth * 1.37)
                edgeInset: 0

                filter: GenesiSchemeState.filter
                onApplied: GenesiSchemeState.hide()
            }

            // ── Typing filters, without a visible text field ─────────────────
            //
            // There is no box to click into: the window has exclusive focus and
            // nothing else on it wants a keystroke, so every printable key is a
            // filter. The line below only appears once something has been
            // typed, which keeps an empty picker to the cards alone.
            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.padding.extraLarge * 2
                implicitWidth: hint.implicitWidth + Tokens.padding.large * 2
                implicitHeight: hint.implicitHeight + Tokens.padding.medium
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.85)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                StyledText {
                    id: hint

                    anchors.centerIn: parent
                    text: GenesiSchemeState.filter
                          ? qsTr("filter: %1").arg(GenesiSchemeState.filter)
                          : qsTr("← → to browse · Enter to apply · type to filter · Esc to close")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // The keys. On the window's content item rather than on any one child,
        // because nothing here is focusable and there is nothing to tab between.
        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GenesiSchemeState.hide();
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    fan.activateCurrent();
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                    fan.decrementCurrentIndex();
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                    fan.incrementCurrentIndex();
                } else if (event.key === Qt.Key_Backspace) {
                    GenesiSchemeState.filter = GenesiSchemeState.filter.slice(0, -1);
                } else if (event.text && event.text.length === 1 && event.text >= " ") {
                    GenesiSchemeState.filter += event.text;
                } else {
                    return;
                }
                event.accepted = true;
            }
        }
    }
}
