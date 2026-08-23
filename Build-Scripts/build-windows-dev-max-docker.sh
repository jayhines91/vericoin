#!/bin/bash
# Windows Developer Edition Max Trace — maximum verbosity debug build.
#
# Output (separate from out-windows-dev/):
#   out-windows-dev-max/vericoin-qt.exe (+ cli, daemon, wallet, tx)
#   out-windows-dev-max/Vericoin-<version>-DeveloperEditionMaxTrace-win64-setup-unsigned.exe
#
# Install dir on Windows: Program Files\Vericoin Developer Edition Max Trace
#
# Prerequisites: ENABLE_DEV_HELPER_WINDOW 1 in src/util/devhelperconfig.h
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
require_dev_helper_enabled "$ROOT"

mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

docker run --rm \
  -v "$ROOT:/build" \
  "${PRESEED_MOUNT[@]}" \
  -w /build \
  ubuntu:22.04 \
  bash -c "
    set -e
    source Build-Scripts/build-common.sh
    build_common_root
    run_windows_dev_max_compile_and_package /build
  "
