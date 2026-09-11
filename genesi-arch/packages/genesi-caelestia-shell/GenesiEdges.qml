// GENESI — which screen edges a Genesi surface owns, and how much of them.
//
// ── The bug this exists to answer ──────────────────────────────────────────
//
// caelestia's drawers window covers the whole screen and takes input on a
// FRAME around it: the border, plus a drag margin so a panel can be pulled in
// from its edge. That margin is not small. Regions.qml sizes it as the largest
// dragThreshold of the four panels
//
//     max(dashboard 50, launcher 50, session 30, sidebar 80)
//
// and applies it on all four edges whenever the active workspace has no
// windows on it -- so the top and bottom NINETY pixels of an empty desktop
// belong to the drawers window.
//
// The Genesi top bar is 46 pixels tall and the dock about 76. Both sit
// entirely inside that strip, and on a freshly logged-in session -- nothing
// open, which is every login and every reboot -- neither received a click.
//
// ── What reads this, and why it is one file ───────────────────────────────
//
// Four things need to know how tall the bar is:
//
//   * the bar itself, to size its own window
//   * Regions.qml, to stop claiming that strip for input
//   * Exclusions.qml, so caelestia's border stops reserving the same edge the
//     bar reserves -- that is what pushed the bar ten pixels down into the
//     border on every cold start
//   * Panels.qml, so the dashboard, the launcher and the notifications open
//     BELOW the bar instead of underneath it
//
// The first version of this answered only yes or no, to avoid writing the
// bar's height in two places. Four callers later that is no longer the choice
// on offer: the number exists, and the question is whether there is one
// expression for it or four. `stripFor()` is the expression, and everything
// calls it -- the bar with its own per-screen config, the three upstream files
// through `top` and `bottom`.
//
// GlobalConfig rather than the per-screen attached Config: this is a
// singleton, so there is no screen to attach to. The surfaces it reports on
// are configured once for the whole session, and a per-screen override of
// topbar.height is not a thing Genesi offers.
pragma Singleton

import Quickshell
import Caelestia.Config

Singleton {
    id: root

    // How much of an edge the bar occupies, given a topbar config. The one
    // expression; `fit` is the only form that floats, so it is the only one
    // that pays for a gap on both sides.
    function stripFor(cfg): real {
        if (!cfg.enabled)
            return 0;
        // `margin` is the distance from the screen edge; `gap` is the space
        // around the islands inside the strip. Both are part of how much of
        // the screen the bar occupies, and everything that lays out around it
        // -- the exclusion zone, caelestia's panels, its input regions --
        // wants that one number.
        if (cfg.form === "fit")
            return cfg.height + cfg.gap * 2 + cfg.margin;
        if (cfg.form === "full")
            return cfg.height + cfg.margin;
        return cfg.height + cfg.gap + cfg.margin;
    }

    readonly property bool barAtTop: GlobalConfig.topbar.enabled
        && GlobalConfig.topbar.position !== "bottom"
    readonly property bool dockAtTop: GlobalConfig.dock.enabled
        && GlobalConfig.dock.edge === "top"

    readonly property real barStrip: root.stripFor(GlobalConfig.topbar)

    // ── Two questions, two names ──────────────────────────────────────
    //
    // HOW MUCH of an edge the bar occupies, for the things that have to lay
    // out around it: its exclusion zone, caelestia's panel inset, the blob
    // backgrounds, where a closed drawer hides. Only the BAR counts, because
    // only the bar reserves space -- a panel opening behind the dock is a
    // panel behind a floating thing, which is what a dock is.
    readonly property real top: root.barAtTop ? root.barStrip : 0
    readonly property real bottom: (GlobalConfig.topbar.enabled && !root.barAtTop)
        ? root.barStrip : 0

    // ...and WHETHER anything of ours is standing on that edge at all, which
    // is a different question with a different answer. It decides whether the
    // drawers window gives up its eighty-pixel drag margin there, and the
    // dock needs that as much as the bar does: `hyprctl layers` puts the
    // drawers above the dock, so without this the dock takes no clicks on an
    // empty workspace. That was the first bug in this whole sequence, and it
    // came back the day these two questions were given one name.
    readonly property bool claimsTop: root.top > 0 || root.dockAtTop
    readonly property bool claimsBottom: root.bottom > 0
        || (GlobalConfig.dock.enabled && !root.dockAtTop)

    // The left edge belongs to caelestia's rail -- except when the Genesi bar
    // has taken the rail's place, which collapses it to the border thickness
    // and leaves that edge with nothing on it. The side panel's hover strip is
    // four pixels of screen and the drawers window's drag margin is eighty, so
    // without this the strip would never see a pointer.
    readonly property bool left: GlobalConfig.topbar.enabled
        && GlobalConfig.sidepanel.enabled && GlobalConfig.sidepanel.edgeHover
}
