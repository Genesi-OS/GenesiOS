/*
 * Genesi Snapshots — the "indestructible OS" dashboard.
 *
 * A protection panel over the genesi-snapshots CLI (snapper + snap-pac +
 * grub-btrfs). The hero states, at a glance, whether the machine is protected;
 * the timeline lists every restore point; one click creates a manual snapshot,
 * rolls back, or deletes. Built on the shared Genesi UI kit (Theme/GlassCard/
 * GButton/StatusBanner/I18n) so it matches the AI Monitor / Sandboxes look.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: win
    visible: true
    width: 900; height: 700
    minimumWidth: 720; minimumHeight: 540
    title: "Genesi Snapshots"
    color: theme.bgBottom

    Theme { id: theme }
    I18n  { id: i18n }

    // ── state (driven by the backend) ──────────────────────────────
    property var  st: ({ btrfs: false, configured: false, snapPac: false, grubBtrfs: false, count: 0 })
    property var  snaps: []
    property bool busy: false
    property string toast: ""

    readonly property bool protectedOk: st.btrfs && st.configured
    readonly property color protColor: !st.btrfs ? theme.red
                                      : (st.configured ? theme.green : theme.turbo)

    Connections {
        target: backend
        function onStatusLoaded(s)    { try { win.st = JSON.parse(s) } catch (e) {} }
        function onSnapshotsLoaded(s) { try { win.snaps = (JSON.parse(s).snapshots) || [] } catch (e) {} }
        function onBusyChanged(b)     { win.busy = b }
        function onActionDone(m)      { win.toast = m; toastTimer.restart() }
        function onLogLine(l)         { console.log(l) }
    }
    Timer { id: toastTimer; interval: 4200; onTriggered: win.toast = "" }

    // Snapshot "type" → colour + label. snap-pac writes pre/post around each
    // pacman transaction; manual/baseline are 'single'.
    function typeColor(s) {
        if (s.type === "pre")  return theme.turbo
        if (s.type === "post") return theme.green
        return theme.blue
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
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
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
                    width: 44; height: 44; radius: 13
                    color: theme.a(theme.green, 0.16)
                    Kirigami.Icon {
                        anchors.centerIn: parent; width: 26; height: 26
                        source: "security-high"; color: theme.green
                    }
                }
                ColumnLayout {
                    spacing: 0
                    QQC2.Label {
                        text: "Genesi Snapshots"
                        font.pixelSize: 20; font.bold: true
                        font.family: theme.display; color: theme.textHi
                    }
                    QQC2.Label {
                        text: i18n.t("snap.subtitle")
                        font.pixelSize: 12; color: theme.textLo
                    }
                }
                Item { Layout.fillWidth: true }

                GButton {
                    theme: theme; kind: "ghost"; text: i18n.code
                    tooltip: i18n.t("lang.tooltip"); onClicked: i18n.toggle()
                }
                GButton {
                    theme: theme; kind: "ghost"; iconSource: "view-refresh"
                    tooltip: i18n.t("snap.refresh"); enabled: !win.busy
                    onClicked: backend.refresh()
                }
            }

            // ── HERO: protection status ────────────────────────────
            GlassCard {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.preferredHeight: heroCol.implicitHeight + Kirigami.Units.largeSpacing * 3
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
                        width: 84; height: 84; radius: 22
                        color: theme.a(win.protColor, 0.14)
                        border.width: 1; border.color: theme.a(win.protColor, 0.4)
                        Kirigami.Icon {
                            anchors.centerIn: parent; width: 46; height: 46
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
                            font.family: theme.display; color: theme.textHi
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: !win.st.btrfs ? i18n.t("snap.stUnavailableSub")
                                : (win.st.configured ? i18n.t("snap.stProtectedSub")
                                                     : i18n.t("snap.stArmingSub"))
                            wrapMode: Text.WordWrap
                            font.pixelSize: 13; color: theme.textMid
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
                                implicitHeight: 28; radius: 14
                                color: on ? theme.a(theme.green, 0.14) : theme.a(theme.textLo, 0.10)
                                border.width: 1
                                border.color: on ? theme.a(theme.green, 0.4) : theme.a(theme.textLo, 0.18)
                                RowLayout {
                                    id: chipRow; anchors.centerIn: parent; spacing: 6
                                    Kirigami.Icon {
                                        width: 13; height: 13
                                        source: on ? "checkmark" : "dialog-cancel"
                                        color: on ? theme.accentText : theme.textLo
                                    }
                                    QQC2.Label {
                                        text: label; font.pixelSize: 12; font.bold: true
                                        color: on ? theme.accentText : theme.textLo
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
                        theme: theme; kind: "filled"; accent: theme.green
                        text: i18n.t("snap.create"); iconSource: "list-add"
                        enabled: win.protectedOk && !win.busy
                        onClicked: createDialog.open()
                    }
                }
            }

            // ── banners ────────────────────────────────────────────
            StatusBanner {
                theme: theme; accent: theme.red
                icon: "drive-harddisk"; visible: !win.st.btrfs
                title: i18n.t("snap.noBtrfsTitle"); body: i18n.t("snap.noBtrfsBody")
            }
            StatusBanner {
                theme: theme; accent: theme.turbo
                icon: "clock"; busy: win.busy
                visible: win.st.btrfs && !win.st.configured
                title: i18n.t("snap.armingTitle"); body: i18n.t("snap.armingBody")
            }

            // ── timeline header ────────────────────────────────────
            QQC2.Label {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: i18n.t("snap.timeline")
                font.pixelSize: 13; font.bold: true; color: theme.textMid
                visible: win.protectedOk
            }

            // empty state
            QQC2.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing * 1.5
                horizontalAlignment: Text.AlignHCenter
                visible: win.protectedOk && win.snaps.length === 0
                text: i18n.t("snap.empty"); color: theme.textLo; font.pixelSize: 13
            }

            // ── snapshot list ──────────────────────────────────────
            Repeater {
                model: win.protectedOk ? win.snaps : []
                delegate: GlassCard {
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
                            width: 46; height: 46; radius: 12
                            color: theme.a(win.typeColor(modelData), 0.14)
                            border.width: 1; border.color: theme.a(win.typeColor(modelData), 0.35)
                            Layout.alignment: Qt.AlignVCenter
                            QQC2.Label {
                                anchors.centerIn: parent
                                text: "#" + modelData.number
                                font.pixelSize: 14; font.bold: true
                                color: theme.textHi
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
                                    font.pixelSize: 13; font.bold: true; color: theme.textHi
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: (modelData.description || "—") + "   ·   " + (modelData.date || "")
                                elide: Text.ElideRight
                                font.pixelSize: 12; color: theme.textLo
                            }
                        }
                        // actions
                        GButton {
                            theme: theme; kind: "tonal"; accent: theme.green
                            text: i18n.t("snap.restore"); iconSource: "edit-undo"
                            enabled: !win.busy
                            tooltip: i18n.t("snap.restoreTip")
                            onClicked: { confirm.num = modelData.number; confirm.desc = modelData.description || ""; confirm.open() }
                        }
                        GButton {
                            theme: theme; kind: "danger"; iconSource: "user-trash"
                            enabled: !win.busy
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
        color: theme.card; border.width: 1; border.color: theme.a(theme.green, 0.4)
        QQC2.Label {
            id: toastLbl; anchors.centerIn: parent
            text: win.toast; color: theme.textHi; font.pixelSize: 13
        }
    }

    // ── create dialog ──────────────────────────────────────────────
    QQC2.Popup {
        id: createDialog
        anchors.centerIn: parent
        modal: true; focus: true
        width: 420
        padding: 0
        background: GlassCard { accent: theme.green; active: true; interactive: false }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            anchors.margins: Kirigami.Units.largeSpacing * 1.5

            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
            QQC2.Label {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("snap.createTitle")
                font.pixelSize: 16; font.bold: true; color: theme.textHi
            }
            QQC2.TextField {
                id: descField
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                placeholderText: i18n.t("snap.createPlaceholder")
                color: theme.textHi
                selectByMouse: true
                background: Rectangle {
                    radius: 8; color: theme.cardHi
                    border.width: 1; border.color: descField.activeFocus ? theme.green : theme.line
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 1.5
                Item { Layout.fillWidth: true }
                GButton { theme: theme; kind: "ghost"; text: i18n.t("snap.cancel"); onClicked: createDialog.close() }
                GButton {
                    theme: theme; kind: "filled"; accent: theme.green
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
        background: GlassCard { accent: theme.turbo; active: true; interactive: false }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing
            Item { Layout.preferredHeight: Kirigami.Units.largeSpacing }
            RowLayout {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon { source: "edit-undo"; width: 28; height: 28; color: theme.turbo }
                QQC2.Label {
                    text: i18n.t("snap.rollbackTitle") + " #" + confirm.num
                    font.pixelSize: 16; font.bold: true; color: theme.textHi
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                text: i18n.t("snap.rollbackBody")
                wrapMode: Text.WordWrap; font.pixelSize: 13; color: theme.textMid
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.rightMargin: Kirigami.Units.largeSpacing * 1.5
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 1.5
                Item { Layout.fillWidth: true }
                GButton { theme: theme; kind: "ghost"; text: i18n.t("snap.cancel"); onClicked: confirm.close() }
                GButton {
                    theme: theme; kind: "filled"; accent: theme.turbo
                    text: i18n.t("snap.rollbackConfirm"); iconSource: "edit-undo"
                    onClicked: { backend.rollback(confirm.num); confirm.close() }
                }
            }
        }
    }
}
