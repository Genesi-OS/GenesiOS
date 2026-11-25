// GENESI — is a plugin turned on?
//
// A plugin is a part of this shell that ships with it and stays OFF until
// somebody turns it on from the Plugins shelf of Genesi Store. Turning it on
// is the store writing one small file,
//
//     ~/.config/genesi/plugins/<id>.json      {"enabled": true}
//
// and turning it off is the store deleting it again -- which is exactly what
// the store's `file` action and its revert already do, so a plugin needed no
// new power in the store: an item is still data, and the code it switches on
// is code this signed package already carries.
//
// ── Polled, not watched ───────────────────────────────────────────────────
//
// FileView's watcher is a QFileSystemWatcher, and that cannot watch a file
// that does not exist yet -- which is the state of every plugin before it is
// switched on. Watching would notice a plugin being turned OFF and never one
// being turned ON until the next login. Reading a file of fifteen bytes every
// few seconds costs nothing, and it makes the switch in the store take effect
// while the store is still open.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property string plugin

    // Not `on`: that word is QML's own (`Behavior on x`), and a property
    // named after a keyword is one more thing to be surprised by.
    property bool active: false

    readonly property string dir: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/genesi/plugins`

    FileView {
        id: flag

        path: `${root.dir}/${root.plugin}.json`
        printErrors: false
        onLoaded: {
            try {
                root.active = JSON.parse(text()).enabled === true;
            } catch (e) {
                root.active = false;
            }
        }
        onLoadFailed: root.active = false
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: flag.reload()
    }
}
