#!/bin/bash
# lib/ssh.sh - SSH paths shared by the ssh step and --export

# The Bitwarden Flatpak binds its SSH agent inside its own data directory:
# $HOME/.var/app/<id>/data when it sees container=flatpak, $HOME otherwise
# (bitwarden/clients: apps/desktop/desktop_native/ssh_agent/src/server/listener/unix.rs).
BITWARDEN_APP_ID="com.bitwarden.desktop"
BITWARDEN_SSH_SOCK="$HOME/.var/app/$BITWARDEN_APP_ID/data/.bitwarden-ssh-agent.sock"

# SSH_AGENT=bitwarden is this file. environment.d is read by the systemd user
# manager, so the whole desktop session gets it, and a late name so it wins
# over anything else that sets SSH_AUTH_SOCK there.
SSH_AGENT_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/90-ensconce-ssh-agent.conf"

# Written by ensconce; how a file can be recognised as ours before removing it
ENSCONCE_MARKER="# Written by ensconce"

# A settings path: relative paths are relative to $HOME, like folders.list
home_path() {
    if [[ "$1" == /* ]]; then
        echo "$1"
    else
        echo "$HOME/$1"
    fi
}

# The other way round, for --export: $HOME-relative if it is under $HOME
# (which on Silverblue is /var/home/<user> behind a /home symlink)
home_relative() {
    local p="$1" home
    home=$(readlink -f "$HOME")
    p=$(readlink -m "$p")
    if [[ "$p" == "$home"/* ]]; then
        echo "${p#"$home"/}"
    else
        echo "$p"
    fi
}
