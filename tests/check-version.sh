#!/usr/bin/env bash
# tests/check-version.sh — the release gate, run by .github/workflows/release.yml
# before it tags, and in CI.
#
# The version lives in two places; keep them equal. ensconce.sh's
# ENSCONCE_VERSION is what the banner and --help print, kiwi.manifest's
# VERSION is what kiwi shows and what the release tag is made from.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

script="$(sed -n 's/^ENSCONCE_VERSION="\(.*\)"$/\1/p' ensconce.sh | head -1)"
man="$(sed -n 's/^VERSION=//p' kiwi.manifest | head -1)"

[[ -n $script ]] || { echo "check-version: no ENSCONCE_VERSION in ensconce.sh" >&2; exit 1; }
[[ -n $man ]]    || { echo "check-version: no VERSION in kiwi.manifest" >&2; exit 1; }
if [[ $script != "$man" ]]; then
    echo "check-version: ensconce.sh says $script, kiwi.manifest says $man" >&2
    exit 1
fi
echo "check-version: ok ($man)"
