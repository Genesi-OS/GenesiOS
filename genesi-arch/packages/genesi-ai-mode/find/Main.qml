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
    color: appTheme.bgBottom

    // appTheme, not `theme`: a component that HAS a `theme` property
    // (GButton, GlassCard, StatusBanner) resolves a bare `theme` on the
    // right-hand side to its own UNSET property, not to this id.
    Theme { id: appTheme }
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
            color: appTheme.bgTop

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
                        color: appTheme.textHi
                        font.family: appTheme.display
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: win.scope.length > 0
                        text: i18n.t("find.scope") + "  " + win.scopeLabel()
                        color: appTheme.textLo
                        font.family: appTheme.mono
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
                        color: appTheme.cardHi
                        border.width: 1
                        border.color: field.activeFocus ? appTheme.accent : appTheme.line

                        QQC2.TextField {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            background: null
                            color: appTheme.textHi
                            placeholderText: i18n.t("find.placeholder")
                            placeholderTextColor: appTheme.textLo
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                            onAccepted: backend.search(text)
                            Component.onCompleted: forceActiveFocus()
                        }
                    }

                    GButton {
                        theme: appTheme
                        kind: "filled"
                        text: win.busy ? i18n.t("find.searching") : i18n.t("find.search")
                        enabled: !win.busy && field.text.trim().length > 0
                        onClicked: backend.search(field.text)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: appTheme.line }

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
                // The cards are cards now, so they need a gap; at 2px they read
                // as one striped block.
                spacing: appTheme.sp2
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: FileCard {
                    required property var modelData
                    // The same card the Monitor's chat shows for the same data.
                    // The old row opened only on a DOUBLE tap, with nothing on
                    // screen saying it was clickable at all, and no way to
                    // reveal the file in a file manager -- which is the thing
                    // you usually want after finding it.
                    width: list.width
                    path: modelData.path || ""
                    name: modelData.name || ""
                    dir: modelData.dir || ""
                    age: modelData.age || ""
                    hsize: modelData.hsize || ""
                }
            }
        }

        // Empty states. Two of them, because "I have not searched yet" and
        // "I searched and there is nothing" are different things to be told.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: win.results.length === 0

            // The three states this window has -- searching, found nothing,
            // not asked yet -- were one line of grey text floating in the
            // middle of a large empty rectangle. Same three strings, given a
            // shape.
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 420)
                spacing: appTheme.sp3
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 46; radius: appTheme.rMd
                    color: appTheme.a(appTheme.green, 0.12)
                    border.width: 1
                    border.color: appTheme.a(appTheme.green, 0.28)
                    FIcon {
                        anchors.centerIn: parent
                        name: win.busy ? "clock" : "search"
                        size: 20
                        color: appTheme.greenBright
                        RotationAnimation on rotation {
                            running: win.busy
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 1400
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: appTheme.textLo
                    font.pixelSize: 14
                    text: win.busy ? i18n.t("find.searching")
                                   : (win.searched ? i18n.t("find.empty")
                                                   : i18n.t("find.hint"))
                }
            }
        }

        // ════════════ WHAT IT ACTUALLY DID ════════════
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            color: appTheme.bgTop
            visible: win.searched && !win.busy

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Text {
                    text: win.results.length + " " + i18n.t("find.results")
                    color: appTheme.textLo
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: win.filterLabel().length > 0
                          ? i18n.t("find.filter") + ":  " + win.filterLabel() : ""
                    color: appTheme.textLo
                    font.family: appTheme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Text {
                    text: win.plan.source === "model" ? i18n.t("find.byModel")
                                                      : i18n.t("find.byParser")
                    color: win.plan.source === "model" ? appTheme.accentText : appTheme.textLo
                    font.pixelSize: 11
                }
            }
        }
    }
}
