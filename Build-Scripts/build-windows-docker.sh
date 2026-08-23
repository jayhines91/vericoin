#!/bin/bash
# Windows x64 cross-compile (out-of-tree) — holder / release builds.
#   build/windows/  +  depends/x86_64-w64-mingw32/  +  out-windows/  +  release-windows/
#
# For Developer Edition (verbose trace, dev splash), use:
#   Build-Scripts/build-windows-dev-docker.sh  →  out-windows-dev/
# Ensure ENABLE_DEV_HELPER_WINDOW is 0 in src/util/devhelperconfig.h before release builds.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh
mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")

PLATFORM=windows
HOST_TRIPLET=x86_64-w64-mingw32
BUILD_DIR="build/${PLATFORM}"
OUT_DIR="out-${PLATFORM}"
RELEASE_DIR="release-${PLATFORM}"

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
      g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
      curl zip unzip gcc-9 g++-9 nsis git

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100
    update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

    export RC=\${HOST_TRIPLET}-windres WINDRES=\${HOST_TRIPLET}-windres

    f=depends/packages/curl.mk
    if [ -f \"\$f\" ] && ! grep -q 'CI: cross-compile opts' \"\$f\"; then
      cat >> \"\$f\" <<'EOF'

# CI: cross-compile opts for Windows
\$(package)_config_opts += --disable-debug --disable-curldebug --disable-ldap --disable-ldaps --without-libidn2 --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-ssh --without-libssh2 --without-rtmp
\$(package)_config_opts_mingw32 += --with-winssl
\$(package)_config_opts_mingw64 += --with-winssl
\$(package)_conf_env += ac_cv_func_strerror_r=no ac_cv_strerror_r_char_p=no ac_cv_func_clock_gettime=no ac_cv_header_dlfcn_h=no ac_cv_have_decl_strerror_r=yes
EOF
    fi

    if [ -f src/util/time.cpp ] && ! grep -q gmtime_r_compat src/util/time.cpp; then
      {
        echo '#ifdef _WIN32'
        echo '#include <time.h>'
        echo 'static inline struct tm* gmtime_r_compat(const time_t* t, struct tm* res){ return gmtime_s(res,t)==0 ? res : NULL; }'
        echo '#define gmtime_r(t,r) gmtime_r_compat((t),(r))'
        echo '#endif'
        cat src/util/time.cpp
      } > src/util/time.cpp.tmp && mv src/util/time.cpp.tmp src/util/time.cpp
    fi

    clean_root_configure_artifacts /build
    ensure_depends ${HOST_TRIPLET} /build \"RC=\\\$RC WINDRES=\\\$WINDRES\"
    ensure_autogen /build
    configure_platform_build ${BUILD_DIR} ${HOST_TRIPLET} '--disable-shared --enable-static ac_cv_search_clock_gettime=no' /build
    ensure_secp256k1_gen_context ${BUILD_DIR} /build
    platform_make ${BUILD_DIR} /build 4

    cd /build/${BUILD_DIR}
    make deploy || true

    prepare_output_dirs /build ${OUT_DIR} ${RELEASE_DIR}
    cp -f src/*.exe /build/${OUT_DIR}/ 2>/dev/null || true
    cp -f src/qt/*.exe /build/${OUT_DIR}/ 2>/dev/null || true
    cp -f release/*.exe /build/${RELEASE_DIR}/ 2>/dev/null || true
    cp -f *win64-setup*.exe /build/${OUT_DIR}/ 2>/dev/null || true
    cp -f *win64-setup*.exe /build/ 2>/dev/null || true

    echo '=== Windows build complete ==='
    ls -la /build/${OUT_DIR}/ /build/${RELEASE_DIR}/ /build/*win64-setup*.exe 2>/dev/null || true
  "
