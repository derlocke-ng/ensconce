#!/usr/bin/env bash
# tests/steps.sh — the ssh, kiwi and sysctl steps and their --export, run against a
# throwaway $HOME with stub systemctl, flatpak, ssh-add, curl, sudo and kiwi
# on PATH.
# Nothing outside the temporary directory is read or written.
#
#   bash tests/steps.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok()  { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

# ── stubs ───────────────────────────────────────────────────────────────────
STUB="$WORK/stub"
mkdir -p "$STUB"
export CALLS="$WORK/calls.log" FAKE_ENV="$WORK/manager.env"

# A user manager that keeps its mask where systemd does; FAKE_MANAGER=0 is
# "no manager reachable" (ensconce run over ssh), FAKE_GCR=0 "no gcr installed"
cat > "$STUB/systemctl" << 'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$CALLS"
[[ $1 == --user ]] && shift
[[ ${FAKE_MANAGER:-1} == 1 ]] || exit 1
units="$XDG_CONFIG_HOME/systemd/user"
case $1 in
    show-environment) cat "$FAKE_ENV" 2>/dev/null; exit 0 ;;
    cat)              [[ ${FAKE_GCR:-1} == 1 ]] ;;
    mask)             shift; [[ $1 == --now ]] && shift
                      mkdir -p "$units"; ln -sfn /dev/null "$units/$1" ;;
    unmask)           rm -f "$units/$2" ;;
    set-environment)  echo "$2" >> "$FAKE_ENV" ;;
    *)                exit 0 ;;
esac
EOF

cat > "$STUB/flatpak" << 'EOF'
#!/usr/bin/env bash
[[ $1 == info ]] && exit "${FAKE_BW_MISSING:-0}"
exit 0
EOF

printf '#!/usr/bin/env bash\nexit 2\n' > "$STUB/ssh-add"

# sudo only records what it was asked to do
printf '#!/usr/bin/env bash\necho "sudo $*" >> "$CALLS"\n' > "$STUB/sudo"

# kiwi's porcelain list: tab-separated, fields 8-10 and 12 empty on purpose.
# Not on PATH: kiwi counts as installed only once get-kiwi.sh (or a test)
# has put it in ~/.local/bin.
KIWI_STUB="$WORK/kiwi-stub"
cat > "$KIWI_STUB" << 'EOF'
#!/usr/bin/env bash
echo "kiwi $*" >> "$CALLS"
case $1 in
    version) echo "kiwi 2.3.1" ;;
    list)
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            ensconce user cli installed 2.2.0 u d "" "" "" dir "" user "" data/ensconce.svg \
            syncman user "cli gui" not-installed - u d "" "" "" dir "" "" "" "" \
            kiwi-updater "user system" "cli gui" installed 2.3.1 u d "" "" "" dir "" "user system" "" "" \
            kiwi-fox user cli installed 0.1.4 u d "" "" "" dir "" user v0.1.3 "" ;;
esac
exit 0
EOF

