import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    component SLabel: Text {
        color: root.muted
        font { family: root.mono; pixelSize: root.fs(14) }
        anchors.verticalCenter: parent.verticalCenter
    }
    component SBtn: Rectangle {
        id: sbtn
        property string label
        signal pressed
        width: 28
        height: 28
        radius: 8
        color: Qt.alpha(root.accent, btnArea.containsMouse ? 0.25 : 0.11)
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.33)
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            text: sbtn.label
            color: root.accent
            font { family: root.mono; pixelSize: root.fs(15); weight: Font.Bold }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sbtn.pressed()
        }
    }
    component SValue: Text {
        color: root.fg
        width: 90
        horizontalAlignment: Text.AlignHCenter
        font { family: root.mono; pixelSize: root.fs(14) }
        anchors.verticalCenter: parent.verticalCenter
    }

    // ---------- settings ----------
    FileView {
        id: settingsStore
        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: cfg
            property int appsCols: 4
            property int appsRows: 3
            property int wallsCols: 3
            property int wallsRows: 3
            property int clipsRows: 8
            property real fontScale: 1.0
            property string iconTheme: ""
            property string theme: "amber"
            property string wallpaperDir: "~/Pictures/wallpapers"
            property real dimOpacity: 0.4
            property var keybinds: ({ cycle: "Tab", launch: "Return", exit: "Escape" })
        }
    }
    function saveSettings() {
        settingsStore.writeAdapter();
    }

    // ---------- theme ----------
    readonly property var themes: [
        { id: "amber", name: "Amber", accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" },
        { id: "frost", name: "Frost", accent: "#7ab8e0", fg: "#e6eef4", muted: "#83919c" },
        { id: "moss",  name: "Moss",  accent: "#a3c76a", fg: "#eef3e4", muted: "#8d9378" },
        { id: "rose",  name: "Rose",  accent: "#e07a9a", fg: "#f4e8ec", muted: "#9c8389" },
        { id: "mono",  name: "Mono",  accent: "#cfcfcf", fg: "#f0f0f0", muted: "#8a8a8a" },
        { id: "dynamic", name: "Dynamic", accent: "", fg: "", muted: "" }
    ]
    // filled in from matugen (current wallpaper) at startup
    property var dynTheme: ({ accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" })
    readonly property var activeTheme: {
        if (cfg.theme === "dynamic")
            return dynTheme;
        const t = themes.find(t => t.id === cfg.theme);
        return t ?? themes[0];
    }
    readonly property color accent: activeTheme.accent
    readonly property color fg: activeTheme.fg
    readonly property color muted: activeTheme.muted
    readonly property string mono: "JetBrains Mono"

    function fs(px: int): int {
        return Math.round(px * cfg.fontScale);
    }

    Process {
        running: true
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            img=$(awww query -n workspaces 2>/dev/null | sed -n 's/.*displaying: image: //p' | head -1)
            [ -n "$img" ] || exit 0
            matugen image "$img" --json hex --dry-run --prefer saturation 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).colors;
                    root.dynTheme = {
                        accent: c.primary.dark.color,
                        fg: c.on_surface.dark.color,
                        muted: c.outline.dark.color
                    };
                } catch (e) {}
            }
        }
    }

    // ---------- apps ----------
    readonly property var allApps: {
        const list = Array.from(DesktopEntries.applications.values)
            .filter(e => !e.noDisplay);
        list.sort((a, b) => a.name.localeCompare(b.name));
        return list;
    }

    // Subsequence fuzzy match. Returns null when q doesn't match, else a
    // score favoring prefixes, word starts, consecutive runs, and short names.
    function fuzzyScore(lname: string, q: string): var {
        let score = 0;
        let next = 0;
        let prevMatch = -2;
        let consec = 0;
        for (let qi = 0; qi < q.length; qi++) {
            const found = lname.indexOf(q[qi], next);
            if (found < 0)
                return null;
            if (found === 0)
                score += 8;
            else if (" -_./".includes(lname[found - 1]))
                score += 6;
            if (found === prevMatch + 1) {
                consec++;
                score += 4 + consec;
            } else {
                consec = 0;
            }
            score -= found - next; // gap penalty
            prevMatch = found;
            next = found + 1;
        }
        if (lname.startsWith(q))
            score += 10;
        else if (lname.includes(q))
            score += 6;
        return score - lname.length * 0.1;
    }

    // Single-instance guard. The first instance records its pid and shows the
    // window; a second invocation instead asks the running one to dismiss
    // itself (by touching the toggle file it watches) and exits — so the
    // keybind acts as open/close and instances can never overlap.
    property bool primary: false
    readonly property string toggleFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/app-launcher.toggle"

    Process {
        running: true
        command: ["bash", "-c", `
            rt="\${XDG_RUNTIME_DIR:-/tmp}"
            pf="$rt/app-launcher.pid"
            tf="$rt/app-launcher.toggle"
            if [ -f "$pf" ]; then
                old=$(cat "$pf" 2>/dev/null)
                if [ -n "$old" ] && grep -qE 'quickshell|^qs$' "/proc/$old/comm" 2>/dev/null \\
                    && tr '\\0' ' ' < "/proc/$old/cmdline" 2>/dev/null | grep -q "Projects/launcher"; then
                    date +%s%N > "$tf"
                    echo DUP
                    exit 0
                fi
            fi
            echo "$PPID" > "$pf"
            [ -e "$tf" ] || echo 0 > "$tf"
            echo PRIMARY`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "PRIMARY")
                    root.primary = true;
                else
                    Qt.quit();
            }
        }
    }

    FileView {
        path: root.toggleFile
        watchChanges: root.primary
        printErrors: false
        onFileChanged: win.exit()
    }

    // Per-app launch counts, persisted across runs. Apps launched more often
    // rank higher in search results.
    FileView {
        id: store
        path: Quickshell.statePath("launch-counts.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: stats
            property var counts: ({})
        }
    }

    function launchCount(entry): int {
        return (stats.counts && stats.counts[entry.id]) || 0;
    }

    function recordLaunch(entry) {
        const c = Object.assign({}, stats.counts);
        c[entry.id] = (c[entry.id] || 0) + 1;
        stats.counts = c;
        store.writeAdapter();
    }

    // ---------- wallpapers ----------
    function expandHome(p: string): string {
        return p.startsWith("~") ? Quickshell.env("HOME") + p.slice(1) : p;
    }
    readonly property string wallDir: expandHome(cfg.wallpaperDir)

    // Each entry: path|thumb|blurred. Reuses the conventions: thumbnails/<f>
    // for grid previews, blurred/<f> or <stem>blurred.<ext> for the overview.
    property var wallpapers: []
    function rescanWallpapers() {
        wallScan.running = false;
        wallScan.running = true;
    }
    Process {
        id: wallScan
        running: true
        command: ["bash", "-c", `
            cd "$1" || exit 0
            shopt -s nullglob nocaseglob
            for f in *.png *.jpg *.jpeg *.webp; do
                case "$f" in *blurred.*) continue ;; esac
                stem="\${f%.*}" ext="\${f##*.}" thumb="$f" blur=""
                [ -e "thumbnails/$f" ] && thumb="thumbnails/$f"
                [ -e "blurred/$f" ] && blur="blurred/$f"
                [ -e "\${stem}blurred.$ext" ] && blur="\${stem}blurred.$ext"
                printf '%s|%s|%s\\n' "$PWD/$f" "$PWD/$thumb" "\${blur:+$PWD/$blur}"
            done | sort`, "_", root.wallDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const walls = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { path: p[0], thumb: p[1], blur: p[2] || "" };
                });
                root.wallpapers = walls;
                // Generate missing thumbnails (a full 5K image standing in as
                // its own thumbnail costs ~100ms to decode+upload) and blurred
                // overview variants in the background; the next scan picks
                // them up and applying never has to blur synchronously.
                const needsWork = walls.some(w => !w.blur || w.thumb === w.path);
                if (needsWork) {
                    Quickshell.execDetached(["bash", "-c", `
                        dir="$1"; shift
                        cd "$dir" || exit 0
                        mkdir -p thumbnails blurred
                        for f in "$@"; do
                            b=$(basename "$f")
                            stem="\${b%.*}" ext="\${b##*.}"
                            [ -e "thumbnails/$b" ] || magick "$f" -resize 480x270^ -gravity center -extent 480x270 "thumbnails/$b"
                            [ -e "blurred/$b" ] || [ -e "\${stem}blurred.$ext" ] || magick "$f" -resize 1024x -blur 0x10 "blurred/$b"
                        done`, "_", root.wallDir].concat(walls.map(w => w.path)));
                }
            }
        }
    }

    // ---------- clipboard history (cliphist) ----------
    property var clips: []
    property bool cliphistAvailable: true
    readonly property string clipThumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/app-launcher-clipthumbs"

    Process {
        id: clipScan
        running: true
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
            command -v cliphist >/dev/null || { echo NOCLIPHIST; exit 0; }
            cliphist list | head -60`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOCLIPHIST") {
                    root.cliphistAvailable = false;
                    return;
                }
                root.clips = text.split("\n").filter(l => l.trim()).map(l => {
                    const tab = l.indexOf("\t");
                    const id = l.slice(0, tab);
                    const preview = l.slice(tab + 1);
                    const m = preview.match(/^\[\[ binary data ([0-9.]+ \w+) (\w+) (\d+x\d+)/);
                    return m
                        ? { id, image: true, size: m[1], kind: m[2], dims: m[3], preview: m[2] + " image  " + m[3] + "  " + m[1], thumb: "" }
                        : { id, image: false, preview: preview.trim() };
                });
                const imgs = root.clips.filter(c => c.image).map(c => c.id);
                if (imgs.length) {
                    clipThumbs.command = ["bash", "-c", `
                        export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                        dir="$1"; shift
                        mkdir -p "$dir"
                        for id in "$@"; do
                            [ -s "$dir/$id.png" ] || cliphist decode "$id" > "$dir/$id.png"
                        done`, "_", root.clipThumbDir].concat(imgs);
                    clipThumbs.running = true;
                }
            }
        }
    }
    Process {
        id: clipThumbs
        onExited: {
            root.clips = root.clips.map(c => c.image
                ? Object.assign({}, c, { thumb: root.clipThumbDir + "/" + c.id + ".png" })
                : c);
        }
    }

    // ---------- icon themes ----------
    property var iconThemes: []
    Process {
        running: true
        command: ["bash", "-c", `
            for d in /usr/share/icons/* "$HOME/.icons"/* "$HOME/.local/share/icons"/*; do
                [ -f "$d/index.theme" ] || continue
                grep -q '^Directories=' "$d/index.theme" || continue
                basename "$d"
            done | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.iconThemes = text.split("\n").filter(l => l.trim())
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PanelWindow {
        id: win

        visible: root.primary
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "app-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // The blur protocol has no strength parameter, so "fade" the blur by
        // opening a circular hole of blur from the center. Quantized to an int
        // diameter so the region's x/y/width/height always change as one step.
        // niri maps the region from surface-local logical coordinates; use the
        // screen's logical size (not the window's, which briefly reports its
        // pre-configure 500x500 during startup and would place the early
        // frames off-center).
        property real reveal: 0
        readonly property real revW: screen ? screen.width : 0
        readonly property real revH: screen ? screen.height : 0
        // Clamped to 1px: an empty region reads as "no region set", which the
        // protocol treats as blur-the-whole-surface — a full-screen blur flash.
        readonly property int revealDiameter: Math.max(1, Math.ceil(Math.hypot(revW, revH) * reveal))
        BackgroundEffect.blurRegion: Region {
            shape: RegionShape.Ellipse
            x: (win.revW - win.revealDiameter) / 2
            y: (win.revH - win.revealDiameter) / 2
            width: win.revealDiameter
            height: win.revealDiameter
        }

        // ---------- pane state ----------
        // Tab cycles clock -> apps -> walls -> clips -> clock; the settings
        // pane sits outside the cycle (opened via the corner button).
        property string pane: "clock"
        readonly property var paneOrder: ["clock", "apps", "walls", "clips"]
        readonly property bool drawerOpen: pane === "apps"

        function setPane(p: string) {
            input.text = "";
            capturingBind = "";
            pane = p;
        }
        function cyclePane(dir: int) {
            if (pane === "settings") {
                setPane("clock");
                return;
            }
            const i = paneOrder.indexOf(pane);
            setPane(paneOrder[((i + dir) % paneOrder.length + paneOrder.length) % paneOrder.length]);
        }

        // ---------- matches ----------
        property var matches: {
            const q = input.text.toLowerCase().trim();
            if (!q) {
                const all = root.allApps.slice();
                all.sort((a, b) => root.launchCount(b) - root.launchCount(a)
                    || a.name.localeCompare(b.name));
                return all;
            }
            const scored = [];
            for (const a of root.allApps) {
                const s = root.fuzzyScore(a.name.toLowerCase(), q);
                if (s !== null)
                    scored.push({ entry: a, score: s });
            }
            scored.sort((x, y) => root.launchCount(y.entry) - root.launchCount(x.entry)
                || y.score - x.score
                || x.entry.name.localeCompare(y.entry.name));
            return scored.map(x => x.entry);
        }
        property int selected: 0
        onMatchesChanged: selected = 0
        readonly property int appPageSize: cfg.appsCols * cfg.appsRows
        readonly property int appPage: appPageSize > 0 ? Math.floor(selected / appPageSize) : 0

        function wallName(wall): string {
            return wall.path.split("/").pop().replace(/\.[^.]+$/, "");
        }
        property var wallMatches: {
            const q = input.text.toLowerCase().trim();
            if (!q)
                return root.wallpapers;
            const scored = [];
            for (const w of root.wallpapers) {
                const s = root.fuzzyScore(wallName(w).toLowerCase(), q);
                if (s !== null)
                    scored.push({ w, s });
            }
            scored.sort((x, y) => y.s - x.s || wallName(x.w).localeCompare(wallName(y.w)));
            return scored.map(x => x.w);
        }
        property int wallSelected: 0
        onWallMatchesChanged: wallSelected = 0
        readonly property int wallPageSize: cfg.wallsCols * cfg.wallsRows
        readonly property int wallPage: wallPageSize > 0 ? Math.floor(wallSelected / wallPageSize) : 0

        property var clipMatches: {
            const q = input.text.toLowerCase().trim();
            if (!q)
                return root.clips;
            const scored = [];
            for (const c of root.clips) {
                const s = root.fuzzyScore(c.preview.toLowerCase(), q);
                if (s !== null)
                    scored.push({ c, s });
            }
            scored.sort((x, y) => y.s - x.s);
            return scored.map(x => x.c);
        }
        property int clipSelected: 0
        onClipMatchesChanged: clipSelected = 0
        readonly property int clipPage: cfg.clipsRows > 0 ? Math.floor(clipSelected / cfg.clipsRows) : 0

        // ---------- navigation ----------
        // Horizontal: previous/next item, wrapping. Vertical: down a row
        // within the column; at the bottom of a column, hop to the top of the
        // next column (next page after the last column), and mirrored for up.
        function hMove(sel: int, count: int, dir: int): int {
            if (!count)
                return 0;
            return ((sel + dir) % count + count) % count;
        }
        function vMove(sel: int, count: int, cols: int, rows: int, dir: int): int {
            if (!count)
                return 0;
            const page = cols * rows;
            const p = Math.floor(sel / page);
            const w = sel % page;
            const r = Math.floor(w / cols);
            const c = w % cols;
            if (dir > 0) {
                const cand = sel + cols;
                if (r < rows - 1 && cand < count)
                    return cand;
                let np = p, nc = c + 1;
                if (nc >= cols) {
                    nc = 0;
                    np = p + 1;
                }
                const idx = np * page + nc;
                return idx < count ? idx : 0;
            } else {
                if (r > 0)
                    return sel - cols;
                let np = p, nc = c - 1;
                if (nc < 0) {
                    nc = cols - 1;
                    np = p - 1;
                }
                if (np < 0)
                    np = Math.ceil(count / page) - 1;
                for (let rr = rows - 1; rr >= 0; rr--) {
                    const idx = np * page + rr * cols + nc;
                    if (idx < count)
                        return idx;
                }
                return count - 1;
            }
        }
        function navigate(dx: int, dy: int) {
            if (pane === "apps") {
                selected = dy !== 0
                    ? vMove(selected, matches.length, cfg.appsCols, cfg.appsRows, dy)
                    : hMove(selected, matches.length, dx);
            } else if (pane === "walls") {
                wallSelected = dy !== 0
                    ? vMove(wallSelected, wallMatches.length, cfg.wallsCols, cfg.wallsRows, dy)
                    : hMove(wallSelected, wallMatches.length, dx);
            } else if (pane === "clips") {
                clipSelected = dy !== 0
                    ? vMove(clipSelected, clipMatches.length, 1, cfg.clipsRows, dy)
                    : hMove(clipSelected, clipMatches.length, dx * cfg.clipsRows);
            }
        }

        // ---------- actions ----------
        function launch(entry) {
            if (!entry)
                return;
            root.recordLaunch(entry);
            entry.execute();
            exit();
        }

        function applyWallpaper(wall) {
            if (!wall)
                return;
            // Workspaces get the image as-is; the overview gets the blurred
            // variant, generated into blurred/ with magick if none exists yet.
            Quickshell.execDetached(["bash", "-c", `
                export PATH="$HOME/.local/bin:$PATH"
                awww img -n workspaces --transition-type fade --transition-duration 1 "$1"
                BLUR="$2"
                if [ -z "$BLUR" ]; then
                    mkdir -p "$3/blurred"
                    BLUR="$3/blurred/$(basename "$1")"
                    [ -e "$BLUR" ] || magick "$1" -resize 1024x -blur 0x10 "$BLUR"
                fi
                awww img -n overview --transition-type fade --transition-duration 1 "$BLUR"
            `, "_", wall.path, wall.blur, root.wallDir]);
            exit();
        }

        function copyClip(clip) {
            if (!clip)
                return;
            Quickshell.execDetached(["bash", "-c", `
                export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                cliphist decode "$1" | wl-copy`, "_", clip.id]);
            exit();
        }

        function activate() {
            if (pane === "walls")
                applyWallpaper(wallMatches[wallSelected] ?? null);
            else if (pane === "clips")
                copyClip(clipMatches[clipSelected] ?? null);
            else if (pane === "apps")
                launch(matches.length ? matches[selected] : null);
            else if (pane === "clock")
                setPane("apps");
        }

        // ---------- keybinds ----------
        property string capturingBind: ""
        function keyName(event): string {
            const special = new Map([
                [Qt.Key_Tab, "Tab"], [Qt.Key_Backtab, "Tab"],
                [Qt.Key_Return, "Return"], [Qt.Key_Enter, "Return"],
                [Qt.Key_Escape, "Escape"], [Qt.Key_Space, "Space"],
                [Qt.Key_Backspace, "Backspace"], [Qt.Key_Delete, "Delete"],
                [Qt.Key_Home, "Home"], [Qt.Key_End, "End"],
                [Qt.Key_PageUp, "PageUp"], [Qt.Key_PageDown, "PageDown"]
            ]);
            const sp = special.get(event.key);
            let name = sp;
            if (!name && event.text && event.text.trim())
                name = event.text.toUpperCase();
            if (!name)
                return "";
            let s = "";
            if (event.modifiers & Qt.ControlModifier)
                s += "Ctrl+";
            if (event.modifiers & Qt.AltModifier)
                s += "Alt+";
            if ((event.modifiers & Qt.ShiftModifier) && sp)
                s += "Shift+";
            return s + name;
        }
        function setBind(action: string, key: string) {
            const kb = Object.assign({}, cfg.keybinds);
            kb[action] = key;
            cfg.keybinds = kb;
            root.saveSettings();
        }

        // ---------- exit / intro ----------
        property bool exiting: false
        function exit() {
            if (exiting)
                return;
            exiting = true;
            firstFrames.stop();
            fadeIn.stop();
            fadeOut.restart();
        }

        ParallelAnimation {
            id: fadeIn
            onFinished: win.warmingWalls = true
            NumberAnimation {
                target: content
                property: "opacity"
                from: 0
                to: 1
                duration: 450
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: win
                property: "reveal"
                from: 0
                to: 1
                duration: 520
                // Starts at moderate velocity (no ease-in dead zone where the
                // dot seems stuck, no Out-style explosion), settles gently.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.33, 0.15, 0.2, 1.0, 1.0, 1.0]
            }
        }

        SequentialAnimation {
            id: fadeOut
            ParallelAnimation {
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 0
                    duration: 320
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: win
                    property: "reveal"
                    to: 0
                    duration: 320
                    easing.type: Easing.InQuad
                }
            }
            // waitForJob flushes pending state writes before exiting
            ScriptAction {
                script: {
                    store.waitForJob();
                    settingsStore.waitForJob();
                    Qt.quit();
                }
            }
        }

        // ---------- content ----------
        Item {
            id: content
            anchors.fill: parent
            opacity: 0

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, cfg.dimOpacity)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: input.forceActiveFocus()
            }

            // Idle state: big clock + date. The outer gate holds the clock
            // back until the blur hole is large enough to accommodate it.
            Item {
                id: clockGate
                anchors.centerIn: parent
                width: clockView.width
                height: clockView.height
                visible: win.pane === "clock"
                onVisibleChanged: if (visible) fadeUp.restart()
                opacity: {
                    const fit = Math.hypot(width, height) + 60;
                    return Math.max(0, Math.min(1, (win.revealDiameter - fit * 0.8) / (fit * 0.5)));
                }

                Column {
                    id: clockView
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: root.fg
                        font { family: root.mono; pixelSize: root.fs(120); weight: Font.DemiBold; letterSpacing: 1 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                        color: root.muted
                        font { family: root.mono; pixelSize: root.fs(17); letterSpacing: 3; capitalization: Font.AllUppercase }
                    }

                    ParallelAnimation {
                        id: fadeUp
                        NumberAnimation { target: clockView; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { target: clockView; property: "anchors.verticalCenterOffset"; from: 10; to: 0; duration: 300; easing.type: Easing.OutCubic }
                    }
                }
            }

            // App drawer: paged grid of app tiles
            Item {
                id: drawer
                anchors.centerIn: parent
                width: cfg.appsCols * 174 + (cfg.appsCols - 1) * 24 + 52
                height: grid.height + 52
                opacity: 0.004
                visible: win.drawerOpen || win.warmingApps
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "apps")
                            drawerIn.restart();
                    }
                }

                ParallelAnimation {
                    id: drawerIn
                    NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: drawer; property: "scale"; from: 0.9; to: 1; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: drawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Grid {
                    id: grid
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    columns: cfg.appsCols
                    columnSpacing: 24
                    rowSpacing: 24

                    Repeater {
                        model: win.appPageSize

                        Item {
                            id: cell
                            required property int index
                            width: 174
                            height: 100

                            readonly property int appIndex: win.appPage * win.appPageSize + index
                            property var entry: win.matches[appIndex] ?? null
                            property var shownEntry: null
                            property bool filled: false
                            readonly property bool isSelected: entry !== null && win.selected === cell.appIndex

                            onEntryChanged: {
                                if (entry) {
                                    const isNew = !filled || !shownEntry || shownEntry.id !== entry.id;
                                    shownEntry = entry;
                                    filled = true;
                                    if (isNew) {
                                        springOut.stop();
                                        springIn.restart();
                                    }
                                } else if (filled) {
                                    // ghost: the old tile springs out in place
                                    filled = false;
                                    springIn.stop();
                                    springOut.restart();
                                }
                            }

                            Column {
                                id: wrap
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 8
                                opacity: 0

                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 76
                                    height: 76

                                    Rectangle {
                                        visible: cell.isSelected
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        radius: 23
                                        color: "transparent"
                                        border.width: 3
                                        border.color: Qt.alpha(root.accent, 0.33)
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: Qt.alpha(root.accent, cell.isSelected ? 0.2 : 0.11)
                                        border.width: 1
                                        border.color: cell.isSelected ? root.accent : Qt.alpha(root.accent, 0.33)

                                        Image {
                                            id: icon
                                            anchors.centerIn: parent
                                            width: 44
                                            height: 44
                                            sourceSize: Qt.size(88, 88)
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                            source: {
                                                const name = cell.shownEntry ? cell.shownEntry.icon : "";
                                                return name ? Quickshell.iconPath(name, true) : "";
                                            }
                                            visible: status === Image.Ready
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !icon.visible
                                            text: (cell.shownEntry ? cell.shownEntry.name : "").slice(0, 2).toUpperCase()
                                            color: root.accent
                                            font { family: root.mono; pixelSize: root.fs(16); weight: Font.Bold }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: cell.filled
                                            onClicked: win.launch(cell.entry)
                                        }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, 76)
                                    height: 16
                                    text: cell.shownEntry ? cell.shownEntry.name : ""
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }

                            SequentialAnimation {
                                id: springIn
                                PropertyAction { target: wrap; property: "opacity"; value: 0 }
                                PropertyAction { target: wrap; property: "scale"; value: 0.4 }
                                PropertyAction { target: wrap; property: "y"; value: 14 }
                                PauseAnimation { duration: win.staggering ? cell.index * 35 : 0 }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wrap; property: "y"; to: 0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: springOut
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: 1.08; duration: 80; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: wrap; property: "y"; to: -3; duration: 80; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: 0.4; duration: 320; easing.type: Easing.InQuad }
                                    NumberAnimation { target: wrap; property: "y"; to: 14; duration: 320; easing.type: Easing.InQuad }
                                    NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
                                }
                            }
                        }
                    }
                }
            }

            // Wallpaper selector
            Item {
                id: wallDrawer
                anchors.centerIn: parent
                width: cfg.wallsCols * 240 + (cfg.wallsCols - 1) * 24 + 52
                height: wallGrid.height + 52
                opacity: 0.004
                // during warm-up, show the pane only after all thumbnail
                // textures are uploaded, so its first frame reuses them
                visible: win.pane === "walls" || (win.warmingWalls && win.wallWarmTick > root.wallpapers.length)
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "walls")
                            wallIn.restart();
                    }
                }

                ParallelAnimation {
                    id: wallIn
                    NumberAnimation { target: wallDrawer; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: wallDrawer; property: "scale"; from: 0.9; to: 1; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: wallDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Grid {
                    id: wallGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    columns: cfg.wallsCols
                    columnSpacing: 24
                    rowSpacing: 24

                    Repeater {
                        model: win.wallPageSize

                        Item {
                            id: wallCell
                            required property int index
                            readonly property int wallIndex: win.wallPage * win.wallPageSize + index
                            readonly property var wall: win.wallMatches[wallIndex] ?? null
                            readonly property bool isSelected: wall !== null && win.wallSelected === wallIndex
                            width: 240
                            height: 159

                            visible: !win.warmingWalls || win.wallWarmTick > root.wallpapers.length + index + 1

                            property var shownWall: null
                            property bool filled: false
                            onWallChanged: {
                                if (wall) {
                                    const isNew = !filled || !shownWall || shownWall.path !== wall.path;
                                    shownWall = wall;
                                    filled = true;
                                    if (isNew) {
                                        wallSpringOut.stop();
                                        wallSpringIn.restart();
                                    }
                                } else if (filled) {
                                    filled = false;
                                    wallSpringIn.stop();
                                    wallSpringOut.restart();
                                }
                            }
                            // replay the spring when the selector opens: the
                            // cells were already filled while it was hidden
                            Connections {
                                target: win
                                function onPaneChanged() {
                                    if (win.pane === "walls" && wallCell.filled)
                                        wallSpringIn.restart();
                                }
                            }

                            Item {
                                id: wallWrap
                                width: 240
                                height: 159
                                opacity: 0

                                Rectangle {
                                    visible: wallCell.isSelected
                                    anchors.fill: thumb
                                    anchors.margins: -5
                                    radius: 19
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Qt.alpha(root.accent, 0.33)
                                }
                                ClippingRectangle {
                                    id: thumb
                                    width: 240
                                    height: 135
                                    radius: 14
                                    color: Qt.alpha(root.accent, 0.08)
                                    border.width: 1
                                    border.color: wallCell.isSelected ? root.accent : Qt.alpha(root.accent, 0.33)

                                    Image {
                                        anchors.fill: parent
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(480, 270)
                                        source: wallCell.shownWall ? "file://" + wallCell.shownWall.thumb : ""
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: wallCell.filled
                                        onClicked: win.applyWallpaper(wallCell.wall)
                                    }
                                }
                                Text {
                                    anchors.top: thumb.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, 220)
                                    height: 16
                                    text: wallCell.shownWall ? win.wallName(wallCell.shownWall) : ""
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }

                            SequentialAnimation {
                                id: wallSpringIn
                                PropertyAction { target: wallWrap; property: "opacity"; value: 0 }
                                PropertyAction { target: wallWrap; property: "scale"; value: 0.4 }
                                PropertyAction { target: wallWrap; property: "y"; value: 14 }
                                PauseAnimation { duration: win.staggering ? wallCell.index * 35 : 0 }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 1; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wallWrap; property: "y"; to: 0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: wallSpringOut
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 1.08; duration: 80; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: wallWrap; property: "y"; to: -3; duration: 80; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 0.4; duration: 320; easing.type: Easing.InQuad }
                                    NumberAnimation { target: wallWrap; property: "y"; to: 14; duration: 320; easing.type: Easing.InQuad }
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
                                }
                            }
                        }
                    }
                }
            }

            // Clipboard history (cliphist)
            Item {
                id: clipDrawer
                anchors.centerIn: parent
                width: 820
                height: clipCol.height + 52
                opacity: 0.004
                visible: win.pane === "clips"
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "clips")
                            clipIn.restart();
                    }
                }

                ParallelAnimation {
                    id: clipIn
                    NumberAnimation { target: clipDrawer; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: clipDrawer; property: "scale"; from: 0.9; to: 1; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: clipDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Column {
                    id: clipCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    spacing: 12

                    Text {
                        visible: !root.cliphistAvailable || root.clips.length === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.cliphistAvailable
                            ? "clipboard history is empty"
                            : "cliphist not found — sudo dnf install cliphist wl-clipboard"
                        color: root.muted
                        font { family: root.mono; pixelSize: root.fs(14) }
                    }

                    Repeater {
                        model: cfg.clipsRows

                        Item {
                            id: clipCell
                            required property int index
                            width: 768
                            height: 48

                            readonly property int clipIndex: win.clipPage * cfg.clipsRows + index
                            readonly property var clip: win.clipMatches[clipIndex] ?? null
                            readonly property bool isSelected: clip !== null && win.clipSelected === clipIndex

                            property var shownClip: null
                            property bool filled: false
                            onClipChanged: {
                                if (clip) {
                                    const isNew = !filled || !shownClip || shownClip.id !== clip.id;
                                    shownClip = clip;
                                    filled = true;
                                    if (isNew) {
                                        clipSpringOut.stop();
                                        clipSpringIn.restart();
                                    }
                                } else if (filled) {
                                    filled = false;
                                    clipSpringIn.stop();
                                    clipSpringOut.restart();
                                }
                            }
                            Connections {
                                target: win
                                function onPaneChanged() {
                                    if (win.pane === "clips" && clipCell.filled)
                                        clipSpringIn.restart();
                                }
                            }

                            Rectangle {
                                id: clipRow
                                anchors.fill: parent
                                radius: 12
                                opacity: 0
                                color: Qt.alpha(root.accent, clipCell.isSelected ? 0.2 : 0.08)
                                border.width: 1
                                border.color: clipCell.isSelected ? root.accent : Qt.alpha(root.accent, 0.25)

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    spacing: 14

                                    ClippingRectangle {
                                        visible: clipCell.shownClip !== null && clipCell.shownClip.image === true
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 60
                                        height: 34
                                        radius: 6
                                        color: Qt.alpha(root.accent, 0.08)

                                        Image {
                                            anchors.fill: parent
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize: Qt.size(120, 68)
                                            source: {
                                                const c = clipCell.shownClip;
                                                return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: clipCell.shownClip && clipCell.shownClip.image ? 640 : 730
                                        text: clipCell.shownClip ? clipCell.shownClip.preview : ""
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        color: root.fg
                                        font { family: root.mono; pixelSize: root.fs(14) }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: clipCell.filled
                                    onClicked: win.copyClip(clipCell.clip)
                                }
                            }

                            SequentialAnimation {
                                id: clipSpringIn
                                PropertyAction { target: clipRow; property: "opacity"; value: 0 }
                                PropertyAction { target: clipRow; property: "scale"; value: 0.7 }
                                PropertyAction { target: clipRow; property: "y"; value: 10 }
                                PauseAnimation { duration: win.staggering ? clipCell.index * 30 : 0 }
                                ParallelAnimation {
                                    NumberAnimation { target: clipRow; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: clipRow; property: "scale"; to: 1; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                    NumberAnimation { target: clipRow; property: "y"; to: 0; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                }
                            }
                            SequentialAnimation {
                                id: clipSpringOut
                                ParallelAnimation {
                                    NumberAnimation { target: clipRow; property: "scale"; to: 0.7; duration: 240; easing.type: Easing.InQuad }
                                    NumberAnimation { target: clipRow; property: "y"; to: 10; duration: 240; easing.type: Easing.InQuad }
                                    NumberAnimation { target: clipRow; property: "opacity"; to: 0; duration: 240; easing.type: Easing.InQuad }
                                }
                            }
                        }
                    }
                }
            }

            // Settings pane
            Item {
                id: settingsPane
                anchors.centerIn: parent
                width: 860
                height: settingsCol.height + 52
                opacity: 0.004
                visible: win.pane === "settings"
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "settings")
                            settingsIn.restart();
                    }
                }
                ParallelAnimation {
                    id: settingsIn
                    NumberAnimation { target: settingsPane; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: settingsPane; property: "scale"; from: 0.9; to: 1; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: settingsPane; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Column {
                    id: settingsCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    spacing: 14

                    Text {
                        text: "SETTINGS"
                        color: root.muted
                        font { family: root.mono; pixelSize: root.fs(13); letterSpacing: 3 }
                    }

                    Repeater {
                        model: [
                            { key: "appsGrid", label: "Apps grid" },
                            { key: "wallsGrid", label: "Wallpaper grid" },
                            { key: "clipsRows", label: "Clipboard rows" },
                            { key: "fontScale", label: "Font size" },
                            { key: "dimOpacity", label: "Opacity" },
                            { key: "iconTheme", label: "Icon theme" }
                        ]

                        Item {
                            id: srow
                            required property var modelData
                            width: 780
                            height: 34

                            SLabel {
                                anchors.left: parent.left
                                text: srow.modelData.label
                            }
                            Row {
                                anchors.right: parent.right
                                spacing: 8
                                height: parent.height
                                SBtn {
                                    label: "‹"
                                    onPressed: win.adjustSetting(srow.modelData.key, -1)
                                }
                                SValue {
                                    text: win.settingValue(srow.modelData.key)
                                    width: srow.modelData.key === "iconTheme" ? 260 : 90
                                }
                                SBtn {
                                    label: "›"
                                    onPressed: win.adjustSetting(srow.modelData.key, 1)
                                }
                            }
                        }
                    }

                    // color themes with palette previews
                    Item {
                        width: 780
                        height: 86

                        SLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: undefined
                            y: 6
                            text: "Color theme"
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 10

                            Repeater {
                                model: root.themes

                                Rectangle {
                                    id: themeCard
                                    required property var modelData
                                    readonly property var pal: modelData.id === "dynamic" ? root.dynTheme : modelData
                                    readonly property bool active: cfg.theme === modelData.id
                                    width: 88
                                    height: 86
                                    radius: 12
                                    color: Qt.alpha(root.accent, active ? 0.16 : 0.06)
                                    border.width: active ? 2 : 1
                                    border.color: active ? root.accent : Qt.alpha(root.accent, 0.25)

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Row {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 5
                                            Repeater {
                                                model: [themeCard.pal.accent, themeCard.pal.fg, themeCard.pal.muted]
                                                Rectangle {
                                                    required property var modelData
                                                    width: 18
                                                    height: 18
                                                    radius: 5
                                                    color: modelData
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, 0.15)
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: themeCard.modelData.name
                                            color: themeCard.active ? root.fg : root.muted
                                            font { family: root.mono; pixelSize: root.fs(12) }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            cfg.theme = themeCard.modelData.id;
                                            root.saveSettings();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // wallpaper path
                    Item {
                        width: 780
                        height: 38

                        SLabel {
                            anchors.left: parent.left
                            text: "Wallpaper path"
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 420
                            height: 34
                            radius: 8
                            color: Qt.alpha(root.accent, pathInput.activeFocus ? 0.16 : 0.08)
                            border.width: 1
                            border.color: pathInput.activeFocus ? root.accent : Qt.alpha(root.accent, 0.33)

                            TextInput {
                                id: pathInput
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                text: cfg.wallpaperDir
                                color: root.fg
                                clip: true
                                font { family: root.mono; pixelSize: root.fs(13) }
                                onEditingFinished: {
                                    if (text !== cfg.wallpaperDir) {
                                        cfg.wallpaperDir = text;
                                        root.saveSettings();
                                        root.rescanWallpapers();
                                    }
                                    input.forceActiveFocus();
                                }
                                Keys.onEscapePressed: input.forceActiveFocus()
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.IBeamCursor
                            }
                        }
                    }

                    // keybinds
                    Repeater {
                        model: [
                            { action: "cycle", label: "Cycle pages (Shift+ reverses)" },
                            { action: "launch", label: "Launch / apply" },
                            { action: "exit", label: "Exit" }
                        ]

                        Item {
                            id: bindRow
                            required property var modelData
                            width: 780
                            height: 34

                            SLabel {
                                anchors.left: parent.left
                                text: bindRow.modelData.label
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(110, bindText.implicitWidth + 26)
                                height: 30
                                radius: 8
                                color: Qt.alpha(root.accent, win.capturingBind === bindRow.modelData.action ? 0.3 : 0.11)
                                border.width: 1
                                border.color: win.capturingBind === bindRow.modelData.action ? root.accent : Qt.alpha(root.accent, 0.33)

                                Text {
                                    id: bindText
                                    anchors.centerIn: parent
                                    text: win.capturingBind === bindRow.modelData.action
                                        ? "press a key…"
                                        : (cfg.keybinds[bindRow.modelData.action] ?? "")
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        win.capturingBind = bindRow.modelData.action;
                                        input.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "icon theme applies on next launch (QS_ICON_THEME)"
                        color: Qt.alpha(root.muted, 0.7)
                        font { family: root.mono; pixelSize: root.fs(11) }
                    }
                }
            }

            // Settings button: pops up when hovering the bottom-right corner
            MouseArea {
                id: settingsHover
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 180
                height: 180
                hoverEnabled: true
                onClicked: win.setPane(win.pane === "settings" ? "clock" : "settings")

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 32
                    width: 56
                    height: 56
                    radius: 28
                    color: Qt.alpha(root.accent, settingsHover.containsMouse ? 0.2 : 0.11)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.33)
                    opacity: settingsHover.containsMouse || win.pane === "settings" ? 1 : 0
                    scale: settingsHover.containsMouse || win.pane === "settings" ? 1 : 0.5
                    Behavior on opacity {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }

                    Image {
                        id: settingsIcon
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        source: Quickshell.iconPath("preferences-system", true)
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !settingsIcon.visible
                        text: "⚙"
                        color: root.accent
                        font { pixelSize: root.fs(24) }
                    }
                }
            }
        }

        function cycleIconTheme(dir: int) {
            const list = [""].concat(root.iconThemes);
            let i = list.indexOf(cfg.iconTheme);
            if (i < 0)
                i = 0;
            cfg.iconTheme = list[((i + dir) % list.length + list.length) % list.length];
        }

        function settingValue(key: string): string {
            switch (key) {
            case "appsGrid": return cfg.appsCols + " × " + cfg.appsRows;
            case "wallsGrid": return cfg.wallsCols + " × " + cfg.wallsRows;
            case "clipsRows": return "" + cfg.clipsRows;
            case "fontScale": return Math.round(cfg.fontScale * 100) + "%";
            case "dimOpacity": return Math.round(cfg.dimOpacity * 100) + "%";
            case "iconTheme": return cfg.iconTheme || "system default";
            }
            return "";
        }
        function adjustSetting(key: string, dir: int) {
            switch (key) {
            case "appsGrid":
                // sweep through cols within each row count
                if (dir > 0) {
                    if (cfg.appsCols < 6) cfg.appsCols++;
                    else if (cfg.appsRows < 5) { cfg.appsRows++; cfg.appsCols = 3; }
                } else {
                    if (cfg.appsCols > 3) cfg.appsCols--;
                    else if (cfg.appsRows > 2) { cfg.appsRows--; cfg.appsCols = 6; }
                }
                break;
            case "wallsGrid":
                if (dir > 0) {
                    if (cfg.wallsCols < 4) cfg.wallsCols++;
                    else if (cfg.wallsRows < 4) { cfg.wallsRows++; cfg.wallsCols = 2; }
                } else {
                    if (cfg.wallsCols > 2) cfg.wallsCols--;
                    else if (cfg.wallsRows > 2) { cfg.wallsRows--; cfg.wallsCols = 4; }
                }
                break;
            case "clipsRows":
                cfg.clipsRows = Math.max(4, Math.min(12, cfg.clipsRows + dir));
                break;
            case "fontScale":
                cfg.fontScale = Math.max(0.7, Math.min(1.6, Math.round((cfg.fontScale + dir * 0.1) * 100) / 100));
                break;
            case "dimOpacity":
                cfg.dimOpacity = Math.max(0, Math.min(0.9, Math.round((cfg.dimOpacity + dir * 0.05) * 100) / 100));
                break;
            case "iconTheme":
                cycleIconTheme(dir);
                break;
            }
            root.saveSettings();
        }

        // Hidden input that captures all typing, mirroring the design's off-screen <input>
        TextInput {
            id: input
            width: 1
            height: 1
            opacity: 0
            focus: true

            // typing from the clock jumps straight into the app search
            onTextChanged: {
                if (text.length > 0 && win.pane === "clock")
                    win.pane = "apps";
            }

            Keys.onPressed: event => {
                // keybind capture (settings)
                if (win.capturingBind) {
                    const ks = win.keyName(event);
                    if (ks) {
                        win.setBind(win.capturingBind, ks);
                        win.capturingBind = "";
                    }
                    event.accepted = true;
                    return;
                }
                const ks = win.keyName(event);
                const kb = cfg.keybinds;
                if (ks === (kb.exit ?? "Escape")) {
                    win.exit();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab || ks === "Shift+" + (kb.cycle ?? "Tab")) {
                    win.cyclePane(-1);
                    event.accepted = true;
                } else if (ks === (kb.cycle ?? "Tab")) {
                    win.cyclePane(1);
                    event.accepted = true;
                } else if (ks === (kb.launch ?? "Return")) {
                    win.activate();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    win.navigate(1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    win.navigate(-1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    win.navigate(0, 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    win.navigate(0, -1);
                    event.accepted = true;
                }
            }
        }

        // Start the reveal only after the mapped window has actually rendered
        // a couple of frames. Animations are wall-clock based, so starting at
        // map time means first-frame latency eats the start of the animation
        // and the hole pops in already partly grown.
        property bool revealStarted: false
        // While warming, the drawer / wallpaper pane / image preloaders are
        // rendered at near-zero opacity so their scene graph nodes and
        // textures are built up front instead of stuttering the first open.
        // Apps warm before the reveal (typing can happen immediately); the
        // heavier wallpaper thumbnails warm after the reveal finishes.
        property bool warmingApps: false
        property bool warmingWalls: false
        FrameAnimation {
            id: firstFrames
            onTriggered: {
                if (currentFrame === 1) {
                    win.warmingApps = true;
                } else if (currentFrame >= 3) {
                    win.warmingApps = false;
                    fadeIn.restart();
                    stop();
                }
            }
        }
        // Spread the wallpaper warm-up over one thumbnail per frame: doing
        // all uploads in a single frame caused a ~110ms hitch right as the
        // reveal ended, mid-spring when the user had typed early.
        property int wallWarmTick: 0
        FrameAnimation {
            running: win.warmingWalls
            onTriggered: {
                win.wallWarmTick = currentFrame;
                // thumbnails first (one per frame), then the pane's cells
                // (one per frame — each ClippingRectangle is an offscreen
                // render target and costs a chunk of frame time to create)
                if (currentFrame > root.wallpapers.length + win.wallPageSize + 4)
                    win.warmingWalls = false;
            }
        }

        // Tile stagger applies when a pane opens, not on every keystroke —
        // re-staggering while filtering makes tiles blink out and pause.
        property bool staggering: false
        Timer {
            id: staggerTimer
            interval: 600
            onTriggered: win.staggering = false
        }
        onPaneChanged: {
            if (pane !== "clock") {
                staggering = true;
                staggerTimer.restart();
            }
        }
        function startReveal() {
            if (revealStarted || !backingWindowVisible)
                return;
            revealStarted = true;
            firstFrames.reset();
            firstFrames.start();
        }
        onBackingWindowVisibleChanged: startReveal()

        // Pre-decode app icons and wallpaper thumbnails while idle, so the
        // drawer's first appearance doesn't stall on cold image loads. The
        // sources/sourceSizes match the visible tiles exactly for cache hits.
        Item {
            visible: win.warmingApps
            opacity: 0.004
            Repeater {
                model: root.allApps
                Image {
                    required property var modelData
                    width: 1
                    height: 1
                    asynchronous: true
                    sourceSize: Qt.size(88, 88)
                    source: {
                        const name = modelData.icon;
                        return name ? Quickshell.iconPath(name, true) : "";
                    }
                }
            }
        }
        Item {
            visible: win.warmingWalls
            opacity: 0.004
            Repeater {
                model: root.wallpapers
                Image {
                    required property int index
                    required property var modelData
                    width: 1
                    height: 1
                    visible: win.wallWarmTick > index
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(480, 270)
                    source: "file://" + modelData.thumb
                }
            }
        }

        Component.onCompleted: {
            input.forceActiveFocus();
            startReveal();
        }
    }
}
