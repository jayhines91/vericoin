#!/bin/bash
# Package Linux x64 beta binaries into a release-style tarball.
#
# Usage:
#   ./Build-Scripts/package-beta-linux-tarball.sh
#   BINARY_DIR=/path/to/beta/linux64 OUT_DIR=/path/to/beta/linux64 ./Build-Scripts/package-beta-linux-tarball.sh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BINARY_DIR="${BINARY_DIR:-${ROOT}/beta/linux64}"
OUT_DIR="${OUT_DIR:-${ROOT}/beta/linux64}"
HOST_TRIPLET="${HOST_TRIPLET:-x86_64-pc-linux-gnu}"

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
DISTNAME="vericoin-${VERSION}-beta-${HOST_TRIPLET}"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="${WORK}/${DISTNAME}"
mkdir -p "${PKG}/bin"
cp -f "${BINARY_DIR}/vericoin-qt" "${BINARY_DIR}/vericoind" \
      "${BINARY_DIR}/vericoin-cli" "${BINARY_DIR}/vericoin-tx" \
      "${BINARY_DIR}/vericoin-wallet" "${PKG}/bin/"
chmod 755 "${PKG}/bin/"*

cp -f "${ROOT}/README.md" "${ROOT}/COPYING" "${PKG}/"
if [ -f "${ROOT}/doc/README.md" ]; then
  mkdir -p "${PKG}/doc"
  cp -f "${ROOT}/doc/README.md" "${PKG}/doc/"
fi

cat > "${PKG}/BETA.txt" <<EOF
Vericoin Beta release build (${HOST_TRIPLET})
Version: ${VERSION}

Pre-release beta for testing:
- Qt 5.15.14
- OpenSSL 1.1.1w
- Wallet startup deadlock fixes

Extract and run binaries from bin/ (e.g. ./bin/vericoin-qt).
EOF

mkdir -p "$OUT_DIR"
rm -f "$TARBALL"
tar -C "$WORK" -czf "$TARBALL" "$DISTNAME"

ls -lh "$TARBALL"
echo "=== Beta Linux tarball ready: ${TARBALL} ==="
