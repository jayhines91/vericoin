#!/bin/bash
# Windows beta only — skips Linux rebuild. Requires beta/linux64/ from a prior run.
#
# Defaults tuned for fast iteration:
#   SKIP_PRESEED_WAIT=1  — use mounted shared depends preseed (no poll)
#   SKIP_LINUX_BUILD=1   — Windows installer only
#   SKIP_BETA_CLEAN=1    — keep build/beta-windows/ for incremental make (~minutes not ~20min)
#
# Full clean rebuild (e.g. after configure.ac / depends / CXXFLAGS changes):
#   SKIP_BETA_CLEAN=0 ./Build-Scripts/build-beta-windows-only.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."
export SKIP_PRESEED_WAIT=1
export SKIP_LINUX_BUILD=1
export SKIP_BETA_CLEAN="${SKIP_BETA_CLEAN:-1}"
export FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}"
exec bash Build-Scripts/build-beta-release.sh "$@"
