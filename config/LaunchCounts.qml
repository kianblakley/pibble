pragma Singleton
import QtQuick
import Quickshell.Io

// Per-app launch counts, persisted across runs. Apps launched more often rank
// higher in search results. Split from its FileView the same way Settings is.
JsonAdapter {
    id: counts

    signal saveRequested

    // key name is load-bearing: it is the on-disk JSON key, so renaming it
    // would silently orphan every existing user's counts
    property var counts: ({})

    function save(): void {
        counts.saveRequested();
    }
}
