#!/usr/bin/env bash
# App-launcher shell daemon control.
#   launch.sh          start the persistent daemon (for spawn-at-startup)
#   launch.sh toggle   show/hide the launcher window (for the keybind),
#                      starting the daemon first if it isn't running
# Qt can't switch icon themes at runtime, so quickshell reads QS_ICON_THEME
# at startup; we pull it out of the launcher's persisted settings.
repo="$(dirname "$(readlink -f "$0")")"
settings="$HOME/.local/state/quickshell/by-shell/b3c79d9b1b83e8627e01e1689066fbb2/settings.json"
theme=$(sed -n 's/.*"iconTheme": *"\([^"]*\)".*/\1/p' "$settings" 2>/dev/null | head -1)
[ -n "$theme" ] && export QS_ICON_THEME="$theme"

case "$1" in
toggle)
    qs -p "$repo" ipc call launcher toggle 2>/dev/null && exit 0
    # daemon not running: start it, then open the launcher
    setsid -f qs -p "$repo" >/dev/null 2>&1
    for _ in $(seq 1 50); do
        sleep 0.1
        qs -p "$repo" ipc call launcher show 2>/dev/null && exit 0
    done
    exit 1
    ;;
*)
    exec qs -p "$repo"
    ;;
esac
