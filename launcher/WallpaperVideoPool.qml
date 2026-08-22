import QtQuick
import QtMultimedia
import "root:/config"
import "root:/services"

// One MediaPlayer per video wallpaper, opened once and - with Settings.preload
// on - kept open for the life of the process, with only the one being looked at
// ever unpaused. With preload off the pool drains itself after the launcher
// closes instead: a decoder's frame pool is VRAM held for as long as the file
// is open, and that mode's contract is that an idle daemon holds nothing back.
//
// Opening a video file costs ~600ms of backend init the first time in a process
// and ~80ms every time after, all on the GUI thread, and both selectors used to
// pay that inside the navigation that needed it: the tiles grid built a whole
// player as the selection landed on a video tile and tore it down (~65ms more)
// as it left, and the carousel kept one player but re-pointed its source at
// each video it reached. Measured against a 16ms budget, every move on or off a
// video blocked the GUI thread for 70-115ms - the freeze that ate the start of
// the slide it landed in.
//
// Navigation only moves `current` and toggles `live`, which measure as no
// stall at all; the file opens happen in the warm pass below instead, while the
// selector that owns the pool is off screen. The only teardown is the drain,
// which also lands off screen. What a player decodes is the cached preview
// proxy where one exists (see the proxies note in Wallpapers) - the warm pass
// retargets a player opened against its source once the proxy lands, again off
// screen, so a first cold-cache session doesn't hold full-resolution decoders
// until a restart.
Item {
    id: root

    // Path of the video whose surface shows, "" for none. Opened on the spot if
    // the warm pass hasn't reached it yet - one stall on first sight of a file
    // rather than one per visit.
    property string current: ""
    // Whether `current` runs. Everything else sits paused on frame 0, which is
    // the frame the still thumbnail underneath it shows (see the ffmpeg call in
    // Wallpapers' scan), so a surface can stay up through a fade-out with
    // nothing to give the swap away.
    property bool live: false
    // Where the video surface sits inside this item. Not simply the item's own
    // bounds: the carousel's windows are a narrow frame onto a wider image that
    // pans with the strip, so its surface is wider than the item and moves
    // within it.
    property real surfaceX: 0
    property real surfaceY: 0
    property real surfaceWidth: root.width
    property real surfaceHeight: root.height
    // Opens one more file per tick while true. The owner keeps this off
    // whenever its selector is on screen: an open is ~80ms of GUI thread, so it
    // has to land somewhere nobody is looking.
    property bool warming: false
    // Whether this pool's selector is the one Settings.wallpaperStyle shows
    // (each selector owns a pool, style-gated so only one ever opens files).
    // The pool a style switch orphans holds players for a selector that can't
    // show them again, so it drains like preload-off does.
    property bool active: true

    // Every video in the wallpaper folder. Routed through a joined string
    // because Wallpapers.list is a fresh array after every scan (they run on
    // every open, and on a timer while the cache is still generating), and a
    // list rebuilt straight from it would re-evaluate - and reopen every player
    // - on scans that changed nothing.
    readonly property string videoKey: Wallpapers.list.filter(w => w.video).map(w => w.path).join("\n")
    readonly property var videoPaths: root.videoKey === "" ? [] : root.videoKey.split("\n")

    // What each open path should be decoding right now: the proxy once the
    // cache holds one, the source until then. A player opened before its proxy
    // landed is stale against this, which is what the warm pass's retarget
    // step looks for.
    function playSourceFor(path: string): string {
        const w = Wallpapers.list.find(x => x.path === path);
        return (w && w.proxy) ? w.proxy : path;
    }

    // Paths that have a player, in the order they were opened, and what each
    // one's player decodes (see playSourceFor). Appended to in place: a var
    // property holding a JS array deliberately doesn't notify on mutation,
    // which is what keeps each delegate's `path` below from re-evaluating (and
    // its player from reopening the file) every time another entry joins.
    // openCount is the Repeater's model, so bumping it after the push is what
    // actually builds the new player.
    property var openPaths: []
    property var openSources: []
    property int openCount: 0

    function open(path: string): void {
        if (!path || root.openPaths.indexOf(path) >= 0)
            return;
        root.openPaths.push(path);
        root.openSources.push(root.playSourceFor(path));
        root.openCount = root.openPaths.length;
    }
    onCurrentChanged: root.open(root.current)

    // What arms the warm pass: an unopened video, or a proxy landing for a
    // player that opened against its source. Cleared by the pass itself once a
    // tick finds neither, so the timer isn't left scanning for work that can't
    // appear.
    readonly property string proxyKey: Wallpapers.list.filter(w => w.video).map(w => w.proxy).join("\n")
    property bool warmWork: true
    onVideoKeyChanged: root.warmWork = true
    onProxyKeyChanged: root.warmWork = true

    Timer {
        // One file per tick rather than the one-per-frame the thumbnail warm-up
        // uses: an open costs an order of magnitude more than a decode, so it
        // needs the gaps to stay off the render loop's back.
        interval: 250
        repeat: true
        running: root.warming && root.warmWork
        onTriggered: {
            const next = root.videoPaths.find(p => root.openPaths.indexOf(p) < 0);
            if (next) {
                root.open(next);
                return;
            }
            // a re-source is the same ~80ms open as anything else here, so it
            // takes a tick of its own
            for (let i = 0; i < root.openCount; i++) {
                const want = root.playSourceFor(root.openPaths[i]);
                if (root.openSources[i] !== want) {
                    root.openSources[i] = want;
                    players.itemAt(i)?.retarget(want);
                    return;
                }
            }
            root.warmWork = false;
        }
    }

    // The drain. The players are the one resident a preload-off close doesn't
    // already shed - unmapping the window drops the scene graph, not
    // QtMultimedia's decoders - so idle would otherwise converge back to
    // preload-on's VRAM after one browse of the pane.
    readonly property bool retain: Settings.preload && root.active
    Connections {
        target: LauncherState

        function onShownChanged(): void {
            if (LauncherState.shown) {
                drain.stop();
                // a drained `current` has to be reopened by hand: the carousel
                // holds its videoSource across a close, so landing back on the
                // same video moves nothing and onCurrentChanged never refires
                root.open(root.current);
            } else if (!root.retain && root.openCount > 0) {
                drain.restart();
            }
        }
    }
    // retain going false mid-idle (a style switch is applied from the settings
    // pane while open, but settings.json is also hand-editable under the file
    // watcher) must still drain - the close that would have has already been
    // and gone
    onRetainChanged: if (!root.retain && !LauncherState.shown && root.openCount > 0)
        drain.restart()
    Timer {
        id: drain
        // Past the exit animation and (preload off) the unmap, so the ~65ms
        // per player the teardown costs on the GUI thread lands with nothing
        // rendering. Not worth racing: the whole point is that idle holds
        // nothing, and idle is long.
        interval: 1200
        onTriggered: {
            // model first, then the arrays truncated in place: reassigning
            // them would notify, re-evaluating every doomed delegate's
            // read-once `path`/`playPath` against an emptied array before the
            // Repeater gets to destroy it
            root.openCount = 0;
            root.openPaths.length = 0;
            root.openSources.length = 0;
            root.warmWork = true;
        }
    }

    Repeater {
        id: players
        model: root.openCount

        VideoOutput {
            id: surface
            required property int index
            // Read once, as this delegate is built: openPaths is only ever
            // appended to in place (see above), so the binding has nothing to
            // re-evaluate on and the player below never has its source
            // rewritten out from under it.
            readonly property string path: root.openPaths[index]
            // Same read-once trick, but assignable: the warm pass retargets it
            // when a proxy lands after this player opened, deliberately
            // severing the creation-time read (nothing else ever writes it).
            property string playPath: root.openSources[index]
            readonly property bool showing: root.current === surface.path

            function retarget(p: string): void {
                surface.playPath = p;
            }

            x: root.surfaceX
            y: root.surfaceY
            width: root.surfaceWidth
            height: root.surfaceHeight
            fillMode: VideoOutput.PreserveAspectCrop
            visible: surface.showing

            // Rewound on the way *out*, not on show: the paused frame is the
            // handover frame, and rewinding on show left a revisited player
            // sitting on whatever mid-clip frame it was paused at for the
            // beat the seek took to land - a visible content/brightness
            // flash over the frame-0 still underneath. Parking it at 0 while
            // nobody is looking gives the seek all the off-screen time it
            // needs, so showing starts from a frame already matching the
            // still. Seeking, pausing and starting a player that already has
            // its file open are all free; only the open itself isn't.
            function sync(): void {
                if (surface.showing && root.live) {
                    player.play();
                } else {
                    if (player.playbackState !== MediaPlayer.PausedState)
                        player.pause();
                    if (player.position > 0)
                        player.position = 0;
                }
            }
            onShowingChanged: surface.sync()
            // pause() on a player that has never run is what decodes its first
            // frame, so a pooled player already holds a frame ready to show by
            // the time anything navigates to it.
            Component.onCompleted: surface.sync()
            // one sync per player when the selector comes and goes, rather than
            // per player per navigation: `live` only moves when the pane or the
            // launcher does
            Connections {
                target: root
                function onLiveChanged() { surface.sync(); }
            }

            MediaPlayer {
                id: player
                source: "file://" + surface.playPath
                loops: MediaPlayer.Infinite
                videoOutput: surface
                audioOutput: AudioOutput { muted: true }
                // a retarget dropped the decoded frame along with the old
                // file; the same pause() as the creation-time sync lands the
                // new file's frame 0 ready for handover
                onSourceChanged: surface.sync()
                // ResourceError is what a missing/broken playback backend comes
                // back as; the rest (a codec it won't take, a file it can't
                // read) are about this one file and must not be reported as a
                // missing dependency. See Notifier.mediaPlaybackFailure for why
                // the classification happens here rather than there.
                onErrorOccurred: (error, errorString) => Notifier.mediaPlaybackFailure(error === MediaPlayer.ResourceError, errorString)
            }
        }
    }
}
