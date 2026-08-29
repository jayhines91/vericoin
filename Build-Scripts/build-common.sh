# Shared helpers for out-of-tree, per-platform Vericoin builds.
# Each platform uses its own:
#   build/<platform>/          configure + object files
#   depends/<host-triplet>/    cached dependency toolchain
#   out-<platform>/            binaries
#   release-<platform>/        stripped binaries (where applicable)
#
# Never configure at the repo root — that pollutes src/ and breaks cross-compiles.

build_common_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    BUILD_COMMON_ROOT="$(pwd)"
}

# Remove accidental in-tree configure/build artifacts (not platform build dirs).
clean_root_configure_artifacts() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    cd "$root"

    if [ -f config.status ] || [ -f Makefile ]; then
        echo "=== Cleaning stale in-tree configure at repo root ==="
        rm -f config.status config.log Makefile libtool
        rm -rf src/config/bitcoin-config.h src/config/stamp-h1
        find src -name '*.o' -delete
        find src -name '*.a' -delete
        find src -name '*.lo' -delete
        find src -name '.deps' -type d -prune -exec rm -rf {} + 2>/dev/null || true
    fi

    # Subproject configure leakage from old in-tree builds
    rm -rf src/univalue/config.* src/univalue/Makefile src/univalue/libtool src/univalue/.libs
    rm -rf src/secp256k1/config.* src/secp256k1/Makefile src/secp256k1/libtool src/secp256k1/.libs
    rm -f src/secp256k1/src/libsecp256k1-config.h
}

ensure_autogen() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    cd "$root"
    local lock="${root}/.autogen.lock"
    (
        flock -x 9
        if [ ! -x configure ] || [ ! -f build-aux/compile ] || [ ! -f build-aux/missing ] \
            || find build-aux/m4 -newer configure -print -quit 2>/dev/null | grep -q .; then
            ./autogen.sh
        fi
    ) 9>"$lock"
}

# Source shared/depends-preseed helpers (env + depends-cache.sh).
source_shared_preseed_helpers() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local cache_root=""

    if [ -n "${SHARED_DEPENDS_PRESEED:-}" ] && [ -f "${SHARED_DEPENDS_PRESEED}/depends-cache.sh" ]; then
        cache_root="${SHARED_DEPENDS_PRESEED}"
    elif [ -d "${root}/../shared/depends-preseed" ]; then
        cache_root="$(cd "${root}/../shared/depends-preseed" && pwd)"
    fi

    if [ -z "$cache_root" ] || [ ! -f "${cache_root}/depends-cache.sh" ]; then
        echo "ERROR: shared depends preseed not found at ${root}/../shared/depends-preseed" >&2
        echo "       Populate it with shared/depends-preseed/preseed-depends.sh" >&2
        return 1
    fi

    if [ -f "${cache_root}/env.sh" ]; then
        # shellcheck source=/dev/null
        source "${cache_root}/env.sh"
    fi
    export DEPENDS_PRESEED_ROOT="${SHARED_DEPENDS_PRESEED:-$cache_root}"
    export SHARED_DEPENDS_PRESEED="${SHARED_DEPENDS_PRESEED:-$cache_root}"
    # shellcheck source=/dev/null
    source "${cache_root}/depends-cache.sh"
}

fix_qt_pkgconfig_versions() {
    local root="$1"
    local host_triplet="$2"
    local pc_dir="${root}/depends/${host_triplet}/lib/pkgconfig"
    if [ -d "$pc_dir" ]; then
        sed -i 's/^Version: .*/Version: 5.15.14/' "${pc_dir}"/Qt5*.pc 2>/dev/null || true
    fi
}

# Strip shared-library artifacts from depends and fix stale pkg-config metadata
# so release binaries statically link OpenSSL/curl (no libssl.so.1.1 / brotli).
fix_depends_static_linkage() {
    local root="$1"
    local host_triplet="$2"
    local lib_dir="${root}/depends/${host_triplet}/lib"
    local pc="${root}/depends/${host_triplet}/lib/pkgconfig/libcurl.pc"

    if [ -d "$lib_dir" ]; then
        rm -f "${lib_dir}"/libssl.so "${lib_dir}"/libssl.so.* \
              "${lib_dir}"/libcrypto.so "${lib_dir}"/libcrypto.so.* \
              "${lib_dir}"/libssl.dylib "${lib_dir}"/libssl.*.dylib \
              "${lib_dir}"/libcrypto.dylib "${lib_dir}"/libcrypto.*.dylib
    fi

    if [ -f "$pc" ]; then
        sed -i 's/ -lbrotlidec//g; s/brotli //g' "$pc"
    fi

    if [ -f "${lib_dir}/libssl.a" ] && [ -f "$pc" ]; then
        if grep -q brotli "$pc"; then
            echo "ERROR: libcurl.pc still references brotli after fix (${pc})" >&2
            return 1
        fi
    fi
}

