#!/bin/bash
# Package a Windows NSIS installer for the beta release build.
#
# Uses stripped binaries from beta/windows/release/.
#
# Usage:
#   ./Build-Scripts/package-beta-windows-installer.sh
#   RELEASE_DIR=/path/to/strip OUT_DIR=/path/to/beta/windows ./Build-Scripts/package-beta-windows-installer.sh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
RELEASE_DIR="${RELEASE_DIR:-${ROOT}/beta/windows/release}"
OUT_DIR="${OUT_DIR:-${ROOT}/beta/windows}"
STAGING_DIR="${STAGING_DIR:-${ROOT}/beta/installer-staging}"
NSI_TEMPLATE="${ROOT}/share/setup-beta.nsi.in"
NSI_GENERATED="${ROOT}/beta/installer-windows/setup-beta.nsi"

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
VERSION_QUAD="$(echo "$VERSION" | awk -F. '{printf "%s.%s.%s.%s", $1, $2, $3, ($4==""?0:$4)}')"
COPYRIGHT_YEAR="$(date +%Y)"
INSTALLER_NAME="Vericoin-${VERSION}-beta-win64-setup-unsigned.exe"
INSTALLER_PATH="${OUT_DIR}/${INSTALLER_NAME}"

REQUIRED_BINARIES=(
  vericoin-qt.exe
  vericoind.exe
  vericoin-cli.exe
  vericoin-tx.exe
  vericoin-wallet.exe
)

for bin in "${REQUIRED_BINARIES[@]}"; do
  if [ ! -f "${RELEASE_DIR}/${bin}" ]; then
    echo "ERROR: missing ${RELEASE_DIR}/${bin}" >&2
    exit 1
  fi
done

if ! command -v makensis >/dev/null 2>&1; then
  echo "ERROR: makensis not found (install NSIS)" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR" "$OUT_DIR" "$(dirname "$NSI_GENERATED")"

cat > "${STAGING_DIR}/BETA_windows.txt" <<EOF
Vericoin Beta release build
Version: ${VERSION}

This is a pre-release beta for testing. It includes:
- Qt 5.15.14 (upgraded from 5.9.8)
- OpenSSL 1.1.1w
- Wallet startup deadlock fixes

Default install location: Program Files\\Vericoin Beta

This installer uses a separate directory and registry keys from a
standard Vericoin installation so it can coexist for side-by-side testing.

Binaries included
-----------------
vericoin-qt.exe          GUI wallet
daemon\\vericoind.exe    Headless node
daemon\\vericoin-cli.exe RPC client
daemon\\vericoin-tx.exe  Transaction utility
daemon\\vericoin-wallet.exe  Wallet tool
EOF

ROOT_NSI="${ROOT//\\//}"
RELEASE_DIR_NSI="${RELEASE_DIR//\\//}"
STAGING_DIR_NSI="${STAGING_DIR//\\//}"
OUTFILE_NSI="${INSTALLER_PATH//\\//}"

sed \
  -e "s|@ROOT@|${ROOT_NSI}|g" \
  -e "s|@RELEASE_DIR@|${RELEASE_DIR_NSI}|g" \
  -e "s|@STAGING_DIR@|${STAGING_DIR_NSI}|g" \
  -e "s|@OUTFILE@|${OUTFILE_NSI}|g" \
  -e "s|@VERSION@|${VERSION}|g" \
  -e "s|@VERSION_QUAD@|${VERSION_QUAD}|g" \
  -e "s|@COPYRIGHT_YEAR@|${COPYRIGHT_YEAR}|g" \
  "$NSI_TEMPLATE" > "$NSI_GENERATED"

echo "=== Building beta Windows installer ==="
echo "Binaries: ${RELEASE_DIR}"
echo "Output:   ${INSTALLER_PATH}"
makensis -V2 "$NSI_GENERATED"

ls -lh "$INSTALLER_PATH"
echo "=== Beta Windows installer ready ==="
