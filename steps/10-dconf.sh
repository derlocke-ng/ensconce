#!/bin/bash
# Step: dconf
# Description: Apply GNOME desktop settings via dconf

step_dconf() {
    local dconf_file="$CONFIG_DIR/dconf-settings.ini"

    if [[ ! -f "$dconf_file" ]]; then
        log_info "No dconf-settings.ini found in config/, skipping"
        log_info "Create one with: dconf dump / > config/dconf-settings.ini"
        return 0
    fi

    log_info "Will apply settings from: $dconf_file"
    echo ""

    if ! confirm "Apply dconf desktop settings?"; then
        log_warn "dconf settings skipped by user"
        return 0
    fi

    # Back up current settings before applying
    local backup_file="$STATE_DIR/dconf-backup-$(date +%Y%m%d_%H%M%S).ini"
    log_info "Backing up current dconf settings to: $backup_file"
    mkdir -p "$STATE_DIR"
    dconf dump / > "$backup_file"
    log_success "Backup saved ($(wc -l < "$backup_file") lines)"

    log_info "Applying dconf settings..."
    run_cmd dconf load / < "$dconf_file"

    log_success "dconf settings applied"

    # ── GTK3 bookmarks (Nautilus sidebar) ──
    local bookmarks_file="$CONFIG_DIR/gtk3-bookmarks"
    local bookmarks_dest="$HOME/.config/gtk-3.0/bookmarks"

    if [[ -f "$bookmarks_file" ]]; then
        echo ""
        log_info "Found GTK3 bookmarks file (Nautilus sidebar shortcuts)"

        if confirm "Install file manager bookmarks?"; then
            mkdir -p "$(dirname "$bookmarks_dest")"

            if [[ -f "$bookmarks_dest" ]] && ! cmp -s "$bookmarks_file" "$bookmarks_dest"; then
                log_info "Backing up existing bookmarks"
                cp "$bookmarks_dest" "${bookmarks_dest}.bak"
            fi

            run_cmd cp "$bookmarks_file" "$bookmarks_dest"
            log_success "Bookmarks installed"
        fi
    fi
}
