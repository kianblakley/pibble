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
        // Not watched, unlike settings.json: nothing but this shell writes the
        // file (`pibble replay` asks the daemon over IPC, and the daemon
        // answers from memory), and a watcher answered the shell's own write
        // by reading the file back in - a copy that, with two saves a few
        // milliseconds apart, was the older of the two. Entries and the
        // looks reported for them were lost to that.
        adapter: NotifCache
    }

    // One notification asks for a save up to three times over - when it
    // arrives, when its colour has been sampled, when its inline image has
    // been written out - all inside its first second on screen, so the file
    // is written once for the lot. Started, never restarted: a steady stream
    // of notifications must not be able to hold the write off forever.
    Timer {
        id: writeDelay

        interval: 1000
        onTriggered: store.writeAdapter()
    }

    Connections {
        target: NotifCache
        function onSaveRequested() {
            writeDelay.start();
        }
    }

    // A write still waiting when the tree comes down (a reload, or the daemon
    // quitting of its own accord) is made now and waited for, since nothing
    // will be left to finish it afterwards. A daemon that is killed gets no
    // such chance, and takes at most the last second of history with it.
    Component.onDestruction: {
        if (!writeDelay.running)
            return;
        store.writeAdapter();
        store.waitForJob();
    }
}
