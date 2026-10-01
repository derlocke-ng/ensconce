#!/bin/bash
# ensconce — Modular post-installation setup for Bluefin-DX
#
# Transforms a fresh Bluefin installation into a fully configured
# development workstation. Modular steps, auto-resume after reboot,
# simple list-file configuration.
#
# Usage:
#   ./ensconce.sh [options]
#
# Options:
#   --init              Create personal config from examples
#   --skip <steps>      Skip step(s) (comma-separated)
#   --only <steps>      Run only these step(s) (comma-separated)
#   --dry-run           Show what would be done without executing
#   --log [file]        Log all output to file
#   --status            Show current progress and exit
#   --list-steps        List available steps and exit
#   --reset             Clear saved progress and start fresh
#   -h, --help          Show this help message

set -euo pipefail

ENSCONCE_VERSION="2.1.0"

# Resolve through symlinks: an installed copy lives in <prefix>/share/ensconce
# with <prefix>/bin/ensconce pointing at it, and lib/ + steps/ have to be found
# next to the real file rather than next to the symlink.
ENSCONCE_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ENSCONCE_DIR="$(cd "$(dirname "$ENSCONCE_SELF")" && pwd)"

# State
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ensconce"
PROGRESS_FILE="$STATE_DIR/progress"
PENDING_REBOOT_FILE="$STATE_DIR/pending_reboot"

# Options
DRY_RUN=false
ENABLE_LOG=false
LOG_FILE=""
RESET_PROGRESS=false
SHOW_STATUS=false
INIT_CONFIG=false
LIST_STEPS=false
DO_EXPORT=false
EXPORT_TARGET=""
SHOW_CONFIG_DIR=false
SKIP_STEPS=()
ONLY_STEPS=()

# Config directory (set after loading)
CONFIG_DIR=""

# ============================================================================
# Source library modules (alphabetical order is fine — no inter-dependencies)
# ============================================================================

for _lib in "$ENSCONCE_DIR"/lib/*.sh; do
    [[ -f "$_lib" ]] && source "$_lib"
done

# ============================================================================
# Sleep protection — re-exec under a logind block inhibitor
#
# This has to happen before anything long-running starts. A session inhibitor
# requested over D-Bus is dropped as soon as the requesting connection closes,
# so the only reliable way to hold one for the whole run is to *be* the child
# of systemd-inhibit. ENSCONCE_INHIBITED stops the re-exec from looping.
# See lib/inhibitor.sh for the other two layers.
# ============================================================================

reexec_under_inhibit() {
    [[ -n "${ENSCONCE_INHIBITED:-}" ]] && return 0
    command -v systemd-inhibit &> /dev/null || return 0

    # Informational / instant commands don't need the machine held awake
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help|--status|--list-steps|--init|--reset|--config-dir|--export) return 0 ;;
        esac
    done

    export ENSCONCE_INHIBITED=1
    exec systemd-inhibit \
        --what=sleep:idle:handle-lid-switch \
        --who="ensconce" \
        --why="Running post-installation setup" \
        --mode=block \
        "$ENSCONCE_SELF" "$@"
}

reexec_under_inhibit "$@"

# ============================================================================
# Step discovery — reads steps/NN-name.sh files to build step list
# ============================================================================

ALL_STEPS=()
declare -A STEP_FILES=()
declare -A STEP_DESCRIPTIONS=()

discover_steps() {
    local _step_file _basename _step_name _desc
    for _step_file in "$ENSCONCE_DIR"/steps/[0-9][0-9]-*.sh; do
        [[ -f "$_step_file" ]] || continue
        _basename=$(basename "$_step_file" .sh)
        _step_name="${_basename#[0-9][0-9]-}"
        _desc=$(grep '^# Description:' "$_step_file" | head -1 | sed 's/^# Description: *//')

        ALL_STEPS+=("$_step_name")
        STEP_FILES["$_step_name"]="$_step_file"
        STEP_DESCRIPTIONS["$_step_name"]="${_desc:-$_step_name}"
    done
}

# Source all step files (defines their step_*() functions)
load_steps() {
    local _name
    for _name in "${ALL_STEPS[@]}"; do
        source "${STEP_FILES[$_name]}"
    done
}

# ============================================================================
# Configuration loading
# ============================================================================

