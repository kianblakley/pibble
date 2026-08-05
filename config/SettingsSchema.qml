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
            return Settings.animStyle;
        case "fontScale":
            return Math.round(Settings.fontScale * 100) + "%";
        case "dimOpacity":
            return Math.round(Settings.dimOpacity * 100) + "%";
        case "launchAnimation":
            return Settings.launchAnimation;
        case "bgBlur":
            return Settings.bgBlur === "compositor" ? "ext-background-effect" : Settings.bgBlur;
        case "gestures":
            return Settings.gestures ? "on" : "off";
        case "singleClickActivate":
            return Settings.singleClickActivate ? "on" : "off";
        case "hiddenMenuAnimations":
            return Settings.hiddenMenuAnimations ? "on" : "off";
        case "fontFamily":
            return Settings.fontFamily || "system default";
        case "iconTheme":
            return Settings.iconTheme || "system default";
        case "volWidth":
            return Settings.volWidth + " px";
        case "volAnim":
            return Settings.volAnim;
        case "volStyle":
            return Settings.volStyle === "sine" ? "sine wave" : Settings.volStyle;
        case "volPercent":
            return Settings.volShowPercent ? "on" : "off";
        case "volTimeout":
            return (Settings.volTimeout / 1000).toFixed(0) + " s";
        case "notifTimeout":
            return (Settings.notifTimeout / 1000).toFixed(0) + " s";
        case "replayCount":
            return "" + Settings.replayCount;
        case "notifStyle":
            return Settings.notifStyle;
        case "notifAnim":
            return Settings.notifAnim;
        case "wallpaperStyle":
            // the internal ids are historical (see Settings.wallpaperStyle);
            // these are what the user is actually shown
            return Settings.wallpaperStyle === "carousel-flat" ? "carousel" : Settings.wallpaperStyle === "carousel" ? "parallax carousel" : Settings.wallpaperStyle;
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
        case "notifStyle":
            Settings.notifStyle = root.cycle(Settings.notifStyle, ["bubble", "pill"], dir);
            break;
        case "notifAnim":
            Settings.notifAnim = root.cycle(Settings.notifAnim, ["pop", "none"], dir);
            break;
        case "wallpaperStyle":
            Settings.wallpaperStyle = root.cycle(Settings.wallpaperStyle, ["grid", "carousel-flat", "carousel"], dir);
            break;
        }
        Settings.save();
    }

    function toggleFlyout(name: string): void {
        const flyouts = Object.assign({}, Defaults.flyouts, Settings.flyouts);
        flyouts[name] = flyouts[name] === false;
        Settings.flyouts = flyouts;
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
        case "gestures":
            Settings.gestures = true;
            break;
        case "singleClickActivate":
            Settings.singleClickActivate = false;
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
        case "notifStyle":
            Settings.notifStyle = "bubble";
            break;
        case "notifAnim":
            Settings.notifAnim = "pop";
            break;
        case "wallpaperStyle":
            Settings.wallpaperStyle = "grid";
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
