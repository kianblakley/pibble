# App Launcher

A Quickshell app launcher implementing the [Claude Design "App Launcher"](https://claude.ai/design/p/b7f6f3a0-488e-43ce-9bf7-af1264cd473d) mockup, with two deltas from the design: real system icons (via desktop entries + icon theme) and a transparent, compositor-blurred background (`ext-background-effect-v1`) instead of the mocked gradient.

## Usage

```sh
qs -p ~/Projects/launcher
```

Runs as a one-shot fullscreen overlay that fades in on launch and fades out on exit:

- **Idle** — shows a clock and date. Enter/Tab opens the app drawer with the most-used apps.
- **Tab / Shift+Tab** — cycles panes forward/backward: clock → apps → wallpapers → clipboard → clock.
- **Apps** — typing fuzzy-matches installed apps (launch count first, fuzzy score second; counts persisted in Quickshell's state dir) into a paged grid; emptying the query shows the most-used apps.
- **Wallpapers** — paged grid of `wallpaperDir` images, fuzzy-filterable. Selecting one sets it via `awww` (`workspaces` namespace) with a blurred variant on `overview`. Missing thumbnails and blurred variants are generated with ImageMagick in the background at startup.
- **Clipboard** — cliphist history (text and images), fuzzy-filterable; Enter/click copies via `wl-copy`. Requires `cliphist` + `wl-clipboard`; the niri config spawns the `wl-paste --watch cliphist store` watchers at startup.
- **Arrows** — ←/→ previous/next; ↓/↑ walks the entire column across pages, then hops to the next/previous column.
- **Enter** / click — launch app / apply wallpaper / copy clip, then exit.
- **Escape** — exits from anywhere.
- **Bottom-right hover** — settings button. Settings pane: per-pane grid sizes, font size, opacity, icon theme (applied on the next launch — `launch.sh` exports `QS_ICON_THEME` from the saved settings, and the niri bind uses it), color themes with palette previews (including a matugen-powered Dynamic theme derived from the current wallpaper), circle reveal origin (center or any corner), wallpaper directory, and rebindable cycle/launch/exit keys. Stored in `settings.json` in Quickshell's state dir.

## niri keybind

```kdl
binds {
    Mod+Space { spawn "qs" "-p" "/home/kian/Projects/launcher"; }
}
```

## Requirements

- Quickshell ≥ 0.3.0 (Wayland module)
- A compositor with `zwlr_layer_shell_v1`; blur needs `ext_background_effect_manager_v1` (degrades to plain transparency without it)
- JetBrains Mono font
