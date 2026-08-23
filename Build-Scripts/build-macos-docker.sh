#!/bin/bash
# macOS x64 cross-compile (out-of-tree).
#   build/macos/  +  depends/x86_64-apple-darwin*/  +  out-macos/
#
# SDKs and built depends sync from CodeRepo/shared/depends-preseed.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
mapfile -t PRESEED_MOUNT < <(docker_build_mount_args "$ROOT")

PLATFORM=macos
HOST_TRIPLET="${HOST_TRIPLET:-x86_64-apple-darwin16}"
BUILD_DIR="build/${PLATFORM}"
OUT_DIR="out-${PLATFORM}"
OSX_SDK="${OSX_SDK:-Xcode-11.3.1-11C505-extracted-SDK-with-libcxx-headers}"

docker run --rm \
  -e OSX_SDK="$OSX_SDK" \
  -v "$ROOT:/build" \
  "${PRESEED_MOUNT[@]}" \
  -w /build \
  ubuntu:22.04 \
  bash -c "
    set -e
    source Build-Scripts/build-common.sh
    build_common_root

    if [ ! -d \"\${SHARED_DEPENDS_PRESEED}/SDKs/\${OSX_SDK}\" ]; then
      echo \"ERROR: macOS SDK not found at \${SHARED_DEPENDS_PRESEED}/SDKs/\${OSX_SDK}\"
      echo \"Run: shared/depends-preseed/ensure-sdks.sh\"
      exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y build-essential automake libtool pkg-config python3 \
      curl git bison ca-certificates clang lld zip unzip gcc-9 g++-9 \
      libcap-dev librsvg2-bin imagemagick libtinfo5

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100

    clean_root_configure_artifacts /build
    ensure_depends ${HOST_TRIPLET} /build \"SDK_PATH=\${SHARED_DEPENDS_PRESEED}/SDKs\"
    ensure_autogen /build
    configure_platform_build ${BUILD_DIR} ${HOST_TRIPLET} '--disable-shared --enable-static ac_cv_search_clock_gettime=no' /build
    ensure_secp256k1_gen_context ${BUILD_DIR} /build
    platform_make ${BUILD_DIR} /build 4

    prepare_output_dirs /build ${OUT_DIR}
    STRIP=/build/depends/${HOST_TRIPLET}/native/bin/${HOST_TRIPLET}-strip
    for bin in vericoind vericoin-cli vericoin-tx vericoin-wallet; do
      \$STRIP -o /build/${OUT_DIR}/\${bin} /build/${BUILD_DIR}/src/\${bin}
    done
    \$STRIP -o /build/${OUT_DIR}/vericoin-qt /build/${BUILD_DIR}/src/qt/vericoin-qt

    export ROOT=/build
    export OTOOL=/build/depends/${HOST_TRIPLET}/native/bin/${HOST_TRIPLET}-otool
    source /build/Build-Scripts/verify-static-macos.sh
    verify_static_macos_binaries \
      /build/${OUT_DIR}/vericoind \
      /build/${OUT_DIR}/vericoin-cli \
      /build/${OUT_DIR}/vericoin-tx \
      /build/${OUT_DIR}/vericoin-wallet \
      /build/${OUT_DIR}/vericoin-qt

    cd /build/${BUILD_DIR}
    make deploy
    stage_macos_app_bundle /build/${BUILD_DIR} /build/${OUT_DIR} Vericoin.app
    stage_macos_dmg /build/${BUILD_DIR} /build/${OUT_DIR} Vericoin.dmg

    echo '=== macOS build complete ==='
    ls -la /build/${OUT_DIR}/
  "
