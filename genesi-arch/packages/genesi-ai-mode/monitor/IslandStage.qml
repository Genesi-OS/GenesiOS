// The AI island outside caelestia: the card, and what it is told.
//
// Both island windows (IslandLayer for layer-shell desktops, IslandPlain for
// the rest) are this, framed differently. `host` is genesi_ai_island.py's
// Host: it reads the Quick Chat's state and runs the card's commands.
import QtQuick

Item {
    id: stage

    property var host
    readonly property var st: stage.parse(stage.host ? stage.host.stateJson : "{}")
    readonly property var prefs: stage.parse(stage.host ? stage.host.prefsJson : "{}")
    readonly property var pal: stage.parse(stage.host ? stage.host.paletteJson : "{}")
    readonly property bool live: stage.host ? stage.host.live : false
    readonly property bool hangs: stage.host ? stage.host.hangs : false

    // Shown at all: always, or only around the chat.
    readonly property bool wanted: (stage.prefs.mode ?? "always") === "always" || card.expanded
                                   || (stage.live && (stage.st.open ?? false))
    readonly property bool typing: card.typing
    // Whether the window is mapped. Not a binding on the fade: the instant
    // the fade starts, "wanted || fading" is briefly false and the window
    // would blink out and back. Shown at once; hidden after the fade.
    property bool shown: true
    onWantedChanged: {
        if (stage.wanted)
            stage.shown = true;
        else
            hideLater.restart();
    }
    Timer {
        id: hideLater

        interval: 280
        onTriggered: if (!stage.wanted) stage.shown = false
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text || "{}");
        } catch (e) {
            return {};
        }
    }

    GenesiAiIslandCard {
        id: card

        x: Math.round((stage.width - width) / 2)
        y: stage.wanted ? (stage.hangs ? 4 : 0) : -14
        width: implicitWidth
        height: implicitHeight
        opacity: stage.wanted ? 1 : 0
        st: stage.st
        live: stage.live
        prefs: stage.prefs
        pal: stage.pal
        attached: !stage.hangs
        canType: true

        Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220 } }

        onOpenChat: stage.host.command("toggle", "")
        onApprove: id => stage.host.command("approve", id)
        onDeny: id => stage.host.command("deny", id)
        onStopWork: stage.host.command("stop", "")
        onAsk: (text, withClip) => stage.host.command("ask", JSON.stringify({ text: text, clip: withClip }))
        onSetting: (key, value) => stage.host.command("set", key + "=" + value)
        onCopyText: text => stage.host.copy(text)
        onAttach: (path, request) => stage.host.command("attach", JSON.stringify({ path: path, prompt: request }))

        // Only the card takes the pointer.
        onXChanged: stage.pushRect()
        onYChanged: stage.pushRect()
        onWidthChanged: stage.pushRect()
        onHeightChanged: stage.pushRect()
    }

    function pushRect(): void {
        if (stage.host)
            stage.host.setInputRect(card.x - 12, Math.max(0, card.y), card.width + 24, card.height + 12);
    }
    Component.onCompleted: {
        stage.shown = stage.wanted;
        stage.pushRect();
    }
}
