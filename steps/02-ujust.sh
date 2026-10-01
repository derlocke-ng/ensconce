#!/bin/bash
# Step: ujust
# Description: Run Bluefin developer setup commands

step_ujust() {
    if ! command -v ujust &> /dev/null; then
        log_warn "ujust not found — are you on a Universal Blue image?"
        return 0
    fi

    log_info "Recommended ujust commands for DX setup:"
    echo "  - ujust dx-group     : Add user to docker, libvirt, incus-admin groups"
    echo "  - ujust bluefin-cli  : Configure terminal with Brew (starship, atuin, etc.)"
    echo "  - ujust bbrew        : Install apps from curated Brewfiles"
    echo ""

    if confirm "Run 'ujust dx-group' (add user to developer groups)?"; then
        run_cmd ujust dx-group || log_warn "dx-group may not be available on this image"
    fi

    if confirm "Configure terminal CLI tools (ujust bluefin-cli)?"; then
        run_cmd ujust bluefin-cli || log_warn "bluefin-cli setup may have issues"
    fi

    if confirm "Install curated Brew apps (ujust bbrew)?"; then
        log_info "Running ujust bbrew (this may take a while)..."
        run_cmd ujust bbrew || log_warn "bbrew may have issues"
    fi

    log_success "ujust setup complete"
}
