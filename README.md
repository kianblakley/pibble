<h1 align=center>
    pibble
</h1>

<!-- TODO: embed the demo video here once it's filmed, e.g.
[![pibble demo](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=VIDEO_ID)
-->

## Features

- **Launcher** — clock, app drawer, wallpaper selector, clipboard history, and power/reboot menu, all in one swipeable window
- **Volume and notification flyouts** — OSDs that pop up over whatever you're doing
- **Dynamic theming** — matugen-driven color extraction from your current wallpaper, or a manual palette
- **Wallpapers** — image and video wallpapers, with generated thumbnails and blurred previews
- **Clipboard history** — backed by cliphist, with thumbnails for image entries
- **Custom pages** — bring your own page into the launcher's page cycle
- **Multi-monitor aware** — the launcher and flyouts follow whichever output your compositor says is focused
- **Notification replay** — `pibble replay` re-fires recent notifications, stepping further back in history on each repeated press
- **Weather and battery** shown on the clock page

## Installation

### 1. Install dependencies

Necessary:

| Dependency | Use |
|---|---|
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland) | Hosts the shell |
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |

Optional (required for full feature set):

| Dependency | Use |
|---|---|
| [matugen](https://github.com/InioX/matugen) | Wallpaper-derived color theme |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | Wallpaper/clip thumbnails |
| [ffmpeg](https://ffmpeg.org/) | Thumbnails/blurred previews for video wallpapers |
| [awww](https://codeberg.org/LGFae/awww) | Sets the wallpaper (can use any program via settings) |
| [wl-clipboard](https://github.com/bugaevc/wl-clipboard) | Feeds cliphist and copies history entries back onto the clipboard |

### 2. Clone

```sh
git clone https://github.com/kianblakley/pibble.git
cd pibble
```

### 3. Start the daemon

```sh
./pibble start
```

### 4. Toggle the launcher

```sh
./pibble toggle
```

## Usage

### Keybindings

| Key | Gesture | Action |
|---|---|---|
| `Tab` / `Shift+Tab` | swipe left/right | Cycle pages |
| Arrow keys | swipe up/down | Navigate tiles in the current pane |
| `Enter` | press | Activate the selected tile |
| `Ctrl+P` | swipe down from the top edge | Reveal power button |
| `Ctrl+R` | swipe up from the bottom edge | Reveal reboot button |
| `Ctrl+S` | press bottom right corner | Open settings |
| `Escape` | right-edge swipe | Go back, then close the launcher |

### `./pibble` commands

| Command | Description |
|---|---|
| `help` | Show the command list (also what a bare `./pibble` does) |
| `start` | Start the persistent daemon (for spawn-at-startup) |
| `stop` | Stop the daemon |
| `restart` | Stop, then start the daemon |
| `toggle [page]` | Show/hide the launcher, starting the daemon first if needed; with a page id, opens/switches straight to that page, or closes it if it's already the one showing |
| `replay` | Re-fire one recent notification; repeated presses step back through history |

## Configuring

pibble also has an extensive in-app settings page (`Ctrl+S`, or press the bottom right corner) covering theming, navigation, flyouts, and pages — most day-to-day customization belongs there rather than in a config file.

### Namespaces

Each window has a layer-shell namespace which can be used to apply background effects in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume OSD |

### Custom pages

TODO: document the custom-page API.

