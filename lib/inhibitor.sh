#!/bin/bash
# lib/inhibitor.sh - Keep the machine awake for the whole run
#
# A stock Bluefin desktop suspends after ~15 minutes of "idle", and typing in
# a terminal does not always reset that timer. Layering RPMs or installing
# Brew apps easily runs past it, so the run has to be actively defended.
#
# No single mechanism is enough, so three are used together:
#
#   1. logind block inhibitor  — blocks suspend / hibernate / lid switch.
#      Taken by re-exec'ing the whole script under systemd-inhibit (see
#      reexec_under_inhibit in ensconce.sh) so it lives exactly as long as
#      the run does.
#   2. gnome-session inhibitor — blocks the GNOME idle timer (screen blank
#      and lock). Held by a parked child process, because a session
#      inhibitor dies the moment the D-Bus connection that asked for it
#      goes away.
#   3. dconf overrides         — gsd-power runs its own idle->suspend timer
#      that ignores (1) and (2) in some GNOME versions. The keys are forced
#      to "never" for the run and put back afterwards.
#
# stop_inhibitor() unwinds 2 and 3; the runner traps it on EXIT.

GNOME_INHIBIT_PID=""
IDLE_BACKUP_FILE=""

# dconf keys forced during the run: path <tab> value-to-force
_IDLE_KEYS=(
    "/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type	'nothing'"
    "/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type	'nothing'"
    "/org/gnome/desktop/session/idle-delay	uint32 0"
    "/org/gnome/desktop/screensaver/idle-activation-enabled	false"
    "/org/gnome/desktop/screensaver/lock-enabled	false"
)

# ============================================================================
# Layer 2 — GNOME session idle inhibitor
# ============================================================================

_start_gnome_inhibitor() {
    command -v gnome-session-inhibit &> /dev/null || return 1
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || return 1

    # --inhibit-only parks the process and holds the inhibit until it is
    # killed, which is exactly the lifetime we want.
    #
    # Do NOT wrap this in setsid: a backgrounded command is already a process
    # group leader, so setsid forks, $! becomes the short-lived setsid wrapper,
    # and the real inhibitor is orphaned — it would then survive the run and
    # keep the session awake forever. Backgrounded commands in a
    # non-interactive shell already ignore SIGINT, so nothing is gained.
    gnome-session-inhibit \
        --inhibit logout:switch-user:suspend:idle \
        --reason "Ensconce post-installation setup" \
        --inhibit-only < /dev/null &> /dev/null &

    GNOME_INHIBIT_PID=$!
    sleep 0.3

    if kill -0 "$GNOME_INHIBIT_PID" 2>/dev/null; then
        echo "$GNOME_INHIBIT_PID" > "$STATE_DIR/inhibitor.pid"
        return 0
    fi

    GNOME_INHIBIT_PID=""
    return 1
}

_stop_gnome_inhibitor() {
    [[ -z "$GNOME_INHIBIT_PID" ]] && return 0
    kill "$GNOME_INHIBIT_PID" 2>/dev/null || true
    rm -f "$STATE_DIR/inhibitor.pid"
    GNOME_INHIBIT_PID=""
}

# A previous run that was killed outright (SIGKILL, crash) leaves its parked
# inhibitor behind. Clean it up before starting a new one.
_reap_stale_inhibitor() {
    local pidfile="$STATE_DIR/inhibitor.pid"
    [[ -f "$pidfile" ]] || return 0

    local stale
    stale=$(<"$pidfile")
    if [[ "$stale" =~ ^[0-9]+$ ]] && kill -0 "$stale" 2>/dev/null; then
        log_info "Releasing inhibitor left over from a previous run (PID $stale)"
        kill "$stale" 2>/dev/null || true
    fi
    rm -f "$pidfile"
}

# ============================================================================
# Layer 3 — temporary dconf idle/suspend overrides
# ============================================================================

_force_idle_settings() {
    command -v dconf &> /dev/null || return 1
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || return 1

    IDLE_BACKUP_FILE="$STATE_DIR/idle-settings.bak"
    : > "$IDLE_BACKUP_FILE"

    local entry path forced original
    for entry in "${_IDLE_KEYS[@]}"; do
        path="${entry%%	*}"
        forced="${entry#*	}"

        # Empty means "unset, using the schema default" — restore = reset
        original=$(dconf read "$path" 2>/dev/null)

        printf '%s\t%s\t%s\n' "$path" "$forced" "$original" >> "$IDLE_BACKUP_FILE"
        dconf write "$path" "$forced" 2>/dev/null || true
    done
}

_restore_idle_settings() {
    [[ -n "$IDLE_BACKUP_FILE" && -f "$IDLE_BACKUP_FILE" ]] || return 0

    local path forced original current
    while IFS=$'\t' read -r path forced original; do
        [[ -z "$path" ]] && continue

        # Only put a key back if it still holds the value we forced. If it
        # changed, something else owns it now — most likely the dconf step
        # loading the user's own settings — and that has to win.
        current=$(dconf read "$path" 2>/dev/null)
        [[ "$current" != "$forced" ]] && continue

        if [[ -z "$original" ]]; then
            dconf reset "$path" 2>/dev/null || true
        else
            dconf write "$path" "$original" 2>/dev/null || true
        fi
    done < "$IDLE_BACKUP_FILE"

    rm -f "$IDLE_BACKUP_FILE"
    IDLE_BACKUP_FILE=""
}

# ============================================================================
# Public interface
# ============================================================================

start_inhibitor() {
    mkdir -p "$STATE_DIR"
    _reap_stale_inhibitor

    log_info "Preventing sleep/screen blank while setup runs..."

    # Layer 1 is already in place if we re-exec'd successfully
    if [[ -n "${ENSCONCE_INHIBITED:-}" ]]; then
        log_success "logind: suspend/hibernate/lid-switch blocked"
    else
        log_warn "logind: no systemd-inhibit — the system may still suspend"
    fi

    if _start_gnome_inhibitor; then
        log_success "GNOME: idle timer inhibited (PID $GNOME_INHIBIT_PID)"
    else
        log_warn "GNOME: session inhibitor unavailable (not a GNOME session?)"
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dconf: idle/suspend overrides skipped (dry run)"
    elif _force_idle_settings; then
        log_success "dconf: idle-delay and auto-suspend disabled for this run"
    else
        log_warn "dconf: could not override idle settings"
    fi
}

stop_inhibitor() {
    _stop_gnome_inhibitor
    _restore_idle_settings
    log_info "Inhibitors released"
}
