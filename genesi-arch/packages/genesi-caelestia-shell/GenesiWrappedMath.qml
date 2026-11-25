// GENESI — the numbers behind the Retrospective.
//
// Plain functions over the tracker's record, so ci/plugins-test.py can hand
// it a made-up month and check every sum: a week that crosses a month, an
// app used on one day only, a period with nothing in it at all.
//
// ── What is recorded ──────────────────────────────────────────────────────
//
//   days: {
//     "2026-09-23": {
//       active: 29340,                     seconds with somebody there
//       apps:   { "firefox": 12000, ... }  seconds with that app focused
//       hours:  [0, 0, ..., 1800, ...]     24 buckets of active seconds
//     }
//   }
//
// Kept per day, in the machine's own time zone, for ten weeks: enough for
// this month and the one before it, and nothing that turns a desktop into
// a surveillance log. Only the window CLASS is kept -- never a title, which
// is where the name of the document, the site or the person would be.
import QtQuick

QtObject {
    id: math

    property bool portuguese: Qt.locale().name.startsWith("pt")

    function t(en: string, pt: string): string {
        return math.portuguese ? pt : en;
    }

    function dayKey(d: var): string {
        const p = n => (n < 10 ? "0" : "") + n;
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
    }

    // The `span` days ending at `end`, newest last.
    function keysBack(end: var, span: int, offset: int): var {
        const out = [];
        for (let i = span - 1 + (offset || 0); i >= (offset || 0); i--) {
            const d = new Date(end.getFullYear(), end.getMonth(), end.getDate() - i);
            out.push(math.dayKey(d));
        }
        return out;
    }

    function fmt(secs: real): string {
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        if (h === 0)
            return `${m}min`;
        return m ? `${h}h ${m}min` : `${h}h`;
    }

    function weekday(key: string): string {
        const [y, mo, d] = key.split("-").map(Number);
        const date = new Date(y, mo - 1, d);
        return date.toLocaleDateString(Qt.locale(math.portuguese ? "pt_BR" : "en_US"), "dddd");
    }

    function summarize(days: var, end: var, span: int): var {
        const keys = math.keysBack(end, span, 0);
        const before = math.keysBack(end, span, span);
        const apps = {};
        const hours = new Array(24).fill(0);
        let total = 0;
        let activeDays = 0;
        let busiest = { key: "", secs: 0 };
        for (const k of keys) {
            const d = days[k];
            if (!d || !d.active)
                continue;
            activeDays++;
            total += d.active;
            if (d.active > busiest.secs)
                busiest = { key: k, secs: d.active };
            for (const [a, s] of Object.entries(d.apps ?? {}))
                apps[a] = (apps[a] || 0) + s;
            (d.hours ?? []).forEach((s, h) => hours[h] += s || 0);
        }
        const previous = before.reduce((n, k) => n + (days[k]?.active ?? 0), 0);
        const top = Object.entries(apps).sort((a, b) => b[1] - a[1]).map(([app, secs]) => ({ app: app, secs: secs }));

        // Consecutive days used, counting back from the last one.
        let streak = 0;
        for (let i = keys.length - 1; i >= 0 && (days[keys[i]]?.active ?? 0) > 0; i--)
            streak++;

        return {
            span: span,
            first: keys[0],
            last: keys[keys.length - 1],
            total: total,
            previous: previous,
            change: previous > 0 ? Math.round((total - previous) / previous * 100) : null,
            activeDays: activeDays,
            busiest: busiest,
            top: top,
            distinct: top.length,
            hours: hours,
            streak: streak
        };
    }

    // Who the numbers say you are this time. One answer, the strongest.
    function persona(s: var): var {
        const total = Math.max(1, s.total);
        const night = [22, 23, 0, 1, 2, 3].reduce((n, h) => n + s.hours[h], 0) / total;
        const morning = [5, 6, 7, 8].reduce((n, h) => n + s.hours[h], 0) / total;
        if (night >= 0.25)
            return { key: "owl", title: math.t("Night owl", "Coruja da noite"),
                     line: math.t("A quarter of your time came after 10 pm.", "Um quarto do seu tempo foi depois das 22h.") };
        if (morning >= 0.2)
            return { key: "lark", title: math.t("Early bird", "Madrugador"),
                     line: math.t("You were at it before 9, most days.", "Você começou antes das 9 quase todo dia.") };
        if (s.busiest.secs >= 8 * 3600)
            return { key: "marathon", title: math.t("Marathoner", "Maratonista"),
                     line: math.t("One day went past eight hours.", "Um dos dias passou de oito horas.") };
        if (s.distinct >= 12)
            return { key: "explorer", title: math.t("Explorer", "Explorador"),
                     line: math.t("%1 different apps in one stretch.", "%1 apps diferentes num período só.").arg(s.distinct) };
        return { key: "steady", title: math.t("Steady", "Constante"),
                 line: math.t("An even rhythm, day after day.", "Um ritmo certinho, dia após dia.") };
    }

    // The slides, in order. Anything with nothing to say is left out rather
    // than shown empty: no games slide for somebody who never played one.
    function slides(s: var, extra: var): var {
        const out = [];
        const month = s.span > 7;
        out.push({ kind: "intro",
                   title: month ? math.t("Your month on Genesi", "Seu mês no Genesi") : math.t("Your week on Genesi", "Sua semana no Genesi"),
                   line: `${s.first} → ${s.last}` });
        if (s.total <= 0) {
            out.push({ kind: "empty", title: math.t("Nothing to show yet", "Nada pra mostrar ainda"),
                       line: math.t("The Retrospective counts from the day it is switched on. Come back in a few days.",
                                    "A Retrospectiva conta a partir do dia em que é ligada. Volta daqui a uns dias.") });
            return out;
        }
        out.push({ kind: "total", title: math.t("You spent", "Você passou"), value: s.total,
                   line: math.t("with your computer, on %1 of %2 days", "com o seu computador, em %1 de %2 dias").arg(s.activeDays).arg(s.span),
                   change: s.change });
        if (s.top.length) {
            const first = s.top[0];
            out.push({ kind: "topapp", title: month ? math.t("Your app of the month", "Seu app do mês") : math.t("Your app of the week", "Seu app da semana"),
                       app: first.app, value: first.secs,
                       line: math.t("%1% of your time", "%1% do seu tempo").arg(Math.round(first.secs / s.total * 100)) });
        }
        if (s.top.length > 1)
            out.push({ kind: "top5", title: math.t("Your top five", "Seu top cinco"), apps: s.top.slice(0, 5) });
        const p = math.persona(s);
        out.push({ kind: "rhythm", title: p.title, line: p.line, persona: p.key, hours: s.hours });
        if (s.busiest.key)
            out.push({ kind: "busiest", title: math.t("Your biggest day", "Seu dia mais cheio"),
                       day: math.weekday(s.busiest.key), value: s.busiest.secs });
        if (extra?.games && extra.games.total > 0)
            out.push({ kind: "games", title: math.t("In the Game Center", "No Game Center"),
                       total: extra.games.total, favourite: extra.games.favourite, best: extra.games.best });
        if (extra?.leaf)
            out.push({ kind: "leaf", title: math.t("Your leaf", "Sua folhinha"), level: extra.leaf.level, name: extra.leaf.title });
        out.push({ kind: "outro", title: month ? math.t("See you next month", "Até o mês que vem") : math.t("See you next week", "Até semana que vem"),
                   line: s.streak > 1 ? math.t("%1 days in a row, and counting.", "%1 dias seguidos, e contando.").arg(s.streak) : "" });
        return out;
    }
}
