#!/bin/bash
# Linux ARM64 cross-compile (out-of-tree).
#   build/linuxarm/  +  depends/aarch64-linux-gnu/  +  out-linuxarm/
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

PLATFORM=linuxarm
HOST_TRIPLET=aarch64-linux-gnu
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
      curl git bison ca-certificates gcc-9 g++-9 \
      g++-aarch64-linux-gnu binutils-aarch64-linux-gnu

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100

    clean_root_configure_artifacts /build
    ensure_depends ${HOST_TRIPLET} /build
    ensure_autogen /build
    rm -rf ${BUILD_DIR}
    configure_platform_build ${BUILD_DIR} ${HOST_TRIPLET} '--disable-shared --enable-static --disable-asm' /build
    ensure_secp256k1_gen_context ${BUILD_DIR} /build
    platform_make ${BUILD_DIR} /build 4

    prepare_output_dirs /build ${OUT_DIR}
    cp -f ${BUILD_DIR}/src/vericoind ${BUILD_DIR}/src/vericoin-cli ${BUILD_DIR}/src/vericoin-tx \
          ${BUILD_DIR}/src/vericoin-wallet ${BUILD_DIR}/src/qt/vericoin-qt /build/${OUT_DIR}/

    echo '=== Linux ARM64 build complete ==='
    ls -la /build/${OUT_DIR}/
  "
