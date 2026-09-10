// GENESI — which screen edges a Genesi surface already owns.
//
// ── The bug this exists to answer ──────────────────────────────────────────
//
// caelestia's drawers window covers the whole screen and takes input on a
// FRAME around it: the border, plus a drag margin so a panel can be pulled in
// from its edge. That margin is not small. Regions.qml computes it as the
// largest dragThreshold of the four panels
//
//     max(dashboard 50, launcher 50, session 30, sidebar 80)
//
// and applies it on all four edges whenever the active workspace has no
// windows on it -- so the top and bottom NINETY pixels of an empty desktop
// belong to the drawers window.
//
// The Genesi top bar is 46 pixels tall and the dock about 76. Both sit
// entirely inside that strip, and the drawers window is above them, so on a
// freshly logged-in session -- nothing open, which is every login and every
// reboot -- neither received a single click. Open any window and the margin
// collapses to zero and both come back to life, which is why this read as a
// startup bug rather than a layout one.
//
// ── What it yields, and what it keeps ──────────────────────────────────────
//
// On an edge a Genesi surface owns, caelestia gives up the drag MARGIN and
// keeps its border strip. That is the smallest change that works: the bar
// needs 46 of those 90 pixels and the dock 76, while the border is 10, so
// both are clear -- and every caelestia hover point stays exactly where it
// was, at exactly its normal size. Yielding the whole edge would have taken
// the dashboard's top hover and the launcher's drag-up with it.
//
// ── Why a boolean and not a height ─────────────────────────────────────────
//
// The first version of this published how TALL each surface was, so upstream
// could inset by exactly that. Which meant the bar's height had an expression
// in the file that draws it and a second one here, and every bug this project
// has spent a day on has been two lists quietly disagreeing. A yes-or-no
// cannot drift.
//
// GlobalConfig rather than the per-screen attached Config: this is a
// singleton, so there is no screen to attach to, and the surfaces it reports
// on are configured once for the whole session.
pragma Singleton

import Quickshell
import Caelestia.Config

Singleton {
    id: root

    readonly property bool barAtTop: GlobalConfig.topbar.enabled
        && GlobalConfig.topbar.position !== "bottom"
    readonly property bool dockAtTop: GlobalConfig.dock.enabled
        && GlobalConfig.dock.edge === "top"

    readonly property bool top: root.barAtTop || root.dockAtTop
    readonly property bool bottom: (GlobalConfig.topbar.enabled && !root.barAtTop)
        || (GlobalConfig.dock.enabled && !root.dockAtTop)

    // The left edge belongs to caelestia's rail -- except when the Genesi bar
    // has taken the rail's place, which collapses it to the border thickness
    // and leaves that edge with nothing on it. The side panel's hover strip
    // is four pixels of screen, and the drawers window's drag margin is
    // eighty, so without this the strip would never see a pointer.
    readonly property bool left: GlobalConfig.topbar.enabled
        && GlobalConfig.sidepanel.enabled && GlobalConfig.sidepanel.edgeHover
}
