// Tells genesi-plugins which app has focus, for the Retrospective's tally of
// where the week went. Plasma does not offer the focused window to other
// processes, so KWin reports it: the window's resource class (the same name
// Hyprland calls `class`), and only that -- no titles, no contents.
function report(window) {
    callDBus("org.genesi.plugins", "/Active", "org.genesi.plugins", "setActive",
             window ? (window.resourceClass || "") : "");
}
workspace.windowActivated.connect(report);
report(workspace.activeWindow);