# Where the config lives, in priority order:
#
#   1. $ENSCONCE_CONFIG        explicit override
#   2. ~/.config/ensconce      XDG — how a nova-installed ensconce stores it
#   3. <repo>/config           working from a git clone
#   4. <repo>/config.example   fallback, with a warning
#
# Installed copies carry a .installed marker next to the script, which is what
# decides where --init puts a new config: a clone gets config/ (gitignored, as
# before), an installed copy gets the XDG directory so it survives updates.
XDG_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ensconce"

is_installed_copy() {
    [[ -f "$ENSCONCE_DIR/.installed" ]]
}

default_config_target() {
    if is_installed_copy; then
        echo "$XDG_CONFIG_DIR"
    else
        echo "$ENSCONCE_DIR/config"
    fi
}

resolve_config_dir() {
    local dir
    for dir in "${ENSCONCE_CONFIG:-}" "$XDG_CONFIG_DIR" "$ENSCONCE_DIR/config"; do
        [[ -n "$dir" && -f "$dir/settings.sh" ]] && { echo "$dir"; return 0; }
    done
    return 1
}

load_config() {
    local dir
    if dir=$(resolve_config_dir); then
        source "$dir/settings.sh"
        CONFIG_DIR="$dir"
    elif [[ -f "$ENSCONCE_DIR/config.example/settings.sh" ]]; then
        log_warn "Using example config — run '$(basename "$0") --init' to create your own"
        source "$ENSCONCE_DIR/config.example/settings.sh"
        CONFIG_DIR="$ENSCONCE_DIR/config.example"
    else
        log_error "No configuration found!"
        log_error "Run '$(basename "$0") --init' to create config from examples"
        exit 1
    fi

    log_info "Config: $CONFIG_DIR"
}

init_config() {
    local src="$ENSCONCE_DIR/config.example"
    local dst
    dst=$(default_config_target)

    if [[ ! -d "$src" ]]; then
        log_error "No config.example/ directory found"
        exit 1
    fi

    if [[ -d "$dst" ]]; then
        log_warn "Config directory already exists: $dst"
        if ! confirm "Overwrite with examples? (existing files will be replaced)" "n"; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
    log_success "Created $dst from config.example/"
    echo ""
    log_info "Edit these files to customize your setup:"
    echo "  config/settings.sh              Main settings (server URLs, feature toggles)"
    echo "  config/packages.list            RPM packages to layer"
    echo "  config/flatpaks.list            Flatpak applications"
    echo "  config/extensions.list          GNOME Shell extensions"
    echo "  config/flatpak-overrides/       Per-app Flatpak permissions"
    echo "  config/repos.d/                 RPM repository files"
    echo "  config/nextcloud/folders.list   Nextcloud sync folders"
    echo "  config/nextcloud/exclude.lst    Sync exclusion rules"
    echo "  config/certs/                   CA certificates (.pem)"
    echo "  config/dconf-settings.ini       GNOME desktop settings"
    echo "  config/gtk3-bookmarks           Nautilus sidebar bookmarks"
    echo "  config/gdm/dconf.d/             Login screen settings (applied as root)"
    echo "  config/gdm/monitors.xml         Login screen display layout (optional)"
}

# ============================================================================
# Step filtering (--skip / --only)
# ============================================================================

