// Which plugin windows exist, from the same switches caelestia reads.
//
// One window per plugin, created when its switch goes on and destroyed when it
// goes off -- nothing of a plugin that is off keeps running. The window type is
// picked by the host (windowFile): a layer surface on Plasma, a plain window
// where there is no layer-shell.
import QtQuick
import QtQuick.Window

Window {
    id: stage

    visible: false
    width: 1
    height: 1

    property bool gamesOpen: false
    property int storyDays: 0
    property var wins: ({})
    readonly property var on: host.enabled

    function want(id: string, yes: bool, props: var): void {
        const have = stage.wins[id];
        if (yes && !have) {
            const c = Qt.createComponent(windowFile);
            if (c.status !== Component.Ready) {
                console.warn("genesi-plugins:", id, c.errorString());
                return;
            }
            const w = c.createObject(stage, props);
            const all = stage.wins;
            all[id] = w;
            stage.wins = all;
        } else if (!yes && have) {
            have.destroy();
            const all = stage.wins;
            delete all[id];
            stage.wins = all;
        }
    }

    function sync(): void {
        const on = stage.on || {};
        stage.want("leaf", on["leaf"] === true,
                   { place: "bottom-right", layerName: "top", width: 280, height: 300, body: leafBody });
        stage.want("vinyl", on["vinyl"] === true,
                   { place: "bottom-left", layerName: "bottom", width: 340, height: 220, body: vinylBody });
        stage.want("live-weather", on["live-weather"] === true,
                   { place: "full", layerName: "bottom", passthrough: true,
                     width: Screen.width, height: Screen.height, body: weatherBody });
        stage.want("game-center", stage.gamesOpen && on["game-center"] === true,
                   { place: "center", layerName: "overlay", keyboard: true,
                     width: 760, height: 580, body: gamesBody });
        stage.want("story", stage.storyDays > 0 && on["wrapped"] === true,
                   { place: "center", layerName: "overlay", keyboard: true,
                     width: 460, height: 780, body: storyBody });
    }

    onOnChanged: stage.sync()
    onGamesOpenChanged: stage.sync()
    onStoryDaysChanged: stage.sync()
    Component.onCompleted: stage.sync()

    Connections {
        target: host
        // Opening it from the menu IS switching it on: a launcher that did
        // nothing until a store switch was flipped would read as broken.
        function onGameCenterToggled(): void {
            if (host.enabled["game-center"] !== true)
                host.turnOn("game-center");
            stage.gamesOpen = !stage.gamesOpen;
        }
        function onWrappedRequested(days: int): void {
            if (host.enabled["wrapped"] !== true)
                host.turnOn("wrapped");
            stage.storyDays = 0;
            stage.storyDays = days;
        }
    }

    // The Retrospective counts focused time whenever it is switched on; the
    // story window is only opened on request.
    Loader {
        active: stage.on["wrapped"] === true
        source: "HostWrappedTracker.qml"
        onLoaded: tracker = item
        property var tracker: null
        id: trackerLoader
    }

    Component { id: leafBody; HostLeaf {} }
    Component { id: vinylBody; HostVinyl {} }
    Component { id: weatherBody; HostWeather {} }
    Component {
        id: gamesBody
        HostGames { onClosed: stage.gamesOpen = false }
    }
    Component {
        id: storyBody
        HostStory {
            days: stage.storyDays
            tracker: trackerLoader.tracker
            onClosed: stage.storyDays = 0
        }
    }
}
