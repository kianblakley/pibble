pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// The screen tools: pointing at what is on screen and asking about it. Five
// things share this file because they are one gesture with five endings -
// take the screen, let the user drag a rectangle over some of it, do
// something with what was in the rectangle. Nothing ever reads more of the
// screen than the rectangle it was given:
//
//   search     the text inside is read and offered up to a web search, the
//              clipboard, a translation or an image search
//   copy       the text inside is read and goes straight to the clipboard
//   code       a QR code or barcode inside is read (zbarimg) and offered up
//              to be opened, copied or searched for
//   translate  every paragraph inside that is not already in the user's
//              language is repainted in it, in place
//   region     the rectangle goes to the recorder (see Recorder) as the area
//              to record. The only one that never looks at a pixel, so the
//              only one that never freezes the screen
//
// The freeze is the color picker's, for the color picker's reasons (see
// ScreenColor, which this deliberately leaves alone rather than generalising -
// that file is a list of crashes it took to get right, and moving its furniture
// would be a gamble on all of them): grim writes one uncompressed frame to
// tmpfs, the overlay shows it in place of the screen, and everything after that
// reads the file rather than the display. ScreencopyView is still off the table
// for the reason given there.
//
// Reading is tesseract, and tesseract is why the frame takes a detour through
// ffmpeg first: it was trained on print, and wants capitals twenty to thirty
// pixels tall where a screen draws them ten. Cropping to the rectangle and
// scaling that up (see upscale) is the difference between most of the words
// and all of them. Nothing here is read by pibble itself - the overlay only
// ever paints boxes tesseract found.
//
// Translation is the one step that leaves the machine, and only on the user's
// say-so: nothing is sent until `pibble translate` is run or the card's
// translate chip is pressed, and Settings.translateCommand replaces the
// network call outright with a command of the user's own.
//
// Like ScreenColor, every script below is written without backslashes and
// without bash's (dollar)(brace) expansions: these are QML template literals,
// where the first is an escape and the second an interpolation.
Singleton {
    id: root

    // ---------- state ----------

    // "" while idle, else which of them is running. The overlay owns the
    // screen - input and all - for as long as this is set.
    property string mode: ""
    readonly property bool active: root.mode !== ""
    // the ones that read what the rectangle holds, all of which keep the
    // frame up for another rectangle when one held nothing
    readonly property bool reading: ["search", "copy", "code", "translate"].includes(root.mode)
    // Who draws the gesture: "overlay", the tools' own surface, or
    // "launcher", over the launcher as it stands when one was started with
    // it up - so a tool used on one of pibble's pages reads that page and
    // leaves it open (see LauncherState's onGranted). Back to "overlay"
    // with every close.
    property string host: "overlay"

    // Where in the gesture things stand:
    //   capture  grim is writing the frame (the overlay is up but transparent)
    //   frame    the file exists; waiting for the overlay to decode it
    //   select   waiting for the user to mark something
    //   working  reading, or translating what was read
    //   result   there is something to show
    property string phase: ""

    // The frozen frame the overlay shows, deleted when the gesture ends.
    property string shotPath: ""
    // Frame pixels per logical pixel, and the frame's size - told to this
    // service by the overlay once it has decoded the file (see frameReady),
    // since the image is the only thing that knows either for certain.
    property real ratio: 1
    property int frameWidth: 0
    property int frameHeight: 0

    // The output the gesture started on, pinned for its whole length: grim is
    // pointed at this one, and a recording region is offset by its position.
    property string outputName: ""
    property int outputX: 0
    property int outputY: 0

    // Bumped per gesture. Every subprocess is stamped with the one it was
    // started under, and an answer that comes back under another is dropped -
    // closing the overlay does not wait for a tesseract it no longer wants.
    property int job: 0

    // the rectangle dragged (frame pixels), and what was read out of it
    property rect selection: Qt.rect(0, 0, 0, 0)
    property string text: ""
    property string translation: ""
    property bool translating: false

    // translate: one row per paragraph found - its box in frame pixels, the
    // height of one of its lines, the text read and the text it became. A
    // ListModel rather than a plain array so that a translation landing fills
    // in its rows where they stand, instead of rebuilding every box on screen
    // (and replaying every entrance) each time a batch comes back.
    readonly property ListModel blocks: ListModel {}
    // how many rows carry a translation worth painting
    property int painted: 0

    // One line the overlay says in place of a result ("No text found here").
    property string notice: ""

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // tmpfs for the same reason as the color picker's frame: tens of megabytes
    // written and read back inside a second, with no business touching a disk
    readonly property string framePath: root.runtimeDir + "/pibble-tools-frame.ppm"
    // What tesseract is actually shown: the selection, cut out and enlarged.
    // Kept past the end of the gesture - the image search uploads it after the
    // overlay has already closed - and simply overwritten by the next one.
    readonly property string cropPath: root.runtimeDir + "/pibble-tools-crop.png"

    // The translator's spelling of the language to translate into. The shell's
    // own "zh" is the one id it would not recognise as written.
    readonly property string targetLanguage: {
        const wanted = (Settings.translateTo || "").trim() || Strings.code;
        return wanted === "zh" ? "zh-CN" : wanted;
    }

    // ---------- the menu ----------

    // The tools menu (ui/ToolsMenu.qml) is up on the overlay: the same four
    // things as the commands, for a pointer or a single keybind, opened by
    // `pibble toggle tools` with no launcher in the way. It is state of this
    // service rather than of the surface that draws it because everything that
    // has to get out of its way, or wants it out of theirs, can see a service -
    // the launcher, the recorder, a gesture starting. The launcher's own menu
    // (the same command with the launcher up) is the launcher's state, not this.
    property bool menuOpen: false
    // how long the menu takes to leave, which is also how long anything that
    // photographs the screen has to wait after closing it - nothing at all
    // with its animation switched off
    readonly property int menuExit: Settings.toolsAnim === "none" ? 0 : 180
    property double menuClosedAt: 0
    onMenuOpenChanged: {
        if (!root.menuOpen)
            root.menuClosedAt = Date.now();
    }

    // `pibble toggle tools`: also how a gesture that is up is put away, so the
    // one keybind opens and closes whatever of this is on screen.
    function toggleMenu(): void {
        if (root.menuOpen)
            root.menuOpen = false;
        else if (root.active)
            root.close();
        else
            root.menuOpen = true;
    }

    // What picking one of the menu's actions does, wherever that menu was
    // drawn. "pause" and "stop" are a running recording's controls; the two
    // record actions do nothing while one runs, there being one recorder.
    function run(action: string): void {
        if (["search", "translate", "copy", "code"].includes(action))
            root.request(action);
        else if (action === "color")
            root.pickColor();
        else if (action === "pause")
            Recorder.togglePause();
        else if (action === "stop")
            Recorder.stop();
        else if (Recorder.recording)
            return;
        else if (action === "area")
            Recorder.toggleRegion();
        else if (action === "record")
            Recorder.toggle();
    }

    // The screen color picker (services/ScreenColor.qml) as a tool: pick any
    // pixel, and its hex lands on the clipboard. The same eyedropper the
    // custom palette uses, asked whether it can run first - a no has been
    // said as an alert by the time it comes back - and started once the menu
    // is off the screen, so the menu is not in the frame it samples.
    // ScreenColor's answers are broadcast, so this only takes the one it
    // asked for.
    property bool colorAsked: false
    function pickColor(): void {
        if (ScreenColor.picking)
            return;
        root.colorAsked = true;
        ScreenColor.check();
    }
    Connections {
        target: ScreenColor
        function onChecked(found: bool): void {
            if (!root.colorAsked)
                return;
            root.colorAsked = false;
            if (!found)
                return;
            ScreenColor.prepare();
            root.afterMenu(() => ScreenColor.pick());
        }
    }

    // Runs `then` once the menu is off the screen: at once if it was not up,
    // else after it has closed and played its exit. Whatever is about to
    // capture the screen goes through here, so the menu that asked for the
    // capture is never in it.
    property var menuThen: null
    function afterMenu(then: var): void {
        root.menuOpen = false;
        const wait = root.menuClosedAt + root.menuExit + 80 - Date.now();
        if (wait <= 0) {
            then();
            return;
        }
        root.menuThen = then;
        menuGone.interval = wait;
        menuGone.restart();
    }
    Timer {
        id: menuGone
        onTriggered: {
            const then = root.menuThen;
            root.menuThen = null;
            if (then)
                then();
        }
    }

    // ---------- starting and stopping ----------

    // Raised once a gesture has been let through (its tools are all there) and
    // the overlay has taken the screen. Whoever is covering the screen gets
    // out of the way and then calls capture() - see LauncherState, which is
    // the only thing that ever is.
    signal granted
    // A recording region, as wf-recorder's -g wants it: "x,y WxH" in the
    // compositor's own layout coordinates. Empty means the whole output.
    signal regionChosen(string output, string geometry)

    function toolsFor(mode: string): var {
        if (mode === "region")
            return [];
        if (mode === "code")
            return ["grim", "ffmpeg", "zbarimg"];
        const tools = ["grim", "tesseract", "ffmpeg"];
        if (mode === "translate" && !Settings.translateCommand)
            tools.push("curl");
        return tools;
    }

    // Tools already seen on PATH. As with the eyedropper, a yes is trusted and
    // a no is asked again: a tool installed since the last try is found by the
    // next one, and a gesture never waits behind a lookup it has already won.
    property var have: ({})
    property string asking: ""

    // The one way in. Asking again while a gesture is up ends it, so the same
    // keybind opens and closes the overlay.
    function request(mode: string): void {
        if (root.active) {
            root.close();
            return;
        }
        if (probe.running || !["search", "translate", "region", "copy", "code"].includes(mode))
            return;
        const unknown = root.toolsFor(mode).filter(tool => !root.have[tool]);
        if (unknown.length === 0) {
            root.grant(mode);
            return;
        }
        root.asking = mode;
        probe.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            for tool in "$@"; do
                command -v "$tool" >/dev/null 2>&1 && echo "have $tool" || echo "miss $tool"
            done`, "_"].concat(unknown);
        probe.running = true;
    }

    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: {
                const have = Object.assign({}, root.have);
                const missing = [];
                for (const line of text.split("\n")) {
                    const [verdict, tool] = line.trim().split(" ");
                    if (verdict === "have")
                        have[tool] = true;
                    else if (verdict === "miss")
                        missing.push(tool);
                }
                root.have = have;
                const mode = root.asking;
                root.asking = "";
                if (missing.length === 0) {
                    root.grant(mode);
                    return;
                }
                for (const tool of missing)
                    Notifier.missingDependency(Strings.trf("%1 not found", tool), root.whatFor(tool));
            }
        }
    }

    function whatFor(tool: string): string {
        if (tool === "grim")
            return Strings.tr("grim is used to capture the screen - install it to search or translate what is on screen.");
        if (tool === "tesseract")
            return Strings.tr("tesseract is used to read the text on screen - install it, along with a language pack for each language you read.");
        if (tool === "ffmpeg")
            return Strings.tr("ffmpeg is used to cut the selection out of the screen capture - install it to search or translate what is on screen.");
        if (tool === "zbarimg")
            return Strings.tr("zbarimg is used to read QR codes and barcodes - install zbar (zbar-tools on Debian and Ubuntu) to scan codes on screen.");
        return Strings.tr("curl is used to reach the translator - install it, or set a translate command of your own.");
    }

    function grant(mode: string): void {
        root.job++;
        root.clearResults();
        const screen = ActiveOutput.screen;
        root.outputName = screen ? screen.name : "";
        root.outputX = screen ? screen.x : 0;
        root.outputY = screen ? screen.y : 0;
        root.mode = mode;
        root.phase = "capture";
        // a gesture picked off the menu waits for the menu to go; one that was
        // cancelled in that moment has nothing left to grant
        const job = root.job;
        root.afterMenu(() => {
            if (root.job === job && root.phase === "capture")
                root.granted();
        });
    }

    // Called once nothing of pibble's own is left on screen to be captured.
    function capture(): void {
        if (!root.active || root.phase !== "capture")
            return;
        if (root.mode === "region") {
            root.phase = "select";
            return;
        }
        settle.restart();
    }

    // The same beat the eyedropper waits, for the same reason: whatever just
    // left the screen needs a frame to actually be gone from it.
    Timer {
        id: settle
        interval: 15
        onTriggered: {
            grim.job = root.job;
            grim.command = root.outputName ? ["grim", "-o", root.outputName, "-t", "ppm", root.framePath] : ["grim", "-t", "ppm", root.framePath];
            grim.running = true;
        }
    }

    Process {
        id: grim
        property int job: 0
        onExited: exitCode => {
            if (grim.job !== root.job || root.phase !== "capture") {
                Quickshell.execDetached(["rm", "-f", "--", root.framePath]);
                return;
            }
            if (exitCode !== 0) {
                root.fail(Strings.tr("Screen capture failed"), Strings.tr("grim could not capture the screen."));
                return;
            }
            root.shotPath = root.framePath;
            root.phase = "frame";
        }
    }

    // A capture or a decode that never arrives must not leave a transparent
    // window holding the screen's input forever.
    Timer {
        interval: 8000
        running: root.phase === "capture" || root.phase === "frame"
        onTriggered: root.fail(Strings.tr("Screen capture failed"), Strings.tr("The captured frame never arrived."))
    }

    // The overlay, once it is showing the frame.
    function frameReady(width: int, height: int, ratio: real): void {
        if (root.phase !== "frame")
            return;
        root.frameWidth = width;
        root.frameHeight = height;
        root.ratio = ratio > 0 ? ratio : 1;
        root.phase = "select";
    }

    // Both ways out, and the only place the screen is given back.
    function close(): void {
        root.job++;
        settle.stop();
        ocr.again = false;
        ocr.running = false;
        scanner.running = false;
        translator.running = false;
        root.queue = [];
        root.mode = "";
        root.phase = "";
        root.host = "overlay";
        root.clearResults();
        if (root.shotPath) {
            Quickshell.execDetached(["rm", "-f", "--", root.shotPath]);
            root.shotPath = "";
        }
    }
    // A translation that has nothing to show: the screen is given back and
    // the reason arrives as a notification, the way the rest of the shell
    // says what happened, rather than over a frozen frame with nothing on it.
    function giveUp(summary: string): void {
        root.close();
        Notifier.action("preferences-desktop-locale", summary, "", "");
    }
    function fail(summary: string, body: string): void {
        root.close();
        Notifier.error(summary, body);
    }
    function clearResults(): void {
        root.selection = Qt.rect(0, 0, 0, 0);
        root.text = "";
        root.translation = "";
        root.translating = false;
        root.notice = "";
        root.blocks.clear();
        root.painted = 0;
    }

    // ---------- marking ----------

    // The user dragged a rectangle over this much of the frame (frame
    // pixels). Marking again while a result is up simply starts over on the
    // new selection.
    function select(x: real, y: real, width: real, height: real): void {
        if (!root.reading || !["select", "working", "result"].includes(root.phase))
            return;
        const left = Math.max(0, Math.floor(x));
        const top = Math.max(0, Math.floor(y));
        const w = Math.min(root.frameWidth - left, Math.ceil(width));
        const h = Math.min(root.frameHeight - top, Math.ceil(height));
        if (w < 4 || h < 4)
            return;
        translator.running = false;
        root.clearResults();
        root.selection = Qt.rect(left, top, w, h);
        root.phase = "working";
        if (root.mode === "code") {
            root.scan(left, top, w, h);
            return;
        }
        // 11 is "sparse text": find every line there is and assume nothing
        // about how they relate - the truth about a stretch of screen, where
        // 3, the page layout analysis, goes looking for a single column of
        // print. A translation's paragraphs are put together afterwards,
        // from where the lines sit (see paragraphs). 6, "one uniform block of
        // text", suits the rest: a rectangle dragged to be searched or copied
        // is usually a word, a line or a paragraph, and the layout analysis
        // gives up on anything that small and reports an empty one.
        root.read(left, top, w, h, root.mode === "translate" ? "11" : "6");
    }

    // Back to an empty frame, for a second try at a rectangle.
    function reselect(): void {
        if (!root.reading || root.phase === "capture" || root.phase === "frame")
            return;
        translator.running = false;
        root.clearResults();
        root.phase = "select";
    }

    // region: the dragged rectangle in the overlay's own logical pixels, or a
    // zero-sized one for "the whole output".
    function chooseRegion(x: real, y: real, width: real, height: real): void {
        if (root.mode !== "region")
            return;
        const output = root.outputName;
        // wf-recorder wants whole, even numbers: every encoder it can be
        // pointed at refuses an odd width or height
        const w = Math.floor(width / 2) * 2;
        const h = Math.floor(height / 2) * 2;
        const geometry = w >= 16 && h >= 16 ? (root.outputX + Math.round(x)) + "," + (root.outputY + Math.round(y)) + " " + w + "x" + h : "";
        root.close();
        root.regionChosen(output, geometry);
    }

    // ---------- reading ----------

    // How far to enlarge a crop before tesseract sees it. The aim is the
    // letter height it was trained on - about two and a half times what a
    // screen draws at scale 1, and proportionally less on an output that is
    // already scaled - held under a pixel budget, because the time a read
    // takes grows with the area and a large output read whole at 2.5x takes most of a
    // minute. Below the budget the factor is the ideal one; above it the read
    // is traded down toward what finishes while the user is still looking.
    readonly property real pixelBudget: 12e6
    function upscale(width: int, height: int): real {
        const ideal = Math.max(1, Math.min(3, 2.5 / root.ratio));
        const affordable = Math.sqrt(root.pixelBudget / Math.max(1, width * height));
        return Math.max(0.5, Math.min(ideal, affordable));
    }

    // Counts reads, so an answer can be matched to the question (see `ocr`).
    property int reads: 0

    // A wide rectangle is read as side-by-side strips, all at once. Tesseract
    // reads one image on one core, and what it costs grows with how wide the
    // image is more than with how much text there is in it - a large output
    // read whole kept the user waiting the better part of ten seconds while
    // the rest of the machine idled. Cut into strips about a column wide it is
    // done in about the time one strip takes.
    //
    // The strips overlap by more than a long word, and each word found is
    // kept by the one strip its middle falls in (the strip's `core`), so a
    // word cut by one strip's edge is read whole by its neighbour. A line
    // that runs across a cut comes back in two pieces, which are put back
    // together by where they sit (see rejoined). A selection narrow enough to
    // read quickly is one strip.
    function strips(width: int): var {
        const wide = 900;
        const overlap = 200;
        const count = Math.max(1, Math.min(8, Math.round(width / wide)));
        const step = Math.ceil(width / count);
        const out = [];
        for (let i = 0; i < count; i++) {
            const core0 = i * step;
            const core1 = Math.min(width, (i + 1) * step);
            const x = Math.max(0, core0 - overlap);
            out.push({ x: x, w: Math.min(width, core1 + overlap) - x, core0: core0, core1: i === count - 1 ? width + 1 : core1 });
        }
        return out;
    }

    function read(x: int, y: int, width: int, height: int, psm: string): void {
        const up = root.upscale(width, height);
        const scaledWidth = Math.max(1, Math.round(width * up));
        const filter = "crop=" + width + ":" + height + ":" + x + ":" + y + ",scale=" + scaledWidth + ":" + Math.max(1, Math.round(height * up)) + ":flags=lanczos";
        ocr.strips = root.strips(scaledWidth);
        const cuts = ocr.strips.map(strip => strip.x + ":" + strip.w).join(" ");
        // only a translation paints over the page, so only it asks for colors
        const thumbHeight = Math.max(1, Math.round(root.thumbWidth * root.frameHeight / Math.max(1, root.frameWidth)));
        const thumb = root.mode === "translate" ? root.thumbWidth + ":" + thumbHeight : "";
        root.thumb = { width: 0, height: 0, hex: "" };
        ocr.thumbHeight = thumbHeight;
        root.reads++;
        ocr.offsetX = x;
        ocr.offsetY = y;
        ocr.up = up;
        ocr.job = root.job;
        ocr.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            frame="$1"; crop="$2"; filter="$3"; langs="$4"; psm="$5"
            echo "READ $6"
            # every installed language, minus the two entries in that list that
            # are not languages (orientation detection and equations)
            if [ -z "$langs" ]; then
                langs=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -v -x -e osd -e equ | paste -sd+ -)
            fi
            [ -n "$langs" ] || { echo NOLANGS; exit 0; }
            # The whole selection is the crop the image search uploads; the
            # strips (see strips()) are cut from it, each read on a core of its
            # own.
            ffmpeg -y -v error -i "$frame" -vf "$filter" -frames:v 1 "$crop" 2>/dev/null || { echo NOCROP; exit 0; }
            # Each strip is read twice at once, under two ways of telling ink
            # from paper (0 is one threshold for the image, 2 one that follows
            # the local background); the two answers are folded together in
            # merged(). Every file is named for this read, so a killed read's
            # straggler cannot write into the next one's. One tesseract thread
            # each: the strips are the parallelism, and its own threads on top
            # only fight them for the cores. The tsv variable rather than the
            # "tsv" config file that sets it: the file ships in a separate
            # package on some distros, and asking for one that is not there is
            # an error where this is not.
            i=0
            for cut in $8; do
                x=$(printf '%s' "$cut" | cut -d: -f1); w=$(printf '%s' "$cut" | cut -d: -f2)
                part="$crop.$6.$i.ppm"
                (
                    ffmpeg -y -v error -i "$crop" -vf "crop=$w:ih:$x:0" -frames:v 1 "$part" 2>/dev/null || exit 0
                    OMP_THREAD_LIMIT=1 tesseract "$part" - -l "$langs" --psm "$psm" -c tessedit_create_tsv=1 > "$part.a" 2>/dev/null &
                    OMP_THREAD_LIMIT=1 tesseract "$part" - -l "$langs" --psm "$psm" -c tessedit_create_tsv=1 -c thresholding_method=2 > "$part.b" 2>/dev/null
                    wait
                ) &
                i=$((i + 1))
            done
            wait
            i=0
            for cut in $8; do
                part="$crop.$6.$i.ppm"
                echo "STRIP $i"
                cat "$part.a" 2>/dev/null
                echo "PASS"
                cat "$part.b" 2>/dev/null
                rm -f "$part" "$part.a" "$part.b"
                i=$((i + 1))
            done
            # the frame in miniature, as hex, for the page's colors (see swatch)
            if [ -n "$7" ]; then
                echo "THUMB"
                ffmpeg -v error -i "$frame" -vf "scale=$7:flags=area" -f rawvideo -pix_fmt rgb24 - 2>/dev/null | od -An -v -tx1 | tr -d '[:space:]'
            fi`,
            "_", root.shotPath, root.cropPath, filter, (Settings.ocrLanguages || "").trim(), psm, String(root.reads), thumb, cuts];
        // A read still running is for a selection nobody wants any more. It is
        // killed, and the new one starts from its exit - a Process cannot be
        // restarted in the same breath it is stopped in.
        if (ocr.running) {
            ocr.again = true;
            ocr.running = false;
        } else {
            ocr.running = true;
        }
    }

    Process {
        id: ocr
        property int job: 0
        property int offsetX: 0
        property int offsetY: 0
        property real up: 1
        property var strips: []
        property int thumbHeight: 0
        property bool again: false
        onExited: {
            if (ocr.again) {
                ocr.again = false;
                Qt.callLater(() => ocr.running = true);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // The script names the read it belongs to on its first line.
                // A killed one may still deliver whatever it had printed, and
                // whether that lands before or after its exit is not promised
                // - so the answer is matched by what it says it is, not by
                // when it arrived.
                const cut = text.indexOf("\n");
                const head = cut < 0 ? text : text.slice(0, cut);
                if (head !== "READ " + root.reads || ocr.job !== root.job || root.phase !== "working")
                    return;
                const body = text.slice(cut + 1);
                if (body.startsWith("NOLANGS")) {
                    root.close();
                    Notifier.missingDependency(Strings.tr("No tesseract language found"), Strings.tr("tesseract is installed without a language pack - install one for each language you read (e.g. tesseract-langpack-eng)."));
                    return;
                }
                if (body.startsWith("NOCROP")) {
                    root.fail(Strings.tr("Reading the screen failed"), Strings.tr("ffmpeg could not cut the selection out of the captured frame."));
                    return;
                }
                const mark = body.indexOf("\nTHUMB\n");
                const hex = mark < 0 ? "" : body.slice(mark + 7).trim();
                // a thumbnail of the wrong length is one ffmpeg did not finish
                if (hex.length === root.thumbWidth * ocr.thumbHeight * 6)
                    root.thumb = { width: root.thumbWidth, height: ocr.thumbHeight, hex: hex };
                root.readFinished(root.paragraphs(mark < 0 ? body : body.slice(0, mark), ocr.strips, ocr.offsetX, ocr.offsetY, ocr.up));
            }
        }
    }

    // Scripts written without spaces between words. Tesseract reports each
    // character or run of them as a "word", and joining those with spaces
    // would put a gap between every pair - which also happens to break the
    // translation, since the translator then sees a list of single characters.
    function unspaced(ch: string): bool {
        const code = ch.charCodeAt(0);
        return (code >= 0x2e80 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) || (code >= 0xff00 && code <= 0xffef);
    }
    function join(parts: var): string {
        let out = "";
        for (const part of parts) {
            if (!part)
                continue;
            if (out && !(root.unspaced(out[out.length - 1]) && root.unspaced(part[0])))
                out += " ";
            out += part;
        }
        return out;
    }

    // Whether a run of words holds anything a person would call text. What it
    // turns away is the debris tesseract makes of icons, rules and window
    // borders - a lone "|", a run of dashes, a stray "=" - and, with an East
    // Asian language pack installed, the long-vowel mark and the middle dot it
    // likes to see in any short horizontal stroke. So: letters and digits
    // only, punctuation of every script left out; at least two of them, or one
    // if that one is an ideograph, which is a word by itself; and a run that
    // short has to be one tesseract was sure of.
    //
    // When translating, a run tesseract was not reasonably sure of as a whole
    // is not text either: that is what it makes of a photograph or a scan behind the
    // words - "GE GEIS HE" out of a book's page edge - and translated, it is
    // painted over the picture as a box of nonsense.
    function legible(text: string, sure: real): bool {
        if (root.mode === "translate" && sure < 62)
            return false;
        const kept = text.match(/[A-Za-z0-9À-῿ぁ-ゖァ-ヺ㐀-鿿가-힯豈-﫿]/g);
        if (kept === null)
            return false;
        if (kept.length >= 3)
            return true;
        const ideograph = kept[0].charCodeAt(0) >= 0x3400;
        return sure >= 75 && (kept.length === 2 || ideograph);
    }

    // One pass of tesseract's TSV as lines of words: only the rows at level 5
    // carry text, and each names the line it sits in. A line is scored by how
    // much text it holds and how sure tesseract was of it, which is what two
    // readings of the same line are compared on (see merged).
    function wordLines(tsv: string): var {
        const lines = [];
        const byKey = {};
        for (const row of tsv.split("\n")) {
            const cell = row.split("\t");
            if (cell.length < 12 || cell[0] !== "5")
                continue;
            const text = cell.slice(11).join(" ").trim();
            const sure = parseFloat(cell[10]);
            // confidence below this is where tesseract is guessing at shapes
            // that are not letters at all
            if (!text || sure < 30)
                continue;
            const key = cell[2] + "." + cell[3] + "." + cell[4];
            let line = byKey[key];
            if (!line) {
                line = byKey[key] = { words: [], score: 0, x0: 1e9, y0: 1e9, x1: 0, y1: 0 };
                lines.push(line);
            }
            const x = parseInt(cell[6]), y = parseInt(cell[7]);
            const word = { text: text, sure: sure, x0: x, y0: y, x1: x + parseInt(cell[8]), y1: y + parseInt(cell[9]) };
            line.words.push(word);
            line.score += sure * text.length;
            line.x0 = Math.min(line.x0, word.x0);
            line.y0 = Math.min(line.y0, word.y0);
            line.x1 = Math.max(line.x1, word.x1);
            line.y1 = Math.max(line.y1, word.y1);
        }
        for (const line of lines)
            line.words.sort((a, b) => a.x0 - b.x0);
        return lines;
    }

    // Two readings of one image, folded into one. The screen is read twice
    // because tesseract has to decide what is ink and what is paper before it
    // reads anything, and no one way of deciding suits a whole screen: its
    // default finds dark text on a light page and loses a white title on a
    // colored bar; the adaptive one finds the title and drops body text the
    // default had. A line only one of them saw is kept as it is. Where both
    // read the same line the first reading stands unless the second is better
    // by a clear margin: the adaptive pass reports looser boxes around what it
    // reads (a word's box is often its whole line's), and a line that measures
    // twice the height of its neighbours no longer joins their paragraph - so
    // a tie, or a win by one stray quote mark, goes to the default.
    function merged(first: var, second: var): var {
        const out = first.slice();
        for (const line of second) {
            const rivals = out.filter(other => {
                const shared = Math.min(line.y1, other.y1) - Math.max(line.y0, other.y0);
                return shared > Math.min(line.y1 - line.y0, other.y1 - other.y0) * 0.5 && Math.min(line.x1, other.x1) > Math.max(line.x0, other.x0);
            });
            if (rivals.length === 0) {
                out.push(line);
                continue;
            }
            let theirs = 0;
            for (const rival of rivals)
                theirs += rival.score;
            if (line.score <= theirs * 1.25)
                continue;
            for (const rival of rivals)
                out.splice(out.indexOf(rival), 1);
            out.push(line);
        }
        return out;
    }

    // A line around the words given, its box and score worked out again.
    function bounded(words: var): var {
        const line = { words: words, score: 0, x0: 1e9, y0: 1e9, x1: 0, y1: 0 };
        for (const word of words) {
            line.score += word.sure * word.text.length;
            line.x0 = Math.min(line.x0, word.x0);
            line.y0 = Math.min(line.y0, word.y0);
            line.x1 = Math.max(line.x1, word.x1);
            line.y1 = Math.max(line.y1, word.y1);
        }
        return line;
    }

    // Pieces of one line that a cut between strips left apart, put back
    // together: two pieces that share most of their height and sit no
    // further apart than the gap a run allows (see paragraphs) are one line.
    // Pieces further apart than that are other columns, and a run would
    // split them again anyway.
    function rejoined(pieces: var): var {
        const out = [];
        for (const piece of pieces.slice().sort((a, b) => a.x0 - b.x0)) {
            const height = piece.y1 - piece.y0;
            const home = out.find(line => {
                const shared = Math.min(line.y1, piece.y1) - Math.max(line.y0, piece.y0);
                return shared > Math.min(height, line.y1 - line.y0) * 0.5 && piece.x0 - line.x1 < Math.max(height, line.y1 - line.y0) * 2;
            });
            if (!home) {
                out.push(piece);
                continue;
            }
            const words = home.words.concat(piece.words).sort((a, b) => a.x0 - b.x0);
            out.splice(out.indexOf(home), 1, root.bounded(words));
        }
        return out;
    }

    // tesseract's lines, rebuilt into paragraphs.
    //
    // The line is the only piece of tesseract's layout this keeps. Its
    // paragraphs and blocks are a page's - it was taught on print - and a
    // screen is not one: asked to analyse a web page it read a headline and
    // the first line of the next column as one sentence, and returned every
    // line of a paragraph as a paragraph of its own. So the words are taken as
    // runs along a line, and the paragraphs rebuilt from where those runs sit:
    //
    //   - a run ends where the gap to the next word is wider than any space
    //     between words gets - a gutter, so the next word is another column's
    //   - a run joins the paragraph directly above it when the two are set in
    //     about the same size, sit closer than a blank line apart, and share a
    //     column
    //
    // Everything comes back in the frame's own pixels, mapped out of the
    // enlarged crop tesseract was shown.
    function paragraphs(tsv: string, strips: var, offsetX: int, offsetY: int, up: real): var {
        // each strip's two readings folded together, moved across to where
        // the strip sits, and left with only the words whose middle is its own
        const pieces = [];
        for (const chunk of tsv.split(/^STRIP /m)) {
            const cut = chunk.indexOf("\n");
            const strip = strips[parseInt(chunk.slice(0, cut))];
            if (cut < 0 || !strip)
                continue;
            const passes = chunk.slice(cut + 1).split("\nPASS\n");
            let read = root.wordLines(passes[0]);
            for (let i = 1; i < passes.length; i++)
                read = root.merged(read, root.wordLines(passes[i]));
            for (const line of read) {
                const words = [];
                for (const word of line.words) {
                    word.x0 += strip.x;
                    word.x1 += strip.x;
                    const middle = (word.x0 + word.x1) / 2;
                    if (middle >= strip.core0 && middle < strip.core1)
                        words.push(word);
                }
                if (words.length > 0)
                    pieces.push(root.bounded(words));
            }
        }
        const lines = root.rejoined(pieces);

        // lines → runs
        const runs = [];
        for (const line of lines) {
            const height = line.y1 - line.y0;
            let run = null;
            for (const word of line.words) {
                if (!run || word.x0 - run.x1 > height * 2) {
                    run = { words: [], sure: 0, x0: word.x0, y0: word.y0, x1: word.x1, y1: word.y1 };
                    runs.push(run);
                }
                run.words.push(word.text);
                run.sure += word.sure;
                run.x0 = Math.min(run.x0, word.x0);
                run.y0 = Math.min(run.y0, word.y0);
                run.x1 = Math.max(run.x1, word.x1);
                run.y1 = Math.max(run.y1, word.y1);
            }
        }

        // runs → paragraphs, top to bottom
        const kept = runs.map(run => Object.assign(run, { text: root.join(run.words) })).filter(run => root.legible(run.text, run.sure / run.words.length));
        kept.sort((a, b) => a.y0 - b.y0 || a.x0 - b.x0);
        const found = [];
        for (const run of kept) {
            const height = run.y1 - run.y0;
            let home = null;
            for (let i = found.length - 1; i >= 0 && !home; i--) {
                const paragraph = found[i];
                const above = paragraph.last;
                const tall = Math.max(height, above.y1 - above.y0);
                const small = Math.min(height, above.y1 - above.y0);
                // A line with no descenders, or no ascenders, measures well
                // short of its neighbours in the same type - hence the slack.
                // A headline over its story is past it on any page.
                if (small < tall * 0.6)
                    continue;
                // closer than a blank line: the leading inside a paragraph
                // leaves a gap of under one line's height even set loose, and
                // the space between two paragraphs - or under a subheading the
                // size of its text - starts at about one and a half
                const gap = run.y0 - above.y1;
                if (gap < -tall * 0.25 || gap > tall)
                    continue;
                const shared = Math.min(run.x1, paragraph.x1) - Math.max(run.x0, paragraph.x0);
                if (shared < Math.min(run.x1 - run.x0, paragraph.x1 - paragraph.x0) * 0.5)
                    continue;
                home = paragraph;
            }
            if (!home) {
                home = { parts: [], heights: [], x0: run.x0, y0: run.y0, x1: run.x1, y1: run.y1, last: run };
                found.push(home);
            }
            home.parts.push(run.text);
            home.heights.push(height);
            home.x0 = Math.min(home.x0, run.x0);
            home.y0 = Math.min(home.y0, run.y0);
            home.x1 = Math.max(home.x1, run.x1);
            home.y1 = Math.max(home.y1, run.y1);
            home.last = run;
        }

        return found.map(paragraph => {
            const heights = paragraph.heights.slice().sort((a, b) => a - b);
            // A word broken over a line end is one word. The hyphen stays: it
            // cannot be told from the hyphen of a compound from here, and a
            // translator reads through a stray one better than a missing one.
            let source = "";
            for (const part of paragraph.parts)
                source = source.endsWith("-") ? source + part : root.join([source, part]);
            return {
                // b- for "box": a model role named x or width would shadow the
                // delegate's own geometry
                bx: offsetX + paragraph.x0 / up,
                by: offsetY + paragraph.y0 / up,
                bw: (paragraph.x1 - paragraph.x0) / up,
                bh: (paragraph.y1 - paragraph.y0) / up,
                // the middle line's height, so a single short line (no
                // descenders, say) does not set the type size for the rest
                lineHeight: heights[Math.floor(heights.length / 2)] / up,
                source: source,
                // the same words as they were set, a line to each line - what
                // copying text wants, where a translator wants the sentences
                lines: paragraph.parts.join("\n"),
                text: "",
                // set once a translation has come back identical to the source:
                // the paragraph was already in the user's language
                same: false,
                // the colors the translation is set in, sampled off the page
                // under it (see swatch)
                paper: "#101014",
                ink: "#f2f0ee"
            };
        });
    }

    // ---------- the page's own colors ----------

    // The frame, scaled down to a quarter of its width and sent back as hex by
    // the same script that reads it. It is how a translated paragraph gets to
    // sit on the page's own background rather than on a card of the shell's:
    // nothing in QML can read a pixel out of an image without a Canvas, and
    // the Canvas route has been walked once already (see ColorPickerOverlay's
    // lens for what it takes); one ffmpeg call nobody is waiting on is not it.
    // A fraction of the frame rather than a fixed size, so that whatever the
    // output's resolution the ring of pixels just outside a box of text (see
    // swatch) is background and not a blur of background and the text beside
    // it: at a fixed 320 pixels a large output had one thumbnail pixel
    // standing for a dozen or more of the frame's, and every box came out a
    // muddy grey whatever it sat on.
    readonly property int thumbWidth: Math.max(320, Math.round(root.frameWidth / 4))
    property var thumb: ({ width: 0, height: 0, hex: "" })

    // The background a box of the frame sits on, and the ink that will read on
    // it. Taken from the ring of thumbnail pixels just outside the box rather
    // than from inside it: inside is a blend of background and text, and how
    // much of each depends on the type - under a bold white title on a colored
    // bar there is more title than bar. Just outside a box of text there is,
    // by construction, no text. The middle of that ring by brightness is the
    // answer, so a box that hangs off the edge of the bar it sits on is still
    // painted the color most of its edge is on.
    function swatch(x: real, y: real, width: real, height: real): var {
        const t = root.thumb;
        if (!t.width || !root.frameWidth)
            return { paper: "#101014", ink: "#f2f0ee" };
        const sx = t.width / root.frameWidth, sy = t.height / root.frameHeight;
        const clampX = v => Math.max(0, Math.min(t.width - 1, v));
        const clampY = v => Math.max(0, Math.min(t.height - 1, v));
        const x0 = clampX(Math.floor(x * sx) - 1), x1 = clampX(Math.ceil((x + width) * sx));
        const y0 = clampY(Math.floor(y * sy) - 1), y1 = clampY(Math.ceil((y + height) * sy));
        const pixels = [];
        const take = (column, row) => {
            const at = (row * t.width + column) * 6;
            const r = parseInt(t.hex.substr(at, 2), 16), g = parseInt(t.hex.substr(at + 2, 2), 16), b = parseInt(t.hex.substr(at + 4, 2), 16);
            pixels.push([0.2126 * r + 0.7152 * g + 0.0722 * b, r, g, b]);
        };
        for (let column = x0; column <= x1; column++) {
            take(column, y0);
            take(column, y1);
        }
        for (let row = y0 + 1; row < y1; row++) {
            take(x0, row);
            take(x1, row);
        }
        pixels.sort((a, b) => a[0] - b[0]);
        const pick = pixels[Math.floor(pixels.length / 2)];
        const hex = n => Math.round(n).toString(16).padStart(2, "0");
        return { paper: "#" + hex(pick[1]) + hex(pick[2]) + hex(pick[3]), ink: pick[0] > 140 ? "#161616" : "#f4f2ef" };
    }

    // Paragraphs that would be painted over each other, thinned out to the
    // larger of each pair. Two boxes only overlap where tesseract has read the
    // same place twice in different ways, or found words inside a picture
    // under a caption - and two translations stacked on one spot read as
    // neither.
    function uncrowded(found: var): var {
        const area = p => p.bw * p.bh;
        const kept = [];
        for (const paragraph of found.slice().sort((a, b) => area(b) - area(a))) {
            const crowded = kept.some(other => {
                const w = Math.min(paragraph.bx + paragraph.bw, other.bx + other.bw) - Math.max(paragraph.bx, other.bx);
                const h = Math.min(paragraph.by + paragraph.bh, other.by + other.bh) - Math.max(paragraph.by, other.by);
                return w > 0 && h > 0 && w * h > area(paragraph) * 0.2;
            });
            if (!crowded)
                kept.push(paragraph);
        }
        // back into reading order, which is the order they are translated in
        return kept.sort((a, b) => a.by - b.by || a.bx - b.bx);
    }

    function readFinished(found: var): void {
        if (root.mode === "search") {
            root.text = found.map(p => p.source).join("\n");
            root.notice = root.text ? "" : Strings.tr("No text found here");
            root.phase = "result";
            return;
        }
        if (root.mode === "copy") {
            const text = found.map(p => p.lines).join("\n");
            if (text) {
                // onto the clipboard while the overlay still has the keyboard:
                // a Wayland compositor can refuse a selection from a client
                // with no focused surface left
                Notifier.copyToClipboard(text);
                root.close();
                return;
            }
            // the frame stays up, for another rectangle
            root.notice = Strings.tr("No text found here - drag again");
            root.phase = "select";
            return;
        }
        if (found.length === 0) {
            root.notice = Strings.tr("No text found here - drag again");
            root.phase = "select";
            return;
        }
        const kept = root.uncrowded(found);
        for (const paragraph of kept)
            root.blocks.append(Object.assign(paragraph, root.swatch(paragraph.bx, paragraph.by, paragraph.bw, paragraph.bh)));
        // The translator takes a few thousand characters at a time, so the
        // screen goes to it in batches of whole paragraphs, one per line -
        // line breaks are the one thing it reliably hands back where it found
        // them, which is what lets each answer find its box again.
        const batches = [];
        let batch = null;
        // counted over the paragraphs that were kept - the same list, in the
        // same order, as the boxes each answer is written back into
        for (let i = 0; i < kept.length; i++) {
            const length = kept[i].source.length + 1;
            if (!batch || batch.length + length > 3500) {
                batch = { first: i, count: 0, length: 0 };
                batches.push(batch);
            }
            batch.count++;
            batch.length += length;
        }
        root.queue = batches;
        root.nextBatch();
    }

    // ---------- codes ----------

    // A QR code or a barcode, read by zbarimg out of that much of the frame,
    // cut out and enlarged so a small code's modules are each several pixels
    // across. The enlargement is
    // nearest-neighbour: a code is hard edges, and smoothing them only blurs
    // the line zbar is looking for.
    property int scans: 0
    function scan(x: int, y: int, width: int, height: int): void {
        const up = Math.max(1, Math.min(4, Math.floor(1200 / Math.max(width, height))));
        const filter = "crop=" + width + ":" + height + ":" + x + ":" + y + ",scale=" + width * up + ":" + height * up + ":flags=neighbor";
        root.scans++;
        scanner.job = root.job;
        scanner.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            frame="$1"; crop="$2"; filter="$3"
            echo "SCAN $4"
            ffmpeg -y -v error -i "$frame" -vf "$filter" -frames:v 1 "$crop" 2>/dev/null || { echo NOCROP; exit 0; }
            # XML rather than the plain listing: a code can hold several lines,
            # and only the XML says where one code ends and the next begins
            zbarimg -q --xml "$crop" 2>/dev/null
            true`, "_", root.shotPath, root.cropPath, filter, String(root.scans)];
        // as with a read, a scan still going is for a circle nobody wants
        if (scanner.running) {
            scanner.again = true;
            scanner.running = false;
        } else {
            scanner.running = true;
        }
    }

    Process {
        id: scanner
        property int job: 0
        property bool again: false
        onExited: {
            if (scanner.again) {
                scanner.again = false;
                Qt.callLater(() => scanner.running = true);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const cut = text.indexOf("\n");
                const head = cut < 0 ? text : text.slice(0, cut);
                if (head !== "SCAN " + root.scans || scanner.job !== root.job || root.phase !== "working")
                    return;
                const body = text.slice(cut + 1);
                if (body.startsWith("NOCROP")) {
                    root.fail(Strings.tr("Reading the screen failed"), Strings.tr("ffmpeg could not cut the selection out of the captured frame."));
                    return;
                }
                root.scanned(root.codes(body));
            }
        }
    }

    // Every code's contents, out of zbarimg's XML. Each sits in a CDATA
    // section - several, when it holds a "]]>" of its own, which XML can only
    // carry by closing the section around it - or comes base64 encoded,
    // which is said on the data element.
    function codes(xml: string): var {
        const found = [];
        const symbols = /<data([^>]*)>([\s\S]*?)<\/data>/g;
        let symbol;
        while ((symbol = symbols.exec(xml)) !== null) {
            let data = "";
            const sections = /<!\[CDATA\[([\s\S]*?)\]\]>/g;
            let section;
            while ((section = sections.exec(symbol[2])) !== null)
                data += section[1];
            if (symbol[1].includes("base64")) {
                try {
                    data = Qt.atob(data.trim());
                } catch (e) {
                    continue;
                }
            }
            if (data && !found.includes(data))
                found.push(data);
        }
        return found;
    }

    // The first code in the rectangle is the one shown; none leaves the
    // frame up for another rectangle.
    function scanned(found: var): void {
        if (found.length > 0) {
            root.text = found[0];
            root.phase = "result";
            return;
        }
        root.notice = Strings.tr("No code found here - drag again");
        root.phase = "select";
    }

    // what a code holds is a web address, to be opened rather than searched
    readonly property bool isLink: root.mode === "code" && /^https?:\/\/\S+$/i.test(root.text.trim())

    // A code's web address goes to the browser; anything else it holds is
    // searched for, the way circled text is.
    function openCode(): void {
        if (root.mode !== "code" || root.phase !== "result")
            return;
        if (!root.isLink) {
            root.searchText();
            return;
        }
        const url = root.text.trim();
        root.close();
        Quickshell.execDetached(["xdg-open", url]);
    }

    // ---------- translating ----------

    property var queue: []
    property int asks: 0

    function nextBatch(): void {
        if (root.queue.length === 0) {
            if (root.painted > 0) {
                root.phase = "result";
            } else {
                root.notice = Strings.tr("Already in your language");
                root.phase = "select";
            }
            return;
        }
        const batch = root.queue[0];
        const lines = [];
        for (let i = 0; i < batch.count; i++)
            lines.push(root.blocks.get(batch.first + i).source);
        root.ask(lines.join("\n"), batch);
    }

    // `batch` is the queue entry the answer belongs to, or null for the
    // search card's own translate chip.
    function ask(text: string, batch: var): void {
        root.asks++;
        translator.batch = batch;
        translator.job = root.job;
        translator.command = ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            text="$1"; to="$2"; custom="$3"
            echo "ASK $4"
            if [ -n "$custom" ]; then
                printf '%s' "$text" | PIBBLE_TRANSLATE_TO="$to" bash -c "$custom"
            else
                curl -fsS -m 20 "https://translate.googleapis.com/translate_a/single" --data-urlencode "client=gtx" --data-urlencode "sl=auto" --data-urlencode "tl=$to" --data-urlencode "dt=t" --data-urlencode "q=$text" 2>/dev/null
            fi`, "_", text, root.targetLanguage, Settings.translateCommand, String(root.asks)];
        translator.running = true;
    }

    Process {
        id: translator
        property var batch: null
        property int job: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const cut = text.indexOf("\n");
                const head = cut < 0 ? text : text.slice(0, cut);
                if (head !== "ASK " + root.asks || translator.job !== root.job)
                    return;
                root.answered(root.translated(text.slice(cut + 1)), translator.batch);
            }
        }
    }

    // The translator's answer as plain text, or "" where there was none. The
    // endpoint answers in JSON - a list of sentences, each with its source
    // beside it - and a custom command in the text itself.
    function translated(raw: string): string {
        if (Settings.translateCommand)
            return raw.replace(/\s+$/, "");
        try {
            return JSON.parse(raw)[0].map(sentence => sentence[0] ?? "").join("");
        } catch (e) {
            return "";
        }
    }

    // Two strings that differ only in case, spacing and punctuation are the
    // same sentence - which is how a paragraph already in the user's language
    // comes back, and such a paragraph is left showing as it was.
    function same(a: string, b: string): bool {
        const bare = s => s.toLowerCase().replace(/[\s.,;:!?'"`()\[\]{}<>\-_‘’“”…]/g, "");
        if (bare(a) === bare(b))
            return true;
        // ...and so is one the translator handed back mostly untouched: most
        // of its words were in the source as they stand. That is a paragraph
        // already in the user's language with a word or two of another, a
        // product name, or a misreading the translator could make nothing of -
        // and painting any of those over the page changes nothing but how it
        // looks.
        const words = s => s.toLowerCase().split(/[\s.,;:!?'"`()\[\]{}<>_‘’“”…]+/).filter(word => word.length > 0);
        const translated = words(a);
        const source = new Set(words(b));
        if (translated.length === 0)
            return true;
        return translated.filter(word => source.has(word)).length / translated.length >= 0.5;
    }

    function answered(answer: string, batch: var): void {
        if (!batch) {
            root.translating = false;
            if (answer)
                root.translation = answer;
            else
                root.notice = Strings.tr("Translation failed - is the network up?");
            return;
        }
        if (root.phase !== "working" || root.queue[0] !== batch)
            return;
        if (!answer) {
            root.queue = [];
            Notifier.error(Strings.tr("Translation failed"), Strings.tr("The translator could not be reached - is the network up?"));
            // what was translated before the failure stays on screen
            if (root.painted > 0)
                root.phase = "result";
            else
                root.close();
            return;
        }
        const lines = answer.split("\n");
        if (lines.length !== batch.count && batch.count > 1) {
            // The line breaks did not survive after all (a translator of the
            // user's own may well reflow), so there is no telling which answer
            // is whose. Ask again in halves, and halves of those where they
            // still come back wrong: one paragraph at a time is never wrong
            // about which box a sentence belongs in, but a screenful of them
            // one after another took the better part of a minute, and the
            // usual culprit is a single paragraph the halving soon isolates.
            const half = Math.ceil(batch.count / 2);
            const halves = [{ first: batch.first, count: half, length: 0 }, { first: batch.first + half, count: batch.count - half, length: 0 }];
            root.queue = halves.concat(root.queue.slice(1));
            root.nextBatch();
            return;
        }
        const texts = batch.count === 1 ? [lines.join(" ")] : lines;
        for (let i = 0; i < batch.count; i++) {
            const row = batch.first + i;
            const text = texts[i].trim();
            const unchanged = !text || root.same(text, root.blocks.get(row).source);
            root.blocks.setProperty(row, "text", text);
            root.blocks.setProperty(row, "same", unchanged);
            if (!unchanged)
                root.painted++;
        }
        root.queue = root.queue.slice(1);
        root.nextBatch();
    }

    // ---------- what a search result can be turned into ----------

    // The text as one line, short enough to be a query.
    readonly property string query: root.text.replace(/\s+/g, " ").trim().slice(0, 300)

    function searchText(): void {
        if (!root.query)
            return;
        const url = (Settings.searchUrl || Defaults.searchUrl).replace("%s", encodeURIComponent(root.query));
        root.close();
        Quickshell.execDetached(["xdg-open", url]);
    }

    function copyText(): void {
        const text = root.translation || root.text;
        if (!text)
            return;
        // before the overlay goes, for the reason copy's own read gives
        Notifier.copyToClipboard(text);
        root.close();
    }

    function translateText(): void {
        if (!root.text || root.translating || root.translation)
            return;
        root.notice = "";
        root.translating = true;
        // one request's worth: the translator turns away much more than this,
        // and a selection that long was not circled to be read off a card
        root.ask(root.text.slice(0, 4500), null);
    }

    // The selection itself, handed to Google Lens. There is no API for this:
    // the upload is the form the Lens page posts, and what comes back is a
    // redirect to the results - which is all a browser needs to be given. A
    // form like that can change without notice, so when no redirect comes back
    // the picture is put on the clipboard and the Lens page opened instead,
    // where a paste does by hand what the upload could not.
    // Google Lens, with the circled part of the screen. The upload has to be
    // made by the browser itself: the results page Lens redirects to is tied
    // to the session that did the uploading, so an upload made from here and
    // a results page opened in the browser are two strangers, and the page
    // comes up empty. So what opens is a page of pibble's own that carries the
    // image and posts it to Lens the moment it loads, the way the upload form
    // on Lens' own page would. It lives in the cache rather than in the
    // runtime folder a sandboxed browser cannot see into, and is deleted again
    // once the browser has had ample time to read it - it is a picture of
    // the screen.
    function searchImage(): void {
        if (root.phase !== "result")
            return;
        root.close();
        Quickshell.execDetached(["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            image="$1"; page="$2"; action="$3"
            mkdir -p "$(dirname "$page")"
            umask 077
            {
                echo '<!doctype html><meta charset="utf-8"><title>Google Lens</title>'
                echo '<form id="upload" method="POST" enctype="multipart/form-data" action="'"$action"'"><input type="file" name="encoded_image" id="image"></form>'
                printf '%s' '<script>const raw = atob("'
                base64 -w0 "$image"
                echo '"); const bytes = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i); const files = new DataTransfer(); files.items.add(new File([bytes], "selection.png", { type: "image/png" })); document.getElementById("image").files = files.files; document.getElementById("upload").submit();</script>'
            } > "$page"
            xdg-open "$page"
            sleep 60
            rm -f "$page"`, "_", root.cropPath, SystemInfo.cacheRoot + "/tools/lens.html", "https://lens.google.com/v3/upload?hl=" + encodeURIComponent(Strings.code)]);
    }

    function copyImage(): void {
        if (root.phase !== "result")
            return;
        root.close();
        Quickshell.execDetached(["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            command -v wl-copy >/dev/null 2>&1 || { [ "$3" = 1 ] && notify-send -a pibble -i system-software-install "$6" "$7"; exit 0; }
            wl-copy -t image/png < "$1"
            [ "$2" = 1 ] && notify-send -a pibble -i edit-copy -h "string:image-path:$1" "$4" "$5"`,
            "_", root.cropPath, Settings.alertEnabled("actions") ? "1" : "0", Settings.alertEnabled("missingDeps") ? "1" : "0",
            Strings.tr("Copied to clipboard"), Strings.tr("the selected part of the screen"),
            Strings.tr("wl-copy not found"), Strings.tr("wl-copy (wl-clipboard) is used to place clipboard history entries back on the clipboard - install it to copy from this page.")]);
    }

    // translate: every translated paragraph, in reading order.
    function copyTranslation(): void {
        const parts = [];
        for (let i = 0; i < root.blocks.count; i++) {
            const row = root.blocks.get(i);
            if (row.text && !row.same)
                parts.push(row.text);
        }
        if (parts.length === 0)
            return;
        Notifier.copyToClipboard(parts.join("\n"));
        root.close();
    }
}
