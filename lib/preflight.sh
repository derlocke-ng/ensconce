#!/bin/bash
# lib/preflight.sh - Pre-run validation checks

run_preflight_checks() {
    log_section "Preflight Checks"

    local errors=0

    # ── Bluefin image ──
    if is_bluefin_image; then
        log_success "Running on a Bluefin image"
    else
        log_error "Not running on a Bluefin image (detected: $(get_current_image))"
        log_error "Ensconce is designed for Bluefin / Universal Blue images"
        errors=$((errors + 1))
    fi

    # ── Required commands ──
    local cmd
    for cmd in rpm-ostree flatpak dconf jq curl; do
        if command -v "$cmd" &> /dev/null; then
            log_success "Found: $cmd"
        else
            log_error "Missing required command: $cmd"
            errors=$((errors + 1))
        fi
    done

    # ── Internet connectivity ──
    if curl -sf --max-time 5 "https://flathub.org" > /dev/null 2>&1; then
        log_success "Internet connectivity OK"
    else
        log_warn "Cannot reach flathub.org — some steps may fail without internet"
    fi

    # ── Disk space (use $HOME — on Silverblue / is a read-only composefs with 0GB free) ──
    local free_gb
    free_gb=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ "$free_gb" -lt 10 ]]; then
        log_warn "Low disk space: ${free_gb}GB free (recommend 10GB+)"
    else
        log_success "Disk space: ${free_gb}GB free"
    fi

    # ── GNOME Shell (needed for extensions) ──
    if pgrep -x gnome-shell > /dev/null 2>&1; then
        log_success "GNOME Shell is running"
    else
        log_warn "GNOME Shell not detected — extension step may fail (SSH session?)"
    fi

    # ── Nextcloud client (needed for preseed to be useful) ──
    if command -v nextcloud &> /dev/null || rpm -q nextcloud-client &> /dev/null 2>&1; then
        log_success "Nextcloud client available"
    else
        log_info "Nextcloud client not yet installed (will be layered in packages step)"
    fi

    echo ""

    if [[ "$errors" -gt 0 ]]; then
        log_error "Preflight failed with $errors error(s)"
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_success "All preflight checks passed"
    fi
}
