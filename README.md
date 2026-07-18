<h1 align=center>
    pibble
</h1>

> [!NOTE] 
> only tested on niri so far. Other WMs may work but aren't verified.

## Video

todo

## Features

- Clock
- App drawer 
- Wallpaper selector
- Clipboard history 
- Power off
- Volume flyout
- Notification flyout

## Core keybindings

| Key | Action |
|---|---|
| Tab | Navigate pages |
| Ctrl+P (or swipe down) | Reveal power button |
| Ctrl+S | Open settings |

## Installation

**1. Install dependencies**

Necessary:

| Dependency | Use |
|---|---|
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland) | Hosts the shell |

Optional - required for full features:

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
./pibble
```

**4. Toggle the launcher**

```sh
./pibble toggle
```

## Compositor integration

Each pibble window sets a `namespace` via the wlr layer-shell protocol, which
compositors can match on to apply their own rules (placement, blur, opacity,
etc.):

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher window |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume OSD |

pibble also requests background blur behind the launcher itself via the
[`ext-background-effect-v1`](https://wayland.app/protocols/ext-background-effect-v1)
Wayland protocol (see the "Background blur" setting) — currently implemented
by niri. On niri, you can tune or override this per window with a layer rule,
e.g.:

```kdl
layer-rule {
    match namespace="^pibble-launcher$"

    background-effect {
        blur false
        xray false
    }
}
```

