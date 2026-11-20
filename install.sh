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
#                                and the app (python/, bin/, data/)
#   <prefix>/bin/ensconce        symlink onto ensconce.sh
#   <prefix>/bin/ensconce-gui    symlink onto the app's launcher
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
APP_ID=eu.kiwinetwork.Ensconce
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"

say() { printf ':: %s\n' "$*"; }

# kiwi exports KIWI_GUI=0/1; standalone installs fall back to checking for
# the GTK4 stack, the same test kiwi uses
want_gui() {
    [[ ${KIWI_GUI:-} == 0 ]] && return 1
    [[ -n ${KIWI_GUI:-} ]] && return 0
    [[ -e /usr/lib64/girepository-1.0/Gtk-4.0.typelib ||
       -e /usr/lib/girepository-1.0/Gtk-4.0.typelib ]]
}

refresh_desktop() {
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -qtf "$DATA_HOME/icons/hicolor" 2>/dev/null || true
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database -q "$APPS" 2>/dev/null || true
}

install_gui() {
    say "installing the app (ensconce-gui) + desktop entry + icon"
    cp -r "$SRC/src/ensconce" "$LIBDIR/python/ensconce"
    find "$LIBDIR/python" -name __pycache__ -type d -prune -exec rm -rf {} +
    install -Dm755 "$SRC/bin/ensconce-gui"      "$LIBDIR/bin/ensconce-gui"
    install -Dm755 "$SRC/bin/ensconce-askpass"  "$LIBDIR/bin/ensconce-askpass"
    # the stock icon, kept for "back to the stock icon" in Preferences
    install -Dm644 "$SRC/data/ensconce.svg"     "$LIBDIR/data/ensconce.svg"
    ln -sfn "$LIBDIR/bin/ensconce-gui" "$BIN/ensconce-gui"
    mkdir -p "$APPS"
    sed "s|^Exec=.*|Exec=$BIN/ensconce-gui|" "$SRC/data/ensconce.desktop" > "$APPS/$APP_ID.desktop"
    install -Dm644 "$SRC/data/ensconce.svg" "$ICON_DIR/$APP_ID.svg"
    # an update must not undo the icon chosen in Preferences
    "$LIBDIR/bin/ensconce-gui" --apply-icon || say "kept the stock icon"
    refresh_desktop
}

do_install() {
    say "installing ensconce runtime to $LIBDIR"
    # Clear the tree first so files dropped upstream don't linger across
    # updates. ${LIBDIR:?} so an empty PREFIX can never make this "rm -rf /lib".
    rm -rf "${LIBDIR:?}/lib" "${LIBDIR:?}/steps" "${LIBDIR:?}/config.example" \
           "${LIBDIR:?}/python" "${LIBDIR:?}/bin" "${LIBDIR:?}/data"
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

    if want_gui; then
        install_gui
    else
        say "no GTK4 stack (or KIWI_GUI=0) — skipping the app"
        rm -f "$BIN/ensconce-gui" "$APPS/$APP_ID.desktop"
    fi

    if [[ -f "$CONF_DIR/settings.sh" ]]; then
        say "keeping existing config in $CONF_DIR"
    else
        say "no config yet — create one with: ensconce --init"
        say "  or bring one over from another machine: ensconce --export"
    fi

    say "done — try: ensconce --list-steps  |  ensconce --dry-run  |  ensconce-gui"
}

do_update() {
    do_install
    # Progress state refers to step names, which are stable across versions;
    # nothing to migrate. A half-finished run resumes where it left off.
}

do_uninstall() {
    say "removing $BIN/ensconce, the app and $LIBDIR"
    rm -f "$BIN/ensconce" "$BIN/ensconce-gui" "$APPS/$APP_ID.desktop" "$ICON_DIR/$APP_ID.svg"
    rm -rf "${LIBDIR:?}"
    refresh_desktop

    # The exports folder (~/Ensconce, or the one chosen in the app) is never
    # touched: other computers read it.
    if [[ "${KIWI_PURGE:-0}" == 1 || "${1:-}" == "--purge" ]]; then
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
