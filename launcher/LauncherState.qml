pragma Singleton
import QtQuick
import Quickshell
import "root:/config"
import "root:/services"

// Everything the launcher *is*, as opposed to how it's drawn: which pane is
// showing, what's selected in it, what the current query matches, and the
// in-flight state of every gesture.
//
// Split out of LauncherWindow so a pane can be its own file and still read the
// state it renders - without either reaching into the window's item tree or
// having that state threaded down through half a dozen properties. The window
// keeps everything that genuinely needs its item tree or a child process
// (launching, applying a wallpaper, decoding a clip) and drives those through
// the signals below.
Singleton {
    id: root

    // ---------- window lifecycle ----------
    // Mirrored from LauncherWindow rather than owned here: the window is what
    // actually maps and unmaps. Panes read them to gate animations and live
    // decoding, which is why they have to be reachable from outside the window.
    property bool shown: false
    property bool exiting: false

    // Which shape the open/close animation takes. "grow" styles reveal a circle
    // that expands to cover the screen; "fade" cross-fades content opacity
    // instead; "none" skips the reveal entirely - and must not be treated as
    // "grow" just because it isn't "fade". The circle's geometry needs the
    // window's own screen, so that part stays on LauncherWindow.
    readonly property bool fadeMode: Settings.launchAnimation === "fade"
    readonly property bool noneMode: Settings.launchAnimation === "none"
    readonly property bool growMode: !root.fadeMode && !root.noneMode

    // Reveal geometry. LauncherWindow writes screenWidth/screenHeight (it owns
    // the screen) and animates `reveal` directly; everything derived from them
    // lives here, because the clock pane gates its own fade on how far the
    // circle has grown.
    property real screenWidth: 0
    property real screenHeight: 0
    property real reveal: 0
    readonly property var originFraction: {
        switch (Settings.launchAnimation) {
        case "grow-top-left":
            return [0, 0];
        case "grow-top-right":
            return [1, 0];
        case "grow-bottom-left":
            return [0, 1];
        case "grow-bottom-right":
            return [1, 1];
        default:
            return [0.5, 0.5]; // grow-center, and fade (origin unused)
        }
    }
    readonly property real originX: root.originFraction[0] * root.screenWidth
    readonly property real originY: root.originFraction[1] * root.screenHeight
    // Radius needed to cover the farthest screen corner from the origin. At
    // reveal=1 that corner sits exactly on the circle - a zero-width
    // mathematical tangent that the mask's antialiasing/threshold softening
    // turns into a visibly rounded notch (all four corners for grow-center,
    // since they're equidistant; just the farthest one otherwise). A small
    // overshoot keeps every corner strictly inside the circle instead of
    // grazing it.
    readonly property real maxRevealRadius: 1.02 * Math.max(Math.hypot(root.originX, root.originY), Math.hypot(root.screenWidth - root.originX, root.originY), Math.hypot(root.originX, root.screenHeight - root.originY), Math.hypot(root.screenWidth - root.originX, root.screenHeight - root.originY))
    // Clamped to 1px: an empty region reads as "no region set", which the blur
    // protocol treats as blur-the-whole-surface - a full-screen blur flash.
    readonly property int revealDiameter: Math.max(1, Math.ceil(2 * root.maxRevealRadius * root.reveal))
    // What the compositor blur region asks for (see LauncherWindow's
    // growRegion), deliberately smaller than the circle the mask draws. At equal
    // diameters the region pokes out from under the content as a ring of
    // blurred, saturated backdrop wearing none of the launcher's dim, which
    // reads as a bright rim riding the edge.
    //
    // The two are not the same circle even though they share a diameter: the
    // region is a true ellipse, while the mask is a Rectangle whose `radius`
    // Qt tessellates at a capped 18 segments a corner - a 72-gon, inscribed, so
    // it sits ~0.1% of the radius *inside* nominal at each segment's midpoint.
    // (Measured: an isolated Rectangle circle's edge has a dominant 72-per-
    // revolution harmonic, and its area is short of a true disc by the 0.13% a
    // 72-gon predicts.) That is a proportional error, not a fixed pixel or two,
    // which is why a constant inset only ever cleaned up the small end of the
    // animation. 0.4% of the diameter gives a ~3x margin over it, plus 2px for
    // integer rounding. Small enough that the unblurred sliver it trades for
    // stays under notice - a few pixels mid-animation, and off-screen entirely
    // by the time the circle is at full size.
    readonly property int revealBlurDiameter: Math.max(1, root.revealDiameter - Math.ceil(root.revealDiameter * 0.004) - 2)

    // Raised for the things that need the window's own item tree or a child
    // process. The window connects to each; nothing else does.
    signal focusRequested
    signal exitRequested
    signal launchRequested(var entry)
    signal wallpaperRequested(var wall)
    signal clipExpandRequested(var clip)
    signal clipCollapseRequested

    function focusInput(): void {
        root.focusRequested();
    }
    function exit(): void {
        root.exitRequested();
    }

    // Set right before exit() when the close is a hand-off to the Pages tab's
    // upload picker rather than a real dismiss. LauncherWindow calls
    // openPendingDialog() once the exit animation has fully played, instead of
    // racing it, and the tab that owns the dialog opens it.
    property string dialogPending: ""
    signal uploadDialogRequested
    // The picker borrowed the screen; replay the entrance animation without a
    // full reset, so the launcher lands back exactly where the exit animation
    // left off instead of at the home pane.
    signal dialogFinished
    function reopenAfterDialog(): void {
        root.dialogFinished();
    }

    function openPendingDialog(): void {
        if (root.dialogPending !== "folder")
            return;
        root.dialogPending = "";
        root.uploadDialogRequested();
    }

    // Live text from the launcher's hidden search field, mirrored here so every
    // pane (and every custom page, via PageContext) filters off one source.
    property string query: ""

    // The carousel's slot pitch, needed by drag maths here and by the carousel
    // view itself - declared here so the gesture code doesn't have to reach
    // into the item that happens to draw it.
    readonly property int carouselSlotSpacing: 262

    // Custom pages that contribute a Settings tab. Pushed in by LauncherWindow,
    // which is where the loaded page items live.
    property var customSettingsTabs: []

    // ---------- cache warm-up ----------
    // Driven by LauncherWindow's frame animations, read by the panes: while
    // warming, a pane renders at near-zero opacity so its scene-graph nodes and
    // textures are built up front instead of stuttering the first real open.
    // Apps warm before the reveal (typing can happen immediately); the heavier
    // wallpaper thumbnails warm after it finishes.
    property bool warmingApps: false
    property bool warmingWallpapers: false
    property bool warmedOnce: false
    property bool wallpapersWarmedOnce: false
    property int wallpaperWarmTick: 0

    // Tab cycles the enabled panes; the settings pane sits outside the
    // cycle (opened via the corner button or Ctrl+S).
    property string pane: "clock"
    // every id the Pages settings row can show: the four built-in
    // panes, any uploaded custom pages, and "__add_folder__" (the
    // add-a-page row - a real, reorderable member of this list so it
    // drags like everything else, but not a real page: the Pages tab's
    // pageOn/pageToggle/etc. special-case it).
    // Deliberately reads only Settings.uploadedPages, never
    // Settings.pageOrder, so its value (and object identity) stays put
    // across a pure reorder - that's what the settings row's Repeater
    // binds its model to, since rebinding a Repeater's model to a new
    // array/object each time destroys and recreates every delegate.
    // Recreating mid-drag severs the DragHandler's grab after one step,
    // and recreating on every property change (rather than genuine
    // add/remove) skips the position Behavior, so reorders - including
    // a Reset - never animate. Membership only actually changes on
    // upload/trash/disk sync, so this binding is stable the rest of
    // the time.
    readonly property var pageIds: {
        const def = ["clock", "apps", "walls", "clips"];
        // custom pages before the built-in four: this is what the
        // "missing id" top-up in orderedPages below falls back to
        // whenever it has to place one without a captured position
        // (see there), so the default order - before anything's ever
        // been dragged - has custom pages at the front
        return (Settings.uploadedPages ?? []).map(u => u.id).concat(def, ["__add_folder__"]);
    }
    // display order for the Pages settings row, layered on top of
    // pageIds above; also what activePanes below filters down to the
    // enabled subset for Tab's cycle order, so dragging a row here
    // reorders the cycle too. The "missing id" top-up loop below is a
    // fallback for ids this doesn't already have an opinion on (should
    // rarely trigger - CustomPages' scan normally captures a new page's
    // position itself, splicing it in right after the add row, i.e.
    // ahead of the built-in four); if it does fire, it appends in
    // pageIds order, which is custom pages first, so still front-
    // leaning rather than landing at the very bottom.
    // "__add_folder__" is pinned to the top unconditionally -
    // stripped out of whatever Settings.pageOrder says and put back at the
    // front every time, not just defaulted there once, since it isn't
    // draggable (see the pageRow DragHandler's `enabled:
    // !pageRow.isAdd`) and nothing else should end up above it either.
    readonly property var orderedPages: {
        const valid = pageIds;
        const o = (Array.isArray(Settings.pageOrder) ? Settings.pageOrder : [])
            .filter(p => valid.includes(p) && p !== "__add_folder__");
        for (const v of valid)
            if (!o.includes(v) && v !== "__add_folder__")
                o.push(v);
        o.unshift("__add_folder__");
        return o;
    }
    function movePage(p: string, to: int) {
        const o = orderedPages.filter(x => x !== p);
        o.splice(Math.max(0, Math.min(o.length, to)), 0, p);
        Settings.pageOrder = o;
    }
    function togglePage(id: string): void {
        const pages = Object.assign({}, Defaults.pages, Settings.pages);
        // keep at least one page enabled overall (built-in or custom)
        if (pages[id] !== false && root.activePanes.length <= 1)
            return;
        pages[id] = pages[id] === false;
        Settings.pages = pages;
        Settings.save();
        if (!root.activePanes.includes(root.pane) && root.pane !== "settings")
            root.setPane(root.homePane());
    }
    function toggleUploadedPage(id: string) {
        const uploaded = Settings.uploadedPages ?? [];
        const u = uploaded.find(x => x.id === id);
        // a broken page (folder missing main.qml - see CustomPages' scan) has
        // nothing to load; its row exists so it can be seen and
        // trashed, not toggled on
        if (!u || u.broken)
            return;
        // keep at least one page enabled overall (built-in or custom),
        // same invariant togglePage enforces for the built-in four
        if (u.on && activePanes.length <= 1)
            return;
        Settings.uploadedPages = uploaded.map(x => x.id === id ? Object.assign({}, x, { on: !x.on }) : x);
        Settings.save();
    }
    // cycle order: the four built-ins (gated by Settings.pages) plus any
    // enabled custom page, in orderedPages' relative order - a custom
    // page's position among the Pages settings rows is exactly where it
    // sits in Tab's cycle too.
    readonly property var activePanes: {
        const pages = Settings.pages ?? {};
        const uploaded = Settings.uploadedPages ?? [];
        const list = orderedPages.filter(id => {
            if (id === "__add_folder__")
                return false;
            const u = uploaded.find(x => x.id === id);
            return u ? u.on : pages[id] !== false;
        });
        return list.length ? list : ["clock"];
    }
    function homePane(): string {
        return activePanes[0];
    }
    // The names `pibble toggle` takes for the two built-in panes whose
    // internal ids read as abbreviations. The ids themselves stay short:
    // they're settings keys (Settings.pages/pageOrder), so renaming them
    // would orphan every existing config. Old-name keybinds keep working
    // anyway - "walls"/"clips" match activePanes directly in resolvePageArg
    // below and never reach this map.
    readonly property var pageArgAliases: ({
        wallpapers: "walls",
        clipboard: "clips"
    })
    // `pibble toggle <page>` accepts a custom page's bare filename (what
    // `pibble help` lists, e.g. "counter") as well as its real, prefixed
    // id ("folder:counter") - the prefix is internal namespacing (see
    // CustomPages.dir/CustomPages' scan) that a CLI user shouldn't have to know
    // or type. Falls through unresolved for built-in ids and "settings",
    // which already match activePanes directly. A custom page wins over the
    // aliases above, so uploading one called "clipboard" still resolves to it.
    function resolvePageArg(p: string): string {
        if (!p || activePanes.includes(p) || p === "settings")
            return p;
        const u = (Settings.uploadedPages ?? []).find(x => x.id.split(":").slice(1).join(":") === p);
        if (u)
            return u.id;
        return root.pageArgAliases[p] ?? p;
    }
    readonly property bool drawerOpen: root.pane === "apps"

    // A page discovered on disk defaults to the front of the list, directly
    // under the pinned add row, rather than the back - custom pages sit ahead
    // of the built-in four. A scan that added nothing still writes the order
    // back, which is what drops ids for pages that have since vanished.
    Connections {
        target: CustomPages
        function onDiscovered(addedIds: var): void {
            if (addedIds.length) {
                const order = root.orderedPages.filter(id => !addedIds.includes(id));
                order.splice(1, 0, ...addedIds);
                Settings.pageOrder = order;
            } else {
                Settings.pageOrder = root.orderedPages;
            }
        }
    }

    // ---------- clock line layout ----------
    // fixed layout, not user-reorderable: battery+weather always
    // combine onto one shared line at the bottom (if either is ticked).
    // date sits directly against the clock - above it when anything
    // else is also showing (so it reads as a header line over the
    // whole block), otherwise below it (just the two of them).
    // Settings.clockShow just controls per-item visibility.
    readonly property var clockVisibleGroups: {
        const show = Settings.clockShow ?? {};
        const dateOn = show.date !== false;
        const bw = [];
        if (show.battery !== false)
            bw.push("battery");
        if (show.weather !== false)
            bw.push("weather");
        const groups = [];
        if (dateOn && bw.length) {
            groups.push(["date"]);
            groups.push(["time"]);
        } else {
            groups.push(["time"]);
            if (dateOn)
                groups.push(["date"]);
        }
        if (bw.length)
            groups.push(bw);
        return groups;
    }
    function toggleClockItem(id: string): void {
        const show = Object.assign({ date: true, battery: true, weather: true }, Settings.clockShow ?? {});
        show[id] = show[id] === false ? true : false;
        Settings.clockShow = show;
        Settings.save();
    }

    function setPane(p: string) {
        root.query = "";
        cancelCapture();
        expandedClip = null;
        // leaving a page resets its selection back to the first item, so
        // returning to it later doesn't resume wherever it was left -
        // set directly rather than relying on root.query = "" above to
        // reset `selected` via onMatchesChanged, which is a no-op (no
        // change signal) whenever the filter was already empty, i.e.
        // most of the time
        selected = 0;
        wallpaperSelected = 0;
        clipSelected = 0;
        root.pane = (p === "settings" || root.activePanes.includes(p)) ? p : root.homePane();
        if (root.pane === "clips")
            Clipboard.checkAlert();
    }

    // Entering a pane replays its tile stagger; the clock has no tiles. Its
    // text scramble runs for every pane, clock included - that one is all
    // text and nothing else. One call for the whole shell rather than one per
    // pane: the run is global, and each label decides for itself whether it's
    // on screen to take part (see ui/ScrambleText.qml). Also tells Clipboard
    // whether its alerts have anywhere to land - a scan runs on every launcher
    // open, but a cliphist problem is only worth reporting while the user is
    // actually looking at the clips pane.
    onPaneChanged: {
        Clipboard.paneVisible = root.pane === "clips";
        if (root.pane !== "clock")
            Anim.beginStagger();
        // Starting the clock is all this does - when each label actually
        // begins is the label's own business, since it can only start once
        // whatever brings it in (a tile's spring, the launch reveal) has
        // brought it in (see ui/ScrambleText.qml).
        Anim.beginScramble();
    }
    // settings remembers where it was opened from
    property string paneBeforeSettings: "clock"
    property string settingsTab: "general"
    // which page's grid the tile picker on the Grids tab is editing
    property string gridTarget: "apps"
    function toggleSettings() {
        if (pane === "settings") {
            setPane(paneBeforeSettings);
        } else {
            paneBeforeSettings = pane;
            setPane("settings");
        }
    }

    function cyclePane(dir: int) {
        // inside settings the cycle keybinds walk the settings tabs
        if (pane === "settings") {
            const tabs = ["general", "pages", "animations", "keybindings", "flyouts"].concat(customSettingsTabs.map(t => t.pageId));
            settingsTab = tabs[((tabs.indexOf(settingsTab) + dir) % tabs.length + tabs.length) % tabs.length];
            return;
        }
        let i = activePanes.indexOf(pane);
        if (i < 0)
            i = 0;
        setPane(activePanes[((i + dir) % activePanes.length + activePanes.length) % activePanes.length]);
    }

    // ---------- swipe-to-power / swipe-to-reboot ----------
    // Android-notification-shade style: dragging down from inside the
    // top edgeSwipeZone pulls the pane content down (rubber band) and
    // reveals a ring that strokes itself closed as you drag, like a
    // swipe-to-refresh. Releasing with the ring complete (or the power
    // keybind) arms the "power off?" prompt; Enter then powers off,
    // anything else (Escape, a click, another key) lets go. Dragging up
    // from inside the bottom edgeSwipeZone does the same, arming a
    // "reboot?" prompt instead - same physics, opposite sign, mirrored
    // geometry. Outside either zone the vertical drag belongs to pane
    // navigation instead (see the MouseArea above).
    // shared with the right-edge swipe-to-go-back drag too (see
    // rightEdgePress below)
    readonly property real edgeSwipeZone: 80
    // true while either prompt is armed - every navigation gesture on
    // screen (pane cycling, page paging, carousel scrolling) stands down
    // for it, see bgArea.onPressed and the carousel's cell's handlers below - except
    // the edge-swipe-back gesture, which stays live on purpose so it can
    // dismiss the prompt (see bgArea.backTracking and root.goBack())
    readonly property bool promptOpen: powerArmed || rebootArmed
    property string dragZone: "none" // "top" | "bottom" | "none" - which edge (if any) the in-flight drag started in
    property bool powerDragging: false
    property real dragGrabY: 0
    property real powerRaw: 0 // raw downward drag distance (finger travel)
    property bool powerArmed: false
    readonly property real powerThreshold: 300
    readonly property real powerProgress: Math.min(1, powerRaw / powerThreshold)
    // how gradually powerPull's resistance ramps up - bigger means more
    // "give" (the curve stays closer to linear for longer before it
    // starts noticeably fighting the finger). Tune this alone for feel;
    // powerRingScale below re-derives to compensate, so the resting
    // depth never has to be re-tuned alongside it
    readonly property real powerPullDecay: 400
    // content shift lags the finger with increasing resistance - same
    // curve whether raw is coming straight off the finger (live drag)
    // or being eased by the Behavior below (keybind / release rebound)
    readonly property real powerPull: 170 * (1 - Math.exp(-powerRaw / powerPullDecay))
    // powerPull's own value once raw reaches the threshold, at the
    // *live* powerPullDecay - used below to derive powerRingScale
    readonly property real powerPullAtThreshold: 170 * (1 - Math.exp(-powerThreshold / powerPullDecay))
    // the ring's resting depth (pull*2.6 - 200) back when the curve
    // used the original decay of 260 - fixed regardless of
    // powerPullDecay so retuning the drag's "give" never moves the
    // settled/rebounded position
    readonly property real powerRestDepth: 170 * (1 - Math.exp(-powerThreshold / 260)) * 2.6 - 200
    // single multiplier on powerPull that reproduces powerRestDepth
    // exactly at the threshold, as one smooth scale of powerPull
    // instead of two competing terms (see the comment on powerRing's y)
    readonly property real powerRingScale: powerRestDepth / powerPullAtThreshold
    Behavior on powerRaw {
        enabled: !root.powerDragging
        NumberAnimation { duration: Anim.menu(320); easing.type: Easing.OutCubic }
    }
    Timer {
        // a forgotten armed prompt must not lie in wait to turn the next
        // launch Return into a poweroff: let go on its own after a beat
        interval: 8000
        running: root.powerArmed && !root.powerDragging
        onTriggered: root.disarmPower()
    }
    function disarmPower() {
        powerArmed = false;
        powerRaw = 0;
    }
    // the power keybind plays the pull animation (the powerRaw Behavior
    // animates the ride down) straight into the armed pose: Enter powers
    // off, anything else lets go - same as completing the drag by hand
    function playPower() {
        powerArmed = true;
        powerRaw = powerThreshold;
    }
    function powerOff() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
        exit();
    }

    property bool rebootDragging: false
    property real rebootRaw: 0 // raw upward drag distance (finger travel)
    property bool rebootArmed: false
    readonly property real rebootThreshold: 300
    readonly property real rebootProgress: Math.min(1, rebootRaw / rebootThreshold)
    // mirror of powerPullDecay/powerPull/powerPullAtThreshold/
    // powerRestDepth/powerRingScale above - see the comments there
    readonly property real rebootPullDecay: 400
    readonly property real rebootPull: 170 * (1 - Math.exp(-rebootRaw / rebootPullDecay))
    readonly property real rebootPullAtThreshold: 170 * (1 - Math.exp(-rebootThreshold / rebootPullDecay))
    readonly property real rebootRestDepth: 170 * (1 - Math.exp(-rebootThreshold / 260)) * 2.6 - 200
    readonly property real rebootRingScale: rebootRestDepth / rebootPullAtThreshold
    Behavior on rebootRaw {
        enabled: !root.rebootDragging
        NumberAnimation { duration: Anim.menu(320); easing.type: Easing.OutCubic }
    }
    Timer {
        // same forgotten-prompt safety net as power, mirrored
        interval: 8000
        running: root.rebootArmed && !root.rebootDragging
        onTriggered: root.disarmReboot()
    }
    function disarmReboot() {
        rebootArmed = false;
        rebootRaw = 0;
    }
    function playReboot() {
        rebootArmed = true;
        rebootRaw = rebootThreshold;
    }
    function rebootNow() {
        Quickshell.execDetached(["systemctl", "reboot"]);
        exit();
    }

    // ---------- swipe-to-go-back ----------
    // Android-edge-gesture style: dragging left from inside the right
    // edgeSwipeZone strip pulls a small pill in from the edge (see
    // backPill, near powerRing/rebootRing below, for how it's drawn;
    // bgArea's backTracking for the drag itself). Unlike
    // swipe-to-power/reboot above there's no separate arm/confirm step -
    // releasing past backThreshold fires goBack() immediately, same as
    // Android's own edge-back gesture, since going back is cheap and
    // reversible (worst case you just reopen whatever you left).
    // Releasing short of the threshold just lets it spring back.
    property bool backDragging: false
    property real backRaw: 0 // raw leftward drag distance from the right edge (finger travel)
    // scene Y the drag actually started at (set once per drag, in
    // bgArea's onPressed) - backPill spawns there instead of
    // always centering vertically, same as Android's edge-back pill
    property real backGrabY: 0
    readonly property real backThreshold: 70
    readonly property real backProgress: Math.min(1, backRaw / backThreshold)
    // backPill (see below, near powerRing/rebootRing) is a fixed 56px
    // circle - same size as the corner settings button it copies - so
    // the resistance curve tracks the finger 1:1 up to that, then
    // resists further travel once fully out, same diminishing-returns
    // curve as powerPull/rebootPull above, applied only to the overshoot
    readonly property real backExtra: Math.max(0, backRaw - 56)
    readonly property real backPull: Math.min(backRaw, 56) + 24 * (1 - Math.exp(-backExtra / 200))
    Behavior on backRaw {
        enabled: !root.backDragging
        NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutCubic }
    }
    // same layered order the Escape keybind used to inline directly -
    // it now just calls this: let go of an armed power/reboot prompt,
    // else collapse an expanded clip, else back out of settings to
    // whatever pane opened it, else close the launcher outright. The
    // Escape keybind never actually reaches this branch (promptOpen is
    // intercepted earlier in the key handler), but the edge-swipe-back
    // gesture calls this directly and has no such earlier interception,
    // so the prompt check has to live here too.
    function goBack() {
        if (root.powerArmed)
            root.disarmPower();
        else if (root.rebootArmed)
            root.disarmReboot();
        else if (root.expandedClip)
            root.collapseClip();
        else if (root.pane === "settings")
            root.setPane(root.paneBeforeSettings);
        else
            root.exit();
    }

    // ---------- matches ----------
    property var matches: {
        const q = root.query.toLowerCase().trim();
        if (!q) {
            const all = Apps.all.slice();
            all.sort((a, b) => Apps.launchCount(b) - Apps.launchCount(a)
                || a.name.localeCompare(b.name));
            return all;
        }
        const scored = [];
        for (const a of Apps.all) {
            const s = Apps.fuzzyScore(a.name.toLowerCase(), q);
            if (s !== null)
                scored.push({ entry: a, score: s });
        }
        scored.sort((x, y) => Apps.launchCount(y.entry) - Apps.launchCount(x.entry)
            || y.score - x.score
            || x.entry.name.localeCompare(y.entry.name));
        return scored.map(x => x.entry);
    }
    property int selected: 0
    onMatchesChanged: selected = 0
    readonly property int appPageSize: Settings.appsCols * Settings.appsRows
    readonly property int appPage: appPageSize > 0 ? Math.floor(selected / appPageSize) : 0

    function wallpaperName(wall): string {
        return wall.path.split("/").pop().replace(/\.[^.]+$/, "");
    }
    property var wallpaperMatches: {
        // The "windows" carousel is a spatial strip, not a list: reordering
        // or dropping entries out from under it as the query changes reads
        // as chaos (tiles teleporting to unrelated slots every keystroke).
        // It keeps Wallpapers.list's natural order/contents always, and
        // typing instead jumps the selection to the best match - see
        // jumpCarousel(), driven from input.onTextChanged.
        if (Settings.wallpaperStyle !== "grid")
            return Wallpapers.list;
        const q = root.query.toLowerCase().trim();
        if (!q)
            return Wallpapers.list;
        const scored = [];
        for (const w of Wallpapers.list) {
            const s = Apps.fuzzyScore(wallpaperName(w).toLowerCase(), q);
            if (s !== null)
                scored.push({ w, s });
        }
        scored.sort((x, y) => y.s - x.s || wallpaperName(x.w).localeCompare(wallpaperName(y.w)));
        return scored.map(x => x.w);
    }
    property int wallpaperSelected: 0
    onWallpaperMatchesChanged: {
        wallpaperSelected = 0;
        carouselStep = 0;
    }
    // Windows-carousel-only: true once a query has no fuzzy match at all
    // anywhere in Wallpapers.list, so every tile plays its exit spring
    // (see the carousel's cell.wall below) instead of the carousel sitting frozen on
    // stale content.
    property bool carouselEmpty: false
    // Jumps the (unfiltered) windows carousel to the best fuzzy match for
    // the current query, choosing whichever wrap direction is shorter so
    // the slide always takes the short way around the ring. Called from
    // input.onTextChanged and whenever the walls pane/style is (re)entered
    // with a query already typed.
    function jumpCarousel() {
        const q = root.query.toLowerCase().trim();
        if (!q) {
            carouselEmpty = false;
            return;
        }
        let best = -1;
        let bestScore = -Infinity;
        for (let i = 0; i < Wallpapers.list.length; i++) {
            const s = Apps.fuzzyScore(wallpaperName(Wallpapers.list[i]).toLowerCase(), q);
            if (s !== null && s > bestScore) {
                bestScore = s;
                best = i;
            }
        }
        if (best < 0) {
            carouselEmpty = true;
            return;
        }
        carouselEmpty = false;
        const count = Wallpapers.list.length;
        if (count > 0 && best !== wallpaperSelected) {
            let delta = ((best - wallpaperSelected) % count + count) % count;
            if (delta > count / 2)
                delta -= count;
            // order matches moveCarousel - see its comment
            carouselStep += delta;
            wallpaperSelected = best;
        }
    }
    readonly property int wallpaperPageSize: Settings.wallsCols * Settings.wallsRows
    readonly property int wallpaperPage: wallpaperPageSize > 0 ? Math.floor(wallpaperSelected / wallpaperPageSize) : 0

    // ---------- wallpaper carousel ("carousel" style) ----------
    // Unbounded step counter driving the carousel's animated position:
    // it only ever moves by ±1 per navigation (never wraps), so a
    // Behavior on carouselAnim always eases in the direction the
    // user actually scrolled, even when wallpaperSelected itself wraps
    // around the end of the list. wallpaperSelected stays the authoritative
    // bounded index (what LauncherWindow.applyWallpaper()/activate() read).
    property int carouselStep: 0
    property real carouselAnim: carouselStep
    // disabled while a finger/pointer is actively dragging the carousel
    // (see carouselDragTo below) so the live drag can move carouselAnim
    // instantly, frame to frame, instead of chasing it through the eased
    // Behavior meant for discrete moveCarousel() steps
    property bool carouselDragging: false
    Behavior on carouselAnim {
        enabled: !root.carouselDragging
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }
    function moveCarousel(dir: int) {
        const count = wallpaperMatches.length;
        if (!count)
            return;
        // carouselStep first: wallpaperSelected's change is what fires
        // centerWall's binding (and the shared video player's
        // onCenterWallChanged off that), so carouselStep must
        // already hold its new value by then or the player captures the
        // slot it's leaving instead of the one it's arriving at.
        carouselStep += dir;
        wallpaperSelected = ((wallpaperSelected + dir) % count + count) % count;
    }
    // Swipe-to-scroll the carousel, live: dx is the total horizontal drag
    // distance so far (from the gesture's press, not since the last
    // call), so the strip tracks the finger 1:1 while dragging, same as
    // the power/reboot pull tracks raw drag distance while *Dragging is
    // true above. carouselStep itself is untouched until release
    // (carouselDragEnd) commits whole slots - dragging alone never
    // changes the selection.
    function carouselDragTo(dx: real) {
        carouselDragging = true;
        carouselAnim = carouselStep - dx / root.carouselSlotSpacing;
    }
    // Release: dx/vx (total drag distance, release velocity px/s,
    // signed) decide how many whole slots to commit - a slow short drag
    // moves roughly one slot; a fast flick carries further, as if the
    // released velocity kept translating the strip for another ~280ms,
    // same feel as a native flick-scroll. Whatever slot the live drag
    // landed on mid-step eases the rest of the way there (or back to the
    // start, if the drag didn't carry far enough to commit) once the
    // Behavior above is re-enabled.
    function carouselDragEnd(dx: real, vx: real) {
        const carried = Math.abs(dx) + Math.abs(vx) * 0.28;
        if (carried >= 24) {
            const steps = Math.max(1, Math.round(carried / root.carouselSlotSpacing));
            moveCarousel((dx < 0 ? 1 : -1) * steps);
        }
        carouselDragging = false;
        carouselAnim = Qt.binding(() => root.carouselStep);
    }

    // text clips are matched word-by-word against their full decoded
    // text (see clipSearchMatch) rather than fuzzyScore's character
    // subsequence match, since that's what makes highlightable spans
    // possible; image clips have no real text to search, so they keep
    // matching against their synthetic "png image 1920x1080 ..." label
    // the old way. Matched clips are shallow-cloned with hiText/hiSpans
    // attached (rather than wrapped) so every other lookup elsewhere
    // (expandClip, clipCopy, ...) keeps working against plain clip
    // fields unchanged.
    property var clipMatches: {
        const raw = root.query.trim();
        if (!raw)
            return Clipboard.entries;
        const q = raw.toLowerCase();
        const terms = q.split(/\s+/).filter(t => t.length > 0);
        const scored = [];
        for (const c of Clipboard.entries) {
            if (c.image) {
                const s = Apps.fuzzyScore(c.preview.toLowerCase(), q);
                if (s !== null)
                    scored.push({ c, s });
                continue;
            }
            const text = c.full || c.preview;
            const m = Clipboard.searchMatch(text, terms);
            if (m === null)
                continue;
            const snip = Clipboard.snippet(text, m, 90);
            scored.push({ c: Object.assign({}, c, { hiText: snip.text, hiSpans: snip.hi }), s: m.score });
        }
        scored.sort((x, y) => y.s - x.s);
        return scored.map(x => x.c);
    }
    property int clipSelected: 0
    onClipMatchesChanged: clipSelected = 0
    readonly property int clipRows: Math.max(2, Math.min(4, Settings.clipsRows))
    readonly property int clipPageSize: Settings.clipsCols * clipRows
    readonly property int clipPage: clipPageSize > 0 ? Math.floor(clipSelected / clipPageSize) : 0

    // Enter on a clip copies it and expands the tile into an info card;
    // Enter again (or Escape) collapses it. The launcher stays open.
    property var expandedClip: null
    property string expandedText: ""
    property int expandedBytes: -1
    // full-resolution decode for the expand view: the grid/warm-up thumb
    // (c.thumb) is downscaled on disk to keep the background warm cheap,
    // so expanding needs its own full-res decode. Done lazily here, on
    // the interactive expand action, instead of eagerly for every clip.
    property string expandedFullPath: ""
    // which clip expandedFullPath belongs to, so a decode that lands after the
    // user has already moved on isn't shown against the wrong entry
    property string expandedFullId: ""
    property point expandOrigin: Qt.point(0, 0)
    signal expandAnimStart
    signal expandAnimCollapse
    function collapseClip(): void {
        if (root.expandedClip)
            root.expandAnimCollapse();
    }

    readonly property var expandedInfo: {
        const c = expandedClip;
        if (!c)
            return [];
        const rows = [];
        rows.push(["type", c.image ? c.kind + " image" : "text"]);
        rows.push(["size", expandedBytes >= 0 ? Format.humanBytes(expandedBytes) : (c.image ? c.size : "…")]);
        if (c.image)
            rows.push(["resolution", c.dims]);
        else if (expandedText)
            rows.push(["lines", "" + expandedText.split("\n").length + (expandedBytes > 1500 ? " (truncated)" : "")]);
        return rows;
    }

    // ---------- navigation ----------
    // Horizontal: previous/next item, wrapping. Vertical: down a row
    // within the column; at the bottom of a column, hop to the top of the
    // next column (next page after the last column), and mirrored for up.
    function hMove(sel: int, count: int, dir: int): int {
        if (!count)
            return 0;
        return ((sel + dir) % count + count) % count;
    }
    // Down walks the entire column - through every page - before hopping
    // to the top of the next column; Up mirrors it.
    function vMove(sel: int, count: int, cols: int, rows: int, dir: int): int {
        if (!count)
            return 0;
        const page = cols * rows;
        const p = Math.floor(sel / page);
        const w = sel % page;
        const r = Math.floor(w / cols);
        const c = w % cols;
        const pages = Math.ceil(count / page);
        if (dir > 0) {
            // next row in this column, continuing onto the next page
            const idx = r < rows - 1 ? sel + cols : (p + 1) * page + c;
            if (idx < count)
                return idx;
            // column exhausted: top of the next column (first page)
            const nc = c + 1;
            return (nc < cols && nc < count) ? nc : 0;
        } else {
            if (r > 0)
                return sel - cols;
            if (p > 0)
                return (p - 1) * page + (rows - 1) * cols + c;
            // top of the column: bottom-most cell of the previous column
            const nc = c > 0 ? c - 1 : cols - 1;
            for (let pp = pages - 1; pp >= 0; pp--) {
                for (let rr = rows - 1; rr >= 0; rr--) {
                    const idx = pp * page + rr * cols + nc;
                    if (idx < count)
                        return idx;
                }
            }
            return count - 1;
        }
    }
    function navigate(dx: int, dy: int) {
        if (pane === "apps") {
            const next = dy !== 0
                ? vMove(selected, matches.length, Settings.appsCols, Settings.appsRows, dy)
                : hMove(selected, matches.length, dx);
            // Re-stagger when the move crosses onto a new page, so the
            // tile wave replays instead of the whole grid popping at once.
            // Set it before the assignment: the entry rebinding cascade
            // that restarts springIn fires synchronously here, and it
            // reads staggering to compute the per-tile delay.
            Anim.staggerIfPageChanged(appPageSize, selected, next);
            selected = next;
        } else if (pane === "walls") {
            if (Settings.wallpaperStyle !== "grid") {
                moveCarousel(dy !== 0 ? dy : dx);
            } else {
                const next = dy !== 0
                    ? vMove(wallpaperSelected, wallpaperMatches.length, Settings.wallsCols, Settings.wallsRows, dy)
                    : hMove(wallpaperSelected, wallpaperMatches.length, dx);
                Anim.staggerIfPageChanged(wallpaperPageSize, wallpaperSelected, next);
                wallpaperSelected = next;
            }
        } else if (pane === "clips") {
            const next = dy !== 0
                ? vMove(clipSelected, clipMatches.length, Settings.clipsCols, clipRows, dy)
                : hMove(clipSelected, clipMatches.length, dx);
            Anim.staggerIfPageChanged(clipPageSize, clipSelected, next);
            clipSelected = next;
        }
    }
    // Jumps a whole page at a time (dir: 1 next, -1 previous), keeping
    // the same row/col within the new page where possible - same "next
    // screenful" feel as a phone home screen, rather than landing on
    // whatever cell vMove's row-by-row walk would stop at.
    function pageJump(sel: int, count: int, pageSize: int, dir: int): int {
        if (!count || pageSize <= 0)
            return sel;
        const pages = Math.ceil(count / pageSize);
        if (pages <= 1)
            return sel;
        const w = sel % pageSize;
        const curPage = Math.floor(sel / pageSize);
        const nextPage = ((curPage + dir) % pages + pages) % pages;
        return Math.min(count - 1, nextPage * pageSize + w);
    }
    // swipe-up/down: page through the current pane's grid. The windows
    // wallpaper carousel has no grid pages (it's a spatial strip, see
    // moveCarousel) so it's excluded upstream via onCarousel, and this
    // only ever sees it as a no-op pane.
    function pageMove(dir: int) {
        if (pane === "apps") {
            const next = pageJump(selected, matches.length, appPageSize, dir);
            Anim.staggerIfPageChanged(appPageSize, selected, next);
            selected = next;
        } else if (pane === "walls" && Settings.wallpaperStyle === "grid") {
            const next = pageJump(wallpaperSelected, wallpaperMatches.length, wallpaperPageSize, dir);
            Anim.staggerIfPageChanged(wallpaperPageSize, wallpaperSelected, next);
            wallpaperSelected = next;
        } else if (pane === "clips") {
            const next = pageJump(clipSelected, clipMatches.length, clipPageSize, dir);
            Anim.staggerIfPageChanged(clipPageSize, clipSelected, next);
            clipSelected = next;
        }
    }
    // Shared dominant-axis swipe dispatch: a completed drag's total
    // travel decides pane-cycling (horizontal) vs paging (vertical), one
    // or the other never both. Used by the per-tile DragHandlers (tiles
    // grab their own presses, so bgArea never sees those drags) - bgArea
    // keeps its own inline copy since it additionally has to gate each
    // axis independently on where the press started (edge zone, over the
    // wallpaper carousel), which a shared single dx/dy call can't express
    // without corrupting which axis reads as "dominant".
    function gestureRelease(dx: real, dy: real) {
        if (Math.abs(dx) >= Math.abs(dy)) {
            if (Math.abs(dx) > 80)
                cyclePane(dx < 0 ? 1 : -1);
        } else {
            if (Math.abs(dy) > 80)
                pageMove(dy < 0 ? 1 : -1);
        }
    }

    // What the launch keybind (or a second click on the selected tile) does,
    // per pane. The three that need a child process are raised as signals for
    // LauncherWindow to carry out.
    function activate(): void {
        if (root.pane === "walls")
            root.wallpaperRequested(root.wallpaperMatches[root.wallpaperSelected] ?? null);
        else if (root.pane === "clips") {
            if (root.expandedClip)
                root.clipCollapseRequested();
            else
                root.clipExpandRequested(root.clipMatches[root.clipSelected] ?? null);
        } else if (root.pane === "apps")
            root.launchRequested(root.matches.length ? root.matches[root.selected] : null);
        else if (root.pane === "clock")
            root.setPane("apps");
    }

    // ---------- keybinds ----------
    readonly property var bindDefaults: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S", power: "Ctrl+P", reboot: "Ctrl+R", navLeft: "Left", navRight: "Right", navUp: "Up", navDown: "Down" })
    // capture (Keybindings tab, click-to-record): capturingBind names the
    // action being recorded; captureHeldKeys tracks which physical keys
    // are still down so the bind only commits once every key of the
    // chord has been released (not on the initial keydown), matching a
    // real "record a shortcut" UX. captureLive always reflects the most
    // recent key event: a bare modifier (Ctrl alone) shows and can still
    // be replaced or extended by whatever's pressed next - pressing a
    // different key switches to that key, holding a modifier and then
    // pressing a real key extends it into "Ctrl+S". Release-time decides
    // whether the final value is actually a complete, saveable chord (a
    // bare modifier alone never is - see bareModifierLabels below).
    property string capturingBind: ""
    property string captureLive: ""
    property var captureHeldKeys: []
    readonly property var bareModifierLabels: ["Ctrl", "Alt", "Shift", "Super"]
    function cancelCapture() {
        capturingBind = "";
        captureLive = "";
        captureHeldKeys = [];
    }
    function modifierLabel(key: int): string {
        switch (key) {
        case Qt.Key_Control: return "Ctrl";
        case Qt.Key_Alt: return "Alt";
        case Qt.Key_Shift: return "Shift";
        case Qt.Key_Meta: return "Super";
        default: return "";
        }
    }
    function keyName(event): string {
        const special = new Map([
            [Qt.Key_Tab, "Tab"], [Qt.Key_Backtab, "Tab"],
            [Qt.Key_Return, "Return"], [Qt.Key_Enter, "Return"],
            [Qt.Key_Escape, "Escape"], [Qt.Key_Space, "Space"],
            [Qt.Key_Backspace, "Backspace"], [Qt.Key_Delete, "Delete"],
            [Qt.Key_Insert, "Insert"],
            [Qt.Key_Home, "Home"], [Qt.Key_End, "End"],
            [Qt.Key_PageUp, "PageUp"], [Qt.Key_PageDown, "PageDown"],
            [Qt.Key_Up, "Up"], [Qt.Key_Down, "Down"], [Qt.Key_Left, "Left"], [Qt.Key_Right, "Right"],
            [Qt.Key_CapsLock, "CapsLock"], [Qt.Key_NumLock, "NumLock"], [Qt.Key_ScrollLock, "ScrollLock"],
            [Qt.Key_Pause, "Pause"], [Qt.Key_Print, "Print"], [Qt.Key_Menu, "Menu"]
        ]);
        let name = special.get(event.key);
        // whether name came from the raw, layout/shift-independent key
        // code (true for everything below) rather than event.text -
        // only the text fallback already bakes Shift into the character
        let fromText = false;
        if (!name && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            name = "F" + (event.key - Qt.Key_F1 + 1);
        // letters/digits from the key code, so Ctrl+letter works (its
        // event.text is a control character) and Shift+letter isn't
        // silently identical to the bare letter
        if (!name && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            name = String.fromCharCode(event.key);
        if (!name && event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            name = String.fromCharCode(event.key);
        if (!name && event.text && event.text.trim() && event.text.charCodeAt(0) >= 32) {
            name = event.text.toUpperCase();
            fromText = true;
        }
        if (!name)
            return "";
        // at most one modifier prefix, so every bind is at most two keys
        let mod = "";
        if (event.modifiers & Qt.ControlModifier)
            mod = "Ctrl+";
        else if (event.modifiers & Qt.AltModifier)
            mod = "Alt+";
        else if ((event.modifiers & Qt.ShiftModifier) && !fromText)
            mod = "Shift+";
        return mod + name;
    }
    function setBind(action: string, key: string) {
        const kb = Object.assign({}, Settings.keybinds);
        kb[action] = key;
        Settings.keybinds = kb;
        Settings.save();
    }
}
