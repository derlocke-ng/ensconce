#!/bin/bash
# Step: power
# Description: Turn off suspend, hibernation and sleep on lid close (systemd)

# Every way into sleep: masked, they can't be started by anyone — GNOME's
# menu and idle timer, the lid, a key, `systemctl suspend`
_SLEEP_TARGETS=(
    sleep.target
    suspend.target
    hibernate.target
    hybrid-sleep.target
    suspend-then-hibernate.target
)

# logind acts on the lid and the suspend keys itself; masked targets alone
# would leave it trying (and failing) on every lid close
_LOGIND_DROPIN="/etc/systemd/logind.conf.d/90-ensconce-no-sleep.conf"
_LOGIND_CONF="[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore"

# GNOME's own idle→suspend timer, in the session's dconf
_GNOME_SLEEP_KEYS=(
    /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
    /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
)

_sleep_targets_masked() {
    local t
    for t in "${_SLEEP_TARGETS[@]}"; do
        [[ "$(systemctl is-enabled "$t" 2>/dev/null)" == masked ]] || return 1
    done
}

_logind_reload() {
    # SIGHUP rereads logind.conf; a restart would end the desktop session
    run_cmd sudo systemctl kill -s HUP systemd-logind \
        || log_warn "Could not reload logind — the lid settings apply after a reboot"
}

_power_sleep_off() {
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$_LOGIND_CONF" > "$tmp"

    local need_mask=true need_dropin=true
    _sleep_targets_masked && need_mask=false
    [[ -f "$_LOGIND_DROPIN" ]] && cmp -s "$tmp" "$_LOGIND_DROPIN" && need_dropin=false

    if [[ $need_mask == false && $need_dropin == false ]]; then
        rm -f "$tmp"
        log_success "Sleep is already off (targets masked, lid ignored)"
        return 0
    fi

    log_info "Turning sleep off:"
    [[ $need_mask == true ]] && echo "  - mask ${_SLEEP_TARGETS[*]}"
    [[ $need_dropin == true ]] && echo "  - $_LOGIND_DROPIN: ignore the lid and the suspend/hibernate keys"
    echo "  - GNOME: no automatic suspend when idle"
    echo ""

    if ! confirm "Turn off suspend, hibernation and sleep on lid close?"; then
        rm -f "$tmp"
        log_warn "Sleep settings left as they are"
        return 0
    fi

    if [[ $need_mask == true ]]; then
        run_cmd sudo systemctl mask "${_SLEEP_TARGETS[@]}" || { rm -f "$tmp"; return 1; }
    fi
    if [[ $need_dropin == true ]]; then
        run_cmd sudo mkdir -p "$(dirname "$_LOGIND_DROPIN")" \
            && run_cmd sudo install -m 0644 "$tmp" "$_LOGIND_DROPIN" \
            || { rm -f "$tmp"; return 1; }
        _logind_reload
    fi
    rm -f "$tmp"

    # With the targets masked GNOME's idle suspend would only fail; turn it
    # off so it doesn't warn about a suspend that never comes
    if command -v dconf &> /dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        local key
        for key in "${_GNOME_SLEEP_KEYS[@]}"; do
            run_cmd dconf write "$key" "'nothing'"
            idle_settings_keep "$key" "'nothing'"
        done
    else
        log_warn "No desktop session — GNOME's idle suspend is left as it is"
    fi

    log_success "Sleep is off: suspend, hibernation and lid close do nothing"
}

_power_sleep_on() {
    local masked=() t
    for t in "${_SLEEP_TARGETS[@]}"; do
        [[ "$(systemctl is-enabled "$t" 2>/dev/null)" == masked ]] && masked+=("$t")
    done

    if [[ ${#masked[@]} -eq 0 && ! -e "$_LOGIND_DROPIN" ]]; then
        log_success "Sleep is already on"
        return 0
    fi

    if ! confirm "Turn suspend, hibernation and sleep on lid close back on?"; then
        log_warn "Sleep settings left as they are"
        return 0
    fi

    # GNOME's idle suspend stays as the dconf step or the user left it
    if [[ ${#masked[@]} -gt 0 ]]; then
        run_cmd sudo systemctl unmask "${masked[@]}" || return 1
    fi
    if [[ -e "$_LOGIND_DROPIN" ]]; then
        run_cmd sudo rm -f "$_LOGIND_DROPIN" || return 1
        _logind_reload
    fi

    log_success "Sleep is back on"
}

step_power() {
    case "${SYSTEM_SLEEP:-}" in
        "")  log_info "SYSTEM_SLEEP is empty — sleep settings left as they are"; return 0 ;;
        off) _power_sleep_off ;;
        on)  _power_sleep_on ;;
        *)   log_error "SYSTEM_SLEEP must be off, on or empty (got: $SYSTEM_SLEEP)"; return 1 ;;
    esac
}
