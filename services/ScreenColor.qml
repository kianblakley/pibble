pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// "Click any pixel on screen to use its color" - the eyedropper in the
// custom-palette editor, with a magnifier of our own.
//
// The magnifier is why this works the way it does. No compositor lets us
// decorate *its* picker: the portal's PickColor hands the whole interaction
// over and gives back only a color, which on niri is a bare crosshair. Drawing
// a magnifier means owning the interaction, and owning it means freezing the
// screen first - the surface has to cover every output to receive pointer
// motion at all, and once it does, what is underneath can no longer be seen or
// reached. hyprpicker filed exactly this under Caveats ("Freezes your displays
// when picking the color"); it is inherent to Wayland, not a shortcut.
//
// The frozen frame comes from grim writing an image, and that is a deliberate
// retreat. Two smarter backends were tried and rejected on evidence:
//
//  - org.gnome.Shell.Screenshot.Screenshot as implemented by niri renders the
//    wrong thing: a viewport shifted one screen to the right in the scroll
//    strip, at 2x the logical size instead of the output's real scale.
//  - Quickshell's ScreencopyView captures perfectly, but on Qt 6.11's
//    Wayland client the mere existence of a live screencopy context corrupts
//    surface/screen bookkeeping: the next time any of the shell's windows
//    maps or unmaps (the launcher does both around every pick), the daemon
//    segfaults in QWaylandWindow::handleScreensChanged. Bisected to exactly
//    this - the same click path runs clean with the context gone and crashes
//    with it idle but alive - and confirmed unchanged on quickshell 0.3.0
//    and 0.3.1 alike, so it is Qt's bug, not quickshell's. Do not bring
//    screencopy back without proving a fixed Qt first.
//
// So grim is the whole of what the eyedropper needs, and without it there is
// no eyedropper: the button is hidden rather than shown broken. Everything
// after the capture is Quickshell's own - the frame is an Image, and the pixel
// under the cursor is read straight out of it by the lens Canvas in
// ColorPickerOverlay. Nothing external reads a pixel.
//
// Two fallbacks used to sit behind grim and both were dropped, each for the
// same reason: it cost a dependency to cover a case that barely existed.
//
//  - niri's own screenshot action, for a niri session without grim. Free of
//    any package, but it costs a 5K PNG round trip paid while the launcher's
//    exit animation is still playing, against grim's uncompressed ppm.
//  - org.gnome.Shell.Screenshot.PickColor over gdbus, which handed the whole
//    interaction to the compositor and gave back a color with no magnifier of
//    ours. That interface is GNOME's by name only, and GNOME never reaches
//    this file at all: it implements no wlr-layer-shell, so none of pibble's
//    windows map there. niri answers it too, which made it a niri-only rescue
//    for a capture that had already failed - and glib2's gdbus was the price.
//    hyprpicker sat behind that in turn, and went first: it wants
//    wlr-screencopy exactly as grim does, so it never reached a session grim
//    could not.
//
// Everything below is written without backslashes on purpose: these commands
// are QML template literals, where an invalid escape (sed's \( or \1) is a
// syntax error in the whole file rather than something bash ever sees. Bash's
// (dollar)(brace) parameter expansions are off the menu for the same reason -
// QML claims that syntax for interpolation - hence the tr/cut spellings.
Singleton {
    id: root

    // Set for the whole pick, capture included, so a second one cannot start
    // underneath the first.
    property bool picking: false
    signal picked(string hex)
    signal failed

    // False until probe() has actually found grim, rather than optimistically
    // true: where nothing can pick, a button that appears and then vanishes
    // reads worse than one that was never there.
    property bool available: false
    property bool probed: false
    // Whether grim can capture a frame, and so whether the magnifier overlay
    // runs. It is the whole of what makes a pick possible: with no frame there
    // is no pixel to read, and nothing else is asked to pick on our behalf.
    property bool canMagnify: false

    // While true the overlay owns the screen. `shotPath` is the frozen frame
    // it samples, deleted the moment the pick ends.
    property bool overlayActive: false
    property string shotPath: ""
    // tmpfs, not the cache dir: the frame is 33MB of throwaway written and
    // read back within a second - the runtime dir keeps that off the disk
    // entirely and shaves the write+read out of the wait.
    readonly property string framePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pibble-frame.ppm"

    function probe(): void {
        if (root.probed || probeProcess.running)
            return;
        probeProcess.running = true;
    }

    // Called the moment the hand-off starts, with the launcher's exit
    // animation still ahead: the transparent overlay takes the screen right
    // away, so the whole grab-the-screen ceremony plays out *under* the
    // animation instead of after it.
    function prepare(): void {
        if (root.picking)
            return;
        root.picking = true;
        if (root.canMagnify)
            root.overlayActive = true;
    }

    // Called once the exit animation has fully played. An Esc during the
    // animation already cancelled through the overlay's own key handling, and
    // a cancelled pick stays cancelled.
    function pick(): void {
        if (!root.picking)
            return;
        if (root.canMagnify)
            settle.restart();
        else
            root.failed();
    }

    // The launcher's fade has already reached opacity 0 when pick() runs, so
    // its pixels can't contaminate the frame - only its compositor-side blur
    // region needs the actual unmap, which the compositor applies within a
    // frame, well inside the capture tool's own startup. This margin covers
    // exactly that.
    Timer {
        id: settle
        interval: 15
        onTriggered: {
            if (!grimProcess.running)
                grimProcess.running = true;
        }
    }

    // grim straight from screencopy to uncompressed ppm on tmpfs, no shell in
    // between, and the only way a frame is ever captured. A failure ends the
    // pick: there is no second road to the screen that costs nothing, and
    // asking another process to pick for us was worth less than the
    // dependency it cost.
    Process {
        id: grimProcess
        command: ["grim", "-t", "ppm", root.framePath]
        onExited: exitCode => {
            if (!root.picking) {
                Quickshell.execDetached(["rm", "-f", "--", root.framePath]);
                return;
            }
            if (exitCode === 0) {
                root.shotPath = root.framePath;
            } else {
                root.overlayActive = false;
                root.picking = false;
                root.failed();
            }
        }
    }

    // Both ways out of the overlay.
    function finishOverlay(hex: string): void {
        const upper = hex.toUpperCase();
        root.closeOverlay();
        root.announce(upper);
        root.picked(upper);
    }
    function cancelOverlay(): void {
        root.closeOverlay();
        root.failed();
    }
    function closeOverlay(): void {
        root.overlayActive = false;
        root.picking = false;
        if (root.shotPath) {
            Quickshell.execDetached(["rm", "-f", "--", root.shotPath]);
            root.shotPath = "";
        }
    }

    // Called by the overlay when the captured frame never becomes usable.
    function magnifyFailed(): void {
        root.overlayActive = false;
        root.picking = false;
        root.failed();
    }

    // Puts the picked color on the clipboard and says so. Split out of the pick
    // itself so a cancel stays silent: the only thing worth announcing is a
    // color the user actually chose.
    function announce(hex: string): void {
        deliver.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            hex="$1"; dir="$2"; notify="$3"; deps="$4"
            if command -v wl-copy >/dev/null 2>&1; then
                printf '%s' "$hex" | wl-copy
            else
                [ "$deps" = 1 ] && notify-send -a pibble -i system-software-install "$7" "$8"
                exit 0
            fi
            # a swatch rides along as notification media, the same way a copied
            # clipboard image does - a hex string alone is hard to read back
            img=""
            if command -v ffmpeg >/dev/null 2>&1; then
                mkdir -p "$dir"
                img="$dir/picked.png"
                # lavfi's color source wants 0xRRGGBB, and the leading # of a
                # hex would open a comment in this shell besides. format=rgb24
                # inside the chain rather than -pix_fmt on the output: the
                # source otherwise negotiates yuv and the swatch lands a step
                # off the color that was picked.
                ffmpeg -y -v error -f lavfi -i "color=c=0x$(printf '%s' "$hex" | cut -c2-):s=96x96,format=rgb24" -frames:v 1 "$img" 2>/dev/null || img=""
            fi
            if [ "$notify" = 1 ]; then
                if [ -n "$img" ]; then
                    notify-send -a pibble -i edit-copy -h "string:image-path:$img" "$5" "$6"
                else
                    notify-send -a pibble -i edit-copy "$5" "$6"
                fi
            fi`, "_", hex, SystemInfo.cacheRoot + "/swatches",
            Settings.alertEnabled("actions") ? "1" : "0",
            Settings.alertEnabled("missingDeps") ? "1" : "0",
            // the shell's language is a QML question, so these arrive already
            // translated as argv rather than being built inside the script
            Strings.tr("Copied to clipboard"), hex,
            Strings.tr("wl-copy not found"),
            Strings.tr("wl-copy (wl-clipboard) is used to place clipboard history entries back on the clipboard - install it to copy from this page.")];
        deliver.running = true;
    }

    Process { id: deliver }

    // Names what this session can do without invoking any of it - nothing
    // appears on screen and no pixel is read. It asks one question now, since
    // grim is the only thing that can freeze the screen: is grim installed?
    // Still a subprocess rather than a QML test, because PATH is the point -
    // a grim in ~/.local/bin counts, and only a shell resolves that.
    Process {
        id: probeProcess
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            command -v grim >/dev/null 2>&1 && echo shot=grim || echo shot=no`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.canMagnify = text.indexOf("shot=grim") >= 0;
                root.available = root.canMagnify;
                root.probed = true;
            }
        }
    }
}
