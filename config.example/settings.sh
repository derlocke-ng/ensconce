#!/bin/bash
# Ensconce — Configuration settings
#
# Copy this directory to config/ and edit to match your setup:
#   ./ensconce.sh --init
#
# This file is sourced by ensconce.sh

# Nextcloud server URL (leave empty to skip Nextcloud preseed step)
NEXTCLOUD_SERVER=""

# ── SSH (step: ssh) ─────────────────────────────────────────────────────────
# Each setting is skipped when empty. Paths are relative to $HOME.

# A folder Nextcloud keeps in sync, holding your ssh `config`. ~/.ssh/config
# becomes a link to it, so every machine reads the same config while
# known_hosts stays local. List the folder in nextcloud/folders.list too:
#   .ssh/.sshsynched|/ssh
SSH_SYNCED_DIR=""            # e.g. ".ssh/.sshsynched"

# The directory your config's ControlPath points into, for example
#   ControlPath ~/.ssh/control_sockets/%C
# ssh does not create it. Keep it outside the synced folder: sockets cannot
# be synced.
SSH_CONTROL_DIR=""           # e.g. ".ssh/control_sockets"

# The SSH agent for the desktop session:
#   bitwarden  the Bitwarden Flatpak's agent: keys stay in your vault and
#              Bitwarden asks before each use. Needs com.bitwarden.desktop in
#              flatpaks.list, and the agent turned on in Bitwarden (Settings →
#              "Enable SSH agent"). GNOME's own agent is masked, so it cannot
#              take SSH_AUTH_SOCK back
#   gnome      GNOME's agent again — undoes "bitwarden"
#   (empty)    leave the agent as it is
SSH_AGENT=""

# ── kiwi apps (step: kiwi) ──────────────────────────────────────────────────
# Installs kiwi-updater if it is missing, then the apps in kiwi-apps.list:
#   recommended  user + system scope: one password now, passwordless updates
#   manual       user + system scope, every system change asks for a password
#   minimal      user scope only, never root (enough for user-only apps)
#   (empty)      don't install kiwi-updater
KIWI_INSTALL=""
