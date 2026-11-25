// GENESI — right-click a widget and change it, right there.
//
//   DESIGN    glass, solid, outline, minimal
//   SIZE      drawn bigger, not stretched -- see GenesiWidgetCard
//   OPACITY
//   COLOUR    auto (the wallpaper's palette), one colour, or a gradient
//   SNAP      free, or one of nine places on the screen
//   Hide, Arrange, Settings
//
// It also edits caelestia's own desktop clock, which Genesi patches to open
// this on a right-click. That clock has different settings under the same
// questions -- a plate or not, inverted colours or not, a shadow -- so the
// same rows are shown with the clock's answers.
//
// ── Preview first, write on release ─────────────────────────────────────────
//
// Dragging a slider shows the change on the widget immediately, through
// GenesiWidgetEditState's preview, and writes shell.json once when the drag
// ends. A write per step would start a process per pixel of movement, and the
// widget would trail the thumb by a write and a reload.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher

Item {
    id: root

    required property var labels
    // Where a card of this size may go. See GenesiDesktopOverlay: the screen
    // is not the answer, because its last eighty pixels belong to caelestia's
    // drawers window and a button drawn there is never clicked.
    required property var place
    // For each widget's home anchor: a widget that was never moved has no
    // position in its config, and is still somewhere the grid should light.
    required property var defs
    signal arrangeRequested

    property string target: ""
    readonly property bool isClock: root.target === "desktopClock"
    readonly property var cfg: root.isClock ? Config.background.desktopClock : (root.target ? Config.background.widgets[root.target] : null)

    readonly property string home: {
        if (root.isClock)
            return "bottom-right";
        for (const d of root.defs)
            if (d.name === root.target)
                return d.home;
        return "";
    }

    // Which colour the picker is editing: 0 the first, 1 the second.
    property int slot: 0
    property bool pickerOpen: false

    anchors.fill: parent
    visible: card.opacity > 0

    function openFor(name: string, x: real, y: real): void {
        root.target = name;
        root.slot = 0;
        root.pickerOpen = false;
        card.wantX = x + 6;
        card.wantY = y + 6;
        card.opacity = 1;
        card.forceActiveFocus();
    }

    // Next to `r` rather than on it: right, left, below, above -- the first
    // side with room for the whole card.
    function openBeside(name: string, r: rect): void {
        const w = card.width, h = card.implicitHeight, gap = 12;
        let x = r.x + r.width + gap, y = r.y;
        if (x + w > root.width - 8) {
            x = r.x - w - gap;
            if (x < 8) {
                x = r.x;
                y = r.y + r.height + gap;
                if (y + h > root.height - 8)
                    y = r.y - h - gap;
            }
        }
        root.openFor(name, x - 6, y - 6);
    }

    function close(): void {
        card.opacity = 0;
        root.pickerOpen = false;
        // The preview is let go a moment AFTER the writes have had time to land
        // in the config, so the widget does not flick back to its old look for
        // the instant between the two.
        clearPreview.restart();
    }

    Timer {
        id: clearPreview

        interval: 1500
        onTriggered: if (card.opacity === 0) GenesiWidgetEditState.clear()
    }

    // ── Reading and writing ──────────────────────────────────────────────────
    function key(k: string): string {
        return root.isClock ? `background.desktopClock.${k}` : `background.widgets.${root.target}.${k}`;
    }

    function current(k: string, fallback: var): var {
        const c = root.cfg;
        let v = fallback;
        if (c) {
            // Dotted keys for the clock's nested settings.
            let o = c;
            for (const part of k.split(".")) {
                if (o === undefined || o === null)
                    break;
                o = o[part];
            }
            if (o !== undefined && o !== null)
                v = o;
        }
        return GenesiWidgetEditState.valueOf(root.target, k, v);
    }

    function preview(k: string, v: var): void {
        GenesiWidgetEditState.set(root.target, k, v);
    }

    function write(k: string, v: var): void {
        root.preview(k, v);
        Quickshell.execDetached(["genesi-center-set", "caelestia", root.key(k), String(v)]);
    }

    // ── Dismissal ────────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        enabled: card.opacity > 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.close()
    }

    StyledRect {
        id: card

        // Where it was asked to open. Kept, and clamped by a binding rather
        // than once, because the card grows after opening -- the colour picker
        // adds a third of its height -- and would otherwise run off the screen.
        property real wantX: 0
        property real wantY: 0

        readonly property point spot: root.place(width, height, wantX, wantY)

        x: spot.x
        y: spot.y
        width: 268
        implicitHeight: col.implicitHeight + 24
        height: implicitHeight
        radius: 18
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
        opacity: 0
        focus: true

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        Keys.onEscapePressed: root.close()

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        Column {
            id: col

            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10

            // ── Title ────────────────────────────────────────────────────────
            Row {
                spacing: 8

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: Qt.alpha(Colours.palette.m3primary, 0.16)

                    GenesiWIcon {
                        anchors.centerIn: parent
                        size: 17
                        fill: 1
                        text: "widgets"
                        color: Colours.palette.m3primary
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    GenesiWText {
                        size: 14
                        font.weight: Font.DemiBold
                        text: root.isClock ? qsTr("Clock") : (root.labels[root.target] ?? root.target)
                        color: Colours.palette.m3onSurface
                    }
                    GenesiWText {
                        size: 10
                        tracking: 1.2
                        text: qsTr("WIDGET")
                        color: Colours.palette.m3outline
                    }
                }
            }

            // ── Design ───────────────────────────────────────────────────────
            Section {
                title: qsTr("DESIGN")
            }
            Segments {
                full: parent.width
                options: root.isClock ? [
                    {
                        "id": true,
                        "label": qsTr("Plate")
                    },
                    {
                        "id": false,
                        "label": qsTr("Minimal")
                    }
                ] : [
                    {
                        "id": "glass",
                        "label": qsTr("Glass")
                    },
                    {
                        "id": "solid",
                        "label": qsTr("Solid")
                    },
                    {
                        "id": "outline",
                        "label": qsTr("Outline")
                    },
                    {
                        "id": "minimal",
                        "label": qsTr("Minimal")
                    }
                ]
                current: root.isClock ? root.current("background.enabled", false) : (root.current("style", "") || (Config.background.widgets.cards ? "glass" : "minimal"))
                onPicked: v => root.write(root.isClock ? "background.enabled" : "style", v)
            }

            // ── Size and opacity ─────────────────────────────────────────────
            Section {
                title: qsTr("ADJUST")
            }
            SliderRow {
                width: parent.width
                label: qsTr("Size")
                from: root.isClock ? 0.4 : 0.5
                to: 2.5
                value: root.current("scale", 1)
                shown: Math.round(value * 100) + "%"
                onMoved: v => root.preview("scale", Number(v.toFixed(2)))
                onReleased: v => root.write("scale", Number(v.toFixed(2)))
            }
            SliderRow {
                width: parent.width
                label: qsTr("Opacity")
                from: root.isClock ? 0 : 0.15
                to: 1
                value: root.isClock ? root.current("background.opacity", 0.7) : root.current("opacity", 1)
                shown: Math.round(value * 100) + "%"
                onMoved: v => root.preview(root.isClock ? "background.opacity" : "opacity", Number(v.toFixed(2)))
                onReleased: v => root.write(root.isClock ? "background.opacity" : "opacity", Number(v.toFixed(2)))
            }

            // ── Colour ───────────────────────────────────────────────────────
            Section {
                title: qsTr("COLOUR")
            }
            Segments {
                full: parent.width
                options: root.isClock ? [
                    {
                        "id": false,
                        "label": qsTr("Auto")
                    },
                    {
                        "id": true,
                        "label": qsTr("Inverted")
                    }
                ] : [
                    {
                        "id": "auto",
                        "label": qsTr("Auto")
                    },
                    {
                        "id": "solid",
                        "label": qsTr("Solid")
                    },
                    {
                        "id": "gradient",
                        "label": qsTr("Gradient")
                    }
                ]
                current: root.isClock ? root.current("invertColors", false) : root.current("colourMode", "auto")
                onPicked: v => {
                    root.write(root.isClock ? "invertColors" : "colourMode", v);
                    if (!root.isClock && v !== "auto") {
                        // A mode with no colour yet gets one, so choosing it
                        // visibly does something.
                        if (!/^#/.test(root.current("colour", "")))
                            root.write("colour", "#8fd6ab");
                        if (v === "gradient" && !/^#/.test(root.current("colour2", "")))
                            root.write("colour2", "#7cc6ff");
                        root.pickerOpen = true;
                    }
                }
            }

            Row {
                visible: !root.isClock && root.current("colourMode", "auto") !== "auto"
                spacing: 8

                Repeater {
                    model: root.current("colourMode", "auto") === "gradient" ? [0, 1] : [0]

                    Rectangle {
                        id: swatch

                        required property int modelData
                        readonly property bool active: root.pickerOpen && root.slot === swatch.modelData

                        width: 30
                        height: 30
                        radius: 9
                        color: root.current(swatch.modelData === 0 ? "colour" : "colour2", "#ffffff") || "#ffffff"
                        border.width: swatch.active ? 2 : 1
                        border.color: swatch.active ? Colours.palette.m3onSurface : Qt.rgba(1, 1, 1, 0.25)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.pickerOpen && root.slot === swatch.modelData)
                                    root.pickerOpen = false;
                                else {
                                    root.slot = swatch.modelData;
                                    root.pickerOpen = true;
                                }
                            }
                        }
                    }
                }
            }

            GenesiColourPicker {
                width: parent.width
                visible: root.pickerOpen && !root.isClock && root.current("colourMode", "auto") !== "auto"
                colour: root.current(root.slot === 0 ? "colour" : "colour2", "#8fd6ab") || "#8fd6ab"
                onPicked: hex => root.preview(root.slot === 0 ? "colour" : "colour2", hex)
                onCommitted: hex => root.write(root.slot === 0 ? "colour" : "colour2", hex)
            }

            // The clock's shadow is its own switch; the widgets have theirs in
            // the design.
            Segments {
                full: parent.width
                visible: root.isClock
                options: [
                    {
                        "id": true,
                        "label": qsTr("Shadow")
                    },
                    {
                        "id": false,
                        "label": qsTr("No shadow")
                    }
                ]
                current: root.current("shadow.enabled", true)
                onPicked: v => root.write("shadow.enabled", v)
            }

            // ── Snap ─────────────────────────────────────────────────────────
            Section {
                title: qsTr("SNAP")
            }
            Row {
                spacing: 10

                Grid {
                    columns: 3
                    spacing: 4

                    Repeater {
                        model: root.isClock ? ["top-left", "top-center", "top-right", "middle-left", "middle-center", "middle-right", "bottom-left", "bottom-center", "bottom-right"] : ["top-left", "top-centre", "top-right", "mid-left", "centre", "mid-right", "bottom-left", "bottom-centre", "bottom-right"]

                        Rectangle {
                            id: cell

                            required property string modelData
                            required property int index
                            readonly property bool on: (root.current("position", "") || root.home) === cell.modelData

                            width: 34
                            height: 26
                            radius: 7
                            color: cell.on ? Qt.alpha(Colours.palette.m3primary, 0.25) : (cellArea.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh)
                            border.width: cell.on ? 1 : 0
                            border.color: Colours.palette.m3primary

                            GenesiWIcon {
                                anchors.centerIn: parent
                                size: 15
                                text: ["north_west", "north", "north_east", "west", "adjust", "east", "south_west", "south", "south_east"][cell.index]
                                color: cell.on ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            }

                            MouseArea {
                                id: cellArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.write("position", cell.modelData)
                            }
                        }
                    }
                }

                Column {
                    spacing: 6

                    Rectangle {
                        width: 88
                        height: 26
                        radius: 7
                        readonly property bool on: root.current("position", root.home) === "free"
                        color: on ? Qt.alpha(Colours.palette.m3primary, 0.25) : Colours.palette.m3surfaceContainerHigh
                        border.width: on ? 1 : 0
                        border.color: Colours.palette.m3primary

                        GenesiWText {
                            anchors.centerIn: parent
                            size: 12
                            text: qsTr("Free")
                            color: Colours.palette.m3onSurface
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close();
                                root.arrangeRequested();
                            }
                        }
                    }
                    GenesiWText {
                        width: 88
                        size: 10
                        wrapMode: Text.WordWrap
                        text: qsTr("Drag it anywhere")
                        color: Colours.palette.m3outline
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
            }

            Action {
                width: parent.width
                icon: "visibility_off"
                text: qsTr("Hide")
                onTriggered: {
                    root.write("enabled", false);
                    root.close();
                }
            }
            Action {
                width: parent.width
                icon: "settings"
                text: qsTr("Settings")
                onTriggered: {
                    Quickshell.execDetached(["genesi-center"]);
                    root.close();
                }
            }
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────
    component Section: GenesiWText {
        property string title: ""

        size: 10
        tracking: 1.6
        font.weight: Font.DemiBold
        text: title
        color: Colours.palette.m3outline
    }

    component Segments: Row {
        id: seg

        property var options: []
        property var current
        // Set where it is used. An inline component cannot reach the ids of
        // the file around it, so `col.width` in here is a load error.
        property real full: 240
        signal picked(var value)

        spacing: 4

        Repeater {
            model: seg.options

            Rectangle {
                id: opt

                required property var modelData
                readonly property bool on: seg.current === opt.modelData.id

                width: (seg.full - 4 * (seg.options.length - 1)) / Math.max(1, seg.options.length)
                height: 28
                radius: 8
                color: opt.on ? Colours.palette.m3primary : (optArea.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh)

                GenesiWText {
                    anchors.centerIn: parent
                    size: 12
                    font.weight: opt.on ? Font.DemiBold : Font.Normal
                    text: opt.modelData.label
                    color: opt.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                }

                MouseArea {
                    id: optArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.id)
                }
            }
        }
    }

    component SliderRow: Item {
        id: sl

        property string label: ""
        property real from: 0
        property real to: 1
        property real value: 0
        property string shown: ""
        signal moved(real value)
        signal released(real value)

        // While dragging, the thumb follows the pointer rather than the bound
        // value, which only catches up once the preview lands.
        property real live: sl.value
        readonly property real frac: (sl.live - sl.from) / Math.max(0.0001, sl.to - sl.from)

        onValueChanged: if (!drag.pressed) sl.live = sl.value

        height: 28

        GenesiWText {
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            size: 13
            text: sl.label
            color: Colours.palette.m3onSurface
        }

        Item {
            id: track

            anchors.left: parent.left
            anchors.leftMargin: 60
            anchors.right: pct.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 20

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Colours.palette.m3surfaceContainerHighest

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, sl.frac))
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary
                }
            }

            Rectangle {
                x: parent.width * Math.max(0, Math.min(1, sl.frac)) - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: Colours.palette.m3primary
                border.width: 3
                border.color: Colours.palette.m3surfaceContainer
            }

            MouseArea {
                id: drag

                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                function at(mx: real): void {
                    const f = Math.max(0, Math.min(1, (mx - 6) / Math.max(1, track.width)));
                    sl.live = sl.from + f * (sl.to - sl.from);
                    sl.moved(sl.live);
                }
                onPressed: e => drag.at(e.x)
                onPositionChanged: e => drag.at(e.x)
                onReleased: sl.released(sl.live)
            }
        }

        GenesiWText {
            id: pct

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            horizontalAlignment: Text.AlignRight
            size: 12
            text: sl.shown
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    component Action: Rectangle {
        id: act

        property string icon: ""
        property string text: ""
        signal triggered

        height: 32
        radius: 8
        color: actArea.containsMouse ? Colours.palette.m3surfaceContainerHighest : "transparent"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            GenesiWIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: 17
                text: act.icon
                color: Colours.palette.m3onSurfaceVariant
            }
            GenesiWText {
                anchors.verticalCenter: parent.verticalCenter
                size: 13
                text: act.text
                color: Colours.palette.m3onSurface
            }
        }

        MouseArea {
            id: actArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.triggered()
        }
    }
}
