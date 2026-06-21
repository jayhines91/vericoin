#!/bin/bash
# Windows beta only — skips Linux rebuild. Requires beta/linux64/ from a prior run.
set -euo pipefail
cd "$(dirname "$0")/.."
export SKIP_PRESEED_WAIT=1
export SKIP_LINUX_BUILD=1
export FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}"
exec bash Build-Scripts/build-beta-release.sh "$@"
