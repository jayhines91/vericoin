#!/bin/bash
# Beta macOS x64 build (static depends) into beta/macos/.
#
# Requires shared macOS SDK in shared/depends-preseed/SDKs/.
#
# Usage:
#   ./Build-Scripts/build-beta-macos.sh
#   SKIP_PRESEED_WAIT=1 ./Build-Scripts/build-beta-macos.sh
#   FORCE_DEPENDS_REBUILD=1 ./Build-Scripts/build-beta-macos.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh

BETA_DIR="${BETA_DIR:-beta}"
MACOS_BUILD_DIR="build/beta-macos"
MACOS_HOST="${MACOS_HOST:-x86_64-apple-darwin16}"
JOBS="${JOBS:-4}"
OSX_SDK="${OSX_SDK:-Xcode-11.3.1-11C505-extracted-SDK-with-libcxx-headers}"
LOCK_FILE="${BETA_MACOS_LOCK_FILE:-/tmp/vericoin-beta-macos-build.lock}"

beta_build_cxxflags() {
  echo "-DENABLE_BETA_BUILD=1 -DENABLE_POST_CATCHUP_VALIDATION_BETA=1"
}

verify_dev_helper_off() {
  if grep -q '^#define ENABLE_DEV_HELPER_WINDOW 1' "${ROOT}/src/util/devhelperconfig.h" 2>/dev/null; then
    echo "ERROR: beta macOS build requires ENABLE_DEV_HELPER_WINDOW 0 in src/util/devhelperconfig.h" >&2
    exit 1
  fi
}

mapfile -t PRESEED_MOUNT < <(docker_build_mount_args "$ROOT")

build_macos() {
  echo "=== Beta macOS x64 build ==="
  docker run --rm \
    -e FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}" \
    -e SKIP_BETA_CLEAN="${SKIP_BETA_CLEAN:-0}" \
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
      apt-get install -y build-essential automake libtool pkg-config python3 python3-dev \
        python3-setuptools patch curl git bison ca-certificates clang lld zip unzip gcc-9 g++-9 \
        libcap-dev librsvg2-bin imagemagick libtiff-tools file ripgrep libtinfo5

      update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
      update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100

      MACOS_HOST=${MACOS_HOST}
      JOBS=${JOBS}
      FORCE_DEPENDS_REBUILD=${FORCE_DEPENDS_REBUILD:-0}
      export CXXFLAGS=\"\${CXXFLAGS:-} $(beta_build_cxxflags)\"
      export CPPFLAGS=\"\${CPPFLAGS:-} $(beta_build_cxxflags)\"

      if [ \"\$FORCE_DEPENDS_REBUILD\" = \"1\" ]; then
        echo '=== FORCE_DEPENDS_REBUILD=1: cleaning macOS depends ==='
        rm -rf /build/depends/\${MACOS_HOST} /build/depends/built/\${MACOS_HOST} \
          /build/depends/work/build/\${MACOS_HOST} /build/depends/work/staging/\${MACOS_HOST}
      fi

      clean_root_configure_artifacts /build
      ensure_depends \${MACOS_HOST} /build \"SDK_PATH=\${SHARED_DEPENDS_PRESEED}/SDKs\"
      test -f /build/depends/\${MACOS_HOST}/lib/libQt5Core.a
      test -f /build/depends/\${MACOS_HOST}/plugins/platforms/libqcocoa.a

      ensure_autogen /build
      if [ \"\${SKIP_BETA_CLEAN:-0}\" = \"1\" ]; then
        echo '=== SKIP_BETA_CLEAN=1: incremental make in ${MACOS_BUILD_DIR} ==='
      else
        rm -rf /build/${MACOS_BUILD_DIR}
      fi
      configure_platform_build ${MACOS_BUILD_DIR} \${MACOS_HOST} \
        '--disable-shared --enable-static ac_cv_search_clock_gettime=no' /build
      ensure_secp256k1_gen_context ${MACOS_BUILD_DIR} /build
      platform_make ${MACOS_BUILD_DIR} /build ${JOBS}

      mkdir -p /build/${BETA_DIR}/macos
      STRIP=/build/depends/\${MACOS_HOST}/native/bin/\${MACOS_HOST}-strip
      for bin in vericoind vericoin-cli vericoin-tx vericoin-wallet; do
        \$STRIP -o /build/${BETA_DIR}/macos/\${bin} /build/${MACOS_BUILD_DIR}/src/\${bin}
      done
      \$STRIP -o /build/${BETA_DIR}/macos/vericoin-qt /build/${MACOS_BUILD_DIR}/src/qt/vericoin-qt
      chmod 755 /build/${BETA_DIR}/macos/*

      export ROOT=/build
      export OTOOL=/build/depends/\${MACOS_HOST}/native/bin/\${MACOS_HOST}-otool
      source /build/Build-Scripts/verify-static-macos.sh
      verify_static_macos_binaries \
        /build/${BETA_DIR}/macos/vericoind \
        /build/${BETA_DIR}/macos/vericoin-cli \
        /build/${BETA_DIR}/macos/vericoin-tx \
        /build/${BETA_DIR}/macos/vericoin-wallet \
        /build/${BETA_DIR}/macos/vericoin-qt

      cd /build/${MACOS_BUILD_DIR}
      make deploy
      stage_macos_app_bundle /build/${MACOS_BUILD_DIR} /build/${BETA_DIR}/macos Vericoin.app
      stage_macos_dmg /build/${MACOS_BUILD_DIR} /build/${BETA_DIR}/macos Vericoin.dmg

      echo '=== macOS binary versions ==='
      strings /build/${BETA_DIR}/macos/vericoin-qt | grep -E 'Qt 5\\.|OpenSSL| Beta' | head -8 || true
      ls -la /build/${BETA_DIR}/macos/
    "
}

package_macos_tarball() {
  chmod +x "${ROOT}/Build-Scripts/package-beta-macos-tarball.sh"
  ROOT="$ROOT" BINARY_DIR="${ROOT}/${BETA_DIR}/macos" \
    OUT_DIR="${ROOT}/${BETA_DIR}/macos" \
    HOST_TRIPLET="$MACOS_HOST" \
    "${ROOT}/Build-Scripts/package-beta-macos-tarball.sh" "$ROOT"
}

main() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "ERROR: another beta macOS build is running (lock: $LOCK_FILE)" >&2
    exit 1
  fi

  verify_dev_helper_off
  verify_macos_preseed_ready "$ROOT" "$MACOS_HOST" "$OSX_SDK"
  mkdir -p "${ROOT}/${BETA_DIR}/macos"
  build_macos
  package_macos_tarball

  echo ""
  echo "=== Beta macOS build complete ==="
  echo "Output: ${ROOT}/${BETA_DIR}/macos/"
  ls -lh "${ROOT}/${BETA_DIR}/macos/" || true
}

main "$@"
