// GENESI — the screen before the session.
//
// This is the first thing the machine shows and the one screen a person cannot
// skip, and until now it was Breeze: correct, grey, and from another project.
//
// ── What it must never do ───────────────────────────────────────────────────
//
// Fail. A greeter that throws is a machine nobody can log into, and the only
// way out is a TTY -- which most people do not know they have. So:
//
// SddmComponents is deliberately NOT imported. Nothing here uses a type from
// it, and an import of a module that is missing takes the whole greeter down
// before a single pixel is drawn -- which is the failure this file cannot
// have.
//
//   * nothing here loads a file. No images, no fonts beyond what Qt finds on
//     its own, no icon theme. The mark is drawn, the background is drawn.
//   * every value out of SDDM is read defensively. userModel and sessionModel
//     exist in the greeter and do not exist in a QML viewer, and the property
//     names have changed across SDDM versions, so each is fetched through a
//     helper that answers something sensible when it cannot answer at all.
//   * the password field is the focus from the first frame, and Enter logs in.
//     Everything else on the screen is optional.
//
// ── What it shows ───────────────────────────────────────────────────────────
//
// The time, large, because that is what a person looks at while they type.
// The Genesi mark. One field. The user, the session and the power actions sit
// at the edges, out of the way, and only say more when you go near them.
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Rectangle {
    id: root

    // ── Where the greeter's values come from ────────────────────────────────
    //
    // `config` is the theme.conf above; `sddm` is the greeter. Both are
    // missing when this file is opened in a plain QML viewer, which is how it
    // gets looked at during development, so every read goes through these.
    function cfg(name, fallback) {
        try {
            const value = config[name];
            return value === undefined || value === "" ? fallback : value;
        } catch (error) {
            return fallback;
        }
    }

    readonly property color accent: root.cfg("accent", "#39d98a")
    readonly property color surface: root.cfg("surface", "#070c09")
    readonly property bool twelveHour: String(root.cfg("twelveHour", "false")) === "true"
    readonly property string wallpaper: String(root.cfg("background", ""))

    property string notice: ""
    property bool working: false

    width: 1920
    height: 1080
    color: root.surface

    // ── The background ──────────────────────────────────────────────────────
    //
    // Drawn, not loaded: two greens and a soft light where the mark sits. A
    // picture is used only if the config names one AND it loads.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.darker(root.accent, 4.6)
            }
            GradientStop {
                position: 0.55
                color: root.surface
            }
            GradientStop {
                position: 1
                color: Qt.darker(root.surface, 1.4)
            }
        }
    }

    Image {
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: source !== "" && status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: root.wallpaper !== ""
        color: Qt.rgba(0.02, 0.05, 0.03, 0.55)
    }

    // A slow breath of light behind the mark, so the screen is not static.
    Rectangle {
        anchors.centerIn: mark
        width: 620
        height: 620
        radius: width / 2
        opacity: 0.12
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.accent
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }

        SequentialAnimation on opacity {
            running: true
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.18
                duration: 4200
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0.09
                duration: 4200
                easing.type: Easing.InOutSine
            }
        }
    }

    // ── The mark ────────────────────────────────────────────────────────────
    //
    // The same outline and veins as the system icon, drawn rather than loaded.
    Item {
        id: mark

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.13
        width: 96
        height: 96

        readonly property real unit: width / 256

        Shape {
            anchors.fill: parent

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 13 * mark.unit
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 9 * mark.unit
                PathCubic {
                    x: 48 * mark.unit
                    y: 148 * mark.unit
                    control1X: 76 * mark.unit
                    control1Y: 43 * mark.unit
                    control2X: 48 * mark.unit
                    control2Y: 95 * mark.unit
                }
                PathCubic {
                    x: 128 * mark.unit
                    y: 247 * mark.unit
                    control1X: 48 * mark.unit
                    control1Y: 193 * mark.unit
                    control2X: 79 * mark.unit
                    control2Y: 224 * mark.unit
                }
                PathCubic {
                    x: 208 * mark.unit
                    y: 148 * mark.unit
                    control1X: 177 * mark.unit
                    control1Y: 224 * mark.unit
                    control2X: 208 * mark.unit
                    control2Y: 193 * mark.unit
                }
                PathCubic {
                    x: 128 * mark.unit
                    y: 9 * mark.unit
                    control1X: 208 * mark.unit
                    control1Y: 95 * mark.unit
                    control2X: 180 * mark.unit
                    control2Y: 43 * mark.unit
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 10 * mark.unit
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 60 * mark.unit
                PathLine {
                    x: 128 * mark.unit
                    y: 211 * mark.unit
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 10 * mark.unit
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 103 * mark.unit
                PathLine {
                    x: 87 * mark.unit
                    y: 129 * mark.unit
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 10 * mark.unit
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 142 * mark.unit
                PathLine {
                    x: 85 * mark.unit
                    y: 170 * mark.unit
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 10 * mark.unit
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 103 * mark.unit
                PathLine {
                    x: 169 * mark.unit
                    y: 129 * mark.unit
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 10 * mark.unit
                capStyle: ShapePath.RoundCap

                startX: 128 * mark.unit
                startY: 142 * mark.unit
                PathLine {
                    x: 171 * mark.unit
                    y: 170 * mark.unit
                }
            }
        }
    }

    // ── The time ────────────────────────────────────────────────────────────
    Column {
        id: clock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: mark.bottom
        anchors.topMargin: 26
        spacing: 2

        property date now: new Date()

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.now = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.now, root.twelveHour ? "h:mm" : "HH:mm")
            color: "#eaf5ee"
            font.pixelSize: 104
            font.weight: Font.Light
            font.letterSpacing: -2
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // No hand-written "de": the month and weekday names come from the
            // system locale, and a Portuguese word glued to an English month
            // is how the first version read.
            text: Qt.formatDateTime(clock.now, "dddd, d MMMM")
            color: Qt.rgba(0.92, 0.96, 0.93, 0.62)
            font.pixelSize: 17
        }
    }

    // ── Who, and the way in ─────────────────────────────────────────────────
    //
    // The user list is read once into plain JS values. Reading a QAbstractItem
    // model in a binding is what breaks a greeter when SDDM renames a role.
    property var users: []
    property int userIndex: 0
    readonly property string userName: root.users.length > 0
        ? root.users[root.userIndex].name : ""

    property var sessions: []
    property int sessionIndex: 0

    // How many rows a model has. `count` is a property on SDDM's models and a
    // method on a plain QAbstractListModel, and neither exists when this file
    // is opened in a viewer -- so all three answers are tried before giving up
    // on the list rather than on the screen.
    function rowsOf(model) {
        try {
            if (model.count !== undefined)
                return model.count;
        } catch (error) {
        }
        try {
            return model.rowCount();
        } catch (error) {
        }
        return 0;
    }

    // The first role that answers with text. SDDM has renumbered these across
    // versions, and a greeter that shows an empty name because a role moved is
    // a greeter that looks broken while working perfectly.
    function roleOf(model, row, roles) {
        for (const role of roles) {
            try {
                const value = model.data(model.index(row, 0), role);
                if (value !== undefined && value !== null && String(value) !== "")
                    return String(value);
            } catch (error) {
            }
        }
        return "";
    }

    function loadModels() {
        const people = [];
        const count = root.rowsOf(typeof userModel !== "undefined" ? userModel : null);
        for (let i = 0; i < count; i++) {
            const name = root.roleOf(userModel, i, [Qt.UserRole + 1, 257, Qt.DisplayRole]);
            const real = root.roleOf(userModel, i, [Qt.UserRole + 2, 258]) || name;
            if (name)
                people.push({"name": name, "real": real});
        }
        root.users = people;
        try {
            if (userModel.lastIndex !== undefined && userModel.lastIndex >= 0
                    && userModel.lastIndex < people.length)
                root.userIndex = userModel.lastIndex;
        } catch (error) {
        }

        const list = [];
        const sessionCount = root.rowsOf(typeof sessionModel !== "undefined" ? sessionModel : null);
        for (let i = 0; i < sessionCount; i++) {
            const label = root.roleOf(sessionModel, i,
                                      [Qt.UserRole + 4, 260, Qt.UserRole + 1, 257, Qt.DisplayRole]);
            list.push({"name": label || (qsTr("sessão") + " " + (i + 1))});
        }
        root.sessions = list;
        try {
            if (sessionModel.lastIndex !== undefined && sessionModel.lastIndex >= 0
                    && sessionModel.lastIndex < list.length)
                root.sessionIndex = sessionModel.lastIndex;
        } catch (error) {
        }
    }

    Component.onCompleted: {
        root.loadModels();
        password.forceActiveFocus();
    }

    Column {
        id: entry

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clock.bottom
        anchors.topMargin: 54
        spacing: 14

        // Who is logging in. One name, and a tap cycles when there are more:
        // a dropdown on a login screen is a menu nobody wanted at 7am.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: (root.users.length > 0 ? root.users[root.userIndex].real : "?").substring(0, 1).toUpperCase()
                    color: root.accent
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.users.length > 0 ? root.users[root.userIndex].real : qsTr("Usuário")
                color: "#eaf5ee"
                font.pixelSize: 19
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.users.length > 1
                text: "▾"
                color: Qt.alpha(root.accent, 0.8)
                font.pixelSize: 15

                TapHandler {
                    onTapped: root.userIndex = (root.userIndex + 1) % root.users.length
                }
            }
        }

        // The field. Everything else is optional; this is not.
        Rectangle {
            width: 380
            height: 52
            radius: 26
            color: Qt.rgba(0, 0, 0, 0.42)
            border.width: 2
            border.color: password.activeFocus ? root.accent : Qt.rgba(1, 1, 1, 0.16)

            Behavior on border.color {
                ColorAnimation {
                    duration: 140
                }
            }

            TextInput {
                id: password

                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 56
                verticalAlignment: TextInput.AlignVCenter
                color: "#eaf5ee"
                font.pixelSize: 17
                echoMode: TextInput.Password
                passwordCharacter: "•"
                selectByMouse: true
                enabled: !root.working
                onAccepted: root.enter()

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: password.text === ""
                    text: qsTr("senha")
                    color: Qt.rgba(0.92, 0.96, 0.93, 0.35)
                    font.pixelSize: 17
                }
            }

            // Enter, for a pointer.
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 20
                color: root.working ? Qt.alpha(root.accent, 0.25)
                                    : (password.text !== "" ? root.accent : Qt.rgba(1, 1, 1, 0.08))

                Behavior on color {
                    ColorAnimation {
                        duration: 140
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.working ? "…" : "→"
                    color: password.text !== "" && !root.working ? root.surface : "#eaf5ee"
                    font.pixelSize: 19
                }

                TapHandler {
                    onTapped: root.enter()
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.notice
            color: "#ff8a8a"
            font.pixelSize: 14
            opacity: root.notice === "" ? 0 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }
        }
    }

    function enter() {
        if (root.working || password.text === "")
            return;
        root.working = true;
        root.notice = "";
        try {
            sddm.login(root.userName, password.text, root.sessionIndex);
        } catch (error) {
            root.working = false;
            root.notice = qsTr("Não foi possível falar com o gerenciador de login.");
        }
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        ignoreUnknownSignals: true

        function onLoginSucceeded() {
            root.working = false;
            root.notice = "";
        }

        function onLoginFailed() {
            root.working = false;
            root.notice = qsTr("Senha incorreta.");
            password.text = "";
            password.forceActiveFocus();
        }
    }

    // ── The session, bottom left ────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 26
        spacing: 10
        visible: root.sessions.length > 0

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("sessão")
            color: Qt.rgba(0.92, 0.96, 0.93, 0.35)
            font.pixelSize: 13
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: sessionName.implicitWidth + 28
            height: 32
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.07)

            Text {
                id: sessionName

                anchors.centerIn: parent
                text: root.sessions.length > 0 ? root.sessions[root.sessionIndex].name : ""
                color: "#eaf5ee"
                font.pixelSize: 13
            }

            TapHandler {
                onTapped: root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length
            }
        }
    }

    // ── Power, bottom right ─────────────────────────────────────────────────
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 26
        spacing: 8

        Repeater {
            model: [
                {"glyph": "⏻", "what": "off", "hint": qsTr("Desligar")},
                {"glyph": "⟳", "what": "reboot", "hint": qsTr("Reiniciar")},
                {"glyph": "☾", "what": "suspend", "hint": qsTr("Suspender")}
            ]

            Rectangle {
                id: power

                required property var modelData

                width: 40
                height: 40
                radius: 20
                color: hover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color {
                    ColorAnimation {
                        duration: 140
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: power.modelData.glyph
                    color: "#eaf5ee"
                    font.pixelSize: 16
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    onTapped: {
                        try {
                            if (power.modelData.what === "off")
                                sddm.powerOff();
                            else if (power.modelData.what === "reboot")
                                sddm.reboot();
                            else
                                sddm.suspend();
                        } catch (error) {
                        }
                    }
                }
            }
        }
    }

    // The line Genesi signs its screens with.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        text: "GENESI OS"
        color: Qt.rgba(0.92, 0.96, 0.93, 0.22)
        font.pixelSize: 11
        font.letterSpacing: 5
    }
}
