/*
 * Genesi Snapshots — the "indestructible OS" dashboard.
 *
 * A protection panel over the genesi-snapshots CLI (snapper + snap-pac +
 * grub-btrfs). The hero states, at a glance, whether the machine is protected;
 * the timeline lists every restore point; one click creates a manual snapshot,
 * rolls back, or deletes. The Studio components only style the presentation;
 * all recovery and restore behavior remains in the existing backend.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: win
    visible: true
    width: 980; height: 740
    minimumWidth: 760; minimumHeight: 580
    title: "Genesi Snapshots"
    color: appTheme.bgBottom

    // appTheme, not `theme`: a component that HAS a `theme` property
    // (GButton, StudioCard, StatusBanner) resolves a bare `theme` on the
    // right-hand side to its own unset property, not to this id.
    StudioTheme { id: appTheme }
    I18n  { id: i18n }

    // ── state (driven by the backend) ──────────────────────────────
    property var  st: ({ btrfs: false, configured: false, snapPac: false, grubBtrfs: false, count: 0 })
    property var  snaps: []
    property var  rec: ({ recovery: false, number: 0, target: "" })
    property bool busy: false
    property string toast: ""

    // Booted a read-only snapshot from the GRUB menu — the "dead end" a layperson
    // hits. In this mode the normal actions target the wrong subvolume, so they're
    // locked and the recovery card drives the one-click way back.
    readonly property bool inRecovery: rec.recovery === true
    readonly property bool protectedOk: st.btrfs && st.configured
    readonly property color protColor: !st.btrfs ? appTheme.red
                                      : (st.configured ? appTheme.green : appTheme.turbo)

    Connections {
        target: backend
        function onStatusLoaded(s)    { try { win.st = JSON.parse(s) } catch (e) {} }
        function onSnapshotsLoaded(s) { try { win.snaps = (JSON.parse(s).snapshots) || [] } catch (e) {} }
        function onRecoveryLoaded(s)  { try { win.rec = JSON.parse(s) } catch (e) {} }
        function onBusyChanged(b)     { win.busy = b }
        function onActionDone(m)      { win.toast = m; toastTimer.restart() }
        function onLogLine(l)         { console.log(l) }
    }
    Timer { id: toastTimer; interval: 4200; onTriggered: win.toast = "" }

    // Snapshot "type" → colour + label. snap-pac writes pre/post around each
    // pacman transaction; manual/baseline are 'single'.
    function typeColor(s) {
        if (s.type === "pre")  return appTheme.turbo
        if (s.type === "post") return appTheme.green
        return appTheme.blue
    }
    function typeLabel(s) {
        if (s.description && s.description.toLowerCase().indexOf("baseline") >= 0) return i18n.t("snap.baseline")
        if (s.type === "pre")  return i18n.t("snap.beforeUpdate")
        if (s.type === "post") return i18n.t("snap.afterUpdate")
        return i18n.t("snap.manual")
    }

    // ── background: subtle vertical gradient ───────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: appTheme.bgTop }
            GradientStop { position: 1.0; color: appTheme.bgBottom }
        }
    }

    // ── scroll body ────────────────────────────────────────────────
    QQC2.ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: win.width
            spacing: Kirigami.Units.largeSpacing

            // ── header ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: 0
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    width: 48; height: 48; radius: 8
                    color: appTheme.a(appTheme.green, 0.16)
                    border.width: 1; border.color: appTheme.a(appTheme.green, 0.34)
                    Kirigami.Icon {
                        anchors.centerIn: parent; width: 26; height: 26
                        source: "security-high"; color: appTheme.green
                    }
                }
                ColumnLayout {
                    spacing: 0
                    QQC2.Label {
                        text: "SYSTEM RECOVERY"
                        font.pixelSize: 9; font.bold: true
                        color: appTheme.accentText
                    }
                    QQC2.Label {
                        text: "Genesi Snapshots"
                        font.pixelSize: 22; font.bold: true
                        font.family: appTheme.display; color: appTheme.textHi
                    }
                    QQC2.Label {
                        text: i18n.t("snap.subtitle")
                        font.pixelSize: 12; color: appTheme.textLo
                    }
                }
                Item { Layout.fillWidth: true }

                GButton {
                    theme: appTheme; kind: "ghost"; text: i18n.code
                    tooltip: i18n.t("lang.tooltip"); onClicked: i18n.toggle()
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "view-refresh"
                    tooltip: i18n.t("snap.refresh"); enabled: !win.busy
                    onClicked: backend.refresh()
                }
            }

            // ── RECOVERY HERO: booted a read-only snapshot from GRUB ───────
            // The dead end for laypeople — dominates the window and offers the
            // single way out: promote this snapshot back to the real system.
            StudioCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.preferredHeight: recCol.implicitHeight + Kirigami.Units.largeSpacing * 3
                visible: win.inRecovery
                accent: appTheme.blue
                active: true
                wash: true

                ColumnLayout {
                    id: recCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing * 1.5
                    spacing: Kirigami.Units.largeSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing * 1.5

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            width: 76; height: 76; radius: 8
                            color: appTheme.a(appTheme.blue, 0.14)
                            border.width: 1; border.color: appTheme.a(appTheme.blue, 0.4)
                            Kirigami.Icon {
                                anchors.centerIn: parent; width: 42; height: 42
                                source: "clock"; color: appTheme.blue
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            QQC2.Label {
                                text: i18n.t("rec.title")
                                font.pixelSize: 22; font.bold: true
                                font.family: appTheme.display; color: appTheme.textHi
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: i18n.t("rec.body")
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13; color: appTheme.textMid
                            }
                            // which snapshot we're inside
                            Rectangle {
                                Layout.topMargin: 6
                                implicitWidth: recChip.implicitWidth + 20
                                implicitHeight: 28; radius: 7
                                color: appTheme.a(appTheme.blue, 0.14)
                                border.width: 1; border.color: appTheme.a(appTheme.blue, 0.4)
                                RowLayout {
                                    id: recChip; anchors.centerIn: parent; spacing: 6
                                    Kirigami.Icon { width: 13; height: 13; source: "document-open-recent"; color: appTheme.blue }
                                    QQC2.Label {
                                        text: i18n.t("rec.snapshot") + "  #" + win.rec.number
                                        font.pixelSize: 12; font.bold: true; color: appTheme.textHi
                                    }
                                }
                            }
                        }
                    }

                    // actions
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Item { Layout.fillWidth: true }
                        GButton {
                            theme: appTheme; kind: "ghost"; iconSource: "system-reboot"
                            text: i18n.t("rec.reboot"); enabled: !win.busy
                            onClicked: backend.reboot()
                        }
                        GButton {
                            theme: appTheme; kind: "filled"; accent: appTheme.blue
                            text: i18n.t("rec.restore"); iconSource: "edit-undo"
                            tooltip: i18n.t("rec.restoreTip")
                            enabled: !win.busy
                            onClicked: recConfirm.open()
                        }
                    }
                }
            }

            // ── HERO: protection status ────────────────────────────
            StudioCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.preferredHeight: heroCol.implicitHeight + Kirigami.Units.largeSpacing * 3
                visible: !win.inRecovery
                accent: win.protColor
                active: win.protectedOk
                wash: true

                RowLayout {
                    id: heroCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing * 1.5
                    spacing: Kirigami.Units.largeSpacing * 1.5

                    // big shield
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 76; height: 76; radius: 8
                        color: appTheme.a(win.protColor, 0.14)
                        border.width: 1; border.color: appTheme.a(win.protColor, 0.4)
                        Kirigami.Icon {
                            anchors.centerIn: parent; width: 42; height: 42
                            source: win.protectedOk ? "security-high"
                                  : (win.st.btrfs ? "security-medium" : "security-low")
                            color: win.protColor
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        QQC2.Label {
                            text: !win.st.btrfs ? i18n.t("snap.stUnavailable")
                                : (win.st.configured ? i18n.t("snap.stProtected")
                                                     : i18n.t("snap.stArming"))
                            font.pixelSize: 22; font.bold: true
                            font.family: appTheme.display; color: appTheme.textHi
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: !win.st.btrfs ? i18n.t("snap.stUnavailableSub")
                                : (win.st.configured ? i18n.t("snap.stProtectedSub")
                                                     : i18n.t("snap.stArmingSub"))
                            wrapMode: Text.WordWrap
                            font.pixelSize: 13; color: appTheme.textMid
                        }

                        // capability chips
                        RowLayout {
                            Layout.topMargin: 6
                            spacing: Kirigami.Units.smallSpacing
                            visible: win.st.btrfs

                            component Chip: Rectangle {
                                property string label: ""
                                property bool on: false
                                implicitWidth: chipRow.implicitWidth + 20
                                implicitHeight: 28; radius: 7
                                color: on ? appTheme.a(appTheme.green, 0.14) : appTheme.a(appTheme.textLo, 0.10)
                                border.width: 1
                                border.color: on ? appTheme.a(appTheme.green, 0.4) : appTheme.a(appTheme.textLo, 0.18)
                                RowLayout {
                                    id: chipRow; anchors.centerIn: parent; spacing: 6
                                    Kirigami.Icon {
                                        width: 13; height: 13
                                        source: on ? "checkmark" : "dialog-cancel"
                                        color: on ? appTheme.accentText : appTheme.textLo
                                    }
                                    QQC2.Label {
                                        text: label; font.pixelSize: 12; font.bold: true
                                        color: on ? appTheme.accentText : appTheme.textLo
                                    }
                                }
                            }
                            Chip { label: i18n.t("snap.capUpdate"); on: win.st.snapPac }
                            Chip { label: i18n.t("snap.capBoot");   on: win.st.grubBtrfs }
                            Chip { label: win.st.count + " " + i18n.t("snap.capPoints"); on: win.st.count > 0 }
                        }
                    }

                    // primary action
                    GButton {
                        Layout.alignment: Qt.AlignVCenter
                        theme: appTheme; kind: "filled"; accent: appTheme.green
                        text: i18n.t("snap.create"); iconSource: "list-add"
                        enabled: win.protectedOk && !win.busy
                        onClicked: createDialog.open()
                    }
                }
            }

            // ── banners ────────────────────────────────────────────
            // Suppressed in recovery: we are demonstrably on a Btrfs snapshot
            // there (the recovery card proves it), and a transient empty status
            // read must not flash a misleading "Root isn't Btrfs" over it.
            // The hero above already says this, in the same words. Two red
            // boxes stacked on each other saying "root is not Btrfs" is not
            // twice as clear; the remedy that used to live down here has moved
            // into the hero's subtitle, where the diagnosis already was.
            StatusBanner {
                theme: appTheme; accent: appTheme.red
                icon: "drive-harddisk"; visible: false
                title: i18n.t("snap.noBtrfsTitle"); body: i18n.t("snap.noBtrfsBody")
            }
            StatusBanner {
                theme: appTheme; accent: appTheme.turbo
                icon: "clock"; busy: win.busy
                visible: win.st.btrfs && !win.st.configured && !win.inRecovery
                title: i18n.t("snap.armingTitle"); body: i18n.t("snap.armingBody")
            }

            // ── timeline header ────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: win.protectedOk
                QQC2.Label {
                    text: i18n.t("snap.timeline")
                    font.pixelSize: 13; font.bold: true; color: appTheme.textMid
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: win.snaps.length + " RESTORE POINTS"
                    font.pixelSize: 10; font.bold: true; color: appTheme.textLo
                }
            }

            // In recovery the per-snapshot actions target the wrong subvolume,
            // so they're locked — the recovery card above is the way back.
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("rec.actionsLocked")
                wrapMode: Text.WordWrap
                font.pixelSize: 12; color: appTheme.textLo
                visible: win.inRecovery && win.protectedOk
            }

            // empty state
            QQC2.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing * 1.5
                horizontalAlignment: Text.AlignHCenter
                visible: win.protectedOk && win.snaps.length === 0
                text: i18n.t("snap.empty"); color: appTheme.textLo; font.pixelSize: 13
            }

            // ── snapshot list ──────────────────────────────────────
            Repeater {
                model: win.protectedOk ? win.snaps : []
                delegate: StudioCard {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                    Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                    Layout.preferredHeight: rowL.implicitHeight + Kirigami.Units.largeSpacing * 2
                    accent: win.typeColor(modelData)

                    RowLayout {
                        id: rowL
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        // number badge
                        Rectangle {
                            width: 48; height: 48; radius: 8
                            color: appTheme.a(win.typeColor(modelData), 0.14)
                            border.width: 1; border.color: appTheme.a(win.typeColor(modelData), 0.35)
                            Layout.alignment: Qt.AlignVCenter
                            QQC2.Label {
                                anchors.centerIn: parent
                                text: "#" + modelData.number
                                font.pixelSize: 14; font.bold: true
                                color: appTheme.textHi
                            }
                        }
                        // type dot + info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                spacing: 6
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: win.typeColor(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                QQC2.Label {
                                    text: win.typeLabel(modelData)
                                    font.pixelSize: 13; font.bold: true; color: appTheme.textHi
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: (modelData.description || "—") + "   ·   " + (modelData.date || "")
                                elide: Text.ElideRight
                                font.pixelSize: 12; color: appTheme.textLo
                            }
                        }
                        // actions
                        GButton {
                            theme: appTheme; kind: "tonal"; accent: appTheme.green
                            text: i18n.t("snap.restore"); iconSource: "edit-undo"
                            enabled: !win.busy && modelData.number > 0 && !win.inRecovery
                            tooltip: i18n.t("snap.restoreTip")
                            onClicked: { confirm.num = modelData.number; confirm.desc = modelData.description || ""; confirm.open() }
                        }
                        GButton {
                            theme: appTheme; kind: "danger"; iconSource: "user-trash"
                            enabled: !win.busy && modelData.number > 0 && !win.inRecovery
                            tooltip: i18n.t("snap.delete")
                            onClicked: backend.deleteSnapshot(modelData.number)
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing * 2 }
        }
    }

    // ── toast ──────────────────────────────────────────────────────
    Rectangle {
        visible: win.toast.length > 0
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Kirigami.Units.largeSpacing * 2
        width: toastLbl.implicitWidth + 40; height: 44; radius: 12
        color: appTheme.card; border.width: 1; border.color: appTheme.a(appTheme.green, 0.4)
        QQC2.Label {
            id: toastLbl; anchors.centerIn: parent
            text: win.toast; color: appTheme.textHi; font.pixelSize: 13
        }
    }

    // ── create dialog ──────────────────────────────────────────────
    QQC2.Popup {
        id: createDialog
        anchors.centerIn: parent
        modal: true; focus: true
        width: 420
        padding: 0
        background: StudioCard { accent: appTheme.green; active: true; interactive: false }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            anchors.margins: Kirigami.Units.largeSpacing * 1.5

            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
            QQC2.Label {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("snap.createTitle")
                font.pixelSize: 16; font.bold: true; color: appTheme.textHi
            }
            QQC2.TextField {
                id: descField
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                placeholderText: i18n.t("snap.createPlaceholder")
                color: appTheme.textHi
                selectByMouse: true
                background: Rectangle {
                    radius: 8; color: appTheme.cardHi
                    border.width: 1; border.color: descField.activeFocus ? appTheme.green : appTheme.line
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 1.5
                Item { Layout.fillWidth: true }
                GButton { theme: appTheme; kind: "ghost"; text: i18n.t("snap.cancel"); onClicked: createDialog.close() }
                GButton {
                    theme: appTheme; kind: "filled"; accent: appTheme.green
                    text: i18n.t("snap.create"); iconSource: "list-add"
                    onClicked: { backend.createSnapshot(descField.text); descField.text = ""; createDialog.close() }
                }
            }
        }
    }

    // ── rollback confirm ───────────────────────────────────────────
    QQC2.Popup {
        id: confirm
        property int num: 0
        property string desc: ""
        anchors.centerIn: parent
        modal: true; focus: true
        width: 460; padding: 0
        background: StudioCard { accent: appTheme.turbo; active: true; interactive: false }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
            RowLayout {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon { source: "edit-undo"; width: 28; height: 28; color: appTheme.turbo }
                QQC2.Label {
                    text: i18n.t("snap.rollbackTitle") + " #" + confirm.num
                    font.pixelSize: 16; font.bold: true; color: appTheme.textHi
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("snap.rollbackBody")
                wrapMode: Text.WordWrap; font.pixelSize: 13; color: appTheme.textMid
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 1.5
                Item { Layout.fillWidth: true }
                GButton { theme: appTheme; kind: "ghost"; text: i18n.t("snap.cancel"); onClicked: confirm.close() }
                GButton {
                    theme: appTheme; kind: "filled"; accent: appTheme.turbo
                    text: i18n.t("snap.rollbackConfirm"); iconSource: "edit-undo"
                    onClicked: { backend.rollback(confirm.num); confirm.close() }
                }
            }
        }
    }

    // ── recovery restore confirm ───────────────────────────────────
    QQC2.Popup {
        id: recConfirm
        anchors.centerIn: parent
        modal: true; focus: true
        width: 480; padding: 0
        background: StudioCard { accent: appTheme.blue; active: true; interactive: false }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
            RowLayout {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon { source: "edit-undo"; width: 28; height: 28; color: appTheme.blue }
                QQC2.Label {
                    text: i18n.t("rec.confirmTitle") + "  #" + win.rec.number
                    font.pixelSize: 16; font.bold: true; color: appTheme.textHi
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("rec.confirmBody")
                wrapMode: Text.WordWrap; font.pixelSize: 13; color: appTheme.textMid
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 1.5
                Item { Layout.fillWidth: true }
                GButton { theme: appTheme; kind: "ghost"; text: i18n.t("snap.cancel"); onClicked: recConfirm.close() }
                GButton {
                    theme: appTheme; kind: "filled"; accent: appTheme.blue
                    text: i18n.t("rec.confirmBtn"); iconSource: "edit-undo"
                    onClicked: { backend.restoreBooted(); recConfirm.close() }
                }
            }
        }
    }
}
