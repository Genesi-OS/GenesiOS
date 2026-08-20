/*
 * Genesi Find — one field, one list.
 *
 * The whole point of this window is that you do not have to remember the file's
 * name, so the interface is a sentence box and nothing else. Everything below
 * the field is a result you can act on; the footer says, honestly, what the
 * search actually did — which words and extensions it used, and whether the
 * local model refined them or the built-in parser did it alone.
 *
 * Every search goes through the `genesi-find` CLI via the `backend` object.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

QQC2.ApplicationWindow {
    id: win
    visible: true
    title: i18n.t("find.title")
    width: 900
    height: 620
    minimumWidth: 560
    minimumHeight: 360
    color: theme.bgBottom

    Theme { id: theme }
    I18n { id: i18n }

    property var results: []
    property var plan: ({})
    property bool busy: false
    property bool searched: false
    property string scope: initialScope

    function scopeLabel() {
        if (win.scope.length === 0) return "~"
        var home = "/home/"
        var idx = win.scope.indexOf(home)
        if (idx === 0) {
            var rest = win.scope.substring(home.length)
            var cut = rest.indexOf("/")
            return cut < 0 ? "~" : "~/" + rest.substring(cut + 1)
        }
        return win.scope
    }

    function filterLabel() {
        var parts = []
        if (win.plan.words && win.plan.words.length > 0)
            parts.push(win.plan.words.join(", "))
        if (win.plan.exts && win.plan.exts.length > 0)
            parts.push("." + win.plan.exts.slice(0, 4).join(" ."))
        if (win.plan.days) parts.push("≤ " + win.plan.days + "d")
        return parts.join("  ·  ")
    }

    Connections {
        target: backend
        function onResultsReady(payload) {
            try {
                var parsed = JSON.parse(payload)
                win.results = parsed.results || []
                win.plan = parsed.plan || ({})
            } catch (e) {
                win.results = []
                win.plan = ({})
            }
            win.searched = true
        }
        function onBusyChanged(value) { win.busy = value }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ════════════ ASK ════════════
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: askColumn.implicitHeight + 36
            color: theme.bgTop

            ColumnLayout {
                id: askColumn
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: i18n.t("find.title")
                        color: theme.textHi
                        font.family: theme.display
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: win.scope.length > 0
                        text: i18n.t("find.scope") + "  " + win.scopeLabel()
                        color: theme.textLo
                        font.family: theme.mono
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 380
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 10
                        color: theme.cardHi
                        border.width: 1
                        border.color: field.activeFocus ? theme.accent : theme.line

                        QQC2.TextField {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            background: null
                            color: theme.textHi
                            placeholderText: i18n.t("find.placeholder")
                            placeholderTextColor: theme.textLo
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                            onAccepted: backend.search(text)
                            Component.onCompleted: forceActiveFocus()
                        }
                    }

                    GButton {
                        theme: theme
                        kind: "filled"
                        text: win.busy ? i18n.t("find.searching") : i18n.t("find.search")
                        enabled: !win.busy && field.text.trim().length > 0
                        onClicked: backend.search(field.text)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.line }

        // ════════════ RESULTS ════════════
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // Invisible items are skipped by the layout, so this and the empty
            // state below take turns owning the space instead of splitting it.
            visible: win.results.length > 0
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ListView {
                id: list
                model: win.results
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: list.width
                    height: 58
                    color: hover.hovered ? theme.cardHi : "transparent"

                    HoverHandler { id: hover }
                    TapHandler {
                        onDoubleTapped: backend.openPath(modelData.path)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 12
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: theme.textHi
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.dir
                                color: theme.textLo
                                font.family: theme.mono
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }

                        Text {
                            text: modelData.age + "  ·  " + modelData.hsize
                            color: theme.textLo
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                        }

                        RowLayout {
                            spacing: 6
                            opacity: hover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            GButton {
                                theme: theme
                                kind: "tonal"
                                text: i18n.t("find.open")
                                onClicked: backend.openPath(modelData.path)
                            }
                            GButton {
                                theme: theme
                                kind: "ghost"
                                text: i18n.t("find.reveal")
                                onClicked: backend.revealPath(modelData.path)
                            }
                            GButton {
                                theme: theme
                                kind: "ghost"
                                text: i18n.t("find.copyPath")
                                onClicked: backend.copyPath(modelData.path)
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: theme.line
                        visible: index < win.results.length - 1
                    }
                }
            }
        }

        // Empty states. Two of them, because "I have not searched yet" and
        // "I searched and there is nothing" are different things to be told.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: win.results.length === 0

            Text {
                anchors.centerIn: parent
                width: parent.width - 80
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: theme.textLo
                font.pixelSize: 14
                text: win.busy ? i18n.t("find.searching")
                               : (win.searched ? i18n.t("find.empty")
                                               : i18n.t("find.hint"))
            }
        }

        // ════════════ WHAT IT ACTUALLY DID ════════════
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            color: theme.bgTop
            visible: win.searched && !win.busy

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Text {
                    text: win.results.length + " " + i18n.t("find.results")
                    color: theme.textLo
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: win.filterLabel().length > 0
                          ? i18n.t("find.filter") + ":  " + win.filterLabel() : ""
                    color: theme.textLo
                    font.family: theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Text {
                    text: win.plan.source === "model" ? i18n.t("find.byModel")
                                                      : i18n.t("find.byParser")
                    color: win.plan.source === "model" ? theme.accentText : theme.textLo
                    font.pixelSize: 11
                }
            }
        }
    }
}
