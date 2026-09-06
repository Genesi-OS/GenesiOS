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

    // What the running session can be asked to do, from genesi-center-data.
    // Empty means "not told", which shows everything -- see capabilities().
    property var caps: ({})

    function can(need) {
        if (!need)
            return true;
        return win.caps[need] !== false;
    }

    property string section: "overview"
    onCapsChanged: {
        // A section can be hidden after being chosen -- a remembered one, or a
        // deep link. Falling back beats showing a page whose controls do
        // nothing.
        for (const g of visibleGroups)
            for (const it of g.items)
                if (it.id === section)
                    return;
        section = "overview";
    }

    // Grouped, not a flat list of nine. Nine rows in one column is a menu;
    // three groups of three, each announced by a number, is a contents page --
    // and it is what the rail this is measured against does.
    //
    // The tag on each row is a second, fixed-width column. It is ornament, and
    // it is the ornament that gives the rail a rhythm a single column of words
    // cannot have.
    readonly property var groups: [
        {
            index: "01", title: qsTr("Overview"), items: [
                { id: "overview", keywords: "dashboard home summary",  label: qsTr("Overview"),  tag: "概観" },
                { id: "system", keywords: "about specs kernel cpu gpu version packages",    label: qsTr("System"),    tag: "系統" },
                { id: "resources", keywords: "cpu ram memory processes disk monitor performance top", label: qsTr("Resources"), tag: "資源" }
            ]
        },
        {
            index: "02", title: qsTr("Devices"), items: [
                { id: "displays", keywords: "monitor screen resolution hz refresh scale rotate", label: qsTr("Displays"), tag: "画面", needs: "hyprland" },
                { id: "input", keywords: "keyboard mouse pointer touchpad layout repeat sensitivity",    label: qsTr("Input"),    tag: "入力" },
                { id: "audio", keywords: "sound volume speaker microphone mic output input mute",    label: qsTr("Audio"),    tag: "音響" }
            ]
        },
        {
            index: "03", title: qsTr("Desktop"), items: [
                { id: "appearance", keywords: "theme colour color scheme wallpaper shader frame border", label: qsTr("Appearance"), tag: "外観", needs: "caelestia" },
                { id: "bar", keywords: "panel taskbar topbar workspaces tray clock",        label: qsTr("Bar"),        tag: "帯", needs: "caelestia" },
                { id: "launcher", keywords: "menu run search spotlight",   label: qsTr("Launcher"),   tag: "起動", needs: "caelestia" },
                { id: "windows", keywords: "gaps rounding border blur opacity animations tiling",    label: qsTr("Windows"),    tag: "窓", needs: "hyprland" },
                { id: "shortcuts", keywords: "keybinds keys hotkeys bindings",  label: qsTr("Shortcuts"),  tag: "操作", needs: "hyprland" }
            ]
        },
        {
            index: "04", title: qsTr("System"), items: [
                { id: "ai", keywords: "llm model kokoro voice tts api key gpu",        label: qsTr("Local AI"),  tag: "知能" },
                { id: "snapshots", keywords: "backup restore rollback btrfs snapper undo", label: qsTr("Snapshots"), tag: "保存" },
                { id: "console", keywords: "terminal shell alias command function fish bash zsh", label: qsTr("Console"), tag: "端末" },
                { id: "settings", keywords: "about preferences",  label: qsTr("Settings"),  tag: "設定" }
            ]
        }
    ]

    // The groups this session can actually use. Filtering here rather than in
    // the delegates means a group whose every item is unavailable disappears
    // with them: a numbered heading over an empty space reads as a bug.
    readonly property var visibleGroups: {
        const out = [];
        for (const g of groups) {
            const items = g.items.filter(it => win.can(it.needs));
            if (items.length === 0)
                continue;
            // Renumbered over what is SHOWN. The declared numbers are 01..04,
            // and hiding a whole group on Plasma left the rail reading
            // #01 #02 #04 -- a gap that says a section is missing rather than
            // inapplicable.
            const n = out.length + 1;
            out.push({
                index: (n < 10 ? "0" : "") + n,
                title: g.title,
                items: items
            });
        }
        return out;
    }

    // What is typed in the rail's search box.
    property string query: ""

    // The rail as DRAWN: visibleGroups, minus anything that does not match the
    // query. Kept separate from visibleGroups on purpose -- that one answers
    // "what can this session do", and the fallback in onCapsChanged reads it.
    // If searching narrowed that list, typing a letter that hides the open
    // page would throw you back to the Overview mid-keystroke.
    readonly property var navGroups: {
        const q = win.query.trim().toLowerCase();
        if (q === "")
            return win.visibleGroups;
        const out = [];
        for (const g of win.visibleGroups) {
            // The group's own name counts: typing "devices" should give you
            // the three things under Devices, which is how a person who does
            // not know our labels will look for a screen setting.
            const whole = g.title.toLowerCase().indexOf(q) >= 0;
            const items = g.items.filter(it => whole
                || it.label.toLowerCase().indexOf(q) >= 0
                || it.id.indexOf(q) >= 0
                || (it.keywords || "").indexOf(q) >= 0);
            if (items.length === 0)
                continue;
            const n = out.length + 1;
            out.push({
                index: (n < 10 ? "0" : "") + n,
                title: g.title,
                items: items
            });
        }
        return out;
    }

    // The first row a search matched, for Enter.
    readonly property string firstMatch: {
        for (const g of win.navGroups)
            for (const it of g.items)
                return it.id;
        return "";
    }

    function labelFor(id) {
        for (const g of groups)
            for (const it of g.items)
                if (it.id === id)
                    return it.label;
        return "";
    }

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
                        selectionColor: Tokens.accentDeep
                        selectedTextColor: Tokens.textHi
                        clip: true
                        focus: true

                        onTextChanged: win.query = text
                        // Enter opens the first match, so a search can be
                        // finished without reaching for the pointer.
                        onAccepted: {
                            if (win.firstMatch !== "")
                                win.section = win.firstMatch;
                        }
                        Keys.onEscapePressed: text = ""

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text === "" && !search.activeFocus
                            text: qsTr("Search Genesi…")
                            color: Tokens.textFaint
                            font: search.font
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        // Not the Command glyph. This is a Linux desktop, and
                        // the shipped hint was a key nobody here has.
                        text: search.text === "" ? "/" : "↵"
                        color: Tokens.textFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fsMicro
                    }
                }

                SectionHead { index: "//"; text: qsTr("Navigation") }
            }

            // The sections. Each row owns its own selected state now: a
            // single sliding plate cannot cross a group heading without
            // passing THROUGH it, and watching a highlight slide over a
            // divider is worse than not sliding at all.
            Flickable {
                id: navArea
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: railFoot.top }
                anchors.topMargin: 158
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.bottomMargin: 12
                clip: true
                contentHeight: navCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: navCol
                    width: navArea.width
                    spacing: 2

                Repeater {
                    model: win.navGroups
                    delegate: Column {
                        id: groupCol
                        required property var modelData
                        required property int index

                        width: navCol.width
                        spacing: 2

                        // Each group arrives a beat after the one above it.
                        opacity: 0
                        Component.onCompleted: groupIn.start()
                        NumberAnimation {
                            id: groupIn
                            target: groupCol
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Tokens.normal
                            easing.type: Easing.OutCubic
                        }

                        GroupHead {
                            width: parent.width
                            index: groupCol.modelData.index
                            text: groupCol.modelData.title
                        }

                        Repeater {
                            model: groupCol.modelData.items
                            delegate: NavRow {
                                required property var modelData
                                width: groupCol.width
                                label: modelData.label
                                tag: modelData.tag
                                current: win.section === modelData.id
                                onActivated: win.section = modelData.id
                            }
                        }
                    }
                    }

                    // A search that matches nothing has to SAY so. An empty
                    // rail reads as the app having lost its navigation.
                    Item {
                        width: navCol.width
                        height: win.navGroups.length === 0 ? 70 : 0
                        visible: win.navGroups.length === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("no section matches")
                                color: Tokens.textDim
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "“" + win.query + "\u201d"
                                color: Tokens.textFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fsMicro
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, navCol.width - 20)
                            }
                        }
                    }
                }
            }

            // Footer plate
            Panel {
                id: railFoot
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
                        text: qsTr("A living system.\nWith you, for what comes next.")
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

                    // This was "EDIT WIDGETS", copied from the mock, with no
                    // handler behind it at all -- a button that did nothing, in
                    // the app whose whole argument is that it has none. Made
                    // into the thing the header is actually useful for: every
                    // page reads once when it opens, so after changing
                    // something outside this window there has to be a way to
                    // say "read it again" that is not closing the app.
                    Rectangle {
                        id: rescan
                        width: 96; height: 26; radius: Tokens.radiusSm
                        color: rescanHov.hovered ? Tokens.cardHi : "transparent"
                        border.width: 1
                        border.color: rescanHov.hovered ? Tokens.accentDim : Tokens.line
                        Behavior on color { ColorAnimation { duration: Tokens.quick } }
                        Behavior on border.color { ColorAnimation { duration: Tokens.quick } }

                        Text {
                            id: rescanLabel
                            anchors.centerIn: parent
                            text: qsTr("REFRESH")
                            color: rescanHov.hovered ? Tokens.textHi : Tokens.text
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fsMicro
                            font.letterSpacing: 0.8
                        }

                        // A flash rather than a spinner: the read is usually
                        // faster than a spinner would be visible for, and a
                        // spinner that appears and vanishes reads as a glitch.
                        SequentialAnimation {
                            id: rescanFlash
                            NumberAnimation {
                                target: rescanLabel; property: "opacity"
                                to: 0.25; duration: Tokens.quick
                            }
                            NumberAnimation {
                                target: rescanLabel; property: "opacity"
                                to: 1; duration: Tokens.normal
                            }
                        }

                        HoverHandler { id: rescanHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (!win.backend)
                                    return;
                                rescanFlash.start();
                                // The Overview's own sections, plus whatever
                                // the open page reads. Asking for a name that
                                // is not a section is harmless -- it comes
                                // back "{}" and the page ignores it -- but
                                // ci/center-wiring-test.py checks the pages,
                                // so this stays honest by asking for the
                                // section the rail is showing.
                                win.backend.refresh();
                                win.backend.ask(win.section);
                            }
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

            // Every section has a page. They are all instantiated and only
            // one is visible, rather than a Loader per section: a page holds
            // its last reading, so switching away and back shows what was
            // there instead of an empty panel that fills in a moment later.
            //
            // The cost is that fourteen pages exist at once. They are cheap --
            // no page polls unless it is visible, which each one enforces with
            // `running: page.visible` on its own timer.
            OverviewPage {
                id: overview
                treeArt: win.treeArt
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "overview"
            }

            DisplaysPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "displays"
            }

            BarPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "bar"
            }

            SystemPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "system"
            }

            ResourcesPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "resources"
            }

            InputPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "input"
            }

            AudioPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "audio"
            }

            AppearancePage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "appearance"
            }

            LauncherPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "launcher"
            }

            WindowsPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "windows"
            }

            ShortcutsPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "shortcuts"
            }

            AiPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "ai"
            }

            SnapshotsPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "snapshots"
            }

            ConsolePage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "console"
            }

            SettingsPage {
                anchors.fill: parent
                anchors.topMargin: 8
                backend: win.backend
                visible: win.section === "settings"
            }
        }
    }
}
