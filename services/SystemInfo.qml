pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Things pibble learns about the machine it's running on, plus the paths it
// generates into. All of the scans here are one-shot and deferred: nothing
// below is needed to render the first launcher frame, so they're started once
// the intro animation has finished (see startDeferredScans).
Singleton {
    id: root

    function expandHome(path: string): string {
        return path.startsWith("~") ? Quickshell.env("HOME") + path.slice(1) : path;
    }

    // Single persistent, self-cleaning cache root for everything pibble
    // generates - separate from the source directories so deleting a wallpaper
    // or a clip scrolling past clipsMax can be detected and swept on the next
    // scan. One directory per shape of generated file: thumbnails/ (split
    // again into crops, wide, clips and notifs), blurred/ and proxies/ (see
    // Wallpapers, Clipboard and Notifier for who owns which), and swatches/
    // (ScreenColor).
    readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/pibble"

    // Scratch file for the notification tint's icon-grab round trip (see
    // NotificationFlyout's tint Canvas), deleted once it has been sampled.
    // One name per grab, never the same one twice. Qt keeps a picture it has
    // loaded under its URL for a while after the last user lets go, and a
    // Canvas asked for a URL still held there is handed the old pixels at once
    // and never told the image loaded - so with a single scratch name, the
    // second sample inside that while never ran and the bubble stayed on the
    // theme accent.
    function tintGrabFile(serial: double): string {
        return (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pibble-tint-" + serial + ".png";
    }

    // ---------- deferred one-shot scans ----------

    property bool scansStarted: false
    function startDeferredScans(): void {
        if (root.scansStarted)
            return;
        root.scansStarted = true;
        iconThemeScan.running = true;
        fontScan.running = true;
    }

    property var fontFamilies: []
    Process {
        id: fontScan
        command: ["bash", "-c", "fc-list :spacing=mono family | sed 's/,.*//' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.fontFamilies = text.split("\n").filter(l => l.trim())
        }
    }

    property var iconThemes: []
    Process {
        id: iconThemeScan
        command: ["bash", "-c", `
            for d in /usr/share/icons/* "$HOME/.icons"/* "$HOME/.local/share/icons"/*; do
                [ -f "$d/index.theme" ] || continue
                grep -q '^Directories=' "$d/index.theme" || continue
                basename "$d"
            done | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.iconThemes = text.split("\n").filter(l => l.trim())
        }
    }

    // ---------- build identity / bug reports ----------

    // shown at the bottom of the general settings tab; empty when the shell
    // isn't running from a git checkout (e.g. a packaged install)
    property string commit: ""
    Process {
        running: true
        command: ["bash", "-c", `git -C "$1" rev-parse --short HEAD 2>/dev/null`, "_", Quickshell.shellDir]
        stdout: StdioCollector {
            onStreamFinished: root.commit = text.trim()
        }
    }

    // Bundles version/build info, this run's recent log, and the latest crash
    // report for this shell (if any) into one blob for bug reports; the
    // clipboard write happens once the collector below has the output.
    function copyDebugInfo(): void {
        if (debugInfo.running)
            return;
        debugInfo.running = true;
    }

    Process {
        id: debugInfo
        // matches by "Shell ID" (md5 of shell.qml's path, the same key
        // quickshell stamps into a crash report.txt) rather than run id, since
        // a crash's run has already ended by the time anyone goes looking
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            pid="$1"
            shell_dir="$2"
            shell_id="$3"
            crashdir="$4"
            echo "pibble debug info -- $(date -Iseconds)"
            qs --version 2>/dev/null
            echo "Shell: $shell_dir"
            echo "Shell ID: $shell_id"
            commit=$(git -C "$shell_dir" rev-parse --short HEAD 2>/dev/null)
            [ -n "$commit" ] && echo "Commit: $commit"
            echo
            echo "----- recent log -----"
            qs log --pid "$pid" --no-color -t 200 2>&1
            latest=""
            for d in $(ls -dt "$crashdir"/*/ 2>/dev/null); do
                grep -q "Shell ID: $shell_id" "$d/report.txt" 2>/dev/null && { latest="$d"; break; }
            done
            if [ -n "$latest" ]; then
                echo
                echo "----- most recent crash: $latest -----"
                cat "$latest/report.txt" 2>/dev/null
            fi`, "_", "" + Quickshell.processId, Quickshell.shellDir, Quickshell.shellId, (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/crashes"]
        stdout: StdioCollector {
            onStreamFinished: {
                Quickshell.clipboardText = text;
                // the blob runs to hundreds of lines; the toast only carries
                // enough of it to be recognisable
                Notifier.action("edit-copy", Strings.tr("Copied to clipboard"), text.slice(0, 4000), "");
            }
        }
    }
}
