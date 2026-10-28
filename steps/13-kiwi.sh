#!/bin/bash
# Step: kiwi
# Description: Install kiwi-updater and the kiwi apps in kiwi-apps.list
#
# kiwi-updater installs and updates apps from git catalogs, ensconce among
# them. KIWI_INSTALL in settings.sh says how to install it when it is missing;
# kiwi-apps.list says which apps to install with it.

KIWI_GET_URL="https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh"

# Bootstrap through kiwi-updater's own installer, the one its README documents.
# Downloaded first and run from the file, so a connection cut off half way
# runs nothing.
_kiwi_bootstrap() {
    local args=() what
    case "$KIWI_INSTALL" in
        recommended) what="user + system scope: one password now, passwordless updates after" ;;
        manual)      what="user + system scope, every system change asks for your password"
                     args=(--with-system=manual) ;;
        minimal)     what="user scope only, never root — enough for user-only apps"
                     args=(--minimal) ;;
    esac

    log_info "kiwi-updater is not installed"
    log_info "KIWI_INSTALL=$KIWI_INSTALL: $what"
    echo ""

    if ! confirm "Install kiwi-updater?"; then
        log_warn "kiwi-updater installation skipped by user"
        return 2
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would run: curl -fsSL $KIWI_GET_URL | bash -s --${args[*]:+ ${args[*]}}"
        return 0
    fi

    local tmp rc=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/get-kiwi-XXXXXX.sh")
    if ! curl -fsSL "$KIWI_GET_URL" -o "$tmp"; then
        rm -f "$tmp"
        log_error "Could not download $KIWI_GET_URL"
        return 1
    fi
    bash "$tmp" "${args[@]}" || rc=$?
    rm -f "$tmp"

    if [[ $rc -ne 0 ]] || ! kiwi_cmd > /dev/null; then
        log_error "kiwi-updater's installer failed (exit $rc)"
        return 1
    fi
    log_success "kiwi-updater installed"
}

step_kiwi() {
    local apps=() app
    while IFS= read -r app; do
        apps+=("$app")
    done < <(read_list_file "$CONFIG_DIR/kiwi-apps.list")

    case "${KIWI_INSTALL:-}" in
        ""|recommended|manual|minimal) ;;
        *) log_error "KIWI_INSTALL='$KIWI_INSTALL' — expected recommended, manual, minimal or empty"
           return 1 ;;
    esac

    local kiwi=""
    if kiwi=$(kiwi_cmd); then
        log_info "kiwi-updater: $kiwi ($("$kiwi" version 2>/dev/null || echo "version unknown"))"
    elif [[ -z "${KIWI_INSTALL:-}" ]]; then
        if [[ ${#apps[@]} -gt 0 ]]; then
            log_warn "kiwi-apps.list has ${#apps[@]} app(s), but kiwi-updater is not installed"
            log_warn "  and KIWI_INSTALL is empty in settings.sh — skipping"
        else
            log_info "KIWI_INSTALL not set in settings.sh, skipping"
        fi
        return 0
    else
        local rc=0
        _kiwi_bootstrap || rc=$?
        [[ $rc -eq 2 ]] && return 0
        [[ $rc -ne 0 ]] && return 1
        kiwi=$(kiwi_cmd) || kiwi=""
    fi

    if [[ ${#apps[@]} -eq 0 ]]; then
        log_info "No apps in kiwi-apps.list"
        return 0
    fi

    # What is already there. Porcelain fields are tab-separated and some can be
    # empty, which `read` would collapse (tab is IFS whitespace), so awk picks
    # name (1) and status (4) out first.
    local -A status=()
    local name st
    if [[ -n "$kiwi" ]]; then
        while IFS='|' read -r name st; do
            [[ -n "$name" ]] && status["$name"]="$st"
        done < <("$kiwi" list --porcelain --no-sync 2>/dev/null | awk -F'\t' '{print $1 "|" $4}')
    fi

    local todo=()
    log_info "kiwi apps:"
    for app in "${apps[@]}"; do
        if [[ "${status[$app]:-}" == installed ]]; then
            echo "  - $app (installed)"
        else
            echo "  - $app"
            todo+=("$app")
        fi
    done
    echo ""

    if [[ ${#todo[@]} -eq 0 ]]; then
        log_success "All kiwi apps are installed"
        return 0
    fi

    if ! confirm "Install ${#todo[@]} kiwi app(s)?"; then
        log_warn "kiwi app installation skipped by user"
        return 0
    fi

    # An app with a root half asks for a password here (or not, on a
    # recommended install); kiwi says which and why before it does
    if ! run_cmd "${kiwi:-kiwi}" install "${todo[@]}"; then
        log_warn "kiwi reported a problem with at least one app — see above; 'kiwi doctor' helps"
        return 1
    fi
    log_success "kiwi apps installed — kiwi keeps them updated from now on"
}
