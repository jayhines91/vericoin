#!/bin/bash
# Build non-dev beta (beta/) then dev beta (beta-dev/).
#
# Toggles ENABLE_DEV_HELPER_WINDOW in src/util/devhelperconfig.h between builds.
# Leaves dev helper ON (1) after completion — restore to 0 manually for holder builds.
#
# Usage:
#   ./Build-Scripts/build-beta-all.sh
#   SKIP_PRESEED_WAIT=1 ./Build-Scripts/build-beta-all.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DEVCFG="${ROOT}/src/util/devhelperconfig.h"

set_dev_helper() {
  local val="$1"
  if grep -q '^#define ENABLE_DEV_HELPER_WINDOW' "$DEVCFG"; then
    sed -i "s/^#define ENABLE_DEV_HELPER_WINDOW .*/#define ENABLE_DEV_HELPER_WINDOW ${val}/" "$DEVCFG"
  else
    echo "ERROR: ENABLE_DEV_HELPER_WINDOW not found in ${DEVCFG}" >&2
    exit 1
  fi
  echo "=== ENABLE_DEV_HELPER_WINDOW=${val} ==="
}

chmod +x Build-Scripts/build-beta-release.sh \
  Build-Scripts/build-beta-dev-release.sh \
  Build-Scripts/package-beta-dev-windows-installer.sh

echo "=== [1/2] Non-dev beta (beta/) ==="
set_dev_helper 0
SKIP_PRESEED_WAIT="${SKIP_PRESEED_WAIT:-1}" \
  JOBS="${JOBS:-4}" \
  ./Build-Scripts/build-beta-release.sh

echo ""
echo "=== [2/2] Dev beta (beta-dev/) ==="
set_dev_helper 1
SKIP_PRESEED_WAIT="${SKIP_PRESEED_WAIT:-1}" \
  JOBS="${JOBS:-4}" \
  ./Build-Scripts/build-beta-dev-release.sh

echo ""
echo "=== Both beta builds complete ==="
echo "  Holder beta:  ${ROOT}/beta/"
echo "  Dev beta:     ${ROOT}/beta-dev/"
find "${ROOT}/beta" "${ROOT}/beta-dev" -maxdepth 3 -type f \
  \( -name '*setup*.exe' -o -name '*.tar.gz' -o -name 'README.txt' \) 2>/dev/null \
  | sort | xargs ls -lh 2>/dev/null || true
