pragma Singleton
import QtQuick
import Quickshell
import "root:/services"

// What each setting *means* to the settings UI: how to render its current
// value, how a ‹›/click step changes it, what resets it, and the bounds the
// grid-size picker enforces.
//
// Separate from Settings itself because Settings is a JsonAdapter - every
// property declared on it becomes a key in settings.json, so ranges, choice
// lists and display strings can't live there.
Singleton {
    id: root

    // ---------- grid sizes ----------

    // Pages whose grid size is editable via the tile picker on the Grids
    // settings tab, and the bounds that picker enforces.
    readonly property var gridTargets: ({
            apps: {
                label: "Apps",
                colsProp: "appsCols",
                rowsProp: "appsRows",
                minCols: 3,
                maxCols: 6,
                minRows: 2,
                maxRows: 6,
                resetKey: "appsGrid"
            },
            walls: {
                label: "Wallpapers",
                colsProp: "wallsCols",
                rowsProp: "wallsRows",
                minCols: 2,
                maxCols: 4,
                minRows: 2,
                maxRows: 4,
                resetKey: "wallsGrid"
            },
            clips: {
                label: "Clipboard",
                colsProp: "clipsCols",
                rowsProp: "clipsRows",
                minCols: 2,
                maxCols: 4,
                minRows: 2,
                maxRows: 4,
                resetKey: "clipsGrid"
            }
        })

    // The "windows" carousel's visible-bar count is always odd, 3-9, so the
    // picker needs nine columns to offer every choice symmetrically.
    readonly property int carouselBarSlots: 9
    // Largest cols/rows any target needs - the tile picker's canvas is always
    // sized to this, so switching targets never resizes it; only which tiles
    // are in bounds (and thus visible) changes.
    readonly property int pickerMaxCols: Math.max(root.carouselBarSlots, ...Object.values(root.gridTargets).map(t => t.maxCols))
    readonly property int pickerMaxRows: Math.max(...Object.values(root.gridTargets).map(t => t.maxRows))

    // ---------- ‹›-stepped settings ----------

    readonly property var launchAnimationChoices: ["grow-top-left", "grow-top-right", "grow-bottom-left", "grow-bottom-right", "grow-center", "fade", "none"]
    readonly property var tileAnimationChoices: ["bloom", "pop", "cascade", "fade", "slide", "none"]

    // The chips under the Animations tab's text-scramble row: one per surface
    // the effect shows up on. Ids are Settings.scrambleSections' keys (see
    // Anim.scrambleAllowed). The launcher's own pages come first, in the order
    // the shell cycles them, then the two menus and the two flyouts - which is
    // also the order the tab wraps them in, four to a line, so the pages sit on
    // one and everything that isn't a page on the next. The launch reveal has
    // no chip: it has no text of its own, every label it uncovers belonging to
    // whichever page it uncovers.
    //
    // Within the second line the two flyouts bracket the two menus rather than
    // sitting together, which is not the order the ids fall in - chosen by
    // hand for the pairing.
    readonly property var scrambleSectionChips: [
        { id: "clock", label: "clock" },
        { id: "apps", label: "apps" },
        { id: "walls", label: "wallpapers" },
        { id: "clips", label: "clipboard" },
        { id: "volume", label: "volume" },
        { id: "power", label: "power" },
        { id: "notifs", label: "notifications" },
        { id: "settings", label: "settings" }
    ]
    readonly property int scrambleChipColumns: 4

    // Every value below the ‹ › arrows sits in a box that shares its width with
    // the Navigation tab's chord boxes (see ui/Metrics.qml), which grow to fit
    // the longest of them - so the whole set a language could ever show has to
    // be enumerable up front. This is that set: everything display() can
    // return for a key that uses Metrics.shortValueWidth, already translated.
    // Metrics measures these and nothing else, which is why a value that isn't
    // listed here is a value that can overhang its arrows.
    readonly property var shortValueChoices: [Strings.tr("on"), Strings.tr("off"), Strings.tr("pill"), Strings.tr("sine wave"), Strings.tr("bubble"), "560 px", "10 s", "50%"]

    // The user-facing spelling of a motion style. Only "none" differs, and only
    // here: the stored id stays "none" everywhere (Settings.heal, and every
    // `=== "none"` check across the shell, read it), so this renames what is
    // shown without renaming the value - which would put every saved config's
    // "none" back to the default. Translated on the way out with everything
    // else display() returns - what a language may not do is rename the stored
    // id, only how it is spelled on screen.
    function styleName(value: string): string {
        return Strings.tr(value === "none" ? "off" : value);
    }

    // The two words half the rows in the pane read out. Said once because a
    // language's spelling of them has to be the same in all of them, and
    // because they are two of the values Metrics sizes those rows against.
    function onOff(value: bool): string {
        return Strings.tr(value ? "on" : "off");
    }

    function cycle(current: string, choices: var, dir: int): string {
        let i = choices.indexOf(current);
        if (i < 0)
            i = 0;
        return choices[((i + dir) % choices.length + choices.length) % choices.length];
    }

    // The value as the settings row shows it. An empty string means "this key
    // has no ‹› readout" - reset-only rows and chip rows return that.
    function display(key: string): string {
        switch (key) {
        case "clipsMax":
            return "" + Settings.clipsMax;
        case "animStyle":
            return root.styleName(Settings.animStyle);
        case "roundedCorners":
            return root.onOff(Settings.roundedCorners);
        case "fontScale":
            return Math.round(Settings.fontScale * 100) + "%";
        case "dimOpacity":
            return Math.round(Settings.dimOpacity * 100) + "%";
        case "launchAnimation":
            return root.styleName(Settings.launchAnimation);
        case "bgBlur":
            // the protocol's own name, which is not pibble's to translate
            return Settings.bgBlur === "compositor" ? "ext-background-effect" : Strings.tr(Settings.bgBlur);
        case "gestures":
            return root.onOff(Settings.gestures);
        case "singleClickActivate":
            return root.onOff(Settings.singleClickActivate);
        case "hiddenMenuAnimations":
            return root.onOff(Settings.hiddenMenuAnimations);
        case "powerAnimations":
            return root.onOff(Settings.powerAnimations);
        case "preload":
            return root.onOff(Settings.preload);
        case "language":
            return Strings.nameOf(Strings.code);
        // a font's and an icon theme's names are the system's, not pibble's -
        // only the "no choice made" placeholder standing in for them is
        case "fontFamily":
            return Settings.fontFamily || Strings.tr("system default");
        case "iconTheme":
            return Settings.iconTheme || Strings.tr("system default");
        case "volWidth":
            return Settings.volWidth + " px";
        case "volAnim":
            return root.styleName(Settings.volAnim);
        case "volStyle":
            return Strings.tr(Settings.volStyle === "sine" ? "sine wave" : Settings.volStyle);
        case "volPercent":
            return root.onOff(Settings.volShowPercent);
        case "volTimeout":
            return (Settings.volTimeout / 1000).toFixed(0) + " s";
        case "notifTimeout":
            return (Settings.notifTimeout / 1000).toFixed(0) + " s";
        case "replayCount":
            return "" + Settings.replayCount;
        case "batteryAlertLevel":
            return Settings.batteryAlertLevel + "%";
        case "notifStyle":
            return Strings.tr(Settings.notifStyle);
        case "notifAnim":
            return root.styleName(Settings.notifAnim);
        case "wallpaperStyle":
            // the internal ids are historical (see Settings.wallpaperStyle);
            // these are what the user is actually shown
            return Strings.tr(Settings.wallpaperStyle === "carousel-flat" ? "carousel" : Settings.wallpaperStyle === "carousel" ? "parallax carousel" : Settings.wallpaperStyle);
        case "wallpaperLive":
            return root.onOff(Settings.wallpaperLive);
        }
        return "";
    }

    function adjust(key: string, dir: int): void {
        switch (key) {
        case "clipsMax":
            Settings.clipsMax = Math.max(20, Math.min(200, Settings.clipsMax + dir * 20));
            Clipboard.rescan();
            break;
        case "animStyle":
            Settings.animStyle = root.cycle(Settings.animStyle, root.tileAnimationChoices, dir);
            break;
        case "roundedCorners":
            Settings.roundedCorners = !Settings.roundedCorners;
            break;
        case "fontScale":
            Settings.fontScale = Math.max(0.7, Math.min(1.6, Math.round((Settings.fontScale + dir * 0.1) * 100) / 100));
            break;
        case "dimOpacity":
            Settings.dimOpacity = Math.max(0, Math.min(1, Math.round((Settings.dimOpacity + dir * 0.05) * 100) / 100));
            break;
        case "launchAnimation":
            Settings.launchAnimation = root.cycle(Settings.launchAnimation, root.launchAnimationChoices, dir);
            break;
        case "bgBlur":
            Settings.bgBlur = root.cycle(Settings.bgBlur, ["off", "compositor", "xray"], dir);
            break;
        case "gestures":
            Settings.gestures = !Settings.gestures;
            break;
        case "singleClickActivate":
            Settings.singleClickActivate = !Settings.singleClickActivate;
            break;
        case "hiddenMenuAnimations":
            Settings.hiddenMenuAnimations = !Settings.hiddenMenuAnimations;
            break;
        case "powerAnimations":
            Settings.powerAnimations = !Settings.powerAnimations;
            break;
        case "preload":
            Settings.preload = !Settings.preload;
            break;
        case "language":
            // cycled off the resolved code, not off the stored value: stepping
            // away from an id nothing ships has to land somewhere real
            Settings.language = root.cycle(Strings.code, Strings.ids, dir);
            break;
        case "fontFamily":
            // "" (system default) is a real choice, so it heads the list
            Settings.fontFamily = root.cycle(Settings.fontFamily, [""].concat(SystemInfo.fontFamilies), dir);
            break;
        case "iconTheme":
            Settings.iconTheme = root.cycle(Settings.iconTheme, [""].concat(SystemInfo.iconThemes), dir);
            break;
        case "volWidth":
            Settings.volWidth = Math.max(240, Math.min(560, Settings.volWidth + dir * 20));
            break;
        case "volAnim":
            Settings.volAnim = root.cycle(Settings.volAnim, ["slide", "fade", "pop", "none"], dir);
            break;
        case "volStyle":
            Settings.volStyle = root.cycle(Settings.volStyle, ["pill", "sine"], dir);
            break;
        case "volPercent":
            Settings.volShowPercent = !Settings.volShowPercent;
            break;
        case "volTimeout":
            Settings.volTimeout = Math.max(1000, Math.min(10000, Settings.volTimeout + dir * 1000));
            break;
        case "notifTimeout":
            Settings.notifTimeout = Math.max(1000, Math.min(15000, Settings.notifTimeout + dir * 1000));
            break;
        case "replayCount":
            Settings.replayCount = Math.max(1, Math.min(5, Settings.replayCount + dir));
            break;
        case "batteryAlertLevel":
            Settings.batteryAlertLevel = Math.max(5, Math.min(50, Settings.batteryAlertLevel + dir * 5));
            break;
        case "notifStyle":
            Settings.notifStyle = root.cycle(Settings.notifStyle, ["bubble", "pill"], dir);
            break;
        case "notifAnim":
            Settings.notifAnim = root.cycle(Settings.notifAnim, ["pop", "none"], dir);
            break;
        case "wallpaperStyle":
            Settings.wallpaperStyle = root.cycle(Settings.wallpaperStyle, ["grid", "carousel-flat", "carousel"], dir);
            break;
        case "wallpaperLive":
            Settings.wallpaperLive = !Settings.wallpaperLive;
            break;
        }
        Settings.save();
    }

    function toggleIndicator(name: string): void {
        const indicators = Object.assign({}, Defaults.pageIndicators, Settings.pageIndicators);
        indicators[name] = indicators[name] === false;
        Settings.pageIndicators = indicators;
        Settings.save();
    }

    function toggleFlyout(name: string): void {
        const flyouts = Object.assign({}, Defaults.flyouts, Settings.flyouts);
        flyouts[name] = flyouts[name] === false;
        Settings.flyouts = flyouts;
        Settings.save();
    }

    function toggleScrambleSection(name: string): void {
        const sections = Object.assign({}, Defaults.scrambleSections, Settings.scrambleSections);
        sections[name] = sections[name] === false;
        Settings.scrambleSections = sections;
        Settings.save();
    }

    function toggleAlert(name: string): void {
        const alerts = Object.assign({}, Defaults.pibbleAlerts, Settings.pibbleAlerts);
        alerts[name] = alerts[name] === false;
        Settings.pibbleAlerts = alerts;
        Settings.save();
    }

    function setBind(action: string, key: string): void {
        const binds = Object.assign({}, Settings.keybinds);
        binds[action] = key;
        Settings.keybinds = binds;
        Settings.save();
    }

    function reset(key: string): void {
        switch (key) {
        case "pages":
            // uploaded pages aren't touched - only their order resets, which
            // drops them to the end and the add row back to the top
            Settings.pages = Defaults.pages;
            Settings.pageOrder = Defaults.pageOrder;
            break;
        case "clock":
            Settings.clockShow = Defaults.clockShow;
            break;
        case "pageIndicators":
            Settings.pageIndicators = Defaults.pageIndicators;
            break;
        case "appsGrid":
            Settings.appsCols = Defaults.appsCols;
            Settings.appsRows = Defaults.appsRows;
            break;
        case "wallsGrid":
            Settings.wallsCols = Defaults.wallsCols;
            Settings.wallsRows = Defaults.wallsRows;
            Settings.wallsVisible = Defaults.wallsVisible;
            break;
        case "clipsGrid":
            Settings.clipsCols = Defaults.clipsCols;
            Settings.clipsRows = Defaults.clipsRows;
            break;
        case "clipsMax":
            Settings.clipsMax = Defaults.clipsMax;
            Clipboard.rescan();
            break;
        case "animStyle":
            Settings.animStyle = "bloom";
            break;
        case "textScramble":
            // the row is its chips, so its reset is theirs (the key it is
            // still named for is retired - see Settings.heal)
            Settings.scrambleSections = Defaults.scrambleSections;
            break;
        case "roundedCorners":
            Settings.roundedCorners = true;
            break;
        case "fontScale":
            Settings.fontScale = 1.0;
            break;
        case "dimOpacity":
            Settings.dimOpacity = 0.4;
            break;
        case "launchAnimation":
            Settings.launchAnimation = "grow-top-left";
            break;
        case "bgBlur":
            Settings.bgBlur = "xray";
            break;
        case "hiddenMenuAnimations":
            Settings.hiddenMenuAnimations = true;
            break;
        case "powerAnimations":
            Settings.powerAnimations = true;
            break;
        case "preload":
            Settings.preload = true;
            break;
        case "gestures":
            Settings.gestures = true;
            break;
        case "singleClickActivate":
            Settings.singleClickActivate = false;
            break;
        case "language":
            Settings.language = Defaults.language;
            break;
        case "fontFamily":
            Settings.fontFamily = "";
            break;
        case "iconTheme":
            Settings.iconTheme = "";
            break;
        case "theme":
            Settings.theme = "matugen";
            break;
        case "customColors":
            Settings.customAccent = Defaults.customAccent;
            Settings.customFg = Defaults.customFg;
            Settings.customMuted = Defaults.customMuted;
            break;
        case "wallpaperDir":
            Settings.wallpaperDir = Defaults.wallpaperDir;
            Wallpapers.rescan();
            break;
        case "wallCommand":
            Settings.wallCommand = Defaults.wallCommand;
            break;
        case "volWidth":
            Settings.volWidth = 420;
            break;
        case "flyouts":
            Settings.flyouts = Defaults.flyouts;
            break;
        case "pibbleAlerts":
            Settings.pibbleAlerts = Defaults.pibbleAlerts;
            break;
        case "volAnim":
            Settings.volAnim = "pop";
            break;
        case "volStyle":
            Settings.volStyle = "sine";
            break;
        case "volPercent":
            Settings.volShowPercent = true;
            break;
        case "volTimeout":
            Settings.volTimeout = 2000;
            break;
        case "notifTimeout":
            Settings.notifTimeout = 5000;
            break;
        case "replayCount":
            Settings.replayCount = 1;
            break;
        case "batteryAlertLevel":
            Settings.batteryAlertLevel = Defaults.batteryAlertLevel;
            break;
        case "notifStyle":
            Settings.notifStyle = "bubble";
            break;
        case "notifAnim":
            Settings.notifAnim = "pop";
            break;
        case "wallpaperStyle":
            Settings.wallpaperStyle = "grid";
            break;
        case "wallpaperLive":
            Settings.wallpaperLive = true;
            break;
        default:
            if (key.startsWith("bind:")) {
                const action = key.slice(5);
                root.setBind(action, Defaults.keybinds[action] ?? "");
                return; // setBind saves
            }
        }
        Settings.save();
    }
}
