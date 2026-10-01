#!/bin/bash
# Step: packages
# Description: Layer RPM packages via rpm-ostree

step_packages() {
    local packages_file="$CONFIG_DIR/packages.list"

    if [[ ! -f "$packages_file" ]]; then
        log_info "No packages.list found, skipping"
        return 0
    fi

    local packages=()
    while IFS= read -r pkg; do
        packages+=("$pkg")
    done < <(read_list_file "$packages_file")

    if [[ ${#packages[@]} -eq 0 ]]; then
        log_info "No packages configured for layering"
        return 0
    fi

    log_info "Packages to layer:"
    for pkg in "${packages[@]}"; do
        echo "  - $pkg"
    done
    echo ""

    if ! confirm "Install these packages via rpm-ostree?"; then
        log_warn "Package installation skipped by user"
        return 0
    fi

    log_info "Installing packages (this may take a while)..."
    run_cmd rpm-ostree install --idempotent "${packages[@]}"

    log_success "Packages layered successfully"
    log_warn "Reboot required to apply rpm-ostree changes"
}
