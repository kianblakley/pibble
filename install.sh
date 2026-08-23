#!/usr/bin/env bash
# pibble installer: pick a language, install the dependencies the shell needs,
# and optionally start the daemons.
#
# Everything this script installs is appended to a manifest (see $manifest
# below) recording *how* it was installed. ./uninstall.sh replays that manifest
# backwards, so it removes exactly what this script added - anything already
# present when the installer ran is never recorded, and therefore never
# removed. That is the whole reason the manifest exists: a blind
# `<pm> remove ffmpeg` on uninstall would take out whatever else on the system
# depends on it.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/pibble"
manifest="$state_dir/install-manifest.tsv"

# ---------------------------------------------------------------- options ---

dry_run=0
assume_yes=0
opt_language=""
opt_daemons=""
skip_deps=0
only_deps=""
skip_list=""
install_optional=0

usage() {
    cat <<USAGE
pibble installer

Usage: ./install.sh [options]

Options:
  --language ID     set the shell's language without asking (see --list-languages)
  --daemons LIST    comma-separated daemons to start without asking:
                    pibble, clipboard, wallpaper, none, all
  --only LIST       only consider these dependencies (comma-separated keys)
  --skip LIST       never touch these dependencies (comma-separated keys)
  --no-deps         skip dependency installation entirely
  --all             say yes to the optional dependencies too (wallpaper
                    backends, colour-picker helpers), not just the recommended
  --yes, -y         non-interactive: accept the recommended answer everywhere
  --dry-run         print every command that would run, install nothing
  --list-deps       print the dependency keys --only/--skip accept and exit
  --list-languages  print the language ids this shell ships and exit
  --help, -h        show this message

Environment (honoured when set, useful for unattended runs):
  PIBBLE_INSTALL_LANG      same as --language
  PIBBLE_INSTALL_DAEMONS   same as --daemons
  PIBBLE_AUR_HELPER        AUR helper to use on Arch (default: autodetect)
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
    --language) opt_language="${2:-}"; shift 2 ;;
    --language=*) opt_language="${1#*=}"; shift ;;
    --daemons) opt_daemons="${2:-}"; shift 2 ;;
    --daemons=*) opt_daemons="${1#*=}"; shift ;;
    --only) only_deps="${2:-}"; shift 2 ;;
    --only=*) only_deps="${1#*=}"; shift ;;
    --skip) skip_list="${2:-}"; shift 2 ;;
    --skip=*) skip_list="${1#*=}"; shift ;;
    --no-deps) skip_deps=1; shift ;;
    --all) install_optional=1; shift ;;
    --yes | -y) assume_yes=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --list-deps) list_deps_only=1; shift ;;
    --list-languages) list_languages_only=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

opt_language="${opt_language:-${PIBBLE_INSTALL_LANG:-}}"
opt_daemons="${opt_daemons:-${PIBBLE_INSTALL_DAEMONS:-}}"

# ------------------------------------------------------------------ output ---

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

# Every mutating command goes through this, so --dry-run is total rather than
# best-effort: nothing outside run() writes to the system.
run() {
    if [ "$dry_run" = 1 ]; then
        printf '    %s$ %s%s\n' "$c_dim" "$*" "$c_off"
        return 0
    fi
    "$@"
}

ask_yn() {
    # ask_yn "question" default(y|n)
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

# ----------------------------------------------------------------- manifest ---

manifest_init() {
    [ "$dry_run" = 1 ] && return 0
    mkdir -p "$state_dir"
    [ -f "$manifest" ] && return 0
    {
        printf '# pibble install manifest - written by install.sh, read by uninstall.sh\n'
        printf '# method\tpackage\tbinary\trole\n'
    } >"$manifest"
}

# record METHOD PACKAGE BINARY ROLE
#   method: the package manager or builder that installed it (pacman, dnf,
#           apt, zypper, xbps, aur, copr, cargo, cargo-git, go, source)
#   role:   dep | toolchain | repo - uninstall treats each differently
record() {
    if [ "$dry_run" = 1 ]; then
        printf '    %s* manifest: %s\t%s\t%s\t%s%s\n' "$c_dim" "$1" "$2" "$3" "$4" "$c_off"
        return 0
    fi
    manifest_init
    # "-" rather than an empty field: keeps every row four columns wide for
    # anything reading it with a whitespace-splitting IFS.
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:--}" "$4" >>"$manifest"
}

# Pure bash rather than awk: a minimal openSUSE install has no awk at all, and
# nothing else here needs one.
already_recorded() {
    [ -f "$manifest" ] || return 1
    local line method pkg rest
    while IFS= read -r line; do
        case "$line" in '#'* | '') continue ;; esac
        method="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        pkg="${rest%%$'\t'*}"
        [ "$method" = "$1" ] && [ "$pkg" = "$2" ] && return 0
    done <"$manifest"
    return 1
}