# Verify shared macOS SDK + depends cache before cross-compiling.
verify_macos_preseed_ready() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local host_triplet="${2:-x86_64-apple-darwin16}"
    local sdk_name="${3:-Xcode-11.3.1-11C505-extracted-SDK-with-libcxx-headers}"

    source_shared_preseed_helpers "$root" || return 1

    if [ ! -d "${SHARED_DEPENDS_PRESEED}/SDKs/${sdk_name}" ]; then
        echo "ERROR: macOS SDK not found at ${SHARED_DEPENDS_PRESEED}/SDKs/${sdk_name}" >&2
        echo "Run: shared/depends-preseed/ensure-sdks.sh" >&2
        return 1
    fi

    local family shared_dep qt_ver ssl_ver
    family="$(detect_project_family "$root")" || return 1
    shared_dep="$(shared_built_depends_dir "$family" "$host_triplet")"

    if [ ! -f "${shared_dep}/lib/libQt5Core.a" ] || [ ! -f "${shared_dep}/plugins/platforms/libqcocoa.a" ]; then
        echo "ERROR: macOS depends preseed incomplete at ${shared_dep}" >&2
        echo "Run: ./Build-Scripts/preseed-depends.sh macos" >&2
        return 1
    fi

    qt_ver=$(grep -o 'QT_VERSION_STR "[^"]*"' "${shared_dep}/include/QtCore/qconfig.h" 2>/dev/null | head -1 || true)
    ssl_ver=$(grep -o 'OpenSSL 1\.1\.1[^"]*"' "${shared_dep}/include/openssl/opensslv.h" 2>/dev/null | head -1 || true)
    if [[ "$qt_ver" != *"5.15.14"* || "$ssl_ver" != *"1.1.1w"* ]]; then
        echo "ERROR: macOS preseed has ${qt_ver:-missing Qt} / ${ssl_ver:-missing OpenSSL}; need Qt 5.15.14 + OpenSSL 1.1.1w" >&2
        return 1
    fi

    echo "=== macOS preseed ready: ${qt_ver}, ${ssl_ver}, SDK ${sdk_name} ==="
}

ensure_depends() {
    local host_triplet="$1"
    local root="${2:-$BUILD_COMMON_ROOT}"
    local extra_make_args="${3:-}"
    cd "$root"

    source_shared_preseed_helpers "$root" || exit 1
    ensure_depends_with_shared_preseed "$host_triplet" "$root" "$extra_make_args" 4
    fix_qt_pkgconfig_versions "$root" "$host_triplet"
    fix_depends_static_linkage "$root" "$host_triplet"
}

# Docker: always mount CodeRepo/shared/depends-preseed at /shared/depends-preseed.
docker_shared_preseed_mount_args() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local shared
    source_shared_preseed_helpers "$root" || exit 1
    shared="$(default_shared_preseed_for_project "$root")" || exit 1
    printf '%s\n' "-v" "${shared}:${DOCKER_SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}" \
        "-e" "SHARED_DEPENDS_PRESEED=${DOCKER_SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}"
}

# Prefer in-repo shared/ (GitHub clone); fall back to CodeRepo sibling layout.
shared_styles_dir() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    if [ -d "${root}/shared/vericonomy-qt-styles" ]; then
        echo "${root}/shared/vericonomy-qt-styles"
    elif [ -d "${root}/../shared/vericonomy-qt-styles" ]; then
        echo "$(cd "${root}/../shared/vericonomy-qt-styles" && pwd)"
    else
        return 1
    fi
}

# Docker: mount shared styles so qt/res symlinks resolve in-container (CodeRepo layout).
docker_shared_styles_mount_args() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local styles_dir
    styles_dir="$(shared_styles_dir "$root")" || return 0
    printf '%s\n' "-v" "${styles_dir}:/shared/vericonomy-qt-styles"
}

