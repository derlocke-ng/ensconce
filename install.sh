#!/usr/bin/env bash
# installer for ensconce — kiwi convention: ./install.sh install|update|uninstall
#
# User scope ONLY: ensconce configures *your* desktop session, and the steps
# that touch system state (rpm-ostree, /etc, GDM) prompt for sudo themselves.
# Running the whole thing as root would put the dconf and Flatpak settings on
# the wrong account.
#
# Layout:
#   <prefix>/share/ensconce/     runtime (ensconce.sh, lib/, steps/, config.example/)
#   <prefix>/bin/ensconce        symlink onto the above
#   ~/.config/ensconce/          your config — never touched by install/uninstall
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-install}"

[[ "${KIWI_SCOPE:-user}" == "user" ]] || {
    echo "error: ensconce is user-only (SCOPE=user)" >&2; exit 1; }

PREFIX="${KIWI_PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
LIBDIR="$PREFIX/share/ensconce"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ensconce"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ensconce"

say() { printf ':: %s\n' "$*"; }

do_install() {
    say "installing ensconce runtime to $LIBDIR"
    # Clear the tree first so files dropped upstream don't linger across
    # updates. ${LIBDIR:?} so an empty PREFIX can never make this "rm -rf /lib".
    rm -rf "${LIBDIR:?}/lib" "${LIBDIR:?}/steps" "${LIBDIR:?}/config.example"
    mkdir -p "$LIBDIR"

    cp -r "$SRC/lib" "$SRC/steps" "$SRC/config.example" "$LIBDIR/"
    install -Dm755 "$SRC/ensconce.sh"     "$LIBDIR/ensconce.sh"
    install -Dm755 "$SRC/dconf-backup.sh" "$LIBDIR/dconf-backup.sh"

    # Marker: tells ensconce this is an installed copy, so --init writes the
    # config to ~/.config/ensconce instead of into the (read-only) runtime dir
    touch "$LIBDIR/.installed"

    say "linking $BIN/ensconce"
    mkdir -p "$BIN"
    ln -sfn "$LIBDIR/ensconce.sh" "$BIN/ensconce"

    if [[ -f "$CONF_DIR/settings.sh" ]]; then
        say "keeping existing config in $CONF_DIR"
    else
        say "no config yet — create one with: ensconce --init"
        say "  or bring one over from another machine: ensconce --export"
    fi

    say "done — try: ensconce --list-steps  |  ensconce --dry-run"
}

do_update() {
    do_install
    # Progress state refers to step names, which are stable across versions;
    # nothing to migrate. A half-finished run resumes where it left off.
}

do_uninstall() {
    say "removing $BIN/ensconce and $LIBDIR"
    rm -f "$BIN/ensconce"
    rm -rf "${LIBDIR:?}"

    if [[ "${1:-}" == "--purge" ]]; then
        say "purging config and progress state"
        rm -rf "$CONF_DIR" "$STATE_DIR"
    else
        say "kept: $CONF_DIR (your config) and $STATE_DIR (progress)"
        say "  remove them with: $0 uninstall --purge"
    fi
}

case "$ACTION" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) shift || true; do_uninstall "${1:-}" ;;
    *) echo "usage: $0 install|update|uninstall [--purge]" >&2; exit 1 ;;
esac
