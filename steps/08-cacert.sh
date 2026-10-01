#!/bin/bash
# Step: cacert
# Description: Install custom CA certificates system-wide

step_cacert() {
    local certs_dir="$CONFIG_DIR/certs"

    # Collect all .pem files
    local certs=()
    if [[ -d "$certs_dir" ]]; then
        while IFS= read -r -d '' f; do
            certs+=("$f")
        done < <(find "$certs_dir" -maxdepth 1 -name '*.pem' -print0 2>/dev/null)
    fi

    if [[ ${#certs[@]} -eq 0 ]]; then
        log_info "No CA certificates found in $certs_dir"
        return 0
    fi

    log_info "CA certificates to install:"
    for cert in "${certs[@]}"; do
        echo "  - $(basename "$cert")"
    done
    log_info "Destination: /etc/pki/ca-trust/source/anchors/"
    log_info "This makes them trusted system-wide (curl, podman, browsers, etc.)"
    echo ""

    if ! confirm "Install custom CA certificates system-wide?"; then
        log_warn "CA certificate installation skipped by user"
        return 0
    fi

    for cert in "${certs[@]}"; do
        local cert_name
        cert_name=$(basename "$cert")
        local trust_anchor="/etc/pki/ca-trust/source/anchors/$cert_name"

        if [[ -f "$trust_anchor" ]] && cmp -s "$cert" "$trust_anchor"; then
            log_info "Already installed and up to date: $cert_name"
            continue
        fi

        log_info "Installing: $cert_name"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would copy to: $trust_anchor"
        else
            sudo cp "$cert" "$trust_anchor"
        fi
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        sudo update-ca-trust
    fi

    log_success "CA certificates installed and trust store updated"
}
