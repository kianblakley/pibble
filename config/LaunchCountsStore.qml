import QtQuick
import Quickshell
import Quickshell.Io

// Binds the LaunchCounts singleton to launch-counts.json. Instantiated once,
// by shell.qml.
Scope {
    FileView {
        id: store

        path: Quickshell.statePath("launch-counts.json")
        blockLoading: true
        printErrors: false
        adapter: LaunchCounts
    }

    Connections {
        target: LaunchCounts
        function onSaveRequested() {
            store.writeAdapter();
        }
    }
}
