#!/bin/bash
# Step: flatpaks
# Description: Install Flatpak applications from Flathub

# Which languages the Locale extensions (translations, and the locale data
# behind dates and numbers) are installed for. Flatpak's default only follows
# the language a user runs in, so en_US with German formats gets no "de". Set
# for both installations: each keeps its own list.
_flatpak_languages() {
    [[ -n "${FLATPAK_LANGUAGES:-}" ]] || return 0

    local want="$FLATPAK_LANGUAGES"
    [[ "$want" == "*" ]] && want="*all*"

    local scope current pending=()
    for scope in system user; do
        current=$(flatpak config "--$scope" --get languages 2>/dev/null)
        if [[ "$current" == "$want" ]]; then
            log_info "Flatpak languages ($scope) already: $want"
        else
            log_info "Flatpak languages ($scope): ${current:-*unset*} → $want"
            pending+=("$scope")
        fi
    done
    [[ ${#pending[@]} -eq 0 ]] && return 0

    if ! confirm "Set the Flatpak languages to '$want' and fetch the missing translations?"; then
        log_warn "Flatpak languages left as they are"
        return 0
    fi

    for scope in "${pending[@]}"; do
        if ! run_cmd flatpak config "--$scope" --set languages "$want"; then
            log_warn "Could not set the Flatpak languages ($scope)"
            continue
        fi
        # Apps already installed only get the new languages' Locale
        # extensions on their next update
        if [[ -n "$(flatpak list "--$scope" --app --columns=application 2>/dev/null)" ]]; then
            log_info "Updating $scope Flatpaks to fetch the new languages..."
            run_cmd flatpak update "--$scope" -y --noninteractive \
                || log_warn "flatpak update ($scope) had problems"
        fi
    done
}

step_flatpaks() {
    local flatpaks_file="$CONFIG_DIR/flatpaks.list"

    # Before installing, so new apps come with the right languages straight away
    _flatpak_languages

    if [[ ! -f "$flatpaks_file" ]]; then
        log_info "No flatpaks.list found, skipping"
        return 0
    fi

    # Ensure Flathub is enabled
    if ! flatpak remote-list --system | grep -q flathub; then
        log_info "Adding Flathub repository..."
        run_cmd flatpak remote-add --system --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    local flatpaks=()
    while IFS= read -r app; do
        flatpaks+=("$app")
    done < <(read_list_file "$flatpaks_file")

    if [[ ${#flatpaks[@]} -eq 0 ]]; then
        log_info "No Flatpaks configured for installation"
        return 0
    fi

    log_info "Flatpaks to install:"
    for app in "${flatpaks[@]}"; do
        echo "  - $app"
    done
    echo ""

    if ! confirm "Install these Flatpak applications?"; then
        log_warn "Flatpak installation skipped by user"
        return 0
    fi

    log_info "Installing Flatpaks..."
    for app in "${flatpaks[@]}"; do
        if flatpak list --app | grep -q "$app"; then
            log_info "Already installed: $app"
        else
            log_info "Installing: $app"
            run_cmd flatpak install --system -y flathub "$app" \
                || log_warn "Failed to install: $app"
        fi
    done

    log_success "Flatpak installation complete"
}
