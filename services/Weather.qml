pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// The clock page's weather readout, fetched from wttr.in.
Singleton {
    id: root

    property string text: ""
    property bool ok: false
    // A fetch that came back with nothing - no network yet, DNS not up,
    // wttr.in unreachable. Distinct from weatherOk (which means "there is a
    // reading to show"), because the two want different handling: a failure
    // keeps the last good reading on screen and retries soon, while a
    // rejected location clears the readout and retrying can't help.
    property bool failed: false
    Process {
        id: weatherFetch
        // location passed as $1, not interpolated into the script, since
        // Settings.weatherLocation is user-editable free text; PATH is widened
        // since Quickshell launches processes without a login shell's PATH,
        // which otherwise silently hides curl on some setups
        command: ["bash", "-c", `export PATH="$PATH:/usr/bin:/usr/local/bin:/bin"; curl -fs -m 5 "wttr.in/$1?format=%C+%t"`, "_", Settings.weatherLocation]
        stdout: StdioCollector {
            onStreamFinished: {
                // wttr.in's "%C+%t" format collapses to "Condition  +Temp"
                // (double space: the "+" separator plus %C's own trailing
                // padding), so normalize runs of whitespace down to one
                const t = text.trim().replace(/\s+/g, " ");
                // curl -f writes nothing at all on a failed request, which is
                // what a boot-time fetch looks like while the network is
                // still coming up: keep whatever was last on screen and let
                // weatherRetry try again shortly, rather than blanking the
                // readout until the 15-minute refresh comes round.
                root.failed = t.length === 0;
                if (root.failed)
                    return;
                root.ok = !t.includes("Unknown location");
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

    // maps the wttr.in condition text to a weather glyph
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
