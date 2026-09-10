// GENESI — is the full-screen scheme picker open?
//
// One boolean, in a singleton, because the two halves of that question live in
// different windows: the launcher (and the desktop menu) ASK for it, and a
// layer-shell surface of its own ANSWERS. Neither can reach the other's item
// tree, and a singleton is how Quickshell shells talk across windows.
//
// It carries nothing else on purpose. The list of schemes is already a
// singleton upstream (Schemes), the colours are already a singleton
// (Colours) -- a second copy of either here would be a second thing to keep
// in step.
pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool open: false

    // What was typed into the picker's own field. Kept here rather than in the
    // window so that closing and reopening starts clean without the window
    // needing to remember to clear it.
    property string filter: ""

    function show(): void {
        root.filter = "";
        root.open = true;
    }

    function hide(): void {
        root.open = false;
    }

    function toggle(): void {
        if (root.open)
            root.hide();
        else
            root.show();
    }
}
