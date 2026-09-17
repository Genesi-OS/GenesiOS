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
