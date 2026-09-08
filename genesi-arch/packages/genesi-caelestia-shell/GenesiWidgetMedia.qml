// GENESI desktop widget: what is playing
//
// Art, title, artist and how far through it is. Hidden entirely when nothing
// is playing: a media widget reading Nothing is a hole in the wallpaper,
// and the wallpaper is what people wanted to look at.
pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Quickshell.Widgets
import qs.components
import qs.services

GenesiWidgetCard {
    id: root

    readonly property var player: Players.active

    visible: !!root.player && !!root.player.trackTitle
    // An invisible item still takes its place in the column that holds it, so
    // the space has to go as well or the corner keeps a gap where the music was.
    height: visible ? implicitHeight : 0

    Row {
        spacing: Tokens.spacing.large

        ClippingRectangle {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 56
            implicitHeight: 56
            radius: Tokens.rounding.small
            color: Colours.palette.m3surfaceContainerHigh

            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: !parent.children[0].visible
                text: "music_note"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            StyledText {
                width: 200
                text: root.player?.trackTitle ?? ""
                font: Tokens.font.body.large
                color: Colours.palette.m3onSurface
                elide: Text.ElideRight
            }
            StyledText {
                width: 200
                text: root.player?.trackArtist ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            StyledRect {
                implicitWidth: 200
                implicitHeight: 4
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest

                StyledRect {
                    // Guarded against a zero length: a track that has not
                    // reported one yet would make this NaN, and a NaN width is
                    // a bar that vanishes rather than one that is empty.
                    width: {
                        const len = root.player?.length ?? 0;
                        if (len <= 0)
                            return 0;
                        return parent.width * Math.max(0, Math.min(1, (root.player?.position ?? 0) / len));
                    }
                    height: parent.height
                    radius: parent.radius
                    color: Colours.palette.m3primary
                }
            }
        }
    }
}
