#!/bin/bash
# Step: nextcloud
# Description: Preseed Nextcloud folder sync configuration

step_nextcloud() {
    local nc_dir="$CONFIG_DIR/nextcloud"
    local folders_file="$nc_dir/folders.list"

    # Check if Nextcloud is configured
    if [[ -z "${NEXTCLOUD_SERVER:-}" ]]; then
        log_info "NEXTCLOUD_SERVER not set in settings.sh, skipping"
        return 0
    fi

    if [[ ! -f "$folders_file" ]]; then
        log_info "No nextcloud/folders.list found, skipping"
        return 0
    fi

    # Parse folder definitions
    local folder_entries=()
    while IFS= read -r line; do
        folder_entries+=("$line")
    done < <(read_list_file "$folders_file")

    if [[ ${#folder_entries[@]} -eq 0 ]]; then
        log_info "No Nextcloud sync folders configured"
        return 0
    fi

    log_info "This will preseed Nextcloud with folder sync definitions."
    log_info "You will still need to log in to your Nextcloud account!"
    log_warn "Do NOT run this if Nextcloud is already configured with syncs."
    echo ""
    log_info "Server: $NEXTCLOUD_SERVER"
    log_info "Folders to sync:"
    for entry in "${folder_entries[@]}"; do
        local lp="${entry%%|*}"
        local rest="${entry#*|}"
        local rp="${rest%%|*}"
        echo "  - ~/$lp → $rp"
    done
    echo ""

    if ! confirm "Preseed Nextcloud folder configuration?"; then
        log_warn "Nextcloud preseed skipped by user"
        return 0
    fi

    local nc_config_dir="$HOME/.config/Nextcloud"
    local nc_config_file="$nc_config_dir/nextcloud.cfg"

    # Safety check
    if [[ -f "$nc_config_file" ]] && grep -q '0\\Folders\\1' "$nc_config_file" 2>/dev/null; then
        log_warn "Nextcloud config already has folder definitions!"
        if ! confirm "Overwrite existing folder configuration?" "n"; then
            log_info "Keeping existing Nextcloud configuration"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Nextcloud config at: $nc_config_file"
        return 0
    fi

    mkdir -p "$nc_config_dir"

    # ── Create local folders ──
    log_info "Creating local folders..."
    for entry in "${folder_entries[@]}"; do
        local local_path="${entry%%|*}"
        local full_path="$HOME/$local_path"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            log_info "Created: ~/$local_path"
        fi
    done

    # ── Generate nextcloud.cfg ──
    log_info "Generating Nextcloud configuration..."

    cat > "$nc_config_file" << 'GENERAL_EOF'
[General]
confirmExternalStorage=true
launchOnSystemStartup=true
monoIcons=true
optionalServerNotifications=true

GENERAL_EOF

    local folder_num=1
    {
        echo "[Accounts]"
        for entry in "${folder_entries[@]}"; do
            local local_path="${entry%%|*}"
            local rest="${entry#*|}"
            local remote_path="${rest%%|*}"
            local journal_id
            journal_id=$(generate_hex_id)

            echo "0\\Folders\\${folder_num}\\ignoreHiddenFiles=false"
            echo "0\\Folders\\${folder_num}\\journalPath=.sync_${journal_id}.db"
            echo "0\\Folders\\${folder_num}\\localPath=$HOME/${local_path}/"
            echo "0\\Folders\\${folder_num}\\paused=false"
            echo "0\\Folders\\${folder_num}\\targetPath=${remote_path}"
            echo "0\\Folders\\${folder_num}\\version=2"
            echo "0\\Folders\\${folder_num}\\virtualFilesMode=off"

            folder_num=$((folder_num + 1))
        done

        # Embed CA certificates if available
        local certs_dir="$CONFIG_DIR/certs"
        if [[ -d "$certs_dir" ]]; then
            local has_certs=false
            local cert_payload=""
            for cert_file in "$certs_dir"/*.pem; do
                [[ -f "$cert_file" ]] || continue
                has_certs=true
                cert_payload+="$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_file")\\n\\n"
            done
            if [[ "$has_certs" == "true" ]]; then
                echo "0\\General\\CaCertificates=@ByteArray(${cert_payload})"
            fi
        fi

        echo "0\\authType=webflow"
        echo "0\\url=${NEXTCLOUD_SERVER}"
        echo "0\\version=13"
        echo "version=13"
    } >> "$nc_config_file"

    # ── Install global sync-exclude.lst ──
    local global_exclude="$nc_dir/exclude.lst"
    if [[ -f "$global_exclude" ]]; then
        cp "$global_exclude" "$nc_config_dir/sync-exclude.lst"
        log_info "Installed global sync-exclude.lst"
    fi

    # ── Place per-folder .sync-exclude.lst via tags ──
    local exclude_d="$nc_dir/exclude.d"
    if [[ -d "$exclude_d" ]]; then
        for entry in "${folder_entries[@]}"; do
            local local_path="${entry%%|*}"
            local rest="${entry#*|}"
            local remote_path="${rest%%|*}"
            local tags=""

            # Tags are the third field (if present)
            if [[ "$rest" == *"|"* ]]; then
                tags="${rest#*|}"
            fi

            [[ -z "$tags" ]] && continue

            local full_path="$HOME/$local_path"
            local exclude_content=""

            # Collect exclusion rules from all matching tag files
            IFS=',' read -ra tag_array <<< "$tags"
            for tag in "${tag_array[@]}"; do
                local tag_file="$exclude_d/${tag}.lst"
                if [[ -f "$tag_file" ]]; then
                    exclude_content+="$(cat "$tag_file")"$'\n'
                fi
            done

            if [[ -n "$exclude_content" ]]; then
                echo "$exclude_content" > "$full_path/.sync-exclude.lst"
                log_info "Placed .sync-exclude.lst in ~/$local_path (tags: $tags)"
            fi
        done
    fi

    log_success "Nextcloud folder configuration preseeded"
    echo ""
    log_info "Next steps:"
    echo "  1. Launch Nextcloud client"
    echo "  2. Log in to your account at $NEXTCLOUD_SERVER"
    echo "  3. The folder syncs should be pre-configured!"
    echo ""
    log_warn "If folders don't appear, you may need to add them manually in Nextcloud settings."
}
