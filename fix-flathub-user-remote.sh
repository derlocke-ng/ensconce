#!/usr/bin/env bash
# Repair hosts where flathub was added as a *user* remote on top of the
# system-wide one (preinstalled by Bluefin). Reinstalls user-installed apps
# from the system flathub remote, keeping user data (~/.var/app).
# Usage: fix-flathub-user-remote.sh [--dry-run]
set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }

if ! flatpak remotes --user --columns=name | grep -qx flathub; then
    echo "No user flathub remote found; nothing to do."
    exit 0
fi

if ! flatpak remotes --system --columns=name | grep -qx flathub; then
    run flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# User-installed apps that came from the user flathub remote
mapfile -t apps < <(flatpak list --user --app --columns=application,origin \
    | awk -F'\t' '$2=="flathub"{print $1}')

echo "Apps to reinstall: ${apps[*]:-(none)}"

for app in "${apps[@]}"; do
    # no --delete-data: keeps ~/.var/app/<app>
    run flatpak uninstall --user -y "$app"
done

# Remove leftover user runtimes from flathub
run flatpak uninstall --user -y --unused || true

run flatpak remote-delete --user flathub

for app in "${apps[@]}"; do
    run flatpak install --system -y flathub "$app"
done

echo "Done."
