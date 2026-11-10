#!/usr/bin/env bash
# pibble uninstaller: removes the dependencies ./install.sh installed, and
# nothing else.
#
# It works only from the manifest install.sh wrote - so a package that was
# already on the system when you installed pibble was never recorded, and is
# never touched here. There is deliberately no "remove everything pibble
# needs" mode: that would take out whatever else on the system depends on
# ffmpeg or ImageMagick.
#
# Your settings, wallpapers, clipboard cache and the repo itself are left
# alone. This removes packages, not pibble's data.
set -euo pipefail

# -P to match ./pibble, which resolves symlinks before it names the daemon
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/pibble"
manifest="$state_dir/install-manifest.tsv"

dry_run=0
assume_yes=0
keep_toolchains=0

usage() {
    cat <<USAGE
pibble uninstaller - removes only what ./install.sh installed

Usage: ./uninstall.sh [options]

Options:
  --keep-toolchains  don't offer to remove compilers/build deps
  --yes, -y          non-interactive: remove the dependencies, keep toolchains
  --dry-run          print what would be removed, change nothing
  --list             show the manifest and exit
  --help, -h         show this message

Not removed by anything here: your settings, thumbnails and clipboard cache
(~/.local/state/quickshell, ~/.cache/pibble) and this repo.
USAGE
}

list_only=0
while [ $# -gt 0 ]; do
    case "$1" in
    --keep-toolchains) keep_toolchains=1; shift ;;
    --yes | -y) assume_yes=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --list) list_only=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_red=$'\033[31m'
    c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_blue=$'\033[34m'; c_off=$'\033[0m'
else
    c_bold=""; c_dim=""; c_red=""; c_green=""; c_yellow=""; c_blue=""; c_off=""
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$c_blue" "$c_off" "$c_bold" "$*" "$c_off"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s+%s %s\n' "$c_green" "$c_off" "$*"; }
skip()  { printf '    %s-%s %s\n' "$c_dim" "$c_off" "$*"; }
warn()  { printf '    %s!%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
fail()  { printf '    %sx%s %s\n' "$c_red" "$c_off" "$*" >&2; }

run() {
    if [ "$dry_run" = 1 ]; then
        printf '    %s$ %s%s\n' "$c_dim" "$*" "$c_off"
        return 0
    fi
    "$@"
}

ask_yn() {
    local prompt="$1" default="${2:-y}" reply
    if [ "$assume_yes" = 1 ] || [ ! -t 0 ]; then
        [ "$default" = y ]
        return
    fi
    if [ "$default" = y ]; then prompt="$prompt [Y/n] "; else prompt="$prompt [y/N] "; fi
    read -r -p "    $prompt" reply || reply=""
    reply="${reply:-$default}"
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

as_root() {
    if [ "$(id -u)" = 0 ]; then
        run "$@"
    elif command -v sudo >/dev/null 2>&1; then
        run sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        run doas "$@"
    else
        fail "need root to run: $*"
        return 1
    fi
}

# Rows are split by hand rather than with `IFS=$'\t' read`, because tab is an
# IFS *whitespace* character: bash collapses a run of them into one separator,
# so a row with an empty binary field would shift role into bin and a toolchain
# would be read as an ordinary dependency and removed without asking. awk would
# do this in one line, but a minimal openSUSE install has no awk.
row_method=""; row_pkg=""; row_bin=""; row_role=""
parse_row() {
    local line="$1" rest
    row_method="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    row_pkg="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    row_bin="${rest%%$'\t'*}"
    row_role="${rest#*$'\t'}"
    [ -n "$row_bin" ] || row_bin="-"
    [ -n "$row_role" ] || row_role="dep"
}

if [ ! -f "$manifest" ]; then
    printf '%sNothing to uninstall.%s\n' "$c_bold" "$c_off"
    info "no install manifest at $manifest"
    info "either install.sh was never run, or it installed nothing (everything was already present)."
    exit 0
fi

if [ "$list_only" = 1 ]; then
    printf '%s%s%s\n\n' "$c_bold" "$manifest" "$c_off"
    printf '    %-10s %-40s %-14s %s\n' METHOD PACKAGE BINARY ROLE
    while IFS= read -r line; do
        case "$line" in '#'* | '') continue ;; esac
        parse_row "$line"
        printf '    %-10s %-40s %-14s %s\n' "$row_method" "$row_pkg" "$row_bin" "$row_role"
    done <"$manifest"
    exit 0
fi

# ------------------------------------------------------------ read manifest ---

# Reversed: last installed, first removed - so a package pulled in as another's
# build dependency goes after the thing that needed it.
#
# The manifest is a plain file in the user's home, and what it says ends up as
# arguments to a package manager and to rm - some of it under sudo. So a row is
# only acted on if it looks like something install.sh could have written: a
# package name that cannot be read as an option or a path out of somewhere, and
# a binary that is a bare file name. Anything else is reported and left alone
# (it also stays in the manifest, since nothing was removed for it).
valid_row() {
    local name='^[A-Za-z0-9@][A-Za-z0-9@._+:/-]*$' file='^[A-Za-z0-9._+-]+$'
    [[ "$row_method" =~ ^[a-z-]+$ ]] || return 1
    [[ "$row_pkg" =~ $name ]] || return 1
    case "$row_pkg" in *..* | *//* | */) return 1 ;; esac
    [ "$row_bin" = "-" ] || [[ "$row_bin" =~ $file ]] || return 1
    case "$row_bin" in . | ..) return 1 ;; esac
    case "$row_role" in dep | toolchain | repo) ;; *) return 1 ;; esac
    # a source build's name becomes part of a file name here; a go build's
    # binary is the whole of what gets deleted
    case "$row_method" in
    source) [[ "$row_pkg" =~ $file ]] || return 1 ;;
    go) [ "$row_bin" != "-" ] || return 1 ;;
    esac
    return 0
}

