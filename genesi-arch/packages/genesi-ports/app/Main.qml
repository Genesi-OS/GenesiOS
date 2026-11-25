import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: win
    width: 1200
    height: 760
    minimumWidth: 960
    minimumHeight: 620
    visible: true
    title: "Genesi PortScope"
    color: appTheme.bgBottom

    property var listeners: []
    property var selected: null
    property var inspection: ({ reachable: false, endpoints: [] })
    property string protocolFilter: "all"
    property string scopeFilter: "any"
    property string query: ""
    property bool busy: false
    property bool hasRestricted: false
    property bool privilegedView: false
    property string toast: ""

    // appTheme, not `theme`: a component that HAS a `theme` property
    // (GButton, StudioCard, StatusBanner, GlassCard) resolves a bare
    // `theme` on the right-hand side to its own UNSET property, not to
    // this id -- so `theme: theme` binds the property to itself and every
    // sibling binding reading appTheme.x gets undefined.
    StudioTheme { id: appTheme }

    function filtered() {
        var out = []
        var q = query.toLowerCase()
        for (var i = 0; i < listeners.length; i++) {
            var item = listeners[i]
            if (protocolFilter !== "all" && item.proto !== protocolFilter) continue
            if (scopeFilter !== "any" && item.scope !== scopeFilter) continue
            var hay = (item.port + " " + item.process + " " + item.command + " "
                       + item.stack + " " + item.address).toLowerCase()
            if (q && hay.indexOf(q) < 0) continue
            out.push(item)
        }
        return out
    }

    function exposedCount() {
        var count = 0
        for (var i = 0; i < listeners.length; i++)
            if (listeners[i].scope === "all" || listeners[i].scope === "network") count++
        return count
    }

    function localCount() {
        return Math.max(0, listeners.length - exposedCount())
    }

    function select(item) {
        selected = item
        inspection = ({ reachable: false, endpoints: [] })
    }

    Connections {
        target: backend
        function onListenersLoaded(raw) {
            try {
                var data = JSON.parse(raw)
                win.listeners = data.listeners || []
                win.hasRestricted = false
                for (var r = 0; r < win.listeners.length; r++)
                    if (!win.listeners[r].pid) win.hasRestricted = true
                if (win.selected) {
                    var replacement = null
                    for (var i = 0; i < win.listeners.length; i++)
                        if (win.listeners[i].id === win.selected.id) replacement = win.listeners[i]
                    win.selected = replacement
                }
            } catch (e) { win.listeners = [] }
        }
        function onInspectionLoaded(raw) {
            try { win.inspection = JSON.parse(raw) } catch (e) {
                win.inspection = ({ reachable: false, endpoints: [] })
            }
        }
        function onBusyChanged(value) { win.busy = value }
        function onMessage(value) { win.toast = value; toastTimer.restart() }
    }

    Timer { interval: 12000; running: win.visible && !win.privilegedView; repeat: true; onTriggered: backend.refresh() }
    Timer { id: toastTimer; interval: 4200; onTriggered: win.toast = "" }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: appTheme.bgTop }
            GradientStop { position: 1; color: appTheme.bgBottom }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 86
            color: appTheme.bgTop
            border.width: 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 14
                Rectangle {
                    width: 48; height: 48; radius: 8
                    color: appTheme.mix(appTheme.card, appTheme.green, 0.20)
                    border.width: 1; border.color: appTheme.a(appTheme.green, 0.55)
                    Kirigami.Icon {
                        anchors.centerIn: parent; width: 26; height: 26
                        source: "network-connect"; color: appTheme.greenBright
                    }
                }
                ColumnLayout {
                    spacing: 1
                    QQC2.Label {
                        text: "Ports & Processes"
                        color: appTheme.textHi; font.family: appTheme.display
                        font.pixelSize: 23; font.bold: true
                    }
                    QQC2.Label {
                        text: "Live ownership map for every listening service"
                        color: appTheme.textMid; font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: liveRow.implicitWidth + 22
                    Layout.preferredHeight: 30
                    radius: 7
                    color: appTheme.a(appTheme.green, 0.10)
                    border.width: 1
                    border.color: appTheme.a(appTheme.green, 0.34)
                    RowLayout {
                        id: liveRow
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle { width: 7; height: 7; radius: 4; color: appTheme.greenBright }
                        QQC2.Label { text: "LIVE  12s"; color: appTheme.accentText; font.pixelSize: 10; font.bold: true }
                    }
                }
                Rectangle {
                    width: 260; height: 38; radius: 7
                    color: appTheme.cardHi; border.width: 1; border.color: appTheme.lineHi
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 8
                        Kirigami.Icon { source: "search"; width: 16; height: 16; color: appTheme.textMid }
                        QQC2.TextField {
                            Layout.fillWidth: true; background: null
                            placeholderText: "Port, PID, process or stack"
                            color: appTheme.textHi; placeholderTextColor: appTheme.textLo
                            selectedTextColor: appTheme.white; selectionColor: appTheme.green
                            onTextChanged: win.query = text
                        }
                    }
                }
                GButton {
                    visible: win.hasRestricted
                    theme: appTheme; kind: "tonal"; accent: appTheme.turbo
                    iconSource: "lock"; tooltip: "Authenticate to reveal system-owned processes"
                    enabled: !win.busy
                    onClicked: { win.privilegedView = true; backend.refreshPrivileged() }
                }
                GButton {
                    theme: appTheme; kind: "ghost"; iconSource: "view-refresh"
                    tooltip: "Refresh listeners"; enabled: !win.busy
                    onClicked: { win.privilegedView = false; backend.refresh() }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: appTheme.line }

        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.preferredWidth: 222; Layout.fillHeight: true
                color: appTheme.panelTop
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    QQC2.Label { text: "OVERVIEW"; color: appTheme.textLo; font.pixelSize: 11; font.bold: true }
                    Rectangle {
                        Layout.fillWidth: true; height: 82; radius: 8
                        color: appTheme.mix(appTheme.card, appTheme.green, 0.12)
                        border.width: 1; border.color: appTheme.a(appTheme.green, 0.35)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            ColumnLayout {
                                spacing: 0
                                QQC2.Label { text: win.localCount(); color: appTheme.greenBright; font.pixelSize: 25; font.bold: true }
                                QQC2.Label { text: "LOCAL"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                            }
                            Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 14; Layout.bottomMargin: 14; color: appTheme.lineHi }
                            ColumnLayout {
                                spacing: 0
                                QQC2.Label { text: win.exposedCount(); color: win.exposedCount() > 0 ? appTheme.turboBright : appTheme.textMid; font.pixelSize: 25; font.bold: true }
                                QQC2.Label { text: "EXPOSED"; color: appTheme.textLo; font.pixelSize: 9; font.bold: true }
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.Label { text: win.listeners.length; color: appTheme.textHi; font.pixelSize: 13; font.bold: true }
                        }
                    }

                    QQC2.Label { text: "PROTOCOL"; color: appTheme.textLo; font.pixelSize: 11; font.bold: true; Layout.topMargin: 8 }
                    Repeater {
                        model: [
                            { key: "all", label: "All listeners", icon: "network-server" },
                            { key: "tcp", label: "TCP", icon: "network-wired" },
                            { key: "udp", label: "UDP", icon: "network-wireless" }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true; height: 38; radius: 6
                            color: win.protocolFilter === modelData.key
                                   ? appTheme.mix(appTheme.card, appTheme.green, 0.18) : "transparent"
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: win.protocolFilter = modelData.key
                            }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8
                                Kirigami.Icon {
                                    source: modelData.icon; width: 17; height: 17
                                    color: win.protocolFilter === modelData.key ? appTheme.greenBright : appTheme.textMid
                                }
                                QQC2.Label {
                                    text: modelData.label; Layout.fillWidth: true
                                    color: win.protocolFilter === modelData.key ? appTheme.textHi : appTheme.textMid
                                    font.bold: win.protocolFilter === modelData.key
                                }
                            }
                        }
                    }

                    QQC2.Label { text: "EXPOSURE"; color: appTheme.textLo; font.pixelSize: 11; font.bold: true; Layout.topMargin: 8 }
                    Repeater {
                        model: [
                            { key: "any", label: "Any scope" },
                            { key: "local", label: "Localhost only" },
                            { key: "network", label: "Network interface" },
                            { key: "all", label: "All interfaces" }
                        ]
                        // Same shape as the PROTOCOL list above it. These two
                        // do the same job — pick one of a set — and were drawn
                        // as two different kinds of control, so the second one
                        // read as a list of links rather than a filter.
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: win.scopeFilter === modelData.key
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: appTheme.rSm
                            color: sel ? appTheme.a(appTheme.green, 0.14)
                                 : (scopeMa.containsMouse ? appTheme.cardHi : "transparent")
                            border.width: 1
                            border.color: sel ? appTheme.a(appTheme.green, 0.32) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 9
                                Rectangle {
                                    Layout.preferredWidth: 8; Layout.preferredHeight: 8
                                    radius: 4
                                    color: parent.parent.sel ? appTheme.greenBright
                                                             : appTheme.a(appTheme.textLo, 0.5)
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: parent.parent.sel ? appTheme.textHi : appTheme.textMid
                                    font.bold: parent.parent.sel
                                    font.pixelSize: appTheme.fsBody
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: scopeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.scopeFilter = modelData.key
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    StatusBanner {
                        Layout.fillWidth: true; theme: appTheme; accent: appTheme.blue
                        icon: "dialog-information"; title: "On demand"
                        body: "HTTP probing runs only when requested."
                    }
                }
            }

            Rectangle { width: 1; Layout.fillHeight: true; color: appTheme.line }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                RowLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: "Listening now"; color: appTheme.textHi
                                font.pixelSize: 18; font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.Label { text: win.filtered().length + " shown"; color: appTheme.textLo }
                        }

                        QQC2.ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            ListView {
                                id: portList
                                model: win.filtered()
                                spacing: 7
                                delegate: StudioCard {
                                    width: ListView.view ? ListView.view.width : 400
                                    height: 80; interactive: true
                                    active: win.selected && win.selected.id === modelData.id
                                    accent: modelData.scope === "all" ? appTheme.turbo : appTheme.green
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.select(modelData)
                                    }
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        Rectangle {
                                            width: 62; height: 54; radius: 8
                                            color: appTheme.mix(appTheme.card, modelData.proto === "tcp" ? appTheme.green : appTheme.blue, 0.18)
                                            Column {
                                                anchors.centerIn: parent; spacing: 0
                                                QQC2.Label {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.port; color: appTheme.textHi
                                                    font.pixelSize: 18; font.bold: true
                                                }
                                                QQC2.Label {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.proto.toUpperCase(); color: appTheme.textLo; font.pixelSize: 9
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                QQC2.Label {
                                                    text: modelData.process || "Restricted"
                                                    color: appTheme.textHi; font.bold: true; Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                QQC2.Label {
                                                    text: modelData.stack; color: appTheme.accentText; font.pixelSize: 11
                                                }
                                            }
                                            QQC2.Label {
                                                text: modelData.address + "  |  PID " + (modelData.pid || "?") + "  |  " + modelData.user
                                                color: appTheme.textMid; font.pixelSize: 11; elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            QQC2.Label {
                                                text: modelData.command || "Process details require elevated access"
                                                color: appTheme.textLo; font.pixelSize: 10; elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Kirigami.Icon {
                                            source: modelData.scope === "local" ? "security-high" : "network-connect"
                                            width: 17; height: 17
                                            color: modelData.scope === "all" ? appTheme.turboBright : appTheme.textMid
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StudioCard {
                        // Below this the list needs the room more than the
                        // inspector does -- and everything the inspector shows
                        // is a click away again the moment the window grows.
                        visible: win.width >= 1150
                        Layout.preferredWidth: win.width >= 1150 ? 360 : 0
                        Layout.fillHeight: true
                        accent: win.selected && win.selected.scope === "all" ? appTheme.turbo : appTheme.green
                        active: !!win.selected; interactive: false

                        // Nothing selected: a centred state, not a heading with
                        // a paragraph under it and eight hundred pixels of
                        // nothing below that.
                        ColumnLayout {
                            visible: !win.selected
                            anchors.fill: parent
                            anchors.margins: appTheme.sp5
                            spacing: appTheme.sp3
                            Item { Layout.fillHeight: true }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 46; height: 46; radius: appTheme.rMd
                                color: appTheme.a(appTheme.green, 0.12)
                                border.width: 1; border.color: appTheme.a(appTheme.green, 0.28)
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    source: "network-connect"
                                    width: 20; height: 20
                                    color: appTheme.greenBright
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: "Select a listener"
                                color: appTheme.textHi
                                font.pixelSize: appTheme.fsHead
                                font.bold: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: "Pick a port to see who owns it, what stack it is, and which HTTP endpoints it exposes."
                                color: appTheme.textLo
                                font.pixelSize: appTheme.fsSmall
                            }
                            Item { Layout.fillHeight: true }
                        }

                        ColumnLayout {
                            visible: !!win.selected
                            anchors.fill: parent; anchors.margins: 16; spacing: 12
                            QQC2.Label {
                                text: win.selected ? ("Port " + win.selected.port) : ""
                                color: appTheme.textHi; font.pixelSize: 20; font.bold: true
                            }

                            ColumnLayout {
                                visible: !!win.selected; Layout.fillWidth: true; spacing: 8
                                DetailRow { label: "Process"; value: win.selected ? win.selected.process : "" }
                                DetailRow { label: "PID"; value: win.selected ? String(win.selected.pid || "Restricted") : "" }
                                DetailRow { label: "Owner"; value: win.selected ? win.selected.user : "" }
                                DetailRow { label: "Binding"; value: win.selected ? win.selected.address + ":" + win.selected.port : "" }
                                DetailRow { label: "Stack"; value: win.selected ? win.selected.stack : "" }
                            }

                            Rectangle { visible: !!win.selected; Layout.fillWidth: true; height: 1; color: appTheme.line }
                            RowLayout {
                                visible: !!win.selected; Layout.fillWidth: true
                                GButton {
                                    theme: appTheme; kind: "filled"; accent: appTheme.green
                                    text: "Inspect"; iconSource: "search"; enabled: !win.busy && win.selected && win.selected.proto === "tcp"
                                    tooltip: "Discover endpoints: OpenAPI/Swagger, GraphQL, or read from the project source"
                                    onClicked: backend.inspectPort(win.selected.port, win.selected.address, win.selected.pid || 0)
                                }
                                Item { Layout.fillWidth: true }
                                GButton {
                                    theme: appTheme; kind: "danger"; iconSource: "process-stop"
                                    enabled: !win.busy && win.selected && win.selected.pid > 1
                                    tooltip: "Stop the process owning this port"
                                    onClicked: killConfirm.open()
                                }
                            }

                            QQC2.BusyIndicator {
                                running: win.busy; visible: win.busy
                                Layout.alignment: Qt.AlignHCenter; width: 28; height: 28
                            }

                            ColumnLayout {
                                visible: win.inspection && win.inspection.reachable
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                                QQC2.Label { text: "DISCOVERED"; color: appTheme.textLo; font.pixelSize: 10; font.bold: true }
                                QQC2.Label {
                                    text: win.inspection.title || (win.inspection.scheme + " service")
                                    color: appTheme.textHi; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                QQC2.Label {
                                    text: (win.inspection.server ? win.inspection.server : "Server header hidden")
                                          + (win.inspection.openapi ? "  |  OpenAPI " + win.inspection.openapi : "")
                                    color: appTheme.textMid; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                // how many endpoints and where they came from (openapi / graphql /
                                // source-derived from the project / probed liveness)
                                QQC2.Label {
                                    visible: (win.inspection.endpoints || []).length > 0
                                    text: (win.inspection.endpoints.length) + " endpoint"
                                          + (win.inspection.endpoints.length === 1 ? "" : "s")
                                          + (win.inspection.kind ? "  ·  " + win.inspection.kind : "")
                                          + (win.inspection.root ? "  ·  from project source" : "")
                                    color: appTheme.textLo; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                // An API can expose dozens of endpoints — scroll them inside the card
                                // instead of overflowing it.
                                ListView {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    clip: true; spacing: 5
                                    model: win.inspection.endpoints || []
                                    boundsBehavior: Flickable.StopAtBounds
                                    QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
                                    delegate: Rectangle {
                                        width: ListView.view ? ListView.view.width : 0
                                        height: 30; radius: 5; color: appTheme.cardHi
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 8
                                            QQC2.Label {
                                                text: modelData.method || "GET"
                                                color: appTheme.accentText; font.bold: true
                                                font.pixelSize: 10; font.family: appTheme.mono
                                                Layout.preferredWidth: 60
                                            }
                                            QQC2.Label {
                                                text: modelData.path; color: appTheme.textHi
                                                Layout.fillWidth: true; elide: Text.ElideMiddle
                                                font.family: appTheme.mono; font.pixelSize: 11
                                            }
                                            QQC2.Label {
                                                visible: modelData.source !== undefined && modelData.source !== "probe"
                                                text: modelData.source; color: appTheme.textLo; font.pixelSize: 9
                                            }
                                            QQC2.Label {
                                                visible: modelData.status !== undefined
                                                text: modelData.status
                                                color: modelData.status < 400 ? appTheme.greenBright : appTheme.turboBright
                                                font.bold: true; font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                            }
                            StatusBanner {
                                visible: win.inspection && !win.inspection.reachable && (win.inspection.endpoints !== undefined)
                                         && !win.busy && !!win.selected
                                Layout.fillWidth: true; theme: appTheme; accent: appTheme.blue
                                icon: "network-server"; title: "Endpoint inspection"
                                body: "No HTTP endpoint inspected yet."
                            }
                            // Only absorb slack when the endpoint list isn't already filling it.
                            Item {
                                Layout.fillHeight: true
                                visible: !(win.inspection && win.inspection.reachable)
                            }
                            QQC2.Label {
                                visible: !!win.selected
                                text: win.selected ? win.selected.command : ""
                                color: appTheme.textLo; font.family: appTheme.mono; font.pixelSize: 10
                                wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; maximumLineCount: 4
                            }
                        }
                    }
                }
            }
        }
    }

    component DetailRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        QQC2.Label { text: parent.label; color: appTheme.textLo; font.pixelSize: 11; Layout.preferredWidth: 66 }
        QQC2.Label { text: parent.value; color: appTheme.textHi; Layout.fillWidth: true; elide: Text.ElideRight }
    }

    QQC2.Popup {
        id: killConfirm
        anchors.centerIn: parent; width: 430; padding: 0; modal: true; focus: true
        background: StudioCard { accent: appTheme.red; active: true; interactive: false }
        ColumnLayout {
            width: parent.width; spacing: 13
            Item { height: 8 }
            QQC2.Label {
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
                text: "Stop process " + (win.selected ? win.selected.pid : "") + "?"
                color: appTheme.textHi; font.pixelSize: 18; font.bold: true
            }
            QQC2.Label {
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.fillWidth: true
                text: "The listener on port " + (win.selected ? win.selected.port : "")
                      + " will receive SIGTERM. Unsaved work in that process may be lost."
                color: appTheme.textMid; wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.bottomMargin: 16; Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                GButton { theme: appTheme; kind: "ghost"; text: "Cancel"; onClicked: killConfirm.close() }
                GButton {
                    theme: appTheme; kind: "danger"; text: "Stop"; iconSource: "process-stop"
                    onClicked: {
                        backend.killProcess(win.selected.pid, win.selected.port)
                        killConfirm.close()
                    }
                }
            }
        }
    }

    Rectangle {
        visible: win.toast.length > 0
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 18; width: Math.min(parent.width - 40, toastLabel.implicitWidth + 36)
        height: 42; radius: 7; color: appTheme.cardHi; border.width: 1; border.color: appTheme.lineHi
        QQC2.Label { id: toastLabel; anchors.centerIn: parent; text: win.toast; color: appTheme.textHi }
    }
}
