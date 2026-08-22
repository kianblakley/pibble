import QtQuick
import Quickshell
import Quickshell.Io
import "root:/services"

// Binds the Settings singleton to settings.json. Instantiated once, by
// shell.qml.
Scope {
    id: root

    // Dynamic-theme kickoff must happen exactly once, on the true initial
    // load: onLoaded re-fires on every save, because writeAdapter's own write
    // loops back through the file watcher below.
    property bool themeKicked: false

    FileView {
        id: store

        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false
        // pick up hand edits to settings.json live; without this the daemon
        // keeps its stale in-memory copy and silently overwrites the file on
        // its next save
        watchChanges: true
        onFileChanged: reload()
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
            store.writeAdapter();
        }
    }

    Component.onCompleted: Settings.heal()
}
