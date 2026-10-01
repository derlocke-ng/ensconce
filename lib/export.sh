#!/bin/bash
# lib/export.sh - Capture this machine's state into an ensconce config/ tree
#
# The inverse of the steps: each step reads a file out of config/ and applies
# it, and each function here reads the live system and writes that same file.
# Export on a configured machine, review/edit the result, drop it in as
# config/ on the next machine, run ensconce.
#
# Everything written here is meant to be reviewed by a human before use, so
# entries that can't be reproduced verbatim are emitted as comments rather
# than silently dropped.

EXPORT_DIR=""

# dconf subtrees worth carrying between machines. A full `dconf dump /` also
# picks up window positions, per-monitor state and recently-used lists, which
# are noise at best and wrong at worst on different hardware.
_EXPORT_DCONF_PATHS=(
    org/gnome/desktop/interface
    org/gnome/desktop/wm/preferences
    org/gnome/desktop/wm/keybindings
    org/gnome/desktop/peripherals
    org/gnome/desktop/input-sources
    org/gnome/desktop/calendar
    org/gnome/desktop/privacy
    org/gnome/desktop/session
    org/gnome/desktop/screensaver
    org/gnome/mutter
    org/gnome/settings-daemon/plugins
    org/gnome/shell
    org/gnome/nautilus
    org/gnome/Ptyxis
    org/gtk/settings
    org/gtk/gtk4/settings
    system/locale
)

_hdr() {
    printf '# %s\n' "$@"
}

# ============================================================================
# RPM packages — only what was explicitly layered, not the whole image
# ============================================================================

_export_packages() {
    local out="$EXPORT_DIR/packages.list"
    {
        _hdr "RPM packages to layer via rpm-ostree" \
             "Exported from $(hostname) on $(date -I)" \
             "" \
             "Only explicitly layered packages are listed — everything else" \
             "comes from the base image."
        echo ""
    } > "$out"

    if ! command -v rpm-ostree &> /dev/null; then
        echo "# (rpm-ostree not available on the exporting machine)" >> "$out"
        log_warn "packages.list: rpm-ostree not found"
        return 0
    fi

    local pkgs
    pkgs=$(rpm-ostree status --json 2>/dev/null \
        | jq -r '.deployments[0]["requested-packages"] // [] | .[]' 2>/dev/null)

    if [[ -z "$pkgs" ]]; then
        echo "# (no layered packages)" >> "$out"
        log_info "packages.list: no layered packages"
        return 0
    fi

    echo "$pkgs" >> "$out"
    log_success "packages.list: $(echo "$pkgs" | grep -c .) package(s)"
}

# ============================================================================
# Flatpaks
# ============================================================================

_export_flatpaks() {
    local out="$EXPORT_DIR/flatpaks.list"
    {
        _hdr "Flatpak applications to install from Flathub" \
             "Exported from $(hostname) on $(date -I)"
        echo ""
    } > "$out"

    if ! command -v flatpak &> /dev/null; then
        echo "# (flatpak not available on the exporting machine)" >> "$out"
        return 0
    fi

    local n=0 other=0 appid origin
    while IFS=$'\t' read -r appid origin; do
        [[ -z "$appid" ]] && continue
        if [[ "$origin" == "flathub" ]]; then
            echo "$appid" >> "$out"
            n=$((n + 1))
        else
            # step 05 installs from flathub only — surface these, don't drop them
            echo "#$appid   # origin: $origin (not flathub — install manually)" >> "$out"
            other=$((other + 1))
        fi
    done < <(flatpak list --app --columns=application,origin 2>/dev/null)

    log_success "flatpaks.list: $n from flathub$([[ $other -gt 0 ]] && echo ", $other commented out")"
}

# ============================================================================
# GNOME extensions — user-installed only
# ============================================================================