should_run_step() {
    local step="$1"

    # --only: whitelist mode
    if [[ ${#ONLY_STEPS[@]} -gt 0 ]]; then
        printf '%s\n' "${ONLY_STEPS[@]}" | grep -qx "$step"
        return $?
    fi

    # --skip: blacklist mode
    if [[ ${#SKIP_STEPS[@]} -gt 0 ]]; then
        if printf '%s\n' "${SKIP_STEPS[@]}" | grep -qx "$step"; then
            return 1
        fi
    fi

    return 0
}

validate_step_names() {
    local name
    for name in "$@"; do
        if [[ -z "${STEP_FILES[$name]+x}" ]]; then
            log_error "Unknown step: '$name'"
            log_info "Available steps: ${ALL_STEPS[*]}"
            exit 1
        fi
    done
}

# ============================================================================
# Argument parsing
# ============================================================================

show_help() {
    cat << HELPEOF
ensconce — Bluefin-DX Post-Installation Setup (v${ENSCONCE_VERSION})

Usage: $(basename "$0") [options]

Options:
  --init              Create personal config from config.example/
  --export [dir]      Capture this machine's setup into a config directory
  --config-dir        Print the config directory in use and exit
  --skip <steps>      Skip step(s) (comma-separated: rebase,ujust,packages)
  --only <steps>      Run only these step(s) (comma-separated)
  --dry-run           Show what would be done without executing
  --log [file]        Log output to file (default: timestamped in state dir)
  --status            Show current progress and exit
  --list-steps        List all available steps and exit
  --reset             Clear saved progress and start fresh
  -h, --help          Show this help message

Steps:
$(for step in "${ALL_STEPS[@]}"; do printf "  %-17s %s\n" "$step" "${STEP_DESCRIPTIONS[$step]}"; done)

Examples:
  $(basename "$0")                          # Run all steps
  $(basename "$0") --skip rebase,ujust      # Skip rebase and ujust
  $(basename "$0") --only extensions,dconf  # Only run extensions and dconf
  $(basename "$0") --dry-run --log          # Preview with logging
  $(basename "$0") --init                   # Create config from examples
  $(basename "$0") --export ./my-setup      # Capture this machine's setup

Config:
  Searched in order, first match wins:
    \$ENSCONCE_CONFIG
    ${XDG_CONFIG_DIR}
    ${ENSCONCE_DIR}/config
    ${ENSCONCE_DIR}/config.example  (fallback)

  Run --init to create one, --config-dir to see which is active.

Moving a setup to another machine:
  ensconce --export ./my-setup       # on the configured machine
  # review and edit ./my-setup, copy it to the new machine, then:
  ensconce --init                    # on the new machine
  cp -rT ./my-setup "\$(ensconce --config-dir)"
  ensconce --dry-run && ensconce

  See README.md for full documentation.
HELPEOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip)
                [[ -z "${2:-}" ]] && { log_error "--skip requires step name(s)"; exit 1; }
                IFS=',' read -ra _s <<< "$2"
                SKIP_STEPS+=("${_s[@]}")
                shift 2
                ;;
            --only)
                [[ -z "${2:-}" ]] && { log_error "--only requires step name(s)"; exit 1; }
                IFS=',' read -ra _s <<< "$2"
                ONLY_STEPS+=("${_s[@]}")
                shift 2
                ;;
            --dry-run)     DRY_RUN=true;       shift ;;
            --log)
                ENABLE_LOG=true
                if [[ "${2:-}" && ! "$2" =~ ^-- ]]; then
                    LOG_FILE="$2"; shift
                fi
                shift
                ;;
            --reset)       RESET_PROGRESS=true; shift ;;
            --status)      SHOW_STATUS=true;    shift ;;
            --init)        INIT_CONFIG=true;    shift ;;
            --list-steps)  LIST_STEPS=true;     shift ;;
            --config-dir)  SHOW_CONFIG_DIR=true; shift ;;
            --export)
                DO_EXPORT=true
                if [[ "${2:-}" && ! "$2" =~ ^-- ]]; then
                    EXPORT_TARGET="$2"; shift
                fi
                shift
                ;;
            -h|--help)     show_help ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$(basename "$0") --help' for usage"
                exit 1
                ;;
        esac
    done

    if [[ ${#SKIP_STEPS[@]} -gt 0 && ${#ONLY_STEPS[@]} -gt 0 ]]; then
        log_error "Cannot use --skip and --only together"
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Discover steps first (needed for --help and validation)
    discover_steps

    parse_args "$@"

    # ── Machine-readable output: nothing but the answer on stdout ──
    # (--config-dir is meant to be used as "$(ensconce --config-dir)")

    if [[ "$SHOW_CONFIG_DIR" == "true" ]]; then
        resolve_config_dir || default_config_target
        exit 0
    fi

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Ensconce — Bluefin-DX Setup  v${ENSCONCE_VERSION}               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # ── Standalone commands (no config needed) ──

    if [[ "$INIT_CONFIG" == "true" ]]; then
        init_config
        exit 0
    fi

    if [[ "$DO_EXPORT" == "true" ]]; then
        run_export "$EXPORT_TARGET"
        exit 0
    fi

    if [[ "$LIST_STEPS" == "true" ]]; then
        echo "Available steps:"
        for step in "${ALL_STEPS[@]}"; do
            printf "  %-17s %s\n" "$step" "${STEP_DESCRIPTIONS[$step]}"
        done
        exit 0
    fi

    # ── Logging ──

    if [[ "$ENABLE_LOG" == "true" ]]; then
        mkdir -p "$STATE_DIR"
        [[ -z "$LOG_FILE" ]] && LOG_FILE="$STATE_DIR/setup-$(date +%Y-%m-%d_%H%M%S).log"
        start_logging "$LOG_FILE" "$@"
    fi

    # ── Reset / Status (need state dir but not full config) ──

    if [[ "$RESET_PROGRESS" == "true" ]]; then
        init_progress
        reset_progress
        exit 0
    fi

    if [[ "$SHOW_STATUS" == "true" ]]; then
        init_progress
        show_progress_status
        exit 0
    fi

    # ── Full run ──

    load_config
    load_steps

    # Validate step names
    [[ ${#SKIP_STEPS[@]} -gt 0 ]] && validate_step_names "${SKIP_STEPS[@]}"
    [[ ${#ONLY_STEPS[@]} -gt 0 ]] && validate_step_names "${ONLY_STEPS[@]}"

    init_progress

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE — No changes will be made"
    fi

    # Preflight checks
    run_preflight_checks

    # System info
    log_section "System Information"
    log_info "Image:    $(get_current_image)"
    log_info "Hostname: $(hostname)"
    log_info "User:     $(whoami)"
    log_info "Config:   $CONFIG_DIR"
    if is_dx_image; then
        log_info "Already running a DX variant"
    else
        log_warn "Not currently on a DX variant"
    fi
    echo ""

    # Progress / resume logic
    local next_step
    next_step=$(get_next_step)

    if [[ "$next_step" == "done" && ${#ONLY_STEPS[@]} -eq 0 ]]; then
        log_success "All steps already completed!"
        show_progress_status
        if confirm "Reset progress and start fresh?" "n"; then
            reset_progress
            next_step=$(get_next_step)
        else
            exit 0
        fi
    fi

    if check_pending_reboot; then
        log_info "Continuing setup after reboot..."
    elif [[ "$next_step" != "${ALL_STEPS[0]:-}" ]]; then
        log_info "Resuming from step: $next_step"
        show_progress_status
        echo ""
    fi

    if ! confirm "Continue with setup?"; then
        log_info "Setup cancelled"
        exit 0
    fi

    # Prevent sleep
    start_inhibitor
    trap 'stop_inhibitor' EXIT

    # ── Run steps ──

    for step_name in "${ALL_STEPS[@]}"; do
        # Already completed (from saved progress)
        if is_step_done "$step_name" && [[ ${#ONLY_STEPS[@]} -eq 0 ]]; then
            log_info "[$step_name] Already completed"
            continue
        fi

        # Filtered out by --skip / --only
        if ! should_run_step "$step_name"; then
            log_info "[$step_name] Skipped"
            mark_step_done "$step_name"
            continue
        fi

        # Run the step
        local step_rc=0
        "step_${step_name}" || step_rc=$?

        case $step_rc in
            0)
                mark_step_done "$step_name"
                ;;
            42)
                # Step signalled "reboot required"
                mark_step_done "$step_name"
                log_warn "Reboot required to continue. Run the script again after reboot."
                exit 0
                ;;
            *)
                log_warn "Step '$step_name' had issues (exit code: $step_rc)"
                if ! confirm "Continue with remaining steps?"; then
                    exit 1
                fi
                # Mark done anyway so we don't loop on a broken step
                mark_step_done "$step_name"
                ;;
        esac
    done

    # ── Done ──

    log_section "Setup Complete!"
    show_progress_status
    echo ""

    if is_step_done "packages"; then
        log_info "If you layered packages, reboot to apply rpm-ostree changes!"
    fi
    if is_step_done "nextcloud"; then
        log_info "Don't forget to log in to Nextcloud to activate folder syncs!"
    fi

    log_info "After reboot, you may need to log out/in for extensions to activate"
    echo ""

    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        log_info "Full log: $LOG_FILE"
    fi

    log_success "All done! Enjoy your Bluefin-DX setup 🐟"

    if confirm "Clear saved progress (setup complete)?" "y"; then
        reset_progress
    fi
}

main "$@"
