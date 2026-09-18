// GENESI — the desktop's menu and the widget editor, drawn above everything
// else on the wallpaper.
//
// ── Why this is not part of the widget layer ────────────────────────────────
//
// Background.qml stacks five things: the wallpaper, the visualiser, the Genesi
// widgets, caelestia's clock, and the Depth cutout -- the wallpaper's subject,
// cut out and drawn in FRONT so windows and widgets sit behind the person in
// the picture. That is the whole point of Depth, and it also means anything
// inside the widget layer is behind it. The menu was: right-clicking the
// desktop on a wallpaper with a subject opened a menu with a shoulder across
// it. So the menu and the editor moved out here, into an item that is added
// after the cutout, and they ask each other for things through
// GenesiWidgetEditState.
//
// ── The safe area ──────────────────────────────────────────────────────────
//
// The other half of the same bug. caelestia's drawers window takes input on a
// margin around the screen -- eighty pixels on an empty desktop, which is when
// people right-click it -- and it sits above this one. A card drawn under that
// margin is perfectly visible and takes no clicks: the third of three colour
// buttons, sitting eighty pixels from the right edge, simply did not respond.
// So both surfaces open inside GenesiEdges' ring, not inside the screen.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.launcher

Item {
    id: root

    anchors.fill: parent

    // Where a card may actually be put and still be clicked.
    readonly property real safeLeft: GenesiEdges.ringLeft + 8
    readonly property real safeTop: GenesiEdges.ringTop + 8
    readonly property real safeRight: root.width - GenesiEdges.ringRight - 8
    readonly property real safeBottom: root.height - GenesiEdges.ringBottom - 8

    function place(w: real, h: real, x: real, y: real): point {
        // Math.min first, then Math.max: on a screen too small for the card
        // the top-left corner wins, which is the one a person can reach.
        return Qt.point(Math.max(root.safeLeft, Math.min(x, root.safeRight - w)), Math.max(root.safeTop, Math.min(y, root.safeBottom - h)));
    }

    // Both signals are heard by every screen's overlay, so each one checks the
    // item it was handed is on ITS window before opening anything.
    function mine(item: Item): bool {
        return !!item && item.Window.window === root.Window.window;
    }

    Connections {
        target: GenesiWidgetEditState

        function onMenuRequested(item: Item, x: real, y: real): void {
            if (!root.mine(item))
                return;
            const p = item.mapToItem(root, x, y);
            menu.openAt(p.x, p.y);
        }

        function onRequested(name: string, item: Item, x: real, y: real): void {
            if (!root.mine(item))
                return;
            // caelestia's clock is drawn above this layer too, so an editor
            // opened at the pointer would be half under it. Beside it instead.
            if (name === "desktopClock") {
                const r = item.mapToItem(root, 0, 0, item.width, item.height);
                editor.openBeside(name, r);
                return;
            }
            const p = item.mapToItem(root, x, y);
            editor.openFor(name, p.x, p.y);
        }
    }

    GenesiDesktopMenu {
        id: menu

        defs: GenesiWidgetEditState.defs
        arranging: GenesiWidgetEditState.arranging
        onToggle: name => {
            const c = Config.background.widgets[name];
            Quickshell.execDetached(["genesi-center-set", "caelestia", `background.widgets.${name}.enabled`, c && c.enabled ? "false" : "true"]);
        }
        onArrange: GenesiWidgetEditState.askArrange(root)
        onSchemes: GenesiSchemeState.show()
        place: (w, h, x, y) => root.place(w, h, x, y)
    }

    GenesiWidgetEditor {
        id: editor

        labels: menu.labels
        defs: GenesiWidgetEditState.defs
        onArrangeRequested: GenesiWidgetEditState.askArrange(root)
        place: (w, h, x, y) => root.place(w, h, x, y)
    }
}
