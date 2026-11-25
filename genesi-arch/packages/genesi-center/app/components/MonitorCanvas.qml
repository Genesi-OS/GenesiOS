/*
 * MonitorCanvas — the desk, to scale.
 *
 * Screens are drawn at their LOGICAL size (resolution divided by scale, swapped
 * when rotated), because that is the space they actually occupy relative to one
 * another. Drawing raw resolutions would put a 4K screen beside a 1080p one at
 * twice the width, when on the desk they are the same size.
 *
 * The factor refuses to compute until there is real geometry: a width of zero
 * divides into a factor big enough to throw every tile off the card, which is
 * exactly what the caelestia version did on its first frame.
 *
 * A drag writes x and y directly, which destroys their bindings, so they are
 * restored on release. The tile is never dropped where it ends up -- genesi-
 * display re-packs the screens so they stay touching -- and without the
 * restore it would stop following the compositor for good.
 */
import QtQuick
import ".."

Item {
    id: root

    property var monitors: []
    property string selected: ""
    signal pick(string name)
    signal moved(string name, int x, int y)

    function logicalW(m) {
        return (m.transform === 1 || m.transform === 3 ? m.height : m.width) / m.scale;
    }
    function logicalH(m) {
        return (m.transform === 1 || m.transform === 3 ? m.width : m.height) / m.scale;
    }

    readonly property real minX: {
        let v = 0;
        for (let i = 0; i < monitors.length; i++)
            v = i === 0 ? monitors[i].x : Math.min(v, monitors[i].x);
        return v;
    }
    readonly property real minY: {
        let v = 0;
        for (let i = 0; i < monitors.length; i++)
            v = i === 0 ? monitors[i].y : Math.min(v, monitors[i].y);
        return v;
    }
    readonly property real spanW: {
        let v = 0;
        for (let i = 0; i < monitors.length; i++)
            v = Math.max(v, monitors[i].x + logicalW(monitors[i]) - minX);
        return v;
    }
    readonly property real spanH: {
        let v = 0;
        for (let i = 0; i < monitors.length; i++)
            v = Math.max(v, monitors[i].y + logicalH(monitors[i]) - minY);
        return v;
    }

    readonly property real factor: (width > 0 && height > 0 && spanW > 0 && spanH > 0)
                                   ? Math.min(width / spanW, height / spanH) * 0.86 : 0
    readonly property real offX: (width - spanW * factor) / 2
    readonly property real offY: (height - spanH * factor) / 2

    clip: true

    Repeater {
        model: root.factor > 0 ? root.monitors : []

        delegate: Rectangle {
            id: tile
            required property var modelData
            required property int index

            readonly property bool held: drag.active
            readonly property bool current: modelData.name === root.selected

            x: root.offX + (modelData.x - root.minX) * root.factor
            y: root.offY + (modelData.y - root.minY) * root.factor
            width: root.logicalW(modelData) * root.factor
            height: root.logicalH(modelData) * root.factor

            radius: Tokens.radiusSm
            // Solid, never the transparent palette: an unfocused screen drawn
            // at the card's own colour disappears, and a two-monitor desk then
            // reads as one monitor sitting oddly off to one side.
            color: current ? Tokens.accentDeep : Tokens.cardHi
            border.width: current ? 2 : 1
            border.color: tile.held ? Tokens.accent
                                    : (current ? Tokens.accentDim : Tokens.line)
            z: tile.held ? 1 : 0

            Behavior on x { enabled: !tile.held; NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !tile.held; NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Tokens.quick } }

            Column {
                anchors.centerIn: parent
                spacing: 1
                visible: tile.height > 40

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.index + 1
                    color: tile.current ? Tokens.textHi : Tokens.text
                    font.family: Tokens.sans
                    font.pixelSize: 22
                    font.weight: Font.Light
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.height > 62 && tile.width > 84
                    text: tile.modelData.name
                    color: tile.current ? Tokens.accent : Tokens.textDim
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: tile.height > 78 && tile.width > 84
                    text: tile.modelData.width + "×" + tile.modelData.height
                    color: Tokens.textFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fsMicro
                }
            }

            DragHandler {
                id: drag
                xAxis.minimum: 0
                xAxis.maximum: Math.max(0, root.width - tile.width)
                yAxis.minimum: 0
                yAxis.maximum: Math.max(0, root.height - tile.height)
                onActiveChanged: {
                    if (active) {
                        root.pick(tile.modelData.name);
                        return;
                    }
                    const mx = (tile.x - root.offX) / root.factor + root.minX;
                    const my = (tile.y - root.offY) / root.factor + root.minY;
                    tile.x = Qt.binding(() => root.offX + (tile.modelData.x - root.minX) * root.factor);
                    tile.y = Qt.binding(() => root.offY + (tile.modelData.y - root.minY) * root.factor);
                    root.moved(tile.modelData.name, Math.round(mx), Math.round(my));
                }
            }
            HoverHandler { cursorShape: tile.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            TapHandler { onTapped: root.pick(tile.modelData.name) }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.monitors.length === 0
        text: qsTr("no displays reported")
        color: Tokens.textFaint
        font.family: Tokens.mono
        font.pixelSize: Tokens.fsMicro
    }
}
