#!/bin/bash
# Flush local Vericoin depends caches (intermediate + installed prefixes).
# Does not touch shared/depends-preseed until you run flush-family-cache.sh there.
#
# Usage:
#   ./Build-Scripts/flush-depends-cache.sh
#   ./Build-Scripts/flush-depends-cache.sh x86_64-pc-linux-gnu x86_64-w64-mingw32
#   ./Build-Scripts/flush-depends-cache.sh --dry-run
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DEPENDS="${ROOT}/depends"

DRY_RUN=0
HOSTS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) HOSTS+=("$arg") ;;
    esac
done

if [ ${#HOSTS[@]} -eq 0 ]; then
    HOSTS=(
        x86_64-pc-linux-gnu
        aarch64-linux-gnu
        x86_64-apple-darwin16
        x86_64-w64-mingw32
    )
fi

remove_path() {
    local path="$1"
    if [ -e "$path" ]; then
        if [ "$DRY_RUN" = 1 ]; then
            echo "  would remove: ${path}"
        else
            echo "  removing: ${path}"
            if ! rm -rf "$path" 2>/dev/null; then
                echo "  ERROR: cannot remove ${path} (likely root-owned from a prior docker build)" >&2
                echo "  Run: docker run --rm -v \"${ROOT}:/build\" -w /build ubuntu:22.04 rm -rf \"${path#${ROOT}/}\"" >&2
                echo "  Or use: Build-Scripts/build-depends-preseed.sh --flush ..." >&2
                exit 1
            fi
        fi
    fi
}

echo "=== Flush local depends cache (${ROOT}) ==="

for sub in built work download; do
    remove_path "${DEPENDS}/${sub}"
done

for host in "${HOSTS[@]}"; do
    remove_path "${DEPENDS}/${host}"
done

echo "=== Done. Sources in depends/sources/ are kept. Run build-depends-preseed.sh next. ==="
