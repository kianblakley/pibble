import QtQuick
import Quickshell
import Quickshell.Io
import "root:/services"

// Binds the Settings singleton to settings.json. Instantiated once, by
// shell.qml.
Scope {
    id: root

    // Dynamic-theme kickoff must happen exactly once, on the true initial
    // load: onLoaded re-fires on every hand edit the file watcher below picks
    // up.
    property bool themeKicked: false

    // When the store last wrote the file itself. The watcher is there for hand
    // edits, but it reports the store's own write too, a millisecond or two
    // after it, and reading that back was a reload per save: the eight
    // re-notifies and the heal below for nothing, and a race - a second save
    // inside that window had already moved the adapter on, and the read-back
    // of the first put it back. A change seen inside the window is taken to be
    // the store's own and left unread; two saves a few milliseconds apart come
    // back as one change, which is why this is a time and not a count.
    property double wroteAt: 0

    FileView {
        id: store

        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false
        // pick up hand edits to settings.json live; without this the daemon
        // keeps its stale in-memory copy and silently overwrites the file on
        // its next save
        watchChanges: true
        onFileChanged: {
            if (Date.now() - root.wroteAt < 100)
                return;
            reload();
        }
        adapter: Settings

        onLoaded: {
            // JsonAdapter's load (both the initial parse and any reload() from
            // a hand-edit) writes object/array-typed properties in a way that
            // doesn't reliably emit their changed signal - plain
            // `Settings.pageOrder = [...]` assignments from QML do
            // (LauncherState.movePage reacts instantly), but the load path
            // leaves bindings that depend on these (LauncherState.pageOrder,
            // activePanes) stuck on whatever they last evaluated to, typically
            // the pre-load default. Force a re-notify by reassigning a fresh
            // shallow copy of each.
            Settings.pageOrder = Settings.pageOrder.slice();
            Settings.uploadedPages = (Settings.uploadedPages ?? []).slice();
            Settings.customPageData = Object.assign({}, Settings.customPageData);
            Settings.pages = Object.assign({}, Settings.pages);
            Settings.keybinds = Object.assign({}, Settings.keybinds);
            Settings.flyouts = Object.assign({}, Settings.flyouts);
            Settings.pibbleAlerts = Object.assign({}, Settings.pibbleAlerts);
            Settings.clockShow = Object.assign({}, Settings.clockShow);
            Settings.heal();
            Settings.loaded();

            if (!root.themeKicked) {
                root.themeKicked = true;
                if (Settings.theme === "matugen")
                    Theme.sampleWallpaper();
            }
        }
    }

    Connections {
        target: Settings
        function onSaveRequested() {
            root.wroteAt = Date.now();
            store.writeAdapter();
        }
    }

    Component.onCompleted: Settings.heal()
}
