pragma Singleton
import QtQuick
import Quickshell
import "root:/config"

// Every user-visible string in the shell goes through here. Keys are the
// English source text itself rather than an id, so a call site still reads as
// the sentence it renders and an untranslated string degrades to the English
// one instead of to a symbol - which also means adding a string costs nothing
// until somebody translates it.
//
// The tables themselves live next door in Translations, which holds nothing
// but data, and the catalogue of languages in Defaults (see below): this file
// is the lookup, and the two typographic questions a language answers - which
// locale formats its dates, and whether its script may be letter-spaced.
//
// Reads Settings for the chosen language, which is the ordinary
// services → config direction; nothing above services ever has to know a
// language exists beyond calling tr().
Singleton {
    id: root

    // The catalogue itself is Defaults.languages - Settings.heal() has to be
    // able to reject an id nothing ships, and that is the one file both it and
    // this may read without pointing the layers at each other. English heads
    // the list and is the fallback for every lookup, so it is the one id with
    // no table behind it.
    readonly property var languages: Defaults.languages
    readonly property var ids: root.languages.map(l => l.id)

    // Settings.heal() clamps an unknown id back to "en", but this is also read
    // during the window between a hand-edited file loading and heal running,
    // so it falls back on its own rather than trusting that.
    readonly property string code: root.ids.indexOf(Settings.language) >= 0 ? Settings.language : "en"
    readonly property var entry: root.languages.find(l => l.id === root.code) ?? root.languages[0]
    readonly property var table: Translations.tables[root.code] ?? ({})

    // The locale dates are formatted against. A `var` rather than a plain
    // string so every caller shares one Qt.locale() rather than building its
    // own on every frame the clock ticks.
    readonly property var dateLocale: Qt.locale(root.entry.locale)

    // Scripts whose letters join (Arabic) or stack into clusters (Devanagari):
    // a letterSpacing that reads as considered typography in Latin pulls those
    // apart into unshaped fragments, which is not a style choice but a broken
    // word. Every letterSpacing in the shell goes through tracking() below.
    readonly property bool cursive: root.code === "ar" || root.code === "hi"
    function tracking(px: real): real {
        return root.cursive ? 0 : px;
    }
    // Whether the chosen language is written right to left. The shell's layout
    // itself is not mirrored - every pane is hand-anchored - so this is only
    // read where a paragraph's own base direction matters.
    readonly property bool rtl: root.code === "ar"

    // The translated form of `source`, or `source` itself where there is no
    // translation. Reading root.table here is what subscribes a binding to the
    // language: any binding that calls tr(), directly or through a function of
    // its own, re-evaluates when the setting changes.
    function tr(source: string): string {
        return root.table[source] ?? source;
    }
    // tr() with %1/%2 filled in, for the handful of strings that wrap a value
    // ("5m ago", "3 visible"). The placeholders are numbered rather than
    // positional so a translation may reorder them.
    function trf(source: string, a: var, b: var): string {
        return root.tr(source).replace("%1", a === undefined ? "" : a).replace("%2", b === undefined ? "" : b);
    }
    // The language's own name for itself, for the settings row's readout.
    function nameOf(id: string): string {
        const l = root.languages.find(x => x.id === id);
        return l ? l.name : id;
    }
}