mapfile -t entries < <(
    while IFS= read -r line; do
        case "$line" in '#'* | '') continue ;; esac
        parse_row "$line"
        if ! valid_row; then
            warn "ignoring a manifest row that install.sh could not have written: $line"
            continue
        fi
        printf '%s|%s|%s|%s\n' "$row_method" "$row_pkg" "$row_bin" "$row_role"
    done <"$manifest" | tac
)
if [ "${#entries[@]}" -eq 0 ]; then
    printf '%sNothing to uninstall.%s\n' "$c_bold" "$c_off"
    info "the manifest is empty - install.sh installed nothing"
    exit 0
fi

deps_pkgs=(); tool_pkgs=(); repo_entries=(); cargo_crates=(); go_bins=(); source_pkgs=()
for line in "${entries[@]}"; do
    IFS='|' read -r method pkg bin role <<<"$line"
    [ "$bin" = "-" ] && bin=""
    case "$method:$role" in
    cargo:*) cargo_crates+=("$pkg|$bin") ;;
    go:*) go_bins+=("$pkg|$bin") ;;
    source:*) source_pkgs+=("$pkg|$bin") ;;
    copr:* | *:repo) repo_entries+=("$method|$pkg") ;;
    *:toolchain) tool_pkgs+=("$method|$pkg") ;;
    *) deps_pkgs+=("$method|$pkg|$bin") ;;
    esac
done

printf '%s%spibble uninstaller%s%s\n' "$c_bold" "$c_blue" "$c_off" "$([ "$dry_run" = 1 ] && printf ' (dry run)')"
info "manifest: $manifest"
info "${#deps_pkgs[@]} package(s), ${#cargo_crates[@]} cargo, ${#go_bins[@]} go, ${#source_pkgs[@]} source-built, ${#tool_pkgs[@]} toolchain/build dep(s)"

# ---------------------------------------------------------- stop the daemons ---

step "Stopping daemons"
qs_instances=""
command -v qs >/dev/null 2>&1 && qs_instances="$(qs list --all 2>/dev/null || true)"
if pgrep -f "qs -p $repo" >/dev/null 2>&1 || grep -q "$repo/shell.qml" <<<"$qs_instances"; then
    # Pulling quickshell out from under a live daemon leaves a process with no
    # binary behind it, so this has to happen first.
    run "$repo/pibble" stop >/dev/null 2>&1 || true
    ok "pibble daemon stopped"
else
    skip "pibble daemon - not running"
