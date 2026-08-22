import QtQuick
import QtMultimedia
import "root:/services"

// One MediaPlayer per video wallpaper, opened once and kept open for the life
// of the process, with only the one being looked at ever unpaused.
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
// Nothing here is ever destroyed or re-sourced. Navigation only moves `current`
// and toggles `live`, which measure as no stall at all; the file opens happen in
// the warm pass below instead, while the selector that owns the pool is off
// screen.
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

    // Every video in the wallpaper folder. Routed through a joined string
    // because Wallpapers.list is a fresh array after every scan (they run on
    // every open, and on a timer while the cache is still generating), and a
    // list rebuilt straight from it would re-evaluate - and reopen every player
    // - on scans that changed nothing.
    readonly property string videoKey: Wallpapers.list.filter(w => w.video).map(w => w.path).join("\n")
    readonly property var videoPaths: root.videoKey === "" ? [] : root.videoKey.split("\n")

    // Paths that have a player, in the order they were opened. Appended to in
    // place: a var property holding a JS array deliberately doesn't notify on
    // mutation, which is what keeps each delegate's `path` below from
    // re-evaluating (and its player from reopening the file) every time another
    // entry joins. openCount is the Repeater's model, so bumping it after the
    // push is what actually builds the new player.
    property var openPaths: []
    property int openCount: 0

    function open(path: string): void {
        if (!path || root.openPaths.indexOf(path) >= 0)
            return;
        root.openPaths.push(path);
        root.openCount = root.openPaths.length;
    }
    onCurrentChanged: root.open(root.current)

    Timer {
        // One file per tick rather than the one-per-frame the thumbnail warm-up
        // uses: an open costs an order of magnitude more than a decode, so it
        // needs the gaps to stay off the render loop's back.
        interval: 250
        repeat: true
        running: root.warming && root.openCount < root.videoPaths.length
        onTriggered: root.open(root.videoPaths.find(p => root.openPaths.indexOf(p) < 0) ?? "")
    }

    Repeater {
        model: root.openCount

        VideoOutput {
            id: surface
            required property int index
            // Read once, as this delegate is built: openPaths is only ever
            // appended to in place (see above), so the binding has nothing to
            // re-evaluate on and the player below never has its source
            // rewritten out from under it.
            readonly property string path: root.openPaths[index]
            readonly property bool showing: root.current === surface.path

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
                source: "file://" + surface.path
                loops: MediaPlayer.Infinite
                videoOutput: surface
                audioOutput: AudioOutput { muted: true }
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
