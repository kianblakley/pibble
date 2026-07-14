# App Launcher

A Quickshell app launcher implementing the [Claude Design "App Launcher"](https://claude.ai/design/p/b7f6f3a0-488e-43ce-9bf7-af1264cd473d) mockup, with two deltas from the design: real system icons (via desktop entries + icon theme) and a transparent, compositor-blurred background (`ext-background-effect-v1`) instead of the mocked gradient.

## Usage

```sh
qs -p ~/Projects/launcher
```

Runs as a one-shot fullscreen overlay that fades in on launch and fades out on exit:

- **Idle** — shows a clock and date. Enter/Tab opens the app drawer with the most-used apps.
- **Type** — fuzzy-matches installed apps (subsequence scoring: prefixes, word starts, and consecutive runs rank higher) into a 4×3 tile grid (max 12). Results are ordered by launch count first (persisted in Quickshell's state dir), fuzzy score second.
- **Tab** — from the app drawer, rotates to a wallpaper selector for `~/Pictures/wallpapers` (3×3 paged grid). Selecting one sets it via `awww` on the `workspaces` namespace and a blurred variant on `overview` (reuses `blurred/<file>` or `<stem>blurred.<ext>` if present, else generates one with ImageMagick into `blurred/`).
- **Arrows** — move selection (←/→ by 1, ↑/↓ by row, wraps).
- **Enter** / click — launch selected app / apply selected wallpaper, then exit.
- **Escape** — steps back one level: wallpapers → apps → clock → exit.

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