fi
# Only the helpers whose package is about to come off: a clipboard watcher or
# wallpaper daemon over something that was here before pibble is the user's
# own, and stays up.
manifest_has_bin() {
    local e b
    for e in "${entries[@]}"; do
        IFS='|' read -r _ _ b _ <<<"$e"
        [ "$b" = "$1" ] && return 0
    done
    return 1
}
stop_helper() {
    # stop_helper LABEL PATTERN - the pattern is a pgrep regex, matched
    # against the whole command line
    local label="$1" pattern="$2"
    pgrep -f "$pattern" >/dev/null 2>&1 || return 0
    if ask_yn "stop $label?" y; then
        run pkill -f "$pattern" || true
        ok "$label stopped"
    else
        skip "$label - left running"
    fi
}
# install.sh starts the watcher as `wl-paste --type text --watch cliphist
# store`, so the type sits between the two words
if manifest_has_bin wl-copy || manifest_has_bin cliphist; then
    stop_helper "the clipboard watcher (wl-paste --watch)" 'wl-paste .*--watch cliphist'
fi
if manifest_has_bin awww || manifest_has_bin awww-daemon; then
    stop_helper awww-daemon '(^|/)awww-daemon( |$)'
fi

# ------------------------------------------------------------- pm packages ---

# dnf, zypper and apt answer "something else needs this" by removing the
# something else as well, and -y says yes to that on the user's behalf. So the
# removal is tested first, and refused unless it takes nothing with it that
# isn't on the list. Both tests are read-only and need no root. pacman and xbps
# refuse on their own, apk keeps whatever is still needed, and a nix profile
# entry has no dependents.
pm_remove_is_safe() {
    local pm="$1"; shift
    local out line name p listed extra=""
    # dnf5 can be asked for the whole transaction without root and without
    # running it. What may go along is what dnf pulled in by itself as a
    # dependency; anything the user asked for by name may not.
    if [ "$pm" = dnf ] && command -v dnf5 >/dev/null 2>&1; then
        local users
        out="$(LC_ALL=C dnf5 remove --assumeno "$@" 2>/dev/null || true)"
        users="$(dnf5 -q repoquery --userinstalled --qf '%{name}\n' 2>/dev/null || true)"
        if [ -n "$users" ] && grep -q '^Removing:' <<<"$out"; then
            while IFS= read -r line; do
                # package rows are indented by one space; the summary's
                # " Removing: 3 packages" is not one
                case "$line" in ' '[!\ ]*) ;; *) continue ;; esac
                name="${line# }"; name="${name%% *}"
                case "$name" in *:) continue ;; esac
                listed=0
                for p in "$@"; do
                    [ "$p" = "$name" ] && { listed=1; break; }
                done
                [ "$listed" = 1 ] && continue
                grep -qxF "$name" <<<"$users" && extra="$extra $name"
            done <<<"$out"
            [ -z "$extra" ] && return 0
            warn "not removing $*: it would take these with it:$extra"
            return 1
        fi
        # couldn't read the plan: fall through to the stricter rpm test
    fi
    case "$pm" in
    dnf | zypper)
        command -v rpm >/dev/null 2>&1 || return 0
        # only what is still installed: rpm stops at a name it doesn't know
        # before it has tested any of the others
        local present=()
        for p in "$@"; do
            rpm -q "$p" >/dev/null 2>&1 && present+=("$p")
        done
        [ "${#present[@]}" -eq 0 ] && return 0
        out="$(LC_ALL=C rpm -e --test "${present[@]}" 2>&1)" && return 0
        warn "not removing ${present[*]}: other installed packages depend on it"
        while IFS= read -r line; do
            case "$line" in *"needed by"*) info "  ${line#"${line%%[![:space:]]*}"}" ;; esac
        done <<<"$out"
        return 1
        ;;
    apt)
        # as with dnf: what apt installed by itself as a dependency may go
        # along, what was asked for by name may not
        local autos
        autos="$(apt-mark showauto 2>/dev/null || true)"
        out="$(LC_ALL=C apt-get remove -s "$@" 2>/dev/null || true)"
        while IFS= read -r line; do
            case "$line" in Remv\ *) ;; *) continue ;; esac
            name="${line#Remv }"; name="${name%% *}"
            listed=0
            for p in "$@"; do
                [ "${p%%:*}" = "${name%%:*}" ] && { listed=1; break; }
            done
            [ "$listed" = 1 ] && continue
            grep -qxF -e "$name" -e "${name%%:*}" <<<"$autos" || extra="$extra $name"
        done <<<"$out"
        [ -z "$extra" ] && return 0
        warn "not removing $*: it would take these with it:$extra"
        return 1
        ;;
    esac
    return 0
}

