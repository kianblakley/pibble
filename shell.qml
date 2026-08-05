import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "root:/config"
import "root:/flyouts"
import "root:/launcher"
import "root:/services"
import "root:/startup"

// pibble — a desktop shell for wlr-layer-shell compositors.
//
// This file is only the wiring: it binds the three persisted stores to disk,
// puts up the four windows, and exposes the IPC the `pibble` script talks to.
// Everything else lives under:
//
//   config/    persisted settings and what the settings UI knows about them
//   services/  the shell's data sources — theme, wallpapers, clipboard, apps…
//   ui/        reusable settings controls, and the custom-page contract
//   launcher/  the launcher window, its state, and one file per pane
//   flyouts/   the volume and notification OSDs
//   startup/   invisible surfaces that only exist to warm caches or measure
//
// See CLAUDE.md for the layer rules that keep those directories acyclic.
ShellRoot {
    id: root

    // Adapters are singletons (so every reference is a plain `Settings.foo`);
    // these bind them to their files. A singleton can't be reparented into a
    // FileView's default property, which is why the two halves live apart.
    SettingsStore {}
    NotifCacheStore {}
    LaunchCountsStore {}

    // Each of these is a distinct wlr-layer-shell surface with its own
    // namespace, so a compositor can carry per-window rules (blur, in
    // particular) for them independently. See README.md for the table.
    LauncherWindow {
        id: launcher
    }
    VolumeOsd {}
    NotificationFlyout {}

    IconWarmupWindow {}
    XrayScaleProbe {}

    // The shell runs as a persistent daemon; the launcher window is toggled
    // over IPC — `qs -p <repo> ipc call launcher toggle`, which is what the
    // `pibble` script wraps.
    IpcHandler {
        target: "launcher"

        // `page` is "" for a plain toggle (`pibble toggle`) or a pane id for
        // `pibble toggle <page>`. Closed: opens straight onto that page. Open
        // and already showing it: closes, so re-pressing the same page's
        // keybind acts like a normal toggle. Open and showing something else:
        // switches to it and stays open — a different page's keybind reads as
        // "take me there", not "close everything".
        function toggle(page: string): void {
            const target = LauncherState.resolvePageArg(page);
            if (launcher.shown && !LauncherState.exiting) {
                if (target && LauncherState.pane !== target)
                    LauncherState.setPane(target);
                else
                    launcher.exit();
            } else {
                launcher.open(target);
            }
        }
        // "show" would collide with the `qs ipc show` CLI subcommand
        function open(): void {
            if (!launcher.shown || LauncherState.exiting)
                launcher.open("");
        }
        function close(): void {
            if (launcher.shown)
                launcher.exit();
        }
        // `pibble replay`: steps back one more cached notification (up to
        // Settings.replayCount deep) and re-fires just that one, independent of
        // whether the launcher window itself is open.
        function replay(): void {
            Notifier.replay();
        }
    }
}
