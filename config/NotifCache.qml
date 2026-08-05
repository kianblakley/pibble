pragma Singleton
import QtQuick
import Quickshell.Io

// The last 5 notifications pibble has shown, most recent first, kept on disk
// so `pibble replay` (a plain CLI invocation, no QML state of its own) can ask
// the running daemon to re-fire one of them via IPC. Capped at 5
// unconditionally — Settings.replayCount only trims how many of the cached 5
// are reachable by stepping back through repeated presses.
//
// Split from its FileView the same way Settings is, and for the same reason.
JsonAdapter {
    id: cache

    signal saveRequested

    // Only `items` may be declared here: every property on a JsonAdapter is a
    // key in the file it backs, so constants (the cap above) live on Notifier
    // instead of turning into stray JSON.
    property var items: []

    function save(): void {
        cache.saveRequested();
    }
}