pm_remove() {
    local pm="$1"; shift
    pm_remove_is_safe "$pm" "$@" || return 1
    case "$pm" in
    # the user profile, so no sudo - and entries go by their last attribute
    # ("qt6.qtmultimedia" was installed under the name "qtmultimedia")
    nix)
        local p rc=0
        for p in "$@"; do
            run nix --extra-experimental-features nix-command --extra-experimental-features flakes \
                profile remove "${p##*.}" || rc=1
        done
        return $rc
        ;;
    pacman) as_root pacman -Rs --noconfirm "$@" ;;
    dnf) as_root dnf remove -y "$@" ;;
    apt) DEBIAN_FRONTEND=noninteractive as_root apt-get remove -y -qq "$@" ;;
    zypper) as_root zypper --non-interactive remove --clean-deps "$@" ;;
    xbps) as_root xbps-remove -Ry "$@" ;;
    apk) as_root apk del "$@" ;;
    *) fail "don't know how to remove packages with '$pm'"; return 1 ;;
    esac
}

removed=()

# Only what actually came off is dropped from the manifest; anything kept stays
# recorded, so a second run can still remove it later. It runs from an EXIT
# trap as well as at the end: a run stopped half way - Ctrl-C at a later
# question, a terminal closed - has still removed what it removed, and a
# manifest that goes on listing those packages would have the next run trying
# to remove them again.
manifest_rewritten=0
rewrite_manifest() {
    [ "$manifest_rewritten" = 0 ] || return 0
    manifest_rewritten=1
    [ "$dry_run" = 0 ] && [ "${#removed[@]}" -gt 0 ] || return 0
    local tmp line gone r rmethod rpkg
    tmp="$(mktemp)" || return 0
    {
        printf '# pibble install manifest - written by install.sh, read by uninstall.sh\n'
        printf '# method\tpackage\tbinary\trole\n'
    } >"$tmp"
    while IFS= read -r line; do
        case "$line" in '#'* | '') continue ;; esac
        parse_row "$line"
        gone=0
        for r in "${removed[@]}"; do
            IFS=$'\t' read -r rmethod rpkg <<<"$r"
            [ "$row_method" = "$rmethod" ] && [ "$row_pkg" = "$rpkg" ] && { gone=1; break; }
        done
        [ "$gone" = 0 ] && printf '%s\n' "$line" >>"$tmp"
    done <"$manifest"
    mv -- "$tmp" "$manifest"
    if [ "$(grep -cv '^#' "$manifest" || true)" = 0 ]; then
        rm -f -- "$manifest"
    fi
    return 0
}
trap rewrite_manifest EXIT
trap 'exit 130' INT TERM HUP
remove_group() {
    # remove_group LABEL DEFAULT entries... [note]
    #   entries: "method|pkg" or "method|pkg|bin"; a trailing argument with no
    #   "|" in it is a caveat printed under the heading
    local label="$1" default="$2"; shift 2
    [ "$#" -eq 0 ] && return 0
    local note=""
    if [ "${!#}" = "${!#/|/}" ]; then
        note="${!#}"
        set -- "${@:1:$#-1}"
        [ "$#" -eq 0 ] && return 0
    fi
    local e method pkg
    step "$label"
    [ -n "$note" ] && info "$note"
    for e in "$@"; do
        IFS='|' read -r method pkg _ <<<"$e"
        info "$pkg ($method)"
    done
    if ! ask_yn "remove these?" "$default"; then
        skip "kept"
        group_declined=1
        return 0
    fi
    group_declined=0
    # Grouped by package manager so each one runs once. "aur" is recorded for
    # provenance only - an AUR build is an ordinary pacman package by the time
    # it is installed, so it comes off with pacman like any other. The original
    # method is carried alongside, because that is what the manifest rows say
    # and what the rewrite at the end has to match them against.
    local pm i
    for pm in pacman dnf apt zypper xbps apk nix; do
        local list=() origs=()
        for e in "$@"; do
            IFS='|' read -r method pkg _ <<<"$e"
            local mapped="$method"
            [ "$mapped" = aur ] && mapped=pacman
            if [ "$mapped" = "$pm" ]; then
                list+=("$pkg")
                origs+=("$method")
                # makepkg builds and installs a -debug package next to the
                # real one wherever makepkg.conf has debug on; it came from
                # the same build and goes with it
                if [ "$method" = aur ] && pacman -Qq "$pkg-debug" >/dev/null 2>&1; then
                    list+=("$pkg-debug")
                    origs+=("$method")
                fi
            fi
        done
        [ "${#list[@]}" -eq 0 ] && continue
        if pm_remove "$pm" "${list[@]}"; then
            for i in "${!list[@]}"; do
                ok "removed ${list[$i]}"
                removed+=("${origs[$i]}	${list[$i]}")
            done
        else
            # One package refusing to go (something else still needs it)
            # shouldn't abort the rest, so retry them one at a time.
            warn "batch removal failed, retrying individually"
            for i in "${!list[@]}"; do
                if pm_remove "$pm" "${list[$i]}"; then
                    ok "removed ${list[$i]}"
                    removed+=("${origs[$i]}	${list[$i]}")
                else
                    warn "kept ${list[$i]} - something else on the system needs it"
                fi
            done
        fi
    done
}

