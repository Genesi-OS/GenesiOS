// GENESI — the things drawn on the wallpaper.
//
// caelestia ships two: a clock and an audio visualiser. This is the layer that
// holds the rest, and it does three jobs and no more -- decide what is on,
// decide where it goes, and stack whatever lands in the same corner.
//
// ── Adding a widget is two lines and a file ─────────────────────────────────
//
// One entry in `defs` and one GenesiWidget<Name>.qml beside this file. The name
// is the config key, the file name and the id, so a widget cannot exist in one
// of those places and not the others. The Loader builds it by NAME rather than
// through a switch over fourteen Components, because a switch is a fifteenth
// place to forget.
//
// ── Nine anchors, and why they stack ────────────────────────────────────────
//
// Free coordinates would want a drag surface, and a widget dragged half off a
// screen is invisible with no way back except editing JSON. So: nine named
// corners, the same vocabulary upstream's desktopClock uses.
//
// Everything that lands in one corner goes in a COLUMN. Without that, turning
// on the second widget draws it exactly on top of the first, and nine anchors
// behave like nine slots -- which is the version of this that feels broken.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components

Item {
    id: root

    // name -> the corner it prefers when the config says nothing. Kept here
    // rather than in the C++ config because it is a layout decision, and
    // because CONFIG_PROPERTY puts its member behind `private:`, so a subclass
    // per widget could not have carried one anyway.
    readonly property var defs: [
        {
            name: "weather",
            home: "top-right"
        },
        {
            name: "forecast",
            home: "top-right"
        },
        {
            name: "media",
            home: "bottom-left"
        },
        {
            name: "cpu",
            home: "top-left"
        },
        {
            name: "memory",
            home: "top-left"
        },
        {
            name: "storage",
            home: "top-left"
        },
        {
            name: "network",
            home: "bottom-right"
        },
        {
            name: "battery",
            home: "top-right"
        },
        {
            name: "calendar",
            home: "bottom-right"
        },
        {
            name: "analogClock",
            home: "top-centre"
        },
        {
            name: "workspaces",
            home: "bottom-centre"
        },
        {
            name: "notifications",
            home: "bottom-right"
        },
        {
            name: "uptime",
            home: "bottom-left"
        },
        {
            name: "greeting",
            home: "top-centre"
        }
    ]

    readonly property int margin: Tokens.padding.extraLargeIncreased + Config.border.thickness
    readonly property int gap: Tokens.spacing.large

    // The names enabled at one anchor, in the order `defs` lists them. Reading
    // `enabled` and `position` here is what makes the callers' bindings track
    // them: a binding follows every notifiable property read while it runs,
    // including the ones read inside a function it called.
    function at(anchor: string): var {
        const out = [];
        for (const d of root.defs) {
            const c = Config.background.widgets[d.name];
            if (c && c.enabled && (c.position || d.home) === anchor)
                out.push(d.name);
        }
        return out;
    }

    // ── The nine ─────────────────────────────────────────────────────────────
    Slot {
        anchorName: "top-left"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: root.margin
    }
    Slot {
        anchorName: "top-centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.margin
    }
    Slot {
        anchorName: "top-right"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.margin
    }
    Slot {
        anchorName: "mid-left"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.margin
    }
    Slot {
        anchorName: "centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }
    Slot {
        anchorName: "mid-right"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: root.margin
    }
    Slot {
        anchorName: "bottom-left"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.margin
    }
    Slot {
        anchorName: "bottom-centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.margin
    }
    Slot {
        anchorName: "bottom-right"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.margin
    }

    component Slot: Column {
        id: slot

        required property string anchorName

        spacing: root.gap

        Repeater {
            model: root.at(slot.anchorName)

            Loader {
                id: holder

                required property string modelData

                readonly property var cfg: Config.background.widgets[holder.modelData]

                // Built by name. The file, the config key and this string are
                // one identifier, so a widget that exists is reachable and one
                // that is not fails visibly at its own Loader instead of
                // quietly not being drawn.
                source: Qt.resolvedUrl("GenesiWidget" + holder.modelData.charAt(0).toUpperCase() + holder.modelData.slice(1) + ".qml")
                asynchronous: true

                // Scale from the corner the widget is anchored to, so growing
                // one does not push it off the edge of the screen it sits in.
                transformOrigin: {
                    const a = slot.anchorName;
                    if (a === "top-left")
                        return Item.TopLeft;
                    if (a === "top-centre")
                        return Item.Top;
                    if (a === "top-right")
                        return Item.TopRight;
                    if (a === "mid-left")
                        return Item.Left;
                    if (a === "mid-right")
                        return Item.Right;
                    if (a === "bottom-left")
                        return Item.BottomLeft;
                    if (a === "bottom-centre")
                        return Item.Bottom;
                    if (a === "bottom-right")
                        return Item.BottomRight;
                    return Item.Center;
                }
                scale: Math.max(0.5, Math.min(2, holder.cfg?.scale ?? 1))

                opacity: status === Loader.Ready ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }
            }
        }
    }
}
