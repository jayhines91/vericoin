#!/bin/bash
# Beta Developer Edition build: Linux x64 + Windows x64 in beta-dev/ only.
#
# Requires ENABLE_DEV_HELPER_WINDOW 1 in src/util/devhelperconfig.h
# Compiles with ENABLE_BETA_BUILD=1 and --enable-debug
#
# Output layout:
#   beta-dev/
#     README.txt
#     linux64/          unstripped binaries + vericoin-*-beta-dev-*.tar.gz
#     windows/          unstripped .exe + *-beta-DeveloperEdition-win64-setup-unsigned.exe
#
# Usage:
#   ./Build-Scripts/build-beta-dev-release.sh
#   SKIP_PRESEED_WAIT=1 ./Build-Scripts/build-beta-dev-release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh

BETA_DIR="${BETA_DIR:-beta-dev}"
LINUX_BUILD_DIR="build/beta-dev-linux64"
WINDOWS_BUILD_DIR="build/beta-dev-windows"
LINUX_HOST="x86_64-pc-linux-gnu"
WINDOWS_HOST="x86_64-w64-mingw32"
JOBS="${JOBS:-4}"
LOCK_FILE="${BETA_DEV_LOCK_FILE:-/tmp/vericoin-beta-dev-build.lock}"

read_version_from_configure() {
  local cfg="${ROOT}/configure.ac"
  local major minor revision build
  major=$(sed -n 's/^define(_CLIENT_VERSION_MAJOR, //p' "$cfg" | tr -d ' )')
  minor=$(sed -n 's/^define(_CLIENT_VERSION_MINOR, //p' "$cfg" | tr -d ' )')
  revision=$(sed -n 's/^define(_CLIENT_VERSION_REVISION, //p' "$cfg" | tr -d ' )')
  build=$(sed -n 's/^define(_CLIENT_VERSION_BUILD, //p' "$cfg" | tr -d ' )')
  if [ -n "$build" ] && [ "$build" != "0" ]; then
    echo "${major}.${minor}.${revision}.${build}"
  else
    echo "${major}.${minor}.${revision}"
  fi
}

