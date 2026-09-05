/*
 * ShortcutsPage — every key the compositor is currently listening for.
 *
 * Read from `hyprctl binds`, not from parsing hyprland.conf. The conf is one of
 * several sources -- ours, the user's, anything either of them sources -- and
 * what is BOUND is the only answer that is true. It also means a bind someone
 * added by hand shows up here without this page having to know where it was
 * written.
 *
 * Read-only, and that is a decision rather than a gap. Writing a bind means
 * editing a config file whose shape this app does not own, and a shortcuts
 * editor that silently drops the comment structure of someone's hyprland.conf
 * is worse than a list they can read. The search box is what makes a list of a
 * hundred binds usable, which is the actual problem people have here: not
 * changing a key, but finding the one they forgot.
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

                        width: bindCol.width
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            color: bindRow.index % 2 === 0 ? "transparent" : Tokens.cardHi
                            opacity: 0.5
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
                            anchors {
                                left: keys.right; right: parent.right
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
                       + "now. Changing a shortcut means editing your Hyprland "
                       + "config — this page will not rewrite it, because it does "
                       + "not own the shape of that file.")
            color: Tokens.textDim
            font.family: Tokens.sans
            font.pixelSize: 11
            lineHeight: 1.4
            wrapMode: Text.WordWrap
        }
    }
}