# ------------------------------------------------------------------ distro ---

distro_id=""; distro_like=""; distro_name=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_id="${ID:-}"; distro_like="${ID_LIKE:-}"; distro_name="${PRETTY_NAME:-$ID}"
fi

pm=""
case "$distro_id" in
arch | endeavouros | manjaro | cachyos | artix | garuda) pm=pacman ;;
fedora | rhel | centos | rocky | almalinux | nobara | bazzite) pm=dnf ;;
debian | ubuntu | pop | linuxmint | elementary | zorin | raspbian) pm=apt ;;
opensuse* | suse | sles) pm=zypper ;;
void) pm=xbps ;;
alpine) pm=apk ;;
nixos) pm=nix ;;
esac
if [ -z "$pm" ]; then
    case " $distro_like " in
    *" arch "*) pm=pacman ;;
    *" fedora "* | *" rhel "*) pm=dnf ;;
    *" debian "* | *" ubuntu "*) pm=apt ;;
    *" suse "*) pm=zypper ;;
    esac
fi
# last resort: whatever package manager is actually on PATH
if [ -z "$pm" ]; then
    for candidate in pacman dnf apt-get zypper xbps-install apk; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        case "$candidate" in
        apt-get) pm=apt ;;
        xbps-install) pm=xbps ;;
        *) pm="$candidate" ;;
        esac
        break
    done
fi

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

# Flakes and the new CLI are what `nix profile` needs, and neither is on by
# default - passing them per invocation works whether or not the user has
# enabled them in nix.conf, and changes no config of theirs.
nix_cmd() {
    run nix --extra-experimental-features nix-command --extra-experimental-features flakes "$@"
}
nix_query() {
    nix --extra-experimental-features nix-command --extra-experimental-features flakes "$@"
}
# Profile entries go by the last attribute: "qt6.qtmultimedia" is listed, and
# removed, as "qtmultimedia".
nix_name() { printf '%s' "${1##*.}"; }

refreshed=0
pm_refresh() {
    [ "$refreshed" = 1 ] && return 0
    refreshed=1
    # Which packages a distro carries is read out of the package database, so a
    # stale one makes the whole plan wrong (every dependency looks unavailable
    # and falls through to a source build). It is refreshed directly rather
    # than through run(), because even a dry run needs the answers - but a dry
    # run must not sit there asking for a password, so where the refresh would
    # need one it is skipped with a warning instead.
    local sudo_cmd=""
    if [ "$(id -u)" != 0 ]; then
        if command -v sudo >/dev/null 2>&1; then sudo_cmd=sudo
        elif command -v doas >/dev/null 2>&1; then sudo_cmd=doas
        fi
        if [ "$dry_run" = 1 ] && ! ${sudo_cmd:-false} -n true 2>/dev/null; then
            warn "dry run: leaving the package database alone (refreshing it needs root)"
            warn "repo availability below is read from the existing cache and may be out of date"
            return 0
        fi
    fi
    case "$pm" in
    nix) ;; # the flake input is fetched per command; nothing to refresh
    pacman) $sudo_cmd pacman -Sy --noconfirm >/dev/null 2>&1 || true ;;
    apt) $sudo_cmd apt-get update -qq >/dev/null 2>&1 || true ;;
    dnf) $sudo_cmd dnf -q makecache >/dev/null 2>&1 || true ;;
    zypper) $sudo_cmd zypper -q --non-interactive refresh >/dev/null 2>&1 || true ;;
    xbps) $sudo_cmd xbps-install -S >/dev/null 2>&1 || true ;;
    apk) $sudo_cmd apk update >/dev/null 2>&1 || true ;;
    esac
}

# Does the distro's own repos carry this package? Everything branches on this
# rather than on a hardcoded per-distro table, so a package that graduates from
# the AUR/COPR into a main repo is picked up without editing this script.
pm_repo_has() {
    local pkg="$1" out
    pm_refresh
    case "$pm" in
    pacman) pacman -Si "$pkg" >/dev/null 2>&1 ;;
    dnf) dnf -q info --available "$pkg" >/dev/null 2>&1 || dnf -q info "$pkg" >/dev/null 2>&1 ;;
    # Captured into a variable and matched with a here-string rather than
    # piped: `grep -q` closes the pipe on its first match, the command
    # upstream dies of SIGPIPE, and `set -o pipefail` then reports the whole
    # pipeline as failed - so an available package reads as missing and the
    # installer silently falls through to a source build. It is a race on how
    # much the upstream command still has to write, so it shows up on a
    # package with a long record (imagemagick) and not a short one.
    apt) out="$(apt-cache show "$pkg" 2>/dev/null || true)"; grep -q '^Package:' <<<"$out" ;;
    # evaluating the attribute is the availability test: it resolves without
    # building or downloading the package itself
    nix) nix_query eval --raw "nixpkgs#$pkg.pname" >/dev/null 2>&1 ;;
    zypper) out="$(zypper -q search --match-exact "$pkg" 2>/dev/null || true)"; grep -q "| $pkg " <<<"$out" ;;
    xbps) xbps-query -R "$pkg" >/dev/null 2>&1 ;;
    apk) apk info -e "$pkg" >/dev/null 2>&1 || { out="$(apk search -x "$pkg" 2>/dev/null || true)"; [ -n "$out" ]; } ;;
    *) return 1 ;;
    esac
}

