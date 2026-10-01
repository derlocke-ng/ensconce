#!/bin/bash
# Step: flatpaks
# Description: Install Flatpak applications from Flathub

step_flatpaks() {
    local flatpaks_file="$CONFIG_DIR/flatpaks.list"

    if [[ ! -f "$flatpaks_file" ]]; then
        log_info "No flatpaks.list found, skipping"
        return 0
    fi

    # Ensure Flathub is enabled
    if ! flatpak remote-list | grep -q flathub; then
        log_info "Adding Flathub repository..."
        run_cmd flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    local flatpaks=()
    while IFS= read -r app; do
        flatpaks+=("$app")
    done < <(read_list_file "$flatpaks_file")

    if [[ ${#flatpaks[@]} -eq 0 ]]; then
        log_info "No Flatpaks configured for installation"
        return 0
    fi

    log_info "Flatpaks to install:"
    for app in "${flatpaks[@]}"; do
        echo "  - $app"
    done
    echo ""

    if ! confirm "Install these Flatpak applications?"; then
        log_warn "Flatpak installation skipped by user"
        return 0
    fi

    log_info "Installing Flatpaks..."
    for app in "${flatpaks[@]}"; do
        if flatpak list --app | grep -q "$app"; then
            log_info "Already installed: $app"
        else
            log_info "Installing: $app"
            run_cmd flatpak install -y flathub "$app" \
                || log_warn "Failed to install: $app"
        fi
    done

    log_success "Flatpak installation complete"
}
