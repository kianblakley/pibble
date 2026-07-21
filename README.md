<h1 align=center>
    pibble
</h1>

| Clock |
|---|
| ![Clock](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/clock.png) |

| App drawer |
|---|
| ![App drawer](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/appdrawer.png) |

| Wallpaper selector |
|---|
| ![Wallpaper selector](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/wallpaperselector.png) |

| Clipboard history |
|---|
| ![Clipboard history](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/clipboardhistory.png) |

| Flyouts |
|---|
| ![Flyouts](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/flyouts.png) |

| Settings |
|---|
| ![Settings](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/settings.png) |

| Power button |
|---|
| ![Power button](https://raw.githubusercontent.com/kianblakley/pibble/assets/assets/powerbutton.png) |

## Installation

**1. Install dependencies**

Necessary:

| Dependency | Use |
|---|---|
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland) | Hosts the shell |

Optional (required for full feature set):

| Dependency | Use |
|---|---|
| [cliphist](https://github.com/sentriz/cliphist) | Clipboard history |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | Wallpaper/clip thumbnails |
| [awww](https://codeberg.org/LGFae/awww) | Sets the wallpaper (can use any program via settings) |
| [matugen](https://github.com/InioX/matugen) | Wallpaper-derived color theme |


**2. Clone**

```sh
git clone https://github.com/kianblakley/pibble.git
cd pibble
```

**3. Start the daemon**

```sh
./pibble start
```

**4. Toggle the launcher**

```sh
./pibble toggle
```

Run `./pibble help` (or `./pibble` with no arguments) for the full command list — `start` / `stop` / `restart` the daemon, `toggle` the launcher, and `replay` to re-fire the last few notifications.

## Core Keybindings

| Key | Action |
|---|---|
| `Tab` | Navigate pages |
| `Ctrl+P` (or swipe down) | Reveal power button |
| `Ctrl+R` (or swipe up) | Reveal reboot button |
| `Ctrl+S` | Open settings |
| `Escape` | Close the launcher |

## Namespaces

Each window has a layer-shell namespace which can be used to apply background effects in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume OSD |



