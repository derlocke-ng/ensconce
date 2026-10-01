#!/bin/bash
# lib/logging.sh - Logging and output formatting

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

log_section() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  $*${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Start logging all output to a file (while still printing to terminal)
# Usage: start_logging "/path/to/logfile" "$@"
start_logging() {
    local log_file="$1"
    shift

    mkdir -p "$(dirname "$log_file")"

    {
        echo "=================================================================="
        echo "Ensconce Setup Log"
        echo "=================================================================="
        echo "Date:     $(date -Iseconds)"
        echo "Hostname: $(hostname)"
        echo "User:     $(whoami)"
        echo "Kernel:   $(uname -r)"
        echo "Shell:    $BASH_VERSION"
        echo "Args:     $*"
        echo "PWD:      $(pwd)"
        echo ""
        if command -v rpm-ostree &> /dev/null; then
            echo "Image:    $(rpm-ostree status --json 2>/dev/null \
                | jq -r '.deployments[0]."container-image-reference" // .deployments[0].origin // "unknown"' 2>/dev/null \
                || echo 'unknown')"
        fi
        if command -v gnome-shell &> /dev/null; then
            echo "GNOME:    $(gnome-shell --version 2>/dev/null || echo 'unknown')"
        fi
        echo "=================================================================="
        echo ""
    } > "$log_file"

    # Redirect stdout+stderr through tee; stdin stays on terminal for prompts
    exec > >(tee -a "$log_file") 2>&1

    log_info "Logging to: $log_file"
}
