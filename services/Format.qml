pragma Singleton
import QtQuick
import Quickshell

// Pure value formatting shared across panes and flyouts. Its one dependency is
// Strings, a sibling - the relative-time labels below are words, and words are
// the language's. The byte units are not: KiB and MiB are the units' own
// spelling everywhere.
Singleton {
    id: root

    function humanBytes(n: int): string {
        if (n < 1024)
            return n + " B";
        if (n < 1048576)
            return (n / 1024).toFixed(1) + " KiB";
        return (n / 1048576).toFixed(1) + " MiB";
    }

    // compact relative-time label for `pibble replay` cards ("5m ago"); not
    // used anywhere live notifications need a timestamp, so it's plain
    // one-shot text, not a ticking Timer-backed binding
    function timeAgo(ms: double): string {
        const diff = Math.max(0, Date.now() - ms);
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return Strings.tr("just now");
        if (mins < 60)
            return Strings.trf("%1m ago", mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return Strings.trf("%1h ago", hours);
        return Strings.trf("%1d ago", Math.floor(hours / 24));
    }

    // solid #rrggbb blend of a toward b (t=0 -> a, t=1 -> b). Qt's rich-text
    // CSS subset doesn't reliably support the rgba()/alpha-channel color
    // syntax, so translucency for the clip search highlight is faked by
    // blending toward the panel's dark surface color instead of an actual
    // alpha channel - this always renders as a flat, well-supported #rrggbb
    // value.
    function mixColor(a: color, b: color, t: real): string {
        return "#" + Format.mixChannel(a.r, b.r, t) + Format.mixChannel(a.g, b.g, t) + Format.mixChannel(a.b, b.b, t);
    }

    // Split out rather than closed over inside mixColor: an unannotated inner
    // arrow function makes Qt's compiler fall back to coercing every argument
    // (it warns about exactly this), where a fully annotated sibling doesn't.
    function mixChannel(from: real, to: real, t: real): string {
        return Math.round(Math.max(0, Math.min(1, from + (to - from) * t)) * 255).toString(16).padStart(2, "0");
    }

    function escapeHtml(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
    }
}