pm_installed() {
    local pkg="$1"
    case "$pm" in
    pacman) pacman -Qi "$pkg" >/dev/null 2>&1 ;;
    dnf) rpm -q "$pkg" >/dev/null 2>&1 ;;
    apt) [ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" = "install ok installed" ] ;;
    nix) nix_query profile list 2>/dev/null | grep -q "^Name: *$(nix_name "$pkg")$" ;;
    zypper) rpm -q "$pkg" >/dev/null 2>&1 ;;
    xbps) xbps-query "$pkg" >/dev/null 2>&1 ;;
    apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
    esac
}

pm_install() {
    pm_refresh
    case "$pm" in
    # never through as_root: nix installs into the *user* profile, and root's
    # profile is not the one on the user's PATH
    nix)
        for _p in "$@"; do
            nix_cmd profile install "nixpkgs#$_p" || return 1
        done
        ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    dnf) as_root dnf install -y "$@" ;;
    apt) DEBIAN_FRONTEND=noninteractive as_root apt-get install -y -qq "$@" ;;
    zypper) as_root zypper --non-interactive install "$@" ;;
    xbps) as_root xbps-install -y "$@" ;;
    apk) as_root apk add "$@" ;;
    *) fail "no supported package manager found"; return 1 ;;
    esac
}

# ---------------------------------------------------------------- toolchains ---

# Installed on demand only, and recorded with role=toolchain so uninstall can
# offer them separately from the shell's actual dependencies - they are much
# more likely to be something the user wants to keep.
ensure_toolchain() {
    local kind="$1" pkg=""
    case "$kind" in
    rust)
        command -v cargo >/dev/null 2>&1 && return 0
        case "$pm" in
        pacman) pkg="rust" ;;
        dnf) pkg="cargo" ;;
        apt) pkg="cargo" ;;
        zypper) pkg="cargo" ;;
        xbps) pkg="cargo" ;;
        apk) pkg="cargo" ;;
        esac
        ;;
    go)
        command -v go >/dev/null 2>&1 && return 0
        case "$pm" in
        pacman) pkg="go" ;;
        dnf) pkg="golang" ;;
        apt) pkg="golang-go" ;;
        zypper) pkg="go" ;;
        xbps) pkg="go" ;;
        apk) pkg="go" ;;
        esac
        ;;
    build)
        # cmake/ninja/pkg-config, for the source builds
        case "$pm" in
        pacman) pkg="base-devel cmake ninja git" ;;
        dnf) pkg="gcc-c++ cmake ninja-build git pkgconf-pkg-config" ;;
        apt) pkg="build-essential cmake ninja-build git pkg-config" ;;
        zypper) pkg="gcc-c++ cmake ninja git pkg-config" ;;
        xbps) pkg="base-devel cmake ninja git pkg-config" ;;
        apk) pkg="build-base cmake ninja git pkgconf" ;;
        esac
        ;;
    esac
    [ -n "$pkg" ] || { fail "don't know how to install the $kind toolchain on this distro"; return 1; }
    info "installing $kind toolchain ($pkg)"
    # shellcheck disable=SC2086
    pm_install $pkg || return 1
    local p
    for p in $pkg; do
        pm_installed "$p" 2>/dev/null && ! already_recorded "$pm" "$p" && record "$pm" "$p" "" toolchain
    done
    return 0
}

cargo_bin_dir() { printf '%s' "${CARGO_HOME:-$HOME/.cargo}/bin"; }
go_bin_dir() {
    local b
    b="$(go env GOBIN 2>/dev/null || true)"
    [ -n "$b" ] && { printf '%s' "$b"; return 0; }
    printf '%s/bin' "$(go env GOPATH 2>/dev/null || printf '%s/go' "$HOME")"
}

# ------------------------------------------------------------ arch AUR helper ---

aur_helper=""
detect_aur_helper() {
    [ -n "$aur_helper" ] && return 0
    local h
    for h in ${PIBBLE_AUR_HELPER:-} paru yay pikaur trizen; do
        [ -n "$h" ] || continue
        command -v "$h" >/dev/null 2>&1 && { aur_helper="$h"; return 0; }
    done
    return 1
}

