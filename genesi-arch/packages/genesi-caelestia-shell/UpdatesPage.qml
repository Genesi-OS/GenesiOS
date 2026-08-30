//
// UpdatesPage.qml — the Nexus "Updates" page, which upstream registers but has
// never shipped.
//
// caelestia's PageRegistry lists Updates under System, and PageCompRegistry
// points it at PlaceholderComp — the "Page under construction" screen. This
// fills it in, so the update UI lives where a user already looks for settings
// instead of in a separate program. Same reason Windows keeps it in Settings.
//
// ── Written in caelestia's design language on purpose ────────────────────────
//
// Everything here is PageBase / ConnectedRect / SectionHeader / InfoRow /
// StyledText with Tokens and Colours. Not one Genesi component. Dropping the
// Genesi UI kit into this panel would read as a patch stitched onto someone
// else's app — and the colours here retint live from the wallpaper, which our
// fixed emerald would fight. The page is Genesi by what it DOES, not by how it
// looks.
//
// ── Why every command goes through `sh -c` ───────────────────────────────────
//
// Quickshell's Process exposes an exit code, but the only stdout API this file
// can point at in upstream's own code is StdioCollector.onStreamFinished
// (see AboutPage.qml). So each command encodes its exit status INTO stdout and
// the parsing reads it back. That keeps this page working against the one API
// upstream demonstrably uses, rather than one assumed from documentation.
//
// It matters most for `checkupdates`, which exits 2 for "nothing to do".
// Treating that happy answer as an error is how an updater starts crying wolf.
//
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // checking | current | available | error
    property string updateState: "checking"
    property var packages: []
    property string channel: ""
    property bool canRollback: false
    property string lastUpdate: ""
    property bool applying: false
    property string applyResult: ""

    readonly property int updateCount: packages.length

    title: qsTr("Updates")

    function refresh(): void {
        root.updateState = "checking";
        checkProc.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ── What is available ────────────────────────────────────────────────
        //
        // `checkupdates` (pacman-contrib) syncs into a PRIVATE database, so it
        // never needs root and can never leave the real one half-synced — the
        // classic `pacman -Sy` footgun that produces a partial upgrade later.
        // Without it we fall back to the on-disk database, which can be stale,
        // and the page says so rather than pretending.
        Process {
            id: checkProc

            running: true
            command: ["sh", "-c", "if command -v checkupdates >/dev/null 2>&1; then checkupdates 2>/dev/null; echo \"__RC__$?\"; else pacman -Qu 2>/dev/null; echo '__RC__STALE'; fi"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                    let rc = "0";
                    const pkgs = [];
                    for (const line of lines) {
                        if (line.startsWith("__RC__")) {
                            rc = line.substring(6);
                            continue;
                        }
                        // "name old -> new", or just "name old" from the fallback
                        const p = line.split(/\s+/);
                        pkgs.push({
                            name: p[0] ?? line,
                            from: p[1] ?? "",
                            to: (p[2] === "->" ? p[3] : "") ?? ""
                        });
                    }
                    root.packages = pkgs;
                    if (rc !== "0" && rc !== "2" && rc !== "STALE")
                        root.updateState = "error";
                    else
                        root.updateState = pkgs.length > 0 ? "available" : "current";
                }
            }
        }

        // Which channel this machine follows. Stable and testing are additive:
        // a machine on testing keeps [genesi] and gains [genesi-testing].
        Process {
            running: true
            command: ["sh", "-c", "genesi-channel get 2>/dev/null || true"]
            stdout: StdioCollector {
                onStreamFinished: root.channel = text.trim()
            }
        }

        // Whether this update can be undone. snap-pac already brackets every
        // pacman transaction with a snapshot on a Btrfs install — Genesi has
        // always done this and has never told anyone.
        Process {
            running: true
            command: ["sh", "-c", "test -e /etc/snapper/configs/root && echo yes || echo no"]
            stdout: StdioCollector {
                onStreamFinished: root.canRollback = text.trim() === "yes"
            }
        }

        // Last upgrade, read from pacman's own log. A separately tracked
        // timestamp would be a second source of truth, and would drift.
        Process {
            running: true
            command: ["sh", "-c", "grep 'starting full system upgrade' /var/log/pacman.log 2>/dev/null | tail -1 | cut -d'[' -f2 | cut -d']' -f1"]
            stdout: StdioCollector {
                onStreamFinished: root.lastUpdate = text.trim()
            }
        }

        // ── The one privileged action ────────────────────────────────────────
        //
        // A FIXED argv. Nothing from this page reaches the command line, and
        // the polkit action pins exec.path to that script, which itself takes
        // no argument that reaches pacman. The widest thing this page can ask
        // for is the transaction the user pressed a button to authorise.
        Process {
            id: applyProc

            command: ["pkexec", "/usr/bin/genesi-update-center-apply"]
            stdout: StdioCollector {
                onStreamFinished: {
                    root.applying = false;
                    // 126/127 are pkexec's own "cancelled / not authorised".
                    // Calling that a failed update would be a lie: nothing was
                    // attempted, and nothing changed.
                    root.refresh();
                }
            }
            onRunningChanged: {
                if (running)
                    root.applying = true;
            }
        }

        // ── Hero: the answer, before any of the detail ───────────────────────
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: hero

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                MaterialIcon {
                    id: heroIcon

                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        if (root.applying)
                            return "sync";
                        if (root.updateState === "available")
                            return "system_update_alt";
                        if (root.updateState === "error")
                            return "cloud_off";
                        return "check_circle";
                    }
                    color: root.updateState === "available" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.icon.extraLarge

                    // Turns only while something is actually happening. A
                    // spinner that never stops stops meaning anything.
                    //
                    // A standalone RotationAnimator with `target:`, NOT
                    // `RotationAnimator on rotation`. The `on` form takes
                    // ownership of the property and leaves it wherever the
                    // animation stopped -- which is why the check-circle sat
                    // upside down after the first check finished. This form
                    // can put it back.
                    RotationAnimator {
                        id: spin

                        target: heroIcon
                        running: root.applying || root.updateState === "checking"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1600
                        onRunningChanged: {
                            if (!running)
                                heroIcon.rotation = 0;
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (root.applying)
                            return qsTr("Updating…");
                        if (root.updateState === "checking")
                            return qsTr("Checking…");
                        if (root.updateState === "error")
                            return qsTr("Could not check");
                        if (root.updateState === "available")
                            return root.updateCount === 1 ? qsTr("1 update available") : qsTr("%1 updates available").arg(root.updateCount);
                        return qsTr("Up to date");
                    }
                    // The same form AboutPage's hero uses. `headline` is only
                    // ever reached through builders upstream -- a plain
                    // `headline.large` does not exist, and the static check
                    // against their source caught it before this shipped.
                    font: Tokens.font.headline.builders.large.width(110).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: {
                        if (root.applying)
                            return qsTr("This can take a few minutes. It is safe to keep using the system.");
                        if (root.updateState === "error")
                            return qsTr("This is usually the network or a mirror being down, not your system.");
                        if (root.updateState === "available" && root.canRollback)
                            return qsTr("A restore point is taken before and after, so this can be undone.");
                        if (root.updateState === "available")
                            return qsTr("Review what changes below.");
                        if (root.lastUpdate)
                            return qsTr("Last updated %1").arg(root.lastUpdate);
                        return "";
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                IconTextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    visible: !root.applying && root.updateState !== "checking"
                    icon: root.updateState === "available" ? "download" : "refresh"
                    text: root.updateState === "available" ? qsTr("Update now") : qsTr("Check again")
                    type: TextButton.Filled
                    onClicked: {
                        if (root.updateState === "available")
                            applyProc.running = true;
                        else
                            root.refresh();
                    }
                }
            }
        }

        // ── What actually changes ────────────────────────────────────────────
        //
        // Shown as a list rather than a count, because "47 updates" tells the
        // user nothing they can act on and a package name they recognise does.
        SectionHeader {
            visible: root.updateState === "available"
            text: qsTr("What changes")
        }

        Repeater {
            model: root.updateState === "available" ? root.packages : []

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.packages.length - 1
                label: modelData.name
                subtext: modelData.from && modelData.to ? `${modelData.from}  →  ${modelData.to}` : (modelData.from ?? "")
            }
        }

        // ── The context around the update ────────────────────────────────────
        SectionHeader {
            text: qsTr("System")
        }

        // InfoRow IS a ConnectedRect -- it draws its own rounded background and
        // takes first/last itself. Wrapping it in another one stacked two
        // rectangles: the outer rounded, the inner nearly square, and the inner
        // one won. That is the squared-off border seen on these cards. Upstream
        // uses InfoRow bare (see AboutPage's System section); so does this now.
        InfoRow {
            first: true
            label: qsTr("Update channel")
            subtext: root.channel === "testing" ? qsTr("Pre-release packages, and they can break your system") : qsTr("Tested packages")
            value: root.channel ? root.channel : "—"
        }

        InfoRow {
            label: qsTr("Last update")
            value: root.lastUpdate ? root.lastUpdate : "—"
        }

        InfoRow {
            last: true
            label: qsTr("Restore point")
            // The reassuring half of an update is being able to undo it, and
            // this machine can -- it just never said so.
            subtext: root.canRollback ? qsTr("Taken automatically before and after every update") : qsTr("Not available: the root filesystem is not Btrfs")
            value: root.canRollback ? qsTr("On") : qsTr("Off")
        }
    }
}
