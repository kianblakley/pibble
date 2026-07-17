import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications

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

    component ThemeRow: Item {
        id: tr
        property string cfgKey: "theme"
        property string sub: ""
        readonly property bool fly: cfgKey === "flyTheme"
        width: 780
        height: 86 + (sub ? trSub.implicitHeight + 6 : 0)
        readonly property string current: fly ? cfg.flyTheme : cfg.theme
        readonly property bool light: fly ? cfg.flyLight : cfg.themeLight
        function setVal(v: string) {
            if (fly)
                cfg.flyTheme = v;
            else
                cfg.theme = v;
            root.saveSettings();
        }

        SLabel {
            anchors.left: parent.left
            anchors.verticalCenter: undefined
            y: 6
            text: tr.fly ? "Flyouts" : "Launcher"
        }
        Row {
            anchors.right: parent.right
            height: 28
            spacing: 8

            // light variant of whichever scheme is active (sun = light)
            SBtn {
                label: tr.light ? "\u2600" : "\u263e"
                onPressed: {
                    if (tr.fly)
                        cfg.flyLight = !cfg.flyLight;
                    else
                        cfg.themeLight = !cfg.themeLight;
                    root.saveSettings();
                }
            }
            SReset {
                key: tr.cfgKey
            }
        }
        SSub {
            id: trSub
            visible: tr.sub !== ""
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: tr.sub
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 70
            // the flyouts row carries one extra card (dynamic): narrow the
            // cards so the row clears the label on the left
            spacing: tr.fly ? 6 : 8

            Repeater {
                model: root.themes.concat(
                    tr.fly ? [{ id: "dynamic", name: "Dynamic", accent: "", fg: "", muted: "" }] : [],
                    [{ id: "custom", name: "Custom", accent: "", fg: "", muted: "" }])

                Rectangle {
                    id: trCard
                    required property var modelData
                    readonly property var pal: modelData.id === "matugen" ? root.dynTheme
                        : modelData.id === "custom" ? root.customPal()
                        : modelData.id === "dynamic" ? ({ accent: root.launcherBase.accent, fg: "#f2f0ee", muted: "#908c87" })
                        : modelData
                    readonly property bool active: tr.current === modelData.id
                    width: tr.fly ? 72 : 80
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
                                model: [trCard.pal.accent, trCard.pal.fg, trCard.pal.muted]
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
                            text: trCard.modelData.name
                            color: trCard.active ? root.fg : root.muted
                            font { family: root.mono; pixelSize: root.fs(12) }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: tr.setVal(trCard.modelData.id)
                    }
                }
            }
        }
    }

    // muted helper line rendered directly beneath the row it explains
    component SSub: Text {
        color: Qt.alpha(root.muted, 0.7)
        font { family: root.mono; pixelSize: root.fs(11) }
    }
    component SettingRow: Item {
        id: sr
        property string key
        property string label
        property string sub: ""
        property int valueWidth: 90
        width: 780
        height: 34 + (sub ? srSub.implicitHeight + 2 : 0)
        Item {
            id: srMain
            width: parent.width
            height: 34
            SLabel {
                anchors.left: parent.left
                text: sr.label
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                height: parent.height
                SBtn {
                    label: "‹"
                    onPressed: win.adjustSetting(sr.key, -1)
                }
                SValue {
                    text: win.settingValue(sr.key)
                    width: sr.valueWidth
                }
                SBtn {
                    label: "›"
                    onPressed: win.adjustSetting(sr.key, 1)
                }
                SReset {
                    key: sr.key
                }
            }
        }
        SSub {
            id: srSub
            visible: sr.sub !== ""
            anchors.top: srMain.bottom
            anchors.topMargin: 2
            text: sr.sub
        }
    }

    readonly property string defaultWallCommand: 'awww img -n workspaces --transition-type fade --transition-duration 1 "$WALL" && awww img -n overview --transition-type fade --transition-duration 1 "$BLUR"'

    component SReset: Rectangle {
        id: sreset
        property string key
        width: 24
        height: 24
        radius: 12
        color: "transparent"
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            text: "↺"
            color: resetArea.containsMouse ? root.fg : root.muted
            font.pixelSize: root.fs(13)
        }
        MouseArea {
            id: resetArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.resetSetting(sreset.key)
        }
    }

    // ---------- settings ----------
    FileView {
        id: settingsStore
        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false
        // pick up hand edits to settings.json live; without this the daemon
        // keeps its stale in-memory copy and silently overwrites the file on
        // its next save
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.healSettings()

        JsonAdapter {
            id: cfg
            property int appsCols: 4
            property int appsRows: 3
            property int wallsCols: 3
            property int wallsRows: 3
            property int clipsCols: 3
            property int clipsRows: 3
            property int clipsMax: 60
            property var pages: ({ clock: true, apps: true, walls: true, clips: true })
            // cycle order of the pages (drag the chips in settings to change)
            property var pageOrder: ["clock", "apps", "walls", "clips"]
            property string animStyle: "wave"
            property real fontScale: 1.0
            property string fontFamily: ""
            property string iconTheme: ""
            property string theme: "amber"
            property string wallpaperDir: "~/Pictures/wallpapers"
            // command run when a wallpaper is chosen; $WALL is the image,
            // $BLUR the blurred variant (only generated if referenced)
            property string wallCommand: root.defaultWallCommand
            property real dimOpacity: 0.4
            property string revealOrigin: "center"
            property var keybinds: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S", power: "Ctrl+P" })
            // flyouts (volume + notification OSDs)
            property string flyTheme: "amber"
            property string flyFontFamily: ""
            property var flyouts: ({ volume: true, notifs: true })
            property real volWidth: 340
            property string volAnim: "slide"
            // volume OSD content style: pill (a level bar) or one of three
            // equalizer visualizers (mirror / spectrum / flicker)
            property string volStyle: "pill"
            // numeric volume % readout on the OSD
            property bool volShowPercent: true
            property int volTimeout: 1500
            property int notifTimeout: 5000
            property real notifFontScale: 1.0
            // one notification at a time (queue across apps, replace within
            // an app): "bubble" = tinted circle + card, "pill" = card only
            property string notifStyle: "bubble"
            // legacy: folded into flyTheme by healSettings; kept so old
            // configs can still be read for the one-time migration
            property string notifTheme: ""
            // palette behind the "custom" scheme (editable in the colors tab)
            property var customTheme: ({ accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" })
            // per-scope light variant of the active scheme (sun/moon toggle)
            property bool themeLight: false
            property bool flyLight: false
        }
    }
    function saveSettings() {
        settingsStore.writeAdapter();
    }

    // ---------- theme ----------
    // Named schemes plus two resolved ones: "matugen" samples the current
    // wallpaper, "custom" is the user-defined palette from the colors tab.
    // The flyouts additionally accept "dynamic" (notification icon tint).
    readonly property var themes: [
        { id: "amber", name: "Amber", accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" },
        { id: "frost", name: "Frost", accent: "#7ab8e0", fg: "#e6eef4", muted: "#83919c" },
        { id: "moss",  name: "Moss",  accent: "#a3c76a", fg: "#eef3e4", muted: "#8d9378" },
        { id: "rose",  name: "Rose",  accent: "#e07a9a", fg: "#f4e8ec", muted: "#9c8389" },
        { id: "mono",  name: "Mono",  accent: "#cfcfcf", fg: "#f0f0f0", muted: "#8a8a8a" },
        { id: "matugen", name: "Matugen", accent: "", fg: "", muted: "" }
    ]
    // filled in from matugen (current wallpaper) at startup
    property var dynTheme: ({ accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" })
    function customPal() {
        const c = cfg.customTheme ?? {};
        return { accent: c.accent || "#e8a24a", fg: c.fg || "#f3ede4", muted: c.muted || "#8a8378" };
    }
    // light variant of a scheme: same accent, ink flips dark (the surface
    // colors flip via root.surface / root.flySurface)
    function applyMode(p, light) {
        return light ? { accent: p.accent, fg: "#26221c", muted: "#6d665c" } : p;
    }
    readonly property var launcherBase: cfg.theme === "matugen" ? dynTheme
        : cfg.theme === "custom" ? customPal()
        : (themes.find(t => t.id === cfg.theme) ?? themes[0])
    readonly property var activeTheme: applyMode(launcherBase, cfg.themeLight)
    readonly property color accent: activeTheme.accent
    readonly property color fg: activeTheme.fg
    readonly property color muted: activeTheme.muted
    // backdrop the launcher dims the screen with
    readonly property color surface: cfg.themeLight ? "#ece7df" : "#0a0908"
    readonly property string mono: cfg.fontFamily || "JetBrains Mono"

    // resolve a scheme id to its raw palette; unknown ids (the flyouts'
    // "dynamic") fall back to the launcher's scheme
    function themeColors(sel) {
        if (sel === "matugen")
            return dynTheme;
        if (sel === "custom")
            return customPal();
        return themes.find(t => t.id === sel) ?? launcherBase;
    }
    readonly property var flyTh: applyMode(themeColors(cfg.flyTheme), cfg.flyLight)
    readonly property string flyMono: cfg.flyFontFamily || mono
    // flyTheme "dynamic": near-black card, bubble tinted from the app icon
    readonly property bool notifIconTint: cfg.flyTheme === "dynamic"
    readonly property var notifTh: notifIconTint
        ? applyMode({ accent: flyTh.accent, fg: "#f2f0ee", muted: "#908c87" }, cfg.flyLight)
        : flyTh
    // card surface behind both flyouts
    readonly property color flySurface: cfg.flyLight ? "#f3efe8" : "#0c0c10"
    function flyoutOn(name: string): bool {
        return (cfg.flyouts ?? {})[name] !== false;
    }
    // icon-name → displayable URL; senders (and .desktop Icon= entries)
    // sometimes resolve the icon themselves, so paths and urls pass through
    function iconUrl(name: string): string {
        if (!name)
            return "";
        if (name.startsWith("file://"))
            return name;
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, true);
    }
    // notification glyph classifier, shared by the stack card and the flyout
    // bubble (the icon name may arrive resolved as a path, so match loosely)
    function notifGlyph(icon: string, summary: string): string {
        const sl = summary.toLowerCase();
        return icon.includes("error") || sl.includes("fail") || sl.includes("not found") ? "!"
            : icon.includes("copy") || sl.includes("copied") ? "⧉" : "✱";
    }

    function fs(px: int): int {
        return Math.round(px * cfg.fontScale);
    }

    // internal errors surface as regular notifications (we are the server)
    function notifyError(summary: string, body: string) {
        Quickshell.execDetached(["notify-send", "-a", "launcher", "-i", "dialog-error", summary, body]);
    }

    function humanBytes(n: int): string {
        if (n < 1024)
            return n + " B";
        if (n < 1048576)
            return (n / 1024).toFixed(1) + " KiB";
        return (n / 1048576).toFixed(1) + " MiB";
    }

    // heal out-of-range / retired settings values. Hooked to the store's
    // loaded signal (not Component.onCompleted) so it also covers hot
    // reloads and hand edits picked up by the file watcher.
    function healSettings() {
        // clamp out-of-range clip rows (old list-style pane stored large
        // values; the grid renders 2–4 rows) — clamp, don't reset, so a
        // hand-edited value degrades to the nearest legal one
        if (cfg.clipsRows > 4 || cfg.clipsRows < 2) {
            cfg.clipsRows = Math.max(2, Math.min(4, cfg.clipsRows));
            saveSettings();
        }
        // One-time migrations, keyed strictly on values only old configs
        // can contain — every branch must be a no-op on a fresh or healed
        // config, because this also runs if a load ever surfaces adapter
        // defaults (an unconditional save here once clobbered the file).
        if (cfg.theme === "dynamic") {
            cfg.theme = "matugen"; // renamed
            saveSettings();
        }
        // pre-colors-tab configs always carry a non-empty notifTheme; fold
        // it into the flyout scheme ("default" = icon tint = new "dynamic";
        // flyTheme's own old "dynamic" meant matugen)
        if (cfg.notifTheme) {
            cfg.flyTheme = cfg.notifTheme === "default" ? "dynamic"
                : cfg.notifTheme === "matugen" ? "matugen"
                : cfg.notifTheme;
            cfg.notifTheme = "";
            saveSettings();
        }
        // the retired equalizer visualizers collapse into the sine wave
        if (["mirror", "spectrum", "flicker"].includes(cfg.volStyle)) {
            cfg.volStyle = "sine";
            saveSettings();
        }
        // "flyout" was renamed "bubble"; the retired stack style folds in too
        if (cfg.notifStyle === "flyout" || cfg.notifStyle === "stack") {
            cfg.notifStyle = "bubble";
            saveSettings();
        }
        // the "follow" flyout theme option was removed; pin to the launcher
        // theme it was following at the time
        if (cfg.flyTheme === "follow") {
            cfg.flyTheme = root.themes.some(t => t.id === cfg.theme) ? cfg.theme : "amber";
            saveSettings();
        }
    }
    Component.onCompleted: healSettings()

    Process {
        id: matugenProc
        // Needed at startup only for the dynamic theme; otherwise deferred
        // until the settings pane wants the preview — its output triggers a
        // theme-color rebind of every tile, which would hitch the intro.
        running: cfg.theme === "matugen"
        // a refresh requested while a run was in flight; honoured on exit so
        // the palette still catches up with a just-applied wallpaper
        property bool rerun: false
        onRunningChanged: {
            if (!running && rerun) {
                rerun = false;
                Qt.callLater(() => running = true);
            }
        }
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            img=$(awww query -n workspaces 2>/dev/null | sed -n 's/.*displaying: image: //p' | head -1)
            [ -n "$img" ] || exit 0
            matugen image "$img" --json hex --dry-run --prefer saturation 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                // empty output is benign (awww not up yet at login, no
                // wallpaper set, or a run torn down early): keep the last
                // palette silently instead of raising a false alarm
                if (!text.trim())
                    return;
                try {
                    const c = JSON.parse(text).colors;
                    root.dynTheme = {
                        accent: c.primary.dark.color,
                        fg: c.on_surface.dark.color,
                        muted: c.outline.dark.color
                    };
                } catch (e) {
                    if (cfg.theme === "matugen")
                        root.notifyError("Matugen theme failed", "matugen returned no palette for the current wallpaper");
                }
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

    // The shell runs as a persistent daemon; the launcher window is toggled
    // over IPC: qs -p <repo> ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (win.shown && !win.exiting)
                win.exit();
            else
                win.open();
        }
        // "show" would collide with the `qs ipc show` CLI subcommand
        function open(): void {
            if (!win.shown || win.exiting)
                win.open();
        }
        function close(): void {
            if (win.shown)
                win.exit();
        }
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
    property string lastMissingDir: ""
    function rescanWallpapers() {
        wallScan.running = false;
        wallScan.running = true;
    }
    Process {
        id: wallScan
        running: true
        command: ["bash", "-c", `
            cd "$1" || { echo NODIR; exit 0; }
            shopt -s nullglob nocaseglob
            for f in *.png *.jpg *.jpeg *.webp; do
                case "$f" in *blurred.*) continue ;; esac
                stem="\${f%.*}" ext="\${f##*.}" thumb="$f" blur=""
                # only trust caches newer than the source image
                [ "thumbnails/$f" -nt "$f" ] && thumb="thumbnails/$f"
                [ "blurred/$f" -nt "$f" ] && blur="blurred/$f"
                [ -e "\${stem}blurred.$ext" ] && blur="\${stem}blurred.$ext"
                printf '%s|%s|%s\\n' "$PWD/$f" "$PWD/$thumb" "\${blur:+$PWD/$blur}"
            done | sort`, "_", root.wallDir]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NODIR") {
                    root.wallpapers = [];
                    if (root.lastMissingDir !== root.wallDir) {
                        root.lastMissingDir = root.wallDir;
                        root.notifyError("Wallpaper folder not found", root.wallDir);
                    }
                    return;
                }
                root.lastMissingDir = "";
                const walls = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { path: p[0], thumb: p[1], blur: p[2] || "" };
                });
                root.wallpapers = walls;
                // Generate missing thumbnails (a full 5K image standing in as
                // its own thumbnail costs ~100ms to decode+upload) and blurred
                // overview variants in the background; the next scan picks
                // them up and applying never has to blur synchronously.
                const wantBlur = cfg.wallCommand.includes("$BLUR");
                const needsWork = walls.some(w => (wantBlur && !w.blur) || w.thumb === w.path);
                if (needsWork) {
                    Quickshell.execDetached(["bash", "-c", `
                        dir="$1" gb="$2"; shift 2
                        cd "$dir" || exit 0
                        mkdir -p thumbnails
                        [ "$gb" = "1" ] && mkdir -p blurred
                        for f in "$@"; do
                            b=$(basename "$f")
                            stem="\${b%.*}" ext="\${b##*.}"
                            [ "thumbnails/$b" -nt "$f" ] || magick "$f" -resize 480x270^ -gravity center -extent 480x270 "thumbnails/$b"
                            if [ "$gb" = "1" ]; then
                                [ "blurred/$b" -nt "$f" ] || [ -e "\${stem}blurred.$ext" ] || magick "$f" -resize 1024x -blur 0x10 "blurred/$b"
                            fi
                        done`, "_", root.wallDir, wantBlur ? "1" : "0"].concat(walls.map(w => w.path)));
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
        running: false // started after the intro finishes
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
            command -v cliphist >/dev/null || { echo NOCLIPHIST; exit 0; }
            cliphist list | head -n "$1" | while IFS=$'\t' read -r id preview; do
                n=$(cliphist decode "$id" 2>/dev/null | wc -c)
                printf '%s\t%s\t%s\n' "$id" "$n" "$preview"
            done`, "_", String(cfg.clipsMax)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOCLIPHIST") {
                    root.cliphistAvailable = false;
                    return;
                }
                root.clips = text.split("\n").filter(l => l.trim()).map(l => {
                    const t1 = l.indexOf("\t");
                    const t2 = l.indexOf("\t", t1 + 1);
                    const id = l.slice(0, t1);
                    const bytes = parseInt(l.slice(t1 + 1, t2)) || 0;
                    const preview = l.slice(t2 + 1);
                    const m = preview.match(/^\[\[ binary data ([0-9.]+ \w+) (\w+) (\d+x\d+)/);
                    return m
                        ? { id, bytes, image: true, size: m[1], kind: m[2], dims: m[3], preview: m[2] + " image  " + m[3] + "  " + m[1], thumb: "" }
                        : { id, bytes, image: false, preview: preview.trim() };
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

    property bool scansStarted: false

    // ---------- fonts ----------
    property var fontFamilies: []
    Process {
        id: fontScan
        running: false // started after the intro finishes
        command: ["bash", "-c", "fc-list :spacing=mono family | sed 's/,.*//' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.fontFamilies = text.split("\n").filter(l => l.trim())
        }
    }

    // ---------- icon themes ----------
    property var iconThemes: []
    Process {
        id: iconThemeScan
        running: false // started after the intro finishes
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

        property bool shown: false
        visible: shown

        function open() {
            fadeOut.stop(); // reopening mid-dismiss is allowed
            resetState();
            shown = true;
            input.forceActiveFocus();
            // fresh data per open: the clipboard and wallpaper folder change
            // between opens, and a dynamic theme follows the wallpaper
            clipScan.running = false;
            clipScan.running = true;
            root.rescanWallpapers();
            // refresh the dynamic palette, but never kill a run already in
            // flight — a killed run surfaces as truncated JSON, which used to
            // raise a spurious "Dynamic theme failed" notification. A refresh
            // that lands mid-run is queued instead of dropped, so the palette
            // can't go stale on the wallpaper the busy run never saw.
            if (cfg.theme === "matugen") {
                if (matugenProc.running)
                    matugenProc.rerun = true;
                else
                    matugenProc.running = true;
            }
        }

        function resetState() {
            exiting = false;
            revealStarted = false;
            reveal = 0;
            content.opacity = 0;
            warmingApps = false;
            warmingWalls = false;
            wallWarmTick = 0;
            expandedClip = null;
            capturingBind = "";
            input.text = "";
            pane = homePane();
            paneBeforeSettings = homePane();
            settingsTab = "general";
            selected = 0;
            wallSelected = 0;
            clipSelected = 0;
            powerArmed = false;
            powerDragging = false;
            powerRaw = 0;
            // panes keep the opacity their last entry animation ended at;
            // reset them or the warm-up pass flashes them fully visible
            drawer.opacity = 0.004;
            wallDrawer.opacity = 0.004;
            clipDrawer.opacity = 0.004;
            settingsPane.opacity = 0.004;
        }

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
        readonly property var originFrac: {
            switch (cfg.revealOrigin) {
            case "top-left": return [0, 0];
            case "top-right": return [1, 0];
            case "bottom-left": return [0, 1];
            case "bottom-right": return [1, 1];
            default: return [0.5, 0.5];
            }
        }
        readonly property real originX: originFrac[0] * revW
        readonly property real originY: originFrac[1] * revH
        // radius needed to cover the farthest screen corner from the origin
        readonly property real maxRevealRadius: Math.max(
            Math.hypot(originX, originY),
            Math.hypot(revW - originX, originY),
            Math.hypot(originX, revH - originY),
            Math.hypot(revW - originX, revH - originY))
        // Clamped to 1px: an empty region reads as "no region set", which the
        // protocol treats as blur-the-whole-surface — a full-screen blur flash.
        readonly property int revealDiameter: Math.max(1, Math.ceil(2 * maxRevealRadius * reveal))
        BackgroundEffect.blurRegion: Region {
            shape: RegionShape.Ellipse
            x: win.originX - win.revealDiameter / 2
            y: win.originY - win.revealDiameter / 2
            width: win.revealDiameter
            height: win.revealDiameter
        }

        // ---------- pane state ----------
        // Tab cycles the enabled panes; the settings pane sits outside the
        // cycle (opened via the corner button or Ctrl+S).
        property string pane: "clock"
        // cycle order comes from settings (drag the page chips to reorder);
        // healed so all four pages are always present exactly once
        readonly property var paneOrder: {
            const def = ["clock", "apps", "walls", "clips"];
            const o = (Array.isArray(cfg.pageOrder) ? cfg.pageOrder : []).filter(p => def.includes(p));
            for (const d of def)
                if (!o.includes(d))
                    o.push(d);
            return o;
        }
        function movePage(p: string, to: int) {
            const o = paneOrder.filter(x => x !== p);
            o.splice(Math.max(0, Math.min(o.length, to)), 0, p);
            cfg.pageOrder = o;
        }
        readonly property var activePanes: {
            const pages = cfg.pages ?? {};
            const list = paneOrder.filter(p => pages[p] !== false);
            return list.length ? list : ["clock"];
        }
        function homePane(): string {
            return activePanes[0];
        }
        readonly property bool drawerOpen: pane === "apps"

        function setPane(p: string) {
            input.text = "";
            capturingBind = "";
            expandedClip = null;
            pane = (p === "settings" || activePanes.includes(p)) ? p : homePane();
        }
        // settings remembers where it was opened from
        property string paneBeforeSettings: "clock"
        property string settingsTab: "general"
        function toggleSettings() {
            if (pane === "settings") {
                setPane(paneBeforeSettings);
            } else {
                paneBeforeSettings = pane;
                setPane("settings");
            }
        }
        // ---------- swipe-to-power ----------
        // Dragging down on empty space pulls the pane content down (rubber
        // band) and reveals a ring that strokes itself closed as you drag,
        // like a swipe-to-refresh. Releasing with the ring complete (or the
        // power keybind) arms the "power off?" prompt; Enter then powers
        // off, anything else (Escape, a click, another key) lets go.
        property bool powerDragging: false
        property real powerGrabY: 0
        property real powerRaw: 0 // raw downward drag distance (finger travel)
        property bool powerArmed: false
        readonly property real powerThreshold: 300
        readonly property real powerProgress: Math.min(1, powerRaw / powerThreshold)
        // content shift lags the finger with increasing resistance
        readonly property real powerPull: 170 * (1 - Math.exp(-powerRaw / 260))
        Behavior on powerRaw {
            enabled: !win.powerDragging
            NumberAnimation { duration: win.ad(320); easing.type: Easing.OutCubic }
        }
        Timer {
            // a forgotten armed prompt must not lie in wait to turn the next
            // launch Return into a poweroff: let go on its own after a beat
            interval: 6000
            running: win.powerArmed && !win.powerDragging
            onTriggered: win.disarmPower()
        }
        function disarmPower() {
            powerArmed = false;
            powerRaw = 0;
        }
        // the power keybind plays the pull animation (the powerRaw Behavior
        // animates the ride down) straight into the armed pose: Enter powers
        // off, anything else lets go — same as completing the drag by hand
        function playPower() {
            powerArmed = true;
            powerRaw = powerThreshold;
        }
        function powerOff() {
            Quickshell.execDetached(["systemctl", "poweroff"]);
            exit();
        }
        function cyclePane(dir: int) {
            // inside settings the cycle keybinds walk the settings tabs
            if (pane === "settings") {
                const tabs = ["general", "flyouts", "colors"];
                settingsTab = tabs[((tabs.indexOf(settingsTab) + dir) % tabs.length + tabs.length) % tabs.length];
                return;
            }
            let i = activePanes.indexOf(pane);
            if (i < 0)
                i = 0;
            setPane(activePanes[((i + dir) % activePanes.length + activePanes.length) % activePanes.length]);
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
        readonly property int clipRowsC: Math.max(2, Math.min(4, cfg.clipsRows))
        readonly property int clipPageSize: cfg.clipsCols * clipRowsC
        readonly property int clipPage: clipPageSize > 0 ? Math.floor(clipSelected / clipPageSize) : 0

        // ---------- navigation ----------
        // Horizontal: previous/next item, wrapping. Vertical: down a row
        // within the column; at the bottom of a column, hop to the top of the
        // next column (next page after the last column), and mirrored for up.
        function hMove(sel: int, count: int, dir: int): int {
            if (!count)
                return 0;
            return ((sel + dir) % count + count) % count;
        }
        // Down walks the entire column — through every page — before hopping
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
                selected = dy !== 0
                    ? vMove(selected, matches.length, cfg.appsCols, cfg.appsRows, dy)
                    : hMove(selected, matches.length, dx);
            } else if (pane === "walls") {
                wallSelected = dy !== 0
                    ? vMove(wallSelected, wallMatches.length, cfg.wallsCols, cfg.wallsRows, dy)
                    : hMove(wallSelected, wallMatches.length, dx);
            } else if (pane === "clips") {
                clipSelected = dy !== 0
                    ? vMove(clipSelected, clipMatches.length, cfg.clipsCols, clipRowsC, dy)
                    : hMove(clipSelected, clipMatches.length, dx);
            }
        }

        // ---------- actions ----------
        // Launch through gtk-launch (GLib): quickshell's own Exec parser
        // follows the desktop-entry spec strictly, where single quotes are
        // not quoting characters — entries like `Exec=kitty bash -lc '...'`
        // get split mid-quote and crash on startup. GLib parses shell-style
        // (like every GTK-based launcher), and also honors Path= and
        // DBusActivatable. Falls back to the entry's own execute() if
        // gtk-launch can't find the id.
        property var launchEntry: null
        Process {
            id: appLaunch
            onExited: exitCode => {
                if (exitCode !== 0 && win.launchEntry)
                    win.launchEntry.execute();
                win.launchEntry = null;
            }
        }
        function launch(entry) {
            if (!entry)
                return;
            root.recordLaunch(entry);
            launchEntry = entry;
            // The launched app inherits gtk-launch's stdio, i.e. this Process's
            // pipes — which close once gtk-launch exits, so chatty apps
            // (flatpaks especially) would SIGPIPE on their next log line and
            // die seconds after launch. Point stdio at /dev/null and give the
            // app its own session; setsid -w keeps gtk-launch's exit code for
            // the fallback below.
            appLaunch.command = ["bash", "-c", 'command -v gtk-launch >/dev/null || exit 42; setsid -w gtk-launch "$1" >/dev/null 2>&1', "_", entry.id];
            appLaunch.running = true;
            exit();
        }

        function applyWallpaper(wall) {
            if (!wall)
                return;
            // Runs the configurable command with $WALL and $BLUR exported.
            // The blurred variant is only ensured when the command actually
            // references $BLUR, so non-blur setups skip that work entirely.
            Quickshell.execDetached(["bash", "-c", `
                export PATH="$HOME/.local/bin:$PATH"
                WALL="$1"
                BLUR="$2"
                if [ "$5" = "1" ] && [ -z "$BLUR" ]; then
                    mkdir -p "$3/blurred"
                    BLUR="$3/blurred/$(basename "$1")"
                    [ -e "$BLUR" ] || magick "$WALL" -resize 1024x -blur 0x10 "$BLUR"
                fi
                export WALL BLUR
                eval "$4" || notify-send -a launcher -i dialog-error "Wallpaper command failed" "$4"
            `, "_", wall.path, wall.blur, root.wallDir, cfg.wallCommand,
                cfg.wallCommand.includes("$BLUR") ? "1" : "0"]);
            exit();
        }

        // Enter on a clip copies it and expands the tile into an info card;
        // Enter again (or Escape) collapses it. The launcher stays open.
        property var expandedClip: null
        property string expandedText: ""
        property int expandedBytes: -1
        property point expandOrigin: Qt.point(0, 0)
        signal expandAnimStart
        signal expandAnimCollapse
        function collapseClip() {
            if (expandedClip)
                expandAnimCollapse();
        }
        function expandClip(clip) {
            if (!clip)
                return;
            expandedClip = clip;
            expandedText = "";
            expandedBytes = -1;
            // cells record expandOrigin synchronously on the change above
            Qt.callLater(() => expandAnimStart());
            // Fast path: decode for the details view immediately so the
            // text reveal runs together with the expand animation.
            infoClipId = clip.id;
            clipInfo.command = ["bash", "-c", `
                export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                cliphist decode "$1" | wc -c
                [ "$2" = "txt" ] && cliphist decode "$1" | head -c 4000
                exit 0`, "_", clip.id, clip.image ? "img" : "txt"];
            clipInfo.running = true;
            // Slow path: copy (which re-stores the entry under a new id via
            // the watcher), notify, then patch the new id into the list so
            // cached thumbnails stay valid.
            clipCopy.command = ["bash", "-c", `
                export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                tmp=$(mktemp)
                cliphist decode "$1" > "$tmp"
                wl-copy < "$tmp"
                # the notification body carries the full copied text (images
                # get the description passed in as $4)
                if [ "$2" = "img" ]; then
                    body="$4"
                else
                    body=$(head -c 4000 "$tmp")
                fi
                rm -f "$tmp"
                # copied images ride along as notification media (the decoded
                # entry is already cached by the thumbnail scan)
                if [ "$2" = "img" ] && [ -s "$3/$1.png" ]; then
                    notify-send -a launcher -i edit-copy -h "string:image-path:$3/$1.png" "Copied to clipboard" "$body"
                else
                    notify-send -a launcher -i edit-copy "Copied to clipboard" "$body"
                fi
                sleep 0.3
                nid=$(cliphist list | head -n 1 | cut -f1)
                echo "$nid"
                if [ "$2" = "img" ] && [ -n "$nid" ] && [ "$nid" != "$1" ]; then
                    cp "$3/$1.png" "$3/$nid.png" 2>/dev/null
                fi
                exit 0`, "_", clip.id, clip.image ? "img" : "txt", root.clipThumbDir,
                clip.preview.slice(0, 60)];
            clipCopy.running = true;
        }
        property string infoClipId: ""
        Process {
            id: clipInfo
            stdout: StdioCollector {
                onStreamFinished: {
                    const nl = text.indexOf("\n");
                    win.expandedBytes = parseInt(text.slice(0, nl).trim()) || 0;
                    win.expandedText = text.slice(nl + 1);
                }
            }
        }
        Process {
            id: clipCopy
            stdout: StdioCollector {
                onStreamFinished: {
                    const nid = text.trim();
                    if (nid && win.infoClipId && nid !== win.infoClipId) {
                        const idx = root.clips.findIndex(c => c.id === win.infoClipId);
                        if (idx >= 0) {
                            const c = root.clips[idx];
                            const upd = Object.assign({}, c, { id: nid });
                            if (c.image && c.thumb)
                                upd.thumb = root.clipThumbDir + "/" + nid + ".png";
                            root.clips = [upd].concat(root.clips.filter(x => x.id !== win.infoClipId));
                        }
                    }
                }
            }
        }
        readonly property var expandedInfo: {
            const c = expandedClip;
            if (!c)
                return [];
            const rows = [];
            rows.push(["type", c.image ? c.kind + " image" : "text"]);
            rows.push(["size", expandedBytes >= 0 ? root.humanBytes(expandedBytes) : (c.image ? c.size : "…")]);
            if (c.image)
                rows.push(["resolution", c.dims]);
            else if (expandedText)
                rows.push(["lines", "" + expandedText.split("\n").length + (expandedBytes > 1500 ? " (truncated)" : "")]);
            return rows;
        }

        function activate() {
            if (pane === "walls")
                applyWallpaper(wallMatches[wallSelected] ?? null);
            else if (pane === "clips") {
                if (expandedClip)
                    collapseClip();
                else
                    expandClip(clipMatches[clipSelected] ?? null);
            } else if (pane === "apps")
                launch(matches.length ? matches[selected] : null);
            else if (pane === "clock")
                setPane("apps");
        }

        // ---------- keybinds ----------
        readonly property var bindDefaults: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S", power: "Ctrl+P" })
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
            // letters/digits from the key code, so Ctrl+letter works (its
            // event.text is a control character)
            if (!name && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
                name = String.fromCharCode(event.key);
            if (!name && event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
                name = String.fromCharCode(event.key);
            if (!name && event.text && event.text.trim() && event.text.charCodeAt(0) >= 32)
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
            onFinished: {
                win.warmingWalls = true;
                // deferred one-time startup work (clip scans run per open)
                if (!root.scansStarted) {
                    root.scansStarted = true;
                    iconThemeScan.running = true;
                    fontScan.running = true;
                    if (!matugenProc.running && cfg.theme !== "matugen")
                        matugenProc.running = true;
                }
            }
            NumberAnimation {
                target: content
                property: "opacity"
                from: 0
                to: 1
                duration: win.ad(450)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: win
                property: "reveal"
                from: 0
                to: 1
                duration: win.ad(520)
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
                    duration: win.ad(320)
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: win
                    property: "reveal"
                    to: 0
                    duration: win.ad(320)
                    easing.type: Easing.InQuad
                }
            }
            // hide the window; the daemon keeps running
            ScriptAction {
                script: win.shown = false
            }
        }

        // ---------- content ----------
        Item {
            id: content
            anchors.fill: parent
            opacity: 0

            // the swipe-to-power rubber band, shared: every pane references
            // this one instance, so the pull physics live in a single place
            Translate {
                id: panePull
                y: win.powerPull
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.surface, cfg.dimOpacity)
            }

            // Background click-catcher; also the scroll-wheel path. Wheel
            // events land here from anywhere on screen: MouseAreas ignore
            // wheel unless they connect onWheel, so tile/button areas pass
            // scrolls down to this full-screen area. (A topmost sibling with
            // a WheelHandler never received the events on this layer surface,
            // so the handler lives on a MouseArea, whose delivery is proven
            // by the click path.)
            MouseArea {
                anchors.fill: parent
                property real wheelAcc: 0
                onClicked: {
                    if (win.powerArmed)
                        win.disarmPower();
                    else if (win.expandedClip)
                        win.collapseClip();
                    else
                        input.forceActiveFocus();
                }
                onWheel: wheel => {
                    wheelAcc += wheel.angleDelta.y;
                    while (wheelAcc >= 120) {
                        win.navigate(0, -1);
                        wheelAcc -= 120;
                    }
                    while (wheelAcc <= -120) {
                        win.navigate(0, 1);
                        wheelAcc += 120;
                    }
                }

                // swipe-to-power: a downward drag that starts on empty space
                // (tile MouseAreas grab their own presses). Same scene-coords
                // pattern as the notification swipe: the content moving under
                // the cursor must not feed back into the drag.
                DragHandler {
                    target: null
                    xAxis.enabled: false
                    yAxis.enabled: true
                    onActiveChanged: {
                        if (active) {
                            win.powerDragging = true;
                            win.powerGrabY = centroid.scenePosition.y - win.powerRaw;
                        } else {
                            win.powerDragging = false;
                            if (win.powerProgress >= 1) {
                                // hold the completed pose and wait for Enter
                                win.powerArmed = true;
                                win.powerRaw = win.powerThreshold;
                            } else {
                                win.disarmPower(); // springs back up
                            }
                        }
                    }
                    onCentroidChanged: {
                        if (active)
                            win.powerRaw = Math.max(0, centroid.scenePosition.y - win.powerGrabY);
                    }
                }
            }

            // Idle state: big clock + date. The outer gate holds the clock
            // back until the blur hole is large enough to accommodate it.
            Item {
                id: clockGate
                anchors.centerIn: parent
                width: clockView.width
                height: clockView.height
                transform: panePull
                visible: win.pane === "clock"
                onVisibleChanged: if (visible) fadeUp.restart()
                // fade in only once the hole (from wherever it originates)
                // has grown enough to reach and contain the clock
                opacity: {
                    const rc = (Math.hypot(width, height) + 60) / 2;
                    const dist = Math.hypot(win.originX - win.revW / 2, win.originY - win.revH / 2);
                    const radius = win.revealDiameter / 2;
                    return Math.max(0, Math.min(1, (radius - dist - rc * 0.8) / (rc * 0.5)));
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
                        NumberAnimation { target: clockView; property: "opacity"; from: 0; to: 1; duration: win.ad(300); easing.type: Easing.OutCubic }
                        NumberAnimation { target: clockView; property: "anchors.verticalCenterOffset"; from: 10; to: 0; duration: win.ad(300); easing.type: Easing.OutCubic }
                    }
                }
            }

            // App drawer: paged grid of app tiles
            Item {
                id: drawer
                anchors.centerIn: parent
                width: cfg.appsCols * 174 + (cfg.appsCols - 1) * 24 + 52
                height: grid.height + 52
                transform: panePull
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
                    NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: drawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: drawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
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
                            // replay the wave when the drawer opens: cells
                            // were already filled while it was hidden
                            Connections {
                                target: win
                                function onPaneChanged() {
                                    if (win.pane === "apps" && cell.filled)
                                        springIn.restart();
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
                                            source: root.iconUrl(cell.shownEntry ? cell.shownEntry.icon : "")
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
                                PropertyAction { target: wrap; property: "scale"; value: win.animFromScale }
                                PropertyAction { target: wrap; property: "y"; value: win.animFromY }
                                PauseAnimation { duration: win.animDelay(cell.index, cfg.appsCols) }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wrap; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: springOut
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: 1.08; duration: win.ad(80); easing.type: Easing.OutQuad }
                                    NumberAnimation { target: wrap; property: "y"; to: -3; duration: win.ad(80); easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: 0.4; duration: win.ad(320); easing.type: Easing.InQuad }
                                    NumberAnimation { target: wrap; property: "y"; to: 14; duration: win.ad(320); easing.type: Easing.InQuad }
                                    NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: win.ad(320); easing.type: Easing.InQuad }
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
                transform: panePull
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
                    NumberAnimation { target: wallDrawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: wallDrawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: wallDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
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
                                PropertyAction { target: wallWrap; property: "scale"; value: win.animFromScale }
                                PropertyAction { target: wallWrap; property: "y"; value: win.animFromY }
                                PauseAnimation { duration: win.animDelay(wallCell.index, cfg.wallsCols) }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wallWrap; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: wallSpringOut
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 1.08; duration: win.ad(80); easing.type: Easing.OutQuad }
                                    NumberAnimation { target: wallWrap; property: "y"; to: -3; duration: win.ad(80); easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 0.4; duration: win.ad(320); easing.type: Easing.InQuad }
                                    NumberAnimation { target: wallWrap; property: "y"; to: 14; duration: win.ad(320); easing.type: Easing.InQuad }
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 0; duration: win.ad(320); easing.type: Easing.InQuad }
                                }
                            }
                        }
                    }
                }
            }

            // Clipboard history: masonry grid of variable-height tiles
            Item {
                id: clipDrawer
                anchors.centerIn: parent
                width: cfg.clipsCols * 240 + (cfg.clipsCols - 1) * 16 + 52
                height: Math.max(clipMasonry.height, 120) + 52
                transform: panePull
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
                    NumberAnimation { target: clipDrawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: clipDrawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: clipDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Text {
                    visible: !root.cliphistAvailable || root.clips.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 40
                    text: root.cliphistAvailable
                        ? "clipboard history is empty"
                        : "cliphist not found — sudo dnf install cliphist wl-clipboard"
                    color: root.muted
                    font { family: root.mono; pixelSize: root.fs(14) }
                }

                Row {
                    id: clipMasonry
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    spacing: 16

                    Repeater {
                        model: cfg.clipsCols

                        Column {
                            id: clipColumn
                            required property int index
                            spacing: 16

                            Repeater {
                                model: win.clipRowsC

                                Item {
                                    id: clipCell
                                    required property int index
                                    // round-robin: slot order matches the
                                    // row-major order vMove navigates
                                    readonly property int slot: index * cfg.clipsCols + clipColumn.index
                                    readonly property int clipIndex: win.clipPage * win.clipPageSize + slot
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

                                    // text tiles grow with content up to a square;
                                    // image tiles keep their real aspect ratio
                                    // measure the wrapped text for an exact fit:
                                    // the tile hugs the content, truncating only
                                    // once it would exceed a square
                                    Text {
                                        id: measureText
                                        visible: false
                                        width: 214
                                        wrapMode: Text.Wrap
                                        text: {
                                            const c = clipCell.shownClip;
                                            return c && !c.image ? c.preview : "";
                                        }
                                        font { family: root.mono; pixelSize: root.fs(13) }
                                    }
                                    readonly property real lineHpx: measureText.lineCount > 0
                                        ? measureText.paintedHeight / measureText.lineCount
                                        : root.fs(16)
                                    readonly property int tileH: {
                                        const c = shownClip;
                                        if (!c)
                                            return 0;
                                        if (c.image) {
                                            const d = (c.dims || "").split("x");
                                            const iw = parseInt(d[0]) || 16;
                                            const ih = parseInt(d[1]) || 9;
                                            return Math.max(70, Math.min(320, Math.round(240 * ih / iw)));
                                        }
                                        return Math.max(44, Math.min(240, Math.ceil(measureText.paintedHeight) + 26));
                                    }
                                    width: 240
                                    height: tileH > 0 ? tileH + 24 : 0
                                    visible: tileH > 0

                                    // expanding one clip animates the rest away
                                    opacity: win.expandedClip !== null ? 0 : 1
                                    scale: win.expandedClip !== null ? 0.85 : 1
                                    Behavior on opacity {
                                        NumberAnimation { duration: win.ad(180); easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        NumberAnimation { duration: win.ad(220); easing.type: Easing.OutCubic }
                                    }
                                    // report the tile position so the expand
                                    // animation can grow out of it
                                    Connections {
                                        target: win
                                        function onExpandedClipChanged() {
                                            if (win.expandedClip && clipCell.isSelected) {
                                                const p = clipCell.mapToItem(clipDrawer, clipCell.width / 2, clipCell.height / 2);
                                                win.expandOrigin = Qt.point(p.x, p.y);
                                            }
                                        }
                                    }

                                    // caption line, like app/wallpaper labels
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: clipTile.y + clipCell.tileH + 6
                                        opacity: clipTile.opacity
                                        scale: clipTile.scale
                                        text: {
                                            const c = clipCell.shownClip;
                                            if (!c)
                                                return "";
                                            return c.image ? c.dims : c.bytes + " chars";
                                        }
                                        color: root.fg
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }

                                    Rectangle {
                                        id: clipTile
                                        width: parent.width
                                        height: clipCell.tileH
                                        radius: 12
                                        opacity: 0
                                        color: Qt.alpha(root.accent, clipCell.isSelected ? 0.2 : 0.08)
                                        border.width: 1
                                        border.color: clipCell.isSelected ? root.accent : Qt.alpha(root.accent, 0.25)

                                        ClippingRectangle {
                                            visible: clipCell.shownClip !== null && clipCell.shownClip.image === true
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            radius: 9
                                            color: "transparent"

                                            Image {
                                                anchors.fill: parent
                                                asynchronous: true
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize: Qt.size(480, 640)
                                                source: {
                                                    const c = clipCell.shownClip;
                                                    return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                                }
                                            }
                                        }
                                        Text {
                                            visible: clipCell.shownClip !== null && clipCell.shownClip.image !== true
                                            anchors.fill: parent
                                            anchors.margins: 13
                                            text: clipCell.shownClip ? clipCell.shownClip.preview : ""
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                            maximumLineCount: Math.max(1, Math.floor((clipCell.tileH - 26) / Math.max(1, clipCell.lineHpx)))
                                            color: root.fg
                                            font { family: root.mono; pixelSize: root.fs(13) }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: clipCell.filled && win.expandedClip === null
                                            onClicked: {
                                                win.clipSelected = clipCell.clipIndex;
                                                win.expandClip(clipCell.clip);
                                            }
                                        }
                                    }

                                    SequentialAnimation {
                                        id: clipSpringIn
                                        PropertyAction { target: clipTile; property: "opacity"; value: 0 }
                                        PropertyAction { target: clipTile; property: "scale"; value: win.animFromScale }
                                        PropertyAction { target: clipTile; property: "y"; value: win.animFromY }
                                        PauseAnimation { duration: win.animDelay(clipCell.slot, cfg.clipsCols) }
                                        ParallelAnimation {
                                            NumberAnimation { target: clipTile; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: clipTile; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 1.6 }
                                            NumberAnimation { target: clipTile; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 1.6 }
                                        }
                                    }
                                    SequentialAnimation {
                                        id: clipSpringOut
                                        ParallelAnimation {
                                            NumberAnimation { target: clipTile; property: "scale"; to: 0.7; duration: win.ad(240); easing.type: Easing.InQuad }
                                            NumberAnimation { target: clipTile; property: "y"; to: 10; duration: win.ad(240); easing.type: Easing.InQuad }
                                            NumberAnimation { target: clipTile; property: "opacity"; to: 0; duration: win.ad(240); easing.type: Easing.InQuad }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // expanded clip: grows out of the selected tile while the
                // rest of the grid animates away (no dimming overlay)
                Item {
                    id: expandCard
                    visible: win.expandedClip !== null
                    readonly property bool isImg: win.expandedClip !== null && win.expandedClip.image === true
                    // images render at native size, capped to fit the screen
                    readonly property size imgFit: {
                        if (!isImg)
                            return Qt.size(0, 0);
                        const d = (win.expandedClip.dims || "").split("x");
                        const iw = parseInt(d[0]) || 16;
                        const ih = parseInt(d[1]) || 9;
                        const s = Math.min(1, 1500 / iw, 800 / ih);
                        return Qt.size(Math.max(320, Math.round(iw * s)), Math.max(180, Math.round(ih * s)));
                    }
                    anchors.centerIn: parent
                    width: isImg ? imgFit.width + 48 : 560
                    height: expandCol.height + 44
                    // the decoded full text arrives async and is longer than
                    // the preview; grow smoothly instead of jumping
                    Behavior on height {
                        NumberAnimation { duration: win.ad(380); easing.type: Easing.OutCubic }
                    }
                    transform: Translate { id: expandTx }

                    // swallow clicks so they don't fall through to the
                    // background (which collapses the expansion)
                    MouseArea {
                        anchors.fill: parent
                    }

                    ParallelAnimation {
                        id: expandIn
                        NumberAnimation { target: expandTx; property: "x"; to: 0; duration: win.ad(380); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandTx; property: "y"; to: 0; duration: win.ad(380); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandCard; property: "opacity"; from: 0.3; to: 1; duration: win.ad(220); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandCard; property: "scale"; from: 0.35; to: 1; duration: win.ad(380); easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    }
                    SequentialAnimation {
                        id: expandOut
                        ParallelAnimation {
                            NumberAnimation {
                                target: expandTx
                                property: "x"
                                to: win.expandOrigin.x - clipDrawer.width / 2
                                duration: win.ad(260)
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: expandTx
                                property: "y"
                                to: win.expandOrigin.y - clipDrawer.height / 2
                                duration: win.ad(260)
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation { target: expandCard; property: "scale"; to: 0.35; duration: win.ad(260); easing.type: Easing.InCubic }
                            NumberAnimation { target: expandCard; property: "opacity"; to: 0; duration: win.ad(260); easing.type: Easing.InCubic }
                        }
                        ScriptAction { script: win.expandedClip = null }
                    }
                    Connections {
                        target: win
                        function onExpandAnimStart() {
                            expandOut.stop();
                            expandTx.x = win.expandOrigin.x - clipDrawer.width / 2;
                            expandTx.y = win.expandOrigin.y - clipDrawer.height / 2;
                            expandIn.restart();
                        }
                        function onExpandAnimCollapse() {
                            expandIn.stop();
                            expandOut.restart();
                        }
                    }

                    Column {
                        id: expandCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        width: parent.width - 48
                        spacing: 14

                        ClippingRectangle {
                            visible: expandCard.isImg
                            width: parent.width
                            height: expandCard.imgFit.height
                            radius: 12
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(2000, 1200)
                                source: {
                                    const c = win.expandedClip;
                                    return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                }
                            }
                        }
                        // the full text reveals gradually as the container
                        // grows, instead of jumping when the decode lands
                        Item {
                            visible: win.expandedClip !== null && win.expandedClip.image !== true
                            width: parent.width
                            height: expandBody.paintedHeight
                            clip: true
                            Behavior on height {
                                NumberAnimation { duration: win.ad(380); easing.type: Easing.OutCubic }
                            }

                            Text {
                                id: expandBody
                                width: parent.width
                                text: win.expandedText || (win.expandedClip ? win.expandedClip.preview : "")
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 30
                                color: root.fg
                                font { family: root.mono; pixelSize: root.fs(13) }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.alpha(root.accent, 0.25)
                        }

                        Repeater {
                            model: win.expandedInfo

                            Item {
                                required property var modelData
                                width: expandCol.width
                                height: root.fs(20)

                                Text {
                                    anchors.left: parent.left
                                    text: parent.modelData[0]
                                    color: root.muted
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: parent.modelData[1]
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }
                        }
                    }
                }
            }

            // Settings pane
            Item {
                id: settingsPane
                readonly property int tabIdx: win.settingsTab === "general" ? 0 : win.settingsTab === "flyouts" ? 1 : 2
                anchors.centerIn: parent
                width: 860
                height: 26 + settingsHeader.height + 18 + tabViewport.height + 26
                transform: panePull
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
                    NumberAnimation { target: settingsPane; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: settingsPane; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: settingsPane; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                // header: title + underlined tab links, left-aligned
                Item {
                    id: settingsHeader
                    width: 780
                    height: 58
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26

                    Text {
                        text: "SETTINGS"
                        color: root.muted
                        font { family: root.mono; pixelSize: root.fs(13); letterSpacing: 3 }
                    }
                    Row {
                        anchors.bottom: parent.bottom
                        spacing: 26

                        Repeater {
                            model: [
                                { id: "general", label: "Launcher" },
                                { id: "flyouts", label: "Flyouts" },
                                { id: "colors", label: "Colors" }
                            ]

                            Item {
                                id: settingsTabItem
                                required property var modelData
                                readonly property bool active: win.settingsTab === modelData.id
                                width: settingsTabText.implicitWidth
                                height: 24

                                Text {
                                    id: settingsTabText
                                    text: settingsTabItem.modelData.label
                                    color: settingsTabItem.active ? root.fg : root.muted
                                    font { family: root.mono; pixelSize: root.fs(14) }
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: root.accent
                                    opacity: settingsTabItem.active ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: win.settingsTab = settingsTabItem.modelData.id
                                }
                            }
                        }
                    }
                }

                // pages slide horizontally when switching tabs, all
                // top-aligned so shorter pages stay level
                Item {
                    id: tabViewport
                    clip: true
                    width: 820
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: settingsHeader.bottom
                    anchors.topMargin: 18
                    // constant height (tallest page): switching tabs never
                    // moves the pane, shorter pages stay top-aligned
                    height: Math.max(settingsCol.height, flyCol.height, colorsCol.height)

                // flyouts tab: volume + notification OSDs
                Column {
                    id: flyCol
                    x: 20 + (1 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.ad(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    // default valueWidth throughout (the values are short), so
                    // the ‹ › buttons line up column-tight like the launcher
                    // tab; only the font row needs a wide value
                    // enabled flyouts (unloading notifications releases the
                    // org.freedesktop.Notifications DBus name for other daemons)
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Flyouts"
                        }
                        SReset {
                            key: "flyouts"
                            anchors.right: parent.right
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            spacing: 8
                            height: parent.height

                            Repeater {
                                model: [
                                    { id: "volume", label: "volume" },
                                    { id: "notifs", label: "notifications" }
                                ]

                                Item {
                                    id: flyChip
                                    required property var modelData
                                    readonly property bool on: root.flyoutOn(modelData.id)
                                    width: flyBox.width + 6 + flyChipText.implicitWidth
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        id: flyBox
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 4
                                        color: flyChip.on ? Qt.alpha(root.accent, 0.85) : "transparent"
                                        border.width: 1
                                        border.color: flyChip.on ? root.accent : Qt.alpha(root.muted, 0.6)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: flyChip.on
                                            text: "✓"
                                            color: "#141210"
                                            font { pixelSize: 13; weight: Font.Bold }
                                        }
                                    }
                                    Text {
                                        id: flyChipText
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: flyBox.right
                                        anchors.leftMargin: 6
                                        text: flyChip.modelData.label
                                        color: flyChip.on ? root.fg : root.muted
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: win.toggleFlyout(flyChip.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    SettingRow { key: "volStyle"; label: "Volume style" }
                    SettingRow { key: "volWidth"; label: "Volume size" }
                    SettingRow { key: "volAnim"; label: "Volume animation" }
                    SettingRow { key: "volPercent"; label: "Volume percent" }
                    SettingRow { key: "volTimeout"; label: "Volume timeout" }
                    SettingRow { key: "notifStyle"; label: "Notification style" }
                    SettingRow { key: "notifTimeout"; label: "Notification timeout" }
                    SettingRow { key: "flyFontFamily"; label: "Font"; valueWidth: 260 }
                    SettingRow { key: "notifFontScale"; label: "Font size"; sub: "applies to all flyout text, including the volume percent" }
                }

                Column {
                    id: settingsCol
                    x: 20 + (0 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.ad(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    // enabled pages: click toggles, drag left/right reorders
                    // the cycle (leftmost chip is the home pane)
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Pages"
                        }
                        SReset {
                            key: "pages"
                            anchors.right: parent.right
                        }
                        Item {
                            id: pagesArea
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property int slotW: 100
                            width: slotW * 4 - 8
                            height: 28

                            Repeater {
                                model: ["clock", "apps", "walls", "clips"]

                                Item {
                                    id: pageChip
                                    required property var modelData
                                    readonly property bool on: (cfg.pages ?? {})[modelData] !== false
                                    readonly property int ord: win.paneOrder.indexOf(modelData)
                                    width: pagesArea.slotW - 8
                                    height: 28

                                    // slot position animates on reorder; the drag
                                    // offset rides on top and is written raw while
                                    // held (its Behavior re-enables before the
                                    // release write, so letting go slides home)
                                    property bool held: false
                                    property real dragOff: 0
                                    property real grabDX: 0
                                    property real slotX: ord * pagesArea.slotW
                                    Behavior on slotX {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on dragOff {
                                        enabled: !pageChip.held
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }
                                    x: slotX + dragOff
                                    z: held ? 2 : 0
                                    scale: held ? 1.06 : 1
                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }

                                    Rectangle {
                                        id: pageBox
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 4
                                        color: pageChip.on ? Qt.alpha(root.accent, 0.85) : "transparent"
                                        border.width: 1
                                        border.color: pageChip.on ? root.accent : Qt.alpha(root.muted, 0.6)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: pageChip.on
                                            text: "✓"
                                            color: "#141210"
                                            font { pixelSize: 13; weight: Font.Bold }
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: pageBox.right
                                        anchors.leftMargin: 6
                                        text: pageChip.modelData
                                        color: pageChip.on ? root.fg : root.muted
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }

                                    TapHandler {
                                        onTapped: win.togglePage(pageChip.modelData)
                                    }
                                    DragHandler {
                                        id: chipDrag
                                        target: null
                                        yAxis.enabled: false
                                        onActiveChanged: {
                                            if (active) {
                                                pageChip.held = true;
                                                pageChip.grabDX = centroid.scenePosition.x - pageChip.x;
                                            } else {
                                                pageChip.held = false;
                                                pageChip.dragOff = 0; // slides into its slot
                                                root.saveSettings();
                                            }
                                        }
                                        onCentroidChanged: {
                                            if (!active)
                                                return;
                                            pageChip.dragOff = centroid.scenePosition.x - pageChip.grabDX - pageChip.slotX;
                                            const idx = Math.max(0, Math.min(3, Math.round(pageChip.x / pagesArea.slotW)));
                                            if (idx !== pageChip.ord)
                                                win.movePage(pageChip.modelData, idx);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SSub {
                        text: "click toggles a page, drag to reorder — the leftmost page is home"
                    }

                    Repeater {
                        model: [
                            { key: "appsGrid", label: "Apps grid" },
                            { key: "wallsGrid", label: "Wallpaper grid" },
                            { key: "clipsGrid", label: "Clipboard grid" },
                            { key: "clipsMax", label: "Clipboard entries" },
                            { key: "animStyle", label: "Animation" },
                            { key: "fontScale", label: "Font size" },
                            { key: "dimOpacity", label: "Opacity" },
                            { key: "revealOrigin", label: "Spawn circle origin" },
                            { key: "fontFamily", label: "Font" },
                            { key: "iconTheme", label: "Icon theme", sub: "applies on next launch" }
                        ]

                        SettingRow {
                            required property var modelData
                            key: modelData.key
                            label: modelData.label
                            sub: modelData.sub ?? ""
                            valueWidth: modelData.key === "iconTheme" || modelData.key === "fontFamily" ? 260
                                : modelData.key === "revealOrigin" ? 150 : 90
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
                        SReset {
                            key: "wallpaperDir"
                            anchors.right: parent.right
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
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
                                Connections {
                                    target: cfg
                                    function onWallpaperDirChanged() {
                                        pathInput.text = cfg.wallpaperDir;
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.IBeamCursor
                            }
                        }
                    }

                    // wallpaper command ($WALL = image, $BLUR = blurred variant)
                    Item {
                        width: 780
                        height: 38

                        SLabel {
                            anchors.left: parent.left
                            text: "Wallpaper command"
                        }
                        SReset {
                            key: "wallCommand"
                            anchors.right: parent.right
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            width: 506
                            height: 34
                            radius: 8
                            color: Qt.alpha(root.accent, cmdInput.activeFocus ? 0.16 : 0.08)
                            border.width: 1
                            border.color: cmdInput.activeFocus ? root.accent : Qt.alpha(root.accent, 0.33)

                            TextInput {
                                id: cmdInput
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                text: cfg.wallCommand
                                color: root.fg
                                clip: true
                                font { family: root.mono; pixelSize: root.fs(12) }
                                onEditingFinished: {
                                    if (text !== cfg.wallCommand) {
                                        cfg.wallCommand = text;
                                        root.saveSettings();
                                    }
                                    input.forceActiveFocus();
                                }
                                Keys.onEscapePressed: input.forceActiveFocus()
                                Connections {
                                    target: cfg
                                    function onWallCommandChanged() {
                                        cmdInput.text = cfg.wallCommand;
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                cursorShape: Qt.IBeamCursor
                            }
                        }
                    }
                    SSub {
                        text: "$WALL = selected image, $BLUR = blurred variant (auto-generated)"
                    }

                    // keybinds
                    Repeater {
                        model: [
                            { action: "cycle", label: "Cycle pages" },
                            { action: "reverseCycle", label: "Cycle pages (reverse)" },
                            { action: "launch", label: "Launch / apply" },
                            { action: "settings", label: "Settings" },
                            { action: "power", label: "Power off prompt" },
                            { action: "exit", label: "Exit / back" }
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
                            SReset {
                                key: "bind:" + bindRow.modelData.action
                                anchors.right: parent.right
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 34
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
                                        : (cfg.keybinds[bindRow.modelData.action] ?? win.bindDefaults[bindRow.modelData.action] ?? "")
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

                }

                // colors tab: one scheme row per scope plus the custom palette
                Column {
                    id: colorsCol
                    x: 20 + (2 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.ad(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    ThemeRow { cfgKey: "theme" }
                    ThemeRow {
                        cfgKey: "flyTheme"
                        sub: "dynamic tints each notification from its app icon; the volume flyout then follows the launcher scheme"
                    }

                    // custom palette: three hex fields feeding the "custom" scheme
                    Item {
                        width: 780
                        height: 40

                        SLabel {
                            anchors.left: parent.left
                            text: "Custom palette"
                        }
                        SReset {
                            key: "customTheme"
                            anchors.right: parent.right
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            spacing: 10
                            height: parent.height

                            Repeater {
                                model: [
                                    { part: "accent", label: "accent" },
                                    { part: "fg", label: "text" },
                                    { part: "muted", label: "muted" }
                                ]

                                Rectangle {
                                    id: palField
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 132
                                    height: 34
                                    radius: 8
                                    color: Qt.alpha(root.accent, palInput.activeFocus ? 0.16 : 0.08)
                                    border.width: 1
                                    border.color: palInput.activeFocus ? root.accent : Qt.alpha(root.accent, 0.33)

                                    Rectangle {
                                        id: palSwatch
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 5
                                        color: root.customPal()[palField.modelData.part]
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.15)
                                    }
                                    TextInput {
                                        id: palInput
                                        anchors.left: palSwatch.right
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.customPal()[palField.modelData.part]
                                        color: root.fg
                                        clip: true
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                        onEditingFinished: {
                                            if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                                                const c = Object.assign({}, root.customPal());
                                                c[palField.modelData.part] = text.toLowerCase();
                                                cfg.customTheme = c;
                                                root.saveSettings();
                                            } else {
                                                text = root.customPal()[palField.modelData.part];
                                            }
                                            input.forceActiveFocus();
                                        }
                                        Keys.onEscapePressed: input.forceActiveFocus()
                                        Connections {
                                            target: cfg
                                            function onCustomThemeChanged() {
                                                palInput.text = root.customPal()[palField.modelData.part];
                                            }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.NoButton
                                        cursorShape: Qt.IBeamCursor
                                    }
                                }
                            }
                        }
                    }
                    SSub {
                        text: "hex colors (accent / text / muted) behind the custom scheme"
                    }
                }
                } // tabViewport
            }

            // Swipe-to-power pull indicator: extra dim over the whole screen,
            // and a small ring that rides down ahead of the pulled content,
            // stroking itself closed as the drag progresses. On completion a
            // "power off?" prompt fades in; Enter confirms.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.5 * win.powerProgress
            }
            Item {
                id: powerRing
                visible: win.powerRaw > 1
                anchors.horizontalCenter: parent.horizontalCenter
                // the -200 rides in with the pull so the ring still enters
                // from the top edge, just landing higher than the stock spot
                y: -height + win.powerPull * 2.6 - 200 * win.powerProgress
                width: 36
                height: 36
                opacity: Math.min(1, win.powerRaw / 80)

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        // a plain ring that strokes itself closed clockwise
                        // from the top as the drag completes
                        ctx.lineWidth = 3.6;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = root.accent;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, 10, -Math.PI / 2,
                            -Math.PI / 2 + Math.PI * 2 * win.powerProgress, false);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: win
                    function onPowerProgressChanged() {
                        ringCanvas.requestPaint();
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: powerRing.y + powerRing.height + 12
                text: "power off?"
                color: root.fg
                // start the fade as the ring nears closed: the pull easing
                // crawls through its last few percent, so waiting for exactly
                // 1.0 reads as a long pause after the circle looks complete
                opacity: win.powerProgress >= 0.85 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                font { family: root.mono; pixelSize: root.fs(18); letterSpacing: 2 }
            }

            // Corner settings button: pops up when hovering the bottom-right
            // corner, or while the settings pane is open
            MouseArea {
                id: settingsHover
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 260
                height: 180
                hoverEnabled: true
                readonly property bool revealed: containsMouse || win.pane === "settings"

                Rectangle {
                    id: cornerBtn
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 32
                    width: 56
                    height: 56
                    radius: 28
                    antialiasing: true
                    color: Qt.alpha(root.accent, cornerBtnArea.containsMouse ? 0.2 : 0.11)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.33)
                    opacity: settingsHover.revealed ? 1 : 0
                    scale: settingsHover.revealed ? 1 : 0.5
                    Behavior on opacity {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: root.fg
                        font { pixelSize: root.fs(26) }
                    }
                    MouseArea {
                        id: cornerBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.toggleSettings()
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
            case "clipsGrid": return cfg.clipsCols + " × " + clipRowsC;
            case "clipsMax": return "" + cfg.clipsMax;
            case "animStyle": return cfg.animStyle;
            case "fontScale": return Math.round(cfg.fontScale * 100) + "%";
            case "dimOpacity": return Math.round(cfg.dimOpacity * 100) + "%";
            case "revealOrigin": return cfg.revealOrigin;
            case "fontFamily": return cfg.fontFamily || "JetBrains Mono";
            case "iconTheme": return cfg.iconTheme || "system default";
            case "volWidth": return cfg.volWidth + " px";
            case "flyFontFamily": return cfg.flyFontFamily || "follow launcher";
            case "volAnim": return cfg.volAnim;
            case "volStyle": return cfg.volStyle === "sine" ? "sine wave" : cfg.volStyle;
            case "volPercent": return cfg.volShowPercent ? "on" : "off";
            case "volTimeout": return (cfg.volTimeout / 1000).toFixed(1) + " s";
            case "notifTimeout": return (cfg.notifTimeout / 1000).toFixed(0) + " s";
            case "notifFontScale": return Math.round(cfg.notifFontScale * 100) + "%";
            case "notifStyle": return cfg.notifStyle;
            }
            return "";
        }
        readonly property var originChoices: ["center", "top-left", "top-right", "bottom-left", "bottom-right"]
        function cycleChoice(cur: string, list, dir: int): string {
            let i = list.indexOf(cur);
            if (i < 0)
                i = 0;
            return list[((i + dir) % list.length + list.length) % list.length];
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
            case "clipsGrid":
                if (dir > 0) {
                    if (cfg.clipsCols < 4) cfg.clipsCols++;
                    else if (clipRowsC < 4) { cfg.clipsRows = clipRowsC + 1; cfg.clipsCols = 2; }
                } else {
                    if (cfg.clipsCols > 2) cfg.clipsCols--;
                    else if (clipRowsC > 2) { cfg.clipsRows = clipRowsC - 1; cfg.clipsCols = 4; }
                }
                break;
            case "clipsMax":
                cfg.clipsMax = Math.max(20, Math.min(200, cfg.clipsMax + dir * 20));
                clipScan.running = false;
                clipScan.running = true;
                break;
            case "animStyle": {
                const styles = ["wave", "pop", "fade", "slide", "none"];
                let i = styles.indexOf(cfg.animStyle);
                if (i < 0)
                    i = 0;
                cfg.animStyle = styles[((i + dir) % styles.length + styles.length) % styles.length];
                break;
            }
            case "fontScale":
                cfg.fontScale = Math.max(0.7, Math.min(1.6, Math.round((cfg.fontScale + dir * 0.1) * 100) / 100));
                break;
            case "dimOpacity":
                cfg.dimOpacity = Math.max(0, Math.min(1, Math.round((cfg.dimOpacity + dir * 0.05) * 100) / 100));
                break;
            case "revealOrigin": {
                let i = originChoices.indexOf(cfg.revealOrigin);
                if (i < 0)
                    i = 0;
                cfg.revealOrigin = originChoices[((i + dir) % originChoices.length + originChoices.length) % originChoices.length];
                break;
            }
            case "fontFamily": {
                const list = [""].concat(root.fontFamilies);
                let i = list.indexOf(cfg.fontFamily);
                if (i < 0)
                    i = 0;
                cfg.fontFamily = list[((i + dir) % list.length + list.length) % list.length];
                break;
            }
            case "iconTheme":
                cycleIconTheme(dir);
                break;
            case "volWidth":
                cfg.volWidth = Math.max(240, Math.min(560, cfg.volWidth + dir * 20));
                break;
            case "volAnim":
                cfg.volAnim = cycleChoice(cfg.volAnim, ["slide", "fade", "pop", "none"], dir);
                break;
            case "volStyle":
                cfg.volStyle = cycleChoice(cfg.volStyle, ["pill", "sine"], dir);
                break;
            case "volPercent":
                cfg.volShowPercent = !cfg.volShowPercent;
                break;
            case "volTimeout":
                cfg.volTimeout = Math.max(500, Math.min(10000, cfg.volTimeout + dir * 500));
                break;
            case "flyFontFamily": {
                const list = [""].concat(root.fontFamilies);
                let i = list.indexOf(cfg.flyFontFamily);
                if (i < 0)
                    i = 0;
                cfg.flyFontFamily = list[((i + dir) % list.length + list.length) % list.length];
                break;
            }
            case "notifTimeout":
                cfg.notifTimeout = Math.max(1000, Math.min(15000, cfg.notifTimeout + dir * 1000));
                break;
            case "notifFontScale":
                cfg.notifFontScale = Math.max(0.7, Math.min(1.6, Math.round((cfg.notifFontScale + dir * 0.1) * 100) / 100));
                break;
            case "notifStyle":
                cfg.notifStyle = cycleChoice(cfg.notifStyle, ["bubble", "pill"], dir);
                break;
            }
            root.saveSettings();
        }

        function toggleFlyout(f: string) {
            const fly = Object.assign({ volume: true, notifs: true }, cfg.flyouts);
            fly[f] = fly[f] === false;
            cfg.flyouts = fly;
            root.saveSettings();
        }

        function togglePage(p: string) {
            const pages = Object.assign({ clock: true, apps: true, walls: true, clips: true }, cfg.pages);
            const enabled = paneOrder.filter(x => pages[x] !== false);
            // keep at least one page enabled
            if (pages[p] !== false && enabled.length <= 1)
                return;
            pages[p] = pages[p] === false;
            cfg.pages = pages;
            root.saveSettings();
            if (!activePanes.includes(pane) && pane !== "settings")
                setPane(homePane());
        }

        function resetSetting(key: string) {
            switch (key) {
            case "pages":
                cfg.pages = ({ clock: true, apps: true, walls: true, clips: true });
                cfg.pageOrder = ["clock", "apps", "walls", "clips"];
                break;
            case "appsGrid": cfg.appsCols = 4; cfg.appsRows = 3; break;
            case "wallsGrid": cfg.wallsCols = 3; cfg.wallsRows = 3; break;
            case "clipsGrid": cfg.clipsCols = 3; cfg.clipsRows = 3; break;
            case "clipsMax":
                cfg.clipsMax = 60;
                clipScan.running = false;
                clipScan.running = true;
                break;
            case "animStyle": cfg.animStyle = "wave"; break;
            case "fontScale": cfg.fontScale = 1.0; break;
            case "dimOpacity": cfg.dimOpacity = 0.4; break;
            case "revealOrigin": cfg.revealOrigin = "center"; break;
            case "fontFamily": cfg.fontFamily = ""; break;
            case "iconTheme": cfg.iconTheme = ""; break;
            case "theme": cfg.theme = "amber"; cfg.themeLight = false; break;
            case "wallpaperDir":
                cfg.wallpaperDir = "~/Pictures/wallpapers";
                root.rescanWallpapers();
                break;
            case "wallCommand": cfg.wallCommand = root.defaultWallCommand; break;
            case "customTheme": cfg.customTheme = ({ accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" }); break;
            case "volWidth": cfg.volWidth = 340; break;
            case "flyFontFamily": cfg.flyFontFamily = ""; break;
            case "flyTheme": cfg.flyTheme = "amber"; cfg.flyLight = false; break;
            case "flyouts": cfg.flyouts = ({ volume: true, notifs: true }); break;
            case "volAnim": cfg.volAnim = "slide"; break;
            case "volStyle": cfg.volStyle = "pill"; break;
            case "volPercent": cfg.volShowPercent = true; break;
            case "volTimeout": cfg.volTimeout = 1500; break;
            case "notifTimeout": cfg.notifTimeout = 5000; break;
            case "notifFontScale": cfg.notifFontScale = 1.0; break;
            case "notifStyle": cfg.notifStyle = "bubble"; break;
            default:
                if (key.startsWith("bind:")) {
                    const a = key.slice(5);
                    setBind(a, bindDefaults[a] ?? "");
                    return; // setBind saves
                }
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
                if (text.length > 0 && win.pane === "clock" && win.activePanes.includes("apps"))
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
                // armed power prompt: Enter powers off, anything else lets go
                if (win.powerArmed) {
                    event.accepted = true;
                    // a bare modifier press is not a decision either way
                    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].includes(event.key))
                        return;
                    // compare the unmodified key: Ctrl still held from the
                    // Ctrl+P arm must not turn the confirm into "Ctrl+Return"
                    const bare = ks.replace(/^(?:Ctrl\+|Alt\+|Shift\+)+/, "");
                    if (bare === (kb.launch ?? "Return"))
                        win.powerOff();
                    else
                        win.disarmPower();
                    return;
                }
                if (ks === (kb.exit ?? "Escape")) {
                    // layered: expanded clip -> settings -> whole app
                    if (win.expandedClip)
                        win.collapseClip();
                    else if (win.pane === "settings")
                        win.setPane(win.paneBeforeSettings);
                    else
                        win.exit();
                    event.accepted = true;
                } else if (ks === (kb.settings ?? "Ctrl+S")) {
                    win.toggleSettings();
                    event.accepted = true;
                } else if (ks === (kb.power ?? "Ctrl+P")) {
                    win.playPower();
                    event.accepted = true;
                } else if (ks === (kb.reverseCycle ?? "Shift+Tab")) {
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
        property bool warmedOnce: false
        FrameAnimation {
            id: firstFrames
            onTriggered: {
                // caches survive between opens; warm only the first time
                if (win.warmedOnce) {
                    fadeIn.restart();
                    stop();
                    return;
                }
                if (currentFrame === 1) {
                    win.warmingApps = true;
                } else if (currentFrame >= 3) {
                    win.warmingApps = false;
                    win.warmedOnce = true;
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

        // ---------- tile entry animation styles ----------
        // wave: staggered spring cascade (default). pop: all tiles spring at
        // once. fade: soft staggered fade. slide: rows slide up. none: instant.
        readonly property string animStyle: cfg.animStyle
        readonly property real animFromScale: animStyle === "wave" || animStyle === "pop" ? 0.4 : 1
        readonly property int animFromY: animStyle === "wave" ? 14 : animStyle === "slide" ? 46 : animStyle === "fade" ? 6 : 0
        readonly property int animDur: animStyle === "fade" ? 220 : animStyle === "slide" ? 320 : animStyle === "none" ? 0 : 400
        readonly property int animFadeDur: animStyle === "none" ? 0 : 180
        readonly property int animEase: animStyle === "wave" || animStyle === "pop" ? Easing.OutBack : Easing.OutCubic
        // "none" zeroes every animation duration, including the intro reveal
        function ad(ms: int): int {
            return animStyle === "none" ? 0 : ms;
        }
        function animDelay(slot: int, cols: int): int {
            if (!staggering)
                return 0;
            switch (animStyle) {
            case "wave": return slot * 35;
            case "slide": return Math.floor(slot / cols) * 60;
            case "fade": return slot * 15;
            }
            return 0;
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
            // With animations off there is no reveal to protect from the
            // warm-up frames: show everything on the very first frame.
            // (firstFrames still runs for cache warming; the zero-duration
            // fadeIn it triggers just re-sets these same values.)
            if (animStyle === "none") {
                reveal = 1;
                content.opacity = 1;
            }
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
                    source: root.iconUrl(modelData.icon)
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

    // Warm the app-icon pixmap cache the moment the daemon starts, so the
    // very first launcher open renders icons immediately instead of briefly
    // showing the two-letter fallback while the SVGs decode (QML decodes
    // images on a single reader thread, so ~100 theme SVGs take a second or
    // two — pay that at session start, not at first open). A tiny transparent
    // overlay surface is enough to drive the image provider and populate the
    // process-global cache; it unloads once the cache is warm (the in-window
    // warm-up Item keeps every pixmap referenced after that, so the cache
    // never evicts them).
    property bool bootWarmIcons: true
    Timer { interval: 30000; running: true; onTriggered: root.bootWarmIcons = false }
    LazyLoader {
        active: root.bootWarmIcons
        PanelWindow {
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "launcher-warm"
            mask: Region {} // click-through, takes no input

            Item {
                anchors.fill: parent
                Repeater {
                    model: root.allApps
                    Image {
                        required property var modelData
                        width: 1
                        height: 1
                        asynchronous: true
                        sourceSize: Qt.size(88, 88)
                        source: root.iconUrl(modelData.icon)
                    }
                }
            }
        }
    }

    // ================= OSDs (persistent) =================
    // Both flyouts are persistent windows of fixed size; the cards animate
    // inside them. niri's geometry-corner-radius does not clip layer-surface
    // blur (verified on 26.04-git 2809), so the blur is shaped client-side
    // with ellipse scanline regions, inset 2px so the region edge hides
    // under the card's antialiased border.

    // ---------- volume OSD: pill sliding up from the bottom edge ----------
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false

    // ignore the initial property churn while pipewire connects
    property bool volReady: false
    Timer {
        interval: 2000
        running: true
        onTriggered: root.volReady = true
    }
    onVolChanged: if (volReady) volOsd.ping()
    onSinkMutedChanged: if (volReady) volOsd.ping()

    Scope {
        id: volOsd
        property bool show: false
        property bool leaving: false
        property bool entered: false
        function ping() {
            if (!root.flyoutOn("volume"))
                return;
            leaving = false;
            if (!show) {
                show = true;
                // entered flips a tick later so the first frame renders the
                // hidden pose and the entry actually animates
                entered = false;
                Qt.callLater(() => entered = true);
            }
            volHide.restart();
        }
        Timer {
            id: volHide
            interval: cfg.volTimeout
            onTriggered: volOsd.leaving = true
        }
        // Fallback unmap. Normally the window unmaps the instant the exit
        // animation reports the card gone (see volCard's watchers), which
        // avoids a lingering blurred remnant after the pill has left; this
        // just guarantees teardown if no frame reports it.
        Timer {
            interval: 500
            running: volOsd.leaving
            onTriggered: volOsd.finishHide()
        }
        function finishHide() {
            show = false;
            leaving = false;
        }

        // Always loaded, only mapped while showing: mapping a pre-built
        // window costs a frame or two, unlike the full rebuild a LazyLoader
        // pays, so rapid volume changes never lag. The card moves inside the
        // fixed window; layer margins never animate (margin changes need a
        // compositor round trip per step and stutter).
        PanelWindow {
            id: volWin
            readonly property string mode: cfg.volAnim
            readonly property bool eq: cfg.volStyle !== "pill"
            visible: volOsd.show || volOsd.leaving
            anchors.bottom: true
            implicitWidth: cfg.volWidth + 8
            implicitHeight: 280
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "launcher-vol-osd"
            // the OSD never takes input
            mask: Region {}

            // ~90ms animation tick drives the equalizer bar motion, only
            // while the OSD is on screen (pill needs no tick)
            property int tick: 0
            Timer {
                interval: 90
                running: volWin.eq && (volOsd.show || volOsd.leaving)
                repeat: true
                onTriggered: volWin.tick++
            }
            readonly property bool pct: cfg.volShowPercent
            // Half-height (px) of one sine-wave bar (mirrored above/below the
            // centre). The volume factor dominates (the wobble is a narrow
            // band on top) and the amplitude spans most of the card, so a
            // volume change reads clearly as taller/shorter bars.
            function volBarHalf(i: int, n: int): int {
                const eff = root.sinkMuted ? 0 : root.vol * 100;
                if (eff <= 0)
                    return 2; // 4px floor
                // square-root response: steep below ~50% so quiet-range
                // volume steps read clearly, flattening toward full volume
                const v = Math.sqrt(Math.min(1, eff / 100));
                const wobble = 0.78 + 0.22 * Math.sin(tick * 0.35 + i * 0.85 + 2);
                return Math.round(Math.max(4, v * 84 * wobble) / 2);
            }

            Rectangle {
                id: volCard
                readonly property bool on: volOsd.show && !volOsd.leaving && volOsd.entered
                x: (parent.width - width) / 2
                width: cfg.volWidth
                // equalizer variants need a taller card than the pill
                height: volWin.eq ? 108 : 56
                radius: volWin.eq ? 18 : 28
                // rests 90px above the screen bottom; the slide exit drops it
                // past the window (= screen) bottom edge. Bounce is built in:
                // the exit overshoot lands off-screen, so only the entry
                // shows it.
                readonly property real restY: parent.height - height - 90
                y: volWin.mode === "slide" ? (on ? restY : parent.height) : restY
                Behavior on y {
                    NumberAnimation {
                        duration: volWin.mode === "slide" ? 340 : 0
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }
                // the sine bars render straight on the wallpaper; the pill
                // style keeps a card behind the level bar so it reads as a
                // pill rather than a bare line
                color: volWin.eq ? "transparent" : root.flySurface
                border.width: volWin.eq ? 0 : 1
                border.color: Qt.alpha(root.flyTh.accent, 0.33)
                antialiasing: true
                opacity: volWin.mode === "slide" ? 1 : (on ? 1 : 0)
                scale: volWin.mode === "pop" ? (on ? 1 : 0.8) : 1
                // unmap the window the instant the card has left, so no
                // blurred remnant lingers between the anim ending and the
                // fallback timer (fixes the "small square" on non-slide exits)
                onOpacityChanged: if (volOsd.leaving && opacity <= 0.02) volOsd.finishHide()
                onYChanged: if (volOsd.leaving && volWin.mode === "slide" && y >= parent.height - 2) volOsd.finishHide()
                Behavior on opacity {
                    NumberAnimation { duration: volWin.mode === "none" ? 0 : 200; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: volWin.mode === "none" ? 0 : 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }

                // optional numeric readout on the right edge; the bar/eq
                // content shifts left to make room. Fixed width so the layout
                // doesn't jitter as the digit count changes.
                Text {
                    id: volPct
                    visible: volWin.pct
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.flyFs(42)
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.vol * 100) + "%"
                    color: root.sinkMuted ? root.flyTh.muted : root.flyTh.fg
                    font { family: root.flyMono; pixelSize: root.flyFs(15); weight: Font.DemiBold }
                }
                readonly property real pctSpace: volWin.pct ? volPct.width + 16 : 0

                // "pill" style: a plain level bar
                Item {
                    visible: !volWin.eq
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -volCard.pctSpace / 2
                    width: parent.width - 60 - volCard.pctSpace
                    height: 8

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.alpha(root.flyTh.accent, 0.15)
                    }
                    Rectangle {
                        width: parent.width * Math.min(1, root.vol)
                        height: parent.height
                        radius: 4
                        color: root.sinkMuted ? Qt.alpha(root.flyTh.muted, 0.8) : root.flyTh.accent
                        Behavior on width {
                            NumberAnimation { duration: 70; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // sine-wave visualizer:
                // fixed-width bars (the design's 6px) mirrored above and below
                // a horizontal centre axis, following the flyout accent colour
                // (neutral when muted / 0). The card width sets how many bars
                // fit — resizing adds/removes bars at the design's ~26px pitch
                // instead of stretching them — and the row still spans edge to
                // edge like the pill's bar. No per-bar height Behaviors: the
                // ~90ms tick already paces the motion, and animating the bars
                // at 60fps kept the compositor re-blurring the backdrop every
                // frame, which showed up as input lag.
                Row {
                    id: eqRow
                    visible: volWin.eq
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -volCard.pctSpace / 2
                    readonly property real avail: volCard.width - 48 - volCard.pctSpace
                    readonly property real barW: 6
                    // bar pitch (px between bar centres) is fixed: dense
                    // enough to read as a waveform at any card width
                    readonly property real pitch: 14
                    readonly property int nBars: Math.max(2, Math.floor((avail + pitch - barW) / pitch))
                    spacing: nBars > 1 ? (avail - barW * nBars) / (nBars - 1) : 0

                    Repeater {
                        model: eqRow.nBars
                        Item {
                            id: eqBar
                            required property int index
                            width: eqRow.barW
                            height: 60
                            readonly property real half: volWin.volBarHalf(index, eqRow.nBars)
                            readonly property color barColor: (root.sinkMuted || root.vol <= 0)
                                ? root.flyTh.muted : root.flyTh.accent

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.verticalCenter
                                width: eqRow.barW
                                radius: 3
                                height: eqBar.half
                                color: eqBar.barColor
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.verticalCenter
                                width: eqRow.barW
                                radius: 3
                                height: eqBar.half
                                color: eqBar.barColor
                                opacity: 0.55
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- notification flyouts ----------
    function flyFs(px: int): int {
        return Math.round(px * cfg.notifFontScale);
    }

    // Own org.freedesktop.Notifications only while the flyout is enabled;
    // unloading releases the name for another daemon to claim.
    LazyLoader {
        active: root.flyoutOn("notifs")

        NotificationServer {
            bodySupported: true
            imageSupported: true
            onNotification: n => {
                n.tracked = true;
                flyNotifLoader.item?.accept(n);
            }
        }
    }

    // ---------- notification flyout (notifStyle "bubble" / "pill") ----------
    // One notification at a time. "bubble": an app-tinted circle pops in
    // below the top-right corner, pulses with an expanding ring, then a
    // compact card staggers its lines in to the left of it. "pill" is the
    // same card without the circle, tucked into the corner directly. Same-app arrivals replace the
    // visible card (it slides out and the new one fires next; if the card
    // hasn't appeared yet the content just swaps in place); other apps queue
    // and fire after the current one dismisses. The tint colour is the
    // dominant colour of the app icon (Canvas pixel average, cached per
    // icon), falling back to the flyout theme accent.
    LazyLoader {
        id: flyNotifLoader
        active: root.flyoutOn("notifs")

        PanelWindow {
            id: flyWin
            // hidden -> appear (circle pops in) -> pulse (overshoot + ring) ->
            // show (card staggers in, timeout runs) -> dismiss (lines stagger
            // out, card slides, circle shrinks) -> hidden
            property string phase: "hidden"
            // "pill" skips every bubble beat: no circle, no pulse phase, the
            // card claims the corner the circle vacated
            readonly property bool bubble: cfg.notifStyle !== "pill"
            property var current: null
            // snapshot of the notification's content: keeps the card intact
            // through the exit animation even if the sender closes the object
            property var view: ({ own: false, glyph: "", app: "", key: "", summary: "", body: "", image: "", icon: "", timeout: 0 })
            property var queue: []
            property int exitDir: 0
            // this dismissal keeps the bubble up until the card is gone
            property bool lingerOut: false
            // "simple" | "thumb" | "rich"; frozen when the card fires so a late
            // image probe can't reshape the visible card
            property string variant: "simple"
            property color nColor: root.notifTh.accent
            property var tintCache: ({})
            Behavior on nColor {
                ColorAnimation { duration: 220 }
            }

            visible: phase !== "hidden"
            anchors.top: true
            anchors.right: true
            // fixed size: everything animates inside (see the OSD architecture
            // note); sized for the widest card at max font scale plus ring bloom
            // and a fully expanded body
            implicitWidth: 720
            implicitHeight: 640
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "launcher-notif-fly"

            function accept(n) {
                // sender may retract a queued notification before it fires
                n.closed.connect(() => flyWin.unqueue(n));
                // fire straight away only when nothing is up AND nothing is
                // waiting (during the inter-notification gap the phase is hidden
                // but the queue must keep its order)
                if (phase === "hidden" && queue.length === 0) {
                    fire(n);
                    return;
                }
                // never hold two notifications of one app: replace in the queue
                for (let i = 0; i < queue.length; i++) {
                    if (appKey(queue[i]) === appKey(n)) {
                        const old = queue[i];
                        queue[i] = n;
                        old.expire();
                        return;
                    }
                }
                if (phase !== "hidden" && view.key === appKey(n)) {
                    if (phase === "appear" || phase === "pulse") {
                        // card isn't up yet: swap the content in place
                        const old = current;
                        snapshot(n);
                        if (old)
                            old.expire();
                        return;
                    }
                    // on screen: slide the current card out now, fire this next
                    queue.unshift(n);
                    if (phase === "show")
                        dismiss(0);
                    return; // already dismissing: it fires on finalize
                }
                if (queue.length >= 6)
                    queue.shift().expire();
                queue.push(n);
            }
            function unqueue(n) {
                const i = queue.indexOf(n);
                if (i >= 0)
                    queue.splice(i, 1);
            }
            // identity for replace-within-app: the name when given, else the
            // desktop-entry hint (Discord and friends send no appName)
            function appKey(n): string {
                return String(n.appName ?? "") || String(n.desktopEntry ?? "");
            }
            function snapshot(n) {
                current = n;
                let icon = root.iconUrl(String(n.appIcon ?? ""));
                let img = String(n.image ?? "");
                // some apps (e.g. niri screenshots) pass a file path in the icon
                // field: that is notification media, not an app icon
                if (icon.startsWith("file://")) {
                    if (!img)
                        img = icon;
                    icon = "";
                }
                // notify-send-style senders arrive with everything in the image
                // slot (appIcon empty), routed through the icon provider: a
                // file path there is notification media (decode it directly so
                // the aspect probe sees real dimensions), an icon name is the
                // app icon, not media
                if (img.startsWith("image://icon/")) {
                    const rest = img.slice("image://icon/".length);
                    if (rest.startsWith("/"))
                        img = "file://" + rest;
                    else {
                        if (!icon)
                            icon = img;
                        img = "";
                    }
                }
                // some senders (e.g. Discord) omit the app name and icon but set
                // the desktop-entry hint — recover both from the entry
                const de = String(n.desktopEntry ?? "");
                let appName = String(n.appName ?? "");
                if (de && (!appName || !icon)) {
                    const ent = Array.from(DesktopEntries.applications.values)
                        .find(e => e.id.toLowerCase() === de.toLowerCase());
                    if (ent) {
                        if (!appName)
                            appName = ent.name;
                        if (!icon && ent.icon)
                            icon = root.iconUrl(ent.icon);
                    }
                    if (!appName)
                        appName = de;
                }
                view = {
                    own: n.appName === "launcher",
                    glyph: root.notifGlyph(icon, String(n.summary ?? "")),
                    app: appName,
                    key: appKey(n),
                    summary: n.summary ?? "",
                    body: n.body ?? "",
                    image: img,
                    icon: icon,
                    timeout: n.expireTimeout
                };
                imgProbe.source = view.image;
                // "default" theme tints from the app icon (else the media
                // image); pinned themes use their accent everywhere
                const src = (root.notifIconTint && !view.own) ? (view.icon || view.image) : "";
                if (!src)
                    nColor = root.notifTh.accent;
                else if (tintCache[src] !== undefined)
                    nColor = tintCache[src];
                else {
                    nColor = root.notifTh.accent;
                    tint.src = src; // updates nColor when extracted
                }
            }
            function fire(n) {
                snapshot(n);
                exitDir = 0;
                phase = "appear";
                phaseTimer.restart();
            }
            // dir: swipe direction (-1 rubber-bands back before the drift),
            // 0 for timeout/bubble click/sender-close; all exit drifting right
            function dismiss(dir: int) {
                if (phase === "hidden" || phase === "dismiss")
                    return;
                exitDir = dir;
                phase = "dismiss";
                phaseTimer.restart();
            }
            function finalize() {
                const c = current;
                current = null;
                if (c)
                    c.expire();
                phase = "hidden";
                if (queue.length > 0)
                    gapTimer.restart();
            }
            function computeVariant(): string {
                if (!view.image)
                    return "simple";
                // wide images (16:10 and up: screenshots, photos) read best as a
                // full strip; squarer ones (avatars, album art) as a thumbnail
                if (imgProbe.status === Image.Ready && imgProbe.implicitHeight > 0
                    && imgProbe.implicitWidth / imgProbe.implicitHeight >= 1.6)
                    return "rich";
                return "thumb";
            }

            onPhaseChanged: {
                iconIn.stop();
                iconPop.stop();
                iconSettle.stop();
                iconOut.stop();
                iconOutDelay.stop();
                stagInAnim.stop();
                stagOutAnim.stop();
                wipeAnim.stop();
                switch (phase) {
                case "appear":
                    ringAnim.stop();
                    // pill: no circle to choreograph
                    // entry pose, applied instantly (inst gates the Behaviors)
                    fcard.inst = true;
                    fcard.stagIn = 0;
                    fcard.stagOut = 0;
                    fcard.imgWipe = 0;
                    fcard.cardO = 0;
                    fcard.cardYS = 0.92;
                    fcard.swipeX = 0;
                    fcard.expanded = false;
                    fcard.inst = false;
                    ring.scale = 1;
                    ring.opacity = 0;
                    if (flyWin.bubble)
                        iconIn.restart();
                    break;
                case "pulse":
                    iconPop.restart();
                    ringAnim.restart();
                    break;
                case "show":
                    variant = computeVariant();
                    if (flyWin.bubble)
                        iconSettle.restart();
                    fcard.cardO = 1;
                    fcard.cardYS = 1;
                    stagInAnim.restart();
                    wipeAnim.restart();
                    break;
                case "dismiss":
                    stagOutAnim.restart();
                    // hold the bubble until the card has fully left
                    flyWin.lingerOut = flyWin.bubble && fcard.cardO > 0;
                    if (flyWin.bubble) {
                        if (flyWin.lingerOut)
                            iconOutDelay.restart();
                        else
                            iconOut.restart();
                    }
                    // every dismissal fades with a gentle rightward drift; a
                    // left swipe rubber-bands back through rest to reach it
                    if (fcard.cardO > 0)
                        fcard.swipeX = (exitDir < 0 ? 0 : fcard.swipeX) + 18;
                    fcard.cardO = 0;
                    break;
                }
            }

            Timer {
                id: phaseTimer
                interval: flyWin.phase === "appear" ? (flyWin.bubble ? 430 : 60)
                    : flyWin.phase === "pulse" ? 210
                    : flyWin.lingerOut ? 640 : 340
                onTriggered: {
                    switch (flyWin.phase) {
                    case "appear":
                        if (flyWin.bubble) {
                            flyWin.phase = "pulse";
                            phaseTimer.restart();
                        } else {
                            flyWin.phase = "show"; // showTimer takes over
                        }
                        break;
                    case "pulse":
                        flyWin.phase = "show"; // showTimer takes over
                        break;
                    case "dismiss":
                        flyWin.finalize();
                        break;
                    }
                }
            }
            Timer {
                id: showTimer
                // a sender timeout of exactly 0 means "never expire" (spec): the
                // notification stays until clicked or swiped away
                interval: flyWin.view.timeout > 0 ? flyWin.view.timeout : cfg.notifTimeout
                running: flyWin.phase === "show" && !cardHover.hovered && flyWin.view.timeout !== 0
                onTriggered: flyWin.dismiss(0)
            }
            Timer {
                // small beat between one notification leaving and the next firing
                id: gapTimer
                interval: 160
                onTriggered: {
                    if (flyWin.queue.length > 0 && flyWin.phase === "hidden")
                        flyWin.fire(flyWin.queue.shift());
                }
            }
            // sender closed the on-screen notification — animate out
            Connections {
                target: flyWin.current
                ignoreUnknownSignals: true
                function onClosed() {
                    flyWin.current = null;
                    flyWin.dismiss(0);
                }
            }

            // aspect-ratio probe for the notification image; the icon-circle
            // phases (~630ms) cover the async load before the card needs it
            Image {
                id: imgProbe
                visible: false
                asynchronous: true
                // a big image can outlast the icon phases; when the probe lands
                // while the card is up, re-classify once so a wide screenshot
                // isn't stuck cropped into the thumbnail circle
                onStatusChanged: {
                    if (status === Image.Ready && flyWin.phase === "show")
                        flyWin.variant = flyWin.computeVariant();
                }
            }
            // dominant-colour extraction: the icon is drawn at 26x26 and averaged,
            // weighted by saturation and alpha, skipping near-white/black pixels;
            // the result is normalised into a band that reads on the dark card.
            // Parked off the window's left edge: a visible:false Canvas never
            // paints, an off-viewport one does.
            Canvas {
                id: tint
                property string src: ""
                x: -60
                y: 0
                width: 26
                height: 26
                renderStrategy: Canvas.Immediate
                renderTarget: Canvas.Image
                onSrcChanged: {
                    if (src)
                        loadImage(src);
                }
                onImageLoaded: requestPaint()
                onPaint: {
                    if (!src || !isImageLoaded(src))
                        return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.drawImage(src, 0, 0, width, height);
                    const d = ctx.getImageData(0, 0, width, height).data;
                    let r = 0, g = 0, b = 0, w = 0;
                    for (let i = 0; i < d.length; i += 4) {
                        const a = d[i + 3] / 255;
                        if (a < 0.4)
                            continue;
                        const mx = Math.max(d[i], d[i + 1], d[i + 2]);
                        const mn = Math.min(d[i], d[i + 1], d[i + 2]);
                        const lum = (mx + mn) / 510;
                        if (lum > 0.95 || lum < 0.06)
                            continue;
                        const sat = mx > 0 ? (mx - mn) / mx : 0;
                        const wt = a * (0.1 + sat * sat);
                        r += d[i] * wt;
                        g += d[i + 1] * wt;
                        b += d[i + 2] * wt;
                        w += wt;
                    }
                    let c = root.notifTh.accent;
                    if (w > 3) {
                        c = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1);
                        // pull into a visible band; leave true greys grey
                        c = (c.hslHue < 0 || c.hslSaturation < 0.12)
                            ? Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.min(0.75, Math.max(0.5, c.hslLightness)), 1)
                            : Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.5), Math.min(0.68, Math.max(0.45, c.hslLightness)), 1);
                    }
                    flyWin.tintCache[src] = c;
                    if (src === flyWin.view.icon || src === flyWin.view.image)
                        flyWin.nColor = c;
                    unloadImage(src);
                    src = "";
                }
            }

            // input only over the card and bubble while they are interactive
            mask: Region {
                x: fcard.x
                y: fcard.y
                width: flyWin.phase === "show" ? fcard.width : 0
                height: fcard.height
                regions: [
                    Region {
                        x: fIcon.x
                        y: fIcon.y
                        width: flyWin.bubble && flyWin.phase === "show" ? fIcon.width : 0
                        height: fIcon.height
                    }
                ]
            }
            // ── icon circle ──
            Item {
                id: fIcon
                visible: flyWin.bubble
                x: flyWin.width - width - 26
                y: 24
                width: 52
                height: 52
                scale: 0
                opacity: 0
                // grow-on-hover rides a transform so the phase animations own
                // `scale`; independent of the card's (separate handlers)
                readonly property bool hov: bubbleHover.hovered && flyWin.phase === "show"
                property real hoverS: hov ? 1.08 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: Scale {
                    origin.x: fIcon.width / 2
                    origin.y: fIcon.height / 2
                    xScale: fIcon.hoverS
                    yScale: fIcon.hoverS
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(flyWin.nColor, 1.18) }
                        GradientStop { position: 1; color: Qt.darker(flyWin.nColor, 1.22) }
                    }

                }
                Rectangle {
                    id: ring
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: 2
                    border.color: flyWin.nColor
                    opacity: 0
                }
                Image {
                    id: circleIcon
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    sourceSize: Qt.size(56, 56)
                    asynchronous: true
                    source: flyWin.view.own ? "" : flyWin.view.icon
                    visible: String(source) !== ""
                }
                // no app icon: the launcher's own glyphs stay; other apps get
                // the drawn bell fallback
                readonly property color inkC: "#f2f0ee"
                Text {
                    anchors.centerIn: parent
                    visible: !circleIcon.visible && flyWin.view.own
                    text: flyWin.view.glyph
                    color: fIcon.inkC
                    // optical parity with the drawn icon (~18px ink): glyph
                    // ink varies per codepoint, so the font size compensates
                    font {
                        family: root.flyMono
                        pixelSize: root.flyFs(text === "✱" ? 27 : text === "⧉" ? 25 : 23)
                        weight: Font.Bold
                    }
                }
                Canvas {
                    visible: !circleIcon.visible && !flyWin.view.own
                    anchors.centerIn: parent
                    width: 24
                    height: width
                    renderStrategy: Canvas.Immediate
                    renderTarget: Canvas.Image
                    property color ink: fIcon.inkC
                    onInkChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.save();
                        // the path is authored on a 24px grid; scale to item size
                        ctx.scale(width / 24, height / 24);
                        ctx.fillStyle = String(ink);
                        // bell: dome, flared skirt, clapper
                        ctx.beginPath();
                        ctx.arc(12, 9.2, 6, Math.PI, 0);
                        ctx.lineTo(18, 12.4);
                        ctx.quadraticCurveTo(19, 14.9, 20.5, 15.9);
                        ctx.lineTo(3.5, 15.9);
                        ctx.quadraticCurveTo(5, 14.9, 6, 12.4);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(12, 18.9, 2, 0, 2 * Math.PI);
                        ctx.fill();
                        ctx.restore();
                    }
                }
                HoverHandler {
                    id: bubbleHover
                }
                // clicking the bubble dismisses the notification
                MouseArea {
                    anchors.fill: parent
                    enabled: flyWin.phase === "show"
                    onClicked: flyWin.dismiss(0)
                }
            }

            // icon keyframes ported from the reference CSS
            SequentialAnimation {
                id: iconIn
                ParallelAnimation {
                    NumberAnimation { target: fIcon; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: fIcon; property: "scale"; to: 1.18; duration: 300; easing.type: Easing.OutCubic }
                }
                NumberAnimation { target: fIcon; property: "scale"; to: 0.95; duration: 100; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1; duration: 100; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation {
                id: iconPop
                NumberAnimation { target: fIcon; property: "scale"; to: 1.32; duration: 170; easing.type: Easing.OutCubic }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.1; duration: 120; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.18; duration: 95; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.1; duration: 95; easing.type: Easing.InOutQuad }
            }
            NumberAnimation {
                id: iconSettle
                target: fIcon
                property: "scale"
                to: 1.1
                duration: 300
                easing.type: Easing.InOutQuad
            }
            ParallelAnimation {
                id: iconOut
                NumberAnimation { target: fIcon; property: "scale"; to: 0; duration: 260; easing.type: Easing.InBack }
                NumberAnimation { target: fIcon; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InCubic }
            }
            Timer {
                // bubble hold on dismiss: fires the icon exit once the card's
                // slide/fade (~300ms) has finished
                id: iconOutDelay
                interval: 300
                onTriggered: iconOut.restart()
            }
            ParallelAnimation {
                id: ringAnim
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.4; duration: 600; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.65; to: 0; duration: 600; easing.type: Easing.OutCubic }
            }
            // shared clocks for the per-line staggers (ms timelines; each line
            // derives its own eased window from them in lp/lq below)
            NumberAnimation { id: stagInAnim; target: fcard; property: "stagIn"; from: 0; to: 650; duration: 650 }
            NumberAnimation { id: stagOutAnim; target: fcard; property: "stagOut"; from: 0; to: 300; duration: 300 }
            SequentialAnimation {
                id: wipeAnim
                PauseAnimation { duration: 100 }
                NumberAnimation { target: fcard; property: "imgWipe"; from: 0; to: 1; duration: 500; easing.type: Easing.OutQuint }
            }

            // ── card ──
            Rectangle {
                id: fcard
                property real stagIn: 0
                property real stagOut: 0
                property real imgWipe: 0
                property real cardO: 0
                property real cardYS: 0.92
                property real swipeX: 0
                property real grabX: 0
                property bool dragging: false
                property bool inst: false
                // click-to-expand for a body longer than the collapsed clip
                property bool expanded: false
                // whether a tap can reveal more (drives the chevron + ellipses)
                readonly property bool expandable: bodyClip.truncated || subWrap.truncated

                // per-line enter/exit progress: 380ms windows offset 90ms apart
                // in (quint-out), 180ms offset 40ms apart out (quad-in)
                function lp(i: int): real {
                    const p = Math.max(0, Math.min(1, (stagIn - i * 90) / 380));
                    return 1 - Math.pow(1 - p, 4);
                }
                function lq(i: int): real {
                    const q = Math.max(0, Math.min(1, (stagOut - i * 40) / 180));
                    return q * q;
                }
                function lineO(i: int): real {
                    return lp(i) * (1 - lq(i));
                }
                function lineY(i: int): real {
                    return 10 * (1 - lp(i)) - 6 * lq(i);
                }

                readonly property bool rich: flyWin.variant === "rich"
                readonly property bool thumb: flyWin.variant === "thumb"
                readonly property int lBase: rich ? 1 : 0
                readonly property real stripH: rich ? root.flyFs(104) : 0
                // a short single-line body renders as a sub line; anything longer
                // becomes a divided body block (they are mutually exclusive)
                readonly property bool bodyAsSub: flyWin.view.body !== "" && flyWin.view.body.length <= 60
                    && flyWin.view.body.indexOf("\n") < 0

                // natural content width clamped to a compact range; rich is fixed
                readonly property real natW: 12 + (thumb ? 50 : 0) + 34 + Math.max(
                    appRow.implicitWidth,
                    headText.implicitWidth,
                    subWrap.visible ? subText.implicitWidth : 0,
                    bodyBlock.visible ? bodyText2.implicitWidth : 0)
                width: rich ? root.flyFs(336)
                    : Math.min(root.flyFs(344), Math.max(root.flyFs(210), Math.ceil(natW)))
                height: stripH + contentBox.height + 22
                radius: 16
                antialiasing: true
                color: root.flySurface
                visible: flyWin.phase === "show" || flyWin.phase === "dismiss"
                opacity: cardO
                // grow-on-hover, independent of the bubble's (separate handlers)
                readonly property bool hov: cardHover.hovered && flyWin.phase === "show"
                property real hoverS: hov ? 1.025 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: [
                    Scale {
                        origin.x: fcard.width / 2
                        origin.y: fcard.height / 2
                        yScale: fcard.cardYS
                    },
                    Scale {
                        // top-pinned: a center origin tracks the animated height
                        // during expand and creeps the card upward
                        origin.x: fcard.width / 2
                        origin.y: 0
                        xScale: fcard.hoverS
                        yScale: fcard.hoverS
                    }
                ]

                // bubble: the card hangs left of the circle, its top at the
                // circle's vertical centre. pill: no circle, so the card
                // tucks into the corner the circle would have occupied.
                readonly property real restX: flyWin.bubble
                    ? fIcon.x - 10 - width
                    : flyWin.width - width - 26
                x: restX + swipeX
                y: flyWin.bubble ? fIcon.y + fIcon.height / 2 : 24
                Behavior on swipeX {
                    enabled: !fcard.inst && !fcard.dragging
                    NumberAnimation {
                        duration: 300
                        easing.type: flyWin.phase === "dismiss" ? Easing.OutCubic : Easing.OutBack
                        easing.overshoot: 1.15
                    }
                }
                Behavior on cardO {
                    enabled: !fcard.inst
                    NumberAnimation {
                        duration: flyWin.phase === "dismiss" ? 260 : 320
                        easing.type: flyWin.phase === "dismiss" ? Easing.InCubic : Easing.OutCubic
                    }
                }
                Behavior on cardYS {
                    enabled: !fcard.inst
                    NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                }

                // rich media strip: left-to-right wipe reveal. The inner clipper
                // overshoots the strip height so its bottom rounding falls below
                // the image (top corners round, bottom edge square).
                Item {
                    visible: fcard.rich
                    x: 0
                    y: 0
                    width: Math.round(fcard.width * fcard.imgWipe)
                    height: fcard.stripH
                    clip: true
                    opacity: 1 - fcard.lq(0)

                    ClippingRectangle {
                        width: fcard.width
                        height: fcard.stripH + 16
                        radius: 16
                        color: Qt.alpha(flyWin.nColor, 0.2)

                        Image {
                            width: fcard.width
                            height: fcard.stripH
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: fcard.rich ? flyWin.view.image : ""
                        }
                    }
                }

                Row {
                    id: contentBox
                    x: 12
                    y: fcard.stripH + 11
                    width: fcard.width - 12 - 34
                    spacing: 10

                    ClippingRectangle {
                        visible: fcard.thumb
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 20
                        color: Qt.alpha(flyWin.nColor, 0.25)
                        border.width: 2
                        border.color: Qt.alpha(flyWin.nColor, 0.4)
                        opacity: fcard.lineO(0)
                        transform: Translate { y: fcard.lineY(0) }

                        Image {
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(80, 80)
                            source: fcard.thumb ? flyWin.view.image : ""
                        }
                    }

                    Column {
                        width: parent.width - (fcard.thumb ? 50 : 0)
                        spacing: 3

                        Row {
                            id: appRow
                            spacing: 5
                            opacity: fcard.lineO(fcard.lBase)
                            transform: Translate { y: fcard.lineY(fcard.lBase) }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                antialiasing: true
                                color: flyWin.nColor
                            }
                            Text {
                                text: flyWin.view.app || "notification"
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(10); letterSpacing: 2; capitalization: Font.AllUppercase }
                            }
                        }
                        Text {
                            id: headText
                            visible: text.length > 0
                            width: parent.width
                            text: flyWin.view.summary
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: root.notifTh.fg
                            font { family: root.flyMono; pixelSize: root.flyFs(13); weight: Font.DemiBold }
                            opacity: fcard.lineO(fcard.lBase + 1)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 1) }
                        }
                        // short body: an elided single line that, when it doesn't
                        // fit, expands to the full wrapped text on tap (the elided
                        // and wrapped copies crossfade inside an animated clip)
                        Item {
                            id: subWrap
                            visible: fcard.bodyAsSub
                            width: parent.width
                            readonly property bool truncated: fcard.bodyAsSub && subText.truncated
                            height: visible ? (fcard.expanded && truncated ? subFull.paintedHeight : subText.implicitHeight) : 0
                            clip: true
                            opacity: fcard.lineO(fcard.lBase + 2)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 2) }
                            Behavior on height {
                                enabled: flyWin.phase === "show"
                                NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                            }

                            Text {
                                id: subText
                                width: parent.width
                                text: fcard.bodyAsSub ? flyWin.view.body : ""
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                opacity: fcard.expanded && subWrap.truncated ? 0 : 1
                                Behavior on opacity {
                                    NumberAnimation { duration: 180 }
                                }
                            }
                            Text {
                                id: subFull
                                width: parent.width
                                text: subText.text
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                opacity: 1 - subText.opacity
                                visible: opacity > 0
                            }
                        }
                        Column {
                            id: bodyBlock
                            visible: flyWin.view.body !== "" && !fcard.bodyAsSub
                            width: parent.width
                            topPadding: 5
                            spacing: 6
                            opacity: fcard.lineO(fcard.lBase + 2)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 2) }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.alpha(root.notifTh.fg, 0.09)
                            }
                            // body clips to 3 lines; tapping the card animates
                            // the clip open (text is fully laid out throughout,
                            // so the reveal is a smooth height change)
                            Item {
                                id: bodyClip
                                width: parent.width
                                clip: true
                                readonly property real lineH: bodyText2.lineCount > 0 ? bodyText2.paintedHeight / bodyText2.lineCount : root.flyFs(15)
                                readonly property real collapsedH: Math.min(bodyText2.paintedHeight, Math.ceil(lineH * 3))
                                readonly property bool truncated: bodyText2.paintedHeight > collapsedH + 1
                                height: fcard.expanded ? bodyText2.paintedHeight : collapsedH
                                Behavior on height {
                                    enabled: flyWin.phase === "show"
                                    NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                                }

                                Text {
                                    id: bodyText2
                                    width: parent.width
                                    text: bodyBlock.visible ? flyWin.view.body : ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 24
                                    textFormat: Text.PlainText
                                    color: root.notifTh.muted
                                    font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                }
                                // ellipses over the clipped last line; gone once
                                // expanded (card-coloured backing masks the text)
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: bodyEll.implicitWidth + 10
                                    height: bodyEll.implicitHeight
                                    color: fcard.color
                                    opacity: bodyClip.truncated && !fcard.expanded ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 180 }
                                    }
                                    Text {
                                        id: bodyEll
                                        anchors.right: parent.right
                                        text: "…"
                                        color: root.notifTh.muted
                                        font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                    }
                                }
                            }
                        }
                    }
                }

                // expand-state chevron: fades in only while the card is hovered
                // and there is more to show. Drawn on a Canvas so up and down
                // share exact ink bounds (glyphs sit at different heights in the
                // em box and visually jumped); flipping direction morphs the
                // arms through a flat line into the opposite point.
                Item {
                    id: chev
                    z: 5
                    // pinned to the card's top-right corner (over the media
                    // strip when there is one), inset to match the app-row
                    // dot's padding on the opposite side
                    x: fcard.width - width - 12
                    y: 12
                    width: 14
                    height: 14
                    // 1 = pointing down (can expand), -1 = pointing up
                    property real morph: fcard.expanded ? -1 : 1
                    Behavior on morph {
                        enabled: flyWin.phase === "show" && !fcard.inst
                        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                    }
                    opacity: (fcard.expandable || fcard.expanded) && cardHover.hovered && flyWin.phase === "show" ? 0.9 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Canvas {
                        anchors.fill: parent
                        renderStrategy: Canvas.Immediate
                        renderTarget: Canvas.Image
                        property color col: root.notifTh.muted
                        property real m: chev.morph
                        onColChanged: requestPaint()
                        onMChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = String(col);
                            ctx.lineWidth = 1.6;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(3.5, 7.25 - 1.75 * m);
                            ctx.lineTo(7, 7.25 + 1.75 * m);
                            ctx.lineTo(10.5, 7.25 - 1.75 * m);
                            ctx.stroke();
                        }
                    }
                }
                HoverHandler {
                    id: cardHover
                }
                // swipe-dismiss: DragHandler measures in scene coordinates,
                // so the card moving under the cursor doesn't feed the drag
                DragHandler {
                    id: fdrag
                    enabled: flyWin.phase === "show"
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            fcard.dragging = true;
                            fcard.grabX = centroid.scenePosition.x - fcard.swipeX;
                        } else {
                            fcard.dragging = false;
                            if (flyWin.phase === "show") {
                                if (fcard.swipeX > 60)
                                    flyWin.dismiss(1);
                                else if (fcard.swipeX < -60)
                                    flyWin.dismiss(-1);
                                else
                                    fcard.swipeX = 0; // springs home
                            }
                        }
                    }
                    onCentroidChanged: {
                        if (active) {
                            const raw = centroid.scenePosition.x - fcard.grabX;
                            // either direction dismisses; both share the same
                            // light asymptotic drag (cap ~140px) so the card
                            // feels equally weighted left and right
                            fcard.swipeX = 140 * raw / (140 + Math.abs(raw));
                        }
                    }
                }
                TapHandler {
                    // a tap (not a drag) expands the clipped body
                    onTapped: {
                        if (fcard.expandable || fcard.expanded)
                            fcard.expanded = !fcard.expanded;
                    }
                }
            }
        }
    }
}