aur_install() {
    local pkg="$1" bin="${2:-}"
    info "$pkg: from the AUR"
    if detect_aur_helper; then
        run "$aur_helper" -S --needed --noconfirm "$pkg" || return 1
        # recorded as "aur" for provenance; it is an ordinary pacman package
        # once built, and uninstall removes it as one
        record aur "$pkg" "$bin" dep
        return 0
    fi
    # makepkg refuses to run as root, and building as another user needs a
    # password we can't ask for mid-script - so this is where an unattended
    # root install has to hand back to the user.
    if [ "$(id -u)" = 0 ]; then
        fail "no AUR helper (paru/yay) and makepkg won't run as root - install $pkg manually"
        return 1
    fi
    ensure_toolchain build || return 1
    if [ "$dry_run" = 1 ]; then
        info "would clone and makepkg $pkg from the AUR"
        record aur "$pkg" "$bin" dep
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    run git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$tmp/$pkg" &&
        (cd "$tmp/$pkg" && run makepkg -si --noconfirm)
    local rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && record aur "$pkg" "$bin" dep
    return $rc
}

# ------------------------------------------------------------- dependencies ---

# One row per dependency: key|binary|role|why
# binary empty = a library, presence is checked through the package manager.
deps=(
    "quickshell|qs|required|runs the shell"
    "libnotify|notify-send|recommended|pibble's own alerts - without it they are silently dropped"
    "wl-clipboard|wl-copy|recommended|clipboard reads and copy actions"
    "cliphist|cliphist|recommended|clipboard history"
    "ffmpeg|ffmpeg|recommended|wallpaper and clipboard thumbnails, blurs and previews"
    "qtmultimedia||recommended|live wallpaper previews"
    "matugen|matugen|recommended|wallpaper-derived colour theme"
    "curl|curl|recommended|weather on the clock page"
    "awww|awww|optional|static wallpaper backend"
    "mpvpaper|mpvpaper|optional|live wallpaper backend"
    "grim|grim|optional|the screen colour picker - without it the eyedropper is hidden"
)

# The distro's package name for a dependency, where it differs from the key.
pkg_for() {
    local dep="$1"
    case "$dep:$pm" in
    qtmultimedia:pacman) printf 'qt6-multimedia-ffmpeg' ;;
    qtmultimedia:dnf) printf 'qt6-qtmultimedia' ;;
    qtmultimedia:apt) printf 'qml6-module-qtmultimedia' ;;
    qtmultimedia:zypper) printf 'qt6-multimedia-imports' ;;
    qtmultimedia:xbps) printf 'qt6-multimedia' ;;
    qtmultimedia:apk) printf 'qt6-qtmultimedia' ;;
    qtmultimedia:nix) printf 'qt6.qtmultimedia' ;;
    # Debian/Ubuntu split the binary out of the library package: libnotify4 is
    # the shared object, notify-send lives in libnotify-bin.
    libnotify:apt) printf 'libnotify-bin' ;;
    # openSUSE splits it the same way, under a different name again
    libnotify:zypper) printf 'libnotify-tools' ;;
    # Fedora's main repos ship the patent-free fork under a different name;
    # plain `ffmpeg` there needs RPM Fusion, which this script won't add.
    ffmpeg:dnf) printf 'ffmpeg-free' ;;
    *) printf '%s' "$dep" ;;
    esac
}

# Where a dependency comes from when the distro doesn't package it.
fallback_install() {
    local dep="$1" bin="${2:-}"
    case "$dep" in
    quickshell)
        case "$pm" in
        pacman) aur_install quickshell "$bin" || aur_install quickshell-git "$bin" ;;
        dnf)
            info "enabling COPR errornointernet/quickshell"
            pm_installed dnf-plugins-core || pm_install dnf-plugins-core
            as_root dnf -y copr enable errornointernet/quickshell &&
                record copr errornointernet/quickshell "" repo &&
                pm_install quickshell &&
                record dnf quickshell "$bin" dep
            ;;
        *) build_quickshell ;;
        esac
        ;;
    matugen)
        case "$pm" in
        pacman) aur_install matugen-bin "$bin" || aur_install matugen "$bin" ;;
        *) cargo_install matugen matugen ;;
        esac
        ;;
    awww)
        case "$pm" in
        pacman) aur_install awww "$bin" || cargo_git_install awww https://codeberg.org/LGFae/awww awww ;;
        *) cargo_git_install awww https://codeberg.org/LGFae/awww awww ;;
        esac
        ;;
    cliphist)
        case "$pm" in
        pacman) aur_install cliphist "$bin" ;;
        *) go_install cliphist go.senan.xyz/cliphist ;;
        esac
        ;;
    mpvpaper)
        case "$pm" in
        pacman) aur_install mpvpaper "$bin" ;;
        *) build_mpvpaper ;;
        esac
        ;;
    *)
        fail "no fallback recipe for $dep on this distro"
        return 1
        ;;
    esac
}

