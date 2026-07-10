import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
// NOTE: do NOT import SddmComponents — it exports its own Button/ComboBox (with
// no `background`/`contentItem`) that SHADOW the QtQuick.Controls 2 ones this
// theme customises, causing "Cannot assign to non-existent property background"
// and the theme failing to load (falls back to Breeze). The greeter context
// objects (sddm, userModel, sessionModel, keyboard) come from SDDM directly, not
// from this import, so dropping it is safe.

Rectangle {
    id: root
    width: 1920
    height: 1080

    property string accentColor: "#1D9E75"
    property string darkBg: "#04342C"
    property string textColor: "#E1F5EE"
    property string subtleText: "#A0B4AC"
    property string inputBg: "#0A1E1A"

    TextConstants { id: textConstants }

    Connections {
        target: sddm
        function onLoginSucceeded() { }
        function onLoginFailed() {
            errorMessage.text = textConstants.loginFailed
            password.text = ""
            password.focus = true
        }
    }

    // Background
    Image {
        id: background
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true

        Rectangle {
            anchors.fill: parent
            color: "#80000000"
        }
    }

    // Main content
    Item {
        anchors.fill: parent

        // Logo and title at top center
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.15
            spacing: 12

            Image {
                id: logo
                source: "logo.png"
                width: 80
                height: 80
                anchors.horizontalCenter: parent.horizontalCenter
                smooth: true
                mipmap: true
            }

            Text {
                text: "GENESI OS"
                color: root.textColor
                font.pixelSize: 28
                font.weight: Font.Bold
                font.letterSpacing: 4
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Developer-first operating system"
                color: root.subtleText
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // Login box
        Rectangle {
            id: loginBox
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 40
            width: 360
            height: 280
            radius: 16
            color: Qt.rgba(4/255, 52/255, 44/255, 0.85)
            border.color: Qt.rgba(29/255, 158/255, 117/255, 0.3)
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width - 60

                // User icon
                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: root.accentColor
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        anchors.centerIn: parent
                        text: userNameInput.text.length > 0 ? userNameInput.text[0].toUpperCase() : "G"
                        color: root.darkBg
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }
                }

                // Username
                TextField {
                    id: userNameInput
                    width: parent.width
                    height: 44
                    placeholderText: "Username"
                    text: userModel.lastUser
                    font.pixelSize: 14
                    color: root.textColor
                    placeholderTextColor: root.subtleText
                    horizontalAlignment: TextInput.AlignHCenter

                    background: Rectangle {
                        radius: 10
                        color: root.inputBg
                        border.color: userNameInput.activeFocus ? root.accentColor : Qt.rgba(29/255, 158/255, 117/255, 0.2)
                        border.width: userNameInput.activeFocus ? 2 : 1
                    }

                    Keys.onReturnPressed: password.focus = true
                }

                // Password
                TextField {
                    id: password
                    width: parent.width
                    height: 44
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    font.pixelSize: 14
                    color: root.textColor
                    placeholderTextColor: root.subtleText
                    horizontalAlignment: TextInput.AlignHCenter

                    background: Rectangle {
                        radius: 10
                        color: root.inputBg
                        border.color: password.activeFocus ? root.accentColor : Qt.rgba(29/255, 158/255, 117/255, 0.2)
                        border.width: password.activeFocus ? 2 : 1
                    }

                    Keys.onReturnPressed: sddm.login(userNameInput.text, password.text, sessionModel.lastIndex)
                }

                // Login button
                Button {
                    id: loginButton
                    width: parent.width
                    height: 44
                    text: "Login"
                    font.pixelSize: 14
                    font.weight: Font.Bold

                    contentItem: Text {
                        text: loginButton.text
                        font: loginButton.font
                        color: root.darkBg
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 10
                        color: loginButton.hovered ? "#0F6E56" : root.accentColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    onClicked: sddm.login(userNameInput.text, password.text, sessionModel.lastIndex)
                }

                // Error message
                Text {
                    id: errorMessage
                    width: parent.width
                    color: "#DA4453"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Session and power buttons at bottom
        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            // Session selector
            ComboBox {
                id: sessionSelect
                width: 180
                height: 36
                model: sessionModel
                currentIndex: sessionModel.lastIndex
                textRole: "name"
                font.pixelSize: 12

                background: Rectangle {
                    radius: 8
                    color: Qt.rgba(4/255, 52/255, 44/255, 0.7)
                    border.color: Qt.rgba(29/255, 158/255, 117/255, 0.3)
                    border.width: 1
                }

                contentItem: Text {
                    text: sessionSelect.displayText
                    color: root.textColor
                    font: sessionSelect.font
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                }
            }

            // Power buttons
            Button {
                width: 36; height: 36
                text: "⏻"
                font.pixelSize: 18
                onClicked: sddm.powerOff()
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? Qt.rgba(218/255, 68/255, 83/255, 0.3) : Qt.rgba(4/255, 52/255, 44/255, 0.7)
                    border.color: Qt.rgba(29/255, 158/255, 117/255, 0.3)
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text; font: parent.font; color: root.textColor
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                width: 36; height: 36
                text: "⟳"
                font.pixelSize: 18
                onClicked: sddm.reboot()
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? Qt.rgba(29/255, 158/255, 117/255, 0.3) : Qt.rgba(4/255, 52/255, 44/255, 0.7)
                    border.color: Qt.rgba(29/255, 158/255, 117/255, 0.3)
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text; font: parent.font; color: root.textColor
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Clock at top right
        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 30
            color: root.textColor
            font.pixelSize: 14
            text: Qt.formatDateTime(new Date(), "HH:mm  |  yyyy-MM-dd")

            Timer {
                interval: 60000
                running: true
                repeat: true
                onTriggered: parent.text = Qt.formatDateTime(new Date(), "HH:mm  |  yyyy-MM-dd")
            }
        }
    }

    Component.onCompleted: {
        if (userNameInput.text !== "") {
            password.focus = true
        } else {
            userNameInput.focus = true
        }
    }
}
