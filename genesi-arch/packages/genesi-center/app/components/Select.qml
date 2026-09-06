/*
 * Select — one of many, from a list too long to show at once.
 *
 * ── Why the list is not a child of this item ─────────────────────────────────
 *
 * It used to be, with `z: 10`, and it was drawn UNDER the next row every time.
 * z only orders an item among its SIBLINGS: this control is 28px tall and
 * lives inside a row, inside a column, and every row after it is painted
 * later. No z inside a 28px box can put anything above a sibling of its
 * grandparent. On the Displays page the resolution list came out beneath the
 * scale and rotation buttons; on Appearance the two font lists came out
 * beneath each other.
 *
 * So the list is reparented to the top of the scene when it opens, and
 * positioned by mapping this item's corner into that space. That is the only
 * place in a QtQuick scene that is above everything, and it is also outside
 * every Flickable's clip -- a dropdown that opens near the bottom of a
 * scrolling page used to be cut off by the page's own edge.
 *
 * It flips ABOVE the field when there is not enough room below, for the same
 * reason: the last row of a long page is exactly where a resolution list is
 * most likely to be opened.
 */
import QtQuick
import ".."

Item {
    id: root

    property var options: []       // [{ id, label }]
    property string current: ""
    property int maxShown: 8
    signal picked(string id)

    implicitWidth: 210
    implicitHeight: 28

    readonly property bool open: list.visible

    function labelOf(id) {
        for (const o of root.options)
            if (o.id === id)
                return o.label;
        return id;
    }

    // The top of the scene: whatever has no parent left. Everything drawn by
    // the window is a descendant of it, so a child of it is above all of them.
    function sceneRoot() {
        let p = root;
        while (p.parent)
            p = p.parent;
        return p;
    }

    function openList() {
        const top = root.sceneRoot();
        if (!top)
            return;
        list.parent = top;

        const here = root.mapToItem(top, 0, 0);
        const below = top.height - (here.y + root.height) - 12;
        const wanted = list.wantedHeight;

        // Below if it fits, above if it does not. Whichever way, it stays
        // inside the scene rather than half off the bottom.
        list.width = root.width;
        list.height = Math.min(wanted, Math.max(below, here.y - 12));
        list.x = Math.max(6, Math.min(here.x, top.width - list.width - 6));
        list.y = (list.height <= below)
                 ? here.y + root.height + 4
                 : here.y - list.height - 4;
        list.visible = true;
    }

    function closeList() {
        list.visible = false;
    }

    // A control scrolled out from under an open list would leave the list
    // hanging over the page, so it closes when this item stops being visible.
    onVisibleChanged: if (!visible) closeList()

    Rectangle {
        id: field
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Tokens.card
        border.width: 1
        border.color: root.open ? Tokens.accentDim : Tokens.line
        Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

        Text {
            anchors {
                left: parent.left; leftMargin: 10
                right: caret.left; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            text: root.labelOf(root.current)
            color: Tokens.textHi
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
            elide: Text.ElideRight
        }
        Text {
            id: caret
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: root.open ? "▴" : "▾"
            color: Tokens.textDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fsMicro
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: root.open ? root.closeList() : root.openList()
        }
    }

    // ── The list, once it is opened ─────────────────────────────────────────
    //
    // Declared here so it reads with the control it belongs to, but reparented
    // on open. Until then it has no parent of its own and is not visible.
    Rectangle {
        id: list

        readonly property int rowHeight: 26
        readonly property int wantedHeight:
            Math.min(root.options.length, root.maxShown) * rowHeight + 8

        visible: false
        // Above every sibling of the scene root as well, for the case where
        // something else has already been parented there.
        z: 9999
        radius: Tokens.radiusSm
        color: Tokens.panel
        border.width: 1
        border.color: Tokens.accentDeep
        clip: true

        // Clicking anywhere else closes it. A full-scene catcher UNDER the
        // list, so the first click outside dismisses rather than landing on
        // whatever happened to be beneath.
        Item {
            id: catcher
            parent: list.parent ? list.parent : null
            anchors.fill: parent ? parent : undefined
            visible: list.visible
            z: list.z - 1
            MouseArea {
                anchors.fill: parent
                onPressed: root.closeList()
            }
        }

        ListView {
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            model: root.options
            currentIndex: {
                for (let i = 0; i < root.options.length; i++)
                    if (root.options[i].id === root.current)
                        return i;
                return -1;
            }
            // Open showing what is applied, not the top of a list of forty.
            Component.onCompleted: positionViewAtIndex(currentIndex, ListView.Center)

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: list.rowHeight
                radius: 3
                color: modelData.id === root.current ? Tokens.accentDeep
                                                     : (h.hovered ? Tokens.cardHi
                                                                  : "transparent")
                Text {
                    anchors {
                        left: parent.left; leftMargin: 8
                        right: parent.right; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.label
                    color: modelData.id === root.current ? Tokens.textHi : Tokens.text
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                    elide: Text.ElideRight
                }
                HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        root.picked(modelData.id);
                        root.closeList();
                    }
                }
            }
        }
    }
}
