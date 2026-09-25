// GENESI — how the Plugins page talks to the plugins, inside the shell.
//
// The page and every plugin live in the same Quickshell process, and the page
// used to reach them the long way round: spawn `caelestia shell <target> ...`,
// which spawns `qs ipc call`, which comes back into this process. Three hops,
// each of which can fail with nobody told -- the Retrospective's buttons were
// reported, twice, as doing nothing at all, and not even the toast its own
// failure path shows ever appeared.
//
// So a button on the page raises a signal here and the plugin that owns the
// thing answers it. The IPC targets stay, for the terminal and for keybinds.
//
// Installed into modules/launcher with Genesi's other singletons and reached
// as `Launcher.GenesiPluginBus` -- from the plugins in modules/background
// too, because Quickshell hands out a directory's singletons through its
// module, never by proximity.
pragma Singleton

import Quickshell

Singleton {
    // "week" or "month".
    signal wrappedRequested(span: string)
}
