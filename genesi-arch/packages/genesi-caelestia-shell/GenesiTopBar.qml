// GENESI — the bar across the top.
//
// caelestia's bar is a vertical rail down the left edge. This is the other
// shape: three islands along the top, the way most desktops have taught people
// to read a status bar.
//
// ── It does NOT replace caelestia. That was the bug ─────────────────────────
//
// The first version of this was a SECOND Quickshell process with its own
// shell.qml, and switching to it ran `pkill -f caelestia`. That does not
// disable a bar, it kills the shell: the launcher, every drawer, the
// notification daemon, the wallpaper, the theme bridge and the CLI all go with
// it. The desktop it left behind was broken in a way no setting could undo,
// and the package was withdrawn.
//
// So this is a WINDOW inside caelestia, exactly like the dock. Same process,
// same config, same colours, and nothing to kill. Turning it on hides the side
// rail through `disabled` on caelestia's own BarWrapper -- a property that
// already existed for excludedScreens -- which collapses its width to the
// border thickness AND drops its exclusive zone. Every drawer reflows because
// Panels.qml anchors itself to `bar.implicitWidth`, which is now zero.
//
// Turning it off puts the rail back. Nothing had to be restarted either way.
//
// ── Islands, not a slab ─────────────────────────────────────────────────────
//
// Three groups, each sized by its own contents, each on its own rounded
// surface. A single row with spacers cannot keep the centre centred when the
// sides are different widths -- the clock drifts as the window title changes,
// which is the tell of a bar built out of a Row. The centre is ANCHORED to the
// bar's centre and the sides are anchored to the edges, so the clock does not
// move when anything else does.
//
// ── Five forms, not a switch ────────────────────────────────────────────────
//
// This started as `topbar.islands`, a bool: three pills, or one inset slab.
// Which is two bars, and a switch labelled "islands rather than one bar"
// cannot grow a third answer without becoming a switch that lies. So the
// shape is a NAME now, and there are five of them:
//
//   islands   three surfaces, one per group, floating in the strip
//   full      one slab, edge to edge, square into the screen's corners
//   fit       one slab, inset on all four sides, rounded
//   dock      one slab flush to its edge, rounded only away from it
//   notch     the centre alone, flush to the edge, with shoulders that
//             curve back into it; the side groups ride on nothing
//
// Each one also decides how TALL the strip is, because a bar flush to the
// screen edge that still reserves a gap above itself is a bar with a stripe
// of desktop above it that nothing can ever be dropped into.
//
// A sixth, `frame`, draws nothing at all. caelestia's own border grows at
// that edge to the bar's height (GenesiEdges.frameTop, read by the drawers
// window), so the bar IS the border: its colour, opacity and shadow, and the
// rounded inner corners where it meets the screen. The contents sit on it.
//
// ── What is on it, and where ────────────────────────────────────────────
//
// The pieces are components -- WindowLabel, Resources, MediaChip,
// Workspaces -- instantiated in every group they are allowed in and shown
// in the one the config names. A Row does not lay out what is not visible,
// so an unshown copy costs nothing and no group has to be rebuilt when a
// piece moves.
//
// ── The tray ──────────────────────────────────────────────────────────────
//
// Turning this bar on collapses caelestia's rail, and the rail is where the
// system tray lived -- so Genesi Update, AI Mode and every other app's tray
// icon went with it. The tray is on this bar now, in the right-hand group.
//
// Which icons show is caelestia's own `bar.tray.hiddenIcons`, not a second
// list: the rail and this bar agree about it whichever one is on. The arrow
// at the end of the tray opens every icon with a pin beside it -- unpinned
// ones leave the bar but stay in that panel, still one click away, the way
// every desktop's "hidden icons" works. `topbar.showTray` turns the whole
// tray off, from the bar's studio.
//
// Left click activates, middle is the app's secondary action, right opens
// the app's own menu, and the wheel scrolls -- the same as the rail.
//
// The menu is DRAWN here, from the app's menu tree (QsMenuOpener), the way
// caelestia's rail draws its own. It used to be handed to
// SystemTrayItem.display() -- which nothing in caelestia calls -- and on a
// layer-shell bar that opened nothing at all. Genesi Update and AI Mode are
// appindicator icons, which are ONLY a menu (`onlyMenu`): their "activate"
// is a no-op by design. So every Genesi icon on this bar did nothing when
// clicked, left or right, which is exactly how it was reported.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils
// GenesiTopBarState -- the flag the bar's own settings panel watches. It sits
// beside the launcher's body, which is the module both halves import.
import qs.modules.launcher

Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property var cfg: contentItem.Config.topbar
        readonly property var tok: contentItem.Tokens
        // `contentItem`, not a bare `Config`. Config and Tokens are ATTACHED
        // types, and on the window itself -- which is not an Item -- the
        // attachment has no screen and falls back to the global config with a
        // warning. Every caelestia window that reads config at this level goes
        // through contentItem; the ones that read it inside their content do
        // not have to. Getting this wrong is how the dock shipped invisible.
        readonly property bool atTop: win.cfg.position !== "bottom"

        // ── The tray ────────────────────────────────────────────────────
        property bool trayOpen: false
        // The icon whose menu is open, the path into its submenus, and the x
        // (in screen-wide window coordinates) the card hangs from.
        property var trayMenu: null
        property var menuPath: []
        property real trayAt: 0
        readonly property var hiddenTray: GlobalConfig.bar.tray.hiddenIcons ?? []
        readonly property var pinnedTray: SystemTray.items.values
            .filter(i => !win.hiddenTray.includes(i.id))

        function setPinned(id: string, pinned: bool): void {
            const now = Array.from(win.hiddenTray);
            const next = pinned ? now.filter(x => x !== id)
                : (now.includes(id) ? now : now.concat([id]));
            GlobalConfig.bar.tray.hiddenIcons = next;
        }

        function closeTray(): void {
            win.trayOpen = false;
            win.trayMenu = null;
            win.menuPath = [];
        }

        // Where a card opened from `from` hangs: under its middle. Both this
        // bar and the card's window span the whole screen, so an x mapped
        // into either one is the same x.
        function hangFrom(from: Item): void {
            win.trayAt = from.mapToItem(null, from.width / 2, 0).x;
        }

        // `from` is the item that was clicked -- on the bar, or a row in the
        // panel of hidden icons -- so the menu opens under it.
        function trayClick(item: var, button: int, from: Item): void {
            if (button === Qt.MiddleButton) {
                item.secondaryActivate();
                return;
            }
            // Left click opens the menu too, whenever there is one. Every
            // Genesi tray icon is a libayatana AppIndicator, which ignores
            // Activate and does NOT declare itself menu-only -- so a left
            // click that went to activate() did nothing at all on them,
            // exactly as reported. Apps that do have a window to raise get
            // an "Open" row at the top of the menu instead.
            if (item.hasMenu) {
                if (win.trayMenu === item) {
                    win.closeTray();
                    return;
                }
                win.hangFrom(from);
                win.trayOpen = false;
                win.menuPath = [item.menu];
                win.trayMenu = item;
                return;
            }
            win.closeTray();
            if (button === Qt.RightButton)
                item.secondaryActivate();
            else
                item.activate();
        }

        // ── The form ────────────────────────────────────────────────────
        readonly property string form: win.cfg.form
        readonly property bool islands: win.form === "islands"
        readonly property bool notch: win.form === "notch"
        // caelestia's border, grown to hold the bar. Nothing of ours is
        // drawn under the groups -- the border is the surface.
        readonly property bool frame: win.form === "frame"
        // The frame is part of caelestia's border and cannot slide away with
        // the groups, so auto-hide means nothing there.
        readonly property bool hiding: win.cfg.autoHide && !win.frame
        // How far in from the screen's side the groups start: past the
        // border's side on the frame, where the border is on screen.
        readonly property real sideInset: win.islands ? win.cfg.gap * 2
            : (win.frame ? contentItem.Config.border.thickness + win.tok.padding.large
                         : win.tok.padding.medium)

        // ── Style ───────────────────────────────────────────────────────
        readonly property color accent: win.cfg.accent === "tertiary" ? Colours.palette.m3tertiary
            : (win.cfg.accent === "secondary" ? Colours.palette.m3secondary
                                              : Colours.palette.m3primary)
        readonly property color accentInk: win.cfg.accent === "tertiary" ? Colours.palette.m3onTertiary
            : (win.cfg.accent === "secondary" ? Colours.palette.m3onSecondary
                                              : Colours.palette.m3onPrimary)
        readonly property bool rings: win.cfg.resourceStyle === "rings"
        readonly property bool numbered: win.cfg.workspaceStyle === "numbers"
        readonly property string timeFormat: (win.cfg.clock24 ? "hh:mm" : "h:mm")
            + (win.cfg.showSeconds ? ":ss" : "") + (win.cfg.clock24 ? "" : " AP")
        readonly property string dateFormat: win.cfg.dateStyle === "numbers" ? "ddd, dd/MM"
            : (win.cfg.dateStyle === "long" ? "dddd, d MMMM" : "ddd, MMM d")
        readonly property var brightMon: Brightness.getMonitorForScreen(win.modelData)
        // One continuous surface behind the whole bar.
        readonly property bool slab: win.form === "full" || win.form === "fit"
            || win.form === "dock"

        // How much of the screen the bar occupies. The expression lives in
        // GenesiEdges because three upstream files need the same number --
        // Regions.qml to stop claiming this strip for input, Exclusions.qml
        // so the border stops reserving the same edge, and Panels.qml so the
        // drawers open below the bar rather than underneath it. Four copies
        // of one formula is four chances for three of them to be right.
        readonly property real strip: GenesiEdges.stripFor(win.cfg)

        // Where the slab's edges sit. Named rather than written inline four
        // times: a margin that says `form === "fit" ? gap : 0` in three places
        // is three chances to get one of them backwards.
        // The screen-edge side carries the margin on every form: it is
        // the space between the screen and the bar, and a `full` bar
        // with a margin is a slab that floats rather than one that is
        // flush.
        readonly property int slabEdge: (win.form === "fit"
            ? win.cfg.gap : 0) + win.cfg.margin
        readonly property int slabFar: win.form === "full" ? 0 : win.cfg.gap
        readonly property int slabSide: win.form === "fit" ? win.cfg.gap : 0
        readonly property int slabRadius: win.form === "full" ? 0 : win.cfg.radius
        // `dock` is flush to its edge, so the two corners on that side are
        // square however round the rest of it is.
        readonly property int slabEdgeRadius: win.form === "dock" ? 0 : win.slabRadius

        // ── Frost ───────────────────────────────────────────────────────
        //
        // Blur behind the bar. Hyprland owns this and Qt cannot: a layer
        // surface has no way to read what is under it, so there is nothing to
        // blur from inside QML. The rule goes on our namespace, which
        // StyledWindow builds as `caelestia-${name}`.
        //
        // `unset` is the way back. There is no negative form of a layerrule,
        // and the alternative -- reloading Hyprland's whole config to drop one
        // runtime keyword -- would throw away every other thing the session
        // had set since login.
        readonly property string ns: "caelestia-genesi-topbar"
        readonly property bool frost: win.cfg.frost

        function applyFrost(): void {
            if (win.frost) {
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `blur,${win.ns}`]);
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `ignorezero,${win.ns}`]);
            } else {
                Quickshell.execDetached(["hyprctl", "keyword", "layerrule",
                                         `unset,${win.ns}`]);
            }
        }

        onFrostChanged: win.applyFrost()
        Component.onCompleted: win.applyFrost()

        // ── Why the bar appears a moment after everything else ──────────
        //
        // Within a layer, Hyprland stacks surfaces in the order they mapped,
        // and there is no way to say otherwise from here: `layerrule = order`
        // is refused by 0.56.2, which answers "invalid field ... missing a
        // value" and changes nothing. Map order is the whole mechanism.
        //
        // And the drawers window remaps itself during startup on its own: its
        // layer is a binding on whether anything is fullscreen, and that
        // answer arrives from Hyprland's IPC a moment after the shell starts.
        // So even though shell.qml builds this bar after the drawers, the bar
        // could be mapped first and the drawers land on top of it -- their
        // border drawn over the bar, their hover strips taking its clicks.
        //
        // Toggling the bar off and on fixed it every single time, because
        // that is a remap, after the drawers have settled. This is that
        // toggle, done once, at the only moment it is needed. `mapped` never
        // goes back to false, so turning the bar off and on later behaves
        // normally.
        //
        // `hyprctl layers` says it works: the bar is the last surface on the
        // top layer on both monitors, above caelestia-drawers.
        property bool mapped: false

        Timer {
            running: !win.mapped
            interval: 800
            onTriggered: win.mapped = true
        }

        screen: modelData
        name: "genesi-topbar"
        visible: win.cfg.enabled && win.mapped

        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"

        anchors.top: win.atTop
        anchors.bottom: !win.atTop
        anchors.left: true
        anchors.right: true

        implicitHeight: win.strip

        // Withdrawn until the pointer reaches the edge. The WINDOW keeps its
        // height either way -- only the islands slide out of view -- because a
        // window that shrinks to nothing has no edge left to notice a pointer
        // arriving at, and the bar could never come back.
        property bool peek: false
        readonly property bool shown: !win.hiding || win.peek

        // The whole strip reserves space, so a maximised window stops below the
        // bar instead of underneath it. This is the one place the top bar and
        // the dock differ on purpose: a dock is somewhere you point at, a bar
        // is somewhere you read, and a bar you have to move a window to read is
        // not doing its job.
        exclusiveZone: win.cfg.enabled ? win.strip : 0

        // Only the islands take input. Without this the strip swallows clicks
        // along the entire top edge of every window on the screen.
        //
        // With auto-hide on it is the whole strip instead, because there has to
        // be something for the pointer to arrive at -- a hidden bar whose input
        // region is the islands it just hid cannot be reached again.
        mask: Region {
            x: win.hiding ? 0 : left.x
            y: win.hiding ? 0 : left.y
            width: win.hiding ? win.width : left.width
            height: win.hiding ? win.height : left.height

            Region {
                x: centre.x
                y: centre.y
                width: centre.width
                height: centre.height
            }
            Region {
                x: right.x
                y: right.y
                width: right.width
                height: right.height
            }
        }

        // ── Auto-hide ────────────────────────────────────────────────────
        //
        // A HoverHandler, not a MouseArea. A MouseArea's `containsMouse` goes
        // FALSE the moment the pointer moves onto a child that takes hover --
        // and every island button takes hover. So reaching for the clock made
        // the strip report the pointer had left, which hid the bar, which
        // moved the button out from under the pointer, which made the strip
        // report it had arrived. The bar flickered in and out and could not
        // be clicked, exactly as reported.
        //
        // A HoverHandler is not blocking and does not care what is above it:
        // it is hovered whenever the pointer is inside this item, children
        // included.
        HoverHandler {
            enabled: win.hiding
            onHoveredChanged: win.peek = hovered
        }

        // ── One continuous surface: full, fit and dock ───────────────────────
        StyledRect {
            anchors.fill: parent
            anchors.topMargin: win.atTop ? win.slabEdge : win.slabFar
            anchors.bottomMargin: win.atTop ? win.slabFar : win.slabEdge
            anchors.leftMargin: win.slabSide
            anchors.rightMargin: win.slabSide

            visible: win.slab && win.cfg.background
            opacity: win.shown ? 1 : 0

            radius: win.slabRadius
            topLeftRadius: win.atTop ? win.slabEdgeRadius : win.slabRadius
            topRightRadius: win.atTop ? win.slabEdgeRadius : win.slabRadius
            bottomLeftRadius: win.atTop ? win.slabRadius : win.slabEdgeRadius
            bottomRightRadius: win.atTop ? win.slabRadius : win.slabEdgeRadius

            color: Qt.alpha(Colours.palette.m3surfaceContainer,
                            Math.max(0, Math.min(100, win.cfg.backgroundOpacity)) / 100)
            border.width: win.cfg.border ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            Behavior on opacity {
                Anim {}
            }
        }

        // ── The notch ───────────────────────────────────────────────────────
        //
        // The centre group alone on a slab that reaches the screen edge, with
        // a shoulder on each side curving back into the bar. The side groups
        // sit on nothing, which is the point: a notch is a bar that only
        // exists where something is written.
        //
        // The shoulders are Shapes rather than rectangles with a radius: the
        // fillet is CONCAVE -- the surface is the part of a square OUTSIDE a
        // quarter circle -- and no rounded rectangle can be that. They cannot
        // be punched out of the slab either, because what shows through is the
        // desktop, and a hole cannot be drawn by painting over it.
        Item {
            id: notch

            readonly property real r: Math.min(win.cfg.radius, win.cfg.height / 2)
            readonly property color surface: Qt.alpha(
                Colours.palette.m3surfaceContainer,
                Math.max(0, Math.min(100, win.cfg.backgroundOpacity)) / 100)

            visible: win.notch && win.cfg.background
            opacity: win.shown ? 1 : 0

            x: centre.x - win.tok.padding.large
            width: centre.width + win.tok.padding.large * 2
            y: win.atTop ? win.cfg.margin
                         : parent.height - height - win.cfg.margin
            height: win.cfg.height + win.cfg.gap

            Behavior on opacity {
                Anim {}
            }

            StyledRect {
                anchors.fill: parent
                color: notch.surface
                topLeftRadius: win.atTop ? 0 : win.cfg.radius
                topRightRadius: win.atTop ? 0 : win.cfg.radius
                bottomLeftRadius: win.atTop ? win.cfg.radius : 0
                bottomRightRadius: win.atTop ? win.cfg.radius : 0
            }

            Repeater {
                model: 2

                Shape {
                    id: shoulder

                    required property int index
                    // Not `onLeft`: a property whose name is `on` plus a capital is
// parsed as a handler for a signal called `left`, and QML refuses
// to assign a value to a signal. ci/qml-sanity-test.py catches it.
                    readonly property bool leftSide: shoulder.index === 0
                    readonly property real r: notch.r

                    x: shoulder.leftSide ? -shoulder.r : notch.width
                    y: win.atTop ? 0 : notch.height - shoulder.r
                    width: shoulder.r
                    height: shoulder.r
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: notch.surface

                        // Three corners of the square and a curve across the
                        // fourth, bowing INTO the square so what is left is
                        // the outside of the fillet. A quadratic rather than
                        // an arc on purpose: an SVG arc between two points
                        // has two possible centres, chosen by a pair of flags
                        // that are easy to write backwards and produce a
                        // convex bulge when you do. A quadratic has one
                        // control point and no way to mean the other shape.
                        //
                        // One path per orientation rather than a mirrored
                        // transform, because mirroring a Shape mirrors its
                        // winding too, and a filled path that changes winding
                        // is a path that disappears.
                        PathSvg {
                            path: {
                                const r = shoulder.r;
                                if (win.atTop)
                                    return shoulder.leftSide
                                        ? `M 0,0 L ${r},0 L ${r},${r} Q 0,${r} 0,0 Z`
                                        : `M ${r},0 L 0,0 L 0,${r} Q ${r},${r} ${r},0 Z`;
                                return shoulder.leftSide
                                    ? `M 0,${r} L ${r},${r} L ${r},0 Q 0,0 0,${r} Z`
                                    : `M ${r},${r} L 0,${r} L 0,0 Q ${r},0 ${r},${r} Z`;
                            }
                        }
                    }
                }
            }
        }

        // ── The flow, between the islands ────────────────────────────────────
        //
        // Two tracks with lights running along them, one from the left island
        // to the centre and one from the centre to the right. It is decoration
        // and it is the point: three separate pills read as three unrelated
        // things until something ties them together, which is the same reason
        // the dock has one between its icons.
        //
        // Only when the islands ARE islands -- on one continuous surface there
        // is no gap for a connector to cross, and drawing one anyway would be a
        // line across the middle of a bar.
        Repeater {
            model: (win.cfg.flow && win.islands && win.shown) ? 2 : 0

            Item {
                id: gap

                required property int index

                readonly property Item from: gap.index === 0 ? left : centre
                readonly property Item to: gap.index === 0 ? centre : right

                x: gap.from.x + gap.from.width
                width: Math.max(0, gap.to.x - x)
                y: left.y
                height: left.height
                // A track between two islands that are touching is a track of
                // negative width drawn as a smear.
                visible: width > 24

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: win.tok.spacing.medium
                    height: 2
                    radius: 1
                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
                }

                Repeater {
                    model: 3

                    Rectangle {
                        id: light

                        required property int index

                        width: 4
                        height: 4
                        radius: 2
                        y: (gap.height - height) / 2
                        color: win.accent

                        SequentialAnimation {
                            running: true
                            loops: Animation.Infinite

                            // Staggered per GAP as well as per light: both
                            // gaps pulsing in unison reads as one bar filling,
                            // which is a progress bar that never finishes.
                            PauseAnimation {
                                duration: gap.index * 420 + light.index * 340
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: light
                                    property: "x"
                                    from: 0
                                    to: Math.max(0, gap.width - light.width)
                                    duration: 1600
                                    easing.type: Easing.InOutSine
                                }
                                SequentialAnimation {
                                    NumberAnimation {
                                        target: light
                                        property: "opacity"
                                        from: 0
                                        to: 1
                                        duration: 320
                                    }
                                    NumberAnimation {
                                        target: light
                                        property: "opacity"
                                        from: 1
                                        to: 0
                                        duration: 1280
                                    }
                                }
                            }
                            PauseAnimation {
                                duration: 900
                            }
                        }
                    }
                }
            }
        }

        // ── Left ─────────────────────────────────────────────────────
        Island {
            id: left

            anchors.left: parent.left
            anchors.leftMargin: win.sideInset
            anchors.verticalCenter: parent.verticalCenter

            // The Genesi mark. It was the "workspaces" glyph -- three dots
            // that mean nothing and belong to Material Symbols -- which is a
            // strange thing for the one place on the desktop that is supposed
            // to say whose desktop it is.
            //
            // It opens the side panel -- the quick settings down the left
            // edge -- rather than the launcher. A mark in the corner of a bar
            // is where every desktop puts its own controls, and the launcher
            // already answers to SUPER, to a tap of SUPER, and to the search
            // glyph beside this one.
            Item {
                id: markButton

                visible: win.cfg.showLogo
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: win.cfg.height * 0.66
                implicitHeight: win.cfg.height * 0.66

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: markHover.containsMouse
                           ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                           : "transparent"

                    Behavior on color {
                        CAnim {}
                    }
                }

                // The Genesi mark, unless somebody asked for something
                // else. `markIcon` is a Material Symbols ligature -- the same
                // names every other icon in the shell uses -- so wanting a
                // different glyph in the corner costs no file and no restart.
                //
                // The mark is a Shape and takes the scheme's colours; a
                // ligature takes them too. Neither is an image with a hex
                // value baked into it, which is the whole reason the mark was
                // drawn rather than loaded.
                GenesiMark {
                    anchors.centerIn: parent
                    visible: win.cfg.markIcon === ""
                    width: parent.width * 0.72
                    height: parent.height * 0.72
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: win.cfg.markIcon !== ""
                    text: win.cfg.markIcon
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                MouseArea {
                    id: markHover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // The Genesi panel, pinned -- you asked for it by
                    // name, so it stays until it is dismissed. The left edge
                    // of the screen opens the same panel on hover, and that
                    // one closes when the pointer leaves.
                    //
                    // It used to open caelestia's dashboard, which is a clock,
                    // a calendar, a media player and four graphs. Useful, and
                    // not what a mark in the corner of a bar is for: that is
                    // where a desktop keeps the switches you reach for without
                    // thinking.
                    onClicked: GenesiSidePanelState.toggle()
                }
            }

            // Search, which is what the launcher is. It used to be the mark's
            // job and the mark used to be a row of dots; both are in the right
            // place now.
            BarIcon {
                visible: win.cfg.showSidebarButton
                icon: "search"
                onActivated: {
                    const v = Visibilities.getForActive();
                    if (v)
                        v.launcher = !v.launcher;
                }
            }

            WindowLabel {
                here: win.cfg.windowPlace === "left"
            }

            Resources {
                here: win.cfg.resourcePlace === "left"
            }

            MediaChip {
                here: win.cfg.mediaPlace === "left"
            }

            Workspaces {}
        }

        // ── Centre ─────────────────────────────────────────────────
        //
        // ANCHORED to the centre of the bar, not placed between the other two.
        // Placed, it slides every time the window title changes length.
        Island {
            id: centre

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            clickable: true
            onActivated: {
                const v = Visibilities.getForActive();
                if (v)
                    v.dashboard = !v.dashboard;
            }

            WindowLabel {
                here: win.cfg.windowPlace !== "left"
            }

            MediaChip {
                here: win.cfg.mediaPlace === "centre"
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showClock
                text: Time.format(win.timeFormat)
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }

            // A dot between the time and the date, when there are both.
            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showClock && win.cfg.showDate
                implicitWidth: 4
                implicitHeight: 4
                radius: 2
                color: win.accent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showDate
                text: Time.format(win.dateFormat)
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        // ── Right ────────────────────────────────────────────────────
        Island {
            id: right

            anchors.right: parent.right
            anchors.rightMargin: win.sideInset
            anchors.verticalCenter: parent.verticalCenter

            MediaChip {
                here: win.cfg.mediaPlace === "right"
            }

            Repeater {
                model: win.cfg.showTray ? win.pinnedTray : []

                TrayIcon {}
            }

            // Every icon, pinned or not, with a pin beside each.
            BarIcon {
                id: trayArrow

                visible: win.cfg.showTray && SystemTray.items.values.length > 0
                icon: (win.trayOpen === win.atTop) ? "keyboard_arrow_up" : "keyboard_arrow_down"
                onActivated: {
                    const open = !win.trayOpen;
                    win.closeTray();
                    if (open) {
                        win.hangFrom(trayArrow);
                        win.trayOpen = true;
                    }
                }
            }

            Resources {
                here: win.cfg.resourcePlace !== "left"
            }

            // Scroll for louder or quieter, click to mute.
            Knob {
                visible: win.cfg.showVolume
                icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                label: Audio.muted ? "" : `${Math.round(Audio.volume * 100)}%`
                onTapped: {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                }
                onStepped: dir => dir > 0 ? Audio.incrementVolume() : Audio.decrementVolume()
            }

            Knob {
                visible: win.cfg.showBrightness && !!win.brightMon
                icon: "brightness_6"
                label: `${Math.round((win.brightMon?.brightness ?? 0) * 100)}%`
                onStepped: dir => win.brightMon?.setBrightness(
                    Math.max(0, Math.min(1, win.brightMon.brightness
                        + dir * GlobalConfig.services.brightnessIncrement)))
            }

            Knob {
                visible: win.cfg.showStatus
                icon: Network.active ? Icons.getNetworkIcon(Network.active.strength ?? 0) : "wifi_off"
                label: ""
                onTapped: GenesiSidePanelState.toggle()
            }

            Knob {
                visible: win.cfg.showBluetooth && !!Bluetooth.defaultAdapter
                icon: !(Bluetooth.defaultAdapter?.enabled ?? false) ? "bluetooth_disabled"
                    : (Bluetooth.devices.values.some(d => d.connected) ? "bluetooth_connected" : "bluetooth")
                label: ""
                onTapped: GenesiSidePanelState.toggle()
            }

            Reading {
                id: batteryReading

                readonly property var dev: UPower.displayDevice

                // A desktop has no battery, and a battery reading 100% for ever
                // is a reading nobody has ever looked at twice.
                visible: win.cfg.showStatus && win.cfg.batteryStyle !== "pill"
                    && (batteryReading.dev?.isLaptopBattery ?? false)
                icon: (batteryReading.dev?.state === UPowerDeviceState.Charging)
                      ? "battery_charging_full" : "battery_full"
                label: `${Math.round((batteryReading.dev?.percentage ?? 0) * 100)}%`
            }

            // The battery as a pill with its number on it: filled with the
            // accent while it charges, red when it is low.
            StyledRect {
                id: batteryPill

                readonly property var dev: UPower.displayDevice
                readonly property real level: batteryPill.dev?.percentage ?? 0
                readonly property bool charging: batteryPill.dev?.state === UPowerDeviceState.Charging

                anchors.verticalCenter: parent.verticalCenter
                visible: win.cfg.showStatus && win.cfg.batteryStyle === "pill"
                    && (batteryPill.dev?.isLaptopBattery ?? false)
                implicitWidth: Math.max(implicitHeight * 1.5, pillText.implicitWidth + win.tok.padding.medium * 2)
                implicitHeight: Math.round(win.cfg.height * 0.56)
                radius: Tokens.rounding.full
                color: batteryPill.charging ? win.accent
                    : (batteryPill.level < 0.2 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant)

                StyledText {
                    id: pillText

                    anchors.centerIn: parent
                    text: Math.round(batteryPill.level * 100)
                    font: Tokens.font.label.medium
                    color: batteryPill.charging ? win.accentInk : Colours.palette.m3surface
                }
            }

            BarIcon {
                visible: win.cfg.showPower
                icon: "power_settings_new"
                onActivated: {
                    const v = Visibilities.getForActive();
                    if (v)
                        v.session = !v.session;
                }
            }

            // The bar's own settings, on the bar. Everything about how this
            // strip looks is in there rather than spread across a settings app
            // -- you change a bar while looking at it, or you change it twice.
            BarIcon {
                visible: win.cfg.showConfigButton
                icon: "tune"
                onActivated: GenesiTopBarState.toggle()
            }
        }

        // ── Every tray icon with a pin, or one icon's menu ──────────────────
        LazyLoader {
            active: win.trayOpen || win.trayMenu !== null

            StyledWindow {
                id: trayWin

                screen: win.modelData
                name: "genesi-topbar-tray"

                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                color: "transparent"

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                // A click anywhere off the card puts it away.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onClicked: win.closeTray()
                }

                StyledRect {
                    id: trayCard

                    readonly property bool menuMode: win.trayMenu !== null

                    width: trayCard.menuMode ? 280 : 340
                    height: (trayCard.menuMode ? menuList.implicitHeight : trayList.implicitHeight)
                        + win.tok.padding.large * 2
                    x: Math.max(win.tok.padding.large,
                                Math.min(trayWin.width - trayCard.width - win.tok.padding.large,
                                         win.trayAt - trayCard.width / 2))
                    y: win.atTop ? win.strip + win.tok.spacing.small
                        : trayWin.height - win.strip - trayCard.height - win.tok.spacing.small
                    radius: win.tok.rounding.large
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                    focus: true
                    Keys.onEscapePressed: win.closeTray()

                    // Eats clicks, so "off the card" stays off the card.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                    }

                    // ── One icon's menu ─────────────────────────────────
                    Column {
                        id: menuList

                        readonly property var handle: win.menuPath.length > 0
                            ? win.menuPath[win.menuPath.length - 1] : null

                        visible: trayCard.menuMode
                        x: win.tok.padding.large
                        y: win.tok.padding.large
                        width: trayCard.width - win.tok.padding.large * 2
                        spacing: 2

                        QsMenuOpener {
                            id: opener

                            menu: menuList.handle
                        }

                        StyledText {
                            width: parent.width
                            bottomPadding: win.tok.spacing.small
                            text: win.trayMenu ? (win.trayMenu.tooltipTitle || win.trayMenu.title || win.trayMenu.id) : ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                            elide: Text.ElideRight
                        }

                        // What a plain left click used to do, for the apps
                        // where it does something: raise their window.
                        MenuRow {
                            visible: win.menuPath.length === 1 && win.trayMenu !== null && !win.trayMenu.onlyMenu
                            glyph: "open_in_new"
                            label: qsTr("Open")
                            onChosen: {
                                const item = win.trayMenu;
                                win.closeTray();
                                item.activate();
                            }
                        }

                        // Out of a submenu.
                        MenuRow {
                            visible: win.menuPath.length > 1
                            glyph: "chevron_left"
                            label: qsTr("Back")
                            onChosen: win.menuPath = win.menuPath.slice(0, -1)
                        }

                        Repeater {
                            model: opener.children

                            Item {
                                id: entry

                                required property QsMenuEntry modelData

                                width: menuList.width
                                height: entry.modelData.isSeparator ? 9 : row.height

                                Rectangle {
                                    visible: entry.modelData.isSeparator
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 1
                                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.7)
                                }

                                MenuRow {
                                    id: row

                                    visible: !entry.modelData.isSeparator
                                    width: parent.width
                                    label: entry.modelData.text
                                    image: entry.modelData.icon
                                    live: entry.modelData.enabled
                                    more: entry.modelData.hasChildren
                                    // A check or a radio shows its state; a
                                    // plain entry shows nothing there.
                                    glyph: entry.modelData.buttonType === QsMenuButtonType.None ? ""
                                        : entry.modelData.checkState === Qt.Checked
                                            ? (entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                               ? "radio_button_checked" : "check_box")
                                            : (entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                               ? "radio_button_unchecked" : "check_box_outline_blank")
                                    onChosen: {
                                        if (entry.modelData.hasChildren) {
                                            win.menuPath = win.menuPath.concat([entry.modelData]);
                                        } else {
                                            entry.modelData.triggered();
                                            win.closeTray();
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: opener.children.values.length === 0
                            width: parent.width
                            topPadding: win.tok.spacing.small
                            text: qsTr("Loading the menu…")
                            color: Colours.palette.m3outline
                        }
                    }

                    // ── Every icon, with a pin ──────────────────────────
                    Column {
                        id: trayList

                        visible: !trayCard.menuMode
                        x: win.tok.padding.large
                        y: win.tok.padding.large
                        width: trayCard.width - win.tok.padding.large * 2
                        spacing: win.tok.spacing.small

                        StyledText {
                            text: qsTr("Tray icons")
                            font: Tokens.font.title.small
                        }
                        StyledText {
                            width: parent.width
                            text: qsTr("Pinned ones sit on the bar. The rest stay here, a click away.")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            width: 1
                            height: win.tok.spacing.small
                        }

                        Repeater {
                            model: SystemTray.items.values

                            StyledRect {
                                id: trayRow

                                required property SystemTrayItem modelData

                                width: trayList.width
                                height: 44
                                radius: win.tok.rounding.medium
                                color: rowHover.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.07) : "transparent"

                                MouseArea {
                                    id: rowHover

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => win.trayClick(trayRow.modelData, mouse.button, trayRow)
                                }

                                ColouredIcon {
                                    id: rowIcon

                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22
                                    height: 22
                                    source: Icons.getTrayIcon(trayRow.modelData.id, trayRow.modelData.icon)
                                    colour: Colours.palette.m3secondary
                                    layer.enabled: GlobalConfig.bar.tray.recolour
                                }

                                StyledText {
                                    anchors.left: rowIcon.right
                                    anchors.leftMargin: 12
                                    anchors.right: pin.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: trayRow.modelData.tooltipTitle || trayRow.modelData.title || trayRow.modelData.id
                                    elide: Text.ElideRight
                                }

                                StyledSwitch {
                                    id: pin

                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: !win.hiddenTray.includes(trayRow.modelData.id)
                                    onToggled: win.setPinned(trayRow.modelData.id, checked)
                                }
                            }
                        }

                        StyledText {
                            visible: SystemTray.items.values.length === 0
                            width: parent.width
                            text: qsTr("No app has an icon in the tray right now.")
                            color: Colours.palette.m3outline
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        // A tray icon on the bar. Coloured like the rail's, and recoloured to
        // the scheme when caelestia's "recolour tray icons" is on.
        component TrayIcon: MouseArea {
            id: trayIcon

            required property SystemTrayItem modelData

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.round(win.cfg.height * 0.52)
            implicitHeight: Math.round(win.cfg.height * 0.52)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: mouse => win.trayClick(trayIcon.modelData, mouse.button, trayIcon)
            onWheel: wheel => trayIcon.modelData.scroll(wheel.angleDelta.y > 0 ? 1 : -1, false)

            ColouredIcon {
                anchors.fill: parent
                source: Icons.getTrayIcon(trayIcon.modelData.id, trayIcon.modelData.icon)
                colour: Colours.palette.m3secondary
                layer.enabled: GlobalConfig.bar.tray.recolour
                opacity: trayIcon.containsMouse ? 1 : 0.9
            }
        }

        // One line of a tray menu: an optional check or icon, the text, and a
        // chevron when it opens a submenu.
        component MenuRow: StyledRect {
            id: menuRow

            property string label: ""
            property string image: ""
            property string glyph: ""
            property bool live: true
            property bool more: false

            signal chosen

            height: 34
            radius: win.tok.rounding.medium
            color: menuHover.containsMouse && menuRow.live
                ? Qt.alpha(Colours.palette.m3onSurface, 0.08) : "transparent"

            MaterialIcon {
                id: menuGlyph

                x: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: menuRow.glyph !== ""
                text: menuRow.glyph
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            IconImage {
                id: menuImage

                x: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: menuRow.glyph === "" && menuRow.image !== ""
                implicitSize: 18
                asynchronous: true
                source: menuRow.image
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: (menuGlyph.visible || menuImage.visible) ? 36 : 10
                anchors.right: menuMore.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                // Qt menus mark their mnemonic with an underscore or an
                // ampersand; neither means anything here.
                text: menuRow.label.replace(/_([^_])/g, "$1").replace(/&([^&])/g, "$1")
                color: menuRow.live ? Colours.palette.m3onSurface : Colours.palette.m3outline
                elide: Text.ElideRight
            }

            MaterialIcon {
                id: menuMore

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                visible: menuRow.more
                text: "chevron_right"
                color: Colours.palette.m3onSurfaceVariant
            }

            MouseArea {
                id: menuHover

                anchors.fill: parent
                hoverEnabled: true
                enabled: menuRow.live
                cursorShape: Qt.PointingHandCursor
                onClicked: menuRow.chosen()
            }
        }

        // ── The surface a group sits on ──────────────────────────────────────
        //
        // The island IS the row. It was a rectangle wrapping an Item that
        // filled it, holding a Row centred in that -- so the island's width
        // came from its child's childrenRect, the child's width came from the
        // island, and the centred Row's position came from both. Qt called it
        // what it was: "Binding loop detected for property implicitWidth", six
        // times, one per island per screen.
        //
        // Sized off `row.implicitWidth`, which depends on nothing above it, and
        // the row sits at a fixed x rather than centred. Nothing in the chain
        // reads the island's own width any more.
        component Island: StyledRect {
            id: island

            default property alias content: row.data

            // A click on the whole island, for the groups that want one. The
            // MouseArea is declared HERE rather than passed in, because the
            // default alias sends every child into the row -- a MouseArea
            // there would be laid out as one more item in the row instead of
            // covering it.
            property bool clickable: false

            signal activated

            implicitWidth: row.implicitWidth + win.tok.padding.large * 2
            implicitHeight: win.cfg.height

            radius: win.cfg.radius
            // Only when the groups ARE islands. On one continuous surface the
            // pills would be three lighter rectangles drawn on top of a bar,
            // which reads as a rendering mistake rather than as a design.
            // Only in the `islands` form. On a slab the pills would be
            // three lighter rectangles drawn on top of a bar, which reads as
            // a rendering mistake rather than as a design; under a notch the
            // centre already has a surface of its own.
            color: (win.islands && win.cfg.background)
                   ? Qt.alpha(Colours.palette.m3surfaceContainer,
                              Math.max(0, Math.min(100, win.cfg.backgroundOpacity)) / 100)
                   : "transparent"
            border.width: (win.islands && win.cfg.background && win.cfg.border) ? 1 : 0
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

            // Slid out of view and faded, rather than merely faded: nothing is
            // then drawn under the pointer at 1% opacity waiting to be clicked
            // by accident.
            opacity: win.shown ? 1 : 0
            // The MARGIN, not y: every island is anchored to the strip's
            // vertical centre, and a `y` binding on an anchored item is two
            // things assigning one property. The anchor wins and the slide
            // silently does nothing -- which is exactly how the dock's slide
            // was dead for a release.
            // Half the margin, because the strip grew by a whole margin on
            // one side only and the island is centred in all of it. Folded
            // into the SLIDE's offset rather than added as a second
            // verticalCenterOffset: two things assigning one property is how
            // the slide was silently dead for a release.
            readonly property real restOffset: win.frame ? 0
                : (win.atTop ? 1 : -1) * win.cfg.margin / 2

            anchors.verticalCenterOffset: win.shown ? island.restOffset
                : (win.atTop ? -(win.cfg.height + win.cfg.gap * 3)
                             : win.cfg.height + win.cfg.gap * 3)

            Behavior on opacity {
                Anim {}
            }
            Behavior on anchors.verticalCenterOffset {
                Anim {}
            }

            // A soft drop, off by default. On a busy wallpaper it is the
            // difference between a surface and a stain; on a plain one it is
            // just haze.
            layer.enabled: win.cfg.shadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.45)
                shadowBlur: 0.6
                shadowVerticalOffset: 2
            }

            MouseArea {
                anchors.fill: parent
                enabled: island.clickable
                cursorShape: Qt.PointingHandCursor
                onClicked: island.activated()
            }

            Row {
                id: row

                x: win.tok.padding.large
                anchors.verticalCenter: parent.verticalCenter
                spacing: win.tok.spacing.medium
            }
        }

        component BarIcon: Item {
            id: barIcon

            property string icon: ""
            property bool accent: false

            signal activated

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: win.cfg.height * 0.66
            implicitHeight: win.cfg.height * 0.66

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: hover.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                                           : "transparent"

                Behavior on color {
                    CAnim {}
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: barIcon.icon
                color: barIcon.accent ? Colours.palette.m3primary
                                      : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: barIcon.activated()
            }
        }

        // ── The pieces that can sit in more than one group ───────────────
        //
        // Each has `here`, set by the group it is placed in, and is visible
        // only where the config puts it. Not `visible` itself: a component
        // that binds its own visibility has that binding REPLACED by any
        // assignment at the place it is used, and the "is it switched on"
        // half would silently go with it.

        // The focused window: its title, and with `windowStacked` the app it
        // belongs to above it, small.
        component WindowLabel: Column {
            id: wl

            property bool here: true
            readonly property var ipc: Hypr.activeToplevel?.lastIpcObject
            readonly property string title: wl.ipc?.title ?? ""
            readonly property string app: wl.ipc?.class ?? ""
            // A title is the one thing here with no natural width, so it is
            // the one thing that gets a cap. Without it a browser tab named
            // after an article pushes the clock off-centre.
            readonly property real cap: win.width * (win.cfg.windowStacked ? 0.16 : 0.22)

            anchors.verticalCenter: parent.verticalCenter
            visible: wl.here && win.cfg.showActiveWindow && wl.title !== ""
            spacing: -2

            StyledText {
                visible: win.cfg.windowStacked && wl.app !== ""
                width: Math.min(implicitWidth, wl.cap)
                text: wl.app
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
            }

            StyledText {
                width: Math.min(implicitWidth, wl.cap)
                text: wl.title
                font: Tokens.font.body.small
                color: win.cfg.windowStacked ? Colours.palette.m3onSurface
                                             : Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        // Processor, memory and -- when asked -- disk and temperature. As an
        // icon and a number, or as rings that fill.
        component Resources: Row {
            id: res

            property bool here: true

            anchors.verticalCenter: parent.verticalCenter
            visible: res.here && (win.cfg.showResources || win.cfg.showDisk || win.cfg.showTemperature)
            spacing: win.rings ? win.tok.spacing.medium : win.tok.spacing.small

            Gauge {
                visible: win.cfg.showResources
                value: Cpu.percentage
                icon: "memory"
                label: `${Math.round(Cpu.percentage * 100)}%`
            }
            Gauge {
                visible: win.cfg.showResources
                value: Memory.percentage
                icon: "memory_alt"
                label: `${Math.round(Memory.percentage * 100)}%`
            }
            Gauge {
                visible: win.cfg.showDisk
                value: Storage.percentage
                icon: "hard_drive"
                label: `${Math.round(Storage.percentage * 100)}%`
            }
            Gauge {
                visible: win.cfg.showTemperature
                // Against 100 degrees: where a desktop processor throttles.
                value: Cpu.temperature / 100
                icon: "thermostat"
                label: `${Math.round(Cpu.temperature)}°`
            }
        }

        // One reading: a ring with the icon inside it, or the icon alone,
        // and the number beside either.
        component Gauge: Row {
            id: gauge

            property real value: 0
            property string icon: ""
            property string label: ""

            anchors.verticalCenter: parent.verticalCenter
            spacing: win.tok.spacing.extraSmall

            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: win.rings ? Math.round(win.cfg.height * 0.64) : gaugeIcon.implicitWidth
                implicitHeight: win.rings ? implicitWidth : gaugeIcon.implicitHeight

                CircularProgress {
                    anchors.fill: parent
                    visible: win.rings
                    value: isNaN(gauge.value) ? 0 : gauge.value
                    strokeWidth: Math.max(2, Math.round(win.cfg.height / 15))
                    fgColour: gauge.value > 0.85 ? Colours.palette.m3error : win.accent
                    bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.12)
                }

                MaterialIcon {
                    id: gaugeIcon

                    anchors.centerIn: parent
                    text: gauge.icon
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: win.rings ? Tokens.font.icon.builders.small.scale(0.75).build()
                                         : Tokens.font.icon.small
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: gauge.label
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
            }
        }

        // What is playing. Click pauses or plays, the wheel skips, the
        // middle button goes to the next track.
        component MediaChip: Item {
            id: media

            property bool here: true
            readonly property var player: Players.active
            readonly property string title: media.player?.trackTitle ?? ""
            readonly property string artist: media.player?.trackArtist ?? ""

            anchors.verticalCenter: parent.verticalCenter
            visible: media.here && win.cfg.showMedia && media.title !== ""
            implicitWidth: mediaRow.implicitWidth
            implicitHeight: mediaRow.implicitHeight

            Row {
                id: mediaRow

                spacing: win.tok.spacing.small

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (media.player?.isPlaying ?? false) ? "graphic_eq" : "music_note"
                    color: win.accent
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, win.width * 0.16)
                    text: media.artist !== "" ? `${media.title} • ${media.artist}` : media.title
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        if (media.player?.canGoNext)
                            media.player.next();
                    } else {
                        media.player?.togglePlaying();
                    }
                }
                onWheel: wheel => {
                    if (wheel.angleDelta.y < 0 && media.player?.canGoNext)
                        media.player.next();
                    else if (wheel.angleDelta.y > 0 && media.player?.canGoPrevious)
                        media.player.previous();
                }
            }
        }

        // The workspaces: dots with the active one stretched, or numbers
        // with the active one circled. The wheel over them moves along.
        component Workspaces: Row {
            id: wsRow

            // With numbers, the first `workspaceCount` are always there, and
            // any workspace past them joins for as long as it exists.
            readonly property var ids: {
                const n = Math.max(1, Math.min(10, win.cfg.workspaceCount));
                const out = [];
                for (let i = 1; i <= n; i++)
                    out.push(i);
                for (const w of (Hypr.workspaces?.values ?? []))
                    if (w.id > n && !out.includes(w.id))
                        out.push(w.id);
                return out.sort((a, b) => a - b);
            }

            anchors.verticalCenter: parent.verticalCenter
            visible: win.cfg.showWorkspaces
            spacing: win.numbered ? 0 : win.tok.spacing.medium

            WheelHandler {
                onWheel: event => Quickshell.execDetached(["hyprctl", "dispatch", "workspace",
                                                          event.angleDelta.y > 0 ? "r-1" : "r+1"])
            }

            Repeater {
                model: win.numbered ? wsRow.ids : []

                Item {
                    id: num

                    required property int modelData

                    readonly property var ws: (Hypr.workspaces?.values ?? []).find(w => w.id === num.modelData)
                    readonly property bool active: num.modelData === Hypr.activeWsId
                    readonly property bool occupied: (num.ws?.lastIpcObject?.windows ?? 0) > 0

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Math.round(win.cfg.height * 0.64)
                    implicitHeight: implicitWidth

                    StyledRect {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Tokens.rounding.full
                        color: num.active ? win.accent : "transparent"

                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: num.modelData
                        font: Tokens.font.label.medium
                        color: num.active ? win.accentInk
                            : (num.occupied ? Colours.palette.m3onSurface
                                            : Qt.alpha(Colours.palette.m3outline, 0.7))
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "workspace",
                                                            String(num.modelData)])
                    }
                }
            }

            Repeater {
                model: win.numbered ? [] : (Hypr.workspaces?.values ?? [])

                StyledRect {
                    id: ws

                    required property var modelData

                    readonly property bool active: ws.modelData?.id === Hypr.activeWsId
                    readonly property bool occupied: (ws.modelData?.lastIpcObject?.windows ?? 0) > 0

                    anchors.verticalCenter: parent.verticalCenter
                    // The active one is a bar, the rest are dots. Shape rather
                    // than colour alone: which workspace you are on has to be
                    // legible at a glance and out of the corner of an eye, and
                    // a colour difference is neither on a busy wallpaper.
                    implicitWidth: ws.active ? win.cfg.height * 0.62 : win.cfg.height * 0.26
                    implicitHeight: win.cfg.height * 0.26
                    radius: Tokens.rounding.full
                    color: ws.active ? win.accent
                                     : (ws.occupied ? Colours.palette.m3onSurfaceVariant
                                                    : Qt.alpha(Colours.palette.m3outline, 0.45))

                    Behavior on implicitWidth {
                        Anim {}
                    }
                    Behavior on color {
                        CAnim {}
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(
                            ["hyprctl", "dispatch", "workspace",
                             String(ws.modelData?.id ?? 1)])
                    }
                }
            }
        }

        // A Reading you can click and scroll.
        component Knob: Item {
            id: ctl

            property string icon: ""
            property string label: ""

            signal tapped
            signal stepped(dir: int)

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: ctlReading.implicitWidth
            implicitHeight: Math.max(ctlReading.implicitHeight, win.cfg.height * 0.6)

            Reading {
                id: ctlReading

                icon: ctl.icon
                label: ctl.label
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: ctl.tapped()
                onWheel: wheel => ctl.stepped(wheel.angleDelta.y > 0 ? 1 : -1)
            }
        }

        // An icon and a number. Read through `reading`, never through `parent`:
        // a `parent` chain is a guess about a tree, and it stops being true the
        // first time anything here is wrapped in a Loader or a Row.
        component Reading: Row {
            id: reading

            property string icon: ""
            property string label: ""

            anchors.verticalCenter: parent.verticalCenter
            spacing: win.tok.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: reading.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: reading.label !== ""
                text: reading.label
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurface
            }
        }
    }
}
