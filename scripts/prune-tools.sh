#!/usr/bin/env bash
#
# Deletes, after confirmation, OSS CAD Suite versions other than the one in tools.lock.
#
# Usage (normally through `make tools-prune`):
#   scripts/prune-tools.sh
#
# Optional environment variables:
#   TOOLS_ROOT  directory of the installs (default: .tools/ inside the repository)
#   KEEP        extra dates to keep, e.g. KEEP="2026-07-11 2026-04-02"
#   YES=1       do not ask for confirmation
#
# Only considers directories named exactly oss-cad-suite-YYYY-MM-DD and the
# temporary ones left by interrupted installs (.oss-cad-suite-YYYY-MM-DD.tmp.*).
# Nothing else in TOOLS_ROOT is touched.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools.lock
source "$REPO_ROOT/tools.lock"

TOOLS_ROOT="${TOOLS_ROOT:-$REPO_ROOT/.tools}"
KEEP="${KEEP:-}"
YES="${YES:-}"

DATE_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}'

info() { echo "[tools-prune] $*"; }
die() {
    echo "[tools-prune] ERROR: $*" >&2
    exit 1
}

[ -d "$TOOLS_ROOT" ] || { info "$TOOLS_ROOT does not exist; nothing to do."; exit 0; }

for d in $KEEP; do
    [[ "$d" =~ ^$DATE_RE$ ]] || die "KEEP contains '$d', which is not a YYYY-MM-DD date."
done

# Build the list of what may be deleted.
victims=()
for path in "$TOOLS_ROOT"/oss-cad-suite-* "$TOOLS_ROOT"/.oss-cad-suite-*; do
    [ -d "$path" ] || continue # also skips the literal pattern when nothing matches
    [ -L "$path" ] && continue # symbolic links are not our installs
    name="$(basename "$path")"

    if [[ "$name" =~ ^oss-cad-suite-($DATE_RE)$ ]]; then
        date="${BASH_REMATCH[1]}"
        [ "$date" = "$OSS_CAD_SUITE_DATE" ] && continue
        [[ " $KEEP " == *" $date "* ]] && continue
        victims+=("$path")
    elif [[ "$name" =~ ^\.oss-cad-suite-$DATE_RE\.tmp\.[A-Za-z0-9]+$ ]]; then
        victims+=("$path") # interrupted install
    fi
done

if [ "${#victims[@]}" -eq 0 ]; then
    info "nothing to delete (pinned: $OSS_CAD_SUITE_DATE${KEEP:+; kept: $KEEP})."
    exit 0
fi

info "version pinned in tools.lock: $OSS_CAD_SUITE_DATE${KEEP:+ (also kept: $KEEP)}"
info "will be deleted:"
du -sh -- "${victims[@]}"

if [ "$YES" != 1 ]; then
    read -r -p "Delete? [y/N] " answer
    case "$answer" in
    y | Y) ;;
    *)
        info "cancelled."
        exit 0
        ;;
    esac
fi

for path in "${victims[@]}"; do
    rm -rf -- "$path"
    info "deleted: $path"
done
