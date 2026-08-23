#!/bin/bash
# Build fresh Vericoin depends caches (Qt 5.15+) for one or more platforms.
# Does not use stale shared preseed — runs make -C depends locally in Docker.
#
# After a successful build, publish into shared preseed so docker build scripts
# can materialize depends again:
#   ./Build-Scripts/build-depends-preseed.sh --publish linux64 windows
# Or manually:
#   ../../shared/depends-preseed/import-local-depends.sh vericoin <host>
#
# Usage:
#   ./Build-Scripts/build-depends-preseed.sh
#   ./Build-Scripts/build-depends-preseed.sh --flush linux64 windows
#   ./Build-Scripts/build-depends-preseed.sh --publish linux64
#   JOBS=8 ./Build-Scripts/build-depends-preseed.sh linux64 windows
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=build-common.sh
source Build-Scripts/build-common.sh

FLUSH=0
PUBLISH=0
PLATFORMS=()
for arg in "$@"; do
    case "$arg" in
        --flush) FLUSH=1 ;;
        --publish) PUBLISH=1 ;;
        linux64|linuxarm|macos|windows|win64|mingw) PLATFORMS+=("$arg") ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--flush] [--publish] [linux64 linuxarm macos windows]" >&2
            exit 1
            ;;
    esac
done

if [ ${#PLATFORMS[@]} -eq 0 ]; then
    PLATFORMS=(linux64 windows)
fi

JOBS="${JOBS:-4}"
mapfile -t PRESEED_MOUNT < <(docker_shared_preseed_mount_args "$ROOT")
SHARED_PRESEED="${SHARED_DEPENDS_PRESEED:-$(cd "$ROOT/../shared/depends-preseed" && pwd)}"

want_linux64=0 want_linuxarm=0 want_macos=0 want_windows=0
for p in "${PLATFORMS[@]}"; do
    case "$p" in
        linux64) want_linux64=1 ;;
        linuxarm) want_linuxarm=1 ;;
        macos) want_macos=1 ;;
        windows|win64|mingw) want_windows=1 ;;
    esac
done

docker run --rm \
  -e JOBS="$JOBS" \
  -e WANT_LINUX64="$want_linux64" \
  -e WANT_LINUXARM="$want_linuxarm" \
  -e WANT_MACOS="$want_macos" \
  -e WANT_WINDOWS="$want_windows" \
  -e FLUSH="$FLUSH" \
  -e PUBLISH="$PUBLISH" \
  -e HOST_LINUX64="${HOST_LINUX64:-x86_64-pc-linux-gnu}" \
  -e HOST_LINUXARM="${HOST_LINUXARM:-aarch64-linux-gnu}" \
  -e HOST_MACOS="${HOST_MACOS:-x86_64-apple-darwin16}" \
  -e HOST_WINDOWS="${HOST_WINDOWS:-x86_64-w64-mingw32}" \
  -e SHARED_DEPENDS_PRESEED="${SHARED_PRESEED}" \
  -v "$ROOT:/build" \
  "${PRESEED_MOUNT[@]}" \
  -w /build \
  ubuntu:22.04 \
  bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y build-essential automake libtool pkg-config python3 python3-setuptools \
      curl git bison ca-certificates gcc-9 g++-9 patch \
      g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
      g++-mingw-w64-x86-64 binutils-mingw-w64-x86-64 \
      clang lld libcap-dev librsvg2-bin imagemagick libtiff-tools \
      libtinfo5 libz-dev libbz2-dev

    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100
    update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

    export RC="${HOST_WINDOWS}-windres"
    export WINDRES="${HOST_WINDOWS}-windres"

    build_depends_host() {
      local host="$1"
      local extra="${2:-}"
      echo "=== Building depends for ${host} (jobs=${JOBS}) ==="
      # shellcheck disable=SC2086
      make -C depends HOST="${host}" ${extra} -j"${JOBS}"
      if [ ! -f "depends/${host}/lib/libcurl.a" ]; then
        echo "ERROR: depends build for ${host} did not produce libcurl.a" >&2
        exit 1
      fi
      if ! ls depends/"${host}"/native/bin/moc* depends/"${host}"/native/bin/qmake* 2>/dev/null | grep -q .; then
        echo "WARNING: Qt tools not found under depends/${host}/native/bin (NO_QT build?)" >&2
      fi
      echo "=== OK depends/${host} ==="
    }

    cd /build

    if [ "$FLUSH" = 1 ]; then
      echo "=== Flushing local depends caches (inside container) ==="
      chmod -R u+w depends/built depends/work depends/download 2>/dev/null || true
      rm -rf depends/built depends/work depends/download
      for host in "$HOST_LINUX64" "$HOST_LINUXARM" "$HOST_MACOS" "$HOST_WINDOWS"; do
        chmod -R u+w "depends/${host}" 2>/dev/null || true
        rm -rf "depends/${host}"
      done
    fi

    [ "$WANT_LINUX64" = 1 ] && build_depends_host "$HOST_LINUX64"
    [ "$WANT_LINUXARM" = 1 ] && build_depends_host "$HOST_LINUXARM"

    if [ "$WANT_MACOS" = 1 ]; then
      if [ -d "${SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}/SDKs" ]; then
        build_depends_host "$HOST_MACOS" "SDK_PATH=${SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}/SDKs"
      else
        echo "=== SKIP macos (shared SDKs not mounted) ===" >&2
      fi
    fi

    [ "$WANT_WINDOWS" = 1 ] && build_depends_host "$HOST_WINDOWS" "RC=$RC WINDRES=$WINDRES"

    if [ "$PUBLISH" = 1 ]; then
      # shellcheck source=/dev/null
      source "${SHARED_DEPENDS_PRESEED:-/shared/depends-preseed}/depends-cache.sh"
      for host in "$HOST_LINUX64" "$HOST_LINUXARM" "$HOST_MACOS" "$HOST_WINDOWS"; do
        if [ -f "/build/depends/${host}/lib/libcurl.a" ]; then
          publish_depends_to_shared_preseed /build "$host" || true
        fi
      done
    fi
  '

echo "=== Depends preseed build finished ==="
echo "Platforms: ${PLATFORMS[*]}"
if [ "$PUBLISH" = 0 ]; then
    echo "To publish into shared preseed after verifying:"
    echo "  $0 --publish ${PLATFORMS[*]}"
    echo "Or flush old shared caches first:"
    echo "  ../shared/depends-preseed/ops/flush-family-cache.sh vericoin x86_64-pc-linux-gnu x86_64-w64-mingw32"
fi
