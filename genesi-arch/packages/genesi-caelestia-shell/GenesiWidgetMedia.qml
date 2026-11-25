// GENESI desktop widget: what is playing.
//
// The cover is the widget. It is shown large, and a blurred copy of it glows
// through behind the whole card, so the widget takes on the colours of the
// record instead of the wallpaper's.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.services

GenesiWidgetCard {
    id: w

    readonly property var player: Players.active
    readonly property real progress: {
        const len = w.player?.length ?? 0;
        return len > 0 ? Math.max(0, Math.min(1, (w.player?.position ?? 0) / len)) : 0;
    }

    function clock(secs: real): string {
        if (!secs || secs < 0)
            return "0:00";
        const m = Math.floor(secs / 60);
        const s = Math.floor(secs % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    visible: !!w.player && !!w.player.trackTitle
    height: visible ? implicitHeight : 0

    Item {
        width: 330 * w.s
        height: 96 * w.s

        // The glow: the cover again, blurred and faint, bleeding past the art.
        MultiEffect {
            x: -40 * w.s
            y: -30 * w.s
            width: 200 * w.s
            height: 160 * w.s
            visible: art.status === Image.Ready
            source: art
            blurEnabled: true
            blur: 1
            blurMax: 64
            opacity: 0.45
            saturation: 0.3
        }

        ClippingRectangle {
            id: cover

            width: 96 * w.s
            height: 96 * w.s
            radius: 16 * w.s
            color: Qt.alpha(w.accent, 0.15)

            Image {
                id: art

                anchors.fill: parent
                source: w.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 256
                sourceSize.height: 256
            }

            GenesiWIcon {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                s: w.s
                size: 40
                fill: 1
                text: "music_note"
                color: w.accent
            }
        }

        Column {
            anchors.left: cover.right
            anchors.leftMargin: 16 * w.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * w.s

            GenesiWText {
                width: parent.width
                s: w.s
                size: 17
                font.weight: Font.DemiBold
                text: w.player?.trackTitle ?? ""
                color: w.ink
                elide: Text.ElideRight
            }
            GenesiWText {
                width: parent.width
                s: w.s
                size: 13
                text: w.player?.trackArtist ?? ""
                color: w.inkDim
                elide: Text.ElideRight
            }

            Item {
                width: 1
                height: 6 * w.s
            }

            Rectangle {
                width: parent.width
                height: 5 * w.s
                radius: height / 2
                color: w.track

                Rectangle {
                    width: Math.max(parent.height, parent.width * w.progress)
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: w.accent
                        }
                        GradientStop {
                            position: 1
                            color: w.accent2
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: pos.implicitHeight

                GenesiWText {
                    id: pos

                    s: w.s
                    size: 11
                    text: w.clock(w.player?.position ?? 0)
                    color: w.inkFaint
                }
                GenesiWText {
                    anchors.right: parent.right
                    s: w.s
                    size: 11
                    text: w.clock(w.player?.length ?? 0)
                    color: w.inkFaint
                }
            }
        }
    }
}
