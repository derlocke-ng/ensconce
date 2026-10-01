#!/bin/bash
# lib/progress.sh - Progress tracking with auto-resume after reboot

init_progress() {
    mkdir -p "$STATE_DIR"
    [[ -f "$PROGRESS_FILE" ]] || touch "$PROGRESS_FILE"
}

mark_step_done() {
    init_progress
    if ! grep -qx "$1" "$PROGRESS_FILE" 2>/dev/null; then
        echo "$1" >> "$PROGRESS_FILE"
    fi
}

is_step_done() {
    [[ -f "$PROGRESS_FILE" ]] && grep -qx "$1" "$PROGRESS_FILE" 2>/dev/null
}

mark_pending_reboot() {
    init_progress
    echo "$1" > "$PENDING_REBOOT_FILE"
    log_info "Progress saved. Run script again after reboot to continue from: $1"
}

check_pending_reboot() {
    if [[ -f "$PENDING_REBOOT_FILE" ]]; then
        local next_step
        next_step=$(cat "$PENDING_REBOOT_FILE")
        rm -f "$PENDING_REBOOT_FILE"
        log_info "Resuming setup from: $next_step"
        return 0
    fi
    return 1
}

reset_progress() {
    rm -f "$PROGRESS_FILE" "$PENDING_REBOOT_FILE"
    log_success "Progress reset. Will start fresh on next run."
}

show_progress_status() {
    log_section "Setup Progress Status"
    init_progress

    local step
    for step in "${ALL_STEPS[@]}"; do
        if is_step_done "$step"; then
            echo -e "  ${GREEN}✓${NC} $step"
        else
            echo -e "  ${YELLOW}○${NC} $step"
        fi
    done

    echo ""

    if [[ -f "$PENDING_REBOOT_FILE" ]]; then
        log_warn "Pending reboot! Next step: $(cat "$PENDING_REBOOT_FILE")"
    fi

    local completed
    completed=$(grep -c . "$PROGRESS_FILE" 2>/dev/null || echo 0)
    local total=${#ALL_STEPS[@]}

    if [[ "$completed" -eq "$total" ]]; then
        log_success "All steps completed!"
    else
        log_info "Progress: $completed/$total steps completed"
    fi
}

get_next_step() {
    local step
    for step in "${ALL_STEPS[@]}"; do
        if ! is_step_done "$step"; then
            echo "$step"
            return 0
        fi
    done
    echo "done"
}
