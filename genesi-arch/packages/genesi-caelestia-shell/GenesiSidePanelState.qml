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

    // Which face the panel is showing: "quick" for the switches and sliders,
    // "depth" for the wallpaper cut-out. A page rather than a second window
    // because they are the same panel -- the rail down its left side is how
    // you get between them, and a panel that closed and reopened somewhere
    // else would not read as one thing.
    property string page: "quick"

    // Not `open()`. There is a property called `open` on this object, and a
    // function of the same name is a second thing answering to one word --
    // which QML resolves quietly and in nobody's favour.
    function openPage(what: string): void {
        root.page = what;
        root.open = true;
        root.pinned = true;
    }

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
        // Back to the switches. The quick settings are what the mark is for;
        // coming back to a settings page you visited once is a panel that
        // has forgotten what it is.
        root.page = "quick";
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
