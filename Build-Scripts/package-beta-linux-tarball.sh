#!/bin/bash
# Package Linux x64 beta binaries into a release-style tarball.
#
# Expects fully static-linked depends (Qt, OpenSSL, xcb stack). No bundled lib/.
#
# Usage:
#   ./Build-Scripts/package-beta-linux-tarball.sh
#   BINARY_DIR=/path/to/beta/linux64 OUT_DIR=/path/to/beta/linux64 ./Build-Scripts/package-beta-linux-tarball.sh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BINARY_DIR="${BINARY_DIR:-${ROOT}/beta/linux64}"
OUT_DIR="${OUT_DIR:-${ROOT}/beta/linux64}"
HOST_TRIPLET="${HOST_TRIPLET:-x86_64-pc-linux-gnu}"

# shellcheck source=verify-static-linux.sh
source "${ROOT}/Build-Scripts/verify-static-linux.sh"

read_version_from_configure() {
  local cfg="${ROOT}/configure.ac"
  local major minor revision build
  major=$(sed -n 's/^define(_CLIENT_VERSION_MAJOR, //p' "$cfg" | tr -d ' )')
  minor=$(sed -n 's/^define(_CLIENT_VERSION_MINOR, //p' "$cfg" | tr -d ' )')
  revision=$(sed -n 's/^define(_CLIENT_VERSION_REVISION, //p' "$cfg" | tr -d ' )')
  build=$(sed -n 's/^define(_CLIENT_VERSION_BUILD, //p' "$cfg" | tr -d ' )')
  if [ -z "$major" ] || [ -z "$minor" ] || [ -z "$revision" ]; then
    echo "ERROR: could not read version from ${cfg}" >&2
    exit 1
  fi
  if [ -n "$build" ] && [ "$build" != "0" ]; then
    echo "${major}.${minor}.${revision}.${build}"
  else
    echo "${major}.${minor}.${revision}"
  fi
}

VERSION="$(read_version_from_configure)"
BETA_DIST_TAG="${BETA_DIST_TAG:-beta}"
DISTNAME="vericoin-${VERSION}-${BETA_DIST_TAG}-${HOST_TRIPLET}"
TARBALL="${OUT_DIR}/${DISTNAME}.tar.gz"

REQUIRED_BINARIES=(
  vericoin-qt
  vericoind
  vericoin-cli
  vericoin-tx
  vericoin-wallet
)

for bin in "${REQUIRED_BINARIES[@]}"; do
  if [ ! -f "${BINARY_DIR}/${bin}" ]; then
    echo "ERROR: missing ${BINARY_DIR}/${bin}" >&2
    exit 1
  fi
done

echo "=== Verifying static depends linkage (glibc runtime only) ==="
verify_static_linux_binaries \
  "${REQUIRED_BINARIES[@]/#/${BINARY_DIR}/}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="${WORK}/${DISTNAME}"
mkdir -p "${PKG}/bin"
cp -f "${BINARY_DIR}/vericoin-qt" "${BINARY_DIR}/vericoind" \
      "${BINARY_DIR}/vericoin-cli" "${BINARY_DIR}/vericoin-tx" \
      "${BINARY_DIR}/vericoin-wallet" "${PKG}/bin/"
chmod 755 "${PKG}/bin/"*

DEPENDS_FONTS="${ROOT}/depends/${HOST_TRIPLET}/etc/fonts"
if [ -d "${DEPENDS_FONTS}" ]; then
  mkdir -p "${PKG}/share/fontconfig/conf.d"
  sed 's|<cachedir>/build/depends/[^<]*</cachedir>|<cachedir prefix="xdg">fontconfig</cachedir>|' \
    "${DEPENDS_FONTS}/fonts.conf" > "${PKG}/share/fontconfig/fonts.conf"
  if [ -d "${DEPENDS_FONTS}/conf.d" ]; then
    cp -a "${DEPENDS_FONTS}/conf.d/." "${PKG}/share/fontconfig/conf.d/"
  fi
fi

cp -f "${ROOT}/README.md" "${ROOT}/COPYING" "${PKG}/" 2>/dev/null || cp -f "${ROOT}/COPYING" "${PKG}/"
if [ -f "${ROOT}/src/certs/cacert.pem" ]; then
  mkdir -p "${PKG}/certs"
  cp -f "${ROOT}/src/certs/cacert.pem" "${PKG}/cacert.pem"
  cp -f "${ROOT}/src/certs/cacert.pem" "${PKG}/certs/cacert.pem"
fi
if [ -f "${ROOT}/doc/README.md" ]; then
  mkdir -p "${PKG}/doc"
  cp -f "${ROOT}/doc/README.md" "${PKG}/doc/"
fi

cat > "${PKG}/BETA.txt" <<EOF
Vericoin Beta release build (${HOST_TRIPLET})
Version: ${VERSION}

Pre-release beta for testing:
- Qt 5.15.14 (static)
- OpenSSL 1.1.1w (static)
- xcb / font stack statically linked (no bundled lib/)
- PoST catch-up validation beta

Extract and run:
  tar -xzf ${DISTNAME}.tar.gz
  cd ${DISTNAME}
  ./bin/vericoin-qt
EOF

mkdir -p "$OUT_DIR"
rm -f "$TARBALL"
tar -C "$WORK" -czf "$TARBALL" "$DISTNAME"

ls -lh "$TARBALL"
echo "=== Beta Linux tarball ready: ${TARBALL} ==="