# curl fetches a get-kiwi.sh that records its arguments and installs the stub
cat > "$STUB/curl" << 'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
out=""
while (($#)); do [[ $1 == -o ]] && { out=$2; shift; }; shift; done
cat > "$out" << 'GET'
echo "get-kiwi $*" >> "$CALLS"
mkdir -p "$HOME/.local/bin"
cp "$KIWI_STUB" "$HOME/.local/bin/kiwi"
GET
EOF
chmod +x "${STUB:?}"/* "$KIWI_STUB"
export STUB KIWI_STUB

# ── harness ─────────────────────────────────────────────────────────────────
fresh_home() {
    rm -rf "${WORK:?}/home" "${WORK:?}/cfg" "$CALLS" "$FAKE_ENV"
    mkdir -p "$WORK/home" "$WORK/cfg/nextcloud"
    export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config"
    : > "$WORK/cfg/settings.sh"
}

setting() { echo "$1=\"$2\"" >> "$WORK/cfg/settings.sh"; }

# Runs one step the way ensconce.sh does: errexit on, but the step is called
# in an || list (so errexit is off inside it) while nounset still applies.
# stdin answers the prompts; output goes to $WORK/out, the exit code to $rc.
run_step() {
    rc=0
    (
        set -euo pipefail
        PATH="$STUB:$PATH"
        DRY_RUN="${DRY:-false}" CONFIG_DIR="$WORK/cfg" STATE_DIR="$WORK/state"
        for l in "$ROOT"/lib/*.sh; do source "$l"; done
        source "$WORK/cfg/settings.sh"
        source "$ROOT"/steps/[0-9][0-9]-"$1".sh
        r=0; "step_$1" || r=$?
        exit $r
    ) > "$WORK/out" 2>&1 || rc=$?
}

run_export() { # function...
    rm -rf "${WORK:?}/export"
    mkdir -p "$WORK/export"
    (
        set -euo pipefail
        PATH="$STUB:$PATH"
        DRY_RUN=false CONFIG_DIR="$WORK/cfg"
        for l in "$ROOT"/lib/*.sh; do source "$l"; done
        # After the libs: lib/export.sh starts out with EXPORT_DIR="", and the
        # export functions write wherever it points
        EXPORT_DIR="$WORK/export"
        for f in "$@"; do "$f"; done
    ) > "$WORK/out" 2>&1
}

out_has()   { grep -qF -- "$1" "$WORK/out"; }
calls_has() { grep -qxF -- "$1" "$CALLS" 2>/dev/null; }
mode()      { stat -c %a "$1" 2>/dev/null; }
SOCK_LINE() { echo "SSH_AUTH_SOCK=$HOME/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock"; }

ssh_settings() {
    setting SSH_SYNCED_DIR .ssh/.sshsynched
    setting SSH_CONTROL_DIR .ssh/control_sockets
    setting SSH_AGENT bitwarden
    echo ".ssh/.sshsynched|/ssh" > "$WORK/cfg/nextcloud/folders.list"
}

echo "== ssh step"

fresh_home; ssh_settings
run_step ssh < /dev/null
check "fresh: step succeeds"                [ "$rc" = 0 ]
check "fresh: ~/.ssh is 0700"               [ "$(mode "$HOME/.ssh")" = 700 ]
check "fresh: synced folder is 0700"        [ "$(mode "$HOME/.ssh/.sshsynched")" = 700 ]
check "fresh: control dir is 0700"          [ "$(mode "$HOME/.ssh/control_sockets")" = 700 ]
check "fresh: config is a relative link"    [ "$(readlink "$HOME/.ssh/config")" = .sshsynched/config ]
check "fresh: SSH_AUTH_SOCK in environment.d" \
      grep -qxF "$(SOCK_LINE)" "$HOME/.config/environment.d/90-ensconce-ssh-agent.conf"
check "fresh: gcr socket masked"            [ "$(readlink "$HOME/.config/systemd/user/gcr-ssh-agent.socket")" = /dev/null ]
check "fresh: masked through the manager"   calls_has "systemctl --user mask --now gcr-ssh-agent.socket"
check "fresh: session environment updated"  grep -qxF "$(SOCK_LINE)" "$FAKE_ENV"
check "fresh: no folders.list warning"      bash -c "! grep -qF 'is in neither' '$WORK/out'"
check "fresh: says how to turn the agent on" out_has 'Enable SSH agent'

run_step ssh < /dev/null
check "rerun: succeeds"                     [ "$rc" = 0 ]
check "rerun: masks only once"              [ "$(grep -c 'mask --now' "$CALLS")" = 1 ]
check "rerun: link left alone"              out_has 'Already linked'
check "rerun: env file left alone"          out_has 'already points at Bitwarden'

# The layout this was written for: an absolute link straight into the folder
fresh_home; ssh_settings
mkdir -p "$HOME/.ssh/.sshsynched"; echo "Host x" > "$HOME/.ssh/.sshsynched/config"
ln -s "$HOME/.ssh/.sshsynched/config" "$HOME/.ssh/config"
run_step ssh < /dev/null
check "absolute link: made relative"        [ "$(readlink "$HOME/.ssh/config")" = .sshsynched/config ]
check "absolute link: said so"              out_has 'relative link (same target)'
check "absolute link: synced config 0600"   [ "$(mode "$HOME/.ssh/.sshsynched/config")" = 600 ]

fresh_home; ssh_settings
mkdir -p "$HOME/.ssh/.sshsynched"
echo "Host synced" > "$HOME/.ssh/.sshsynched/config"; echo "Host local" > "$HOME/.ssh/config"
run_step ssh < /dev/null
check "local + synced: local backed up"     grep -qx "Host local" "$HOME"/.ssh/config.ensconce-*
check "local + synced: linked"              [ "$(readlink "$HOME/.ssh/config")" = .sshsynched/config ]
check "local + synced: reads synced"        grep -qx "Host synced" "$HOME/.ssh/config"

fresh_home; ssh_settings
mkdir -p "$HOME/.ssh"; echo "Host local" > "$HOME/.ssh/config"
# Two prompts: "Apply the SSH settings?", then whether to move the config
printf 'y\ny\n' | run_step ssh
check "local only, move: moved into folder" grep -qx "Host local" "$HOME/.ssh/.sshsynched/config"
check "local only, move: no backup"         bash -c "! ls '$HOME'/.ssh/config.ensconce-* 2>/dev/null"
check "local only, move: reads it via link" grep -qx "Host local" "$HOME/.ssh/config"

fresh_home; ssh_settings
mkdir -p "$HOME/.ssh"; echo "Host local" > "$HOME/.ssh/config"
printf 'y\nn\n' | run_step ssh
check "local only, keep: backed up"         grep -qx "Host local" "$HOME"/.ssh/config.ensconce-*
check "local only, keep: linked"            [ -L "$HOME/.ssh/config" ]
check "local only, keep: link waits for sync" [ ! -e "$HOME/.ssh/config" ]
check "local only, keep: says so"           out_has 'once Nextcloud has synced'

fresh_home; ssh_settings; : > "$WORK/cfg/nextcloud/folders.list"
run_step ssh < /dev/null
check "unsynced folder: warns"              out_has 'is in neither'

fresh_home; setting SSH_SYNCED_DIR .ssh/.sshsynched; setting SSH_CONTROL_DIR .ssh/.sshsynched/cm
echo ".ssh/.sshsynched|/ssh" > "$WORK/cfg/nextcloud/folders.list"
run_step ssh < /dev/null
check "control dir in synced: warns"        out_has 'cannot sync sockets'

fresh_home; ssh_settings
export FAKE_MANAGER=0
run_step ssh < /dev/null
unset FAKE_MANAGER
# Without a manager the stub cannot say whether gcr is installed; the step
# then looks for the unit file itself, which this host may or may not have
check "no manager: still succeeds"          [ "$rc" = 0 ]
check "no manager: no set-environment"      bash -c "! grep -q set-environment '$CALLS'"

fresh_home; ssh_settings
run_step ssh < /dev/null
: > "$WORK/cfg/settings.sh"; setting SSH_AGENT gnome
run_step ssh < /dev/null
check "gnome: succeeds"                     [ "$rc" = 0 ]
check "gnome: env file removed"             [ ! -e "$HOME/.config/environment.d/90-ensconce-ssh-agent.conf" ]
check "gnome: unmasked"                     calls_has "systemctl --user unmask gcr-ssh-agent.socket"
check "gnome: mask gone"                    [ ! -L "$HOME/.config/systemd/user/gcr-ssh-agent.socket" ]
check "gnome: socket started again"         calls_has "systemctl --user start gcr-ssh-agent.socket"

fresh_home; ssh_settings
DRY=true run_step ssh < /dev/null
check "dry run: succeeds"                   [ "$rc" = 0 ]
check "dry run: ~/.ssh untouched"           [ ! -e "$HOME/.ssh" ]
check "dry run: nothing masked"             [ ! -e "$HOME/.config/systemd/user/gcr-ssh-agent.socket" ]
check "dry run: no env file"                [ ! -e "$HOME/.config/environment.d/90-ensconce-ssh-agent.conf" ]

fresh_home; setting SSH_AGENT bogus
run_step ssh < /dev/null
check "unknown SSH_AGENT: fails"            [ "$rc" = 1 ]

fresh_home
run_step ssh < /dev/null
check "no settings: skipped"                out_has 'No SSH settings'

echo "== kiwi step"

kiwi_apps() { printf '%s\n' "# comment" ensconce "syncman   # inline" kiwi-fox > "$WORK/cfg/kiwi-apps.list"; }

fresh_home; kiwi_apps
run_step kiwi < /dev/null
check "no kiwi, no KIWI_INSTALL: skipped"   [ "$rc" = 0 ]
check "no kiwi, no KIWI_INSTALL: says why"  out_has 'KIWI_INSTALL is empty'
check "no kiwi, no KIWI_INSTALL: no fetch"  bash -c "! grep -q '^curl' '$CALLS' 2>/dev/null"

for mode_args in "minimal|get-kiwi --minimal" "manual|get-kiwi --with-system=manual" "recommended|get-kiwi "; do
    m="${mode_args%%|*}" want="${mode_args#*|}"
    fresh_home; kiwi_apps; setting KIWI_INSTALL "$m"
    run_step kiwi < /dev/null
    check "KIWI_INSTALL=$m: succeeds"       [ "$rc" = 0 ]
    check "KIWI_INSTALL=$m: get-kiwi args"  calls_has "$want"
    check "KIWI_INSTALL=$m: only missing apps" calls_has "kiwi install syncman"
done

fresh_home; kiwi_apps; setting KIWI_INSTALL minimal
mkdir -p "$HOME/.local/bin"; cp "$KIWI_STUB" "$HOME/.local/bin/kiwi"
printf '%s\n' ensconce kiwi-fox > "$WORK/cfg/kiwi-apps.list"
run_step kiwi < /dev/null
check "kiwi present: not re-bootstrapped"   bash -c "! grep -q '^get-kiwi' '$CALLS'"
check "all installed: nothing to install"   bash -c "! grep -q '^kiwi install' '$CALLS'"

fresh_home; kiwi_apps; setting KIWI_INSTALL minimal
run_step kiwi <<< "n"
check "bootstrap declined: no fetch"        bash -c "! grep -q '^curl' '$CALLS' 2>/dev/null"
check "bootstrap declined: not a failure"   [ "$rc" = 0 ]

fresh_home; kiwi_apps; setting KIWI_INSTALL minimal
DRY=true run_step kiwi < /dev/null
check "dry run: no fetch"                   bash -c "! grep -q '^curl' '$CALLS' 2>/dev/null"
check "dry run: shows the bootstrap"        out_has "Would run: curl -fsSL"
check "dry run: shows the apps"             out_has "Would run: kiwi install ensconce syncman kiwi-fox"

fresh_home; setting KIWI_INSTALL sometimes
run_step kiwi < /dev/null
check "unknown KIWI_INSTALL: fails"         [ "$rc" = 1 ]

echo "== sysctl step"

fresh_home
run_step sysctl < /dev/null
check "no drop-ins: skipped"                out_has 'No sysctl drop-ins'

fresh_home; mkdir -p "$WORK/cfg/sysctl.d"
cp "$ROOT/config.example/sysctl.d/99-dirty-writeback.conf" "$WORK/cfg/sysctl.d/"
run_step sysctl < /dev/null
check "drop-in: succeeds"                   [ "$rc" = 0 ]
check "drop-in: installed to /etc/sysctl.d" \
      calls_has "sudo install -m 0644 $WORK/cfg/sysctl.d/99-dirty-writeback.conf /etc/sysctl.d/99-dirty-writeback.conf"
check "drop-in: applied"                    calls_has "sudo sysctl --system"
check "drop-in: shows the settings"         out_has 'vm.dirty_bytes = 1073741824'

rm -f "$CALLS"; run_step sysctl <<< "n"
check "declined: not a failure"             [ "$rc" = 0 ]
check "declined: nothing installed"         [ ! -s "$CALLS" ]

rm -f "$CALLS"; DRY=true run_step sysctl < /dev/null
check "dry run: nothing installed"          [ ! -s "$CALLS" ]
check "dry run: shows the apply"            out_has 'Would run: sudo sysctl --system'

echo "== export"

fresh_home; ssh_settings
run_step ssh < /dev/null
printf '%s\n' "Host *" "    ControlMaster auto" "    ControlPath ~/.ssh/control_sockets/%r@%h:%p" \
    > "$HOME/.ssh/.sshsynched/config"
mkdir -p "$HOME/.local/bin"; cp "$KIWI_STUB" "$HOME/.local/bin/kiwi"
run_export _export_ssh _export_kiwi _export_settings
S="$WORK/export/settings.sh"
check "export: settings.sh parses"          bash -n "$S"
check "export: SSH_SYNCED_DIR"              grep -qx 'SSH_SYNCED_DIR=".ssh/.sshsynched"' "$S"
check "export: SSH_CONTROL_DIR from ControlPath" grep -qx 'SSH_CONTROL_DIR=".ssh/control_sockets"' "$S"
check "export: SSH_AGENT"                   grep -q '^SSH_AGENT="bitwarden"' "$S"
# /usr/local/bin/kiwi decides recommended/manual; this host has neither
check "export: KIWI_INSTALL"                grep -qE '^KIWI_INSTALL="(minimal|manual|recommended)"' "$S"
L="$WORK/export/kiwi-apps.list"
check "export: installed apps listed"       grep -qx ensconce "$L"
check "export: pin kept as a comment"       grep -q '^kiwi-fox .*pinned to v0.1.3' "$L"
check "export: not-installed left out"      bash -c "! grep -q '^syncman' '$L'"
check "export: kiwi-updater left out"       bash -c "! grep -q '^kiwi-updater' '$L'"

fresh_home
printf '%s\n' "Host a" "  ControlPath=none" "Host b" "  controlpath /run/user/1000/cm-%C" > "$WORK/cfg/sshconf"
mkdir -p "$HOME/.ssh"; cp "$WORK/cfg/sshconf" "$HOME/.ssh/config"
run_export _export_ssh _export_settings
check "export: none skipped, absolute kept" grep -qx 'SSH_CONTROL_DIR="/run/user/1000"' "$WORK/export/settings.sh"
check "export: plain config is not synced"  grep -qx 'SSH_SYNCED_DIR=""' "$WORK/export/settings.sh"

fresh_home
mkdir -p "$HOME/.ssh"; printf '%s\n' "Host *" "	ControlPath %d/.ssh/cm/%C" > "$HOME/.ssh/config"
run_export _export_ssh _export_settings
check "export: %d in ControlPath is home"   grep -qx 'SSH_CONTROL_DIR=".ssh/cm"' "$WORK/export/settings.sh"

echo
if [[ $fails -gt 0 ]]; then
    echo "$fails check(s) failed"
    exit 1
fi
echo "all checks passed"
