#!/bin/bash
# Step: overrides
# Description: Apply Flatpak permission overrides

step_overrides() {
    local overrides_src="$CONFIG_DIR/flatpak-overrides"

    if [[ ! -d "$overrides_src" ]] || [[ -z "$(ls -A "$overrides_src" 2>/dev/null)" ]]; then
        log_info "No flatpak-overrides/ directory or empty, skipping"
        return 0
    fi

    log_info "Flatpak permission overrides to apply:"
    local override_file
    for override_file in "$overrides_src"/*; do
        [[ -f "$override_file" ]] || continue
        echo "  - $(basename "$override_file")"
    done
    echo ""

    if ! confirm "Apply Flatpak permission overrides?"; then
        log_warn "Flatpak overrides skipped by user"
        return 0
    fi

    local overrides_dest="$HOME/.local/share/flatpak/overrides"
    mkdir -p "$overrides_dest"

    for override_file in "$overrides_src"/*; do
        [[ -f "$override_file" ]] || continue
        local app_id
        app_id=$(basename "$override_file")
        local dest_file="$overrides_dest/$app_id"

        # Check if the app is installed (skip if not)
        if ! flatpak list --app 2>/dev/null | grep -q "$app_id"; then
            log_info "Skipping $app_id (not installed)"
            continue
        fi

        # Idempotency: compare before writing
        if [[ -f "$dest_file" ]] && cmp -s "$override_file" "$dest_file"; then
            log_info "Already up to date: $app_id"
        else
            log_info "Applying override: $app_id"
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "${YELLOW}[DRY-RUN]${NC} Would write: $dest_file"
            else
                cp "$override_file" "$dest_file"
            fi
        fi
    done

    log_success "Flatpak permission overrides applied"
    log_info "Overrides take effect on next app launch"
}
