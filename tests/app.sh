#!/usr/bin/env bash
# tests/app.sh — what the Ensconce app needs from the command: --export with
# --parts and the info file, --yes, output without colour codes when it is no
# terminal, sudo through SUDO_ASKPASS. Run against a throwaway $HOME with a
# stub dconf and systemctl on PATH; nothing outside it is read or written.
#
#   bash tests/app.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

STUB="$WORK/stub"
mkdir -p "$STUB" "$WORK/home/.config/gtk-3.0"
# dconf: dump prints a group with an old font; read/reset keep keys in files
export FAKE_DCONF="$WORK/dconfkeys"
cat > "$STUB/dconf" << 'EOF'
#!/usr/bin/env bash
case $1 in
    dump)  if [[ $2 == /org/gnome/desktop/interface/ ]]; then
               printf "[/]\nfont-name='Cantarell 11'\nmonospace-font-name='JetBrains Mono 11'\n"
           else printf '[/]\nkey=1\n'; fi ;;
    read)  cat "$FAKE_DCONF$2" 2>/dev/null ;;
    reset) echo "reset $2" >> "$FAKE_DCONF.log"; rm -f "$FAKE_DCONF$2" ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/systemctl"
# fc-list: the new fonts are installed
printf '#!/usr/bin/env bash\necho "Adwaita Sans"\necho Cantarell\n' > "$STUB/fc-list"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/fc-cache"
chmod +x "$STUB"/*
echo "file:///tmp Tmp" > "$WORK/home/.config/gtk-3.0/bookmarks"

ens() {
    env -i HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_STATE_HOME="$WORK/state" \
        PATH="$STUB:/usr/bin:/bin" ENSCONCE_INHIBITED=1 bash "$ROOT/ensconce.sh" "$@" < /dev/null
}

# ── --export --parts ───────────────────────────────────────────────────────
out="$(ens --yes --export "$WORK/exp" --parts dconf,power 2>&1)"; rc=$?
check "--export --parts exits 0" test "$rc" -eq 0
check "the chosen parts are written" test -f "$WORK/exp/dconf-settings.ini" -a -f "$WORK/exp/gtk3-bookmarks"
check "the others are not" test ! -e "$WORK/exp/packages.list" -a ! -e "$WORK/exp/flatpaks.list" -a ! -d "$WORK/exp/nextcloud"
check "settings.sh is always written" test -f "$WORK/exp/settings.sh"
check "the info file names the parts" grep -qx 'PARTS=dconf power' "$WORK/exp/ensconce-export.info"
check "the info file names the host" grep -q '^HOST=.' "$WORK/exp/ensconce-export.info"
check "the info file names the version" \
    grep -qx "VERSION=$(sed -n 's/^VERSION=//p' "$ROOT/kiwi.manifest")" "$WORK/exp/ensconce-export.info"
check "no colour codes without a terminal" bash -c '! grep -q $'"'"'\033'"'"' <<<"$1"' _ "$out"

out="$(ens --yes --export "$WORK/exp2" --parts dconf,bogus 2>&1)"; rc=$?
check "an unknown part is refused" test "$rc" -ne 0 -a ! -e "$WORK/exp2/settings.sh"

ens --yes --export "$WORK/all" > /dev/null 2>&1
check "without --parts every part but the fonts is exported" grep -qx 'PARTS=packages repos flatpaks overrides extensions cacert nextcloud dconf gdm ssh kiwi sysctl power' "$WORK/all/ensconce-export.info"
check "an old font setting is left out of the export, as a comment" \
    grep -qx "# font-name='Cantarell 11'   # GNOME's font before GNOME 48, left out" "$WORK/all/dconf-settings.ini"
check "other font settings stay in the export" grep -qx "monospace-font-name='JetBrains Mono 11'" "$WORK/all/dconf-settings.ini"

# ── fonts ──────────────────────────────────────────────────────────────────
mkdir -p "$WORK/home/.local/share/fonts/sub" "$WORK/home/.fonts/sub"
echo a > "$WORK/home/.local/share/fonts/sub/A.ttf"
echo u > "$WORK/home/.local/share/fonts/.uuid"
echo b > "$WORK/home/.fonts/B.otf"
echo old > "$WORK/home/.fonts/sub/A.ttf"
ens --yes --export "$WORK/fexp" --parts fonts > /dev/null 2>&1
check "--parts fonts exports both font folders" test -f "$WORK/fexp/fonts/sub/A.ttf" -a -f "$WORK/fexp/fonts/B.otf"
check "the newer font folder wins over the older one" grep -qx a "$WORK/fexp/fonts/sub/A.ttf"
check "fontconfig's cache files are not exported" test ! -e "$WORK/fexp/fonts/.uuid"

# the fonts step: installs what is missing, keeps what differs, resets old font settings
mkdir -p "$WORK/fhome/.local/share/fonts/sub" "$FAKE_DCONF/org/gnome/desktop/interface"
echo mine > "$WORK/fhome/.local/share/fonts/sub/A.ttf"
echo "'Cantarell 11'" > "$FAKE_DCONF/org/gnome/desktop/interface/font-name"
echo "'JetBrains Mono 11'" > "$FAKE_DCONF/org/gnome/desktop/interface/monospace-font-name"
env -i HOME="$WORK/fhome" PATH="$STUB:/usr/bin:/bin" FAKE_DCONF="$FAKE_DCONF" CONFIG_DIR="$WORK/fexp" \
    ASSUME_DEFAULTS=true bash -c '
    for l in "$0"/lib/*.sh; do source "$l"; done; source "$0/steps/16-fonts.sh"; step_fonts' "$ROOT" \
    < /dev/null > "$WORK/fonts.out" 2>&1
check "the fonts step installs a missing font" test -f "$WORK/fhome/.local/share/fonts/B.otf"
check "the fonts step keeps your font of the same name" grep -qx mine "$WORK/fhome/.local/share/fonts/sub/A.ttf"
check "the fonts step resets a setting that names Cantarell" grep -qx 'reset /org/gnome/desktop/interface/font-name' "$FAKE_DCONF.log"
check "the fonts step keeps other font settings" test -f "$FAKE_DCONF/org/gnome/desktop/interface/monospace-font-name"

# ── --init next to the app's own settings ─────────────────────────────────
mkdir -p "$WORK/inithome/.config/ensconce"
echo '{}' > "$WORK/inithome/.config/ensconce/settings.json"
env -i HOME="$WORK/inithome" PATH="$STUB:/usr/bin:/bin" ENSCONCE_INHIBITED=1 \
    bash -c '
    cp -r "$0" "$1/copy" && touch "$1/copy/.installed" && bash "$1/copy/ensconce.sh" --init' \
    "$ROOT" "$WORK" < /dev/null > /dev/null 2>&1
check "--init fills an existing folder without a config" test -f "$WORK/inithome/.config/ensconce/settings.sh"
check "--init does not nest config.example" test ! -e "$WORK/inithome/.config/ensconce/config.example"
check "--init keeps the app's settings.json" test -f "$WORK/inithome/.config/ensconce/settings.json"

# ── --yes, sudo through SUDO_ASKPASS ───────────────────────────────────────
# helpers <ASSUME_DEFAULTS> <SUDO_ASKPASS> <code>: code run with the libs loaded
helpers() {
    env -i PATH="$STUB:/usr/bin:/bin" ASSUME_DEFAULTS="$1" SUDO_ASKPASS="$2" bash -c '
        source "$0/lib/logging.sh"; source "$0/lib/helpers.sh"; eval "$1"' "$ROOT" "$3" < /dev/null
}
check "--yes takes a question's default yes" helpers true "" 'confirm "Go?" y > /dev/null'
if helpers true "" 'confirm "Go?" n' > /dev/null; then bad "--yes takes a question's default no"
else ok "--yes takes a question's default no"; fi
check "SUDO_ASKPASS without a terminal makes sudo ask with -A" \
    test "$(helpers false /bin/true 'type -t sudo')" = function
check "without SUDO_ASKPASS sudo is sudo" test "$(helpers false '' 'type -t sudo')" != function

# ── --dry-run records no progress ─────────────────────────────────────────
check "a dry run marks no step done" env -i PATH="/usr/bin:/bin" STATE="$WORK/drystate" bash -c '
    STATE_DIR="$STATE" PROGRESS_FILE="$STATE/progress" DRY_RUN=true
    source "$0/lib/logging.sh"; source "$0/lib/progress.sh"
    mark_step_done dconf; ! is_step_done dconf' "$ROOT"

out="$(env -i PATH="/usr/bin:/bin" STATE="$WORK/drystate" bash -c '
    STATE_DIR="$STATE" PROGRESS_FILE="$STATE/progress" ALL_STEPS=(a b)
    source "$0/lib/logging.sh"; source "$0/lib/progress.sh"; show_progress_status' "$ROOT" 2>&1)"
check "--status with nothing done says 0/2" grep -q 'Progress: 0/2 steps completed' <<<"$out"

echo
if [[ $fails -gt 0 ]]; then echo "$fails failed"; exit 1; fi
echo "all passed"
