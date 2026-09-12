// GENESI — the quick settings, down the left edge.
//
// The Genesi mark on the bar used to open caelestia's dashboard, which is a
// clock, a calendar, a media player and four graphs. Useful, and not what a
// mark in the corner of a bar is for: that is where every desktop keeps the
// switches you reach for without thinking -- the network, the volume, the
// screen, whether the machine is allowed to sleep.
//
// ── Two ways in, and they mean different things ────────────────────────────
//
// The mark opens it PINNED: you asked for it by name, so it stays until it is
// dismissed. A panel that vanished while you reached for a slider in it would
// be a panel nobody uses twice.
//
// The left edge of the screen opens it on hover, unpinned, and it closes when
// the pointer leaves. caelestia already teaches that edges are where panels
// come from -- the top for the dashboard, the bottom for the launcher, the
// right for the session -- and with the Genesi bar on, the left edge is the
// one nothing is using: the side rail has collapsed to make room for the bar.
//
// ── Only with the top bar ──────────────────────────────────────────────────
//
// Without it, caelestia's rail is on the left edge and its own popouts are
// there too, and a second panel arriving from underneath it would be two
// things answering one gesture. So this exists exactly when the bar does.
//
// ── Everything here is a real service, or it is not here ───────────────────
//
// Wi-Fi is Nmcli, Bluetooth is the adapter, Do not disturb is Notifs.dnd,
// Gaming is GameMode, Keep awake is IdleInhibitor, the power profile is
// UPower's. Aeroplane mode is rfkill and night light is hyprsunset, which are
// the two that are not already in the shell -- both are processes, and both
// read their state back rather than remembering what they were told, because
// a toggle that only remembers is a toggle that lies after anything else
// touches the same setting.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher

