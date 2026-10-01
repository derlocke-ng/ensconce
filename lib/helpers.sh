#!/bin/bash
# lib/helpers.sh - Common helper functions

# Run a command, or print it in dry-run mode
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $*"
    else
        "$@"
    fi
}

# Prompt for yes/no confirmation
# Usage: confirm "Do this?" [y|n]
confirm() {
    local prompt="$1"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    read -r -p "$prompt" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

# Check that a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command not found: $1"
        return 1
    fi
}

# Get the current rpm-ostree / bootc image reference
get_current_image() {
    local image
    image=$(rpm-ostree status --json \
        | jq -r '.deployments[0]."container-image-reference"' 2>/dev/null)

    if [[ -z "$image" || "$image" == "null" ]]; then
        image=$(rpm-ostree status --json \
            | jq -r '.deployments[0].origin' 2>/dev/null)
    fi
    echo "${image:-unknown}"
}

is_dx_image() {
    [[ "$(get_current_image)" == *"-dx"* ]]
}

is_bluefin_image() {
    [[ "$(get_current_image)" == *"bluefin"* ]]
}

# Read a list file: strips comments (#), blank lines, leading/trailing whitespace
read_list_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$file" \
        | grep -v '^$'
}

# Generate a random 12-character hex string
generate_hex_id() {
    head -c 6 /dev/urandom | xxd -p
}
