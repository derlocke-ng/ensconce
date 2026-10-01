#!/bin/bash
# Step: repos
# Description: Add RPM package repositories

step_repos() {
    local repos_dir="$CONFIG_DIR/repos.d"

    if [[ ! -d "$repos_dir" ]] || [[ -z "$(ls -A "$repos_dir" 2>/dev/null)" ]]; then
        log_info "No repo files found in $repos_dir"
        return 0
    fi

    log_info "Repositories to install:"
    local repo_file
    for repo_file in "$repos_dir"/*.repo; do
        [[ -f "$repo_file" ]] || continue
        echo "  - $(basename "$repo_file")"
    done
    echo ""

    if ! confirm "Install these RPM repositories?"; then
        log_warn "Repository installation skipped by user"
        return 0
    fi

    for repo_file in "$repos_dir"/*.repo; do
        [[ -f "$repo_file" ]] || continue
        local dest="/etc/yum.repos.d/$(basename "$repo_file")"

        if [[ -f "$dest" ]]; then
            log_info "Already installed: $(basename "$repo_file")"
        else
            log_info "Installing: $(basename "$repo_file")"
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "${YELLOW}[DRY-RUN]${NC} Would copy to: $dest"
            else
                sudo cp "$repo_file" "$dest"
                log_success "Installed: $(basename "$repo_file")"
            fi
        fi
    done

    log_success "Repository setup complete"
}
