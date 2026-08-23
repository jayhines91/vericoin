#!/bin/bash
# Canonical Windows Developer Edition recompile (debug machine).
#
# Prerequisites: ENABLE_DEV_HELPER_WINDOW 1 in src/util/devhelperconfig.h
#
# Produces:
#   out-windows-dev/vericoin-qt.exe (+ cli, daemon, wallet, tx)
#   out-windows-dev/Vericoin-<version>-DeveloperEdition-win64-setup-unsigned.exe
#
# Install dir on Windows: Program Files\Vericoin Developer Edition
# (separate from release — will not overwrite holder installs)
#
# Aliases: recompile-dev-windows.sh, build-windows-dev-installer-docker.sh
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
require_dev_helper_enabled "$ROOT"

mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

DEV_DOCKER_ENV=()
for var in WINDOWS_DEV_OUT_DIR WINDOWS_DEV_BUILD_DIR WINDOWS_DEV_RELEASE_DIR WINDOWS_DEV_CONFIGURE_EXTRA; do
  if [ -n "${!var:-}" ]; then
    DEV_DOCKER_ENV+=(-e "${var}=${!var}")
  fi
done

docker run --rm \
  -v "$ROOT:/build" \
  "${PRESEED_MOUNT[@]}" \
  "${DEV_DOCKER_ENV[@]}" \
  -w /build \
  ubuntu:22.04 \
  bash -c "
    set -e
    source Build-Scripts/build-common.sh
    build_common_root
    run_windows_dev_compile_and_package /build
  "
