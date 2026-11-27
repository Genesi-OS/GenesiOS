// The Retrospective's counting, on Plasma: every 15 s of a non-idle session,
// the focused app's class (reported by a KWin script, see kwin/) gets the
// time, in the same genesi-wrapped.json caelestia keeps, ten weeks deep. The
// story window reads `days` from here.
import QtQuick

QtObject {
    id: root

    property var days: ({})
    property string announced: ""
    property bool loaded: false
    property bool dirty: false

    property GenesiWrappedMath math: GenesiWrappedMath {}

    function save(): void {
        if (!root.loaded)
            return;
        const keep = {};
        const cutoff = root.math.dayKey(new Date(Date.now() - 70 * 86400000));
        for (const k of Object.keys(root.days))
            if (k >= cutoff)
                keep[k] = root.days[k];
        host.writeState("genesi-wrapped.json",
                        JSON.stringify({ version: 1, announced: root.announced, days: keep }) + "\n");
        root.dirty = false;
    }

    function tick(seconds: int): void {
        const cls = host.activeApp;
        const now = new Date();
        const key = root.math.dayKey(now);
        const days = root.days;
        const d = days[key] ?? { active: 0, apps: {}, hours: new Array(24).fill(0) };
        d.active += seconds;
        d.hours[now.getHours()] = (d.hours[now.getHours()] || 0) + seconds;
        if (cls)
            d.apps[cls] = (d.apps[cls] || 0) + seconds;
        days[key] = d;
        root.days = days;
        root.dirty = true;
    }

    Component.onCompleted: {
        try {
            const d = JSON.parse(host.readState("genesi-wrapped.json") || "{}");
            root.days = d.days ?? {};
            root.announced = d.announced ?? "";
        } catch (e) {}
        root.loaded = true;
    }
    Component.onDestruction: root.save()

    property Timer counter: Timer {
        interval: 15000
        repeat: true
        running: root.loaded
        onTriggered: if (host.stats.idle !== true) root.tick(15)
    }

    property Timer saver: Timer {
        // Every two minutes, not every tick: a statistic is not a reason to
        // write to the disk four times a minute.
        interval: 120000
        repeat: true
        running: root.dirty
        onTriggered: root.save()
    }
}
