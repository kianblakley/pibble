pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// The clock page's weather readout, fetched from wttr.in.
Singleton {
    id: root

    property string text: ""
    // The condition's emoji as wttr.in reported it - what root.glyph is picked
    // from, and the only part of the response that doesn't change with the
    // language.
    property string symbol: ""
    property bool ok: false
    // A fetch that came back with nothing - no network yet, DNS not up,
    // wttr.in unreachable. Distinct from weatherOk (which means "there is a
    // reading to show"), because the two want different handling: a failure
    // keeps the last good reading on screen and retries soon, while a
    // rejected location clears the readout and retrying can't help.
    property bool failed: false
    // The language wttr.in is asked to describe the conditions in, so the one
    // line on the clock page that comes from outside the shell still arrives
    // in the language the rest of it is set to. Refetched when it changes -
    // the reading on screen is in the old language until something replaces
    // it, and a 15-minute wait to find that out is not an answer.
    readonly property string lang: Strings.entry.wttr
    // Deferred, not called straight from here: weatherFetch.command is a
    // binding that also reads root.lang, and a change handler runs before the
    // bindings that depend on the same property have re-evaluated. Called
    // directly, refetch() re-runs the command still holding the *old* language
    // and puts the previous language's reading back on screen - and nothing
    // asks again until the 15-minute refresh comes round.
    onLangChanged: if (Settings.weatherEnabled)
        Qt.callLater(root.refetch)
    Process {
        id: weatherFetch
        // location passed as $1 and the language as $2, not interpolated into
        // the script, since Settings.weatherLocation is user-editable free
        // text; PATH is widened since Quickshell launches processes without a
        // login shell's PATH, which otherwise silently hides curl on some setups
        // "%c|%C+%t": the condition's emoji, then the reading itself. The
        // emoji is asked for because %C is now translated and the glyph the
        // clock page draws used to be picked by matching English words in it -
        // where %c is the same handful of symbols in every language (see
        // root.glyph).
        command: ["bash", "-c", `export PATH="$PATH:/usr/bin:/usr/local/bin:/bin"; curl -fs -m 5 "wttr.in/$1?format=%c|%C+%t&lang=$2"`, "_", Settings.weatherLocation, root.lang]
        stdout: StdioCollector {
            onStreamFinished: {
                // wttr.in's "%C+%t" format collapses to "Condition  +Temp"
                // (double space: the "+" separator plus %C's own trailing
                // padding), so normalize runs of whitespace down to one
                const raw = text.trim().replace(/\s+/g, " ");
                // the emoji and the reading are separated by the "|" put in
                // the format above; a response that somehow arrives without
                // one is all reading and no symbol, which the keyword
                // fallback in glyphFor still has a chance at
                const bar = raw.indexOf("|");
                const symbol = bar >= 0 ? raw.slice(0, bar).trim() : "";
                const t = bar >= 0 ? raw.slice(bar + 1).trim() : raw;
                // curl -f writes nothing at all on a failed request, which is
                // what a boot-time fetch looks like while the network is
                // still coming up: keep whatever was last on screen and let
                // weatherRetry try again shortly, rather than blanking the
                // readout until the 15-minute refresh comes round.
                root.failed = raw.length === 0;
                if (root.failed)
                    return;
                root.symbol = symbol;
                // A reading always carries a degree sign (%t), and wttr.in's
                // rejection of a location never does - which is the test that
                // still works now that the response is asked for in the user's
                // language and the wording of that rejection is no longer
                // something to match on.
                root.ok = t.includes("°");
                root.text = root.ok ? t : "";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("pibble: weather fetch failed:", text.trim());
            }
        }
    }
    function refetch(): void {
        weatherFetch.running = false;
        weatherFetch.running = true;
    }
    Timer {
        interval: 15 * 60 * 1000
        running: Settings.weatherEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refetch()
    }
    // The shell starts with the session, typically several seconds before the
    // network is up, so the first fetch of a fresh boot fails and - with only
    // the refresh above - nothing tried again for 15 minutes, which read as
    // weather never loading until the daemon was restarted. Backs off 5s, 10s,
    // 20s ... up to the refresh interval, and stops itself the moment a fetch
    // comes back with anything (including a rejected location, which retrying
    // can't fix).
    Timer {
        id: weatherRetry
        property int attempt: 0
        interval: Math.min(15 * 60 * 1000, 5000 * Math.pow(2, attempt))
        running: Settings.weatherEnabled && root.failed
        repeat: true
        onTriggered: {
            attempt++;
            root.refetch();
        }
        onRunningChanged: if (!running)
            attempt = 0
    }

    // The glyph the clock page draws beside the reading. Picked from the
    // condition emoji rather than from the words next to it: those are in
    // whatever language the shell is set to now, and matching English keywords
    // in them worked only for as long as English was the only thing wttr.in
    // was ever asked for. The keyword pass below is still the fallback, for a
    // response that arrived without a symbol at all.
    readonly property string glyph: {
        const c = root.symbol;
        if (c.includes("⛈") || c.includes("🌩"))
            return Icons.cloudStorm;
        if (c.includes("❄") || c.includes("🌨"))
            return Icons.snowflake;
        if (c.includes("🌧") || c.includes("🌦") || c.includes("💧"))
            return Icons.cloudRain;
        if (c.includes("☁") || c.includes("🌫") || c.includes("⛅") || c.includes("🌥"))
            return Icons.cloud;
        if (c.includes("☀") || c.includes("🌤"))
            return Icons.sun;
        return root.glyphFor(root.text);
    }

    // maps an English wttr.in condition text to a weather glyph - the fallback
    // behind root.glyph above, and what a custom page reading the service
    // directly still has
    function glyphFor(condition: string): string {
        const t = condition.toLowerCase();
        if (t.includes("thunder"))
            return Icons.cloudStorm;
        if (t.includes("snow") || t.includes("sleet") || t.includes("ice"))
            return Icons.snowflake;
        if (t.includes("rain") || t.includes("drizzle") || t.includes("shower"))
            return Icons.cloudRain;
        if (t.includes("fog") || t.includes("mist") || t.includes("haze") || t.includes("overcast") || t.includes("cloud"))
            return Icons.cloud;
        if (t.includes("clear") || t.includes("sunny"))
            return Icons.sun;
        return "";
    }
}