docker_build_mount_args() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local preseed_real styles_dir
    if [ -d "${root}/shared/depends-preseed" ]; then
        preseed_real="$(readlink -f "${root}/shared/depends-preseed" 2>/dev/null || echo "${root}/shared/depends-preseed")"
    else
        local repo_shared
        repo_shared="$(cd "${root}/../shared" && pwd)"
        preseed_real="$(readlink -f "${repo_shared}/depends-preseed" 2>/dev/null || echo "${repo_shared}/depends-preseed")"
    fi
    styles_dir="$(shared_styles_dir "$root")" || styles_dir=""
    if [ -n "$styles_dir" ]; then
        printf '%s\n' \
            "-v" "${preseed_real}:/shared/depends-preseed" \
            "-v" "${styles_dir}:/shared/vericonomy-qt-styles" \
            "-e" "SHARED_DEPENDS_PRESEED=${DOCKER_SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}"
    else
        printf '%s\n' \
            "-v" "${preseed_real}:/shared/depends-preseed" \
            "-e" "SHARED_DEPENDS_PRESEED=${DOCKER_SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}"
    fi
}

run_pre_compile_checks() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    "${root}/Build-Scripts/pre-compile-checks.sh"
}

configure_platform_build() {
    local build_dir="$1"
    local host_triplet="$2"
    local configure_extra="${3:-}"
    local root="${4:-$BUILD_COMMON_ROOT}"
    cd "$root"
    run_pre_compile_checks "$root"
    mkdir -p "$build_dir"
    cd "$build_dir"

    export CONFIG_SITE="${root}/depends/${host_triplet}/share/config.site"
    local dep="${root}/depends/${host_triplet}"

    if [ -f config.status ]; then
        echo "=== Reusing existing ${build_dir} (incremental) ==="
        return 0
    fi

    echo "=== Configuring ${build_dir} for ${host_triplet} ==="
    rm -f config.cache
    # shellcheck disable=SC2086
    ../../configure --host="$host_triplet" --prefix="$dep" --with-gui=qt5 \
        --with-qt-bindir="$dep/native/bin" --with-qt-incdir="$dep/include" --with-qt-libdir="$dep/lib" \
        --with-qt-plugindir="$dep/plugins" \
        --disable-bench --disable-tests --enable-reduce-exports \
        $configure_extra
}

ensure_secp256k1_gen_context() {
    local build_dir="$1"
    local root="${2:-$BUILD_COMMON_ROOT}"
    cd "${root}/${build_dir}/src/secp256k1"
    if [ -x gen_context ]; then
        return 0
    fi
    echo "=== Building native gen_context for ${build_dir} ==="
    gcc-9 -I../../../../src/secp256k1/src -I../../../../src/secp256k1 \
        -c ../../../../src/secp256k1/src/gen_context.c -o gen_context.o
    gcc-9 gen_context.o -o gen_context
}

platform_make() {
    local build_dir="$1"
    local root="${2:-$BUILD_COMMON_ROOT}"
    local jobs="${3:-4}"
    cd "${root}/${build_dir}"
    make -j"$jobs" -C src/univalue
    make -j"$jobs"
}

# Stage Vericoin.app (from make deploy or appbundle) into beta/macos output.
stage_macos_app_bundle() {
    local build_dir="$1"
    local out_dir="$2"
    local app_name="${3:-Vericoin.app}"
    local src=""

    if [ -d "${build_dir}/dist/${app_name}" ]; then
        src="${build_dir}/dist/${app_name}"
    elif [ -d "${build_dir}/${app_name}" ]; then
        src="${build_dir}/${app_name}"
    fi

    if [ -z "$src" ]; then
        echo "ERROR: ${app_name} not found under ${build_dir} (make deploy/appbundle failed)" >&2
        return 1
    fi

    rm -rf "${out_dir}/${app_name}"
    cp -a "$src" "${out_dir}/"
    echo "=== Staged ${app_name} from ${src} ==="
}

