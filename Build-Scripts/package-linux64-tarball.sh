#!/bin/bash
# Package Linux x64 release binaries into a distributable tarball.
#
# Usage:
#   ./Build-Scripts/package-linux64-tarball.sh
#   BINARY_DIR=/path/to/out-linux64 OUT_DIR=/path/to/out-linux64 ./Build-Scripts/package-linux64-tarball.sh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BINARY_DIR="${BINARY_DIR:-${ROOT}/out-linux64}"
OUT_DIR="${OUT_DIR:-${ROOT}/out-linux64}"
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
DISTNAME="vericoin-${VERSION}-${HOST_TRIPLET}"
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
    echo "       Run Build-Scripts/build-linux64-docker.sh first." >&2
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

cp -f "${ROOT}/COPYING" "${PKG}/"
if [ -f "${ROOT}/src/certs/cacert.pem" ]; then
  mkdir -p "${PKG}/certs"
  cp -f "${ROOT}/src/certs/cacert.pem" "${PKG}/cacert.pem"
  cp -f "${ROOT}/src/certs/cacert.pem" "${PKG}/certs/cacert.pem"
fi
if [ -f "${ROOT}/doc/README.md" ]; then
  mkdir -p "${PKG}/doc"
  cp -f "${ROOT}/doc/README.md" "${PKG}/doc/"
fi
if [ -f "${ROOT}/doc/README_linux.txt" ]; then
  mkdir -p "${PKG}/doc"
  cp -f "${ROOT}/doc/README_linux.txt" "${PKG}/doc/"
fi

cat > "${PKG}/INSTALL.txt" <<EOF
Vericoin Linux release (${HOST_TRIPLET})
Version: ${VERSION}

Extract this archive, then run binaries from bin/:

  tar -xzf ${DISTNAME}.tar.gz
  cd ${DISTNAME}
  ./bin/vericoin-qt

Headless node:  ./bin/vericoind
RPC client:     ./bin/vericoin-cli
Wallet tool:    ./bin/vericoin-wallet
Transaction:    ./bin/vericoin-tx

Default data directory: ~/.vericoin
EOF

mkdir -p "$OUT_DIR"
rm -f "$TARBALL"
tar -C "$WORK" -czf "$TARBALL" "$DISTNAME"

ls -lh "$TARBALL"
echo "=== Linux release tarball ready: ${TARBALL} ==="