cargo_install() {
    local bin="$1" crate="$2"
    ensure_toolchain rust || return 1
    info "building $crate with cargo (this takes a few minutes)"
    run cargo install --locked "$crate" || return 1
    record cargo "$crate" "$bin" dep
}

cargo_git_install() {
    local bin="$1" url="$2" crate="$3"
    ensure_toolchain rust || return 1
    ensure_toolchain build || return 1
    info "building $crate from $url (this takes a few minutes)"
    run cargo install --locked --git "$url" || return 1
    record cargo "$crate" "$bin" dep
}

go_install() {
    local bin="$1" module="$2"
    ensure_toolchain go || return 1
    info "building $module with go"
    run env GOFLAGS=-mod=mod go install "$module@latest" || return 1
    record go "$module" "$bin" dep
}

# A `make install` leaves no record of itself, so uninstall.sh has nothing to
# undo unless the file list the build system wrote is kept here. Both builders
# below produce one; this normalises it into $state_dir/files-<pkg>.txt.
save_file_list() {
    local pkg="$1" src="$2"
    [ "$dry_run" = 1 ] && { printf '    %s* would record %s'"'"'s installed files from %s%s\n' "$c_dim" "$pkg" "$src" "$c_off"; return 0; }
    [ -r "$src" ] || { warn "$pkg installed but its file list wasn'"'"'t written - uninstall won'"'"'t be able to remove it automatically"; return 0; }
    mkdir -p "$state_dir"
    grep -v '"'"'^#'"'"' "$src" | grep '"'"'^/'"'"' >"$state_dir/files-$pkg.txt" || true
}

build_mpvpaper() {
    ensure_toolchain build || return 1
    local mpv_dev
    case "$pm" in
    dnf) mpv_dev="mpv-libs-devel wayland-devel wayland-protocols-devel meson" ;;
    apt) mpv_dev="libmpv-dev libwayland-dev wayland-protocols meson" ;;
    zypper) mpv_dev="mpv-devel wayland-devel wayland-protocols-devel meson" ;;
    xbps) mpv_dev="mpv-devel wayland-devel wayland-protocols meson" ;;
    *) fail "don't know mpvpaper's build deps on this distro"; return 1 ;;
    esac
    # shellcheck disable=SC2086
    pm_install $mpv_dev || return 1
    for p in $mpv_dev; do
        already_recorded "$pm" "$p" || record "$pm" "$p" "" toolchain
    done
    if [ "$dry_run" = 1 ]; then
        info "would clone and build mpvpaper from https://github.com/GhostNaN/mpvpaper"
        record source mpvpaper mpvpaper dep
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    run git clone --depth 1 https://github.com/GhostNaN/mpvpaper "$tmp/mpvpaper" &&
        (cd "$tmp/mpvpaper" && run meson setup build && run ninja -C build &&
            as_root ninja -C build install) || { rm -rf "$tmp"; return 1; }
    save_file_list mpvpaper "$tmp/mpvpaper/build/meson-logs/install-log.txt"
    rm -rf "$tmp"
    record source mpvpaper mpvpaper dep
}

