#!/bin/bash
# Step: fonts
# Description: Install your own fonts, reset font settings left over from before GNOME 48

step_fonts() {
    local src="$CONFIG_DIR/fonts"
    local dst="$HOME/.local/share/fonts"

    if [[ -d "$src" ]]; then
        local f rel new=() differ=0
        while IFS= read -r -d '' f; do
            rel="${f#"$src"/}"
            font_file_is_cache "$rel" && continue
            if [[ ! -e "$dst/$rel" ]]; then
                new+=("$rel")
            elif ! cmp -s "$f" "$dst/$rel"; then
                differ=$((differ + 1))
            fi
        done < <(find "$src" -type f -print0 | sort -z)

        [[ $differ -gt 0 ]] && log_info "$differ font file(s) differ from yours of the same name; yours stay"
        if [[ ${#new[@]} -eq 0 ]]; then
            log_info "Fonts: every font in fonts/ is installed already"
        elif confirm "Install ${#new[@]} font file(s) into ~/.local/share/fonts?"; then
            for rel in "${new[@]}"; do
                run_cmd install -Dm644 "$src/$rel" "$dst/$rel" || return 1
            done
            run_cmd fc-cache -f "$dst" > /dev/null
            log_success "${#new[@]} font file(s) installed"
        fi
    else
        log_info "No fonts/ in the config"
    fi

    echo ""
    fix_old_font_settings
}
