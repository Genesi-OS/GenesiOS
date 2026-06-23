/*
 * Genesi API Inspector — native interception workbench over mitmproxy.
 * Four Burp-style lanes: Proxy/Intercept · Repeater · Intruder · Scanner.
 * All traffic state comes from the Python `backend` (mitmproxy DumpMaster).
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1240
    height: 800
    minimumWidth: 940
    minimumHeight: 600
    visible: true
    title: "Genesi API Inspector"
    color: theme.bgBottom

    Theme { id: theme }
    I18n { id: i18n }

    // ── shared state ───────────────────────────────────────────────
    property int page: 0
    property string selectedId: ""
    property string repeaterBaseId: ""
    property string intruderBaseId: ""
    property var interceptItem: null     // {id, raw, host} when a request is paused
    property int scanCount: 0
    property string proxyStatus: "starting…"
    property bool certTrusted: false
    // Whether a Chromium-family browser exists to pre-configure (Burp-style).
    property bool hasBrowser: false
    Component.onCompleted: hasBrowser = backend.hasBrowser()
    // The host/port mitmproxy ACTUALLY bound — may differ from PROXY_PORT when
    // 8080 was busy and the engine hopped to 8081+. The engine label reads these
    // so it never lies about where to point curl/your browser.
    property string proxyHost: PROXY_HOST
    property int proxyPort: PROXY_PORT

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bgTop }
            GradientStop { position: 1.0; color: theme.bgBottom }
        }
    }

    // ── reusable bits ──────────────────────────────────────────────
    component PillButton: Rectangle {
        id: pb
        property string text: ""
        property color accent: theme.green
        property bool flat: false
        property bool enabledX: true
        signal clicked()
        implicitHeight: 32
        implicitWidth: lbl.implicitWidth + 26
        radius: 9
        opacity: enabledX ? 1 : 0.4
        color: flat ? (ma.containsMouse ? theme.a(accent, 0.16) : "transparent")
                    : (ma.containsMouse ? Qt.lighter(accent, 1.12) : accent)
        border.width: flat ? 1 : 0
        border.color: theme.a(accent, 0.5)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: lbl
            anchors.centerIn: parent
            text: pb.text
            color: pb.flat ? accent : "#06120D"
            font.pixelSize: 13
            font.bold: !pb.flat
        }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: pb.enabledX
            onClicked: pb.clicked()
        }
    }

    component Chip: Rectangle {
        property string text: ""
        property color accent: theme.green
        implicitHeight: 20
        implicitWidth: t.implicitWidth + 14
        radius: 6
        color: theme.a(accent, 0.18)
        border.width: 1
        border.color: theme.a(accent, 0.5)
        Text {
            id: t; anchors.centerIn: parent; text: parent.text
            color: parent.accent; font.pixelSize: 11; font.bold: true
        }
    }

    component RawView: Rectangle {
        id: rv
        property alias text: ta.text
        property bool editable: false
        color: theme.bgBottom
        radius: 10
        border.width: 1
        border.color: theme.line
        clip: true
        ScrollView {
            anchors.fill: parent
            anchors.margins: 2
            TextArea {
                id: ta
                readOnly: !rv.editable
                wrapMode: TextArea.NoWrap
                color: theme.textHi
                font.family: theme.mono
                font.pixelSize: 12
                selectByMouse: true
                background: null
                placeholderText: ""
            }
        }
    }

    // ╔══════════════════════ top bar ══════════════════════╗
    header: Rectangle {
        height: 56
        color: theme.card
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            spacing: 14
            Image {
                source: Qt.resolvedUrl("icons/logo.svg")
                sourceSize.width: 24; sourceSize.height: 24
                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                smooth: true
            }
            Text {
                text: "Genesi API Inspector"
                color: theme.textHi; font.pixelSize: 17; font.bold: true
            }
            Rectangle {
                Layout.preferredWidth: dot.implicitWidth + 26
                Layout.preferredHeight: 26
                radius: 8
                color: theme.a(proxyStatus.indexOf("error") >= 0 ? theme.red : theme.green, 0.16)
                border.width: 1
                border.color: theme.a(proxyStatus.indexOf("error") >= 0 ? theme.red : theme.green, 0.5)
                Text {
                    id: dot
                    anchors.centerIn: parent
                    text: "● proxy " + proxyStatus
                    color: proxyStatus.indexOf("error") >= 0 ? theme.red : theme.greenBright
                    font.pixelSize: 12; font.bold: true
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: !certTrusted
                text: i18n.t("insp.httpsHelp")
                color: theme.textMid; font.pixelSize: 12
            }
            PillButton {
                text: certTrusted ? i18n.t("insp.caTrusted") : i18n.t("insp.trustCert")
                accent: certTrusted ? theme.green : theme.turbo
                flat: certTrusted
                enabledX: !certTrusted
                onClicked: backend.trustCert()
            }
            // Burp-style "open a pre-configured browser": a Chromium pointed at
            // this engine's port + our CA, in an isolated profile. No system-proxy
            // flip, so it can't strand the desktop. Hidden if no Chromium exists.
            PillButton {
                visible: hasBrowser
                text: i18n.t("insp.openBrowser")
                accent: theme.blue
                onClicked: backend.openBrowser()
            }
            // Language switch (EN / PT, live)
            Rectangle {
                Layout.preferredWidth: langRow.implicitWidth + 18
                Layout.preferredHeight: 30
                radius: 8
                color: langMa.containsMouse ? theme.a(theme.green, 0.14) : theme.cardHi
                border.width: 1; border.color: theme.line
                Row {
                    id: langRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "🌐"; font.pixelSize: 13 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: i18n.code; color: theme.textHi; font.pixelSize: 12; font.bold: true }
                }
                MouseArea {
                    id: langMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: i18n.toggle()
                    ToolTip.text: i18n.t("lang.tooltip")
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 400
                }
            }
        }
    }

    // ╔══════════════════════ body ══════════════════════╗
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── nav rail ──
        Rectangle {
            Layout.preferredWidth: 168
            Layout.fillHeight: true
            color: theme.card
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.line }
            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6
                Repeater {
                    model: [
                        { t: "Proxy",    i: "icons/proxy.svg",    n: 0 },
                        { t: "Repeater", i: "icons/repeater.svg", n: 1 },
                        { t: "Intruder", i: "icons/intruder.svg", n: 2 },
                        { t: "Scanner",  i: "icons/scanner.svg",  n: 3 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 10
                        color: page === modelData.n ? theme.a(theme.green, 0.16)
                                                    : (nma.containsMouse ? theme.cardHi : "transparent")
                        border.width: page === modelData.n ? 1 : 0
                        border.color: theme.a(theme.green, 0.45)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 10
                            Image {
                                source: Qt.resolvedUrl(modelData.i)
                                sourceSize.width: 19; sourceSize.height: 19
                                Layout.preferredWidth: 19; Layout.preferredHeight: 19
                                opacity: page === modelData.n ? 1.0 : 0.6
                                smooth: true
                            }
                            Text {
                                text: modelData.t
                                color: page === modelData.n ? theme.greenBright : theme.textMid
                                font.pixelSize: 14
                                font.bold: page === modelData.n
                            }
                            Item { Layout.fillWidth: true }
                            Chip {
                                visible: modelData.n === 3 && scanCount > 0
                                text: scanCount + ""
                                accent: theme.red
                            }
                        }
                        MouseArea {
                            id: nma; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page = modelData.n
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true
                    text: "engine: mitmproxy\n" + proxyHost + ":" + proxyPort
                    color: theme.textLo; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── page stack ──
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: page

            // ════════════ PAGE 0 — PROXY / INTERCEPT ════════════
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // controls
                    RowLayout {
                        spacing: 12
                        Rectangle {
                            implicitHeight: 32
                            implicitWidth: 132
                            radius: 9
                            color: interceptOn ? theme.a(theme.turbo, 0.18) : theme.cardHi
                            border.width: 1
                            border.color: interceptOn ? theme.turbo : theme.line
                            property bool interceptOn: false
                            id: interceptBtn
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    text: interceptBtn.interceptOn ? "⏸ Intercept ON" : "▶ Intercept OFF"
                                    color: interceptBtn.interceptOn ? theme.turboBright : theme.textMid
                                    font.pixelSize: 13; font.bold: true
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    interceptBtn.interceptOn = !interceptBtn.interceptOn
                                    backend.setIntercept(interceptBtn.interceptOn)
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 260
                            implicitHeight: 32
                            radius: 9
                            color: theme.bgBottom
                            border.width: 1; border.color: theme.line
                            TextField {
                                id: scopeField
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: theme.textHi
                                font.pixelSize: 12
                                placeholderText: "Scope filter — host substring (blank = all)"
                                background: null
                                onEditingFinished: backend.setScope(text)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: flowsModel.count + " flows"
                            color: theme.textLo; font.pixelSize: 12
                        }
                        PillButton {
                            text: "Clear"; flat: true; accent: theme.textMid
                            onClicked: { backend.clearFlows(); flowsModel.clear() }
                        }
                    }

                    // intercept banner (paused request)
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 230
                        visible: interceptItem !== null
                        accent: theme.turbo
                        active: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "⏸ Request paused — " + (interceptItem ? interceptItem.host : "")
                                    color: theme.turboBright; font.pixelSize: 13; font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                PillButton {
                                    text: "Forward ▶"; accent: theme.green
                                    onClicked: {
                                        backend.forwardIntercepted(interceptItem.id, interceptEdit.text)
                                        interceptItem = null
                                    }
                                }
                                PillButton {
                                    text: "Drop ✕"; accent: theme.red
                                    onClicked: {
                                        backend.dropIntercepted(interceptItem.id)
                                        interceptItem = null
                                    }
                                }
                            }
                            RawView {
                                id: interceptEdit
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                editable: true
                            }
                        }
                    }

                    // flow list + detail
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        GlassCard {
                            Layout.preferredWidth: parent.width * 0.46
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 4
                                // header row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text { text: "M";   color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 42 }
                                    Text { text: "Host / Path"; color: theme.textLo; font.pixelSize: 11; Layout.fillWidth: true }
                                    Text { text: "St";  color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 30 }
                                    Text { text: "Len"; color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 52 }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: theme.line }
                                ListView {
                                    id: flowList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: ListModel { id: flowsModel }
                                    ScrollBar.vertical: ScrollBar {}
                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 30
                                        color: selectedId === id ? theme.a(theme.green, 0.14)
                                              : (fma.containsMouse ? theme.cardHi : "transparent")
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 2
                                            anchors.rightMargin: 6
                                            spacing: 8
                                            Text {
                                                text: method; color: theme.methodColor(method)
                                                font.pixelSize: 11; font.bold: true
                                                Layout.preferredWidth: 42
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: -2
                                                Text {
                                                    text: host; color: theme.textHi; font.pixelSize: 12
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: path; color: theme.textLo; font.pixelSize: 10
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                }
                                            }
                                            Text {
                                                text: status === 0 ? "—" : status
                                                color: theme.statusColor(status)
                                                font.pixelSize: 11; font.bold: true
                                                Layout.preferredWidth: 30
                                            }
                                            Text {
                                                text: length > 0 ? length : ""
                                                color: theme.textMid; font.pixelSize: 10
                                                Layout.preferredWidth: 52
                                                horizontalAlignment: Text.AlignRight
                                            }
                                        }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.a(theme.line, 0.5) }
                                        MouseArea {
                                            id: fma; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { selectedId = id; backend.loadDetail(id) }
                                        }
                                    }
                                }
                            }
                        }

                        GlassCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    TabBar {
                                        id: detailTabs
                                        Layout.fillWidth: true
                                        background: null
                                        TabButton { text: "Request";  width: 110 }
                                        TabButton { text: "Response"; width: 110 }
                                    }
                                    PillButton {
                                        text: "→ Repeater"; flat: true; accent: theme.purple
                                        enabledX: selectedId !== ""
                                        onClicked: {
                                            repeaterBaseId = selectedId
                                            repeaterEdit.text = backend.rawRequestOf(selectedId)
                                            repeaterResp.text = "(send to see the response)"
                                            page = 1
                                        }
                                    }
                                    PillButton {
                                        text: "→ Intruder"; flat: true; accent: theme.blue
                                        enabledX: selectedId !== ""
                                        onClicked: {
                                            intruderBaseId = selectedId
                                            intruderTpl.text = backend.rawRequestOf(selectedId)
                                            page = 2
                                        }
                                    }
                                }
                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: detailTabs.currentIndex
                                    RawView { id: detailReq }
                                    RawView { id: detailResp }
                                }
                            }
                        }
                    }
                }
            }

            // ════════════ PAGE 1 — REPEATER ════════════
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12
                    RowLayout {
                        Text {
                            text: repeaterBaseId === "" ? "Repeater — pick a request in Proxy, then \"→ Repeater\""
                                                        : "Repeater — edit & resend"
                            color: theme.textHi; font.pixelSize: 15; font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        PillButton {
                            text: "Send ▶"; accent: theme.purple
                            enabledX: repeaterBaseId !== ""
                            onClicked: backend.repeaterSend(repeaterBaseId, repeaterEdit.text)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        GlassCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                Text { text: "Request"; color: theme.textMid; font.pixelSize: 12 }
                                RawView { id: repeaterEdit; Layout.fillWidth: true; Layout.fillHeight: true; editable: true }
                            }
                        }
                        GlassCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                RowLayout {
                                    Text { text: "Response"; color: theme.textMid; font.pixelSize: 12 }
                                    Item { Layout.fillWidth: true }
                                    Text { id: repeaterMeta; text: ""; color: theme.greenBright; font.pixelSize: 12; font.family: theme.mono }
                                }
                                RawView { id: repeaterResp; Layout.fillWidth: true; Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // ════════════ PAGE 2 — INTRUDER ════════════
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12
                    RowLayout {
                        Text {
                            text: intruderBaseId === "" ? "Intruder — pick a request in Proxy, then \"→ Intruder\""
                                                        : "Intruder (Sniper) — mark a spot with §…§"
                            color: theme.textHi; font.pixelSize: 15; font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        PillButton {
                            text: "Insert §§"; flat: true; accent: theme.blue
                            onClicked: intruderTpl.insert(intruderTpl.cursorPosition, "§§")
                        }
                        PillButton {
                            text: "Start ▶"; accent: theme.blue
                            enabledX: intruderBaseId !== ""
                            onClicked: {
                                intruderModel.clear()
                                intruderBaseLen = -1
                                backend.intruderStart(intruderBaseId, intruderTpl.text, payloadBox.text)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height * 0.42
                        spacing: 12
                        GlassCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                Text { text: "Request template (wrap the payload position in §…§)"; color: theme.textMid; font.pixelSize: 12 }
                                RawView { id: intruderTpl; Layout.fillWidth: true; Layout.fillHeight: true; editable: true }
                            }
                        }
                        GlassCard {
                            Layout.preferredWidth: parent.width * 0.34
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                Text { text: "Payloads (one per line)"; color: theme.textMid; font.pixelSize: 12 }
                                RawView { id: payloadBox; Layout.fillWidth: true; Layout.fillHeight: true; editable: true }
                            }
                        }
                    }
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text { text: "#";       color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 34 }
                                Text { text: "Payload"; color: theme.textLo; font.pixelSize: 11; Layout.fillWidth: true }
                                Text { text: "Status";  color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 56 }
                                Text { text: "Length";  color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 70 }
                                Text { text: "Time";    color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 64 }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: theme.line }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: ListModel { id: intruderModel }
                                ScrollBar.vertical: ScrollBar {}
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 26
                                    color: ima.containsMouse ? theme.cardHi : "transparent"
                                    // anomaly highlight: length differs from baseline
                                    property bool anomaly: intruderBaseLen >= 0 && length !== intruderBaseLen
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.rightMargin: 6
                                        spacing: 8
                                        Text { text: idx; color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 34; font.family: theme.mono }
                                        Text { text: payload; color: theme.textHi; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight; font.family: theme.mono }
                                        Text { text: status; color: theme.statusColor(status); font.pixelSize: 11; font.bold: true; Layout.preferredWidth: 56 }
                                        Text {
                                            text: length; Layout.preferredWidth: 70; font.pixelSize: 11; font.family: theme.mono
                                            color: parent.parent.anomaly ? theme.turboBright : theme.textMid
                                            font.bold: parent.parent.anomaly
                                        }
                                        Text { text: ms === null ? "—" : ms + "ms"; color: theme.textLo; font.pixelSize: 11; Layout.preferredWidth: 64 }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.a(theme.line, 0.5) }
                                    MouseArea { id: ima; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                        }
                    }
                }
            }

            // ════════════ PAGE 3 — SCANNER ════════════
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12
                    RowLayout {
                        Text { text: "Passive Scanner — findings on live traffic"; color: theme.textHi; font.pixelSize: 15; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Text { text: scanCount + " findings"; color: theme.textLo; font.pixelSize: 12 }
                        PillButton {
                            text: "Clear"; flat: true; accent: theme.textMid
                            onClicked: { scanModel.clear(); scanCount = 0 }
                        }
                    }
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            Text {
                                visible: scanModel.count === 0
                                text: "No findings yet — browse with the proxy on and HTTPS cert trusted."
                                color: theme.textLo; font.pixelSize: 13
                            }
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: ListModel { id: scanModel }
                                ScrollBar.vertical: ScrollBar {}
                                spacing: 6
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    implicitHeight: col.implicitHeight + 16
                                    radius: 10
                                    color: theme.bgBottom
                                    border.width: 1
                                    border.color: theme.a(theme.severityColor(severity), 0.4)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            width: 4; Layout.fillHeight: true; radius: 2
                                            color: theme.severityColor(severity)
                                        }
                                        ColumnLayout {
                                            id: col
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                spacing: 8
                                                Chip { text: severity.toUpperCase(); accent: theme.severityColor(severity) }
                                                Text { text: title; color: theme.textHi; font.pixelSize: 13; font.bold: true }
                                            }
                                            Text { text: detail; color: theme.textMid; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                            Text { text: url; color: theme.textLo; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true; font.family: theme.mono }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── intruder baseline length (first result) ──
    property int intruderBaseLen: -1

    // ╔══════════════════════ backend wiring ══════════════════════╗
    Connections {
        target: backend

        function onProxyReady(host, port) {
            proxyHost = host; proxyPort = port
            proxyStatus = "ready · " + host + ":" + port
        }
        function onProxyError(msg)        { proxyStatus = "error: " + msg }
        function onCertTrusted(t)         { certTrusted = t }
        function onStatusMessage(m)       { proxyStatus = proxyStatus.indexOf("error") >= 0 ? proxyStatus : ("ready · " + m) }

        function onFlowAdded(j) {
            var f = JSON.parse(j)
            flowsModel.append(f)
            flowList.positionViewAtEnd()
        }
        function onFlowUpdated(j) {
            var f = JSON.parse(j)
            for (var i = flowsModel.count - 1; i >= 0; i--) {
                if (flowsModel.get(i).id === f.id) {
                    flowsModel.setProperty(i, "status", f.status)
                    flowsModel.setProperty(i, "length", f.length)
                    break
                }
            }
        }
        function onFlowsCleared() { flowsModel.clear(); selectedId = "" }

        function onFlowDetail(j) {
            var d = JSON.parse(j)
            if (d.id !== selectedId) return
            detailReq.text = d.request
            detailResp.text = d.response
        }

        function onInterceptPaused(j) { interceptItem = JSON.parse(j) }
        function onInterceptStateChanged(on) { if (!on) interceptItem = null }

        function onRepeaterResult(j) {
            var r = JSON.parse(j)
            repeaterResp.text = r.raw
            repeaterMeta.text = (r.status > 0 ? r.status : "ERR") + " · " + r.length + " B"
                              + (r.ms === null ? "" : " · " + r.ms + " ms")
        }

        function onIntruderRow(j) {
            var r = JSON.parse(j)
            if (intruderBaseLen < 0) intruderBaseLen = r.length
            // keep rows ordered by idx
            var pos = intruderModel.count
            for (var i = 0; i < intruderModel.count; i++) {
                if (intruderModel.get(i).idx > r.idx) { pos = i; break }
            }
            intruderModel.insert(pos, r)
        }
        function onIntruderDone(job) { /* could flash a toast */ }

        function onScannerFinding(j) {
            scanModel.insert(0, JSON.parse(j))
            scanCount += 1
        }
    }
}
