pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// "Click any pixel on screen to use its color" - the eyedropper in the
// custom-palette editor, with hyprpicker's magnifier.
//
// The magnifier is why this works the way it does. No compositor lets us
// decorate *its* picker: the portal's PickColor hands the whole interaction
// over and gives back only a color, which on niri is a bare crosshair. Drawing
// a magnifier means owning the interaction, and owning it means freezing the
// screen first - the surface has to cover every output to receive pointer
// motion at all, and once it does, what is underneath can no longer be seen or
// reached. hyprpicker files exactly this under Caveats ("Freezes your displays
// when picking the color"); it is inherent to Wayland, not a shortcut.
//
// The frozen frame comes from a plain subprocess writing an image - grim
// where it exists, else niri's own screenshot action - and that is a
// deliberate retreat. Two smarter backends were tried and rejected on
// evidence:
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
// grim keeps the capture cheap (uncompressed ppm both ways, a few hundred
// ms); without it, niri's action costs a 5K PNG round trip, paid while the
// launcher's exit animation is already playing. Sessions with neither fall
// back to the compositor's own picker - org.gnome.Shell.Screenshot.PickColor
// (native on GNOME and niri) or hyprpicker - with no magnifier of ours. KDE
// and COSMIC get no eyedropper at all; the button is hidden rather than shown
// broken. The overlay also falls back to that picker at runtime if no frame
// arrives, so a missing capture degrades instead of hanging.
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

    // False until probe() has actually found a backend, rather than
    // optimistically true: where nothing can pick, a button that appears and
    // then vanishes reads worse than one that was never there.
    property bool available: false
    property bool probed: false
    // Whether a frame can be captured, and so whether the magnifier overlay
    // runs. When false but `canPick` is true the compositor's own picker runs
    // instead - no magnifier, but it picks.
    property bool canMagnify: false
    property bool canPick: false

    // While true the overlay owns the screen. `shotPath` is the frozen frame
    // it samples, deleted the moment the pick ends - on niri the compositor
    // writes it into the user's screenshot folder, and one file per pick
    // would pile up fast.
    property bool overlayActive: false
    property string shotPath: ""
    // Which capture the probe found, so the pick doesn't re-discover it with
    // a bash round trip every time: "grim" runs the binary directly, "niri"
    // goes through the newest-file dance below.
    property string captureBackend: ""
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
            pickProcess.running = true;
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
            if (root.captureBackend === "grim") {
                if (!grimProcess.running)
                    grimProcess.running = true;
            } else if (!captureProcess.running) {
                captureProcess.running = true;
            }
        }
    }

    // The fast path: grim straight from screencopy to uncompressed ppm on
    // tmpfs, no shell in between. A failure falls through to the niri dance,
    // and from there to the compositor's own picker.
    Process {
        id: grimProcess
        command: ["grim", "-t", "ppm", root.framePath]
        onExited: exitCode => {
            if (!root.picking) {
                Quickshell.execDetached(["rm", "-f", "--", root.framePath]);
                return;
            }
            if (exitCode === 0)
                root.shotPath = root.framePath;
            else
                captureProcess.running = true;
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
    // Remembered, so the next pick goes straight to the fallback instead of
    // timing out again.
    function magnifyFailed(): void {
        root.overlayActive = false;
        root.canMagnify = false;
        if (root.canPick) {
            pickProcess.running = true;
        } else {
            root.picking = false;
            root.failed();
        }
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
            if command -v magick >/dev/null 2>&1; then
                mkdir -p "$dir"
                img="$dir/picked.png"
                magick -size 96x96 xc:"$hex" "$img" 2>/dev/null || img=""
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
    // appears on screen and no pixel is read.
    Process {
        id: probeProcess
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            has_name() { gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1" 2>/dev/null | grep -q true; }
            pick=no
            shot=no
            if has_name org.gnome.Shell.Screenshot; then
                pick=yes
            fi
            command -v hyprpicker >/dev/null 2>&1 && pick=yes
            shot=no
            command -v grim >/dev/null 2>&1 && shot=grim
            [ "$shot" = no ] && [ -n "$NIRI_SOCKET" ] && shot=niri
            echo "pick=$pick shot=$shot"`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.canPick = text.indexOf("pick=yes") >= 0;
                root.captureBackend = text.indexOf("shot=grim") >= 0 ? "grim"
                                    : text.indexOf("shot=niri") >= 0 ? "niri" : "";
                root.canMagnify = root.captureBackend !== "";
                root.available = root.canPick || root.canMagnify;
                root.probed = true;
            }
        }
    }

    // Freezes the screen to a file and hands back its path - the no-grim
    // road. niri writes into the user's configured screenshot folder under
    // its own timestamped name, so the only handle back is "the newest file
    // that was not there before" - found by polling, then trusted only once
    // its PNG trailer has landed so a half-written file never gets decoded.
    Process {
        id: captureProcess
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            if [ -n "$NIRI_SOCKET" ]; then
                line=$(grep -m1 'screenshot-path' "$HOME/.config/niri/config.kdl" 2>/dev/null | grep -v '^ *//' | grep -o '"[^"]*"' | head -1)
                tpl=$(printf '%s' "$line" | tr -d '"')
                [ -z "$tpl" ] && tpl="$HOME/Pictures/Screenshots/x.png"
                dir=$(dirname "$tpl")
                case "$dir" in "~"*) dir="$HOME"$(printf '%s' "$dir" | cut -c2-) ;; esac
                [ -d "$dir" ] || exit 1
                before=$(ls -t "$dir" 2>/dev/null | head -1)
                niri msg action screenshot-screen >/dev/null 2>&1 || exit 1
                for _ in $(seq 1 150); do
                    now=$(ls -t "$dir" 2>/dev/null | head -1)
                    if [ -n "$now" ] && [ "$now" != "$before" ]; then
                        f="$dir/$now"
                        # a finished PNG ends in its IEND chunk - cheaper and
                        # quicker than waiting out a size-stability window
                        if [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 1000 ] && tail -c 12 "$f" 2>/dev/null | grep -q IEND; then
                            printf '%s' "$f"
                            exit 0
                        fi
                    fi
                    sleep 0.02
                done
            fi
            exit 1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (!root.picking) {
                    // cancelled while the capture was still in flight - the
                    // frame arriving now belongs to nobody
                    if (path)
                        Quickshell.execDetached(["rm", "-f", "--", path]);
                    return;
                }
                if (path) {
                    root.shotPath = path;
                } else {
                    // nothing to magnify: fall back to letting the compositor
                    // run its own picker rather than giving up
                    root.overlayActive = false;
                    pickProcess.running = true;
                }
            }
        }
    }

    // Fallback only, for sessions that can pick but not capture. No magnifier -
    // the compositor draws whatever it draws.
    Process {
        id: pickProcess
        // The gdbus --timeout is in seconds and has to be generous: it bounds
        // how long the user has to click, and the default 25 is short enough
        // that hesitating is enough to abort the pick.
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            emit() { awk '{ printf "#%02X%02X%02X", int($1 * 255 + 0.5), int($2 * 255 + 0.5), int($3 * 255 + 0.5) }'; }

            if gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.gnome.Shell.Screenshot 2>/dev/null | grep -q true; then
                out=$(gdbus call --timeout 300 --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.PickColor 2>/dev/null)
                # the only digits in a reply are the three doubles themselves,
                # so everything else can just be blanked out
                set -- $(printf '%s' "$out" | tr -cs '0-9.' ' ')
                if [ $# = 3 ]; then
                    printf '%s %s %s' "$1" "$2" "$3" | emit
                    exit 0
                fi
                exit 1
            fi

            if command -v hyprpicker >/dev/null 2>&1; then
                hex=$(hyprpicker -f hex -n 2>/dev/null | tr -d ' ')
                case "$hex" in
                    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) printf '%s' "$hex"; exit 0 ;;
                esac
            fi
            exit 1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const hex = text.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                    const upper = hex.toUpperCase();
                    root.announce(upper);
                    root.picked(upper);
                } else {
                    root.failed();
                }
            }
        }
        // cleared here rather than beside the emit above so it is false
        // whichever way the pick ended, cancel and crash included
        onExited: root.picking = false
    }
}
