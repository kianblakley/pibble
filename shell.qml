// pibble - a desktop shell for wlr-layer-shell compositors.
// Copyright (C) 2026 Kian Blakley
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "root:/config"
import "root:/flyouts"
import "root:/launcher"
import "root:/services"
import "root:/startup"

// This file is only the wiring: it binds the three persisted stores to disk,
// puts up the six windows, and exposes the IPC the `pibble` script talks to.
// Everything else lives under:
//
//   config/    persisted settings and what the settings UI knows about them
//   services/  the shell's data sources - theme, wallpapers, clipboard, apps…
//   ui/        reusable settings controls, and the custom-page contract
//   launcher/  the launcher window, its state, and one file per pane
//   flyouts/   transient overlay surfaces - the OSDs, the color picker, and
//              the screen tools' overlay
//   startup/   invisible surfaces that only exist to measure the output
//
// Those layers only ever point one way - launcher/flyouts → ui → services →
// config - which is what keeps the directories acyclic.
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
    ColorPickerOverlay {}
    ToolsOverlay {}

    XrayScaleProbe {}



    // The shell runs as a persistent daemon; the launcher window is toggled
    // over IPC - `qs -p <repo> ipc call launcher toggle`, which is what the
    // `pibble` script wraps.
    IpcHandler {
        target: "launcher"

        // `page` is "" for a plain toggle (`pibble toggle`) or a pane id for
        // `pibble toggle <page>`. Closed: opens straight onto that page. Open
        // and already showing it: closes, so re-pressing the same page's
        // keybind acts like a normal toggle. Open and showing something else:
        // switches to it and stays open - a different page's keybind reads as
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
        // `pibble search`: freeze the screen and drag a rectangle over
        // something on it - to select and copy its words, search for it, open
        // a code in it or translate it in place. `pibble translate` is the
        // same, translating the moment the rectangle has been read. Asking
        // again while either is up closes it, so one keybind does both (see
        // ScreenTools.request; getting the launcher out of the way first is
        // LauncherState's).
        function search(): void {
            ScreenTools.request("search");
        }
        function translate(): void {
            ScreenTools.request("translate");
        }
        // `pibble toggle tools`: the menu these and the recorder share.
        // With the launcher up it is the launcher's own menu; with nothing up
        // it opens at the pointer on the tools overlay.
        function tools(): void {
            if (launcher.shown && !LauncherState.exiting)
                LauncherState.toggleTools();
            else
                ScreenTools.toggleMenu();
        }
        // `pibble record [pause]`: asks for a rectangle to record (a click
        // for the whole output) and stops the recording that is running;
        // "pause" holds it and carries it on. "region" is still taken, from
        // when the whole output was recorded without asking.
        function record(what: string): void {
            if (what === "pause")
                Recorder.togglePause();
            else
                Recorder.toggleRegion();
        }
    }
}
