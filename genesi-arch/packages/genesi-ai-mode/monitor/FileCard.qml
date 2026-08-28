/*
 * Genesi AI Mode Monitor — one file, as a block you can act on.
 *
 * Genesi Find answers with paths. A path printed as text is a dead end: the
 * user reads it, then goes and finds the file again by hand in a file manager.
 * So a result is a CARD — what it is, where it lives, how old, how big — and
 * the two things anyone actually wants to do with it are one click away.
 *
 * Clicking the body opens the file. "Show in folder" reveals it SELECTED in the
 * file manager (org.freedesktop.FileManager1.ShowItems), which is the thing
 * "open the containing folder" always fails to do.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

Rectangle {
    id: card

    // Its own Theme, like every page in this app, rather than one passed in.
    // Theme is a stateless Item holding constants, so an instance costs
    // nothing -- and a property assigned from OUTSIDE is not set yet while the
    // object's own children are being created, which a delegate built by a
    // Repeater hits every time ("Cannot read property of undefined").
    Theme { id: theme }
    property string path: ""
    property string name: ""
    property string dir: ""
    property string age: ""
    property string hsize: ""
    // Below this the meta line drops the folder and keeps age/size: on a narrow
    // window a truncated path is noise, but "2d · 4.1 MB" still tells you which
    // of two files you are looking at.
    readonly property bool tight: width < 380

    Layout.fillWidth: true
    implicitHeight: 62
    radius: theme.rMd
    color: hover.containsMouse ? theme.hover : theme.surface
    border.width: 1
    border.color: hover.containsMouse ? theme.a(theme.green, 0.45) : theme.hairline
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    // The extension, as the icon. No icon theme to depend on, no bundled set to
    // keep in step with the file types people actually have, and it says more
    // than a generic document glyph does.
    readonly property string ext: {
        var n = ("" + card.name)
        var i = n.lastIndexOf(".")
        return (i > 0 && i < n.length - 1) ? n.substring(i + 1).toLowerCase() : "?"
    }
    readonly property color kindColor: {
        var e = card.ext
        if (["png", "jpg", "jpeg", "webp", "avif", "gif", "svg", "bmp"].indexOf(e) >= 0)
            return theme.purple
        if (["mp4", "mkv", "webm", "mov", "avi", "mp3", "flac", "wav", "ogg"].indexOf(e) >= 0)
            return theme.violet
        if (["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "epub"].indexOf(e) >= 0)
            return theme.blue
        if (["xls", "xlsx", "ods", "csv", "tsv"].indexOf(e) >= 0)
            return theme.green
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].indexOf(e) >= 0)
            return theme.turbo
        return theme.textLo
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: backend.openPath(card.path)
        QQC2.ToolTip.visible: containsMouse && card.tight
        QQC2.ToolTip.text: card.path
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: theme.sp3
        anchors.rightMargin: theme.sp2
        spacing: theme.sp3

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: theme.rSm
            color: theme.a(card.kindColor, 0.14)
            border.width: 1
            border.color: theme.a(card.kindColor, 0.30)
            QQC2.Label {
                anchors.centerIn: parent
                width: parent.width - 6
                horizontalAlignment: Text.AlignHCenter
                text: card.ext.toUpperCase()
                elide: Text.ElideRight
                color: card.kindColor
                font.pixelSize: card.ext.length > 4 ? theme.fsMicro - 1 : theme.fsMicro
                font.bold: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            QQC2.Label {
                Layout.fillWidth: true
                text: card.name
                color: theme.textHi
                font.pixelSize: theme.fsBody
                font.bold: true
                elide: Text.ElideMiddle
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: {
                    var bits = []
                    if (!card.tight && card.dir) bits.push(card.dir)
                    if (card.age) bits.push(card.age)
                    if (card.hsize) bits.push(card.hsize)
                    return bits.join("  ·  ")
                }
                color: theme.textLo
                font.pixelSize: theme.fsSmall
                elide: Text.ElideMiddle
            }
        }

        // Actions. Always present rather than hover-only: a control nobody can
        // see is a control nobody uses, and this card has exactly two verbs.
        Repeater {
            model: [
                { "act": "reveal", "icon": "folder", "tip": "find.reveal" },
                { "act": "copy",   "icon": "copy",   "tip": "find.copy" }
            ]
            delegate: Rectangle {
                required property var modelData
                // card.theme, not theme: inside a delegate that declares a
                // required property, a bare name no longer falls through to the
                // root object's PROPERTIES (an id still resolves, which is why
                // the same pattern works in ChatPage where theme is an id).
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: theme.rSm
                color: actMa.containsMouse ? theme.a(theme.green, 0.16) : "transparent"
                border.width: 1
                border.color: actMa.containsMouse ? theme.a(theme.green, 0.35) : "transparent"
                FIcon {
                    anchors.centerIn: parent
                    name: modelData.icon
                    size: 14
                    color: actMa.containsMouse ? theme.accentText : theme.textLo
                }
                MouseArea {
                    id: actMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.act === "reveal") backend.revealPath(card.path)
                        else backend.copyToClipboard(card.path)
                    }
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.text: card.tipFor(modelData.tip)
                }
            }
        }
    }

    // The page passes its I18n instance down; fall back to a readable English
    // label rather than showing a raw key if it ever arrives unset.
    property var i18n: null
    function tipFor(key) {
        if (i18n) return i18n.t(key)
        return key === "find.reveal" ? "Show in folder" : "Copy path"
    }
}
