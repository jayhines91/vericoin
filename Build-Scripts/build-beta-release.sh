#!/bin/bash
# Beta release build: Linux x64 + Windows x64 with installers in beta/ only.
#
# Waits for shared depends preseed (Qt 5.15.14 + OpenSSL 1.1.1w on both hosts),
# then builds fresh out-of-tree binaries and packages installers.
#
# Output layout:
#   beta/
#     README.txt
#     linux64/          binaries + vericoin-*-beta-x86_64-pc-linux-gnu.tar.gz
#     windows/          binaries + release/ stripped + *-beta-win64-setup-unsigned.exe
#
# Usage:
#   ./Build-Scripts/build-beta-release.sh
#   SKIP_PRESEED_WAIT=1 ./Build-Scripts/build-beta-release.sh
#
# Do not run other Docker depends/build jobs in parallel with this script.
LOCK_FILE="${BETA_LOCK_FILE:-/tmp/vericoin-beta-build.lock}"
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh

BETA_DIR="${BETA_DIR:-beta}"
LINUX_BUILD_DIR="build/beta-linux64"
WINDOWS_BUILD_DIR="build/beta-windows"
LINUX_HOST="x86_64-pc-linux-gnu"
WINDOWS_HOST="x86_64-w64-mingw32"
JOBS="${JOBS:-4}"

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

  echo "=== Waiting for shared preseed (Qt 5.15.14 + OpenSSL 1.1.1w on linux64 and windows) ==="
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
      echo "  linux:  ${linux_qt}, ${linux_ssl}"
      echo "  windows: ${win_qt}, ${win_ssl}"
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
    mkdir -p "${ROOT}/${BETA_DIR}/linux64" "${ROOT}/${BETA_DIR}/windows/release"
}

verify_dev_helper_off() {
  if grep -q '^#define ENABLE_DEV_HELPER_WINDOW 1' "${ROOT}/src/util/devhelperconfig.h" 2>/dev/null; then
    echo "ERROR: beta release requires ENABLE_DEV_HELPER_WINDOW 0 in src/util/devhelperconfig.h" >&2
    exit 1
  fi
}

beta_build_cxxflags() {
  echo "-DENABLE_BETA_BUILD=1"
}

mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

