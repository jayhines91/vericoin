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
#   SKIP_BETA_CLEAN=1 ./Build-Scripts/build-beta-release.sh   # incremental source rebuild
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
MACOS_BUILD_DIR="build/beta-macos"
LINUX_HOST="x86_64-pc-linux-gnu"
WINDOWS_HOST="x86_64-w64-mingw32"
MACOS_HOST="${MACOS_HOST:-x86_64-apple-darwin16}"
OSX_SDK="${OSX_SDK:-Xcode-11.3.1-11C505-extracted-SDK-with-libcxx-headers}"
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

  echo "=== Waiting for shared preseed (Qt 5.15.14 + OpenSSL 1.1.1w) ==="
  local need_macos=0
  if [ "${SKIP_MACOS_BUILD:-1}" != "1" ]; then
    need_macos=1
  fi
  local waited=0
  while true; do
    local linux_qt linux_ssl win_qt win_ssl mac_qt mac_ssl mac_ok=1
    linux_qt=$(grep -o 'QT_VERSION_STR "[^"]*"' \
      "${shared_root}/${LINUX_HOST}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
    linux_ssl=$(grep -o 'OpenSSL 1\.1\.1[^"]*' \
      "${shared_root}/${LINUX_HOST}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)
    win_qt=$(grep -o 'QT_VERSION_STR "[^"]*"' \
      "${shared_root}/${WINDOWS_HOST}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
    win_ssl=$(grep -o 'OpenSSL 1\.1\.1[^"]*' \
      "${shared_root}/${WINDOWS_HOST}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)
    if [ "$need_macos" = "1" ]; then
      mac_qt=$(grep -o 'QT_VERSION_STR "[^"]*"' \
        "${shared_root}/${MACOS_HOST}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
      mac_ssl=$(grep -o 'OpenSSL 1\.1\.1[^"]*' \
        "${shared_root}/${MACOS_HOST}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)
      if [[ "$mac_qt" != *"5.15.14"* || "$mac_ssl" != *"1.1.1w"* ]]; then
        mac_ok=0
      fi
    fi

    if [[ "$linux_qt" == *"5.15.14"* && "$linux_ssl" == *"1.1.1w"* \
          && "$win_qt" == *"5.15.14"* && "$win_ssl" == *"1.1.1w"* \
          && "$mac_ok" = "1" ]]; then
      echo "=== Preseed ready (${waited}s waited) ==="
      echo "  linux:   ${linux_qt}, ${linux_ssl}"
      echo "  windows: ${win_qt}, ${win_ssl}"
      if [ "$need_macos" = "1" ]; then
        echo "  macos:   ${mac_qt}, ${mac_ssl}"
      fi
      return 0
    fi

    if [ "$((waited % 300))" -eq 0 ]; then
      echo "[${waited}s] linux: ${linux_qt:-missing} / ${linux_ssl:-missing}"
      echo "       windows: ${win_qt:-missing} / ${win_ssl:-missing}"
      if [ "$need_macos" = "1" ]; then
        echo "       macos: ${mac_qt:-missing} / ${mac_ssl:-missing}"
      fi
    fi
    sleep 30
    waited=$((waited + 30))
  done
}

prepare_beta_tree() {
    echo "=== Preparing ${BETA_DIR}/ output tree ==="
    if [ "${SKIP_BETA_CLEAN:-0}" = "1" ]; then
        echo "=== SKIP_BETA_CLEAN=1: keeping ${LINUX_BUILD_DIR} and ${WINDOWS_BUILD_DIR} for incremental make ==="
    else
        docker run --rm -v "${ROOT}:/build" ubuntu:22.04 \
            rm -rf "/build/${LINUX_BUILD_DIR}" "/build/${WINDOWS_BUILD_DIR}"
    fi
    if [ "${SKIP_LINUX_BUILD:-0}" != "1" ]; then
        docker run --rm -v "${ROOT}:/build" ubuntu:22.04 \
            rm -rf "/build/${BETA_DIR}/linux64"
    fi
    if [ "${SKIP_MACOS_BUILD:-1}" != "1" ]; then
        docker run --rm -v "${ROOT}:/build" ubuntu:22.04 \
            rm -rf "/build/${BETA_DIR}/macos" "/build/${MACOS_BUILD_DIR}"
    fi
    mkdir -p "${ROOT}/${BETA_DIR}/linux64" "${ROOT}/${BETA_DIR}/macos" "${ROOT}/${BETA_DIR}/windows/release"
}

verify_dev_helper_off() {
  if grep -q '^#define ENABLE_DEV_HELPER_WINDOW 1' "${ROOT}/src/util/devhelperconfig.h" 2>/dev/null; then
    echo "ERROR: beta release requires ENABLE_DEV_HELPER_WINDOW 0 in src/util/devhelperconfig.h" >&2
    exit 1
  fi
}

beta_build_cxxflags() {
  echo "-DENABLE_BETA_BUILD=1 -DENABLE_POST_CATCHUP_VALIDATION_BETA=1"
}

mapfile -t PRESEED_MOUNT < <(docker_build_mount_args "$ROOT")

build_linux64() {
  echo "=== Beta Linux x64 build ==="
  docker run --rm \
    -e FORCE_DEPENDS_REBUILD="${FORCE_DEPENDS_REBUILD:-0}" \
    -e SKIP_BETA_CLEAN="${SKIP_BETA_CLEAN:-0}" \
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
        libxcb-xinerama0-dev libfontconfig1-dev libfreetype6-dev ripgrep

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
      fix_depends_static_linkage /build \${LINUX_HOST}

      ensure_autogen /build
      if [ \"\${SKIP_BETA_CLEAN:-0}\" = \"1\" ]; then
        echo '=== SKIP_BETA_CLEAN=1: incremental make in ${LINUX_BUILD_DIR} ==='
      else
        rm -rf /build/${LINUX_BUILD_DIR}
      fi
      configure_platform_build ${LINUX_BUILD_DIR} \${LINUX_HOST} '--disable-shared --enable-static ac_cv_search_clock_gettime=no' /build
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
    -e SKIP_BETA_CLEAN="${SKIP_BETA_CLEAN:-0}" \
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
        curl zip unzip gcc-9 g++-9 nsis git cmake file ripgrep

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
      if [ \"\${SKIP_BETA_CLEAN:-0}\" = \"1\" ]; then
        echo '=== SKIP_BETA_CLEAN=1: incremental make in ${WINDOWS_BUILD_DIR} ==='
      else
        rm -rf /build/${WINDOWS_BUILD_DIR}
      fi
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

build_macos() {
  if [ ! -d "${ROOT}/../shared/depends-preseed/SDKs/${OSX_SDK}" ] \
     && [ ! -d "${SHARED_DEPENDS_PRESEED:-}/SDKs/${OSX_SDK}" ]; then
    echo "=== SKIP macOS (SDK not found: ${OSX_SDK}) ==="
    echo "    Run: shared/depends-preseed/ensure-sdks.sh"
    echo "    Or build separately: ./Build-Scripts/build-beta-macos.sh"
    return 0
  fi

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

package_linux_tarball() {
  chmod +x "${ROOT}/Build-Scripts/package-beta-linux-tarball.sh"
  BINARY_DIR="${ROOT}/${BETA_DIR}/linux64" \
    OUT_DIR="${ROOT}/${BETA_DIR}/linux64" \
    "${ROOT}/Build-Scripts/package-beta-linux-tarball.sh" "$ROOT"
}

write_beta_readme() {
  local version qt_linux qt_win qt_macos
  version="$(read_version_from_configure)"
  qt_linux=$(grep -o 'QT_VERSION_STR "[^"]*"' \
    "${ROOT}/depends/${LINUX_HOST}/include/QtCore/qconfig.h" 2>/dev/null || echo "unknown")
  qt_win=$(grep -o 'QT_VERSION_STR "[^"]*"' \
    "${ROOT}/depends/${WINDOWS_HOST}/include/QtCore/qconfig.h" 2>/dev/null || echo "unknown")
  qt_macos=$(grep -o 'QT_VERSION_STR "[^"]*"' \
    "${ROOT}/depends/${MACOS_HOST}/include/QtCore/qconfig.h" 2>/dev/null || echo "unknown")

  cat > "${ROOT}/${BETA_DIR}/README.txt" <<EOF
Vericoin ${version} Beta
========================
Version: ${version}
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

2.1.1 baseline: clean 2.0.1 chain logic plus QoL upgrades only.
No IBD/catch-up PoST attestation changes from the 2.1.0 beta line.

Contents
--------
linux64/
  vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet
  vericoin-${version}-beta-x86_64-pc-linux-gnu.tar.gz  (installer)

macos/
  Vericoin.app, Vericoin.dmg, vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet
  vericoin-${version}-beta-${MACOS_HOST}.tar.gz  (Vericoin.app + Vericoin.dmg + bin/; SKIP_MACOS_BUILD=1 by default)
  *.dmg  (when make deploy succeeds)

windows/
  Unstripped .exe binaries
  release/  stripped binaries used by the installer
  Vericoin-${version}-beta-win64-setup-unsigned.exe  (installer)

Dependency versions (from preseed)
----------------------------------
Linux Qt:   ${qt_linux}
macOS Qt:   ${qt_macos}
Windows Qt: ${qt_win}
OpenSSL:    1.1.1w

Changes in ${version}
---------------------
- Qt 5.15.14, OpenSSL 1.1.1w, updated depends/build scripts
- Bootstrap download/apply with P2P pause and startup install
- Modern splash screen and shared Vericonomy wallet styling
- HTTPS bootstrap downloads (bundled Mozilla CA via curlssl)
- RAM-tier default -dbcache; DNS seed hostname fallback
- Static release linkage helpers for Linux/macOS beta tarballs

Build script: Build-Scripts/build-beta-windows-only.sh (this run)
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

  if [ "${SKIP_WINDOWS_BUILD:-0}" != "1" ]; then
    build_windows
  else
    echo "=== SKIP_WINDOWS_BUILD=1: keeping existing beta/windows/ ==="
  fi

  if [ "${SKIP_MACOS_BUILD:-1}" != "1" ]; then
    build_macos
    package_macos_tarball
  else
    echo "=== SKIP_MACOS_BUILD=1: skipping macOS (use build-beta-macos.sh or SKIP_MACOS_BUILD=0) ==="
  fi

  write_beta_readme

  echo ""
  echo "=== Beta release build complete ==="
  echo "Output: ${ROOT}/${BETA_DIR}/"
  find "${ROOT}/${BETA_DIR}" -maxdepth 3 -type f \( -name '*.exe' -o -name 'vericoin-*' -o -name '*.tar.gz' -o -name 'README.txt' \) \
    | sort | xargs ls -lh 2>/dev/null || true
}

main "$@"
