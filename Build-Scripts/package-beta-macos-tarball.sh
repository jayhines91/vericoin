#!/bin/bash
# Package macOS x64 beta binaries into a release-style tarball.
#
# Expects static-linked depends (Qt, OpenSSL). Includes Vericoin.app, Vericoin.dmg, and CLI binaries.
#
# Usage:
#   ./Build-Scripts/package-beta-macos-tarball.sh
#   BINARY_DIR=/path/to/beta/macos OUT_DIR=/path/to/beta/macos ./Build-Scripts/package-beta-macos-tarball.sh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BINARY_DIR="${BINARY_DIR:-${ROOT}/beta/macos}"
OUT_DIR="${OUT_DIR:-${ROOT}/beta/macos}"
HOST_TRIPLET="${HOST_TRIPLET:-x86_64-apple-darwin16}"
OSX_APP_NAME="${OSX_APP_NAME:-Vericoin.app}"
OSX_DMG_NAME="${OSX_DMG_NAME:-Vericoin.dmg}"

# shellcheck source=verify-static-macos.sh
source "${ROOT}/Build-Scripts/verify-static-macos.sh"

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
INSTALLER_DMG="${OUT_DIR}/${DISTNAME}.dmg"

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

if [ ! -d "${BINARY_DIR}/${OSX_APP_NAME}" ]; then
  echo "ERROR: missing ${BINARY_DIR}/${OSX_APP_NAME}" >&2
  echo "The macOS build must run make deploy and stage the app bundle." >&2
  exit 1
fi

if [ ! -f "${BINARY_DIR}/${OSX_APP_NAME}/Contents/MacOS/Vericoin" ]; then
  echo "ERROR: ${BINARY_DIR}/${OSX_APP_NAME} is not a valid app bundle (missing Contents/MacOS/Vericoin)" >&2
  exit 1
fi

if [ ! -f "${BINARY_DIR}/${OSX_DMG_NAME}" ]; then
  echo "ERROR: missing ${BINARY_DIR}/${OSX_DMG_NAME}" >&2
  echo "The macOS build must run make deploy and stage the DMG installer." >&2
  exit 1
fi

echo "=== Verifying static depends linkage (system libs only) ==="
verify_static_macos_binaries \
  "${REQUIRED_BINARIES[@]/#/${BINARY_DIR}/}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="${WORK}/${DISTNAME}"
mkdir -p "${PKG}/bin"
cp -f "${BINARY_DIR}/vericoin-qt" "${BINARY_DIR}/vericoind" \
      "${BINARY_DIR}/vericoin-cli" "${BINARY_DIR}/vericoin-tx" \
      "${BINARY_DIR}/vericoin-wallet" "${PKG}/bin/"
chmod 755 "${PKG}/bin/"*

cp -a "${BINARY_DIR}/${OSX_APP_NAME}" "${PKG}/"
cp -f "${BINARY_DIR}/${OSX_DMG_NAME}" "${PKG}/${DISTNAME}.dmg"

cp -f "${ROOT}/README.md" "${ROOT}/COPYING" "${PKG}/" 2>/dev/null || cp -f "${ROOT}/COPYING" "${PKG}/"

cat > "${PKG}/BETA.txt" <<EOF
Vericoin Beta release build (${HOST_TRIPLET})
Version: ${VERSION}

Pre-release beta for testing:
- Qt 5.15.14 (static)
- OpenSSL 1.1.1w (static)
- PoST catch-up validation beta

Install (recommended):
  open ${DISTNAME}.dmg
  drag ${OSX_APP_NAME} to Applications

Or extract and run:
  tar -xzf ${DISTNAME}.tar.gz
  cd ${DISTNAME}
  xattr -cr ${OSX_APP_NAME}
  open ${OSX_APP_NAME}

CLI binaries are also in ./bin/ (vericoind, vericoin-cli, etc.).
EOF

mkdir -p "$OUT_DIR"
rm -f "$TARBALL" "$INSTALLER_DMG"
cp -f "${BINARY_DIR}/${OSX_DMG_NAME}" "$INSTALLER_DMG"
tar -C "$WORK" -czf "$TARBALL" "$DISTNAME"

ls -lh "$TARBALL" "$INSTALLER_DMG"
echo "=== Beta macOS tarball ready: ${TARBALL} ==="
echo "=== Beta macOS installer ready: ${INSTALLER_DMG} ==="
echo "    includes ${OSX_APP_NAME}, ${DISTNAME}.dmg, and bin/"