wait_for_preseed() {
  if [ "${SKIP_PRESEED_WAIT:-0}" = "1" ]; then
    echo "=== SKIP_PRESEED_WAIT=1: skipping preseed poll ==="
    return 0
  fi

  source_shared_preseed_helpers "$ROOT" || exit 1
  local family shared_root
  family="$(detect_project_family "$ROOT")"
  shared_root="$(shared_built_depends_dir "$family" "$LINUX_HOST")"
  shared_root="${shared_root%/x86_64-pc-linux-gnu}"

  echo "=== Waiting for shared preseed (Qt 5.15.14 + OpenSSL 1.1.1w) ==="
  local waited=0
  while true; do
    local linux_qt linux_ssl win_qt win_ssl
    linux_qt=$(grep -o 'QT_VERSION_STR "[^"]*"' \
      "${shared_root}/${LINUX_HOST}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
    linux_ssl=$(grep -o 'OpenSSL 1\.1\.1[^"]*' \
      "${shared_root}/${LINUX_HOST}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)
    win_qt=$(grep -o 'QT_VERSION_STR "[^"]*"' \
      "${shared_root}/${WINDOWS_HOST}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
    win_ssl=$(grep -o 'OpenSSL 1\.1\.1[^"]*' \
      "${shared_root}/${WINDOWS_HOST}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)

    if [[ "$linux_qt" == *"5.15.14"* && "$linux_ssl" == *"1.1.1w"* \
          && "$win_qt" == *"5.15.14"* && "$win_ssl" == *"1.1.1w"* ]]; then
      echo "=== Preseed ready (${waited}s waited) ==="
      return 0
    fi

    if [ "$((waited % 300))" -eq 0 ]; then
      echo "[${waited}s] linux: ${linux_qt:-missing} / ${linux_ssl:-missing}"
      echo "       windows: ${win_qt:-missing} / ${win_ssl:-missing}"
    fi
    sleep 30
    waited=$((waited + 30))
  done
}

prepare_beta_tree() {
  echo "=== Preparing ${BETA_DIR}/ output tree ==="
  docker run --rm -v "${ROOT}:/build" ubuntu:22.04 \
    rm -rf "/build/${LINUX_BUILD_DIR}" "/build/${WINDOWS_BUILD_DIR}"
  if [ "${SKIP_LINUX_BUILD:-0}" != "1" ]; then
    docker run --rm -v "${ROOT}:/build" ubuntu:22.04 \
      rm -rf "/build/${BETA_DIR}/linux64"
  fi
  mkdir -p "${ROOT}/${BETA_DIR}/linux64" "${ROOT}/${BETA_DIR}/windows"
}

beta_build_cxxflags() {
  echo "-DENABLE_BETA_BUILD=1"
}

beta_configure_extra() {
  echo '--disable-shared --enable-static --enable-debug ac_cv_search_clock_gettime=no'
}

mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

build_linux64() {
  echo "=== Beta Dev Linux x64 build ==="
  docker run --rm \
    -e FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}" \
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
      apt-get install -y build-essential automake libtool pkg-config python3 python3-dev \
        python3-setuptools patch curl git bison ca-certificates gcc-9 g++-9 cmake file \
        xutils-dev x11proto-dev libx11-dev libxcb1-dev libxcb-util-dev \
        libxcb-util0-dev libxkbcommon-dev libxcb-render0-dev libxcb-shm0-dev \
        libxcb-xfixes0-dev libxcb-sync-dev libxcb-randr0-dev libxcb-shape0-dev \
        libxcb-xinerama0-dev libfontconfig1-dev libfreetype6-dev

      update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
      update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100

      LINUX_HOST=${LINUX_HOST}
      JOBS=${JOBS}
      export CXXFLAGS=\"\${CXXFLAGS:-} $(beta_build_cxxflags)\"
      export CPPFLAGS=\"\${CPPFLAGS:-} $(beta_build_cxxflags)\"

      clean_root_configure_artifacts /build
      cd /build/depends && make HOST=\${LINUX_HOST} -j\${JOBS}
      cd /build
      fix_qt_pkgconfig_versions /build \${LINUX_HOST}

      ensure_autogen /build
      rm -rf /build/${LINUX_BUILD_DIR}
      configure_platform_build ${LINUX_BUILD_DIR} \${LINUX_HOST} '$(beta_configure_extra)' /build
      platform_make ${LINUX_BUILD_DIR} /build ${JOBS}

      cp -f /build/${LINUX_BUILD_DIR}/src/vericoind /build/${BETA_DIR}/linux64/
      cp -f /build/${LINUX_BUILD_DIR}/src/vericoin-cli /build/${BETA_DIR}/linux64/
      cp -f /build/${LINUX_BUILD_DIR}/src/vericoin-tx /build/${BETA_DIR}/linux64/
      cp -f /build/${LINUX_BUILD_DIR}/src/vericoin-wallet /build/${BETA_DIR}/linux64/
      cp -f /build/${LINUX_BUILD_DIR}/src/qt/vericoin-qt /build/${BETA_DIR}/linux64/
      chmod 755 /build/${BETA_DIR}/linux64/*

      strings /build/${BETA_DIR}/linux64/vericoin-qt | grep -E ' Beta|Dev Edition|Qt 5\\.' | head -8 || true
      ls -la /build/${BETA_DIR}/linux64/
    "
}

build_windows() {
  echo "=== Beta Dev Windows x64 build ==="
  docker run --rm \
    -e FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}" \
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
      apt-get install -y build-essential automake libtool pkg-config python3 python3-dev \
        python3-setuptools patch g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
        curl zip unzip gcc-9 g++-9 nsis git cmake file

      update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
      update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100
      update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
      update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

      export RC=\${WINDOWS_HOST}-windres WINDRES=\${WINDOWS_HOST}-windres
      patch_curl_mk_for_windows_cross /build
      patch_time_cpp_for_windows_cross /build

      WINDOWS_HOST=${WINDOWS_HOST}
      JOBS=${JOBS}
      export CXXFLAGS=\"\${CXXFLAGS:-} $(beta_build_cxxflags)\"
      export CPPFLAGS=\"\${CPPFLAGS:-} $(beta_build_cxxflags)\"

      clean_root_configure_artifacts /build
      ensure_depends \${WINDOWS_HOST} /build \"RC=\$RC WINDRES=\$WINDRES\"
      fix_qt_pkgconfig_versions /build \${WINDOWS_HOST}

      ensure_autogen /build
      rm -rf /build/${WINDOWS_BUILD_DIR}
      configure_platform_build ${WINDOWS_BUILD_DIR} \${WINDOWS_HOST} '$(beta_configure_extra)' /build
      ensure_secp256k1_gen_context ${WINDOWS_BUILD_DIR} /build
      platform_make ${WINDOWS_BUILD_DIR} /build ${JOBS}

      mkdir -p /build/${BETA_DIR}/windows
      cp -f /build/${WINDOWS_BUILD_DIR}/src/*.exe /build/${BETA_DIR}/windows/
      cp -f /build/${WINDOWS_BUILD_DIR}/src/qt/*.exe /build/${BETA_DIR}/windows/

      strings /build/${BETA_DIR}/windows/vericoin-qt.exe | grep -E ' Beta|Dev Edition|2\\.1\\.' | head -8 || true

      chmod +x /build/Build-Scripts/package-beta-dev-windows-installer.sh
      BINARY_DIR=/build/${BETA_DIR}/windows \
        OUT_DIR=/build/${BETA_DIR}/windows \
        /build/Build-Scripts/package-beta-dev-windows-installer.sh /build

      ls -la /build/${BETA_DIR}/windows/
    "
}

package_linux_tarball() {
  chmod +x "${ROOT}/Build-Scripts/package-beta-linux-tarball.sh"
  BETA_DIST_TAG=beta-dev \
    BINARY_DIR="${ROOT}/${BETA_DIR}/linux64" \
    OUT_DIR="${ROOT}/${BETA_DIR}/linux64" \
    "${ROOT}/Build-Scripts/package-beta-linux-tarball.sh" "$ROOT"
}

write_beta_readme() {
  local version qt_linux qt_win
  version="$(read_version_from_configure)"
  qt_linux=$(grep -o 'QT_VERSION_STR "[^"]*"' \
    "${ROOT}/depends/${LINUX_HOST}/include/QtCore/qconfig.h" 2>/dev/null || echo "unknown")
  qt_win=$(grep -o 'QT_VERSION_STR "[^"]*"' \
    "${ROOT}/depends/${WINDOWS_HOST}/include/QtCore/qconfig.h" 2>/dev/null || echo "unknown")

  cat > "${ROOT}/${BETA_DIR}/README.txt" <<EOF
Vericoin Beta Developer Edition Build
=====================================
Version: ${version}
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Contents
--------
linux64/
  vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet (unstripped, --enable-debug)
  vericoin-${version}-beta-dev-x86_64-pc-linux-gnu.tar.gz

windows/
  Unstripped .exe binaries (debug symbols)
  Vericoin-${version}-beta-DeveloperEdition-win64-setup-unsigned.exe

Flags
-----
ENABLE_DEV_HELPER_WINDOW=1  (dev trace window, activity log)
ENABLE_BETA_BUILD=1       (Beta splash/title)
--enable-debug            (DEBUG_LOCKORDER)

Install: Program Files\\Vericoin Developer Edition
Default dev-tools password: VeriDev225!

Dependency versions (from preseed)
----------------------------------
Linux Qt:   ${qt_linux}
Windows Qt: ${qt_win}
OpenSSL:    1.1.1w

Build script: Build-Scripts/build-beta-dev-release.sh
EOF
}

main() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "ERROR: another beta dev build is running (lock: $LOCK_FILE)" >&2
    exit 1
  fi

  require_dev_helper_enabled "$ROOT"
  wait_for_preseed
  prepare_beta_tree

  if [ "${SKIP_LINUX_BUILD:-0}" != "1" ]; then
    build_linux64
    package_linux_tarball
  else
    echo "=== SKIP_LINUX_BUILD=1: keeping existing beta-dev/linux64/ ==="
  fi

  build_windows
  write_beta_readme

  echo ""
  echo "=== Beta dev release build complete ==="
  echo "Output: ${ROOT}/${BETA_DIR}/"
  find "${ROOT}/${BETA_DIR}" -maxdepth 3 -type f \( -name '*.exe' -o -name 'vericoin-*' -o -name '*.tar.gz' -o -name 'README.txt' \) \
    | sort | xargs ls -lh 2>/dev/null || true
}

main "$@"
