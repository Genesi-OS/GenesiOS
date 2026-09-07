// GENESI — the launcher's results, in numbered columns.
//
// Upstream's AppList is a ListView, and a ListView has one column by
// construction. Rather than fight that, this is a Repeater over a fixed window
// of the results laid out in a Grid: the launcher already caps what it shows at
// `maxShown`, so there is never anything to scroll to, and a positioner that
// draws exactly the rows it shows is simpler than a view that virtualises rows
// nobody will reach.
//
// The numbers are not decoration either. Two columns of names with nothing
// between them read as two unrelated lists; numbering them 01..08 across the
// rows is what says "this is ONE ranked list that happens to fold".
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property StyledTextField search
    required property DrawerVisibilities visibilities
    property int columns: 2
    property int rounding: Tokens.rounding.large

    // Every match, in order. `Apps.search("")` is the full list, which is what
    // the launcher shows before anything is typed.
    readonly property var entries: Apps.search(root.search.text)
    readonly property int count: entries.length
    // `maxShown` counts ROWS here, not results. It is the number of lines the
    // launcher is allowed to grow to, and that meaning has to survive the second
    // column -- otherwise turning columns on silently halves the list for
    // everyone who had set it.
    readonly property int shown: Math.min(root.count, Math.max(1, Config.launcher.maxShown) * root.columns)

    property int currentIndex: 0
    readonly property var currentEntry: root.shown > 0 && root.currentIndex < root.shown ? root.entries[root.currentIndex] : null

    readonly property int cellHeight: Tokens.sizes.launcher.itemHeight
    readonly property real cellWidth: root.columns > 0 ? (width - (root.columns - 1) * Tokens.spacing.small) / root.columns : width

    implicitHeight: grid.implicitHeight

    // A new query re-ranks everything, so the old index points at a different
    // application. Nothing is more surprising than typing three letters and
    // launching whatever happened to land on row four.
    onEntriesChanged: currentIndex = 0
    onColumnsChanged: currentIndex = Math.min(currentIndex, Math.max(0, shown - 1))

    function moveBy(by: int): void {
        if (root.shown === 0)
            return;
        // Clamped, not wrapped. Wrapping means Down at the bottom of the list
        // silently puts the selection back at the top, and the next Enter opens
        // the wrong thing -- which is the failure people notice by launching it.
        root.currentIndex = Math.max(0, Math.min(root.shown - 1, root.currentIndex + by));
    }

    function activateCurrent(): void {
        const entry = root.currentEntry;
        if (!entry)
            return;
        Apps.launch(entry);
        root.visibilities.launcher = false;
    }

    Grid {
        id: grid

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        columns: root.columns
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.small

        Repeater {
            model: root.shown

            Item {
                id: cell

                required property int index
                readonly property var entry: root.entries[cell.index] ?? null
                readonly property bool on: root.currentIndex === cell.index

                width: root.cellWidth
                height: root.cellHeight

                StyledRect {
                    anchors.fill: parent
                    radius: root.rounding
                    color: Colours.palette.m3onSurface
                    opacity: cell.on ? 0.08 : 0

                    Behavior on opacity {
                        Anim {}
                    }
                }

                StateLayer {
                    radius: root.rounding
                    // Its own hover wash is off. Hovering MOVES the selection,
                    // and the selection already draws one -- leaving both on
                    // stacks two 8% layers on the hovered row and makes it a
                    // different colour from the row the arrow keys select.
                    stateOpacity: 0
                    // Two lit rows and one Enter key is a launcher that looks
                    // like it is about to open the wrong thing.
                    onEntered: root.currentIndex = cell.index
                    onClicked: {
                        root.currentIndex = cell.index;
                        root.activateCurrent();
                    }
                }

                StyledText {
                    id: number

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter

                    text: (cell.index + 1 < 10 ? "0" : "") + (cell.index + 1)
                    font: Tokens.font.label.small
                    color: cell.on ? Colours.palette.m3primary : Colours.palette.m3outline

                    Behavior on color {
                        CAnim {}
                    }
                }

                IconImage {
                    id: icon

                    anchors.left: number.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter

                    asynchronous: true
                    implicitSize: Math.round(root.cellHeight * 0.55)
                    source: Quickshell.iconPath(cell.entry?.icon, "image-missing")
                }

                Column {
                    anchors.left: icon.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        width: parent.width
                        text: cell.entry?.name ?? ""
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        // The category, not the comment. A comment is a sentence
                        // and there is no room for one beside a second column;
                        // "APP" under the name is what the reference layout puts
                        // there, and it is the part that stays true at any width.
                        text: qsTr("APP")
                        font: Tokens.font.label.small
                        color: Colours.palette.m3outline
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Nothing matched. Upstream draws this inside its list; here the list is a
    // positioner with no rows, so it has to be its own item or the panel simply
    // loses its bottom half and looks broken rather than empty.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.large
        spacing: Tokens.spacing.medium
        visible: root.shown === 0

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: qsTr("No results")
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                text: qsTr("Try searching for something else")
                font: Tokens.font.body.medium
                color: Colours.palette.m3outline
            }
        }
    }
}
