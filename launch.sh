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

# ipc calls fail on ambiguity if duplicate daemons exist; always talk to the
# newest and reap any older duplicates.
ipc() {
    qs -p "$repo" ipc -n call launcher "$1" 2>/dev/null
}
reap_duplicates() {
    mapfile -t pids < <(pgrep -f "^qs -p $repo\$" | sort -n)
    while [ "${#pids[@]}" -gt 1 ]; do
        kill "${pids[0]}" 2>/dev/null
        pids=("${pids[@]:1}")
    done
}

case "$1" in
toggle)
    reap_duplicates
    ipc toggle && exit 0
    # daemon not running: start it, then open the launcher
    setsid -f qs -p "$repo" >/dev/null 2>&1
    for _ in $(seq 1 50); do
        sleep 0.1
        ipc open && exit 0
    done
    exit 1
    ;;
*)
    # never start a second daemon
    pgrep -f "^qs -p $repo\$" >/dev/null && exit 0
    exec qs -p "$repo"
    ;;
esac
