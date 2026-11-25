// Dev stub for Kirigami.ApplicationWindow.
//
// Two shapes are in use across the Genesi apps: the Monitor builds its layout
// as plain children, and the smaller apps hand over one page — some as
// `initialPage`, some as `pageStack.initialPage`. Upstream pushes it onto a
// page stack; here it is parented to the content item and sized to it, which
// is what a one-page app looks like anyway.
import QtQuick
import QtQuick.Controls as QQC2
QQC2.ApplicationWindow {
    id: root
    property var globalDrawer: null
    property var contextDrawer: null
    visible: true

    function _host(page) {
        if (!page)
            return
        page.parent = root.contentItem
        page.width = Qt.binding(function () { return root.contentItem.width })
        page.height = Qt.binding(function () { return root.contentItem.height })
    }

    property Item initialPage
    onInitialPageChanged: root._host(initialPage)

    readonly property PageStack pageStack: PageStack {
        onInitialPageChanged: root._host(initialPage)
        onPageRequested: function (page) { root._host(page) }
    }
}
