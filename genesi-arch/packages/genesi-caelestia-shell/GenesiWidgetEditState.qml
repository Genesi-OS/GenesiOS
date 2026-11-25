// GENESI — who asked for the widget editor, and what it is previewing.
//
// A singleton beside the other Genesi state, because two unrelated files have
// to reach one editor: a Genesi widget's own host, and caelestia's desktop
// clock, which Genesi patches so a right-click on it opens the same editor.
// Neither can see the widget layer's items; both can see this.
//
// ── Preview ─────────────────────────────────────────────────────────────────
//
// A slider that wrote to shell.json on every step would start a process per
// pixel of drag, and the widget would lag a write and a config reload behind
// the thumb. So while the editor is open, what it is showing is held HERE, and
// the card and the host read it ahead of the config: the widget follows the
// thumb at once, and the value is written when the thumb is let go.
pragma Singleton

import QtQuick

QtObject {
    id: root

    // (name, item, x, y) -- `item` is whatever was right-clicked, so each
    // screen's widget layer can tell whether the click happened on its window.
    signal requested(string name, Item item, real x, real y)

    // ── The desktop menu, and arrange mode ──────────────────────────────────
    //
    // Both cross the same gap, in the other direction. The menu and the editor
    // are drawn ABOVE the depth cutout now -- they were behind it, which on a
    // wallpaper with a subject meant right-clicking the desktop opened a menu
    // half hidden by a person's shoulder -- and the layer that draws them is a
    // separate item in Background.qml, after GenesiDepth. So the widget layer
    // asks for the menu, the overlay opens it; the overlay asks for arrange
    // mode, the widget layer enters it. Each side checks the item it is handed
    // belongs to its own screen before answering.
    signal menuRequested(Item item, real x, real y)
    signal arrangeAsked(Item item)

    // Set by the widget layer, read by the menu, which lives in the other one.
    property bool arranging: false

    // The widgets themselves: name, and the corner each prefers when the
    // config says nothing. Here rather than in the layer because the menu, the
    // editor and the layer are three files now, and a list that lives in one
    // of them is a list the other two have to be handed.
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
        },
        {
            name: "digitalClock",
            home: "top-centre"
        }
    ]

    function askMenu(item: Item, x: real, y: real): void {
        root.menuRequested(item, x, y);
    }

    function askArrange(item: Item): void {
        root.arrangeAsked(item);
    }

    // name -> { key: value } while the editor is open.
    property var preview: ({})

    function request(name: string, item: Item, x: real, y: real): void {
        root.requested(name, item, x, y);
    }

    function set(name: string, key: string, value: var): void {
        const next = {};
        for (const n in root.preview)
            next[n] = root.preview[n];
        const one = {};
        for (const k in (next[name] || {}))
            one[k] = next[name][k];
        one[key] = value;
        next[name] = one;
        root.preview = next;
    }

    // The previewed value, or the fallback (the config's) when there is none.
    function valueOf(name: string, key: string, fallback: var): var {
        const p = root.preview[name];
        return p && p[key] !== undefined ? p[key] : fallback;
    }

    function clear(): void {
        root.preview = ({});
    }
}