group_declined=0
remove_group "Dependencies installed for pibble" y ${deps_pkgs[@]+"${deps_pkgs[@]}"}
deps_declined="$group_declined"

# ------------------------------------------------------------ cargo and go ---

if [ "${#cargo_crates[@]}" -gt 0 ]; then
    step "Cargo-built dependencies"
    for e in "${cargo_crates[@]}"; do
        IFS='|' read -r crate bin <<<"$e"
        info "$crate${bin:+ ($bin)}"
    done
    if ask_yn "remove these?" y; then
        for e in "${cargo_crates[@]}"; do
            IFS='|' read -r crate bin <<<"$e"
            # ~/.local is where install.sh puts them; the bare form is for a
            # manifest written before it did
            if run cargo uninstall --root "$HOME/.local" "$crate" >/dev/null 2>&1 ||
                run cargo uninstall "$crate" >/dev/null 2>&1; then
                ok "removed $crate"
                removed+=("cargo	$crate")
            else
                warn "cargo uninstall $crate failed - remove ${bin:+$HOME/.local/bin/$bin} by hand"
            fi
        done
    else
        skip "kept"
    fi
fi

if [ "${#go_bins[@]}" -gt 0 ]; then
    step "Go-built dependencies"
    # `|| true`: with go itself already gone this substitution fails, and under
    # set -e that would end the run before the manifest is rewritten
    gobin="$(go env GOBIN 2>/dev/null || true)"
    [ -z "$gobin" ] && gobin="$(go env GOPATH 2>/dev/null || printf '%s/go' "$HOME")/bin"
    for e in "${go_bins[@]}"; do
        IFS='|' read -r module bin <<<"$e"
        info "$bin ($gobin/$bin)"
    done
    if ask_yn "remove these?" y; then
        for e in "${go_bins[@]}"; do
            IFS='|' read -r module bin <<<"$e"
            # `go install` has no uninstall; the binary is the whole install.
            if [ -f "$gobin/$bin" ] || [ -L "$gobin/$bin" ]; then
                run rm -f -- "$gobin/$bin"
                ok "removed $gobin/$bin"
                removed+=("go	$module")
            else
                skip "$bin - not where go put it, left alone"
                removed+=("go	$module")
            fi
        done
    else
        skip "kept"
    fi
fi

# --------------------------------------------------------- source installs ---

