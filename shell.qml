import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property color accent: "#e8a24a"
    readonly property color fg: "#f3ede4"
    readonly property color muted: "#8a8378"
    readonly property string mono: "JetBrains Mono"
    readonly property int slotCount: 12

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

    // Wallpapers in ~/Pictures/wallpapers. Each line: path|thumb|blurred.
    // Reuses the existing conventions: thumbnails/<f> for grid previews, and
    // blurred/<f> or <stem>blurred.<ext> as the pre-blurred overview variant.
    property var wallpapers: []
    Process {
        running: true
        command: ["bash", "-c", `
            cd "$HOME/Pictures/wallpapers" || exit 0
            shopt -s nullglob nocaseglob
            for f in *.png *.jpg *.jpeg *.webp; do
                case "$f" in *blurred.*) continue ;; esac
                stem="\${f%.*}" ext="\${f##*.}" thumb="$f" blur=""
                [ -e "thumbnails/$f" ] && thumb="thumbnails/$f"
                [ -e "blurred/$f" ] && blur="blurred/$f"
                [ -e "\${stem}blurred.$ext" ] && blur="\${stem}blurred.$ext"
                printf '%s|%s|%s\\n' "$PWD/$f" "$PWD/$thumb" "\${blur:+$PWD/$blur}"
            done | sort`]
        stdout: StdioCollector {
            onStreamFinished: {
                const walls = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { path: p[0], thumb: p[1], blur: p[2] || "" };
                });
                root.wallpapers = walls;
                // Pre-generate missing thumbnails (a full 5K image standing
                // in as its own thumbnail costs ~100ms to decode+upload) and
                // blurred overview variants, in the background. They land in
                // thumbnails/ and blurred/ (the existing conventions), so the
                // next scan picks them up and applying a wallpaper never has
                // to blur synchronously.
                const needsWork = walls.some(w => !w.blur || w.thumb === w.path);
                if (needsWork) {
                    Quickshell.execDetached(["bash", "-c", `
                        cd "$HOME/Pictures/wallpapers" || exit 0
                        mkdir -p thumbnails blurred
                        for f in "$@"; do
                            b=$(basename "$f")
                            stem="\${b%.*}" ext="\${b##*.}"
                            [ -e "thumbnails/$b" ] || magick "$f" -resize 480x270^ -gravity center -extent 480x270 "thumbnails/$b"
                            [ -e "blurred/$b" ] || [ -e "\${stem}blurred.$ext" ] || magick "$f" -resize 1024x -blur 0x10 "blurred/$b"
                        done`, "_"].concat(walls.map(w => w.path)));
                }
            }
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
        // niri applies the region in buffer (physical) pixels, not
        // surface-local logical ones, so scale by the device pixel ratio —
        // otherwise the circle grows from 40%/40% and misses the right edge.
        // Screen-based, not window-based: at startup the window briefly
        // reports its pre-configure size (500x500) and a rounded-up DPR (2),
        // which would place the early reveal frames far off-center.
        property real reveal: 0
        readonly property real physW: screen ? screen.width * screen.devicePixelRatio : 0
        readonly property real physH: screen ? screen.height * screen.devicePixelRatio : 0
        // Clamped to 1px: an empty region reads as "no region set", which the
        // protocol treats as blur-the-whole-surface — a full-screen blur flash.
        readonly property int revealDiameter: Math.max(1, Math.ceil(Math.hypot(physW, physH) * reveal))
        BackgroundEffect.blurRegion: Region {
            shape: RegionShape.Ellipse
            x: (win.physW - win.revealDiameter) / 2
            y: (win.physH - win.revealDiameter) / 2
            width: win.revealDiameter
            height: win.revealDiameter
        }

        // browsing: drawer open with no query, showing the most-used apps.
        // wallMode: the wallpaper selector. Tab rotates clock -> apps -> walls.
        property bool browsing: false
        property bool wallMode: false
        readonly property bool drawerOpen: !wallMode && (browsing || input.text.trim().length > 0)

        property var matches: {
            if (wallMode)
                return [];
            const q = input.text.toLowerCase().trim();
            if (!q) {
                if (!browsing)
                    return [];
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
        readonly property int appPage: root.slotCount > 0 ? Math.floor(selected / root.slotCount) : 0
        readonly property int appPages: Math.max(1, Math.ceil(matches.length / root.slotCount))

        function move(delta: int) {
            const count = matches.length;
            if (!count)
                return;
            selected = ((selected + delta) % count + count) % count;
        }

        function launch(entry) {
            if (!entry)
                return;
            root.recordLaunch(entry);
            entry.execute();
            exit();
        }

        property int wallSelected: 0
        readonly property int wallCols: 3
        readonly property int wallRows: 3
        readonly property int wallPageSize: wallCols * wallRows
        readonly property int wallPage: wallPageSize > 0 ? Math.floor(wallSelected / wallPageSize) : 0
        readonly property int wallPages: Math.max(1, Math.ceil(wallMatches.length / wallPageSize))

        function wallName(wall): string {
            return wall.path.split("/").pop().replace(/\.[^.]+$/, "");
        }

        property var wallMatches: {
            const q = input.text.toLowerCase().trim();
            if (!q || !wallMode)
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
        onWallMatchesChanged: wallSelected = 0

        function wallMove(delta: int) {
            const count = wallMatches.length;
            if (!count)
                return;
            wallSelected = ((wallSelected + delta) % count + count) % count;
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
                    mkdir -p "$HOME/Pictures/wallpapers/blurred"
                    BLUR="$HOME/Pictures/wallpapers/blurred/$(basename "$1")"
                    [ -e "$BLUR" ] || magick "$1" -resize 1024x -blur 0x10 "$BLUR"
                fi
                awww img -n overview --transition-type fade --transition-duration 1 "$BLUR"
            `, "_", wall.path, wall.blur]);
            exit();
        }

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
            // waitForJob flushes any pending launch-count write before exiting
            ScriptAction {
                script: {
                    store.waitForJob();
                    Qt.quit();
                }
            }
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: 0

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, 0.4)
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
                visible: !win.drawerOpen && !win.wallMode
                onVisibleChanged: if (visible) fadeUp.restart()
                opacity: {
                    const fit = (Math.hypot(width, height) + 60) * win.devicePixelRatio;
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
                    font { family: root.mono; pixelSize: 120; weight: Font.DemiBold; letterSpacing: 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                    color: root.muted
                    font { family: root.mono; pixelSize: 17; letterSpacing: 3; capitalization: Font.AllUppercase }
                }

                ParallelAnimation {
                    id: fadeUp
                    NumberAnimation { target: clockView; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
                    NumberAnimation { target: clockView; property: "anchors.verticalCenterOffset"; from: 10; to: 0; duration: 300; easing.type: Easing.OutCubic }
                }
            }
            }

            // Results drawer: 4x3 grid of app tiles
            Item {
                id: drawer
                anchors.centerIn: parent
                width: 820
                height: grid.height + 84
                opacity: 0.004
                visible: win.drawerOpen || win.warmingApps
                Connections {
                    target: win
                    function onDrawerOpenChanged() {
                        if (win.drawerOpen)
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
                    columns: 4
                    columnSpacing: 24
                    rowSpacing: 24

                    Repeater {
                        model: root.slotCount

                        Item {
                            id: cell
                            required property int index
                            width: 174
                            height: 100

                            readonly property int appIndex: win.appPage * root.slotCount + index
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
                                    // ghost: keep the old tile visible while it springs out in place
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
                                        id: tile
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
                                            font { family: root.mono; pixelSize: 16; weight: Font.Bold }
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
                                    font { family: root.mono; pixelSize: 13 }
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

                Text {
                    visible: win.appPages > 1
                    anchors.top: grid.bottom
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (win.appPage + 1) + " / " + win.appPages
                    color: root.muted
                    font { family: root.mono; pixelSize: 13; letterSpacing: 2 }
                }
            }
            // Wallpaper selector: Tab rotates here from the app drawer
            Item {
                id: wallDrawer
                anchors.centerIn: parent
                width: 820
                height: wallGrid.height + 84
                opacity: 0.004
                // during warm-up, show the pane only after all thumbnail
                // textures are uploaded, so its first frame reuses them
                visible: win.wallMode || (win.warmingWalls && win.wallWarmTick > root.wallpapers.length)
                Connections {
                    target: win
                    function onWallModeChanged() {
                        if (win.wallMode)
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
                    columns: win.wallCols
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
                                function onWallModeChanged() {
                                    if (win.wallMode && wallCell.filled)
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
                                    color: wallCell.isSelected ? root.fg : root.muted
                                    font { family: root.mono; pixelSize: 13 }
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

                Text {
                    visible: win.wallPages > 1
                    anchors.top: wallGrid.bottom
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (win.wallPage + 1) + " / " + win.wallPages
                    color: root.muted
                    font { family: root.mono; pixelSize: 13; letterSpacing: 2 }
                }
            }

            // Settings button: pops up when hovering the bottom-right corner
            // (no functionality yet)
            MouseArea {
                id: settingsHover
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 180
                height: 180
                hoverEnabled: true

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
                    opacity: settingsHover.containsMouse ? 1 : 0
                    scale: settingsHover.containsMouse ? 1 : 0.5
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
                        font { pixelSize: 24 }
                    }
                }
            }
        }

        // Hidden input that captures all typing, mirroring the design's off-screen <input>
        TextInput {
            id: input
            width: 1
            height: 1
            opacity: 0
            focus: true

            // once the user starts typing, an emptied query shows the
            // most-used apps rather than falling back to the clock
            onTextChanged: {
                if (text.length > 0 && !win.wallMode)
                    win.browsing = true;
            }

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    win.exit();
                    event.accepted = true;
                    break;
                case Qt.Key_Tab:
                    // cycle: clock -> apps -> wallpapers -> clock
                    input.text = "";
                    if (win.wallMode) {
                        win.wallMode = false;
                        win.browsing = false;
                    } else if (win.drawerOpen) {
                        win.wallMode = true;
                    } else {
                        win.browsing = true;
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Right:
                    win.wallMode ? win.wallMove(1) : win.move(1);
                    event.accepted = true;
                    break;
                case Qt.Key_Left:
                    win.wallMode ? win.wallMove(-1) : win.move(-1);
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    win.wallMode ? win.wallMove(win.wallCols) : win.move(4);
                    event.accepted = true;
                    break;
                case Qt.Key_Up:
                    win.wallMode ? win.wallMove(-win.wallCols) : win.move(-4);
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (win.wallMode)
                        win.applyWallpaper(win.wallMatches[win.wallSelected] ?? null);
                    else if (win.drawerOpen)
                        win.launch(win.matches.length ? win.matches[win.selected] : null);
                    else
                        win.browsing = true;
                    event.accepted = true;
                    break;
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
        onDrawerOpenChanged: {
            if (drawerOpen) {
                staggering = true;
                staggerTimer.restart();
            }
        }
        onWallModeChanged: {
            if (wallMode) {
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
