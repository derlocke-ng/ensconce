#!/usr/bin/env bash
# tests/check-version.sh — the release gate, run by .github/workflows/release.yml
# before it tags, and in CI.
#
# The version is written down in four places; keep them equal. ensconce.sh's
# ENSCONCE_VERSION is what the banner and --help print, the app's __version__
# what its About says, the newest CHANGELOG.md section what the release notes
# are made from, and kiwi.manifest's VERSION is what kiwi shows and what the
# release tag is made from. Also: the scripts are executable in git.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

rc=0
bad() { echo "check-version: $*" >&2; rc=1; }

man="$(sed -n 's/^VERSION=//p' kiwi.manifest | head -1)"
[[ -n $man ]] || { echo "check-version: no VERSION in kiwi.manifest" >&2; exit 1; }

script="$(sed -n 's/^ENSCONCE_VERSION="\(.*\)"$/\1/p' ensconce.sh | head -1)"
app="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' src/ensconce/__init__.py | head -1)"
log="$(grep -m1 -oE '^## [0-9]+(\.[0-9]+)*' CHANGELOG.md | cut -c4-)"
[[ $script == "$man" ]] || bad "ensconce.sh says ${script:-nothing}, kiwi.manifest says $man"
[[ $app == "$man" ]]    || bad "src/ensconce/__init__.py says ${app:-nothing}, kiwi.manifest says $man"
[[ $log == "$man" ]]    || bad "the newest CHANGELOG.md section is ${log:-missing}, kiwi.manifest says $man"

for f in ensconce.sh install.sh dconf-backup.sh bin/* tests/*.sh tools/*.sh; do
    mode="$(git ls-files -s -- "$f" | cut -d' ' -f1)"
    [[ -z $mode || $mode == 100755 ]] || bad "$f is not executable in git (git update-index --chmod=+x $f)"
done

(( rc )) || echo "check-version: ok ($man)"
exit $rc
