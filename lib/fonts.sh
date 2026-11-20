#!/bin/bash
# lib/fonts.sh - Your own fonts, and font settings left over from before GNOME 48
#
# GNOME 48 replaced its fonts: Adwaita Sans and Adwaita Mono took the place
# of Cantarell and Source Code Pro. A setting that names the old ones
# explicitly (GNOME Tweaks writes them, so do old dconf exports) still wins
# over the new defaults on an updated Bluefin, and an export carries it on to
# every new computer. The old fonts themselves come with the image and stay.

# Where fonts of your own live; ~/.fonts is the old place fontconfig still reads
# shellcheck disable=SC2034  # read by lib/export.sh
FONT_DIRS=("$HOME/.local/share/fonts" "$HOME/.fonts")

# The dconf keys that name a font
FONT_KEYS=(
    /org/gnome/desktop/interface/font-name
    /org/gnome/desktop/interface/document-font-name
    /org/gnome/desktop/interface/monospace-font-name
    /org/gnome/desktop/wm/preferences/titlebar-font
)

# GNOME's fonts before 48
OLD_FONT_RE='Cantarell|Source Code Pro'

# Files fontconfig and X keep next to the fonts; not fonts
font_file_is_cache() {
    case "${1##*/}" in
        .uuid|fonts.dir|fonts.scale|fonts.cache-*) return 0 ;;
    esac
    return 1
}

# The new fonts are installed: GNOME 48 or later
have_adwaita_fonts() {
    fc-list : family 2>/dev/null | grep -q '^Adwaita Sans'
}

# Look for font settings that name Cantarell or Source Code Pro, and offer to
# reset the ones in your dconf, so the system's default fonts apply. System
# files that name them are only reported: /etc keeps a file you (or an old
# image) changed across updates, and it is yours to look at.
fix_old_font_settings() {
    if ! have_adwaita_fonts; then
        log_info "Fonts: Adwaita Sans is not installed, so Cantarell is still GNOME's font here"
        return 0
    fi

    local key value stale=()
    for key in "${FONT_KEYS[@]}"; do
        value=$(dconf read "$key" 2>/dev/null)
        [[ -n "$value" && "$value" =~ $OLD_FONT_RE ]] || continue
        log_info "  ${key##*/} = $value"
        stale+=("$key")
    done

    local f
    for f in /etc/dconf/db/*.d/* "${XDG_CONFIG_HOME:-$HOME/.config}"/fontconfig/fonts.conf \
             "${XDG_CONFIG_HOME:-$HOME/.config}"/fontconfig/conf.d/*.conf; do
        [[ -f "$f" ]] && grep -qE "$OLD_FONT_RE" "$f" 2>/dev/null || continue
        log_warn "  $f names $(grep -oE "$OLD_FONT_RE" "$f" | sort -u | paste -sd, -) — check it by hand"
    done

    if [[ ${#stale[@]} -eq 0 ]]; then
        log_success "Fonts: no setting names GNOME's fonts from before GNOME 48"
        return 0
    fi

    log_info "These settings name Cantarell or Source Code Pro, GNOME's fonts before GNOME 48."
    log_info "They win over today's defaults (Adwaita Sans and Adwaita Mono, or your image's)."
    if ! confirm "Reset them, so the default fonts apply?"; then
        log_warn "Old font settings kept"
        return 0
    fi
    for key in "${stale[@]}"; do
        run_cmd dconf reset "$key"
    done
    log_success "Font settings reset to the defaults"
}
