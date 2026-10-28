#!/bin/bash
# Step: ssh
# Description: SSH config from a synced folder, Bitwarden as the SSH agent
#
# Three settings, each skipped when empty (see settings.sh):
#
#   SSH_SYNCED_DIR   ~/.ssh/config becomes a link into a folder Nextcloud keeps
#                    in sync, so every machine reads the same config while
#                    known_hosts stays local to each one
#   SSH_CONTROL_DIR  the directory the config's ControlPath points into; ssh
#                    does not create it, and multiplexing fails without it
#   SSH_AGENT        bitwarden: the Bitwarden Flatpak's agent becomes the
#                    session's SSH_AUTH_SOCK; gnome: back to GNOME's agent

# A settings path the way a person writes it: ~/… under $HOME, else absolute
_ssh_show() {
    local r
    r=$(home_relative "$(home_path "$1")")
    if [[ "$r" == /* ]]; then echo "$r"; else echo "~/$r"; fi
}

# A directory only this user can read, labelled the way SELinux expects for
# anything under ~/.ssh
_ssh_private_dir() {
    local d="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        [[ -d "$d" && "$(stat -c %a "$d")" == 700 ]] \
            || echo -e "${YELLOW}[DRY-RUN]${NC} Would create $d (mode 0700)"
        return 0
    fi
    mkdir -p "$d"
    chmod 700 "$d"
    if command -v restorecon &> /dev/null; then
        restorecon -R "$d" 2>/dev/null || true
    fi
}

# Nothing fills the synced folder unless something syncs it. Not an error —
# it may be synced by hand — but worth saying before ssh silently reads nothing.
_ssh_check_synced() {
    local synced="$1" rel entry
    rel=$(home_relative "$synced")

    while IFS= read -r entry; do
        entry="${entry%%|*}"
        [[ "${entry%/}" == "$rel" ]] && return 0
    done < <(read_list_file "$CONFIG_DIR/nextcloud/folders.list")

    # The client stores the path as it was given, so either spelling of a
    # Silverblue home (/home/<user> or /var/home/<user>) can be in there
    local nc_cfg="$HOME/.config/Nextcloud/nextcloud.cfg"
    if [[ -f "$nc_cfg" ]] && grep -qF -e "localPath=$synced/" \
            -e "localPath=$(readlink -m "$synced")/" "$nc_cfg"; then
        return 0
    fi

    log_warn "~/$rel is in neither nextcloud/folders.list nor the Nextcloud client's folders"
    log_warn "  add it to folders.list, e.g.  $rel|/ssh  — or the config never arrives"
}

_ssh_link_config() {
    local synced link="$HOME/.ssh/config" target rel
    synced=$(home_path "$SSH_SYNCED_DIR")
    target="$synced/config"
    # Relative, so the link means the same on a machine with another user name
    # or home directory
    rel=$(realpath -m --relative-to="$HOME/.ssh" "$target")

    _ssh_private_dir "$synced"
    _ssh_check_synced "$synced"

    if [[ -L "$link" && "$(readlink "$link")" == "$rel" ]]; then
        log_info "Already linked: ~/.ssh/config → $rel"
    elif [[ -L "$link" && "$(readlink -m "$link")" == "$(readlink -m "$target")" ]]; then
        log_info "Making ~/.ssh/config a relative link (same target)"
        run_cmd ln -sfn "$rel" "$link"
    elif [[ -L "$link" ]]; then
        log_info "Replacing link ~/.ssh/config → $(readlink "$link")"
        run_cmd ln -sfn "$rel" "$link"
    elif [[ -e "$link" ]]; then
        if [[ -f "$target" ]] && cmp -s "$link" "$target"; then
            log_info "~/.ssh/config is identical to the synced one, replacing it with the link"
        elif [[ -f "$target" ]]; then
            _ssh_backup "$link"
        else
            # Nothing synced yet: this machine's config could be the one that syncs
            log_info "~/.ssh/config exists, and the synced folder has no config (yet)"
            log_info "  If the server already has one, Nextcloud keeps both as a conflict copy."
            if confirm "Move your ~/.ssh/config into the synced folder, so it syncs to your other machines?" "n"; then
                run_cmd mv "$link" "$target"
                log_success "Moved ~/.ssh/config into $(home_relative "$synced")/"
            else
                _ssh_backup "$link"
            fi
        fi
        run_cmd ln -sfn "$rel" "$link"
    else
        run_cmd ln -s "$rel" "$link"
    fi

    if [[ -f "$target" ]]; then
        # ssh refuses a config others can write ("Bad owner or permissions"),
        # and a synced file arrives with whatever mode the client gives it
        run_cmd chmod 600 "$target"
        log_success "~/.ssh/config → $rel"
    else
        log_success "~/.ssh/config → $rel (takes effect once Nextcloud has synced it)"
    fi
}

_ssh_backup() {
    local f="$1" bak
    bak="$f.ensconce-$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up the local ~/.ssh/config to $(basename "$bak")"
    run_cmd mv "$f" "$bak"
}

_ssh_control_dir() {
    local d synced=""
    d=$(home_path "$SSH_CONTROL_DIR")
    [[ -n "${SSH_SYNCED_DIR:-}" ]] && synced=$(home_path "$SSH_SYNCED_DIR")

    if [[ -n "$synced" && "$(readlink -m "$d")/" == "$(readlink -m "$synced")/"* ]]; then
        log_warn "SSH_CONTROL_DIR is inside SSH_SYNCED_DIR — Nextcloud cannot sync sockets"
        log_warn "  and will report errors for every one; keep it next to the folder instead"
    fi

    _ssh_private_dir "$d"
    log_success "ControlMaster sockets: ~/$(home_relative "$d")"
}

# ── The agent ───────────────────────────────────────────────────────────────

# gcr ≥ 4.2.1 (GNOME 46 and later) starts gcr-ssh-agent.socket in every
# session, and the socket unit's ExecStartPost runs
#   systemctl --user set-environment SSH_AUTH_SOCK=%t/gcr/ssh
# which overrides whatever environment.d set. Masking it is the per-user way
# to keep it from doing that; older gnome-keyring used an autostart entry.
_GCR_SOCKET="gcr-ssh-agent.socket"
_GCR_MASK="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$_GCR_SOCKET"

_gcr_masked() {
    [[ -L "$_GCR_MASK" && "$(readlink "$_GCR_MASK")" == /dev/null ]]
}

# Over ssh, or from a TTY, there may be no user manager to talk to
_user_manager() {
    systemctl --user show-environment &> /dev/null
}

_gcr_present() {
    if _user_manager; then
        systemctl --user cat "$_GCR_SOCKET" &> /dev/null
    else
        [[ -f "/usr/lib/systemd/user/$_GCR_SOCKET" || -f "/etc/systemd/user/$_GCR_SOCKET" ]]
    fi
}

_ssh_gnome_agent_off() {
    if _gcr_masked; then
        log_info "GNOME's SSH agent ($_GCR_SOCKET) is already masked"
    elif ! _gcr_present; then
        :
    elif _user_manager; then
        log_info "Masking GNOME's SSH agent ($_GCR_SOCKET), which would take SSH_AUTH_SOCK back"
        run_cmd systemctl --user mask --now "$_GCR_SOCKET" || return 1
        run_cmd systemctl --user stop gcr-ssh-agent.service 2>/dev/null || true
    else
        # A mask is exactly this link; it applies from the next login on
        log_info "Masking GNOME's SSH agent ($_GCR_SOCKET) from the next login on"
        run_cmd mkdir -p "$(dirname "$_GCR_MASK")"
        run_cmd ln -sfn /dev/null "$_GCR_MASK"
    fi

    local sys_autostart="/etc/xdg/autostart/gnome-keyring-ssh.desktop"
    local autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/gnome-keyring-ssh.desktop"
    if [[ -f "$sys_autostart" && ! -f "$autostart" ]]; then
        log_info "Hiding gnome-keyring's SSH component from autostart"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would write: $autostart (Hidden=true)"
        else
            mkdir -p "$(dirname "$autostart")"
            printf '%s\n' "[Desktop Entry]" "$ENSCONCE_MARKER (SSH_AGENT=bitwarden)" \
                "Type=Application" "Name=SSH Key Agent" "Hidden=true" > "$autostart"
        fi
    fi
}

_ssh_agent_bitwarden() {
    local want
    want=$(printf '%s\n' "$ENSCONCE_MARKER (SSH_AGENT=bitwarden): the Bitwarden Flatpak's SSH agent" \
                         "SSH_AUTH_SOCK=$BITWARDEN_SSH_SOCK")

    if ! flatpak info "$BITWARDEN_APP_ID" &> /dev/null; then
        log_warn "$BITWARDEN_APP_ID is not installed — add it to flatpaks.list"
    fi

    if [[ -f "$SSH_AGENT_ENV_FILE" && "$(cat "$SSH_AGENT_ENV_FILE")" == "$want" ]]; then
        log_info "SSH_AUTH_SOCK already points at Bitwarden ($SSH_AGENT_ENV_FILE)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would write: $SSH_AGENT_ENV_FILE"
    else
        mkdir -p "$(dirname "$SSH_AGENT_ENV_FILE")"
        echo "$want" > "$SSH_AGENT_ENV_FILE"
        log_success "SSH_AUTH_SOCK=$BITWARDEN_SSH_SOCK for the desktop session"
    fi

    _ssh_gnome_agent_off || { log_warn "Could not mask gcr-ssh-agent.socket"; return 1; }

    # Apps started from now on get it; the rest of the session after a re-login
    if _user_manager; then
        run_cmd systemctl --user set-environment "SSH_AUTH_SOCK=$BITWARDEN_SSH_SOCK" || true
    fi

    # ssh-add -l: 0 keys listed, 1 agent has no keys, 2 no agent there
    if [[ -S "$BITWARDEN_SSH_SOCK" ]]; then
        local rc=0
        SSH_AUTH_SOCK="$BITWARDEN_SSH_SOCK" timeout 10 ssh-add -l &> /dev/null || rc=$?
        case $rc in
            0) log_success "Bitwarden's SSH agent is running and holds keys" ;;
            1) log_info "Bitwarden's SSH agent is running but lists no keys — vault locked, or no SSH key items in it" ;;
            *) log_warn "Bitwarden's agent socket exists but does not answer — is Bitwarden running?" ;;
        esac
    else
        log_info "Bitwarden's agent is not running yet. In Bitwarden: Settings → \"Enable SSH agent\""
        log_info "  (and \"Start automatically on login\", so the agent is there when ssh asks for it)"
    fi
    log_info "Log out and back in for the whole desktop session to use it"
}

# Undo SSH_AGENT=bitwarden: remove what it wrote, give GNOME its agent back
_ssh_agent_gnome() {
    if [[ -f "$SSH_AGENT_ENV_FILE" ]]; then
        log_info "Removing $SSH_AGENT_ENV_FILE"
        run_cmd rm -f "$SSH_AGENT_ENV_FILE"
    fi

    local autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/gnome-keyring-ssh.desktop"
    if [[ -f "$autostart" ]] && grep -qF "$ENSCONCE_MARKER" "$autostart"; then
        run_cmd rm -f "$autostart"
    fi

    if _gcr_masked; then
        log_info "Unmasking GNOME's SSH agent ($_GCR_SOCKET)"
        if _user_manager; then
            run_cmd systemctl --user unmask "$_GCR_SOCKET" || return 1
            # Starting the socket sets SSH_AUTH_SOCK for the session again
            run_cmd systemctl --user start "$_GCR_SOCKET" || true
        else
            run_cmd rm -f "$_GCR_MASK"
        fi
    fi
    log_success "GNOME's SSH agent is the session's agent (after a re-login)"
}

step_ssh() {
    if [[ -z "${SSH_SYNCED_DIR:-}${SSH_CONTROL_DIR:-}${SSH_AGENT:-}" ]]; then
        log_info "No SSH settings in settings.sh (SSH_SYNCED_DIR, SSH_CONTROL_DIR, SSH_AGENT), skipping"
        return 0
    fi

    case "${SSH_AGENT:-}" in
        ""|bitwarden|gnome) ;;
        *) log_error "SSH_AGENT='$SSH_AGENT' — expected bitwarden, gnome or empty"; return 1 ;;
    esac

    log_info "SSH setup:"
    [[ -n "${SSH_SYNCED_DIR:-}" ]] && echo "  - ~/.ssh/config → link into $(_ssh_show "$SSH_SYNCED_DIR") (synced)"
    [[ -n "${SSH_CONTROL_DIR:-}" ]] && echo "  - ControlMaster socket directory $(_ssh_show "$SSH_CONTROL_DIR")"
    case "${SSH_AGENT:-}" in
        bitwarden) echo "  - SSH agent: Bitwarden (Flatpak), GNOME's agent masked" ;;
        gnome)     echo "  - SSH agent: GNOME's own (undo Bitwarden)" ;;
    esac
    echo ""

    if ! confirm "Apply the SSH settings?"; then
        log_warn "SSH setup skipped by user"
        return 0
    fi

    _ssh_private_dir "$HOME/.ssh"

    local rc=0
    [[ -n "${SSH_SYNCED_DIR:-}" ]] && { _ssh_link_config || rc=1; }
    [[ -n "${SSH_CONTROL_DIR:-}" ]] && { _ssh_control_dir || rc=1; }
    case "${SSH_AGENT:-}" in
        bitwarden) _ssh_agent_bitwarden || rc=1 ;;
        gnome)     _ssh_agent_gnome || rc=1 ;;
    esac

    [[ $rc -eq 0 ]] && log_success "SSH setup complete"
    return $rc
}
