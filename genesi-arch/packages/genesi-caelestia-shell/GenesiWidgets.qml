// GENESI — the things drawn on the wallpaper, and the menu that manages them.
//
// caelestia ships two: a clock and an audio visualiser. This is the layer that
// holds the rest, and it does four jobs -- decide what is on, decide where it
// goes, stack whatever lands in the same corner, and let a right-click on the
// desktop change any of that without opening an app.
//
// ── Adding a widget is two lines and a file ─────────────────────────────────
//
// One entry in `defs` and one GenesiWidget<Name>.qml beside this file. The name
// is the config key, the file name and the id, so a widget cannot exist in one
// of those places and not the others. The Loader builds it by NAME rather than
// through a switch over fourteen Components, because a switch is a fifteenth
// place to forget.
//
// ── Nine anchors, or anywhere ───────────────────────────────────────────────
//
// A widget sits in one of nine named corners, and everything that lands in one
// corner goes in a COLUMN -- without that, turning on the second widget draws
// it exactly on top of the first and nine anchors behave like nine slots.
//
// Or it is dragged, and then its position is "free" and it remembers where it
// was dropped as a FRACTION of the screen. Fractions because the config
// outlives the monitor: a widget dropped at x=1700 on a 1920 screen is off the
// edge of a 1366 one.
//
// ── Writing goes through genesi-center-set ──────────────────────────────────
//
// The menu does not edit shell.json. It shells out to the same writer Genesi
// Center uses, which validates the key and the value and owns the file format.
// Two programs writing one JSON file by two sets of rules is how a config ends
// up with a key that only one of them understands.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

    // Arrange mode. While it is on, every widget can be dragged and says so;
    // while it is off, nothing on the wallpaper is draggable, because a desktop
    // whose contents move when you brush past them is a desktop you stop
    // putting things on.
    property bool arranging: false

    // Where each anchored widget WAS when arrange mode started, in pixels.
    //
    // This is what lets every widget be dragged directly instead of being
    // unpinned first. A widget in a corner lives inside a Column, and a Column
    // sets the x and y of everything in it -- a drag handler writing the same
    // properties is two things assigning one value every frame, which does not
    // look like dragging, it looks like vibrating.
    //
    // So arrange mode moves ALL of them into the free layer at once. Their
    // positions are read off the screen first, so nothing jumps: the widget you
    // grab is exactly where it was a moment ago.
    property var placed: ({})

    function beginArrange(): void {
        const map = {};
        for (const slot of [tl, tc, tr, ml, cc, mr, bl, bc, br]) {
            for (const child of slot.children) {
                // The Repeater is a child of the Column too, and it is not a
                // widget. `widget` is what tells them apart.
                if (!child.widget)
                    continue;
                const p = child.mapToItem(root, 0, 0);
                map[child.widget] = {
                    "x": p.x,
                    "y": p.y
                };
            }
        }
        root.placed = map;
        root.arranging = true;
    }

    function endArrange(): void {
        root.arranging = false;
        root.placed = ({});
    }

    function cfgOf(name: string): var {
        return Config.background.widgets[name];
    }

    function write(name: string, leaf: string, value: string): void {
        // The same writer Genesi Center uses. It validates the key and the
        // value; this does not want a second opinion about either.
        Quickshell.execDetached(["genesi-center-set", "caelestia",
                                 `background.widgets.${name}.${leaf}`, value]);
    }

    // The names enabled at one anchor, in the order `defs` lists them. Reading
    // `enabled` and `position` here is what makes the callers' bindings track
    // them: a binding follows every notifiable property read while it runs,
    // including the ones read inside a function it called.
    function at(anchor: string): var {
        // Nothing is anchored while arranging: they are all in the free layer,
        // where they can be dragged without fighting a positioner.
        if (root.arranging)
            return [];
        const out = [];
        for (const d of root.defs) {
            const c = root.cfgOf(d.name);
            if (c && c.enabled && (c.position || d.home) === anchor)
                out.push(d.name);
        }
        return out;
    }

    function floating(): var {
        const out = [];
        for (const d of root.defs) {
            const c = root.cfgOf(d.name);
            if (!c || !c.enabled)
                continue;
            if (root.arranging || c.position === "free")
                out.push(d.name);
        }
        return out;
    }

    // ── Right-click anywhere on the wallpaper ────────────────────────────────
    //
    // RightButton only. Accepting every button would swallow the left click as
    // well, and this window covers the whole screen -- the desktop would stop
    // responding to anything else that ever wants a click there.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => menu.openAt(event.x, event.y)
    }

    // ── The nine ─────────────────────────────────────────────────────────────
    Slot {
        id: tl

        anchorName: "top-left"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: root.margin
    }
    Slot {
        id: tc

        anchorName: "top-centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.margin
    }
    Slot {
        id: tr

        anchorName: "top-right"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.margin
    }
    Slot {
        id: ml

        anchorName: "mid-left"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.margin
    }
    Slot {
        id: cc

        anchorName: "centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }
    Slot {
        id: mr

        anchorName: "mid-right"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: root.margin
    }
    Slot {
        id: bl

        anchorName: "bottom-left"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.margin
    }
    Slot {
        id: bc

        anchorName: "bottom-centre"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.margin
    }
    Slot {
        id: br

        anchorName: "bottom-right"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.margin
    }

    // ── And the dragged ones ─────────────────────────────────────────────────
    Repeater {
        model: root.floating()

        Item {
            id: floater

            required property string modelData

            readonly property var cfg: root.cfgOf(floater.modelData)

            width: body.implicitWidth * body.scale
            height: body.implicitHeight * body.scale

            // Where it already was if arrange mode just moved it here, and its
            // stored fraction otherwise. Without the first case, entering
            // arrange mode piles every anchored widget into one corner.
            x: root.placed[floater.modelData] !== undefined ? root.placed[floater.modelData].x : (floater.cfg?.x ?? 0.05) * root.width
            y: root.placed[floater.modelData] !== undefined ? root.placed[floater.modelData].y : (floater.cfg?.y ?? 0.05) * root.height

            GenesiWidgetHost {
                id: body

                widget: floater.modelData
                corner: "top-left"
                arranging: root.arranging

                // Dropped, so remember where -- and that it is placed by hand
                // now, which is what `free` means. A widget dragged out of a
                // corner that stayed "top-left" in the config would snap back
                // there on the next reload and nowhere else.
                //
                // The x and y bindings are NOT restored: the drag wrote them
                // imperatively, and leaving arrange mode rebuilds this item
                // from the model anyway, with fresh ones.
                onDropped: {
                    const fx = Math.max(0, Math.min(0.98, floater.x / root.width));
                    const fy = Math.max(0, Math.min(0.98, floater.y / root.height));
                    root.write(floater.modelData, "x", fx.toFixed(4));
                    root.write(floater.modelData, "y", fy.toFixed(4));
                    root.write(floater.modelData, "position", "free");
                }
                dragTarget: floater
            }
        }
    }

    GenesiDesktopMenu {
        id: menu

        defs: root.defs
        onToggle: name => {
            const c = root.cfgOf(name);
            root.write(name, "enabled", c && c.enabled ? "false" : "true");
        }
        onArrange: root.arranging ? root.endArrange() : root.beginArrange()
        arranging: root.arranging
    }

    component Slot: Column {
        id: slot

        required property string anchorName

        spacing: root.gap

        Repeater {
            model: root.at(slot.anchorName)

            GenesiWidgetHost {
                required property string modelData

                widget: modelData
                corner: slot.anchorName
                arranging: root.arranging

            }
        }
    }
}
