pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// The screen recorder: `pibble record` starts one and the same command, or
// stop in the tools menu (see ui/ToolsMenu.qml - while a recording runs its
// controls are a ring of their own there), ends it; `pibble record pause` and
// the menu's pause hold it and carry it on. Nothing else of it is on the
// screen, so nothing of pibble's is in the recording but what is asked for.
//
// The recording itself is wf-recorder's. It is the one recorder that asks for
// nothing but what grim already asks for - wlr-screencopy, which is what makes
// pibble's compositors pibble's compositors - where the alternatives each want
// more: a portal and a PipeWire session, or a setuid helper to read the
// framebuffer directly. What it costs is that the encode is on the CPU unless
// told otherwise, and telling it otherwise is a question about the GPU that
// this file cannot answer - hence Settings.recordArgs, passed through as-is,
// and a default (see startSegment) that only goes as far as picking a format
// that plays everywhere.
//
// wf-recorder cannot pause. Stopping its process with SIGSTOP would hold the
// capture, but every frame is stamped with the wall clock, so the file would
// come out with the whole pause in it as one frozen frame. So a pause ends the
// file being written instead, and a resume starts another: a recording is a
// run of segments, written next to where it will land under hidden names, and
// stitched into the one file at the end (see finish) - without re-encoding,
// since every segment was made with the same settings.
//
// What is recorded is always picked first on the tools overlay (ScreenTools'
// "region" mode, whose answer arrives here as regionChosen): a rectangle
// dragged on the output in use, or that whole output for a click with no drag
// in it. A resume records the same.
Singleton {
    id: root

    // A recording is under way, paused or not - from the moment it is started,
    // not from its first frame, since there is no telling the two apart from
    // out here - until its file has been put together.
    property bool recording: false
    // held: no wf-recorder running, and the next segment not yet asked for
    property bool paused: false
    // it has been told to finish and is writing the file out
    property bool stopping: false
    // whole seconds recorded, pauses left out, for the tools menu
    property int elapsed: 0
    // seconds recorded by the segments already finished, and when the one
    // running now started
    property real banked: 0
    property double segmentStartedAt: 0

    // what is being recorded, kept for every segment after the first
    property string output: ""
    property string geometry: ""
    // the file the recording ends up as, and the segments it is put together
    // out of, in order
    property string file: ""
    property var segments: []
    // the last thing wf-recorder said, for the error if nothing was written
    property string lastLine: ""
    // what the segment ending now is ending for: "pause" or "stop"
    property string ending: ""

    // `pibble record`, and the menu's record: stop if recording, else ask for
    // a rectangle (or a click for the whole output).
    function toggleRegion(): void {
        if (root.recording)
            root.stop();
        else
            ScreenTools.request("region");
    }

    // `pibble record pause`: hold a recording, or carry a held one on.
    function togglePause(): void {
        // a segment still being closed for a pause is asked again once it is
        // gone: a resume in the meantime would find the recorder still there
        if (!root.recording || root.stopping || (root.paused && recorder.running))
            return;
        if (root.paused) {
            root.paused = false;
            root.startSegment();
        } else if (recorder.running) {
            root.ending = "pause";
            root.bank();
            root.paused = true;
            recorder.signal(2);
            root.announce("paused");
        }
    }

    // Started, paused and resumed, each with the way to its controls: once
    // it is going nothing of the recording is on the screen (see the
    // header), so this is the one reminder that it is, and of where it
    // stops. They are pibble's own and so replace one another in the
    // flyout rather than piling up, "Recording saved" included.
    function announce(what: string): void {
        const how = Strings.tr("Open the pibble tools menu to pause or stop it.");
        if (what === "paused")
            Notifier.action("media-playback-pause", Strings.trf("Recording paused at %1", root.clock(root.elapsed)), Strings.tr("Open the pibble tools menu to resume or stop it."), "");
        else
            Notifier.action("media-record", what === "resumed" ? Strings.tr("Recording resumed") : Strings.tr("Recording started"), how, "");
    }

    Connections {
        target: ScreenTools
        function onRegionChosen(output: string, geometry: string): void {
            // a beat for the overlay's dim to actually leave the screen, so it
            // is not the recording's first frames
            pending.output = output;
            pending.geometry = geometry;
            pending.restart();
        }
    }
    Timer {
        id: pending
        property string output: ""
        property string geometry: ""
        interval: 120
        onTriggered: root.start(pending.output, pending.geometry)
    }

    // `geometry` is wf-recorder's "x,y WxH" in layout coordinates, or "" for
    // the whole of `output`.
    function start(output: string, geometry: string): void {
        if (root.recording || recorder.running)
            return;
        const dir = SystemInfo.expandHome(Settings.recordDir || Defaults.recordDir);
        root.file = dir + "/recording-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".mp4";
        root.segments = [];
        root.output = output;
        root.geometry = geometry;
        root.lastLine = "";
        root.elapsed = 0;
        root.banked = 0;
        root.paused = false;
        root.stopping = false;
        root.recording = true;
        root.startSegment();
    }

    // The next segment: hidden beside the file it will become part of, so the
    // stitching at the end is a move within one filesystem and nothing half
    // made shows up in the recordings folder meanwhile.
    function startSegment(): void {
        if (recorder.running)
            return;
        const slash = root.file.lastIndexOf("/");
        const segment = root.file.slice(0, slash + 1) + "." + root.file.slice(slash + 1, -4) + ".part" + (root.segments.length + 1) + ".mp4";
        root.segments = root.segments.concat([segment]);
        root.ending = "";
        root.segmentStartedAt = Date.now();
        recorder.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            file="$1"; output="$2"; geometry="$3"; audio="$4"; extra="$5"
            command -v wf-recorder >/dev/null 2>&1 || { echo "MISSING"; exit 0; }
            mkdir -p "$(dirname "$file")" || { echo "NODIR"; exit 0; }
            echo "FILE $file"
            set -- -f "$file"
            # a region is named in layout coordinates, which already say which
            # output it is on; naming the output as well is only for the whole
            if [ -n "$geometry" ]; then
                set -- "$@" -g "$geometry"
            elif [ -n "$output" ]; then
                set -- "$@" -o "$output"
            fi
            case "$audio" in
            desktop)
                # the monitor of whatever the speakers are, which is what
                # "record the sound too" means; without pactl there is no
                # asking, and a silent recording beats none
                sink=$(pactl get-default-sink 2>/dev/null)
                [ -n "$sink" ] && set -- "$@" "--audio=$sink.monitor"
                ;;
            mic) set -- "$@" --audio ;;
            esac
            # Left to itself wf-recorder writes whatever its build prefers -
            # VP9 on the one this was tested against - and asked for H.264
            # with nothing else said, it writes the 4:4:4 kind that almost
            # nothing but a desktop player will open. So when the encoder is
            # there and the user has not chosen one, it is asked for the H.264
            # everything plays: 4:2:0, at a preset a CPU keeps up with.
            case " $extra " in
            *" -c "* | *" --codec"*) ;;
            *)
                if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' libx264 '; then
                    set -- "$@" -c libx264 -x yuv420p -p preset=veryfast
                fi
                ;;
            esac
            # exec, so that the process this Process holds is the recorder
            # itself and the interrupt that ends the segment reaches it
            # rather than a shell; $extra unquoted, to split into arguments
            exec wf-recorder "$@" $extra`,
            "_", segment, root.output, root.geometry, Settings.recordAudio, Settings.recordArgs];
        recorder.running = true;
    }

    // the running segment's time, added to what is already recorded
    function bank(): void {
        if (root.segmentStartedAt > 0)
            root.banked += (Date.now() - root.segmentStartedAt) / 1000;
        root.segmentStartedAt = 0;
        root.elapsed = Math.floor(root.banked);
    }

    // SIGINT is what wf-recorder finishes a file on: it stops capturing,
    // flushes the encoder and writes the container's index. Anything harsher
    // leaves an mp4 with no index, which is to say no recording.
    function stop(): void {
        if (!root.recording || root.stopping)
            return;
        root.stopping = true;
        if (recorder.running) {
            root.ending = "stop";
            root.bank();
            recorder.signal(2);
            giveUp.restart();
        } else {
            // paused: every segment is already written
            root.finish();
        }
    }

    // A recorder that ignores the interrupt is killed after all - a broken
    // segment is still better than an indicator that can never be dismissed.
    Timer {
        id: giveUp
        interval: 8000
        onTriggered: {
            if (recorder.running)
                recorder.running = false;
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root.recording && !root.paused && !root.stopping
        onTriggered: root.elapsed = Math.floor(root.banked + (Date.now() - root.segmentStartedAt) / 1000)
    }

    Process {
        id: recorder
        property bool refused: false
        onStarted: recorder.refused = false
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("FILE ")) {
                    // the segment really is under way - said here rather
                    // than on asking, so a recorder that is missing or has
                    // nowhere to write says only that
                    root.announce(root.segments.length > 1 ? "resumed" : "started");
                    return;
                } else if (line === "MISSING") {
                    recorder.refused = true;
                    Notifier.missingDependency(Strings.tr("wf-recorder not found"), Strings.tr("wf-recorder is used to record the screen - install it to use `pibble record`."));
                } else if (line === "NODIR") {
                    recorder.refused = true;
                    Notifier.error(Strings.tr("Recording failed"), Strings.trf("The recordings folder (%1) could not be created.", Settings.recordDir));
                } else if (line.trim()) {
                    root.lastLine = line.trim();
                }
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.lastLine = line.trim();
            }
        }
        onExited: {
            giveUp.stop();
            // one of the two refusals above, which has already said what was
            // wrong - with nothing recorded, there is nothing to put together
            if (recorder.refused && root.segments.length <= 1) {
                root.reset();
                return;
            }
            // held, and waiting for a resume
            if (root.ending === "pause" && !root.stopping)
                return;
            // Told to stop, or a recorder that died on its own (the output
            // went away, the encoder gave up): either way what has been
            // recorded so far is the recording.
            root.bank();
            root.stopping = true;
            root.finish();
        }
    }

    // Puts the segments together into root.file - moved into place when there
    // is only one, joined without re-encoding when there are more - and drops
    // the ones that came out empty, as a pause in the first instant leaves.
    function finish(): void {
        wrapUp.complaint = root.lastLine;
        wrapUp.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            file="$1"; thumb="$2"; shift 2
            list="$file.parts.txt"
            : > "$list"
            count=0; first=""
            for part in "$@"; do
                if [ -s "$part" ]; then
                    count=$((count + 1))
                    [ -n "$first" ] || first="$part"
                    echo "file '$part'" >> "$list"
                else
                    rm -f "$part"
                fi
            done
            if [ "$count" = 0 ]; then
                rm -f "$list"
                echo EMPTY
                exit 0
            elif [ "$count" = 1 ]; then
                mv -f "$first" "$file"
            elif ffmpeg -y -v error -f concat -safe 0 -i "$list" -c copy "$file" 2>/dev/null; then
                for part in "$@"; do
                    rm -f "$part"
                done
            else
                rm -f "$file"
                echo "NOJOIN $first"
                rm -f "$list"
                exit 0
            fi
            rm -f "$list"
            mkdir -p "$(dirname "$thumb")"
            rm -f "$thumb"
            command -v ffmpeg >/dev/null 2>&1 && ffmpeg -y -v error -i "$file" -frames:v 1 -vf "scale=480:-2" "$thumb" 2>/dev/null
            [ -s "$thumb" ] && echo "THUMB" || echo "SAVED"`,
            "_", root.file, SystemInfo.cacheRoot + "/recordings/last.png"].concat(root.segments);
        wrapUp.running = true;
    }

    Process {
        id: wrapUp
        property string complaint: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const verdict = text.trim();
                const file = root.file;
                root.reset();
                if (verdict === "EMPTY" || verdict === "") {
                    Notifier.error(Strings.tr("Recording failed"), wrapUp.complaint || Strings.tr("wf-recorder wrote nothing."));
                    return;
                }
                if (verdict.startsWith("NOJOIN ")) {
                    // the parts are left where they are rather than lost
                    Notifier.error(Strings.tr("Recording failed"), Strings.trf("The paused parts could not be joined - they are kept beside it, starting with %1.", verdict.slice(7)));
                    return;
                }
                Notifier.action("media-record", Strings.tr("Recording saved"), file, verdict === "THUMB" ? SystemInfo.cacheRoot + "/recordings/last.png" : "");
            }
        }
    }

    function reset(): void {
        root.recording = false;
        root.paused = false;
        root.stopping = false;
        root.segments = [];
        root.ending = "";
        root.segmentStartedAt = 0;
    }

    // m:ss, or h:mm:ss once it has run that long
    function clock(seconds: int): string {
        const two = n => String(n).padStart(2, "0");
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds / 60) % 60;
        const s = seconds % 60;
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s);
    }
}