# Quickshell isn't packaged outside Arch/Fedora/Nix, so on everything else it
# gets built. It needs Qt 6.6+; distros older than that can't run pibble at all,
# which is worth saying plainly rather than failing halfway through a build.
build_quickshell() {
    ensure_toolchain build || return 1
    local qt_deps=""
    case "$pm" in
    apt) qt_deps="qt6-base-dev qt6-declarative-dev qt6-declarative-private-dev qt6-wayland qt6-wayland-dev qt6-wayland-private-dev qt6-shadertools-dev libwayland-dev wayland-protocols libdrm-dev libgbm-dev libjemalloc-dev libpam0g-dev libpipewire-0.3-dev libcli11-dev spirv-tools qml6-module-qtqml-workerscript qml6-module-qtquick-controls qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtquick-layouts" ;;
    zypper) qt_deps="qt6-base-devel qt6-declarative-devel qt6-declarative-private-devel qt6-wayland-devel qt6-shadertools-devel wayland-devel wayland-protocols-devel libdrm-devel Mesa-libgbm-devel jemalloc-devel pam-devel pipewire-devel cli11-devel" ;;
    xbps) qt_deps="qt6-base-devel qt6-declarative-devel qt6-wayland-devel qt6-shadertools-devel wayland-devel wayland-protocols libdrm-devel jemalloc-devel pam-devel libpipewire-devel cli11" ;;
    *) fail "don't know Quickshell's build deps on this distro - see https://quickshell.outfoxxed.me/docs/guide/install"; return 1 ;;
    esac
    # shellcheck disable=SC2086
    pm_install $qt_deps || { fail "couldn't install Quickshell's build dependencies"; return 1; }
    local p
    for p in $qt_deps; do
        already_recorded "$pm" "$p" || record "$pm" "$p" "" toolchain
    done

    local qt_ver=""
    if command -v qmake6 >/dev/null 2>&1; then qt_ver="$(qmake6 -query QT_VERSION 2>/dev/null)"; fi
    if [ -n "$qt_ver" ]; then
        local major minor
        major="${qt_ver%%.*}"; minor="${qt_ver#*.}"; minor="${minor%%.*}"
        if [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -lt 6 ]; }; then
            fail "Qt $qt_ver is too old for Quickshell (needs 6.6+). Upgrade the distro or install Quickshell from Nix."
            return 1
        fi
    fi

    if [ "$dry_run" = 1 ]; then
        info "would clone and build Quickshell from https://git.outfoxxed.me/quickshell/quickshell"
        record source quickshell qs dep
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    info "building Quickshell from source (this takes a while)"
    run git clone --recursive https://git.outfoxxed.me/quickshell/quickshell "$tmp/quickshell" &&
        (cd "$tmp/quickshell" &&
            run cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release -DDISTRIBUTOR=pibble-installer &&
            run cmake --build build &&
            as_root cmake --install build) || {
        rm -rf "$tmp"
        fail "Quickshell build failed - see https://quickshell.outfoxxed.me/docs/guide/install"
        return 1
    }
    save_file_list quickshell "$tmp/quickshell/build/install_manifest.txt"
    rm -rf "$tmp"
    record source quickshell qs dep
}

dep_present() {
    local dep="$1" bin="$2"
    if [ -n "$bin" ]; then
        command -v "$bin" >/dev/null 2>&1 && return 0
        [ "$dep" = awww ] && command -v swww >/dev/null 2>&1 && return 0
        return 1
    fi
    pm_installed "$(pkg_for "$dep")"
}

install_dep() {
    local dep="$1" bin="$2" pkg
    pkg="$(pkg_for "$dep")"
    if pm_repo_has "$pkg"; then
        info "$dep: from $pm as '$pkg'"
        if pm_install "$pkg"; then
            record "$pm" "$pkg" "$bin" dep
            return 0
        fi
        warn "$pkg failed to install from the repos, trying a fallback"
    else
        info "$dep: not in this distro's repos, building/fetching it instead"
    fi
    fallback_install "$dep" "$bin"
}

# ------------------------------------------------------------- 1. language ---

# Read straight out of the shell's own catalogue so the two can't drift apart
# (config/Defaults.qml is the single source of truth - Settings.heal() rejects
# any id it doesn't list).
# Pure bash rather than sed: a minimal nix environment ships neither sed nor
# python3, and losing the language step there is worse than a few lines here.
read_languages() {
    local line id name
    while IFS= read -r line; do
        case "$line" in
        *'{ id: "'*'name: "'*) ;;
        *) continue ;;
        esac
        id="${line#*id: \"}"; id="${id%%\"*}"
        name="${line#*name: \"}"; name="${name%%\"*}"
        [ -n "$id" ] && printf '%s\t%s\n' "$id" "$name"
    done <"$repo/config/Defaults.qml"
}

lang_ids() { read_languages | cut -f1; }

settings_file() {
    local shell_id
    shell_id="$(printf '%s' "$repo/shell.qml" | md5sum | cut -d' ' -f1)"
    printf '%s/quickshell/by-shell/%s/settings.json' "${XDG_STATE_HOME:-$HOME/.local/state}" "$shell_id"
}

write_language() {
    local lang="$1" file
    file="$(settings_file)"
    if [ "$dry_run" = 1 ]; then
        printf '    %s$ set "language": "%s" in %s%s\n' "$c_dim" "$lang" "$file" "$c_off"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    if [ ! -s "$file" ]; then
        # A partial file is fine: the JsonAdapter fills in every key it doesn't
        # find with the declared default.
        printf '{\n    "language": "%s"\n}\n' "$lang" >"$file"
        return 0
    fi
    # Patch in place, preserving everything else the user has set. python3 and
    # jq are both common but neither is guaranteed, hence the sed fallback.
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$lang" <<'PY'
import json, sys
path, lang = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data["language"] = lang
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
    elif command -v jq >/dev/null 2>&1; then
        local tmp; tmp="$(mktemp)"
        jq --arg l "$lang" '.language = $l' "$file" >"$tmp" && mv "$tmp" "$file"
    elif grep -q '"language"' "$file"; then
        sed -i 's/"language": *"[^"]*"/"language": "'"$lang"'"/' "$file"
    else
        sed -i '0,/{/s//{\n    "language": "'"$lang"'",/' "$file"
    fi
}