_export_extensions() {
    local out="$EXPORT_DIR/extensions.list"
    {
        _hdr "GNOME Shell extensions to install" \
             "Exported from $(hostname) on $(date -I)" \
             "" \
             "Only user-installed extensions are listed. Extensions shipped in" \
             "/usr/share/gnome-shell/extensions come with the image and would" \
             "fail to install from extensions.gnome.org."
        echo ""
    } > "$out"

    local user_ext_dir="$HOME/.local/share/gnome-shell/extensions"
    if [[ ! -d "$user_ext_dir" ]]; then
        echo "# (no user-installed extensions)" >> "$out"
        return 0
    fi

    local enabled_list
    enabled_list=$(dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || echo "")

    local n=0 off=0 local_ext=0 uuid d
    for d in "$user_ext_dir"/*/; do
        [[ -d "$d" ]] || continue
        uuid=$(basename "$d")

        # extensions.gnome.org stamps "_generated" into metadata.json when it
        # packages an extension. Without it the extension was installed by hand
        # or by another tool, so step 07 could never fetch it from EGO.
        if ! grep -q '_generated' "$d/metadata.json" 2>/dev/null; then
            echo "#$uuid   # installed locally, not from extensions.gnome.org" >> "$out"
            local_ext=$((local_ext + 1))
            continue
        fi

        if [[ "$enabled_list" == *"'$uuid'"* ]]; then
            echo "$uuid" >> "$out"
            n=$((n + 1))
        else
            echo "#$uuid   # installed but not enabled" >> "$out"
            off=$((off + 1))
        fi
    done

    [[ $n -eq 0 && $off -eq 0 && $local_ext -eq 0 ]] && echo "# (no user-installed extensions)" >> "$out"
    log_success "extensions.list: $n enabled, $off disabled, $local_ext local-only (all commented out)"
}

# ============================================================================
# Flatpak permission overrides
# ============================================================================

_export_overrides() {
    local src="$HOME/.local/share/flatpak/overrides"
    local dst="$EXPORT_DIR/flatpak-overrides"
    mkdir -p "$dst"

    [[ -d "$src" ]] || { log_info "flatpak-overrides/: none"; return 0; }

    local n=0 f
    for f in "$src"/*; do
        [[ -f "$f" ]] || continue
        # "global" applies to every app; carrying it to another machine is
        # rarely what you want, so leave it behind
        [[ "$(basename "$f")" == "global" ]] && continue
        cp "$f" "$dst/"
        n=$((n + 1))
    done

    log_success "flatpak-overrides/: $n file(s)"
}

# ============================================================================
# RPM repositories — the ones not owned by any package
# ============================================================================

# Repo files that come with Bluefin/Universal Blue but are written at runtime
# (by the image's scripts or by `ujust`), so they carry no RPM ownership and
# would otherwise look hand-added. Matched as shell globs against the filename.
_BLUEFIN_REPOS=(
    'fedora*.repo'
    'rpmfusion*.repo'
    'negativo17*.repo'
    'nvidia-container-toolkit.repo'
    '_copr*.repo'
    'docker-ce.repo'
    'vscode.repo'
    'tailscale.repo'
    'terra.repo'
    'charm.repo'
    'gh-cli.repo'
)

_repo_ships_with_bluefin() {
    local name="$1" pattern
    for pattern in "${_BLUEFIN_REPOS[@]}"; do
        # shellcheck disable=SC2053
        [[ "$name" == $pattern ]] && return 0
    done
    return 1
}

_export_repos() {
    local dst="$EXPORT_DIR/repos.d"
    mkdir -p "$dst"

    local n=0 owned=0 shipped=0 f name
    for f in /etc/yum.repos.d/*.repo; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")

        # Owned by an RPM: definitely part of the image
        if rpm -qf "$f" &> /dev/null; then
            owned=$((owned + 1))
            continue
        fi

        # Written at runtime by the image / ujust: exported for reference but
        # parked as .repo.disabled so step 03 (which globs *.repo) ignores it.
        # Rename to .repo to bring one back.
        if _repo_ships_with_bluefin "$name"; then
            cp "$f" "$dst/${name}.disabled"
            shipped=$((shipped + 1))
            continue
        fi

        cp "$f" "$dst/"
        n=$((n + 1))
    done

    if [[ $n -eq 0 ]]; then
        touch "$dst/.gitkeep"
        log_info "repos.d/: no custom repos ($owned from packages, $shipped from Bluefin)"
    else
        log_success "repos.d/: $n custom repo(s) — $owned from packages, $shipped from Bluefin parked as .disabled"
        log_info "repos.d/: check the .disabled files if a layered package can't be found"
    fi
}

# ============================================================================
# CA certificates
# ============================================================================

_export_certs() {
    local src="/etc/pki/ca-trust/source/anchors"
    local dst="$EXPORT_DIR/certs"
    mkdir -p "$dst"

    local n=0 f
    if [[ -d "$src" ]]; then
        for f in "$src"/*.pem; do
            [[ -f "$f" ]] || continue
            cp "$f" "$dst/" 2>/dev/null && n=$((n + 1))
        done
    fi

    [[ $n -eq 0 ]] && touch "$dst/.gitkeep"
    log_success "certs/: $n certificate(s)"
}

# ============================================================================
# dconf — curated subtrees, reassembled into one loadable file
# ============================================================================

# `dconf dump /a/b/` emits groups relative to /a/b, so the prefix has to be
# put back for the result to be loadable at /.
_dump_subtree() {
    local path="$1"
    local body
    body=$(dconf dump "/$path/" 2>/dev/null) || return 1
    [[ -z "$body" ]] && return 1

    awk -v prefix="$path" '
        /^\[/ {
            grp = substr($0, 2, length($0) - 2)
            if (grp == "/") print "[" prefix "]"
            else            print "[" prefix "/" grp "]"
            next
        }
        { print }
    ' <<< "$body"
}

_export_dconf() {
    local out="$EXPORT_DIR/dconf-settings.ini"
    {
        _hdr "GNOME desktop settings — applied with: dconf load / < this file" \
             "Exported from $(hostname) on $(date -I)" \
             "" \
             "Curated subtrees only. Machine-specific state (window positions," \
             "monitor layout, recently-used files) is deliberately not included." \
             "" \
             "Review before applying on another machine — keybindings and" \
             "extension settings referencing absent extensions are harmless," \
             "but display and input settings may not suit different hardware."
        echo ""
    } > "$out"

    local path chunk n=0
    for path in "${_EXPORT_DCONF_PATHS[@]}"; do
        chunk=$(_dump_subtree "$path") || continue
        printf '%s\n\n' "$chunk" >> "$out"
        n=$((n + 1))
    done

    log_success "dconf-settings.ini: $n subtree(s), $(grep -c '^\[' "$out") group(s)"
}

# ============================================================================
# GTK3 bookmarks
# ============================================================================

_export_bookmarks() {
    local src="$HOME/.config/gtk-3.0/bookmarks"
    local out="$EXPORT_DIR/gtk3-bookmarks"

    if [[ ! -f "$src" ]]; then
        log_info "gtk3-bookmarks: none"
        return 0
    fi

    # No header comment: this file is installed verbatim and '#' is not a
    # comment character in GTK's bookmark format.
    cp "$src" "$out"
    log_success "gtk3-bookmarks: $(grep -c . "$out") bookmark(s)"
}

# ============================================================================
# Nextcloud — reverse of step 09
# ============================================================================

_export_nextcloud() {
    local cfg="$HOME/.config/Nextcloud/nextcloud.cfg"
    local dst="$EXPORT_DIR/nextcloud"
    mkdir -p "$dst/exclude.d"

    if [[ ! -f "$cfg" ]]; then
        log_info "nextcloud/: no client configuration found"
        printf '%s\n' "# Nextcloud sync folder definitions" \
                      "# Format: localPath|remotePath[|exclude-tags]" > "$dst/folders.list"
        return 0
    fi

    # Server URL feeds settings.sh
    NEXTCLOUD_SERVER_EXPORTED=$(grep -m1 '^0\\url=' "$cfg" 2>/dev/null | cut -d= -f2-)

    # Global exclude list
    if [[ -f "$HOME/.config/Nextcloud/sync-exclude.lst" ]]; then
        cp "$HOME/.config/Nextcloud/sync-exclude.lst" "$dst/exclude.lst"
    fi

    local out="$dst/folders.list"
    {
        _hdr "Nextcloud sync folder definitions" \
             "Format: localPath|remotePath[|exclude-tags]" \
             "Exported from $(hostname) on $(date -I)"
        echo ""
    } > "$out"

    # Pair up localPath/targetPath by folder index
    local indices
    indices=$(grep -oP '^0\\Folders\\\K[0-9]+' "$cfg" 2>/dev/null | sort -un)

    # ── Pass 1: collect folders and fingerprint their exclude rules ──
    #
    # Naming the tags needs to wait until every folder is known: a rule set
    # used by several folders is a shared policy and must not be named after
    # whichever folder happened to be read first.
    local -a rels=() remotes=() hashes=()
    local -A rule_body=() rule_uses=()
    local idx local_path remote_path rel sum body

    for idx in $indices; do
        local_path=$(grep -m1 "^0\\\\Folders\\\\${idx}\\\\localPath=" "$cfg" | cut -d= -f2-)
        remote_path=$(grep -m1 "^0\\\\Folders\\\\${idx}\\\\targetPath=" "$cfg" | cut -d= -f2-)
        [[ -z "$local_path" || -z "$remote_path" ]] && continue

        # Absolute -> $HOME-relative, and drop the trailing slash
        rel="${local_path%/}"
        rel="${rel#"$HOME"/}"
        [[ "$rel" == /* ]] && { echo "# outside \$HOME, skipped: $local_path" >> "$out"; continue; }

        sum=""
        if [[ -f "$local_path/.sync-exclude.lst" ]]; then
            # Normalise before fingerprinting, so rule sets that differ only by
            # trailing whitespace or a stray blank line still count as one.
            body=$(sed -e 's/[[:space:]]*$//' "$local_path/.sync-exclude.lst" | grep -v '^$' || true)
            if [[ -n "$body" ]]; then
                sum=$(md5sum <<< "$body" | cut -d' ' -f1)
                rule_body["$sum"]="$body"
                rule_uses["$sum"]=$(( ${rule_uses["$sum"]:-0} + 1 ))
            fi
        fi

        rels+=("$rel"); remotes+=("$remote_path"); hashes+=("$sum")
    done

    # ── Pass 2: name each rule set, then write it out ──
    local -A tag_of=()
    local shared=0

    for sum in "${!rule_body[@]}"; do
        if [[ "${rule_uses[$sum]}" -gt 1 ]]; then
            # Shared by several folders: name it for what it is, not for a folder
            if grep -qiE 'sqlite|singleton|parentlock' <<< "${rule_body[$sum]}"; then
                tag="browser"
            else
                tag="shared"
            fi
        else
            # Used once: the folder name is the most descriptive label available
            for idx in "${!hashes[@]}"; do
                [[ "${hashes[$idx]}" == "$sum" ]] || continue
                tag=$(basename "${rels[$idx]}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')
                break
            done
            tag="${tag#-}"; tag="${tag%-}"
        fi
        [[ -z "$tag" ]] && tag="exclude"

        # Distinct rule sets that landed on the same name
        local suffix=2
        while [[ -f "$dst/exclude.d/${tag}.lst" ]]; do
            tag="${tag}-${suffix}"; suffix=$((suffix + 1))
        done

        printf '%s\n' "${rule_body[$sum]}" > "$dst/exclude.d/${tag}.lst"
        tag_of["$sum"]="$tag"
        [[ "${rule_uses[$sum]}" -gt 1 ]] && shared=$((shared + 1))
    done

    local n=0
    for idx in "${!rels[@]}"; do
        if [[ -n "${hashes[$idx]}" ]]; then
            echo "${rels[$idx]}|${remotes[$idx]}|${tag_of[${hashes[$idx]}]}" >> "$out"
        else
            echo "${rels[$idx]}|${remotes[$idx]}" >> "$out"
        fi
        n=$((n + 1))
    done

    log_success "nextcloud/: $n folder(s), ${#rule_body[@]} exclude tag(s) ($shared shared)"
}

# ============================================================================
# Login screen
# ============================================================================

_export_gdm() {
    local dst="$EXPORT_DIR/gdm"
    mkdir -p "$dst/dconf.d"

    local n=0 f
    for f in /etc/dconf/db/gdm.d/*; do
        [[ -f "$f" ]] || continue
        cp "$f" "$dst/dconf.d/" 2>/dev/null && n=$((n + 1))
    done

    # The greeter's own monitors.xml lives in a 0700 directory. Try it without
    # prompting; fall back to the desktop layout, which is what step 11 would
    # offer to install anyway.
    local greeter="/var/lib/gdm/.config/monitors.xml"
    if sudo -n test -r "$greeter" 2>/dev/null; then
        # shellcheck disable=SC2024  # sudo only needs to read; the target is ours
        sudo -n cat "$greeter" > "$dst/monitors.xml" 2>/dev/null \
            && log_success "gdm/: $n keyfile(s) + greeter monitors.xml"
    elif [[ -f "$HOME/.config/monitors.xml" ]]; then
        cp "$HOME/.config/monitors.xml" "$dst/monitors.xml"
        log_success "gdm/: $n keyfile(s) + monitors.xml (from your desktop layout)"
        log_info "gdm/: run with sudo available to capture the greeter's own layout instead"
    else
        log_success "gdm/: $n keyfile(s), no monitors.xml"
    fi
}

# ============================================================================
# settings.sh
# ============================================================================

_export_settings() {
    local out="$EXPORT_DIR/settings.sh"
    cat > "$out" << SETTINGSEOF
#!/bin/bash
# Ensconce — Personal configuration settings
# Exported from $(hostname) on $(date -I)
#
# This file is sourced by ensconce.sh

# Nextcloud server URL (leave empty to skip Nextcloud preseed)
NEXTCLOUD_SERVER="${NEXTCLOUD_SERVER_EXPORTED:-}"
SETTINGSEOF
    log_success "settings.sh: NEXTCLOUD_SERVER=${NEXTCLOUD_SERVER_EXPORTED:-<empty>}"
}

# ============================================================================
# Entry point
# ============================================================================

run_export() {
    EXPORT_DIR="${1:-}"

    if [[ -z "$EXPORT_DIR" ]]; then
        EXPORT_DIR="./ensconce-config-$(hostname -s)-$(date +%Y-%m-%d)"
    fi

    log_section "Exporting this machine's configuration"

    if [[ -e "$EXPORT_DIR" ]]; then
        log_warn "Target already exists: $EXPORT_DIR"
        if ! confirm "Overwrite files in it?" "n"; then
            log_info "Cancelled"
            return 0
        fi
    fi

    mkdir -p "$EXPORT_DIR"
    EXPORT_DIR="$(cd "$EXPORT_DIR" && pwd)"
    log_info "Target: $EXPORT_DIR"
    echo ""

    _export_packages
    _export_flatpaks
    _export_extensions
    _export_overrides
    _export_repos
    _export_certs
    _export_dconf
    _export_bookmarks
    _export_nextcloud
    _export_gdm
    _export_settings

    echo ""
    log_success "Export complete: $EXPORT_DIR"
    echo ""
    log_info "Next steps:"
    echo "  1. Review and edit the files — an export is a starting point,"
    echo "     not a finished config (hardware-specific dconf, machine-local"
    echo "     paths, repos added by ujust)."
    echo "  2. Copy it to the target machine as its config directory:"
    echo "       ensconce --init                       # create the config dir"
    echo "       cp -rT <export> \$(ensconce --config-dir)"
    echo "  3. Run 'ensconce --dry-run' there before the real run."
    echo ""
    log_warn "certs/ and nextcloud/ may contain private material — check before sharing."
}
