/*
 * ShortcutsPage — every key the compositor is currently listening for.
 *
 * Read from `hyprctl binds`, not from parsing hyprland.conf. The conf is one of
 * several sources -- ours, the user's, anything either of them sources -- and
 * what is BOUND is the only answer that is true. It also means a bind someone
 * added by hand shows up here without this page having to know where it was
 * written.
 *
 * Editable, WITHOUT touching hyprland.conf. Rebinding writes an `unbind` for
 * the old combination and a `bind` for the new one into the Genesi drop-in
 * that the config sources last -- so the shipped shortcut is taken out of the
 * way and ours replaces it, and the user's own file keeps its shape, its
 * comments and its order. A shortcuts editor that rewrites somebody's
 * hyprland.conf is one they stop trusting after the first time it reformats a
 * section they care about.
 *
 * A row we moved says so and offers to put it back. That matters more here
 * than anywhere else in the app: a shortcut you changed and cannot restore is
 * a keyboard you have to repair by hand.
 *
 * The search box is still the thing that makes a hundred binds usable, which
 * is the other problem people have here: not changing a key, but finding the
 * one they forgot.
 */
import QtQuick
import "../components"
import ".."

Item {
    id: page

    property var backend: null
    property var d: ({})
    property string filter: ""

    readonly property bool ready: page.d.available === true

    // The bind being rebound, while the capture is up.
    property var editing: null

    // "SUPER SHIFT,Q" for a bind, which is how genesi-center-set names one.
    function comboOf(b) {
        return b.mods.join(" ") + "," + b.key;
    }

    // Overrides, keyed by the ORIGINAL combination -- which is what the
    // drop-in records, because that is the one that has to be unbound.
    readonly property var overridden: {
        const out = {};
        for (const o of (page.d.overrides || [])) {
            const k = o.original.mods.join(" ") + "," + o.original.key;
            out[k] = o;
        }
        return out;
    }

    function rebind(bind, mods, key) {
        if (!page.backend)
            return;
        page.backend.act(["genesi-center-set", "bind", page.comboOf(bind),
                          mods.join(" ") + "," + key,
                          bind.dispatcher, bind.arg], "shortcuts");
    }

    function reset(bind) {
        if (page.backend)
            page.backend.act(["genesi-center-set", "unbind",
                              page.comboOf(bind)], "shortcuts");
    }

    // What a bind DOES, in words, for the dispatchers Genesi actually ships.
    // An unknown dispatcher falls through to its own name -- honest, and it
    // still tells you more than the key alone.
    readonly property var says: ({
        "exec": qsTr("run"),
        "killactive": qsTr("close the focused window"),
        "togglefloating": qsTr("float or tile the window"),
        "fullscreen": qsTr("fullscreen"),
        "workspace": qsTr("go to workspace"),
        "movetoworkspace": qsTr("send the window to workspace"),
        "movefocus": qsTr("move focus"),
        "movewindow": qsTr("move the window"),
        "resizeactive": qsTr("resize the window"),
        "togglesplit": qsTr("flip the split"),
        "layoutmsg": qsTr("layout"),
        "exit": qsTr("leave the session"),
        "pseudo": qsTr("pseudo-tile")
    })

    readonly property var shown: {
        const q = page.filter.trim().toLowerCase();
        const all = page.d.binds || [];
        if (q === "")
            return all;
        return all.filter(b => {
            const hay = (b.mods.join(" ") + " " + b.key + " " + b.dispatcher
                         + " " + b.arg + " " + b.description).toLowerCase();
            return hay.indexOf(q) >= 0;
        });
    }

    Connections {
        target: page.backend
        ignoreUnknownSignals: true
        function onSectionReady(name, payload) {
            if (name !== "shortcuts")
                return;
            try {
                page.d = JSON.parse(payload);
            } catch (e) {}
        }
    }

    Component.onCompleted: if (page.backend) page.backend.ask("shortcuts")

    PageFrame {
        anchors.fill: parent
        index: "03"
        group: qsTr("Desktop")
        title: qsTr("Shortcuts")
        blurb: qsTr("Every key combination Hyprland is listening for right now — "
                    + "the ones Genesi ships and any you added yourself, because "
                    + "this is read from the compositor rather than from a file.")
        note: page.ready
              ? (page.filter === ""
                 ? qsTr("%1 shortcut(s)").arg((page.d.binds || []).length)
                 : qsTr("%1 of %2 shortcut(s)").arg(page.shown.length)
                                               .arg((page.d.binds || []).length))
              : qsTr("no Hyprland session — nothing to list")
        noteWarn: !page.ready

        Rectangle {
            width: parent.width
            height: 34
            radius: Tokens.radiusSm
            color: Tokens.card
            border.width: 1
            border.color: search.activeFocus ? Tokens.accentDim : Tokens.line
            visible: page.ready
            Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 12
                text: "/"
                color: Tokens.accentDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsLabel
            }

            TextInput {
                id: search
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 30; rightMargin: 12
                }
                color: Tokens.textHi
                font.family: Tokens.mono
                font.pixelSize: Tokens.fsBody
                selectionColor: Tokens.accentDeep
                selectedTextColor: Tokens.textHi
                clip: true
                onTextChanged: page.filter = text

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text === ""
                    text: qsTr("Filter by key, mod or what it does…")
                    color: Tokens.textFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsBody
                }
            }
        }

        Panel {
            width: parent.width
            height: bindCol.implicitHeight + 20
            visible: page.ready

            Column {
                id: bindCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 10
                spacing: 0

                Repeater {
                    model: page.shown
                    delegate: Item {
                        id: bindRow
                        required property var modelData
                        required property int index

                        readonly property bool moved:
                            page.overridden[page.comboOf(modelData)] !== undefined

                        width: bindCol.width
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            color: bindRow.moved
                                   ? Tokens.accentDeep
                                   : (bindRow.index % 2 === 0 ? "transparent"
                                                              : Tokens.cardHi)
                            opacity: bindRow.moved ? 0.35 : 0.5
                        }

                        Row {
                            id: keys
                            anchors {
                                left: parent.left; verticalCenter: parent.verticalCenter
                                leftMargin: 8
                            }
                            spacing: 4

                            Repeater {
                                model: bindRow.modelData.mods.concat([bindRow.modelData.key])
                                delegate: Rectangle {
                                    required property var modelData

                                    width: cap.implicitWidth + 12
                                    height: 20
                                    radius: 4
                                    color: Tokens.bg
                                    border.width: 1
                                    border.color: Tokens.line

                                    Text {
                                        id: cap
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Tokens.text
                                        font.family: Tokens.mono
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        Text {
                            id: what
                            anchors {
                                left: keys.right; right: actions.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 16; rightMargin: 10
                            }
                            // The description Hyprland carries wins when there
                            // is one -- it is what whoever wrote the bind meant.
                            text: bindRow.modelData.description !== ""
                                  ? bindRow.modelData.description
                                  : ((page.says[bindRow.modelData.dispatcher]
                                      || bindRow.modelData.dispatcher)
                                     + (bindRow.modelData.arg !== ""
                                        ? "  " + bindRow.modelData.arg : ""))
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Row {
                            id: actions
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                rightMargin: 8
                            }
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: bindRow.moved
                                text: qsTr("MOVED")
                                color: Tokens.accent
                                font.family: Tokens.mono
                                font.pixelSize: 8
                                font.letterSpacing: 1
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: bindRow.moved
                                width: 56; height: 20; radius: 4
                                color: resetHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: resetHov.hovered ? Tokens.accentDim
                                                               : Tokens.line
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("RESET")
                                    color: Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 8
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: resetHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: page.reset(bindRow.modelData) }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                // Shown on hover only: a REBIND button on every
                                // one of a hundred rows is a wall of buttons.
                                opacity: rowHov.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Tokens.quick } }
                                width: 66; height: 20; radius: 4
                                color: rebindHov.hovered ? Tokens.cardHi : "transparent"
                                border.width: 1
                                border.color: rebindHov.hovered ? Tokens.accentDim
                                                                : Tokens.line
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("REBIND")
                                    color: rebindHov.hovered ? Tokens.textHi : Tokens.textDim
                                    font.family: Tokens.mono
                                    font.pixelSize: 8
                                    font.letterSpacing: 1
                                }
                                HoverHandler { id: rebindHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        page.editing = bindRow.modelData;
                                        capture.start();
                                    }
                                }
                            }
                        }

                        HoverHandler { id: rowHov }
                    }
                }

                Item {
                    width: bindCol.width
                    height: page.shown.length === 0 ? 60 : 0
                    visible: page.shown.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("nothing matches “%1”").arg(page.filter)
                        color: Tokens.textDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsLabel
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: page.ready
            text: qsTr("Read from the compositor, so this is what is bound right "
                       + "now. Rebinding writes to a Genesi file your config "
                       + "pulls in — your hyprland.conf is never rewritten, and "
                       + "RESET puts the shipped shortcut back.")
            color: Tokens.textDim
            font.family: Tokens.sans
            font.pixelSize: 11
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
    }

    KeyCapture {
        id: capture
        prompt: page.editing
                ? qsTr("new shortcut for “%1”")
                  .arg(page.says[page.editing.dispatcher]
                       || page.editing.dispatcher)
                : qsTr("press a combination")

        onCaptured: (mods, key) => {
            if (page.editing)
                page.rebind(page.editing, mods, key);
            page.editing = null;
        }
        onCancelled: page.editing = null
    }
}
