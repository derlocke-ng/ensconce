#!/bin/bash
# Step: sysctl
# Description: Kernel tunables (sysctl.d drop-ins)

step_sysctl() {
    local src_dir="$CONFIG_DIR/sysctl.d"
    local dst_dir="/etc/sysctl.d"

    local confs=()
    if [[ -d "$src_dir" ]]; then
        while IFS= read -r -d '' f; do
            confs+=("$f")
        done < <(find "$src_dir" -maxdepth 1 -name '*.conf' -print0 2>/dev/null | sort -z)
    fi

    if [[ ${#confs[@]} -eq 0 ]]; then
        log_info "No sysctl drop-ins found in $src_dir"
        return 0
    fi

    # Only what differs from what is installed
    local pending=() conf
    for conf in "${confs[@]}"; do
        if [[ -f "$dst_dir/$(basename "$conf")" ]] && cmp -s "$conf" "$dst_dir/$(basename "$conf")"; then
            log_info "Already installed and up to date: $(basename "$conf")"
        else
            pending+=("$conf")
        fi
    done

    if [[ ${#pending[@]} -eq 0 ]]; then
        log_success "sysctl drop-ins already in place"
        return 0
    fi

    log_info "sysctl drop-ins to install to $dst_dir/:"
    for conf in "${pending[@]}"; do
        echo "  - $(basename "$conf")"
        grep -vE '^[[:space:]]*([#;]|$)' "$conf" | sed 's/^/      /'
    done
    echo ""

    if ! confirm "Install sysctl drop-ins and apply them now?"; then
        log_warn "sysctl drop-ins skipped by user"
        return 0
    fi

    for conf in "${pending[@]}"; do
        log_info "Installing: $(basename "$conf")"
        run_cmd sudo install -m 0644 "$conf" "$dst_dir/$(basename "$conf")" || return 1
    done

    # Applies every sysctl.d file, in the kernel's own order, so later files
    # still win the way they will at the next boot
    run_cmd sudo sysctl --system || return 1

    log_success "sysctl drop-ins installed and applied"
}
