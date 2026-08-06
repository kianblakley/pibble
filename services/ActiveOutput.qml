pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.I3
import Quickshell.WindowManager

// Which output the user is actually on, so the launcher and the flyouts map
// onto the monitor being used instead of always onto the first one.
//
// Nothing pibble can see on its own answers this: wlr-layer-shell has no notion
// of a focused output, and Qt only knows about the surfaces this process owns.
// So it has to be asked of the compositor, and there are four tiers of asking,
// picked from the environment (see `compositor`) rather than by probing - every
// module below logs loudly when it can't reach the compositor it's for:
//
//   niri        the IPC socket's event stream, read straight off $NIRI_SOCKET -
//               no `niri msg` child process to keep alive.
//   Hyprland    Quickshell's Hyprland module, via $HYPRLAND_INSTANCE_SIGNATURE.
//   sway / i3   Quickshell's I3 module, via $SWAYSOCK / $I3SOCK.
//   anything    ext-workspace-v1, if the compositor implements it (COSMIC,
//   else        Wayfire, labwc…). A guess rather than an answer - see the
//               Variants block for what it can and can't see.
//
// And below all of that, the primary output - which is what every window here
// mapped onto before any of this existed, so an unknown compositor is no worse
// off than it was.
//
// Only the niri tier is tested; the other three are the same shape as what the
// modules' own examples do.
Singleton {
    id: root

    // Name of the focused output ("HDMI-A-1", "DP-2"…), "" while unknown.
    property string name: ""

    // What that name resolves to. Falls back to the primary output rather than
    // null whenever it can't be resolved: an output can be named by an event a
    // moment before Qt has a QScreen for it, and it can be unplugged while it
    // is still named here - and every window binding this needs *an* output.
    readonly property var screen: {
        const screens = Quickshell.screens;
        if (screens.length === 0)
            return null;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === root.name)
                return screens[i];
        }
        return screens[0];
    }

    // Which tier is in play. Decided from the environment alone, so that only
    // the one integration is ever constructed - reading a property off any of
    // these modules outside its own session logs a warning on every startup
    // ("$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.",
    // and the I3 module's pair of them), which is also why each tier below sits
    // behind a Loader or a short-circuiting binding rather than being written
    // out plainly.
    readonly property string compositor: {
        if (Quickshell.env("NIRI_SOCKET"))
            return "niri";
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return "hyprland";
        if (Quickshell.env("SWAYSOCK") || Quickshell.env("I3SOCK"))
            return "sway";
        return "";
    }

    // ---------- niri ----------
    // Workspace id -> output name. WorkspaceActivated only carries an id, so
    // the map from the last full snapshot is what turns it into an output.
    property var workspaceOutputs: ({})

    function readNiri(line: string): void {
        // Every window focus change sends the entire window list down this
        // socket - kilobytes of JSON, several times a second while alt-tabbing
        // through a busy session. Only two event types say anything about which
        // output is focused, so match the discriminant as a string before
        // paying for a parse.
        const activated = line.startsWith('{"WorkspaceActivated"');
        if (!activated && !line.startsWith('{"WorkspacesChanged"'))
            return;
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (activated) {
            const data = event.WorkspaceActivated;
            // a workspace becoming active on an output that isn't the focused
            // one (`focused: false`) says nothing about where the keyboard is
            if (!data.focused)
                return;
            const output = root.workspaceOutputs[data.id];
            if (output)
                root.name = output;
            return;
        }
        // Full snapshot: rebuild the id map, and take the focused workspace's
        // output along with it. This is also the first event on every
        // connection, so it is what seeds `name` at startup.
        const map = {};
        let focused = "";
        const workspaces = event.WorkspacesChanged.workspaces;
        for (let i = 0; i < workspaces.length; i++) {
            const workspace = workspaces[i];
            if (!workspace.output)
                continue; // a workspace whose output is currently unplugged
            map[workspace.id] = workspace.output;
            if (workspace.is_focused)
                focused = workspace.output;
        }
        root.workspaceOutputs = map;
        if (focused)
            root.name = focused;
    }

    Socket {
        path: Quickshell.env("NIRI_SOCKET") ?? ""
        // Not reconnected if it drops: niri's socket path carries its pid, so a
        // compositor that went away is not coming back at this address, and a
        // shell whose compositor exited is on its way out with it.
        connected: root.compositor === "niri"
        onConnectedChanged: {
            if (!connected)
                return;
            // niri's IPC takes one JSON-encoded request per connection;
            // EventStream is a unit variant, so the request is the bare string.
            // It answers {"Ok":"Handled"} and then streams events forever.
            write('"EventStream"\n');
            flush();
        }
        parser: SplitParser {
            onRead: line => root.readNiri(line)
        }
    }

    // ---------- Hyprland ----------
    Loader {
        active: root.compositor === "hyprland"
        sourceComponent: QtObject {
            readonly property string monitorName: Hyprland.focusedMonitor?.name ?? ""
            // seeded as well as watched: a monitor is already focused by the
            // time this loads, and that first binding evaluation is not
            // guaranteed to reach the change handler below
            Component.onCompleted: if (monitorName)
                root.name = monitorName
            onMonitorNameChanged: if (monitorName)
                root.name = monitorName
        }
    }

    // ---------- sway / i3 ----------
    // Same shape as Hyprland above, against the other module Quickshell ships.
    // i3 itself is X11, where none of this applies; the module is here for sway,
    // which speaks the same IPC and is why it reads $SWAYSOCK first.
    Loader {
        active: root.compositor === "sway"
        sourceComponent: QtObject {
            readonly property string monitorName: I3.focusedMonitor?.name ?? ""
            Component.onCompleted: if (monitorName)
                root.name = monitorName
            onMonitorNameChanged: if (monitorName)
                root.name = monitorName
        }
    }

    // ---------- ext-workspace-v1 ----------
    // The last tier before giving up, for a compositor with no integration of
    // its own that still implements the protocol. It is a guess, and worth
    // knowing exactly how good a one:
    //
    // ext-workspace has no "focused" state, only "active", and every output has
    // an active workspace - so a snapshot cannot say which output the keyboard
    // is on. What it can see is *transitions*: a workspace going active means
    // the user went there, and where they went is an output. So this follows
    // workspace switching, and misses focus simply moving between two outputs
    // whose workspaces don't change. That is still strictly better than pinning
    // to the primary output, which is the alternative here.
    function adoptWindowset(windowset): void {
        const screens = windowset.projection ? windowset.projection.screens : null;
        if (screens && screens.length > 0)
            root.name = screens[0].name;
    }

    Variants {
        // Short-circuited so the WindowManager singleton is never touched (and
        // never binds the protocol) on a compositor that has a real tier above.
        model: root.compositor === "" ? WindowManager.windowsets : []

        QtObject {
            required property var modelData
            readonly property bool workspaceActive: modelData.active

            // With one output this is the answer; with several it is whichever
            // delegate was built last, i.e. no better than the primary fallback
            // it replaces - the transitions below are what make it right.
            Component.onCompleted: if (workspaceActive)
                root.adoptWindowset(modelData)
            onWorkspaceActiveChanged: if (workspaceActive)
                root.adoptWindowset(modelData)
        }
    }
}