if [ "${#source_pkgs[@]}" -gt 0 ]; then
    step "Source-built dependencies"
    for e in "${source_pkgs[@]}"; do
        IFS='|' read -r pkg bin <<<"$e"
        filelist="$state_dir/files-$pkg.txt"
        if [ -r "$filelist" ]; then
            count=$(grep -c . "$filelist" || true)
            info "$pkg - $count installed file(s), recorded at install time"
            if ask_yn "remove $pkg's files?" y; then
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    # This runs rm as root on whatever the list says, so the
                    # list is not taken on trust: both builds install under
                    # /usr/local and nowhere else, and a line that is anything
                    # other than a plain path inside it is not theirs.
                    case "$f" in
                    /usr/local/*) ;;
                    *) warn "not removing $f - outside /usr/local, not something the build installed"; continue ;;
                    esac
                    case "$f/" in
                    */../* | */./* | *//*) warn "not removing $f - not a plain path"; continue ;;
                    esac
                    # files and links only (rm -f never takes a directory, but
                    # there is no reason to ask it to). -L as well as -f: a
                    # link whose target went a line earlier (qs -> quickshell)
                    # no longer "exists"
                    [ -L "$f" ] || [ -f "$f" ] || continue
                    as_root rm -f -- "$f" || warn "couldn't remove $f"
                done <"$filelist"
                [ "$dry_run" = 0 ] && rm -f -- "$filelist"
                ok "removed $pkg"
                removed+=("source	$pkg")
            else
                skip "$pkg - kept"
            fi
        else
            # Nothing to replay: `make install` with no record can't be undone
            # safely, so say where it went rather than guessing at rm targets.
            warn "$pkg was built from source with no file list recorded${bin:+ - its binary is $(command -v "$bin" 2>/dev/null || printf 'not on PATH')}"
            info "remove it by hand if you want it gone"
        fi
    done
fi

# ---------------------------------------------------------------- toolchains ---

removed_before_tools="${#removed[@]}"
if [ "$keep_toolchains" = 0 ] && [ "${#tool_pkgs[@]}" -gt 0 ]; then
    # remove_group prints its own heading; this block only adds the caveat
    remove_group "Toolchains and build dependencies" n "${tool_pkgs[@]}" \
        "these were installed only to build the above, but are useful on their own - removing them is usually not what you want"
elif [ "${#tool_pkgs[@]}" -gt 0 ]; then
    step "Toolchains and build dependencies"
    skip "${#tool_pkgs[@]} kept (--keep-toolchains)"
fi

# A dependency that a build package leans on (Debian's qt6-declarative-dev
# needs the QML modules) is refused the first time round, because taking it
# would take the build package too. Once those are gone it is free to go.
if [ "$deps_declined" = 0 ] && [ "${#removed[@]}" -gt "${removed_before_tools:-0}" ]; then
    waiting=()
    for e in ${deps_pkgs[@]+"${deps_pkgs[@]}"}; do
        IFS='|' read -r method pkg _ <<<"$e"
        gone=0
        for r in "${removed[@]}"; do
            [ "$r" = "$method	$pkg" ] && { gone=1; break; }
        done
        [ "$gone" = 0 ] && waiting+=("$e")
    done
    [ "${#waiting[@]}" -gt 0 ] && remove_group "Dependencies kept back earlier" y "${waiting[@]}"
fi

# --------------------------------------------------------------- extra repos ---

if [ "${#repo_entries[@]}" -gt 0 ]; then
    step "Package repositories"
    for e in "${repo_entries[@]}"; do
        IFS='|' read -r method name <<<"$e"
        info "$name ($method)"
    done
    if ask_yn "remove these?" y; then
        for e in "${repo_entries[@]}"; do
            IFS='|' read -r method name <<<"$e"
            case "$method" in
            # remove rather than disable: install.sh only records a COPR it
            # switched on itself, and disabling leaves its .repo file behind
            copr)
                if as_root dnf -y copr remove "$name" || as_root dnf -y copr disable "$name"; then
                    ok "removed $name"
                    removed+=("copr	$name")
                else
                    warn "couldn't remove $name"
                fi
                ;;
            *) warn "don't know how to disable $name ($method)" ;;
            esac
        done
    else
        skip "kept"
    fi
fi

# ------------------------------------------------------- rewrite the manifest ---

rewrite_manifest

step "Done"
if [ "$dry_run" = 1 ]; then
    info "dry run - nothing was removed"
elif [ -f "$manifest" ]; then
    info "some entries were kept; $manifest still lists them"
else
    info "everything install.sh added has been removed"
fi
# apt alone leaves behind what a package pulled in with it
for r in ${removed[@]+"${removed[@]}"}; do
    case "$r" in apt$'\t'*)
        info "apt keeps the libraries those packages brought with them; 'sudo apt autoremove' clears them"
        break
        ;;
    esac
done
info "your settings and caches were not touched:"
info "  ${XDG_STATE_HOME:-$HOME/.local/state}/quickshell   (settings, launch counts, notification cache)"
info "  ${XDG_CACHE_HOME:-$HOME/.cache}/pibble             (thumbnails, blurs, video proxies)"
