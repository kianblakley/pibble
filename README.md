<h1 align=center>
    pibble
</h1>

<!-- TODO: embed the demo video here once it's filmed, e.g.
[![pibble demo](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=VIDEO_ID)
-->
![App drawer](https://raw.githubusercontent.com/kianblakley/pibble/dev/assets/appdrawer.png)


## Features

- **Launcher** - clock, app drawer, wallpaper selector, clipboard history, and power/reboot menus
- **Volume and notification flyouts** - OSDs that pop up over whatever you're doing
- **Weather and battery** - shown on the clock page
- **In-app settings** - configurable layout, animations, theming, keybindings, resource usage and much more
- **Custom pages** - create your own qml page and have it show up in the launcher
- **Dynamic theming** - matugen-driven color extraction from your current wallpaper, or a custom palette
- **Notification replay** - re-fire recent notifications, stepping further back in history on each repeated call
- **Live wallpaper support** - live wallpaper previews, with auto-generated blurred variants
- **Multi-monitor support** - the launcher and flyouts follow whichever output is focused
- **Gesture and keyboard support** - entirely navigateable with either keyboard or gestures alone
  
## Installation

### 1. Install dependencies

Necessary:

| Dependency | Use |
|---|---|
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland), [Sway](https://github.com/swaywm/sway) | Hosts the shell |
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |

Optional (required for full feature set):

| Dependency | Use |
|---|---|
| [matugen](https://github.com/InioX/matugen) | Wallpaper-derived color theme |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | Static wallpaper/clipboard thumbnails |
| [ffmpeg](https://ffmpeg.org/) | Live wallpaper thumbnails |
| [qtmultimedia](https://doc.qt.io/qt-6/qtmultimedia-index.html) | Live wallpaper previews (install via your distro's package manager) |
| [awww](https://codeberg.org/LGFae/awww) | Recommended wallpaper backend (can use any) |
| [cliphist](https://github.com/sentriz/cliphist) | Clipboard history support |

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
| `Arrow keys` | swipe up/down | Navigate tiles in the current page |
| `Enter` | press | Activate the selected tile |
| `Ctrl+P` | swipe down from the top edge | Reveal power button |
| `Ctrl+R` | swipe up from the bottom edge | Reveal reboot button |
| `Ctrl+S` | press bottom right corner | Open settings |
| `Escape` | right-edge swipe | Go back or close the launcher |

### `./pibble` commands

| Command | Description |
|---|---|
| `help` | List the available commands |
| `start` | Start the daemon |
| `stop` | Stop the daemon |
| `restart` | Restart the daemon |
| `toggle [page]` | Show/hide the launcher, starting the daemon first if needed; with a page id, opens/switches straight to that page |
| `replay` | Re-fire one recent notification; repeated presses step back through history |

## Configuring

### Settings
pibble has an extensive in-app settings page (`Ctrl+S`, or press the bottom right corner to open) covering appearance, animations, resource usage, layouts, navigation and flyouts.

### Namespaces

Each window has a layer-shell namespace which can be used to apply background effects/animations in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume flyout |

### Custom pages

Custom page api is coming. 

