/*
 * KeyCapture — hold down the combination you want, and it reads it.
 *
 * A shortcut editor that asks you to TYPE "SUPER SHIFT, Q" is a shortcut
 * editor nobody uses correctly; the whole value is pressing the keys.
 *
 * Two things this has to get right, and both are why it is a component rather
 * than a handler inside the page:
 *
 *   * Qt names keys its own way and Hyprland uses xkb's names. Return is
 *     "Return", the space bar is "space" and Page Up is "Prior". A capture
 *     that hands back Qt's name writes a bind that never fires -- silent, and
 *     indistinguishable from the setting not working.
 *   * a modifier pressed on its own is not a shortcut. Holding SUPER while
 *     deciding must not be read as "the SUPER key", or every capture ends the
 *     instant you reach for it.
 *
 * Escape cancels, and it is the one combination that cannot be captured. A
 * key-grabber with no way out is a window you have to kill.
 */
import QtQuick
import ".."

Item {
    id: root

    // Emitted with e.g. (["SUPER", "SHIFT"], "Q").
    signal captured(var mods, string key)
    signal cancelled()

    property string prompt: qsTr("press a combination")

    anchors.fill: parent
    visible: false
    z: 100

    function start() {
        visible = true;
        held = "";
        grabber.forceActiveFocus();
    }

    function stop() {
        visible = false;
    }

    // What is being held right now, drawn live so it is obvious the capture is
    // listening rather than frozen.
    property string held: ""

    // Qt's key codes to the names Hyprland (xkb) uses. Only the keys a person
    // actually binds; anything else falls back to the character typed, which is
    // right for every letter and digit.
    readonly property var special: ({
        0x01000000: "Escape",
        0x01000004: "Return",
        0x01000005: "KP_Enter",
        0x01000001: "Tab",
        0x01000003: "BackSpace",
        0x01000007: "Delete",
        0x01000006: "Insert",
        0x01000010: "Home",
        0x01000011: "End",
        0x01000016: "Prior",
        0x01000017: "Next",
        0x01000012: "Left",
        0x01000013: "Up",
        0x01000014: "Right",
        0x01000015: "Down",
        0x20: "space",
        0x01000030: "F1", 0x01000031: "F2", 0x01000032: "F3",
        0x01000033: "F4", 0x01000034: "F5", 0x01000035: "F6",
        0x01000036: "F7", 0x01000037: "F8", 0x01000038: "F9",
        0x01000039: "F10", 0x0100003a: "F11", 0x0100003b: "F12"
    })

    // Modifier key codes, so holding one is not mistaken for pressing one.
    readonly property var modifierKeys: [0x01000020, 0x01000021, 0x01000022,
                                         0x01000023, 0x01000024, 0x01000025]

    function modsOf(m) {
        const out = [];
        // Meta is the SUPER key. Hyprland calls it SUPER and so does everyone
        // looking at their keyboard.
        if (m & Qt.MetaModifier)
            out.push("SUPER");
        if (m & Qt.ControlModifier)
            out.push("CTRL");
        if (m & Qt.AltModifier)
            out.push("ALT");
        if (m & Qt.ShiftModifier)
            out.push("SHIFT");
        return out;
    }

    function nameOf(event) {
        const s = root.special[event.key];
        if (s !== undefined)
            return s;
        if (event.text && event.text.trim().length === 1)
            return event.text.toUpperCase();
        return "";
    }

    Rectangle {
        anchors.fill: parent
        color: Tokens.bg
        opacity: 0.86

        // Swallows everything behind it, so a click during a capture does not
        // land on whatever row happens to be under the pointer.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.stop();
                root.cancelled();
            }
        }
    }

    Item {
        id: grabber
        anchors.fill: parent
        focus: root.visible

        Keys.onPressed: event => {
            event.accepted = true;

            if (event.key === 0x01000000) {          // Escape
                root.stop();
                root.cancelled();
                return;
            }
            if (root.modifierKeys.indexOf(event.key) >= 0) {
                // A modifier alone: show it, wait for the real key.
                const m = root.modsOf(event.modifiers);
                root.held = m.length > 0 ? m.join(" + ") + " + …" : "…";
                return;
            }

            const key = root.nameOf(event);
            if (key === "")
                return;

            const mods = root.modsOf(event.modifiers);
            root.held = (mods.length > 0 ? mods.join(" + ") + " + " : "") + key;
            root.stop();
            root.captured(mods, key);
        }

        Keys.onReleased: event => {
            event.accepted = true;
            if (root.modifierKeys.indexOf(event.key) >= 0)
                root.held = "";
        }
    }

    Panel {
        anchors.centerIn: parent
        width: 420
        height: 152
        color: Tokens.card
        border.color: Tokens.accentDim

        Column {
            anchors.centerIn: parent
            spacing: 14

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.prompt.toUpperCase()
                color: Tokens.textDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsLabel
                font.letterSpacing: 2
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.held === "" ? "—" : root.held
                color: root.held === "" ? Tokens.textFaint : Tokens.accent
                font.family: Tokens.mono
                font.pixelSize: 22
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Escape cancels")
                color: Tokens.textFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsMicro
            }
        }
    }
}
