#!/usr/bin/env bash
# tests/install.sh — install.sh install, update and uninstall, with and without
# the app, into a throwaway $HOME. Nothing outside it is read or written.
#
#   bash tests/install.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

H="$WORK/home"
mkdir -p "$H"
inst() { # inst <KIWI_GUI> <install.sh args...>
    local gui="$1"; shift
    env -i HOME="$H" PATH="/usr/bin:/bin" KIWI_GUI="$gui" bash "$ROOT/install.sh" "$@"
}
LIB="$H/.local/share/ensconce"
APPS="$H/.local/share/applications/eu.kiwinetwork.Ensconce.desktop"

# ── a first install, with the app ─────────────────────────────────────────
inst 1 install > "$WORK/out" 2>&1; rc=$?
check "install with the app exits 0" test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"
check "the command is linked" test -L "$H/.local/bin/ensconce" -a -f "$LIB/ensconce.sh"
check "the app's package is installed" test -f "$LIB/python/ensconce/__init__.py" -a -f "$LIB/python/ensconce/kit/__init__.py"
check "the app's launchers are installed" test -x "$LIB/bin/ensconce-gui" -a -x "$LIB/bin/ensconce-askpass"
check "ensconce-gui is linked" test -L "$H/.local/bin/ensconce-gui"
check "the app grid entry starts ensconce-gui" grep -qx "Exec=$H/.local/bin/ensconce-gui" "$APPS"
check "the icon is installed" test -f "$H/.local/share/icons/hicolor/scalable/apps/eu.kiwinetwork.Ensconce.svg"
check "the installed command runs" env -i HOME="$H" PATH=/usr/bin:/bin bash "$H/.local/bin/ensconce" --list-steps > /dev/null
check "the installed app finds its command and icon" env -i HOME="$H" PATH=/usr/bin:/bin \
    PYTHONPATH="$LIB/python" python3 -c '
from ensconce import ROOT, INFO
from ensconce.core import cli
assert cli.SCRIPT.is_file() and cli.ASKPASS.is_file() and INFO.stock_icon.is_file(), ROOT'

# ── an update over it, and over a half-done one ───────────────────────────
mkdir -p "$H/.config/ensconce" && echo '{}' > "$H/.config/ensconce/settings.json"
rm -rf "$LIB/python"   # the state a failed 2.6.0 update left behind
inst 1 update > "$WORK/out" 2>&1; rc=$?
check "update exits 0, also after a failed one" test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"
check "update puts the app back" test -f "$LIB/python/ensconce/__init__.py"
check "update leaves no nested package" test ! -e "$LIB/python/ensconce/ensconce"
check "update keeps the app's settings" test -f "$H/.config/ensconce/settings.json"

# ── without GTK ───────────────────────────────────────────────────────────
inst 0 update > "$WORK/out" 2>&1; rc=$?
check "update without the app exits 0" test "$rc" -eq 0
check "without the app, its link and entry go" test ! -e "$H/.local/bin/ensconce-gui" -a ! -e "$APPS"
check "without the app, the command stays" test -L "$H/.local/bin/ensconce"

# ── uninstall ─────────────────────────────────────────────────────────────
inst 1 install > /dev/null 2>&1
mkdir -p "$H/Ensconce/papaya"
inst 1 uninstall > /dev/null 2>&1
check "uninstall removes the command, the app and its entry" \
    test ! -e "$H/.local/bin/ensconce" -a ! -e "$H/.local/bin/ensconce-gui" -a ! -e "$LIB" -a ! -e "$APPS"
check "uninstall keeps the config" test -d "$H/.config/ensconce"
inst 1 uninstall --purge > /dev/null 2>&1
check "--purge removes the config" test ! -e "$H/.config/ensconce"
check "--purge keeps the exports folder" test -d "$H/Ensconce/papaya"

echo
if [[ $fails -gt 0 ]]; then echo "$fails failed"; exit 1; fi
echo "all passed"
