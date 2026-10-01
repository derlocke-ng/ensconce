#!/bin/bash
# dconf-backup.sh - Export and import GNOME/dconf settings
# Usage:
#   ./dconf-backup.sh export [file]    - Export settings to file (default: dconf-backup.ini)
#   ./dconf-backup.sh import <file>    - Import settings from file
#   ./dconf-backup.sh export-path <path> [file] - Export specific dconf path
#   ./dconf-backup.sh import-path <path> <file> - Import to specific dconf path

set -euo pipefail

DEFAULT_FILE="dconf-backup.ini"

usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
    export [file]              Export all dconf settings to file
                               Default file: $DEFAULT_FILE
    
    import <file>              Import settings from file
    
    export-path <path> [file]  Export specific dconf path (e.g., /org/gnome/)
                               Default file: $DEFAULT_FILE
    
    import-path <path> <file>  Import settings to specific dconf path

Options:
    -h, --help                 Show this help message
    -q, --quiet                Suppress non-error output

Examples:
    $(basename "$0") export                     # Export all to dconf-backup.ini
    $(basename "$0") export my-settings.ini    # Export all to my-settings.ini
    $(basename "$0") import my-settings.ini    # Import from file
    $(basename "$0") export-path /org/gnome/terminal/  # Export terminal settings
EOF
    exit "${1:-0}"
}

log() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo "$@"
    fi
}

error() {
    echo "Error: $*" >&2
    exit 1
}

check_dconf() {
    if ! command -v dconf &> /dev/null; then
        error "dconf command not found. Please install dconf-cli."
    fi
}

do_export() {
    local output_file="${1:-$DEFAULT_FILE}"
    
    check_dconf
    log "Exporting dconf settings to: $output_file"
    
    dconf dump / > "$output_file"
    
    log "Export complete: $(wc -l < "$output_file") lines written"
}

do_import() {
    local input_file="$1"
    
    if [[ -z "$input_file" ]]; then
        error "Import requires a file argument"
    fi
    
    if [[ ! -f "$input_file" ]]; then
        error "File not found: $input_file"
    fi
    
    check_dconf
    log "Importing dconf settings from: $input_file"
    
    dconf load / < "$input_file"
    
    log "Import complete"
}

do_export_path() {
    local dconf_path="$1"
    local output_file="${2:-$DEFAULT_FILE}"
    
    if [[ -z "$dconf_path" ]]; then
        error "export-path requires a dconf path argument"
    fi
    
    # Ensure path ends with /
    [[ "$dconf_path" != */ ]] && dconf_path="$dconf_path/"
    
    check_dconf
    log "Exporting dconf path '$dconf_path' to: $output_file"
    
    dconf dump "$dconf_path" > "$output_file"
    
    log "Export complete: $(wc -l < "$output_file") lines written"
}

do_import_path() {
    local dconf_path="$1"
    local input_file="$2"
    
    if [[ -z "$dconf_path" ]]; then
        error "import-path requires a dconf path argument"
    fi
    
    if [[ -z "$input_file" ]]; then
        error "import-path requires a file argument"
    fi
    
    if [[ ! -f "$input_file" ]]; then
        error "File not found: $input_file"
    fi
    
    # Ensure path ends with /
    [[ "$dconf_path" != */ ]] && dconf_path="$dconf_path/"
    
    check_dconf
    log "Importing dconf settings to path '$dconf_path' from: $input_file"
    
    dconf load "$dconf_path" < "$input_file"
    
    log "Import complete"
}

# Parse global options
QUIET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage 0
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

# Main command dispatch
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    export)
        do_export "${1:-}"
        ;;
    import)
        do_import "${1:-}"
        ;;
    export-path)
        do_export_path "${1:-}" "${2:-}"
        ;;
    import-path)
        do_import_path "${1:-}" "${2:-}"
        ;;
    ""|help)
        usage 0
        ;;
    *)
        error "Unknown command: $COMMAND. Use --help for usage."
        ;;
esac
