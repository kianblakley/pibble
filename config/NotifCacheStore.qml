import QtQuick
import Quickshell
import Quickshell.Io

// Binds the NotifCache singleton to notif-cache.json. Instantiated once, by
// shell.qml.
Scope {
    FileView {
        id: store

        path: Quickshell.statePath("notif-cache.json")
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        adapter: NotifCache
    }

    Connections {
        target: NotifCache
        function onSaveRequested() {
            store.writeAdapter();
        }
    }
}
