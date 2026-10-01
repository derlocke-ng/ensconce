#!/bin/bash
# Step: gdm
# Description: Apply login screen (GDM) settings — scaling, mouse accel
#
# The GDM greeter runs as the "gdm" user, so none of the desktop dconf from
# step 10 reaches it. It has two separate sources of configuration:
#
#   * /etc/dconf/db/gdm.d/   — keyfiles compiled by `dconf update` into the
#                              gdm dconf profile. This is where pointer,
#                              cursor and interface settings belong.
#   * /var/lib/gdm/.config/monitors.xml — the greeter's display layout. This
#                              is what actually decides the login screen's
#                              resolution and scale; if it is missing, mutter
#                              guesses, which is where a stray 125% comes from.

_gdm_install_dconf() {
    local src_dir="$CONFIG_DIR/gdm/dconf.d"

    if [[ ! -d "$src_dir" ]] || [[ -z "$(ls -A "$src_dir" 2>/dev/null)" ]]; then
        log_info "No gdm/dconf.d/ files, skipping login screen dconf"
        return 0
    fi

    log_info "Login screen dconf keyfiles to install:"
    local f
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        echo "  - $(basename "$f")"
    done
    log_info "Destination: /etc/dconf/db/gdm.d/"
    echo ""

    if ! confirm "Apply these login screen settings?"; then
        log_warn "Login screen dconf skipped by user"
        return 0
    fi

    local changed=false
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        local dest="/etc/dconf/db/gdm.d/$(basename "$f")"

        if [[ -f "$dest" ]] && sudo cmp -s "$f" "$dest" 2>/dev/null; then
            log_info "Already up to date: $(basename "$f")"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would install: $dest"
        else
            sudo install -m 0644 "$f" "$dest"
            log_success "Installed: $(basename "$f")"
        fi
        changed=true
    done

    if [[ "$changed" == "true" ]]; then
        log_info "Recompiling dconf databases..."
        run_cmd sudo dconf update
    fi
}

_gdm_install_monitors() {
    local src="$CONFIG_DIR/gdm/monitors.xml"
    local user_monitors="$HOME/.config/monitors.xml"
    local dest="/var/lib/gdm/.config/monitors.xml"

    # Prefer an explicit config file; otherwise offer the current desktop layout
    if [[ ! -f "$src" ]]; then
        if [[ ! -f "$user_monitors" ]]; then
            log_info "No monitors.xml available — skipping login screen layout"
            return 0
        fi

        echo ""
        log_info "No config/gdm/monitors.xml, but your desktop has one:"
        log_info "  $user_monitors"
        log_info "Copying it makes the login screen use the same resolution and scale."

        if ! confirm "Use your current display layout for the login screen?"; then
            log_warn "Login screen display layout skipped by user"
            return 0
        fi
        src="$user_monitors"
    else
        echo ""
        log_info "Login screen display layout: $src"
        if ! confirm "Apply this display layout to the login screen?"; then
            log_warn "Login screen display layout skipped by user"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would install $src -> $dest (owner gdm:gdm)"
        return 0
    fi

    sudo mkdir -p /var/lib/gdm/.config

    if [[ -f "$dest" ]]; then
        sudo cp -a "$dest" "${dest}.bak"
        log_info "Backed up existing greeter layout to ${dest}.bak"
    fi

    sudo install -m 0644 -o gdm -g gdm "$src" "$dest"
    sudo chown -R gdm:gdm /var/lib/gdm/.config
    # /var/lib/gdm is SELinux-confined; a copied-in file carries the wrong label
    sudo restorecon -R /var/lib/gdm/.config 2>/dev/null || true

    log_success "Login screen display layout installed"
}

step_gdm() {
    local gdm_dir="$CONFIG_DIR/gdm"

    if [[ ! -d "$gdm_dir" ]]; then
        log_info "No gdm/ directory in config, skipping"
        return 0
    fi

    if [[ ! -d /etc/dconf/db/gdm.d ]]; then
        log_warn "/etc/dconf/db/gdm.d not found — is GDM installed?"
        return 0
    fi

    log_info "Login screen settings are applied as root and affect all users."

    _gdm_install_dconf
    _gdm_install_monitors

    echo ""
    log_success "Login screen configuration complete"
    log_info "Changes take effect at the next logout / reboot"
}
