/*
 * BarContent — everything the Genesi bar draws, and nothing about where it
 * lives.
 *
 * This file is plain QtQuick on purpose. The Quickshell half — the panel
 * window, the layer-shell anchors, the Hyprland IPC, the system tray — is in
 * shell.qml, and it hands this component data. That split is not tidiness:
 * Quickshell cannot be rendered offscreen on the machine this is written on, so
 * a bar built as one file would be the first thing here shipped without anyone
 * having looked at it. Split like this, the whole visual layer renders with stub
 * data and gets reviewed like every other page.
 *
 * The layout is the one every horizontal bar converges on, and for a reason:
 * three blocks, left / centre / right, each independently sized. A single row
 * with spacers cannot keep the centre centred when the sides are different
 * widths — the clock drifts as the window title changes, which is the tell of a
 * bar built out of a Row.
 */
import QtQuick
import "components"

Item {
    id: root

    // Everything is fed in. The bar never reads the system itself.
    property var workspaces: []        // [{ id, occupied, active, windows }]
    property string activeWindow: ""
    property string clockText: "--:--"
    property string dateText: ""
    property var trayItems: []         // [{ id, icon, tooltip }]
    property var status: ({})          // { volume, mic, network, battery, ... }

    property int barHeight: 34
    property int gap: 14

    signal activated(string what, var arg)

    implicitHeight: barHeight

    // ── Left ─────────────────────────────────────────────────────────────────
    Row {
        id: left
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: root.gap

        BarButton {
            mark: true
            onActivated: root.activated("logo", null)
        }

        Workspaces {
            workspaces: root.workspaces
            anchors.verticalCenter: parent.verticalCenter
            onPicked: id => root.activated("workspace", id)
        }
    }

    // ── Centre ───────────────────────────────────────────────────────────────
    //
    // Anchored to the bar's centre, not placed between the blocks. Placed, it
    // would move whenever the left or right block changed width -- and the left
    // block changes width every time a workspace gains a window.
    Item {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - left.width - right.width - 80)
        implicitWidth: title.implicitWidth
        height: parent.height
        clip: true

        BarLabel {
            id: title
            anchors.centerIn: parent
            text: root.activeWindow
            dim: true
        }
    }

    // ── Right ────────────────────────────────────────────────────────────────
    Row {
        id: right
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: root.gap

        Tray {
            items: root.trayItems
            anchors.verticalCenter: parent.verticalCenter
            onPicked: id => root.activated("tray", id)
        }

        StatusCluster {
            status: root.status
            anchors.verticalCenter: parent.verticalCenter
            onActivated: what => root.activated(what, null)
        }

        Clock {
            time: root.clockText
            date: root.dateText
            anchors.verticalCenter: parent.verticalCenter
            onActivated: root.activated("calendar", null)
        }

        BarButton {
            glyph: "⏻"
            onActivated: root.activated("session", null)
        }
    }
}
