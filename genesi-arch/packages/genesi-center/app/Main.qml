/*
 * Genesi Center — the desktop's control surface.
 *
 * Layout: a fixed rail on the left (brand, search, sections, a footer plate)
 * and one content page on the right. The rail owns navigation; a page never
 * knows what else exists, which is what keeps adding the tenth page cheap.
 *
 * The window is frameless. The chrome at the top right is ours because the
 * design is edge to edge -- a title bar would put a foreign strip of the
 * system's colour across the top of a page that is trying to be an instrument.
 * The cost is that dragging has to be implemented, which is the MouseArea in
 * the header.
 */
import QtQuick
import QtQuick.Window
import "components"
import "pages"

Window {
    id: win

    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 720
    visible: true
    color: "transparent"
    title: "Genesi"
    flags: Qt.Window | Qt.FramelessWindowHint

    // Set by the Python side; null when the QML is opened on its own, which is
    // how the design is rendered offscreen for review.
    property var backend: null
    // Resolved by the Python side: a user drop-in, else the packaged
    // asset, else empty and the page draws its own glow.
    property string treeArt: ""

    property string section: "overview"
    readonly property var sections: [
        { id: "overview",     label: qsTr("Visão Geral"),   glyph: "⌂" },
        { id: "system",       label: qsTr("Sistema"),       glyph: "▤" },
        { id: "resources",    label: qsTr("Recursos"),      glyph: "▦" },
        { id: "apps",         label: qsTr("Aplicativos"),   glyph: "⌸" },
        { id: "snapshots",    label: qsTr("Snapshots"),     glyph: "↺" },
        { id: "tools",        label: qsTr("Ferramentas"),   glyph: "⚙" },
        { id: "code",         label: qsTr("Genesi Code"),   glyph: "‹›" },
        { id: "integrations", label: qsTr("Integrações"),   glyph: "☷" },
        { id: "settings",     label: qsTr("Configurações"), glyph: "✲" }
    ]

    Rectangle {
        anchors.fill: parent
        color: Tokens.bg
        radius: 14

        // ── The rail ─────────────────────────────────────────────────────────
        Rectangle {
            id: rail
            width: 268
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            color: Tokens.panel
            radius: 14

            // Square off the inner edge: the rail and the content share a seam,
            // and two rounded corners meeting there reads as a gap.
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 14
                color: Tokens.panel
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: Tokens.line
            }

            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 22
                spacing: 20

                // Brand
                Row {
                    spacing: 12
                    Image {
                        source: "art/genesi-leaf.svg"
                        sourceSize: Qt.size(30, 30)
                        width: 30; height: 30
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        spacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "GENESI"
                            color: Tokens.textHi
                            font.family: Tokens.sans
                            font.pixelSize: 21
                            font.letterSpacing: 5
                            font.weight: Font.Light
                        }
                        Text {
                            text: qsTr("where creations begin")
                            color: Tokens.textDim
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                        }
                    }
                }

                // Search
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: Tokens.radiusSm
                    color: Tokens.card
                    border.width: 1
                    border.color: search.activeFocus ? Tokens.accentDim : Tokens.line
                    Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "/"
                        color: Tokens.textDim
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: search
                        anchors { left: parent.left; leftMargin: 30; right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
                        color: Tokens.textHi
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsBody
                        clip: true
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text === "" && !search.activeFocus
                            text: qsTr("Pesquisar no Genesi…")
                            color: Tokens.textFaint
                            font: search.font
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "⌘K"
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }

                SectionHead { index: "//"; text: qsTr("Navegação") }
            }

            // Sections, with ONE indicator that slides. Drawing a highlight per
            // row and toggling opacity looks the same standing still and reads
            // as unrelated boxes in motion; a single moving plate is what makes
            // the rail feel like one instrument.
            Item {
                id: navArea
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.topMargin: 168
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                height: win.sections.length * 43

                Rectangle {
                    id: indicator
                    width: parent.width
                    height: 39
                    radius: Tokens.radiusSm
                    color: Tokens.accentDeep
                    opacity: 0.55
                    y: {
                        for (let i = 0; i < win.sections.length; i++)
                            if (win.sections[i].id === win.section)
                                return i * 43;
                        return 0;
                    }
                    Behavior on y {
                        NumberAnimation { duration: Tokens.normal; easing.type: Easing.OutCubic }
                    }
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 2
                        radius: 1
                        color: Tokens.accent
                    }
                }

                Repeater {
                    model: win.sections
                    delegate: Item {
                        required property var modelData
                        required property int index

                        width: navArea.width
                        height: 43
                        y: index * 43

                        readonly property bool current: modelData.id === win.section

                        Row {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Text {
                                text: modelData.glyph
                                color: current ? Tokens.accent : Tokens.textDim
                                font.family: Tokens.mono
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }
                            Text {
                                text: modelData.label
                                color: current ? Tokens.textHi : Tokens.text
                                font.family: Tokens.sans
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.section = modelData.id
                        }
                    }
                }
            }

            // Footer plate
            Panel {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.margins: 22
                height: 96
                color: Tokens.card

                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.margins: 14
                    spacing: 4
                    Row {
                        spacing: 8
                        Image {
                            source: "art/genesi-leaf.svg"
                            sourceSize: Qt.size(14, 14)
                            width: 14; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "GENESI OS"
                            color: Tokens.textHi
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsLabel
                            font.letterSpacing: 1.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        text: overview.core.version ? ("v" + overview.core.version) : "rolling"
                        color: Tokens.accentDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                    Text {
                        text: qsTr("Sistema vivo.\nCom você, para o futuro.")
                        color: Tokens.textDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                        lineHeight: 1.35
                    }
                }
            }
        }

        // ── Content ──────────────────────────────────────────────────────────
        Item {
            anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }

            // Window chrome. Dragging lives here because the window is
            // frameless and nothing else would move it.
            Item {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 54
                z: 2

                MouseArea {
                    anchors.fill: parent
                    property point press
                    onPressed: mouse => press = Qt.point(mouse.x, mouse.y)
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        win.x += mouse.x - press.x;
                        win.y += mouse.y - press.y;
                    }
                    onDoubleClicked: win.visibility = win.visibility === Window.Maximized
                                                      ? Window.Windowed : Window.Maximized
                }

                Row {
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    Rectangle {
                        width: 118; height: 26; radius: Tokens.radiusSm
                        color: "transparent"
                        border.width: 1
                        border.color: Tokens.line
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("EDITAR WIDGETS")
                            color: Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 0.8
                        }
                    }
                    Repeater {
                        model: [{ g: "–", act: "min" }, { g: "✕", act: "close" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 26; height: 26; radius: Tokens.radiusSm
                            color: chrome.containsMouse ? Tokens.cardHi : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.quick } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.g
                                color: chrome.containsMouse ? Tokens.textHi : Tokens.textDim
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: chrome
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.act === "min" ? win.showMinimized() : win.close()
                            }
                        }
                    }
                }
            }

            OverviewPage {
                id: overview
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                treeArt: win.treeArt
                visible: win.section === "overview"
            }

            // Every other section, until it has a page. Saying so is better
            // than a blank panel that reads as a bug.
            Item {
                anchors.fill: parent
                visible: win.section !== "overview"
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: "art/genesi-leaf.svg"
                        sourceSize: Qt.size(46, 46)
                        width: 46; height: 46
                        opacity: 0.35
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            for (const s of win.sections)
                                if (s.id === win.section)
                                    return s.label.toUpperCase();
                            return "";
                        }
                        color: Tokens.textDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsLabel
                        font.letterSpacing: 2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("em construção")
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }
            }
        }
    }
}