choose_language() {
    step "Language"
    local ids names n i
    mapfile -t ids < <(lang_ids)
    if [ "${#ids[@]}" -eq 0 ]; then
        warn "couldn't read the language catalogue from config/Defaults.qml - leaving the language alone"
        return 0
    fi

    if [ -n "$opt_language" ]; then
        if ! grep -qx "$opt_language" <<<"$(printf '%s\n' "${ids[@]}")"; then
            fail "unknown language id '$opt_language' (known: $(printf '%s ' "${ids[@]}"))"
            exit 2
        fi
        write_language "$opt_language"
        ok "language set to $opt_language"
        return 0
    fi

    if [ "$assume_yes" = 1 ] || [ ! -t 0 ]; then
        skip "no language given, keeping the default (en)"
        return 0
    fi

    mapfile -t names < <(read_languages | cut -f2)
    for i in "${!ids[@]}"; do
        printf '    %2d) %-4s %s\n' "$((i + 1))" "${ids[$i]}" "${names[$i]}"
    done
    read -r -p "    Choose a language [1-${#ids[@]}, default 1]: " n || n=1
    n="${n:-1}"
    case "$n" in
    '' | *[!0-9]*) warn "not a number, keeping English"; return 0 ;;
    esac
    if [ "$n" -lt 1 ] || [ "$n" -gt "${#ids[@]}" ]; then
        warn "out of range, keeping English"
        return 0
    fi
    write_language "${ids[$((n - 1))]}"
    ok "language set to ${ids[$((n - 1))]} (${names[$((n - 1))]})"
}

# --------------------------------------------------------------- 2. deps ---

check_compositor() {
    # Never installed, only reported: replacing whatever compositor a user
    # already runs is not an installer's call to make.
    local c
    for c in niri Hyprland sway river labwc wayfire; do
        command -v "$c" >/dev/null 2>&1 && { ok "compositor found: $c"; return 0; }
    done
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        ok "a Wayland session is running"
        return 0
    fi
    warn "no Wayland compositor found - pibble needs one (niri, Hyprland, sway, ...). Install it yourself; this script won't pick one for you."
}

install_deps() {
    step "Dependencies"
    if [ -z "$pm" ]; then
        fail "couldn't identify a package manager for ${distro_name:-this system}"
        info "install the dependencies listed in README.md by hand, then re-run with --no-deps"
        return 1
    fi
    # nix installs into the user profile, which - unlike the system
    # configuration - persists across a rebuild and is exactly what an
    # imperative installer should be writing to. The toolchain and source-build
    # fallbacks further down are still wrong here, but nothing reaches them:
    # nixpkgs carries every dependency pibble has, quickshell included.
    if [ "$pm" = nix ]; then
        info "${distro_name:-nix} - installing into your nix profile, not the system config"
        info "to declare them in configuration.nix instead, stop here and add the same"
        info "names to environment.systemPackages."
    else
        info "${distro_name:-unknown distro} - using $pm"
    fi
    [ -z "$only_deps" ] && check_compositor

    local row dep bin role why want
    for row in "${deps[@]}"; do
        IFS='|' read -r dep bin role why <<<"$row"
        if [ -n "$only_deps" ] && [[ ",$only_deps," != *",$dep,"* ]]; then
            continue
        fi
        if [ -n "$skip_list" ] && [[ ",$skip_list," == *",$dep,"* ]]; then
            skip "$dep - skipped (--skip)"
            continue
        fi
        if dep_present "$dep" "$bin"; then
            skip "$dep - already installed"
            continue
        fi
        case "$role" in
        required | recommended) want=y ;;
        optional) [ "$install_optional" = 1 ] && want=y || want=n ;;
        esac
        if ! ask_yn "install $dep? ($why)" "$want"; then
            skip "$dep - skipped"
            continue
        fi
        if install_dep "$dep" "$bin"; then
            ok "$dep installed"
        else
            if [ "$role" = required ]; then
                fail "$dep is required and couldn't be installed - pibble will not run without it"
            else
                warn "$dep couldn't be installed; the features it powers stay off"
            fi
        fi
    done

    if [ "$install_optional" = 0 ] && [ "$assume_yes" = 1 ]; then
        info "optional dependencies were left out; --all installs them too"
    fi

    # Fedora's patent-free build has no libx264, so video wallpaper previews
    # fall back to libopenh264 - and with neither, to decoding the source.
    if command -v ffmpeg >/dev/null 2>&1; then
        encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"
        case "$encoders" in
        *" libx264 "* | *" libopenh264 "*) ;;
        *) warn "this ffmpeg has no H.264 encoder; video wallpaper previews will decode the source instead of a smaller proxy" ;;
        esac
    fi
}

# ------------------------------------------------------------- 3. daemons ---

