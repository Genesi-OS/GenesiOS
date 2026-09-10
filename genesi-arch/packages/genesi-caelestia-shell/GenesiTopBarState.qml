// GENESI — is the top bar's own settings panel open?
//
// The same one-boolean singleton as GenesiSchemeState, and for the same
// reason: the bar ASKS for the panel and a separate layer-shell surface
// ANSWERS, and two windows cannot reach into each other's item trees.
//
// It lives beside the launcher's body rather than beside the bar because that
// directory is already a module both halves import. Putting a second singleton
// directory next to it would be a second place to look for the same kind of
// thing.
pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool open: false

    // Which group of settings the panel is showing. Kept here rather than in
    // the panel so that closing and reopening comes back to where you were --
    // adjusting a bar is a loop of change, look, change again, and a panel
    // that resets to its first tab every time makes that loop longer than the
    // change.
    property string section: "shape"

    function show(): void {
        root.open = true;
    }

    function hide(): void {
        root.open = false;
    }

    function toggle(): void {
        root.open = !root.open;
    }
}
