#!/bin/bash
# Linux x64 native build (out-of-tree).
#   build/linux64/  +  depends/x86_64-pc-linux-gnu/  +  out-linux64/
# Does not touch windows/linuxarm/macos trees or their depends caches.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

PLATFORM=linux64
HOST_TRIPLET=x86_64-pc-linux-gnu
BUILD_DIR="build/${PLATFORM}"
OUT_DIR="out-${PLATFORM}"

docker run --rm \
  -v "$ROOT:/build" \
  "${PRESEED_MOUNT[@]}" \
  -w /build \
  ubuntu:22.04 \
  bash -c "
    set -e
    source Build-Scripts/build-common.sh
    build_common_root

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y build-essential automake libtool pkg-config python3 \
      curl git bison ca-certificates gcc-9 g++-9

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100

    clean_root_configure_artifacts /build
    ensure_depends ${HOST_TRIPLET} /build
    ensure_autogen /build
    configure_platform_build ${BUILD_DIR} ${HOST_TRIPLET} '' /build
    platform_make ${BUILD_DIR} /build 4

    prepare_output_dirs /build ${OUT_DIR}
    cp -f /build/${BUILD_DIR}/src/vericoind /build/${BUILD_DIR}/src/vericoin-cli \
          /build/${BUILD_DIR}/src/vericoin-tx /build/${BUILD_DIR}/src/vericoin-wallet \
          /build/${BUILD_DIR}/src/qt/vericoin-qt /build/${OUT_DIR}/

    echo '=== Linux x64 build complete ==='
    ls -la /build/${OUT_DIR}/
  "
