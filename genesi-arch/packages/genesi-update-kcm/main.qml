/*
 * The Genesi update page, inside Plasma's System Settings.
 *
 * Written in Kirigami — Plasma's own design language — for the same reason the
 * caelestia page was written in caelestia's: a settings page that looks like it
 * came from somewhere else reads as a patch stitched on, however good it is on
 * its own. Genesi's identity lives in its apps; here the job is to belong.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    implicitWidth: Kirigami.Units.gridUnit * 32
    implicitHeight: Kirigami.Units.gridUnit * 28

    Kirigami.InlineMessage {
        id: result

        Layout.fillWidth: true
        showCloseButton: true
        position: Kirigami.InlineMessage.Position.Header
    }

    Connections {
        target: kcm

        function onApplyFinished(rc, message) {
            result.text = message;
            // 126/127 is pkexec's cancel. Painting that red would teach people
            // that red means "you clicked away", and then red stops meaning
            // anything on the day it should.
            result.type = rc === 0 || rc === 2 || rc === 126 || rc === 127
                ? Kirigami.MessageType.Positive
                : Kirigami.MessageType.Error;
            result.visible = true;
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ── The answer, before any of the detail ─────────────────────────────
        Kirigami.AbstractCard {
            Layout.fillWidth: true

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                    source: {
                        if (kcm.busy)
                            return "view-refresh";
                        if (kcm.updateState === "available")
                            return "system-software-update";
                        if (kcm.updateState === "error")
                            return "network-offline";
                        return "checkmark";
                    }
                }

                Kirigami.Heading {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    level: 1
                    text: {
                        if (kcm.busy && kcm.updateState === "checking")
                            return i18n("Checking…");
                        if (kcm.busy)
                            return i18n("Updating…");
                        if (kcm.updateState === "error")
                            return i18n("Could not check");
                        if (kcm.updateState === "available")
                            return kcm.packages.length === 1
                                ? i18n("1 update available")
                                : i18n("%1 updates available", kcm.packages.length);
                        return i18n("Up to date");
                    }
                }

                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: {
                        if (kcm.busy && kcm.updateState !== "checking")
                            return i18n("This can take a few minutes. It is safe to keep using the system.");
                        if (kcm.updateState === "error")
                            return i18n("This is usually the network or a mirror being down, not your system.");
                        // The reassuring half of an update is being able to undo
                        // it, and this machine can — it just never said so.
                        if (kcm.updateState === "available" && kcm.canRollback)
                            return i18n("A restore point is taken before and after, so this can be undone.");
                        if (kcm.lastUpdate)
                            return i18n("Last updated %1", kcm.lastUpdate);
                        return "";
                    }
                }

                QQC2.Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    enabled: !kcm.busy
                    icon.name: kcm.updateState === "available" ? "install" : "view-refresh"
                    text: kcm.updateState === "available" ? i18n("Update now") : i18n("Check again")
                    onClicked: {
                        result.visible = false;
                        if (kcm.updateState === "available")
                            kcm.applyUpdates();
                        else
                            kcm.checkUpdates();
                    }
                }
            }
        }

        // ── What actually changes ────────────────────────────────────────────
        //
        // A list, not a count. "47 updates" tells a user nothing they can act
        // on; a package name they recognise does.
        Kirigami.Heading {
            visible: kcm.updateState === "available" && !kcm.busy
            level: 3
            text: i18n("What changes")
        }

        Repeater {
            model: kcm.updateState === "available" && !kcm.busy ? kcm.packages : []

            Kirigami.BasicListItem {
                required property var modelData

                Layout.fillWidth: true
                separatorVisible: false
                hoverEnabled: false
                text: modelData.name
                subtitle: modelData.from && modelData.to
                    ? `${modelData.from}  →  ${modelData.to}`
                    : (modelData.from ?? "")
            }
        }

        // ── Live output, so nobody stares at a frozen dialog ─────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 10
            visible: kcm.log.length > 0

            QQC2.TextArea {
                readOnly: true
                wrapMode: TextEdit.Wrap
                font.family: "monospace"
                text: kcm.log
                // Follow the tail: an update log the user has to scroll is a
                // log they will not read.
                onTextChanged: cursorPosition = length
            }
        }

        // ── The context around the update ────────────────────────────────────
        Kirigami.Heading {
            level: 3
            text: i18n("System")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Kirigami.FormData.label: i18n("Update channel:")
                text: kcm.channel ? kcm.channel : "—"
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Last update:")
                text: kcm.lastUpdate ? kcm.lastUpdate : "—"
            }

            QQC2.Label {
                Kirigami.FormData.label: i18n("Restore point:")
                text: kcm.canRollback
                    ? i18n("Taken automatically before and after every update")
                    : i18n("Not available: the root filesystem is not Btrfs")
            }
        }
    }
}