Variants {
    model: Screens.screens

    Scope {
        id: scope

        required property ShellScreen modelData

        // GlobalConfig, not the attached Config. A Scope is not an Item, so
        // there is no screen for the attached type to resolve against --
        // every singleton and every Scope upstream reads GlobalConfig for
        // exactly this reason.
        readonly property bool available: GlobalConfig.topbar.enabled
            && GlobalConfig.sidepanel.enabled

        // ── The strip along the left edge ───────────────────────────────────
        //
        // Four pixels wide, invisible, and the only thing it does is notice a
        // pointer. It is a window of its own rather than part of the panel
        // because the panel is 360 wide: a hover region that size would open
        // itself every time the pointer crossed the left third of the screen.
        StyledWindow {
            id: edge

            // scope.modelData, not a declaration of its own. Variants hands
            // `modelData` to its delegate -- the Scope -- and to nothing
            // inside it, so a `required property` here is one nobody sets,
            // which is a load error for the whole file.
            screen: scope.modelData
            name: "genesi-edge"
            visible: scope.available && GlobalConfig.sidepanel.edgeHover

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"

            anchors.left: true
            anchors.top: true
            anchors.bottom: true
            implicitWidth: 4

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: if (containsMouse)
                    GenesiSidePanelState.peek()
            }
        }

        StyledWindow {
            id: win

            readonly property var cfg: contentItem.Config.sidepanel
            readonly property var tok: contentItem.Tokens

            // One screen, the focused one. Two monitors would otherwise get
            // two panels, both of them live.
            readonly property bool mine: GenesiSidePanelState.open
                && scope.available
                && Hypr.monitorFor(scope.modelData)?.id === Hypr.focusedMonitor?.id

            // Named on the window, not read from `contentItem` down in the
            // card. Config is an ATTACHED type: at window level it has to be
            // reached through contentItem, and from a grandchild an
            // unqualified `contentItem` is a name that may or may not resolve
            // depending on where the object was declared. One property here,
            // read as win.markIcon everywhere else.
            readonly property string markIcon: contentItem.Config.topbar.markIcon

            readonly property real barStrip: contentItem.Config.topbar.height
                + contentItem.Config.topbar.gap * 2
            readonly property bool barAtTop:
                contentItem.Config.topbar.position !== "bottom"

            // ── Depth, as this panel sees it ────────────────────────────
            readonly property var depth: contentItem.Config.background.depth
            readonly property string wallpaper: Wallpapers.current

            property string cutout: ""
            property string cutError: ""
            readonly property bool cutting: cutter.running

            // Which cutter is installed, from `genesi-depth status`. There
            // are two: a segmentation model, and the saliency pipeline that
            // needs nothing installed. The second one refused a cat sitting
            // on a lawn, so this page's job is to put the first one one click
            // away instead of in a paragraph nobody reads.
            property string depthEngine: ""
            property string depthSetup: ""
            property int depthModelMb: 176
            readonly property bool depthInstalling:
                win.depthSetup.startsWith("running")

            function set(section: string, key: string, value: var): void {
                Quickshell.execDetached(["genesi-center-set", "caelestia",
                                         `${section}.${key}`, String(value)]);
            }

            // The same command the desktop layer runs, with the same two
            // names passed straight through -- so the picture on this page is
            // the picture on the wallpaper and not a second opinion about it.
            function recut(force: bool): void {
                win.cutout = "";
                win.cutError = "";
                if (!win.depth.enabled || win.wallpaper === "") {
                    return;
                }
                const argv = ["genesi-depth", "cutout", win.wallpaper,
                              "--quality", win.depth.quality,
                              "--edge-fade", win.depth.edgeFade];
                if (force)
                    argv.push("--force");
                cutter.command = argv;
                cutter.running = true;
            }

            function run(argv: var): void {
                Quickshell.execDetached(argv);
                GenesiSidePanelState.hide();
            }

            screen: scope.modelData
            name: "genesi-sidepanel"
            visible: win.mine

            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: win.mine ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Declared first, so the card is drawn over it and takes its own
            // clicks. Without this every toggle would close the panel.
            MouseArea {
                anchors.fill: parent
                onClicked: GenesiSidePanelState.hide()
            }

            StyledRect {
                id: card

                anchors.left: parent.left
                anchors.leftMargin: win.tok.padding.large
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // Clear of the bar, on whichever edge the bar is. A panel that
                // starts under the thing whose button opened it hides the
                // button.
                anchors.topMargin: (win.barAtTop ? win.barStrip : 0)
                    + win.tok.padding.large
                anchors.bottomMargin: (win.barAtTop ? 0 : win.barStrip)
                    + win.tok.padding.large

                implicitWidth: Math.max(300, Math.min(win.width * 0.4, win.cfg.width))

                radius: win.tok.rounding.large
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.6)

                opacity: win.mine ? 1 : 0
                // Slid in from the edge it belongs to, which is the only
                // animation that says where a panel came from.
                x: win.mine ? win.tok.padding.large : -implicitWidth

                Behavior on opacity {
                    Anim {}
                }
                Behavior on x {
                    Anim {}
                }

                focus: true
                Keys.onEscapePressed: GenesiSidePanelState.hide()

                // The pointer leaving closes an UNPINNED panel -- one the edge
                // opened. One the mark opened stays.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: {
                        if (containsMouse)
                            leaveTimer.stop();
                        else if (!GenesiSidePanelState.pinned)
                            leaveTimer.restart();
                    }
                }

                // Not immediate: a pointer crossing the gap between two
                // controls leaves the card for a frame, and a panel that shuts
                // on that is a panel you cannot use.
                Timer {
                    id: leaveTimer

                    interval: 400
                    onTriggered: if (!GenesiSidePanelState.pinned)
                        GenesiSidePanelState.hide()
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                // ── The rail ─────────────────────────────────────────────────
                //
                // Not pages: every one of these opens something that already
                // exists elsewhere in the shell. A rail of pages where half of
                // them are empty would be worse than no rail.
                Column {
                    id: rail

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: win.tok.padding.medium
                    width: 34
                    spacing: win.tok.spacing.small

                    Repeater {
                        model: [
                            {
                                icon: "tune",
                                what: "studio",
                                tip: qsTr("Shell studio")
                            },
                            {
                                icon: "notifications",
                                what: "notifications",
                                tip: qsTr("Notifications")
                            },
                            {
                                icon: "filter_center_focus",
                                what: "depth",
                                tip: qsTr("Depth")
                            },
                            {
                                icon: "wallpaper",
                                what: "wallpaper",
                                tip: qsTr("Next wallpaper")
                            },
                            {
                                icon: "palette",
                                what: "schemes",
                                tip: qsTr("Colour schemes")
                            },
                            {
                                icon: "settings",
                                what: "center",
                                tip: qsTr("Genesi Center")
                            }
                        ]

                        StyledRect {
                            id: railItem

                            required property var modelData

                            readonly property bool on: railItem.modelData.what
                                === GenesiSidePanelState.page

                            width: rail.width
                            implicitHeight: rail.width
                            radius: win.tok.rounding.full
                            color: railItem.on
                                ? Colours.palette.m3primaryContainer
                                : (railHover.containsMouse
                                   ? Qt.alpha(Colours.palette.m3onSurface, 0.1)
                                   : "transparent")

                            Behavior on color {
                                CAnim {}
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: railItem.modelData.icon
                                color: railItem.on
                                    ? Colours.palette.m3onPrimaryContainer
                                    : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            MouseArea {
                                id: railHover

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    switch (railItem.modelData.what) {
                                    case "studio":
                                        GenesiSidePanelState.hide();
                                        GenesiTopBarState.show();
                                        return;
                                    case "notifications":
                                        const v = Visibilities.getForActive();
                                        if (v)
                                            v.sidebar = true;
                                        GenesiSidePanelState.hide();
                                        return;
                                    case "depth":
                                        GenesiSidePanelState.openPage("depth");
                                        return;
                                    case "wallpaper":
                                        win.run(["caelestia", "wallpaper", "-r"]);
                                        return;
                                    case "schemes":
                                        GenesiSidePanelState.hide();
                                        GenesiSchemeState.show();
                                        return;
                                    case "center":
                                        win.run(["genesi-center"]);
                                        return;
                                    }
                                }
                            }
                        }
                    }
                }

                StyledFlickable {
                    id: flick

                    anchors.left: rail.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: win.tok.padding.large
                    anchors.leftMargin: win.tok.spacing.small
                    contentHeight: GenesiSidePanelState.page === "depth"
                        ? depthBody.implicitHeight : body.implicitHeight
                    clip: true

                    // ── Depth ────────────────────────────────────────────
                    //
                    // Here rather than in the shell studio because this is
                    // where it belongs: the studio is about how the shell is
                    // DRAWN, and this is about the picture behind it.
                    //
                    // The preview is the point of the page. genesi-depth
                    // answers "there is no subject in this picture" for a
                    // texture, a gradient or a sky full of cloud -- which is
                    // a correct answer and an invisible one, because the
                    // desktop then looks exactly as it did before. Showing
                    // the cut-out, or saying plainly that there is not one,
                    // is the difference between a feature that is off and a
                    // feature that is broken.
                    ColumnLayout {
                        id: depthBody

                        width: flick.width
                        spacing: win.tok.spacing.medium
                        visible: GenesiSidePanelState.page === "depth"

                        Head {
                            text: qsTr("DEPTH")
                        }

                        StyledRect {
                            id: preview

                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: win.tok.rounding.large
                            color: Colours.palette.m3surface
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
                            clip: true

                            // The wallpaper, dimmed, so the cut-out on top of
                            // it reads as a piece taken OUT of that picture
                            // rather than as a picture of its own.
                            Image {
                                anchors.fill: parent
                                source: win.wallpaper === "" ? "" : `file://${win.wallpaper}`
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.28
                            }

                            Image {
                                id: previewCut

                                anchors.fill: parent
                                source: win.cutout === "" ? "" : `file://${win.cutout}`
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: win.cutout !== ""
                            }

                            StyledText {
                                anchors.centerIn: parent
                                width: parent.width - win.tok.padding.large * 2
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                visible: win.cutout === ""
                                text: win.cutting
                                    ? qsTr("Looking for a subject…")
                                    : (win.cutError !== ""
                                       ? win.cutError
                                       : qsTr("Turn Depth on to see what it finds."))
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        // ── The cutter ───────────────────────────────
                        //
                        // Above the on/off switch, because it decides how
                        // good everything below it can be. The built-in one
                        // infers a subject from contrast and its thresholds
                        // are guesses about what a picture is made of; the
                        // model was trained to answer the question. On eight
                        // photographs the built-in one refuses a cat on a
                        // lawn and the model traces its whiskers.
                        Tile {
                            icon: win.depthEngine === "model"
                                ? "auto_awesome" : "download"
                            label: win.depthInstalling
                                ? qsTr("Installing the cutter")
                                : (win.depthEngine === "model"
                                   ? qsTr("Trained cutter")
                                   : qsTr("Install the better cutter"))
                            reading: win.depthInstalling
                                ? win.depthSetup.replace("running ", "")
                                : (win.depthEngine === "model"
                                   ? qsTr("In use")
                                   : (win.depthSetup.startsWith("failed")
                                      ? qsTr("Failed — tap to retry")
                                      : qsTr("%1 MB").arg(win.depthModelMb)))
                            // Lit when the model is in use. Nothing to turn
                            // off: it is used whenever it is installed,
                            // because there is no picture the worse cutter is
                            // better on.
                            on: win.depthEngine === "model"
                            onTriggered: {
                                if (win.depthEngine === "model"
                                    || win.depthInstalling)
                                    return;
                                Quickshell.execDetached(["genesi-depth",
                                                         "setup"]);
                                // Optimistic, and corrected by the read two
                                // and a half seconds later. Without it the
                                // row sits unchanged after a tap, which reads
                                // as a dead control -- and this project has
                                // shipped enough of those.
                                win.depthSetup = "running preparing";
                                depthProc.running = true;
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            wrapMode: Text.WordWrap
                            visible: win.depthEngine !== "model"
                                     || win.depthSetup.startsWith("failed")
                            text: win.depthSetup.startsWith("failed")
                                ? qsTr("The install failed: %1")
                                  .arg(win.depthSetup.replace("failed ", ""))
                                : qsTr("The built-in cutter guesses from "
                                       + "contrast and often finds nothing. "
                                       + "The trained one is %1 MB, "
                                       + "downloaded once, and runs on this "
                                       + "machine like everything else.")
                                  .arg(win.depthModelMb)
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        Tile {
                            icon: "filter_center_focus"
                            label: qsTr("Depth effect")
                            reading: win.depth.enabled ? qsTr("On") : qsTr("Off")
                            on: win.depth.enabled
                            onTriggered: win.set("background", "depth.enabled",
                                                 !win.depth.enabled)
                        }

                        Pick {
                            label: qsTr("Detail")
                            blurb: qsTr("Higher detail traces hair and fine edges, but the cut takes longer.")
                            options: [
                                { id: "draft", label: qsTr("DRAFT") },
                                { id: "standard", label: qsTr("STANDARD") },
                                { id: "fine", label: qsTr("FINE") }
                            ]
                            current: win.depth.quality
                            onPicked: id => win.set("background", "depth.quality", id)
                        }

                        Pick {
                            label: qsTr("Edge fade")
                            blurb: qsTr("Soften where the cut-out meets the scene.")
                            options: [
                                { id: "none", label: qsTr("NONE") },
                                { id: "soft", label: qsTr("SOFT") },
                                { id: "strong", label: qsTr("STRONG") }
                            ]
                            current: win.depth.edgeFade
                            onPicked: id => win.set("background", "depth.edgeFade", id)
                        }

                        Pick {
                            label: qsTr("Strength")
                            blurb: qsTr("How much the subject stands out in front.")
                            options: [
                                { id: "subtle", label: qsTr("SUBTLE") },
                                { id: "medium", label: qsTr("MEDIUM") },
                                { id: "full", label: qsTr("FULL") }
                            ]
                            current: win.depth.strength
                            onPicked: id => win.set("background", "depth.strength", id)
                        }

                        Pick {
                            label: qsTr("Shadow")
                            blurb: qsTr("A soft shadow behind the subject, for more depth.")
                            options: [
                                { id: "none", label: qsTr("NONE") },
                                { id: "soft", label: qsTr("SOFT") },
                                { id: "strong", label: qsTr("STRONG") }
                            ]
                            current: win.depth.shadow
                            onPicked: id => win.set("background", "depth.shadow", id)
                        }

                        Head {
                            text: qsTr("CUT-OUT")
                        }

                        Tile {
                            icon: "refresh"
                            label: qsTr("Re-render the cut-out")
                            reading: qsTr("Ignores the cache")
                            onTriggered: win.recut(true)
                        }

                        Tile {
                            icon: "delete_sweep"
                            label: qsTr("Clear cached cut-outs")
                            reading: qsTr("They are made again on demand")
                            onTriggered: {
                                Quickshell.execDetached(["genesi-depth", "clear"]);
                                win.cutout = "";
                            }
                        }
                    }

                    ColumnLayout {
                        id: body

                        width: flick.width
                        spacing: win.tok.spacing.medium
                        visible: GenesiSidePanelState.page === "quick"

                        // ── The head ─────────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: win.tok.spacing.medium

                            // The mark, or whatever the user put in its place.
                            // Same fork the bar's button uses, so the two are
                            // never different pictures of the same thing.
                            Item {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34

                                StyledRect {
                                    anchors.fill: parent
                                    radius: Tokens.rounding.full
                                    color: Colours.palette.m3primaryContainer
                                }

                                GenesiMark {
                                    anchors.centerIn: parent
                                    visible: win.markIcon === ""
                                    width: 20
                                    height: 20
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: win.markIcon !== ""
                                    text: win.markIcon
                                    color: Colours.palette.m3onPrimaryContainer
                                    fontStyle: Tokens.font.icon.small
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: Time.format("hh:mm")
                                    font: Tokens.font.title.large
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: Time.format("dddd, d MMMM")
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            // The battery, when there is one. A desktop drawing
                            // "100%" for ever is a reading nobody asked for.
                            StyledText {
                                visible: UPower.displayDevice?.isLaptopBattery ?? false
                                text: `${Math.round((UPower.displayDevice?.percentage ?? 0) * 100)}%`
                                font: Tokens.font.mono.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        // ── Session ──────────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.cfg.showSession
                            spacing: win.tok.spacing.small

                            Repeater {
                                model: [
                                    {
                                        icon: "logout",
                                        argv: ["hyprctl", "dispatch", "exit"]
                                    },
                                    {
                                        icon: "lock",
                                        argv: ["loginctl", "lock-session"]
                                    },
                                    {
                                        icon: "restart_alt",
                                        argv: ["systemctl", "reboot"]
                                    },
                                    {
                                        icon: "power_settings_new",
                                        argv: ["systemctl", "poweroff"]
                                    }
                                ]

                                StyledRect {
                                    id: sessionButton

                                    required property var modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: win.tok.rounding.large
                                    color: sessionHover.containsMouse
                                        ? Colours.palette.m3surfaceContainerHighest
                                        : Colours.layer(Colours.palette.m3surfaceContainer, 2)

                                    Behavior on color {
                                        CAnim {}
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: sessionButton.modelData.icon
                                        color: Colours.palette.m3onSurfaceVariant
                                        fontStyle: Tokens.font.icon.small
                                    }

                                    MouseArea {
                                        id: sessionHover

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.run(sessionButton.modelData.argv)
                                    }
                                }
                            }
                        }

                        // ── Connect ──────────────────────────────────────────
                        Head {
                            text: qsTr("CONNECT")
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            visible: win.cfg.showToggles
                            columns: 2
                            columnSpacing: win.tok.spacing.small
                            rowSpacing: win.tok.spacing.small

                            Tile {
                                icon: "wifi"
                                label: qsTr("Wi-Fi")
                                reading: Nmcli.wifiEnabled
                                    ? (Nmcli.active?.ssid ?? qsTr("On"))
                                    : qsTr("Off")
                                on: Nmcli.wifiEnabled
                                onTriggered: Nmcli.toggleWifi()
                            }

                            Tile {
                                icon: "bluetooth"
                                label: qsTr("Bluetooth")
                                // qmllint disable unresolved-type
                                reading: (Bluetooth.defaultAdapter?.enabled ?? false)
                                    ? qsTr("On") : qsTr("Off")
                                on: Bluetooth.defaultAdapter?.enabled ?? false
                                onTriggered: {
                                    const adapter = Bluetooth.defaultAdapter;
                                    if (adapter)
                                        adapter.enabled = !adapter.enabled;
                                }
                                // qmllint enable unresolved-type
                            }

                            Tile {
                                icon: "airplanemode_active"
                                label: qsTr("Airplane")
                                reading: radios.airplane ? qsTr("On") : qsTr("Off")
                                on: radios.airplane
                                onTriggered: radios.toggle()
                            }

                            Tile {
                                icon: "nightlight"
                                label: qsTr("Night light")
                                reading: night.on
                                    ? `${win.cfg.nightTemperature}K` : qsTr("Off")
                                on: night.on
                                onTriggered: night.on = !night.on
                            }

                            Tile {
                                icon: "coffee"
                                label: qsTr("Keep awake")
                                reading: IdleInhibitor.enabled ? qsTr("On") : qsTr("Off")
                                on: IdleInhibitor.enabled
                                onTriggered: IdleInhibitor.enabled = !IdleInhibitor.enabled
                            }

                            Tile {
                                icon: "do_not_disturb_on"
                                label: qsTr("Do not disturb")
                                reading: Notifs.dnd ? qsTr("On") : qsTr("Off")
                                on: Notifs.dnd
                                onTriggered: Notifs.dnd = !Notifs.dnd
                            }

                            Tile {
                                icon: "sports_esports"
                                label: qsTr("Gaming")
                                reading: GameMode.enabled ? qsTr("On") : qsTr("Off")
                                on: GameMode.enabled
                                onTriggered: GameMode.enabled = !GameMode.enabled
                            }
                        }

                        // ── Sound and display ────────────────────────────────
                        Head {
                            text: qsTr("SOUND & DISPLAY")
                            visible: win.cfg.showSliders
                        }

                        Level {
                            visible: win.cfg.showSliders
                            icon: Audio.muted ? "volume_off" : "volume_up"
                            value: Audio.volume
                            onMoved: v => Audio.setVolume(v)
                            onIconClicked: {
                                const a = Audio.sink?.audio;
                                if (a)
                                    a.muted = !a.muted;
                            }
                        }

                        Level {
                            visible: win.cfg.showSliders
                            icon: Audio.sourceMuted ? "mic_off" : "mic"
                            value: Audio.sourceVolume
                            onMoved: v => Audio.setSourceVolume(v)
                            onIconClicked: {
                                const a = Audio.source?.audio;
                                if (a)
                                    a.muted = !a.muted;
                            }
                        }

                        Level {
                            // The monitor this panel is ON, not the first one
                            // in the list: brightness is per screen, and a
                            // slider that moves somebody else's display is
                            // worse than no slider.
                            readonly property var monitor:
                                Brightness.getMonitorForScreen(win.screen)

                            visible: win.cfg.showSliders && monitor !== undefined
                            icon: "brightness_6"
                            value: monitor?.brightness ?? 0
                            onMoved: v => monitor?.setBrightness(v)
                        }

                        // ── Calendar ─────────────────────────────────────────
                        Head {
                            text: qsTr("CALENDAR")
                            visible: win.cfg.showCalendar
                        }

                        StyledRect {
                            id: calendar

                            // The first of this month, and which weekday it
                            // falls on. Everything else on the grid is an
                            // offset from that, so the month only has to be
                            // worked out once.
                            readonly property date today: Time.date
                            readonly property int year: calendar.today.getFullYear()
                            readonly property int month: calendar.today.getMonth()
                            readonly property int firstDay:
                                new Date(calendar.year, calendar.month, 1).getDay()
                            readonly property int days:
                                new Date(calendar.year, calendar.month + 1, 0).getDate()

                            Layout.fillWidth: true
                            visible: win.cfg.showCalendar
                            implicitHeight: calGrid.implicitHeight
                                + calHead.implicitHeight
                                + win.tok.padding.large * 2
                                + win.tok.spacing.small
                            radius: win.tok.rounding.large
                            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

                            StyledText {
                                id: calHead

                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: win.tok.padding.large
                                text: Time.format("MMMM yyyy")
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurface
                            }

                            GridLayout {
                                id: calGrid

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: calHead.bottom
                                anchors.leftMargin: win.tok.padding.large
                                anchors.rightMargin: win.tok.padding.large
                                anchors.topMargin: win.tok.spacing.small
                                columns: 7
                                columnSpacing: 0
                                rowSpacing: 2

                                Repeater {
                                    model: [qsTr("S"), qsTr("M"), qsTr("T"),
                                            qsTr("W"), qsTr("T"), qsTr("F"),
                                            qsTr("S")]

                                    StyledText {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3outline
                                    }
                                }

                                Repeater {
                                    // The blanks before the first, then the
                                    // days. One list, so the grid never has to
                                    // be told where the month starts.
                                    model: calendar.firstDay + calendar.days

                                    Item {
                                        id: day

                                        required property int index

                                        readonly property int date:
                                            day.index - calendar.firstDay + 1
                                        readonly property bool real: day.date >= 1
                                        readonly property bool today: day.real
                                            && day.date === calendar.today.getDate()

                                        Layout.fillWidth: true
                                        implicitHeight: 24

                                        StyledRect {
                                            anchors.centerIn: parent
                                            visible: day.today
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            radius: Tokens.rounding.full
                                            color: Colours.palette.m3primary
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            visible: day.real
                                            text: day.date
                                            font: Tokens.font.body.small
                                            color: day.today
                                                ? Colours.palette.m3onPrimary
                                                : Colours.palette.m3onSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }

                        // ── Power ────────────────────────────────────────────
                        Head {
                            text: qsTr("POWER")
                            visible: win.cfg.showPower && PowerProfiles.hasPerformanceProfile
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.cfg.showPower && PowerProfiles.hasPerformanceProfile
                            spacing: win.tok.spacing.small

                            Repeater {
                                model: [
                                    {
                                        label: qsTr("Saver"),
                                        profile: PowerProfile.PowerSaver
                                    },
                                    {
                                        label: qsTr("Balanced"),
                                        profile: PowerProfile.Balanced
                                    },
                                    {
                                        label: qsTr("Performance"),
                                        profile: PowerProfile.Performance
                                    }
                                ]

                                StyledRect {
                                    id: profile

                                    required property var modelData

                                    readonly property bool on:
                                        PowerProfiles.profile === profile.modelData.profile

                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: win.tok.rounding.large
                                    color: profile.on
                                        ? Colours.palette.m3primaryContainer
                                        : Colours.layer(Colours.palette.m3surfaceContainer, 2)

                                    Behavior on color {
                                        CAnim {}
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: profile.modelData.label
                                        font: Tokens.font.label.small
                                        color: profile.on
                                            ? Colours.palette.m3onPrimaryContainer
                                            : Colours.palette.m3onSurfaceVariant
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: PowerProfiles.profile =
                                            profile.modelData.profile
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Night light ──────────────────────────────────────────────────
            //
            // hyprsunset as a child process rather than a fire-and-forget
            // command: `running` is the switch, so the warm cast leaves when
            // the shell does and there is never a stray daemon holding a
            // colour transform nothing on screen can explain.
            PersistentProperties {
                id: night

                property bool on: false

                reloadableId: "genesiNightLight"
            }

            Process {
                running: night.on && win.cfg.nightTemperature > 0
                command: ["hyprsunset", "-t", String(win.cfg.nightTemperature)]
            }

            // ── Aeroplane mode ───────────────────────────────────────────────
            //
            // rfkill, read back rather than remembered. Something else can
            // block a radio -- a laptop's own switch, a udev rule, nmcli --
            // and a toggle that only remembers what it was told last would
            // then be showing the opposite of what is true.
            QtObject {
                id: radios

                property bool airplane: false

                function toggle(): void {
                    setProc.command = ["rfkill",
                                       radios.airplane ? "unblock" : "block",
                                       "all"];
                    setProc.running = true;
                }
            }

            Process {
                id: setProc

                onExited: readProc.running = true
            }

            Process {
                id: readProc

                command: ["rfkill", "list", "--output", "SOFT", "--noheadings"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.trim().split("\n")
                            .map(l => l.trim()).filter(l => l !== "");
                        radios.airplane = lines.length > 0
                            && lines.every(l => l === "blocked");
                    }
                }
            }

            // Read when the panel opens, not on a timer: nothing else in the
            // shell needs this, and polling rfkill every few seconds for a
            // reading nobody is looking at is a process per tick for ever.
            onMineChanged: {
                if (!win.mine)
                    return;
                readProc.running = true;
                depthProc.running = true;
                win.recut(false);
            }

            // `genesi-depth status` prints `key value`, one per line. Read
            // when the panel opens, and again every couple of seconds while
            // an install is running -- which is the only time it changes. A
            // timer that ran for ever would be a process per tick for a
            // number nobody is looking at.
            Process {
                id: depthProc

                command: ["genesi-depth", "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const was = win.depthEngine;
                        let setup = "";
                        for (const line of text.trim().split("\n")) {
                            const sp = line.indexOf(" ");
                            if (sp < 0)
                                continue;
                            const k = line.slice(0, sp);
                            const v = line.slice(sp + 1).trim();
                            if (k === "engine")
                                win.depthEngine = v;
                            else if (k === "setup")
                                setup = v;
                            else if (k === "model_mb")
                                win.depthModelMb = parseInt(v) || 176;
                        }
                        win.depthSetup = setup;
                        // A cut-out made by the other engine is stale in a
                        // way nothing about it looks stale, which is the same
                        // reason the cache is keyed by the picture's mtime.
                        if (was !== "" && was !== win.depthEngine)
                            win.recut(true);
                    }
                }
            }

            Timer {
                running: win.mine && win.depthInstalling
                interval: 2500
                repeat: true
                onTriggered: depthProc.running = true
            }

            Process {
                id: cutter

                stdout: StdioCollector {
                    onStreamFinished: win.cutout = text.trim()
                }
                stderr: StdioCollector {
                    onStreamFinished: win.cutError = text.trim()
                }
                // A non-zero exit is a real answer -- "nothing in this picture
                // stands out enough to be a subject" -- and the message on
                // stderr is the one worth showing. Clearing the path on
                // failure matters: the collector still fires, and a stale one
                // would leave the last wallpaper's subject on this page.
                onExited: code => {
                    if (code !== 0)
                        win.cutout = "";
                }
            }

            Connections {
                function onEnabledChanged(): void {
                    win.recut(false);
                }

                function onQualityChanged(): void {
                    win.recut(false);
                }

                function onEdgeFadeChanged(): void {
                    win.recut(false);
                }

                target: win.depth
            }

            // ── The parts ────────────────────────────────────────────────────
            component Head: StyledText {
                Layout.fillWidth: true
                Layout.topMargin: win.tok.spacing.small
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
            }

            // A toggle with a name and a reading. The reading is what makes it
            // worth the space: "Wi-Fi / On" is a switch, "Wi-Fi / Fibra-5G" is
            // an answer to the question you opened the panel to ask.
            component Tile: StyledRect {
                id: tile

                property string icon: ""
                property string label: ""
                property string reading: ""
                property bool on: false

                signal triggered

                Layout.fillWidth: true
                implicitHeight: 56
                radius: win.tok.rounding.large
                color: tile.on
                    ? Colours.palette.m3primaryContainer
                    : (tileHover.containsMouse
                       ? Colours.palette.m3surfaceContainerHighest
                       : Colours.layer(Colours.palette.m3surfaceContainer, 2))

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    id: tileIcon

                    anchors.left: parent.left
                    anchors.leftMargin: win.tok.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.icon
                    color: tile.on ? Colours.palette.m3onPrimaryContainer
                                   : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                Column {
                    anchors.left: tileIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: win.tok.spacing.small
                    anchors.rightMargin: win.tok.padding.small
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        width: parent.width
                        text: tile.label
                        font: Tokens.font.label.medium
                        color: tile.on ? Colours.palette.m3onPrimaryContainer
                                       : Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: tile.reading
                        font: Tokens.font.body.small
                        color: tile.on
                            ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.75)
                            : Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: tileHover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.triggered()
                }
            }

            // A named row of choices. The panel's own, rather than the
            // studio's: this is a 360-wide column, and the studio's cards are
            // sized for a pane three times that.
            component Pick: ColumnLayout {
                id: pick

                property string label: ""
                property string blurb: ""
                property var options: []
                property string current: ""

                signal picked(string id)

                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: pick.label
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    visible: pick.blurb !== ""
                    text: pick.blurb
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: win.tok.spacing.extraSmall

                    Repeater {
                        model: pick.options

                        StyledRect {
                            id: opt

                            required property var modelData

                            readonly property bool on: opt.modelData.id === pick.current

                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: win.tok.rounding.large
                            color: opt.on
                                ? Colours.palette.m3primaryContainer
                                : Colours.layer(Colours.palette.m3surfaceContainer, 2)

                            Behavior on color {
                                CAnim {}
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: opt.modelData.label
                                font: Tokens.font.label.small
                                color: opt.on
                                    ? Colours.palette.m3onPrimaryContainer
                                    : Colours.palette.m3onSurfaceVariant
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pick.picked(opt.modelData.id)
                            }
                        }
                    }
                }
            }

            // An icon, a slider and a percentage.
            //
            // caelestia's StyledSlider does not move its own `value`: its
            // MouseArea drives `pos`, a 0-to-1 position, and hands that back
            // through `interaction`. Reading `value` after a drag gives you
            // the number you started with -- which is how every slider in the
            // shell studio came to write nothing at all.
            component Level: RowLayout {
                id: level

                property string icon: ""
                property real value: 0

                signal moved(real v)
                signal iconClicked

                Layout.fillWidth: true
                spacing: win.tok.spacing.medium

                MaterialIcon {
                    text: level.icon
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: level.iconClicked()
                    }
                }

                StyledSlider {
                    id: slider

                    Layout.fillWidth: true
                    value: level.value
                    onInteraction: v => level.moved(v)
                }

                StyledText {
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                    text: `${Math.round(slider.pos * 100)}%`
                    font: Tokens.font.mono.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
