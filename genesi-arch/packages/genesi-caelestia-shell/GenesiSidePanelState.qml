// GENESI — is the side panel open?
//
// The same small singleton as GenesiTopBarState and GenesiSchemeState, and for
// the same reason: the bar's mark ASKS for the panel, the left edge of the
// screen asks for it too, and a separate layer-shell surface ANSWERS. Three
// windows cannot reach into each other's item trees.
//
// It lives beside the launcher's body because that directory is already a
// module every half of this imports. A second singleton directory next to it
// would be a second place to look for the same kind of thing.
pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool open: false

    // `pinned` is what the pointer leaving the panel is allowed to close. A
    // panel opened by hovering the screen edge closes when you leave it; one
    // opened by clicking the mark stays until it is dismissed, because a
    // panel you asked for by name should not vanish while you reach for a
    // slider in it.
    property bool pinned: false

    function show(): void {
        root.open = true;
    }

    function peek(): void {
        if (!root.open) {
            root.pinned = false;
            root.open = true;
        }
    }

    function hide(): void {
        root.open = false;
        root.pinned = false;
    }

    function toggle(): void {
        if (root.open) {
            root.hide();
            return;
        }
        root.open = true;
        root.pinned = true;
    }
}