# Stage Vericoin.dmg (from make deploy) into beta/macos output.
stage_macos_dmg() {
    local build_dir="$1"
    local out_dir="$2"
    local dest_name="${3:-Vericoin.dmg}"
    local src=""

    for candidate in "${build_dir}/Vericoin.dmg" "${build_dir}"/*.dmg; do
        if [ -f "$candidate" ]; then
            src="$candidate"
            break
        fi
    done

    if [ -z "$src" ]; then
        echo "ERROR: no .dmg installer found in ${build_dir} (make deploy failed)" >&2
        return 1
    fi

    cp -f "$src" "${out_dir}/${dest_name}"
    echo "=== Staged macOS installer: ${out_dir}/${dest_name} (from ${src}) ==="
}

prepare_output_dirs() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local out_dir="$2"
    local release_dir="${3:-}"
    mkdir -p "${root}/${out_dir}"
    if [ -n "$release_dir" ]; then
        mkdir -p "${root}/${release_dir}"
    fi
}

# --- Windows Developer Edition (debug machine) --------------------------------

WINDOWS_DEV_HOST_TRIPLET="${WINDOWS_DEV_HOST_TRIPLET:-x86_64-w64-mingw32}"
WINDOWS_DEV_BUILD_DIR="${WINDOWS_DEV_BUILD_DIR:-build/windows-dev}"
WINDOWS_DEV_OUT_DIR="${WINDOWS_DEV_OUT_DIR:-out-windows-dev}"
WINDOWS_DEV_RELEASE_DIR="${WINDOWS_DEV_RELEASE_DIR:-release-windows-dev}"
WINDOWS_DEV_CONFIGURE_EXTRA="${WINDOWS_DEV_CONFIGURE_EXTRA:-}"

# Max-trace Developer Edition (separate tree: build/windows-dev-max → out-windows-dev-max)
WINDOWS_DEV_MAX_BUILD_DIR="${WINDOWS_DEV_MAX_BUILD_DIR:-build/windows-dev-max}"
WINDOWS_DEV_MAX_OUT_DIR="${WINDOWS_DEV_MAX_OUT_DIR:-out-windows-dev-max}"
WINDOWS_DEV_MAX_RELEASE_DIR="${WINDOWS_DEV_MAX_RELEASE_DIR:-release-windows-dev-max}"

require_dev_helper_enabled() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    if ! grep -q '^#define ENABLE_DEV_HELPER_WINDOW 1' "${root}/src/util/devhelperconfig.h" 2>/dev/null; then
        echo "ERROR: Developer Edition requires ENABLE_DEV_HELPER_WINDOW 1 in src/util/devhelperconfig.h" >&2
        echo "       Set it to 1 on this debug machine, then re-run." >&2
        echo "       For holder/release builds use Build-Scripts/build-windows-docker.sh with the flag at 0." >&2
        exit 1
    fi
}

ensure_windows_cross_toolchain() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y build-essential automake libtool pkg-config python3 \
        g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
        curl zip unzip gcc-9 g++-9 nsis git

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100
    update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

    export RC="${WINDOWS_DEV_HOST_TRIPLET}-windres"
    export WINDRES="${WINDOWS_DEV_HOST_TRIPLET}-windres"
}

patch_curl_mk_for_windows_cross() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local f="${root}/depends/packages/curl.mk"
    if [ -f "$f" ] && ! grep -q 'CI: cross-compile opts' "$f"; then
        cat >> "$f" <<'EOF'

# CI: cross-compile opts for Windows
$(package)_config_opts += --disable-debug --disable-curldebug --disable-ldap --disable-ldaps --without-libidn2 --without-libpsl --without-brotli --without-zstd --without-nghttp2 --without-ssh --without-libssh2 --without-rtmp
$(package)_config_opts_mingw32 += --with-winssl
$(package)_config_opts_mingw64 += --with-winssl
$(package)_conf_env += ac_cv_func_strerror_r=no ac_cv_strerror_r_char_p=no ac_cv_func_clock_gettime=no ac_cv_header_dlfcn_h=no ac_cv_have_decl_strerror_r=yes
EOF
    fi
}

patch_time_cpp_for_windows_cross() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    if [ -f "${root}/src/util/time.cpp" ] && ! grep -q gmtime_r_compat "${root}/src/util/time.cpp"; then
        {
            echo '#ifdef _WIN32'
            echo '#include <time.h>'
            echo 'static inline struct tm* gmtime_r_compat(const time_t* t, struct tm* res){ return gmtime_s(res,t)==0 ? res : NULL; }'
            echo '#define gmtime_r(t,r) gmtime_r_compat((t),(r))'
            echo '#endif'
            cat "${root}/src/util/time.cpp"
        } > "${root}/src/util/time.cpp.tmp" && mv "${root}/src/util/time.cpp.tmp" "${root}/src/util/time.cpp"
    fi
}

copy_windows_dev_binaries() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local build_dir="${2:-$WINDOWS_DEV_BUILD_DIR}"
    local out_dir="${3:-$WINDOWS_DEV_OUT_DIR}"
    local release_dir="${4:-$WINDOWS_DEV_RELEASE_DIR}"

    prepare_output_dirs "$root" "$out_dir" "$release_dir"
    cp -f "${root}/${build_dir}/src/"*.exe "${root}/${out_dir}/" 2>/dev/null || true
    cp -f "${root}/${build_dir}/src/qt/"*.exe "${root}/${out_dir}/" 2>/dev/null || true
    cp -f "${root}/${build_dir}/release/"*.exe "${root}/${release_dir}/" 2>/dev/null || true
}

clean_windows_dev_output_dir() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local out_dir="${2:-$WINDOWS_DEV_OUT_DIR}"
    if [ -d "${root}/${out_dir}" ]; then
        echo "=== Cleaning ${out_dir}/ before dev build ==="
        rm -rf "${root}/${out_dir}"
    fi
}

# Compile all Windows dev binaries and build the Developer Edition NSIS installer.
run_windows_dev_compile_and_package() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    local host_triplet="${2:-$WINDOWS_DEV_HOST_TRIPLET}"
    local build_dir="${3:-$WINDOWS_DEV_BUILD_DIR}"
    local out_dir="${4:-$WINDOWS_DEV_OUT_DIR}"
    local release_dir="${5:-$WINDOWS_DEV_RELEASE_DIR}"
    local configure_extra="${6:---disable-shared --enable-static --enable-debug ac_cv_search_clock_gettime=no}"
    local package_script="${7:-${root}/Build-Scripts/package-windows-dev-installer.sh}"

    require_dev_helper_enabled "$root"
    clean_windows_dev_output_dir "$root" "$out_dir"
    ensure_windows_cross_toolchain
    patch_curl_mk_for_windows_cross "$root"
    patch_time_cpp_for_windows_cross "$root"

    clean_root_configure_artifacts "$root"
    ensure_depends "$host_triplet" "$root" "RC=\$RC WINDRES=\$WINDRES"
    ensure_autogen "$root"
    configure_platform_build "$build_dir" "$host_triplet" \
        "${configure_extra} ${WINDOWS_DEV_CONFIGURE_EXTRA}" "$root"
    ensure_secp256k1_gen_context "$build_dir" "$root"
    platform_make "$build_dir" "$root" 4

    copy_windows_dev_binaries "$root" "$build_dir" "$out_dir" "$release_dir"

    chmod +x "$package_script"
    BINARY_DIR="${root}/${out_dir}" OUT_DIR="${root}/${out_dir}" "$package_script" "$root"

    echo "=== Windows Developer Edition recompile complete ==="
    echo "Binaries + installer: ${root}/${out_dir}/"
    ls -la "${root}/${out_dir}/"
}

run_windows_dev_max_compile_and_package() {
    local root="${1:-$BUILD_COMMON_ROOT}"
    echo "=== Windows Developer Edition MAX TRACE build ==="
    echo "    build: ${WINDOWS_DEV_MAX_BUILD_DIR}/"
    echo "    out:   ${WINDOWS_DEV_MAX_OUT_DIR}/"
    WINDOWS_DEV_CONFIGURE_EXTRA="--enable-dev-max-trace"
    run_windows_dev_compile_and_package \
        "$root" \
        "$WINDOWS_DEV_HOST_TRIPLET" \
        "$WINDOWS_DEV_MAX_BUILD_DIR" \
        "$WINDOWS_DEV_MAX_OUT_DIR" \
        "$WINDOWS_DEV_MAX_RELEASE_DIR" \
        '--disable-shared --enable-static --enable-debug ac_cv_search_clock_gettime=no' \
        "${root}/Build-Scripts/package-windows-dev-max-installer.sh"
    WINDOWS_DEV_CONFIGURE_EXTRA=""
}
