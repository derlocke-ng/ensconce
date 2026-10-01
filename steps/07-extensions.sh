#!/bin/bash
# Step: extensions
# Description: Install GNOME Shell extensions from extensions.gnome.org

_get_gnome_shell_version() {
    gnome-shell --version 2>/dev/null | grep -oP '[\d.]+' | head -1
}

_install_extension_from_ego() {
    local uuid="$1"
    local shell_version
    shell_version=$(_get_gnome_shell_version)

    [[ -z "$shell_version" ]] && { log_error "Cannot detect GNOME Shell version"; return 1; }

    # Query extensions.gnome.org API
    local api_url="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_version}"
    local json
    json=$(curl -sf "$api_url" 2>/dev/null)

    [[ -z "$json" ]] && { log_warn "No API response for: $uuid"; return 1; }

    local download_url
    download_url=$(echo "$json" | jq -r '.download_url // empty')

    [[ -z "$download_url" ]] && { log_warn "No compatible version for GNOME $shell_version: $uuid"; return 1; }

    # Download and install
    local tmpfile
    tmpfile=$(mktemp /tmp/gnome-ext-XXXXXX.zip)

    if ! curl -sf "https://extensions.gnome.org${download_url}" -o "$tmpfile"; then
        rm -f "$tmpfile"
        log_warn "Download failed: $uuid"
        return 1
    fi

    # Installs to ~/.local/share/gnome-shell/extensions/ (Silverblue-safe)
    if gnome-extensions install --force "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        return 0
    else
        rm -f "$tmpfile"
        return 1
    fi
}

step_extensions() {
    local ext_file="$CONFIG_DIR/extensions.list"

    if [[ ! -f "$ext_file" ]]; then
        log_info "No extensions.list found, skipping"
        return 0
    fi

    if ! command -v gnome-extensions &> /dev/null; then
        log_warn "gnome-extensions command not found"
        return 0
    fi

    local extensions=()
    while IFS= read -r uuid; do
        extensions+=("$uuid")
    done < <(read_list_file "$ext_file")

    if [[ ${#extensions[@]} -eq 0 ]]; then
        log_info "No GNOME extensions configured"
        return 0
    fi

    local shell_version
    shell_version=$(_get_gnome_shell_version)
    log_info "GNOME Shell version: $shell_version"
    log_info "Extensions to install (from extensions.gnome.org):"
    for ext in "${extensions[@]}"; do
        echo "  - $ext"
    done
    echo ""

    if ! confirm "Install GNOME Shell extensions?"; then
        log_warn "Extension installation skipped by user"
        return 0
    fi

    log_info "Downloading and installing to ~/.local/share/gnome-shell/extensions/"
    echo ""

    local failed=()

    for uuid in "${extensions[@]}"; do
        if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
            log_info "Already installed: $uuid"
        else
            log_info "Installing: $uuid"
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "${YELLOW}[DRY-RUN]${NC} Would download and install: $uuid"
            else
                if _install_extension_from_ego "$uuid"; then
                    log_success "Installed: $uuid"
                else
                    log_warn "Failed: $uuid"
                    failed+=("$uuid")
                fi
            fi
        fi
    done

    # Enable all
    log_info "Enabling installed extensions..."
    for uuid in "${extensions[@]}"; do
        [[ "$DRY_RUN" != "true" ]] && gnome-extensions enable "$uuid" 2>/dev/null || true
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo ""
        log_warn "Some extensions failed to install:"
        for ext in "${failed[@]}"; do echo "  - $ext"; done
        echo ""
        log_info "Try installing manually via Extension Manager or https://extensions.gnome.org"
    fi

    log_success "Extension installation complete"
    log_info "You may need to log out/in for extensions to fully activate"
}