build_linux64() {
  echo "=== Beta Linux x64 build ==="
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
      FORCE_DEPENDS_REBUILD=${FORCE_DEPENDS_REBUILD:-0}
      export CXXFLAGS=\"\${CXXFLAGS:-} $(beta_build_cxxflags)\"
      export CPPFLAGS=\"\${CPPFLAGS:-} $(beta_build_cxxflags)\"

      if [ \"\$FORCE_DEPENDS_REBUILD\" = \"1\" ]; then
        echo '=== FORCE_DEPENDS_REBUILD=1: cleaning linux depends ==='
        rm -rf /build/depends/\${LINUX_HOST} /build/depends/built/\${LINUX_HOST} \
          /build/depends/work/build/\${LINUX_HOST} /build/depends/work/staging/\${LINUX_HOST}
      else
        echo '=== Resuming linux depends build ==='
      fi

      clean_root_configure_artifacts /build
      cd /build/depends && make HOST=\${LINUX_HOST} -j\${JOBS}
      cd /build
      test -f /build/depends/\${LINUX_HOST}/lib/libQt5Core.a
      test -f /build/depends/\${LINUX_HOST}/plugins/platforms/libqxcb.a
      fix_qt_pkgconfig_versions /build \${LINUX_HOST}

      ensure_autogen /build
      rm -rf /build/${LINUX_BUILD_DIR}
      configure_platform_build ${LINUX_BUILD_DIR} \${LINUX_HOST} '' /build
      platform_make ${LINUX_BUILD_DIR} /build ${JOBS}

      strip -o /build/${BETA_DIR}/linux64/vericoind /build/${LINUX_BUILD_DIR}/src/vericoind
      strip -o /build/${BETA_DIR}/linux64/vericoin-cli /build/${LINUX_BUILD_DIR}/src/vericoin-cli
      strip -o /build/${BETA_DIR}/linux64/vericoin-tx /build/${LINUX_BUILD_DIR}/src/vericoin-tx
      strip -o /build/${BETA_DIR}/linux64/vericoin-wallet /build/${LINUX_BUILD_DIR}/src/vericoin-wallet
      strip -o /build/${BETA_DIR}/linux64/vericoin-qt /build/${LINUX_BUILD_DIR}/src/qt/vericoin-qt
      chmod 755 /build/${BETA_DIR}/linux64/*

      echo '=== Linux binary versions ==='
      strings /build/${BETA_DIR}/linux64/vericoin-qt | grep -E 'Qt 5\\.|OpenSSL| Beta' | head -8 || true
      ls -la /build/${BETA_DIR}/linux64/
    "
}

build_windows() {
  echo "=== Beta Windows x64 build ==="
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
      FORCE_DEPENDS_REBUILD=${FORCE_DEPENDS_REBUILD:-0}
      export CXXFLAGS=\"\${CXXFLAGS:-} $(beta_build_cxxflags)\"
      export CPPFLAGS=\"\${CPPFLAGS:-} $(beta_build_cxxflags)\"

      if [ \"\$FORCE_DEPENDS_REBUILD\" = \"1\" ]; then
        echo '=== FORCE_DEPENDS_REBUILD=1: refreshing windows depends from shared preseed ==='
        rm -rf /build/depends/\${WINDOWS_HOST}
      fi

      clean_root_configure_artifacts /build
      ensure_depends \${WINDOWS_HOST} /build \"RC=\$RC WINDRES=\$WINDRES\"
      test -f /build/depends/\${WINDOWS_HOST}/lib/libQt5Core.a
      test -f /build/depends/\${WINDOWS_HOST}/plugins/platforms/libqwindows.a
      fix_qt_pkgconfig_versions /build \${WINDOWS_HOST}

      ensure_autogen /build
      rm -rf /build/${WINDOWS_BUILD_DIR}
      configure_platform_build ${WINDOWS_BUILD_DIR} \${WINDOWS_HOST} \
        '--disable-shared --enable-static ac_cv_search_clock_gettime=no' /build
      ensure_secp256k1_gen_context ${WINDOWS_BUILD_DIR} /build
      platform_make ${WINDOWS_BUILD_DIR} /build ${JOBS}

      mkdir -p /build/${BETA_DIR}/windows /build/${BETA_DIR}/windows/release
      cp -f /build/${WINDOWS_BUILD_DIR}/src/*.exe /build/${BETA_DIR}/windows/
      cp -f /build/${WINDOWS_BUILD_DIR}/src/qt/*.exe /build/${BETA_DIR}/windows/

      STRIP=x86_64-w64-mingw32-strip
      for bin in vericoind vericoin-cli vericoin-tx vericoin-wallet; do
        \$STRIP -o /build/${BETA_DIR}/windows/release/\${bin}.exe /build/${BETA_DIR}/windows/\${bin}.exe
      done
      \$STRIP -o /build/${BETA_DIR}/windows/release/vericoin-qt.exe /build/${BETA_DIR}/windows/vericoin-qt.exe

      echo '=== Windows depends Qt (from synced preseed) ==='
      grep QT_VERSION_STR /build/depends/${WINDOWS_HOST}/include/QtCore/qconfig.h || true
      echo '=== Beta branding in stripped vericoin-qt.exe ==='
      strings /build/${BETA_DIR}/windows/release/vericoin-qt.exe | grep -E ' Beta|2\\.2\\.5' | head -5 || true

      chmod +x /build/Build-Scripts/package-beta-windows-installer.sh
      RELEASE_DIR=/build/${BETA_DIR}/windows/release \
        OUT_DIR=/build/${BETA_DIR}/windows \
        /build/Build-Scripts/package-beta-windows-installer.sh /build

      ls -la /build/${BETA_DIR}/windows/ /build/${BETA_DIR}/windows/release/
    "
}

package_linux_tarball() {
  chmod +x "${ROOT}/Build-Scripts/package-beta-linux-tarball.sh"
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
Vericoin Beta Release Build
===========================
Version: ${version}
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Contents
--------
linux64/
  vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet
  vericoin-${version}-beta-x86_64-pc-linux-gnu.tar.gz  (installer)

windows/
  Unstripped .exe binaries
  release/  stripped binaries used by the installer
  Vericoin-${version}-beta-win64-setup-unsigned.exe  (installer)

Dependency versions (from preseed)
----------------------------------
Linux Qt:   ${qt_linux}
Windows Qt: ${qt_win}
OpenSSL:    1.1.1w

Changes in this beta
--------------------
- Qt upgraded to 5.15.14
- OpenSSL upgraded to 1.1.1w
- Wallet startup deadlock fixes (lock order, postInitProcess timing)
- Bootstrap pindexLast assert fix during sync pause
- Bootstrap download progress throttling + 1 MB write buffer
- Splash/window title show "Beta" for identification
- About dialog: copyright 2009-2026, veribase source line removed

Build script: Build-Scripts/build-beta-release.sh
EOF
}

main() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "ERROR: another beta build is running (lock: $LOCK_FILE)" >&2
    exit 1
  fi

  verify_dev_helper_off
  wait_for_preseed
  prepare_beta_tree

  if [ "${SKIP_LINUX_BUILD:-0}" != "1" ]; then
    build_linux64
    package_linux_tarball
  else
    echo "=== SKIP_LINUX_BUILD=1: keeping existing beta/linux64/ ==="
  fi

  build_windows
  write_beta_readme

  echo ""
  echo "=== Beta release build complete ==="
  echo "Output: ${ROOT}/${BETA_DIR}/"
  find "${ROOT}/${BETA_DIR}" -maxdepth 3 -type f \( -name '*.exe' -o -name 'vericoin-*' -o -name '*.tar.gz' -o -name 'README.txt' \) \
    | sort | xargs ls -lh 2>/dev/null || true
}

main "$@"
