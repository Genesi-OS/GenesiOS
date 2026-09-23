// GENESI STORE — which language a catalogue string is shown in.
//
// The catalogue ships both: `name` and `blurb` are English, `name_pt` and
// `blurb_pt` are Portuguese. English leads because Genesi is installed from
// anywhere; the machine's own language wins when it has one, which is what
// LANGUAGE/LC_ALL/LANG says.
//
// A singleton rather than a property threaded through every component: the
// answer cannot change while the window is open, and passing it down six
// levels of delegate would be six places to forget.
pragma Singleton

import QtQuick

QtObject {
    id: root

    // Set from Python at startup. The fallback matters for the harness that
    // renders these components outside the app.
    readonly property bool pt: typeof isPortuguese !== "undefined"
                               && isPortuguese === true

    // One field of a catalogue object, in the right language. Falls back to
    // English whenever the translation is missing, which is the only
    // half-state worth having: a card in the wrong language still reads, and
    // a card with an empty name does not.
    function of(item, field) {
        if (!item)
            return "";
        if (root.pt) {
            const translated = item[field + "_pt"];
            if (translated !== undefined && translated !== "")
                return translated;
        }
        return item[field] ?? "";
    }

    // The same for a list, used by the tag chips.
    function listOf(item, field) {
        if (!item)
            return [];
        if (root.pt) {
            const translated = item[field + "_pt"];
            if (translated !== undefined && translated.length > 0)
                return translated;
        }
        return item[field] ?? [];
    }

    // For the app's own words, which are written in English in the source.
    function t(english, portuguese) {
        return root.pt ? portuguese : english;
    }
}
