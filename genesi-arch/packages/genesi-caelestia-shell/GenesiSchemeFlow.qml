// GENESI — the colour schemes, fanned out.
//
// A colour scheme is the one setting whose value IS a picture, and upstream's
// scheme mode is a list of names with a two-tone dot beside each. That dot is
// two of the twenty-odd colours a scheme defines, which is enough to tell
// catppuccin from gruvbox and not enough to choose between four catppuccins.
//
// So each scheme is a CARD PAINTED IN ITS OWN COLOURS -- its surface as the
// ground, its onSurface as the ink, a title bar in its container colour, and
// its text, primary, tertiary, secondary and error as five swatches. You pick
// the one that looks right, which is how anybody has ever picked one.
//
// The fan is a PathView, the same component upstream's wallpaper picker uses,
// so this is the house's own mechanism rather than an import. The path carries
// scale, rotation and z as attributes: the centre card is upright, forward and
// full size; its neighbours tilt away, drop, and fall behind.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

PathView {
    id: root

    // Both optional, because this fan now has two homes: inside the launcher
    // panel, where it borrows the launcher's text field and closes the
    // launcher when you pick something -- and on a window of its own covering
    // the screen, where there is no launcher to borrow from or to close.
    property StyledTextField search: null
    property DrawerVisibilities visibilities: null

    // What to filter by when there is no `search` field to read. The searcher
    // strips the `>scheme ` prefix itself, so it has to be put back on.
    property string filter: ""

    // Settable, because the whole point of the full-screen picker is cards big
    // enough to judge a colour scheme from across the room.
    property int cardWidth: 172
    property int cardHeight: 236
    // How far in from each end the fan starts. Inside a panel the ends must
    // stay clear of a visible rounded edge; across a whole screen the fan is
    // supposed to run off both sides, which is what "edge to edge" means.
    property real edgeInset: cardWidth / 2

    // Emitted after a scheme is applied, so the full-screen window can close
    // itself. Inside the launcher nothing listens: `visibilities` already did
    // the closing.
    signal applied

    // Room for the tilt: a rotated card's corners reach outside the box the
    // upright one occupies, and a PathView does not grow to fit them.
    implicitHeight: cardHeight + 44

    // A plain array, not a ScriptModel. Upstream reaches for ScriptModel so a
    // keystroke diffs the list instead of rebuilding it, which matters for a
    // list of every application on the machine. This is at most a couple of
    // dozen cards that somebody opens, looks at and picks from, and a plain
    // array is a type Qt itself can resolve -- which is what lets this file be
    // rendered and checked outside Quickshell at all.
    readonly property var entries: Schemes.query(
        root.search ? root.search.text
                    : `${Config.launcher.actionPrefix}scheme ${root.filter}`)

    model: entries

    // Land on the scheme in use when nothing is typed, so the fan opens where
    // you already are rather than at whatever sorts first. Typing re-ranks, and
    // then the top match is the right place to be.
    onEntriesChanged: {
        const cur = Schemes.currentScheme;
        const at = root.entries.findIndex(s => `${s.name} ${s.flavour}` === cur);
        root.currentIndex = at >= 0 ? at : 0;
    }

    pathItemCount: 9
    cacheItemCount: 4
    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange

    // Applying it is two lines of CLI, written out rather than routed through
    // upstream's `Scheme.onClicked(list: AppList)`, which wants upstream's own
    // list object by type. Unlike the action list -- where the handler reaches
    // into `list.search.text` and copying it would mean owning its behaviour --
    // this one only closes the launcher and shells out, and `caelestia scheme
    // set -n X -f Y` is a documented command rather than an internal.
    function activateCurrent(): void {
        const s = root.currentItem?.modelData;
        if (!s)
            return;
        if (root.visibilities)
            root.visibilities.launcher = false;
        Quickshell.execDetached(["caelestia", "scheme", "set",
                                 "-n", s.name, "-f", s.flavour]);
        root.applied();
    }

    delegate: Item {
        id: card

        required property Schemes.Scheme modelData
        // The delegate's place in the model.
        //
        // NOT `PathView.itemIndex`, which is what this used to read and which
        // does not exist -- that attached property belongs to Repeater. It
        // came back undefined, so "am I the middle card" was `number ===
        // undefined` and therefore false for every card, and the else branch
        // assigned undefined to currentIndex. Clicking a card in the fan did
        // nothing at all; only Enter ever applied a scheme.
        required property int index

        // The scheme's colours arrive as bare hex with no leading "#", the way
        // caelestia's own SchemeItem takes them.
        function hex(key: string, fallback: string): color {
            const v = card.modelData?.colours?.[key];
            return v ? `#${v}` : fallback;
        }

        readonly property bool on: `${card.modelData?.name} ${card.modelData?.flavour}` === Schemes.currentScheme

        width: root.cardWidth
        height: root.cardHeight

        z: card.PathView.z ?? 0
        scale: card.PathView.s ?? 1
        rotation: card.PathView.r ?? 0

        Behavior on scale {
            Anim {}
        }
        Behavior on rotation {
            Anim {}
        }

        StyledRect {
            id: face

            anchors.fill: parent
            radius: Tokens.rounding.large
            color: card.hex("surface", Colours.palette.m3surface)
            border.width: card.on ? 2 : 1
            border.color: card.on ? card.hex("primary", Colours.palette.m3primary)
                                  : Qt.alpha(card.hex("outline", Colours.palette.m3outline), 0.5)

            Column {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: card.modelData?.flavour === "default"
                          ? (card.modelData?.name ?? "")
                          : `${card.modelData?.name ?? ""} ${card.modelData?.flavour ?? ""}`
                    font: Tokens.font.body.medium
                    color: card.hex("onSurface", Colours.palette.m3onSurface)
                    elide: Text.ElideRight
                }

                // The title bar of an imaginary window. It is what says these
                // colours are meant to be used TOGETHER, rather than merely to
                // sit next to each other in a row.
                //
                // Sized as a FRACTION of the card, because the card has two
                // sizes now. A 24px bar on a 460px full-screen card is a line,
                // not a title bar.
                StyledRect {
                    width: parent.width
                    implicitHeight: Math.round(root.cardHeight * 0.102)
                    radius: Tokens.rounding.small
                    color: card.hex("surfaceContainerHigh",
                                    card.hex("surfaceContainer", Colours.palette.m3surfaceContainer))

                    StyledRect {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: Math.round(root.cardWidth * 0.163)
                        implicitHeight: Math.round(root.cardHeight * 0.034)
                        radius: Tokens.rounding.full
                        color: card.hex("primary", Colours.palette.m3primary)
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        StyledRect {
                            implicitWidth: Math.round(root.cardHeight * 0.03)
                            implicitHeight: Math.round(root.cardHeight * 0.03)
                            radius: Tokens.rounding.full
                            color: card.hex("tertiary", Colours.palette.m3tertiary)
                        }
                        StyledRect {
                            implicitWidth: Math.round(root.cardHeight * 0.03)
                            implicitHeight: Math.round(root.cardHeight * 0.03)
                            radius: Tokens.rounding.full
                            color: card.hex("secondary", Colours.palette.m3secondary)
                        }
                        StyledRect {
                            implicitWidth: Math.round(root.cardHeight * 0.03)
                            implicitHeight: Math.round(root.cardHeight * 0.03)
                            radius: Tokens.rounding.full
                            color: card.hex("error", Colours.palette.m3error)
                        }
                    }
                }

                Row {
                    id: swatch

                    width: parent.width
                    height: parent.height - y
                    spacing: 6

                    readonly property real barWidth: (width - spacing * 4) / 5

                    StyledRect {
                        width: swatch.barWidth
                        height: parent.height
                        radius: width / 2
                        color: card.hex("onSurface", Colours.palette.m3onSurface)
                    }
                    StyledRect {
                        width: swatch.barWidth
                        height: parent.height
                        radius: width / 2
                        color: card.hex("primary", Colours.palette.m3primary)
                    }
                    StyledRect {
                        width: swatch.barWidth
                        height: parent.height
                        radius: width / 2
                        color: card.hex("tertiary", Colours.palette.m3tertiary)
                    }
                    StyledRect {
                        width: swatch.barWidth
                        height: parent.height
                        radius: width / 2
                        color: card.hex("secondary", Colours.palette.m3secondary)
                    }
                    StyledRect {
                        width: swatch.barWidth
                        height: parent.height
                        radius: width / 2
                        color: card.hex("error", Colours.palette.m3error)
                    }
                }
            }
        }

        StateLayer {
            radius: face.radius
            // A click on a card off to the side BRINGS IT TO THE MIDDLE first.
            // Applying a scheme from the edge of the fan, where the card is
            // tilted and half behind its neighbour, is a misclick waiting to
            // happen -- and this one repaints the entire desktop.
            onClicked: {
                if (root.currentIndex === card.index)
                    root.activateCurrent();
                else
                    root.currentIndex = card.index;
            }
        }
    }

    // Inset by `edgeInset` at each end. Inside the launcher that is half a
    // card, because the panel has a visible rounded edge and a card hanging
    // over it onto the desktop reads as a bug rather than as a flourish. On a
    // window of its own there is no edge to respect, the inset goes to zero,
    // and the fan runs off both sides of the screen the way the reference does.
    path: Path {
        startX: root.edgeInset
        startY: root.height / 2 + 26

        PathAttribute {
            name: "s"
            value: 0.72
        }
        PathAttribute {
            name: "r"
            value: -13
        }
        PathAttribute {
            name: "z"
            value: 0
        }

        PathLine {
            x: root.width / 2
            y: root.height / 2 - 10
        }

        PathAttribute {
            name: "s"
            value: 1.06
        }
        PathAttribute {
            name: "r"
            value: 0
        }
        PathAttribute {
            name: "z"
            value: 20
        }

        PathLine {
            x: root.width - root.edgeInset
            y: root.height / 2 + 26
        }

        PathAttribute {
            name: "s"
            value: 0.72
        }
        PathAttribute {
            name: "r"
            value: 13
        }
        PathAttribute {
            name: "z"
            value: 0
        }
    }
}
