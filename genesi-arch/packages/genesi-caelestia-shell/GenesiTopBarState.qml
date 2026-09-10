// GENESI — is the shell studio open, and on which page?
//
// The same small singleton as GenesiSchemeState, and for the same reason:
// the bar ASKS for the studio and a separate layer-shell surface ANSWERS,
// and two windows cannot reach into each other's item trees.
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

    // Which page the studio is on. Kept here rather than in the studio so that
    // closing and reopening comes back to where you were -- adjusting a shell
    // is a loop of change, look, change again, and a panel that resets to its
    // first page every time makes that loop longer than the change itself.
    // The front door, on a shell that has never opened this. Seven pages
    // and a hundred and eighty rows is more than a rail can answer for, and
    // a map nobody is ever shown is not a map.
    property string section: "home"

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
