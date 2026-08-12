pragma Singleton
import QtQuick

// Factory values for every setting that more than one place needs to know:
// Settings declares them as its adapter defaults, and SettingsSchema.reset()
// puts them back. Kept in their own singleton rather than on either of those
// so neither has to import the other (Settings is the store's adapter;
// SettingsSchema writes to Settings), and so "what is the default" has one
// answer instead of a literal repeated at both ends.
QtObject {
    readonly property string wallCommand: 'pkill mpvpaper; case "$WALL" in *.mp4|*.webm|*.mkv|*.mov|*.gif) mpvpaper -s -a MAX -o "no-audio --loop-file=inf" HDMI-A-1 "$WALL";; *) awww img "$WALL" --transition-type fade --transition-duration 1;; esac'
    readonly property string wallpaperDir: "~/Pictures/wallpapers"

    readonly property var pages: ({ clock: true, apps: true, walls: true, clips: true })
    readonly property var pageOrder: ["clock", "apps", "walls", "clips"]
    readonly property var clockShow: ({ date: true, battery: true, weather: true })
    readonly property var flyouts: ({ volume: true, notifs: true })
    readonly property var pibbleAlerts: ({ errors: true, missingDeps: true, actions: true, battery: true })
    readonly property var keybinds: ({
        cycle: "Tab",
        reverseCycle: "Shift+Tab",
        launch: "Return",
        exit: "Escape",
        settings: "Ctrl+S",
        power: "Ctrl+P",
        reboot: "Ctrl+R",
        navLeft: "Left",
        navRight: "Right",
        navUp: "Up",
        navDown: "Down"
    })

    // the retired Mono preset's palette, which the custom theme is seeded from
    readonly property string customAccent: "#cfcfcf"
    readonly property string customFg: "#f0f0f0"
    readonly property string customMuted: "#8a8a8a"

    readonly property int appsCols: 4
    readonly property int appsRows: 3
    readonly property int wallsCols: 3
    readonly property int wallsRows: 3
    readonly property int wallsVisible: 7
    readonly property int clipsCols: 4
    readonly property int clipsRows: 3
    readonly property int clipsMax: 120
}
