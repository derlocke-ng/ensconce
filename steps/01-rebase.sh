#!/bin/bash
# Step: rebase
# Description: Switch to Bluefin-DX (Developer Mode)

step_rebase() {
    if is_dx_image; then
        log_info "Already on a DX image, skipping rebase"
        return 0
    fi

    local current_image
    current_image=$(get_current_image)

    log_info "Current image: $current_image"
    log_info "This will use Bluefin's built-in 'ujust toggle-devmode' to switch to DX"
    echo ""

    if ! confirm "Proceed with switching to Developer Mode?"; then
        log_warn "Rebase skipped by user"
        return 0
    fi

    log_info "Running 'ujust toggle-devmode'..."
    log_warn "This will require a reboot to take effect!"
    log_info "Follow the prompts from the Bluefin tool..."
    echo ""

    run_cmd ujust toggle-devmode

    mark_pending_reboot "ujust"
    log_success "Rebase initiated!"
    log_warn "After reboot, run the script again — it will resume automatically."

    # Signal reboot needed (runner handles exit)
    return 42
}
