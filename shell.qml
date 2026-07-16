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
        property bool includeFollow: false
        width: 780
        height: 86
        readonly property string current: cfgKey === "theme" ? cfg.theme : cfg.flyTheme
        function setVal(v: string) {
            if (cfgKey === "theme")
                cfg.theme = v;
            else
                cfg.flyTheme = v;
            root.saveSettings();
        }

        SLabel {
            anchors.left: parent.left
            anchors.verticalCenter: undefined
            y: 6
            text: "Color theme"
        }
        SReset {
            key: tr.cfgKey
            anchors.right: parent.right
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 34
            spacing: 8

            Repeater {
                model: (tr.includeFollow
                    ? [{ id: "follow", name: "Follow", accent: "", fg: "", muted: "" }]
                    : []).concat(root.themes)

                Rectangle {
                    id: trCard
                    required property var modelData
                    readonly property var pal: modelData.id === "follow" ? root.activeTheme
                        : modelData.id === "dynamic" ? root.dynTheme : modelData
                    readonly property bool active: tr.current === modelData.id
                    width: tr.includeFollow ? 80 : 88
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

    component SettingRow: Item {
        id: sr
        property string key
        property string label
        property int valueWidth: 90
        width: 780
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

    // Pixel-accurate rounded-rect blur region: the protocol only takes rect
    // unions, but ellipse child regions decompose into exact 1px scanlines
    // (same mechanism as the launcher's circular reveal), so the blur edge
    // follows the corner curve with no visible stair-steps.
    component RoundedBlur: Region {
        id: rb
        property real rx: 0
        property real ry: 0
        property real rw: 100
        property real rh: 50
        property real rr: 18
        // Effective radius never exceeds half the box, so a card shrinking to
        // nothing (fade/scale exit) collapses to a genuine ~1px region instead
        // of leaving the min-radius corner ellipses behind as a small blurred
        // square. The body height is clamped to ≥1 so the region is never
        // empty (an empty blurRegion means "blur the whole surface").
        readonly property real er: Math.max(0, Math.min(rr, rw / 2, rh / 2))
        x: rx
        y: ry + er
        width: rw
        height: Math.max(1, rh - 2 * er)
        regions: [
            Region { x: rb.rx + rb.er; y: rb.ry; width: Math.max(0, rb.rw - 2 * rb.er); height: rb.er },
            Region { x: rb.rx + rb.er; y: rb.ry + rb.rh - rb.er; width: Math.max(0, rb.rw - 2 * rb.er); height: rb.er },
            Region { shape: RegionShape.Ellipse; x: rb.rx; y: rb.ry; width: 2 * rb.er; height: 2 * rb.er },
            Region { shape: RegionShape.Ellipse; x: rb.rx + rb.rw - 2 * rb.er; y: rb.ry; width: 2 * rb.er; height: 2 * rb.er },
            Region { shape: RegionShape.Ellipse; x: rb.rx; y: rb.ry + rb.rh - 2 * rb.er; width: 2 * rb.er; height: 2 * rb.er },
            Region { shape: RegionShape.Ellipse; x: rb.rx + rb.rw - 2 * rb.er; y: rb.ry + rb.rh - 2 * rb.er; width: 2 * rb.er; height: 2 * rb.er }
        ]
    }

    // Per-card input mask region: the card's bbox while it is active.
    component NotifMaskRegion: Region {
        property var c: null
        x: c ? c.x : 0
        y: c ? c.y : 0
        width: c && c.active ? c.width : 0
        height: c && c.active ? c.height : 0
    }
    // Per-card rounded blur region, tracking the card's animated pose. rr is
    // un-clamped at the low end so it collapses to ~1px on fade/scale exit
    // instead of leaving a small square; inactive slots stay a 1px region so
    // the union is never empty (which would blur the whole surface).
    component NotifBlurRegion: RoundedBlur {
        property var c: null
        readonly property real s: c && c.active ? (c.mode === "expand" ? c.scale : 1) * c.opacity : 0
        rx: c ? c.x + (c.width - c.width * s) / 2 + 2 : 0
        ry: c ? c.y + 2 : 0
        rw: c && c.active ? Math.max(1, c.width * s - 4) : 1
        rh: c && c.active ? Math.max(1, c.height * s - 4) : 1
        rr: 18 * s
    }

    // One notification card: a free-floating pill that slides/expands in,
    // stacks below its newer siblings, and is swipeable in both directions.
    // Only ever used as a cardRep delegate.
    component NotifCard: Rectangle {
        id: nc
        required property int index
        property var rep: null
        property var notifObj: null
        // snapshot of the notification's content: keeps the card intact
        // through the exit animation even if the sender closes the object
        property var view: ({ own: false, glyph: "", app: "", summary: "", body: "", image: "", appIcon: "", timeout: 0 })
        property bool active: false
        property bool leaving: false
        property bool expanded: false
        property int seq: 0
        property bool inst: false // apply poses without animating
        property real cardScale: 1
        property real cardOpacity: 1
        // horizontal offset from rest: entry/exit/drag. Driven by swipe
        // (scene coords, so the card moving doesn't feed back into the drag).
        property real swipeX: 0
        property real grabX: 0
        // gates the body-height animation on: false during spawn so the
        // collapsed body appears instantly (no expand-on-spawn), true shortly
        // after so a click animates the expand
        property bool expandReady: false
        readonly property string mode: cfg.notifAnim

        function assign(n) {
            notifObj = n;
            const ic = String(n.appIcon ?? "");
            const sl = String(n.summary ?? "").toLowerCase();
            view = {
                own: n.appName === "launcher",
                // the icon name may arrive resolved (path/url), so match loosely
                glyph: ic.includes("error") || sl.includes("fail") || sl.includes("not found") ? "!"
                    : ic.includes("copy") || sl.includes("copied") ? "⧉" : "✱",
                app: n.appName ?? "",
                summary: n.summary ?? "",
                body: n.body ?? "",
                image: String(n.image ?? ""),
                appIcon: ic,
                timeout: n.expireTimeout
            };
            seq = ++root.notifSeq;
            expanded = false;
            leaving = false;
            expandReady = false;
            expandReadyTimer.restart();
            exitTimer.stop();
            // entry pose by style, applied instantly, then released so the
            // Behaviors animate from the pose to the rest state
            inst = true;
            swipeX = mode === "slide" ? width + 40 : 0;
            cardScale = mode === "expand" ? 0 : 1;
            cardOpacity = (mode === "fade" || mode === "none") ? 0 : 1;
            active = true;
            Qt.callLater(() => {
                inst = false;
                swipeX = 0;
                cardScale = 1;
                cardOpacity = 1;
            });
        }
        // dir: -1 swiped left, 1 swiped right, 0 timeout/programmatic
        function dismiss(dir: int) {
            if (leaving || !active)
                return;
            leaving = true;
            expanded = false;
            if (dir > 0 || (dir === 0 && mode === "slide"))
                swipeX = width + 60;
            else if (dir < 0) {
                swipeX = -(restX + width + 20);
                cardOpacity = 0;
            } else if (mode === "expand")
                cardScale = 0;
            else
                cardOpacity = 0;
            exitTimer.restart();
        }
        function finalize() {
            exitTimer.stop();
            if (notifObj)
                notifObj.expire();
            notifObj = null;
            active = false;
            leaving = false;
            expanded = false;
        }

        Timer {
            id: exitTimer
            interval: 340
            onTriggered: nc.finalize()
        }
        Timer {
            id: expandReadyTimer
            interval: 500
            onTriggered: nc.expandReady = true
        }
        Timer {
            // per-card timeout, paused only while the pointer is over the card
            // (hovering to read it); leaving the card restarts the countdown.
            interval: nc.view.timeout > 0 ? nc.view.timeout : cfg.notifTimeout
            running: nc.active && !nc.leaving && !hover.hovered
            onTriggered: nc.dismiss(0)
        }
        // sender closed it (or another daemon action) — animate out
        Connections {
            target: nc.notifObj
            ignoreUnknownSignals: true
            function onClosed() {
                nc.notifObj = null;
                if (nc.active && !nc.leaving)
                    nc.dismiss(0);
            }
        }

        visible: active
        width: cfg.notifWidth
        readonly property real cardH: Math.max(66, contentRow.height + 26)
        height: cardH
        radius: 20
        color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, cfg.flyOpacity)
        border.width: 1
        border.color: Qt.alpha(root.flyTh.accent, 0.33)
        transformOrigin: Item.Top
        scale: cardScale
        opacity: cardOpacity

        // x = restX + swipeX. The Behavior lives on swipeX (not x) so x snaps
        // when restX changes as the layer surface settles its width — that
        // width settle was what made every entry read as a slide regardless
        // of the animation setting.
        readonly property real restX: parent.width - cfg.notifWidth - 16
        x: restX + swipeX
        Behavior on swipeX {
            enabled: !nc.inst && !dragHandler.active
            NumberAnimation {
                duration: nc.mode === "none" ? 0 : 300
                easing.type: nc.leaving ? Easing.OutCubic : Easing.OutBack
                easing.overshoot: 1.15
            }
        }
        // newest card on top; older active ones stack downward and reflow
        y: {
            let yy = 14;
            if (nc.rep)
                for (let i = 0; i < nc.rep.count; i++) {
                    const o = nc.rep.itemAt(i);
                    if (o && o !== nc && o.active && o.seq > nc.seq)
                        yy += o.cardH + 12;
                }
            return yy;
        }
        Behavior on y {
            enabled: !nc.inst
            NumberAnimation { duration: nc.mode === "none" ? 0 : 260; easing.type: Easing.OutCubic }
        }
        Behavior on cardScale {
            enabled: !nc.inst
            NumberAnimation {
                duration: nc.mode === "none" ? 0 : 320
                easing.type: nc.leaving ? Easing.InCubic : Easing.OutBack
                easing.overshoot: 1.3
            }
        }
        Behavior on cardOpacity {
            enabled: !nc.inst
            NumberAnimation { duration: nc.mode === "none" ? 0 : 220; easing.type: Easing.OutCubic }
        }

        Row {
            id: contentRow
            x: 18
            y: 13
            width: parent.width - 36
            spacing: 14

            // the launcher's own notifications use themed glyph badges;
            // other apps get their image or icon-theme icon
            Rectangle {
                visible: nc.view.own
                width: visible ? 44 : 0
                height: 44
                radius: 22
                color: Qt.alpha(root.flyTh.accent, 0.14)
                border.width: 1
                border.color: Qt.alpha(root.flyTh.accent, 0.4)

                Text {
                    anchors.centerIn: parent
                    text: nc.view.glyph
                    color: root.flyTh.accent
                    font { family: root.flyMono; pixelSize: root.notifFs(20); weight: Font.Bold }
                }
            }
            Image {
                id: notifImage
                visible: !nc.view.own && String(source) !== ""
                width: visible ? 48 : 0
                height: 48
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                source: {
                    const v = nc.view;
                    if (v.image)
                        return v.image;
                    if (!v.appIcon)
                        return "";
                    // some apps (e.g. niri screenshots) pass a file path in
                    // the icon field instead of an icon name
                    if (v.appIcon.startsWith("file://"))
                        return v.appIcon;
                    if (v.appIcon.startsWith("/"))
                        return "file://" + v.appIcon;
                    return Quickshell.iconPath(v.appIcon, true);
                }
            }

            Column {
                width: contentRow.width - (nc.view.own ? 58 : (notifImage.visible ? 62 : 0))
                spacing: 4

                Text {
                    visible: text.length > 0
                    text: nc.view.app
                    color: root.flyTh.muted
                    font { family: root.flyMono; pixelSize: root.notifFs(11); letterSpacing: 2; capitalization: Font.AllUppercase }
                }
                Text {
                    visible: text.length > 0
                    width: parent.width
                    text: nc.view.summary
                    wrapMode: Text.Wrap
                    // fixed cap so the title never reflows on expand (line-count
                    // changes can't animate and would look like a jump)
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: root.flyTh.fg
                    font { family: root.flyMono; pixelSize: root.notifFs(14); weight: Font.DemiBold }
                }
                // body clips to ~4 lines; clicking the card grows the clip to
                // the full text. The text is fully laid out at all times and
                // only the clip height animates, so it reveals smoothly with
                // no reflow jump.
                Item {
                    id: bodyClip
                    width: parent.width
                    clip: true
                    visible: bodyText.text.length > 0
                    readonly property real lineH: bodyText.lineCount > 0 ? bodyText.paintedHeight / bodyText.lineCount : root.notifFs(16)
                    readonly property real collapsedH: Math.min(bodyText.paintedHeight, Math.ceil(lineH * 4))
                    height: visible ? (nc.expanded ? bodyText.paintedHeight : collapsedH) : 0
                    // animate only a user-initiated expand, not the initial
                    // layout on spawn (which would look like it expands itself)
                    Behavior on height {
                        enabled: nc.expandReady
                        NumberAnimation { duration: 360; easing.type: Easing.InOutCubic }
                    }

                    Text {
                        id: bodyText
                        width: parent.width
                        text: nc.view.body
                        wrapMode: Text.Wrap
                        maximumLineCount: 24
                        textFormat: Text.PlainText
                        color: root.flyTh.muted
                        font { family: root.flyMono; pixelSize: root.notifFs(12) }
                    }
                }
            }
        }

        // Pointer handlers, not a MouseArea with drag.target: dragging the
        // card by a proxy that is itself a child of the (moving) card fed
        // back into the drag and stalled it. DragHandler measures the swipe
        // in scene coordinates, so the card moving under the cursor doesn't
        // affect the delta; TapHandler gives a clean click that the drag
        // gesture doesn't swallow.
        HoverHandler {
            id: hover
        }
        DragHandler {
            id: dragHandler
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    nc.grabX = centroid.scenePosition.x - nc.swipeX;
                } else if (!nc.leaving) {
                    if (nc.swipeX > 90)
                        nc.dismiss(1);
                    else if (nc.swipeX < -90)
                        nc.dismiss(-1);
                    else
                        nc.swipeX = 0; // springs home
                }
            }
            onCentroidChanged: {
                if (active)
                    nc.swipeX = centroid.scenePosition.x - nc.grabX;
            }
        }
        TapHandler {
            // a tap (not a drag) toggles the expanded body
            onTapped: nc.expanded = !nc.expanded
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
            property var keybinds: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S" })
            // flyouts (volume + notification OSDs)
            property string flyTheme: "amber"
            property real flyOpacity: 0.4
            property string flyFontFamily: ""
            property var flyouts: ({ volume: true, notifs: true })
            property real volWidth: 340
            property string volAnim: "slide"
            property int volTimeout: 1500
            property int notifTimeout: 5000
            property real notifFontScale: 1.0
            property real notifWidth: 420
            property string notifAnim: "expand"
            property int notifMax: 3
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
    readonly property string mono: cfg.fontFamily || "JetBrains Mono"

    // OSDs can follow the launcher theme or pin their own
    function themeColors(sel) {
        if (sel && sel !== "follow") {
            if (sel === "dynamic")
                return dynTheme;
            const t = themes.find(t => t.id === sel);
            if (t)
                return t;
        }
        return activeTheme;
    }
    readonly property var flyTh: themeColors(cfg.flyTheme)
    readonly property string flyMono: cfg.flyFontFamily || mono
    function flyoutOn(name: string): bool {
        return (cfg.flyouts ?? {})[name] !== false;
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

    Component.onCompleted: {
        // heal settings from the old list-style clipboard pane
        if (cfg.clipsRows > 4 || cfg.clipsRows < 2) {
            cfg.clipsRows = 3;
            saveSettings();
        }
        // the "follow" flyout theme option was removed; pin to the launcher
        // theme it was following at the time
        if (cfg.flyTheme === "follow") {
            cfg.flyTheme = root.themes.some(t => t.id === cfg.theme) ? cfg.theme : "amber";
            saveSettings();
        }
    }

    Process {
        id: matugenProc
        // Needed at startup only for the dynamic theme; otherwise deferred
        // until the settings pane wants the preview — its output triggers a
        // theme-color rebind of every tile, which would hitch the intro.
        running: cfg.theme === "dynamic"
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
                } catch (e) {
                    if (cfg.theme === "dynamic")
                        root.notifyError("Dynamic theme failed", "matugen returned no palette for the current wallpaper");
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
            if (cfg.theme === "dynamic") {
                matugenProc.running = false;
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
        readonly property var paneOrder: ["clock", "apps", "walls", "clips"]
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
        function cyclePane(dir: int) {
            // inside settings the cycle keybinds walk the settings tabs
            if (pane === "settings") {
                const tabs = ["general", "flyouts"];
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
            appLaunch.command = ["bash", "-c", 'command -v gtk-launch >/dev/null || exit 42; exec gtk-launch "$1"', "_", entry.id];
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
                notify-send -a launcher -i edit-copy "Copied to clipboard" "$body"
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
        readonly property var bindDefaults: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S" })
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
                    if (!matugenProc.running && cfg.theme !== "dynamic")
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

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, cfg.dimOpacity)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (win.expandedClip)
                        win.collapseClip();
                    else
                        input.forceActiveFocus();
                }
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
                                            source: {
                                                const name = cell.shownEntry ? cell.shownEntry.icon : "";
                                                if (!name)
                                                    return "";
                                                // some entries put a file path in Icon=
                                                return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
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
                readonly property int tabIdx: win.settingsTab === "general" ? 0 : 1
                anchors.centerIn: parent
                width: 860
                height: 26 + settingsHeader.height + 18 + tabViewport.height + 26
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
                                { id: "flyouts", label: "Flyouts" }
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
                    height: Math.max(settingsCol.height, flyCol.height)

                // flyouts tab: volume + notification OSDs
                Column {
                    id: flyCol
                    x: 20 + (1 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.ad(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    SettingRow { key: "volWidth"; label: "Volume size" }
                    SettingRow { key: "volAnim"; label: "Volume animation"; valueWidth: 130 }
                    SettingRow { key: "volTimeout"; label: "Volume timeout" }
                    SettingRow { key: "notifWidth"; label: "Notification size" }
                    SettingRow { key: "notifTimeout"; label: "Notification timeout" }
                    SettingRow { key: "notifFontScale"; label: "Notification font size" }
                    SettingRow { key: "notifAnim"; label: "Notification animation"; valueWidth: 130 }
                    SettingRow { key: "notifMax"; label: "Max notifications" }
                    SettingRow { key: "flyFontFamily"; label: "Font"; valueWidth: 260 }
                    SettingRow { key: "flyOpacity"; label: "Opacity" }

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

                    ThemeRow { cfgKey: "flyTheme" }
                }

                Column {
                    id: settingsCol
                    x: 20 + (0 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.ad(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

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
                                    width: srow.modelData.key === "iconTheme" || srow.modelData.key === "fontFamily" ? 260
                                        : srow.modelData.key === "revealOrigin" ? 150 : 90
                                }
                                SBtn {
                                    label: "›"
                                    onPressed: win.adjustSetting(srow.modelData.key, 1)
                                }
                                SReset {
                                    key: srow.modelData.key
                                }
                            }
                        }
                    }

                    // enabled pages
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
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            spacing: 8
                            height: parent.height

                            Repeater {
                                model: ["clock", "apps", "walls", "clips"]

                                Item {
                                    id: pageChip
                                    required property var modelData
                                    readonly property bool on: (cfg.pages ?? {})[modelData] !== false
                                    width: pageBox.width + 6 + pageChipText.implicitWidth
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter

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
                                        id: pageChipText
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: pageBox.right
                                        anchors.leftMargin: 6
                                        text: pageChip.modelData
                                        color: pageChip.on ? root.fg : root.muted
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: win.togglePage(pageChip.modelData)
                                    }
                                }
                            }
                        }
                    }

                    // color themes with palette previews
                    ThemeRow {
                        cfgKey: "theme"
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
                    Text {
                        text: "$WALL = selected image, $BLUR = blurred variant (auto-generated)"
                        color: Qt.alpha(root.muted, 0.7)
                        font { family: root.mono; pixelSize: root.fs(11) }
                    }

                    // keybinds
                    Repeater {
                        model: [
                            { action: "cycle", label: "Cycle pages" },
                            { action: "reverseCycle", label: "Cycle pages (reverse)" },
                            { action: "launch", label: "Launch / apply" },
                            { action: "settings", label: "Settings" },
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

                    Text {
                        text: "icon theme applies on next launch"
                        color: Qt.alpha(root.muted, 0.7)
                        font { family: root.mono; pixelSize: root.fs(11) }
                    }
                }
                } // tabViewport
            }

            // Settings button: pops up when hovering the bottom-right corner
            MouseArea {
                id: settingsHover
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 180
                height: 180
                hoverEnabled: true
                onClicked: win.toggleSettings()

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

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: root.fg
                        font { pixelSize: root.fs(26) }
                    }
                }
            }

            // Scroll wheel walks the grids (down the column, across pages).
            // Topmost sibling: MouseAreas below (background, tiles) consume
            // wheel events, so the handler must intercept before them. An
            // Item with only a WheelHandler doesn't block clicks or hover.
            Item {
                anchors.fill: parent
                WheelHandler {
                    property real acc: 0
                    target: null
                    onWheel: event => {
                        acc += event.angleDelta.y;
                        while (acc >= 120) {
                            win.navigate(0, -1);
                            acc -= 120;
                        }
                        while (acc <= -120) {
                            win.navigate(0, 1);
                            acc += 120;
                        }
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
            case "flyOpacity": return Math.round(cfg.flyOpacity * 100) + "%";
            case "flyFontFamily": return cfg.flyFontFamily || "follow launcher";
            case "volAnim": return cfg.volAnim;
            case "volTimeout": return (cfg.volTimeout / 1000).toFixed(1) + " s";
            case "notifMax": return "" + cfg.notifMax;
            case "notifWidth": return cfg.notifWidth + " px";
            case "notifTimeout": return (cfg.notifTimeout / 1000).toFixed(0) + " s";
            case "notifFontScale": return Math.round(cfg.notifFontScale * 100) + "%";
            case "notifAnim": return cfg.notifAnim;
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
                cfg.dimOpacity = Math.max(0, Math.min(0.9, Math.round((cfg.dimOpacity + dir * 0.05) * 100) / 100));
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
            case "flyOpacity":
                cfg.flyOpacity = Math.max(0, Math.min(0.9, Math.round((cfg.flyOpacity + dir * 0.05) * 100) / 100));
                break;
            case "volAnim":
                cfg.volAnim = cycleChoice(cfg.volAnim, ["slide", "fade", "pop", "none"], dir);
                break;
            case "volTimeout":
                cfg.volTimeout = Math.max(500, Math.min(10000, cfg.volTimeout + dir * 500));
                break;
            case "notifMax":
                cfg.notifMax = Math.max(1, Math.min(5, cfg.notifMax + dir));
                break;
            case "flyFontFamily": {
                const list = [""].concat(root.fontFamilies);
                let i = list.indexOf(cfg.flyFontFamily);
                if (i < 0)
                    i = 0;
                cfg.flyFontFamily = list[((i + dir) % list.length + list.length) % list.length];
                break;
            }
            case "notifWidth":
                cfg.notifWidth = Math.max(320, Math.min(600, cfg.notifWidth + dir * 20));
                break;
            case "notifTimeout":
                cfg.notifTimeout = Math.max(1000, Math.min(15000, cfg.notifTimeout + dir * 1000));
                break;
            case "notifFontScale":
                cfg.notifFontScale = Math.max(0.7, Math.min(1.6, Math.round((cfg.notifFontScale + dir * 0.1) * 100) / 100));
                break;
            case "notifAnim":
                cfg.notifAnim = cycleChoice(cfg.notifAnim, ["expand", "slide", "fade", "none"], dir);
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
            case "theme": cfg.theme = "amber"; break;
            case "wallpaperDir":
                cfg.wallpaperDir = "~/Pictures/wallpapers";
                root.rescanWallpapers();
                break;
            case "wallCommand": cfg.wallCommand = root.defaultWallCommand; break;
            case "volWidth": cfg.volWidth = 340; break;
            case "flyOpacity": cfg.flyOpacity = 0.4; break;
            case "flyFontFamily": cfg.flyFontFamily = ""; break;
            case "flyTheme": cfg.flyTheme = "amber"; break;
            case "flyouts": cfg.flyouts = ({ volume: true, notifs: true }); break;
            case "volAnim": cfg.volAnim = "slide"; break;
            case "volTimeout": cfg.volTimeout = 1500; break;
            case "notifMax": cfg.notifMax = 3; break;
            case "notifWidth": cfg.notifWidth = 420; break;
            case "notifTimeout": cfg.notifTimeout = 5000; break;
            case "notifFontScale": cfg.notifFontScale = 1.0; break;
            case "notifAnim": cfg.notifAnim = "expand"; break;
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
                    source: {
                        const name = modelData.icon;
                        if (!name)
                            return "";
                        return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
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

    // Warm the app-icon pixmap cache shortly after the daemon starts, so the
    // very first launcher open renders icons immediately instead of briefly
    // showing the two-letter fallback while the SVGs decode. A tiny
    // transparent overlay surface is enough to drive the image provider and
    // populate the process-global cache; it unloads once the cache is warm.
    // (The in-window warm-up only spans a couple of frames before the reveal,
    // too short for the async decodes to finish on a cold first open.)
    property bool bootWarmIcons: false
    Timer { interval: 900; running: true; onTriggered: root.bootWarmIcons = true }
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
                        source: {
                            const name = modelData.icon;
                            if (!name)
                                return "";
                            return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
                        }
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
            visible: volOsd.show || volOsd.leaving
            anchors.bottom: true
            implicitWidth: cfg.volWidth + 8
            implicitHeight: 180
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "launcher-vol-osd"
            // the OSD never takes input
            mask: Region {}

            BackgroundEffect.blurRegion: RoundedBlur {
                // rr un-clamped at the low end so the region collapses to
                // ~1px (invisible) as the pill fades/scales out
                readonly property real s: (volWin.mode === "pop" ? volCard.scale : 1) * volCard.opacity
                rx: volCard.x + (volCard.width - volCard.width * s) / 2 + 2
                ry: volCard.y + (volCard.height - volCard.height * s) / 2 + 2
                rw: Math.max(1, volCard.width * s - 4)
                rh: Math.max(1, volCard.height * s - 4)
                rr: 26 * s
            }

            Rectangle {
                id: volCard
                readonly property bool on: volOsd.show && !volOsd.leaving && volOsd.entered
                x: (parent.width - width) / 2
                width: cfg.volWidth
                height: 56
                radius: 28
                // rests 90px above the screen bottom; the slide exit drops it
                // past the window (= screen) bottom edge. Bounce is built in:
                // the exit overshoot lands off-screen, so only the entry
                // shows it.
                y: volWin.mode === "slide" ? (on ? parent.height - 146 : parent.height) : parent.height - 146
                Behavior on y {
                    NumberAnimation {
                        duration: volWin.mode === "slide" ? 340 : 0
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }
                color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, cfg.flyOpacity)
                border.width: 1
                border.color: Qt.alpha(root.flyTh.accent, 0.33)
                opacity: volWin.mode === "slide" ? 1 : (on ? 1 : 0)
                scale: volWin.mode === "pop" ? (on ? 1 : 0.8) : 1
                // unmap the window the instant the pill has left, so no
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

                // just a pill with a bar
                Item {
                    anchors.centerIn: parent
                    width: parent.width - 60
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
            }
        }
    }

    // ---------- notification flyouts ----------
    // A stack of pill cards below the top-right corner, hosted in one
    // fixed-size window. Cards are assigned to free slots, so existing cards
    // never rebuild when another notification arrives; stacking order is by
    // arrival, newest on top. Click expands the body text; swiping left or
    // right moves the card and dismisses past the threshold. Five slots
    // exist; cfg.notifMax caps how many are used at once.
    readonly property int notifSlots: 5
    function notifFs(px: int): int {
        return Math.round(px * cfg.notifFontScale);
    }
    property int notifSeq: 0

    // Own org.freedesktop.Notifications only while the flyout is enabled;
    // unloading releases the name for another daemon to claim.
    LazyLoader {
        active: root.flyoutOn("notifs")

        NotificationServer {
            bodySupported: true
            imageSupported: true
            onNotification: n => {
                n.tracked = true;
                notifWin.accept(n);
            }
        }
    }

    PanelWindow {
        id: notifWin
        property bool anyActive: false
        function refreshActive() {
            let a = false;
            for (let i = 0; i < cardRep.count; i++) {
                const c = cardRep.itemAt(i);
                if (c && c.active) { a = true; break; }
            }
            anyActive = a;
        }
        visible: anyActive
        anchors.top: true
        anchors.right: true
        // fixed size: cards animate inside; the left slack is swipe travel
        implicitWidth: cfg.notifWidth + 240
        implicitHeight: 1290
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "launcher-notif-osd"

        function accept(n) {
            const max = Math.max(1, Math.min(root.notifSlots, cfg.notifMax));
            let free = null, oldest = null;
            for (let i = 0; i < max; i++) {
                const c = cardRep.itemAt(i);
                if (!c)
                    continue;
                if (!c.active && !c.leaving) {
                    free = c;
                    break;
                }
                if (!oldest || c.seq < oldest.seq)
                    oldest = c;
            }
            const s = free || oldest;
            if (!s)
                return;
            if (!free)
                s.finalize();
            s.assign(n);
            refreshActive();
        }

        // input only over the cards; everything else clicks through.
        // Children are the region set (Region's default property is
        // `regions`); assigning `regions:` explicitly as well produced a
        // broken region that dropped the blur, so children only.
        mask: Region {
            NotifMaskRegion { c: cardRep.itemAt(0) }
            NotifMaskRegion { c: cardRep.itemAt(1) }
            NotifMaskRegion { c: cardRep.itemAt(2) }
            NotifMaskRegion { c: cardRep.itemAt(3) }
            NotifMaskRegion { c: cardRep.itemAt(4) }
        }
        BackgroundEffect.blurRegion: Region {
            // one rounded region per card; inactive slots stay a harmless 1px
            // (never 0-area, which would read as "blur the whole surface")
            NotifBlurRegion { c: cardRep.itemAt(0) }
            NotifBlurRegion { c: cardRep.itemAt(1) }
            NotifBlurRegion { c: cardRep.itemAt(2) }
            NotifBlurRegion { c: cardRep.itemAt(3) }
            NotifBlurRegion { c: cardRep.itemAt(4) }
        }

        Repeater {
            id: cardRep
            model: root.notifSlots
            NotifCard {
                rep: cardRep
                onActiveChanged: notifWin.refreshActive()
            }
        }
    }
}
