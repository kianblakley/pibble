import QtQuick
import Quickshell.Widgets
import "root:/config"
import "root:/services"
import "root:/ui"

// Wallpaper selector, "carousel" style: an infinite horizontal strip of
// narrow parallax windows with the selected wallpaper always centered.
// One shared video player stands in for whichever cell holds the selection
// rather than one per cell - see the note above it for why.
Item {
    id: root

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        root.opacity = 0.004;
    }
    anchors.centerIn: parent
    // slots actually shown; delegates beyond that (up to
    // restSpan) sit pre-positioned but faded out, ready to slide
    // into view without popping in from nowhere
    readonly property int halfVisible: Math.floor((Settings.wallsVisible - 1) / 2)
    readonly property int bufferSlots: 2
    readonly property int restSpan: halfVisible + bufferSlots
    readonly property int totalSlots: 2 * restSpan + 1
    // A count change strands the Repeater's surviving delegates:
    // their absStep was imperatively relabeled by rebalance()
    // (congruent mod the *old* totalSlots), and freshly added
    // ones init assuming step 0 - so rebuild the whole
    // contiguous window around the current selection, keeping
    // LauncherState.carouselStep congruent with LauncherState.wallpaperSelected. callLater
    // lets the Repeater finish adding/removing delegates first;
    // the carousel is hidden while the settings pane is open,
    // so the relayout is never seen.
    onTotalSlotsChanged: Qt.callLater(() => {
        LauncherState.carouselStep = LauncherState.wallpaperSelected;
        for (let i = 0; i < cells.count; i++) {
            const c = cells.itemAt(i);
            if (c)
                c.absStep = LauncherState.wallpaperSelected + i - restSpan;
        }
    })
    readonly property int barWidth: 220
    readonly property int barHeight: 440
    readonly property int slotSpacing: 262
    readonly property real parallaxPx: Settings.wallpaperStyle === "carousel-flat" ? 0 : 75
    readonly property int captionGap: 14
    // cell's per-rank shrink (see its scale property): floor
    // is the minimum scale a cell can shrink to, rate is the
    // falloff per step of |rank|.
    readonly property real edgeFloor: 0.7
    readonly property real edgeRate: 0.07
    // |rank| at which the falloff above hits edgeFloor and goes
    // constant - the boundary between the two edgeOffset
    // branches below.
    readonly property real edgeBreak: (1 - edgeFloor) / edgeRate
    // constant per-step position delta once cells are past
    // edgeBreak (both neighbors' scale stuck at the same floor,
    // so the compensation needed per step stops changing)
    readonly property real edgeClampedStep: slotSpacing - barWidth * (1 - edgeFloor)
    // Magnitude of a cell's x offset from center, as a function
    // of |rank| (m). Plain `m * slotSpacing` (rank-linear
    // spacing) is what scale shrinking around each cell's own
    // center visibly opens up into growing gaps - every step a
    // cell's near edge retreats by half its own shrink *and*
    // its neighbor's, while the two centers stay slotSpacing
    // apart regardless of scale. This is the closed form of
    // "each step's cell-to-cell gap stays exactly slotSpacing -
    // barWidth, the scale=1 gap" - solved by requiring
    // edgeOffset(m+1) - edgeOffset(m) == slotSpacing -
    // barWidth*(scale(m) + scale(m+1))/1 for every real m (not
    // just integers, since a slide's rank is continuous and
    // neighboring cells are always exactly 1 apart). That's a
    // quadratic in the unclamped region (scale linear in m) and
    // linear beyond edgeBreak (scale pinned to edgeFloor).
    function edgeOffset(m: real): real {
        if (m <= edgeBreak)
            return slotSpacing * m - (barWidth * edgeRate / 2) * m * m;
        const atBreak = slotSpacing * edgeBreak - (barWidth * edgeRate / 2) * edgeBreak * edgeBreak;
        return atBreak + edgeClampedStep * (m - edgeBreak);
    }
    // extra top/bottom room for the optional query label and page dots.
    // The carousel is a spatial ring - there's no visual "page of tiles" to
    // land on - but wallsCols/wallsRows (the grid pages' own size setting)
    // still carves wallpaperMatches into pages the same way LauncherState
    // already does for the grid style (wallpaperPageSize/wallpaperPage,
    // unconditional on style), so the dots below reuse that directly.
    readonly property int queryH: Settings.pageIndicatorEnabled("query") ? 52 : 0
    readonly property int dotsH: Settings.pageIndicatorEnabled("dots") ? 20 : 0
    width: 2 * edgeOffset(halfVisible) + barWidth
    height: barHeight + captionGap + 22 + root.queryH + root.dotsH
    // Its own instance of the shared power/reboot rubber band: one Translate
    // per pane, all bound to the same pull, so no pane has to reach across the
    // tree for a sibling's transform.
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
    opacity: 0.004
    visible: Settings.wallpaperStyle !== "grid" && LauncherState.pane === "walls"

    Connections {
        target: LauncherState
        function onPaneChanged() {
            if (LauncherState.pane === "walls" && Settings.wallpaperStyle !== "grid") {
                LauncherState.jumpCarousel();
                enterAnim.restart();
                // cells replay their entrance spring below; the
                // shared video has none, so keep it out until
                // they've landed (see root.entranceDone)
                root.entranceDone = false;
                entranceSettle.restart();
            }
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: root; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }

    Repeater {
        id: cells
        // fixed count: delegate identity (and its absStep) must
        // stay stable across steps so the strip visibly slides
        // instead of the content teleporting into static slots
        model: root.totalSlots

        Item {
            id: cell
            required property int index
            property int absStep: index - root.restSpan
            readonly property real rank: absStep - LauncherState.carouselAnim
            readonly property int count: LauncherState.wallpaperMatches.length
            readonly property int wallIndex: count > 0 ? ((absStep % count) + count) % count : -1
            readonly property var wall: (wallIndex >= 0 && !LauncherState.carouselEmpty) ? LauncherState.wallpaperMatches[wallIndex] : null
            readonly property bool isCenter: wallIndex >= 0 && wallIndex === LauncherState.wallpaperSelected && Math.abs(rank) < 0.5
            // drives the ring/stroke/fill selection highlight
            // below; continuous in |rank| (not isCenter's hard
            // cutoff) so it cross-fades with the slide instead
            // of snapping - see wallCell's isSelected boolean
            // toggle above for how the static tiles grid does it
            readonly property real selFade: Math.max(0, 1 - Math.abs(rank) * 2)
            // the carousel is already a horizontal strip, so
            // every style's entrance drift (Anim.fromY) runs
            // along x here instead of the grids' vertical y -
            // same magnitude, just the other axis. "slide"
            // flips the sign: the grid version reads as rows
            // rising up from below, and cells sliding in from
            // the left (negative) reads as the same "coming up
            // the reading order" motion here, rather than
            // reusing the plain positive-x direction the other
            // styles share.
            readonly property int springFromX: Anim.style === "slide" ? -Anim.fromY : Anim.fromY
            readonly property int springFromY: 0
            // left-to-right visual slot, for the same bloom/reveal/slide
            // stagger the tile grids use (see Anim.stagger)
            readonly property int visSlot: Math.max(0, Math.min(root.halfVisible * 2,
                Math.round(rank) + root.halfVisible))

            // once a cell has drifted a full step past the resting
            // buffer, relabel it to the opposite edge (±totalSlots
            // keeps it congruent mod the ring) - by then it's
            // faded to 0 opacity, so the relabel is invisible
            function rebalance() {
                while (absStep - LauncherState.carouselAnim > root.restSpan + 1)
                    absStep -= root.totalSlots;
                while (absStep - LauncherState.carouselAnim < -(root.restSpan + 1))
                    absStep += root.totalSlots;
            }
            Connections {
                target: LauncherState
                function onCarouselAnimChanged() { cell.rebalance(); }
                function onWallpaperMatchesChanged() {
                    cell.absStep = cell.index - root.restSpan;
                }
                // replay the spring when the selector opens: the
                // cell was already filled while it was hidden, so
                // onWallChanged alone won't fire (see wallCell's
                // identical hook for the "grid" style)
                function onPaneChanged() {
                    if (LauncherState.pane === "walls" && Settings.wallpaperStyle !== "grid" && cell.filled)
                        springIn.restart();
                }
            }

            // sign-aware, not rank*slotSpacing: a plain linear
            // step is what the scale shrink below visibly opens
            // into growing gaps (each cell shrinks around its
            // own center while consecutive centers stay a fixed
            // slotSpacing apart). edgeOffset's magnitude is
            // solved so cell-to-cell gaps stay exactly
            // slotSpacing - barWidth (the scale=1 gap) at every
            // rank, not just growing ones.
            x: parent.width / 2 - width / 2 + Math.sign(rank) * root.edgeOffset(Math.abs(rank))
            y: root.queryH
            width: root.barWidth
            height: root.barHeight
            z: -Math.abs(rank)
            // continuous in rank (exactly 1 at rank 0) - an
            // isCenter branch here would snap scale mid-slide
            // the moment rank crosses 0.5. Uniform (not a
            // separate x/y scale): scaling width and height
            // unevenly would stretch/squash the already-cropped
            // image inside, not just resize its frame.
            scale: Math.max(root.edgeFloor, 1 - Math.abs(rank) * root.edgeRate)
            // No wall===null cut here (unlike the plain
            // opacity/rank cull below): a cell losing its wall
            // (query no longer matches, list emptied) still needs
            // to render while wrap's own opacity plays the exit
            // spring - hard-cutting the parent to 0 here would
            // hide that animation entirely. A cell that's never
            // had a wall (count === 0) just stays invisible via
            // wrap's untouched initial opacity of 0.
            opacity: Math.max(0, Math.min(1, root.halfVisible + 1 - Math.abs(rank)))

            // entrance/exit spring for this window's content,
            // replayed whenever filtering changes which wallpaper
            // it shows - same bloom/pop/fade/reveal/slide/none
            // language (Settings.animStyle) and stagger the tile grids use
            property var shownWall: null
            property bool filled: false
            onWallChanged: {
                if (wall) {
                    const wasFilled = filled;
                    const isNew = !wasFilled || !shownWall || shownWall.path !== wall.path;
                    shownWall = wall;
                    filled = true;
                    if (isNew) {
                        springIn.stop();
                        springOut.stop();
                        if (wasFilled) {
                            // direct replacement: snap straight to the
                            // resting state, no animation
                            wrap.opacity = 1;
                            wrap.scale = 1;
                            wrap.x = 0;
                            wrap.y = 0;
                        } else {
                            springIn.restart();
                        }
                    }
                } else if (filled) {
                    filled = false;
                    springIn.stop();
                    if (LauncherState.pane === "walls" && Settings.wallpaperStyle !== "grid") {
                        springOut.restart();
                    } else {
                        // filtered while the pane is off-screen - for the
                        // carousel that's a query with no match at all
                        // (LauncherState.carouselEmpty) typed from the clock,
                        // one statement before the pane switch. Same reasoning
                        // as AppsPage's identical branch.
                        springOut.stop();
                        wrap.opacity = 0;
                    }
                }
            }

            Item {
                id: wrap
                // fixed size matching the parent, not
                // anchors.fill: an anchor continuously
                // re-asserts x/y against the parent, silently
                // overriding the spring's writes below - same
                // reason wallWrap/clipTile size themselves this
                // way instead of anchoring
                width: parent.width
                height: parent.height
                opacity: 0

                // selected-tile ring from the tiles grid (see
                // wallCell above), reused here: sits behind
                // thumb and is larger by the same margin, so
                // it never overlaps the thumbnail itself, just
                // frames it. Opacity tracks |rank| continuously
                // (not cell.isCenter's hard cutoff) so it
                // cross-fades smoothly between the outgoing and
                // incoming centered card as the carousel slides,
                // instead of popping on/off mid-transition.
                // Anchored to parent (wrap), not thumb - same
                // reason the inner stroke below is: anchoring to
                // the ClippingRectangle sibling instead of the
                // plain, non-clipping parent visibly jittered the
                // ring every frame while cell's scale animated.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: 17
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.alpha(Theme.accent, 0.33)
                    opacity: cell.selFade
                }
                ClippingRectangle {
                    id: thumb
                    anchors.fill: parent
                    radius: 12
                    color: Qt.alpha(Theme.accent, 0.08 + 0.08 * cell.selFade)

                    Image {
                        // wider than the bar and panned opposite the
                        // scroll direction, so each window reads as
                        // a fixed frame onto a slowly-drifting
                        // backdrop. The pan is driven by the cell's
                        // rank - bounded, unlike LauncherState.carouselAnim,
                        // whose unbounded growth would slide the
                        // backdrop out of the frame after a few
                        // steps in one direction - and the image is
                        // wide enough to cover the whole fade range
                        // (|rank| <= halfVisible + 1; past that the
                        // cell is fully transparent, so further
                        // overshoot is invisible). The full-res
                        // source (not the 480x270 tile thumbnail,
                        // which is already cropped tight to a
                        // landscape frame and has no spare width to
                        // pan through) decoded at bar height keeps
                        // the pan free of seams.
                        //
                        // Video uses its cached still frame here
                        // (Image can't decode the source file - see
                        // the source binding below) in this same
                        // wide/panned box, so it pans exactly like
                        // every other type. The still keeps the
                        // video's own aspect rather than the tile
                        // grid's 16:9 crop (see the ffmpeg call in
                        // Wallpapers' scan), which is what lets the shared
                        // player below hand over to it - and back -
                        // without the crop shifting.
                        width: root.barWidth + ((root.halfVisible + 1) * root.parallaxPx + 20) * 2
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        x: (parent.width - width) / 2 - cell.rank * root.parallaxPx
                        // stays visible underneath even once
                        // animating/videoAnimating - see the matching
                        // note on the grid tile's still Image
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(0, root.barHeight)
                        // shownWall, not wall: wall goes null the instant
                        // the cell is filtered/emptied out, but the exit
                        // spring below still needs something to fade -
                        // shownWall keeps the last-rendered wallpaper
                        // until a new one replaces it (see onWallChanged).
                        // A video source can't be decoded by Image at
                        // all, so it falls back to the (narrower,
                        // tightly-cropped) static thumb instead of the
                        // full-res pan source every other type gets.
                        source: cell.shownWall ? "file://" + (cell.shownWall.video ? cell.shownWall.thumb : cell.shownWall.path) : ""
                    }
                    // Only the centered window plays its .gif from the
                    // source file; side windows keep the still Image
                    // above (which already shows frame 0 of a gif) so
                    // scrolling the carousel doesn't decode a movie
                    // per window. Video is not played per cell at all
                    // - see the single shared player below the
                    // Repeater.
                    // style/shown checked for the same reason the
                    // grid's tiles check them (see tileLive above):
                    // the carousel is only `visible: false` in grid
                    // mode, so its bindings keep running there.
                    //
                    // Starts as soon as this cell is the selected
                    // one and within a slot of center, rather than
                    // waiting for the slide to stop - a gif that
                    // only came to life after the strip had already
                    // settled read as the preview lagging the
                    // navigation. Playing mid-slide is only safe
                    // because the AnimatedImage below pans with the
                    // still frame it replaces (it used to sit
                    // unpanned, which is what made a mid-slide
                    // start jump). The full slot of slack, rather
                    // than isCenter's half, is hysteresis for
                    // dragging back and forth across center:
                    // dropping out reloads the source below.
                    readonly property bool gifAnimating: cell.wallIndex >= 0 && cell.wallIndex === LauncherState.wallpaperSelected && Math.abs(cell.rank) < 1
                        && Settings.wallpaperStyle !== "grid" && LauncherState.shown && !!cell.shownWall?.gif
                    AnimatedImage {
                        // Same (wider-than-bar) target width as the still
                        // Image above, not just barWidth: PreserveAspectCrop
                        // picks its scale from max(targetW/iw, targetH/ih),
                        // so a narrower target box here would crop to a
                        // different (larger) scale than the still frame it
                        // replaces, producing a visible shrink/jump the
                        // instant a centered gif starts playing.
                        width: root.barWidth + ((root.halfVisible + 1) * root.parallaxPx + 20) * 2
                        height: parent.height
                        // exactly the still Image's box *and* its
                        // parallax offset, so handing over to the
                        // animation mid-slide moves nothing
                        anchors.verticalCenter: parent.verticalCenter
                        x: (parent.width - width) / 2 - cell.rank * root.parallaxPx
                        visible: thumb.gifAnimating
                        playing: thumb.gifAnimating
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        source: thumb.gifAnimating ? "file://" + cell.shownWall.path : ""
                    }
                }
                // Stroke above the image, not a border on thumb:
                // settled cells rest on half-pixel x (parent
                // width is an odd multiple of slotSpacing) and
                // side cells have fractional edges from the rank
                // scale, so the clip mask and an underlying
                // border rasterize a pixel apart - the image eats
                // the right/bottom stroke and roughens the
                // corners (same image-over-border effect the
                // tiles grid's WallpaperGrid stroke above works
                // around).
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    // same muted-to-full-accent brighten tiles
                    // mode gives the selected cell's stroke
                    border.color: Qt.alpha(Theme.accent, 0.33 + 0.67 * cell.selFade)
                }
                // TapHandler (not a plain MouseArea) so a
                // completed swipe below doesn't also register
                // as a click - same tap-vs-drag split the
                // pages list's swipe-to-delete row uses.
                TapHandler {
                    enabled: cell.wall !== null && !LauncherState.promptOpen
                    onTapped: {
                        if (cell.isCenter)
                            LauncherState.wallpaperRequested(cell.wall);
                        else
                            LauncherState.moveCarousel(Math.round(cell.rank));
                    }
                }
                // swiping the image itself scrolls the
                // carousel - same LauncherState.carouselDragTo()/
                // carouselDragEnd() the background's
                // carouselTracking gesture uses, just fed
                // straight from the drag instead of
                // reconstructed from press/release timestamps
                DragHandler {
                    target: null
                    yAxis.enabled: false
                    enabled: cell.wall !== null && Settings.gesturesEnabled() && !LauncherState.promptOpen
                    property real grabX: 0
                    onActiveChanged: {
                        if (active)
                            grabX = centroid.scenePosition.x;
                        else
                            LauncherState.carouselDragEnd(centroid.scenePosition.x - grabX, centroid.velocity.x);
                    }
                    onCentroidChanged: {
                        if (active)
                            LauncherState.carouselDragTo(centroid.scenePosition.x - grabX);
                    }
                }
            }

            SequentialAnimation {
                id: springIn
                PropertyAction { target: wrap; property: "opacity"; value: 0 }
                PropertyAction { target: wrap; property: "scale"; value: Anim.fromScale }
                PropertyAction { target: wrap; property: "x"; value: cell.springFromX }
                PropertyAction { target: wrap; property: "y"; value: cell.springFromY }
                // cols: 1 - the carousel is a single strip, so
                // "slide"'s row-based stagger (Math.floor(slot /
                // cols) * step) should treat each tile as its own
                // row instead of collapsing them all into row 0.
                // 35ms step (not the grid's 60ms) since with
                // cols:1 every bar staggers individually and 60ms
                // makes the carousel noticeably slower to settle
                // than bloom/cascade.
                PauseAnimation { duration: Anim.stagger(cell.visSlot, 1, 35) }
                ParallelAnimation {
                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                    NumberAnimation { target: wrap; property: "x"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                    NumberAnimation { target: wrap; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                }
            }
            SequentialAnimation {
                id: springOut
                ParallelAnimation {
                    NumberAnimation { target: wrap; property: "scale"; to: Anim.outBounce ? 1.08 : 1; duration: Anim.outBounce ? Anim.tile(80) : 0; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: wrap; property: "scale"; to: Anim.fromScale; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                    NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                }
            }
        }
    }

    // One video surface for the whole carousel, standing in for
    // whichever cell holds the selection, rather than one living
    // inside each cell - every video's player is already open and
    // paused behind it (see WallpaperVideoPool), so what navigation
    // does here is only ever move this surface and start or stop
    // the player it points at, both of which are free.
    //
    // It is not pinned to the middle of the strip, though: it
    // takes the placement, scale, stacking and parallax a cell
    // at centerRank would get, so it rides a slide (or a drag)
    // in its cell's place. Playback used to wait for the strip
    // to settle instead, which is what made a video preview
    // read as arriving late behind the navigation.
    readonly property var centerWall: (!LauncherState.carouselEmpty && LauncherState.wallpaperSelected >= 0 && LauncherState.wallpaperSelected < LauncherState.wallpaperMatches.length) ? LauncherState.wallpaperMatches[LauncherState.wallpaperSelected] : null
    // Video the surface shows. Sticky: navigating off a video
    // leaves it showing that (now paused, and therefore identical
    // to the still frame underneath) file while it fades out
    // riding its own cell away, rather than blanking mid-slide.
    property string videoSource: ""
    // absStep of the cell videoSource was last handed over from,
    // updated in lockstep with videoSource itself (see below) so
    // centerRank always measures from the slot the open file
    // actually belongs to. Without this it tracked
    // LauncherState.carouselStep directly, which jumps to the
    // *destination* slot the instant navigation starts - fine
    // while hopping video-to-video (videoSource jumps with it),
    // but wrong leaving a video for a plain image: videoSource
    // stays put (see onCenterWallChanged), so the fading-out
    // player would ride the incoming cell's position instead of
    // the outgoing one, flashing the old thumbnail over the tile
    // being navigated to.
    property int videoAbsStep: LauncherState.carouselStep
    onCenterWallChanged: if (centerWall && centerWall.video) {
        videoSource = centerWall.path;
        videoAbsStep = LauncherState.carouselStep;
    }
    // Same ± totalSlots wrap the cells' own rebalance() applies to
    // absStep (see cell.rebalance above), kept in sync here too: without
    // it, videoAbsStep is the one position on this whole strip that
    // never gets recycled, so a slot it drifted off from during a fast
    // scroll stays on the books forever and can wrap back into view
    // later - by then some other cell owns that geometric spot, and the
    // stale player would paint the old video's frame over its content
    // instead of staying retired off-screen like every real cell does.
    function rebalanceVideo() {
        while (root.videoAbsStep - LauncherState.carouselAnim > root.restSpan + 1)
            root.videoAbsStep -= root.totalSlots;
        while (root.videoAbsStep - LauncherState.carouselAnim < -(root.restSpan + 1))
            root.videoAbsStep += root.totalSlots;
    }
    Connections {
        target: LauncherState
        function onCarouselAnimChanged() { root.rebalanceVideo(); }
    }
    // videoSource === centerWall.path holds off the handover for
    // the frame or two after a switch between two videos, while
    // the player still has the previous file open.
    // LauncherState.shown, not just the pane: the launcher keeps its last
    // pane while hidden, and decoding frames for a window nobody
    // is looking at costs the same as decoding for one they are.
    readonly property bool videoShowing: LauncherState.shown && LauncherState.pane === "walls" && Settings.wallpaperStyle !== "grid" && entranceDone && !!centerWall && !!centerWall.video && videoSource === centerWall.path
    // Rank of the slot the player stands in for: the cell
    // videoSource belongs to (see videoAbsStep above) - the one
    // it's riding into on a video-to-video handover, or the one
    // it's riding off of when the next cell over isn't a video.
    // 0 at rest, ±1 at the start of a step, free-running under a
    // drag - which is what keeps the player over its own cell
    // throughout the motion rather than over whatever happens to
    // be in the middle.
    readonly property real centerRank: videoAbsStep - LauncherState.carouselAnim
    // The shared player has no entrance spring of its own, so
    // hold it back until the cells have finished theirs - it
    // would otherwise sit at full opacity in the center slot
    // while the cell it stands in for is still fading/sliding
    // in. Longest case: the center cell's stagger delay plus
    // its own duration.
    property bool entranceDone: true
    Timer {
        id: entranceSettle
        interval: Anim.stagger(root.halfVisible, 1, 35) + Anim.duration + 40
        onTriggered: root.entranceDone = true
    }
    Item {
        id: sharedVideo
        // the same placement/scale/stacking cell derives from
        // its own rank - see the notes there for why each is
        // shaped the way it is
        x: parent.width / 2 - width / 2 + Math.sign(root.centerRank) * root.edgeOffset(Math.abs(root.centerRank))
        y: root.queryH
        width: root.barWidth
        height: root.barHeight
        scale: Math.max(root.edgeFloor, 1 - Math.abs(root.centerRank) * root.edgeRate)
        // ties with the cell it stands in for; declared after the
        // Repeater, so it wins the tie and draws over that cell's
        // still frame
        z: -Math.abs(root.centerRank)
        // fades out toward the edges exactly as its cell does, so
        // a slide that carries a video off the strip takes the
        // playing frame with it instead of leaving it at full
        // strength over a faded cell
        opacity: root.videoShowing
            ? Math.max(0, Math.min(1, root.halfVisible + 1 - Math.abs(root.centerRank)))
            : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: Anim.tile(90); easing.type: Easing.OutCubic }
        }
        ClippingRectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            WallpaperVideoPool {
                anchors.fill: parent
                // style-gated as well as bound to videoSource, which keeps
                // moving in grid mode (centerWall is only the selection, and
                // the bindings under an invisible pane keep running): without
                // it, navigating the *grid* onto a video would have this pool
                // open the file too, for a strip nobody is looking at.
                current: Settings.wallpaperStyle === "grid" ? "" : root.videoSource
                live: root.videoShowing
                // Only while the launcher is down, so the file
                // opens land with nothing on screen to stutter
                // rather than inside a slide - measured, an open
                // landing in a slide freezes the GUI thread for
                // ~700ms on first sight of a file. The style check
                // keeps the grid's own pool from opening the same
                // files a second time over. Settings.preload off
                // trades that freeze back for the ~150MiB per video
                // this holds.
                warming: Settings.preload && Settings.wallpaperStyle !== "grid" && !LauncherState.shown
                // exactly the box - and therefore exactly the crop
                // - the centered cell's still Image uses at rank 0,
                // parallax included: without it the video would sit
                // still inside its bar while everything around it
                // panned
                surfaceWidth: root.barWidth + ((root.halfVisible + 1) * root.parallaxPx + 20) * 2
                surfaceHeight: height
                surfaceX: (width - surfaceWidth) / 2 - root.centerRank * root.parallaxPx
            }
        }
        // the centered cell's own 1px stroke is underneath this
        // overlay, so redraw it on top, in the color that cell
        // resolves to at selFade 1. Outside the ClippingRectangle
        // for the same reason the cell's is (see wrap above).
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: Theme.accent
        }
    }

    PageQueryLabel {
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        queryText: LauncherState.query
    }

    Text {
        anchors.top: parent.top
        anchors.topMargin: root.queryH + root.barHeight + root.captionGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, root.width)
        text: {
            if (LauncherState.carouselEmpty)
                return "";
            const count = LauncherState.wallpaperMatches.length;
            if (count === 0)
                return "";
            // tracks the live drag position (LauncherState.carouselAnim),
            // not just the last-committed LauncherState.wallpaperSelected, so the
            // caption updates continuously while dragging
            const idx = ((Math.round(LauncherState.carouselAnim) % count) + count) % count;
            const w = LauncherState.wallpaperMatches[idx];
            return w ? LauncherState.wallpaperName(w) : "";
        }
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
    }

    PageDots {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        pageCount: LauncherState.wallpaperPageSize > 0
            ? Math.ceil(LauncherState.wallpaperMatches.length / LauncherState.wallpaperPageSize) : 0
        currentPage: LauncherState.wallpaperPage
    }
}