daemon_wanted() {
    local name="$1"
    case ",$opt_daemons," in
    *",all,"*) return 0 ;;
    *",none,"*) return 1 ;;
    *",$name,"*) return 0 ;;
    esac
    return 1
}

start_daemons() {
    step "Daemons"
    local explicit=0
    [ -n "$opt_daemons" ] && explicit=1

    # pibble itself
    if { [ "$explicit" = 1 ] && daemon_wanted pibble; } ||
        { [ "$explicit" = 0 ] && ask_yn "start the pibble daemon now?" y; }; then
        if command -v qs >/dev/null 2>&1; then
            # `pibble start` execs quickshell and blocks; setsid detaches it so
            # it survives this script exiting and the terminal closing.
            run setsid -f "$repo/pibble" start >/dev/null 2>&1 || true
            ok "pibble daemon started (./pibble toggle to open the launcher)"
        else
            fail "quickshell isn't installed, so the daemon can't start"
        fi
    else
        skip "pibble daemon - not started"
    fi

    # clipboard watcher: cliphist only records what something pipes into it,
    # so without this the clips pane stays empty however much you copy. Two
    # watchers, matching Notifier.clipWatcherFixCommand.
    if command -v cliphist >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
        if { [ "$explicit" = 1 ] && daemon_wanted clipboard; } ||
            { [ "$explicit" = 0 ] && ask_yn "start the clipboard watcher? (clipboard history stays empty without it)" y; }; then
            if pgrep -x wl-paste >/dev/null 2>&1; then
                skip "clipboard watcher - already running"
            else
                run setsid -f wl-paste --type text --watch cliphist store >/dev/null 2>&1 || true
                run setsid -f wl-paste --type image --watch cliphist store >/dev/null 2>&1 || true
                ok "clipboard watcher started"
            fi
        else
            skip "clipboard watcher - not started"
        fi
    else
        skip "clipboard watcher - needs cliphist and wl-clipboard"
    fi

    # wallpaper backend: awww needs its daemon up before `awww img` will do
    # anything. mpvpaper needs nothing running - the wallpaper command spawns
    # it per video (see Defaults.wallCommand).
    local wall_daemon=""
    command -v awww-daemon >/dev/null 2>&1 && wall_daemon=awww-daemon
    [ -z "$wall_daemon" ] && command -v swww-daemon >/dev/null 2>&1 && wall_daemon=swww-daemon
    if [ -n "$wall_daemon" ]; then
        if { [ "$explicit" = 1 ] && daemon_wanted wallpaper; } ||
            { [ "$explicit" = 0 ] && ask_yn "start the wallpaper backend ($wall_daemon)?" y; }; then
            if pgrep -x "$wall_daemon" >/dev/null 2>&1; then
                skip "$wall_daemon - already running"
            else
                run setsid -f "$wall_daemon" >/dev/null 2>&1 || true
                ok "$wall_daemon started"
            fi
        else
            skip "wallpaper backend - not started"
        fi
    else
        skip "wallpaper backend - awww/swww not installed"
    fi

    if [ "$explicit" = 0 ] || ! daemon_wanted none; then
        info ""
        info "None of these survive a reboot. To make them persistent, add them to"
        info "your compositor's autostart, e.g. for niri:"
        info "  spawn-at-startup \"$repo/pibble\" \"start\""
        info "  spawn-at-startup \"sh\" \"-c\" \"wl-paste --type text --watch cliphist store\""
    fi
}

# ------------------------------------------------------------------- main ---

if [ "${list_languages_only:-0}" = 1 ]; then
    read_languages
    exit 0
fi

if [ "${list_deps_only:-0}" = 1 ]; then
    printf '%-14s %-12s %-12s %s\n' KEY BINARY ROLE PURPOSE
    for row in "${deps[@]}"; do
        IFS='|' read -r dep bin role why <<<"$row"
        printf '%-14s %-12s %-12s %s\n' "$dep" "${bin:--}" "$role" "$why"
    done
    exit 0
fi

printf '%s%spibble installer%s%s\n' "$c_bold" "$c_blue" "$c_off" "$([ "$dry_run" = 1 ] && printf ' (dry run)')"
[ "$dry_run" = 1 ] && info "nothing will be installed or changed"

choose_language
if [ "$skip_deps" = 1 ]; then
    step "Dependencies"
    skip "skipped (--no-deps)"
else
    install_deps || warn "some dependencies could not be installed - see above"
fi
start_daemons

step "Done"
if [ -f "$manifest" ] && [ "$dry_run" = 0 ]; then
    installed_count=$(grep -c "$(printf '\tdep$')" "$manifest" || true)
    info "$installed_count package(s) recorded in $manifest"
    info "./uninstall.sh removes exactly those, and nothing that was already here"
fi
info "open the launcher with: $repo/pibble toggle"
