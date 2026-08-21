pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// The resolved palette, type scale and surfaces every window paints with.
//
// Named schemes plus two computed ones: "matugen" (labelled "Dynamic" in
// settings) samples the current wallpaper for the launcher and volume OSD and
// tints each notification from its own app icon; "custom" is the user's own
// palette from the color picker.
Singleton {
    id: root

    readonly property var presets: [
        {
            id: "amber",
            name: "Amber",
            accent: "#e8a24a",
            fg: "#f3ede4",
            muted: "#8a8378"
        },
        {
            id: "frost",
            name: "Frost",
            accent: "#7ab8e0",
            fg: "#e6eef4",
            muted: "#83919c"
        },
        {
            id: "moss",
            name: "Moss",
            accent: "#a3c76a",
            fg: "#eef3e4",
            muted: "#8d9378"
        },
        {
            id: "rose",
            name: "Rose",
            accent: "#e07a9a",
            fg: "#f4e8ec",
            muted: "#9c8389"
        },
        {
            id: "custom",
            name: "Custom",
            accent: "",
            fg: "",
            muted: ""
        },
        {
            id: "matugen",
            name: "Dynamic",
            accent: "",
            fg: "",
            muted: ""
        }
    ]

    // filled in from matugen (current wallpaper) at startup and on every pick
    property var dynamic: ({
        accent: "#e8a24a",
        fg: "#f3ede4",
        muted: "#8a8378"
    })
    // user-defined palette, edited via the color picker under the theme row
    readonly property var custom: ({
        accent: Settings.customAccent,
        fg: Settings.customFg,
        muted: Settings.customMuted
    })

    readonly property var active: Settings.theme === "matugen" ? root.dynamic : Settings.theme === "custom" ? root.custom : (root.presets.find(t => t.id === Settings.theme) ?? root.presets[0])

    readonly property color accent: root.active.accent
    readonly property color fg: root.active.fg
    readonly property color muted: root.active.muted
    // backdrop the launcher dims the screen with
    readonly property color surface: "#0a0908"
    // card surface behind both flyouts
    readonly property color flyoutSurface: "#0c0c10"

    // "" (system default) falls back to the GTK monospace font the `pibble`
    // script resolved into QS_FONT_FAMILY at startup (see export_font_family) -
    // Qt's own font.family: "" resolution isn't reliable in a bare
    // layer-shell session, the same problem export_icon_theme works around
    // for icons.
    readonly property string fontFamily: Settings.fontFamily || Quickshell.env("QS_FONT_FAMILY") || ""

    function fontSize(px: int): int {
        return Math.round(px * Settings.fontScale);
    }

    // Every corner radius the shell draws goes through here, so Settings >
    // General > "Rounded corners" can square all of them with one switch -
    // pass the radius the corner wants when rounding is on. The only radius
    // that deliberately bypasses this is the launch reveal's growing circle
    // (LauncherWindow's growMask, and LaunchPreview's stand-in for it): that
    // one is animation geometry rather than a corner, and the compositor blur
    // region traced to match it is a true ellipse either way (see
    // LauncherState.revealBlurDiameter).
    function radius(px: real): real {
        return Settings.roundedCorners ? px : 0;
    }

    // "matugen" ("Dynamic"): near-black card, bubble tinted from the app icon;
    // the volume level bar still follows the wallpaper palette
    readonly property bool tintNotificationsFromIcon: Settings.theme === "matugen"
    readonly property var notification: root.tintNotificationsFromIcon ? ({
            accent: root.active.accent,
            fg: "#f2f0ee",
            muted: "#908c87"
        }) : root.active

    // ---------- matugen (Dynamic theme) ----------

    // Kicked off imperatively from SettingsStore's initial load and from
    // LauncherWindow.commitWallpaper() on every wallpaper pick - never via a
    // `running: Settings.theme === "matugen"`-style binding. That was tried and
    // races: the settings file load is async, so Settings.currentWallpaper is
    // still "" (the adapter's blank default) when the tree is first
    // constructed, even though Settings.theme already reads "matugen" (its
    // default too). The natural fix looked like adding
    // `&& Settings.currentWallpaper !== ""` to the binding, but that still
    // loses: once the load completes, `running` and `command` both react to the
    // same Settings.currentWallpaper change as sibling bindings on this
    // Process, and Qt doesn't guarantee `command` has re-evaluated to the
    // loaded path before `running`'s flip spawns the process - so it reliably
    // ran with an empty $WALL anyway. Driving both imperatively, one statement
    // after the other, forces the ordering.
    function sampleWallpaper(): void {
        if (matugen.running)
            matugen.rerun = true;
        else
            matugen.running = true;
    }

    Process {
        id: matugen

        property bool rerun: false
        onRunningChanged: {
            if (!running && rerun) {
                rerun = false;
                Qt.callLater(() => running = true);
            }
        }

        // samples Settings.currentWallpaper (set when a pick is committed)
        // rather than asking the compositor what's on screen - wallCommand is a
        // freeform user command and may not even go through the tool we'd
        // query, so the picker's own record of what it applied is the only
        // source that's guaranteed to match
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            command -v matugen >/dev/null || { echo NOMATUGEN; exit 0; }
            img="$1"
            [ -n "$img" ] || exit 0
            matugen image "$img" --json hex --dry-run --prefer saturation 2>/dev/null`, "_", Wallpapers.matugenSource]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOMATUGEN") {
                    if (Settings.theme === "matugen")
                        Notifier.missingDependency(Strings.tr("matugen not found"), Strings.tr("Install matugen to use the Dynamic theme."));
                    return;
                }
                // empty output is benign (the wallpaper daemon not up yet at
                // login, no wallpaper set, or a run torn down early): keep the
                // last palette silently instead of raising a false alarm
                if (!text.trim())
                    return;
                try {
                    const colors = JSON.parse(text).colors;
                    root.dynamic = {
                        accent: colors.primary.dark.color,
                        fg: colors.on_surface.dark.color,
                        muted: colors.outline.dark.color
                    };
                } catch (e) {
                    if (Settings.theme === "matugen")
                        Notifier.error(Strings.tr("Matugen theme failed"), Strings.tr("matugen returned no palette for the current wallpaper"));
                }
            }
        }
    }
}
