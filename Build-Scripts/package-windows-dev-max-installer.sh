#!/bin/bash
# Package a Windows NSIS installer for the Developer Edition Max Trace build.
#
# Uses unstripped binaries from out-windows-dev-max/
# Default install dir: Program Files\Vericoin Developer Edition Max Trace
#
# Usage:
#   ./Build-Scripts/package-windows-dev-max-installer.sh
#   ./Build-Scripts/package-windows-dev-max-installer.sh /path/to/repo
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
BINARY_DIR="${BINARY_DIR:-${ROOT}/out-windows-dev-max}"
STAGING_DIR="${STAGING_DIR:-${ROOT}/installer-windows-dev-max/staging}"
OUT_DIR="${OUT_DIR:-${ROOT}/out-windows-dev-max}"
NSI_TEMPLATE="${ROOT}/share/setup-dev-max.nsi.in"
NSI_GENERATED="${ROOT}/installer-windows-dev-max/setup-dev-max.nsi"

if ! grep -q '^#define ENABLE_DEV_HELPER_WINDOW 1' "${ROOT}/src/util/devhelperconfig.h" 2>/dev/null; then
  echo "ERROR: Max Trace packaging requires ENABLE_DEV_HELPER_WINDOW 1 in src/util/devhelperconfig.h" >&2
  exit 1
fi

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
INSTALLER_NAME="Vericoin-${VERSION}-DeveloperEditionMaxTrace-win64-setup-unsigned.exe"
INSTALLER_PATH="${OUT_DIR}/${INSTALLER_NAME}"

REQUIRED_BINARIES=(
  vericoin-qt.exe
  vericoind.exe
  vericoin-cli.exe
  vericoin-tx.exe
  vericoin-wallet.exe
)

for bin in "${REQUIRED_BINARIES[@]}"; do
  if [ ! -f "${BINARY_DIR}/${bin}" ]; then
    echo "ERROR: missing ${BINARY_DIR}/${bin}" >&2
    echo "       Run Build-Scripts/build-windows-dev-max-docker.sh first." >&2
    exit 1
  fi
done

if ! command -v makensis >/dev/null 2>&1; then
  echo "ERROR: makensis not found (install NSIS)" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR" "$OUT_DIR" "$(dirname "$NSI_GENERATED")"

cat > "${STAGING_DIR}/DEV_EDITION_windows.txt" <<EOF
Vericoin Developer Edition Max Trace — maximum local debugging build
Version: ${VERSION}
NOT for distribution to coin holders.

Install location
----------------
Program Files\\Vericoin Developer Edition Max Trace

Separate from the standard Developer Edition and public release installs.

Logging (enabled by default in this build)
------------------------------------------
-debug=all (all log categories unless you override on the command line)
-logthreadnames=1
-logtimemicros=1
-shrinkdebugfile=0
-consensus category mirrored to activity.log
-15s heartbeat lines in activity.log (chain height / shutdown state)

Developer tools
---------------
Verbose Dev Trace window on startup. Default master password: VeriDev225!

Build flags
-----------
ENABLE_DEV_HELPER_WINDOW=1, --enable-debug, --enable-dev-max-trace
EOF

ROOT_NSI="${ROOT//\\//}"
BINARY_DIR_NSI="${BINARY_DIR//\\//}"
STAGING_DIR_NSI="${STAGING_DIR//\\//}"
OUTFILE_NSI="${INSTALLER_PATH//\\//}"

sed \
  -e "s|@ROOT@|${ROOT_NSI}|g" \
  -e "s|@BINARY_DIR@|${BINARY_DIR_NSI}|g" \
  -e "s|@STAGING_DIR@|${STAGING_DIR_NSI}|g" \
  -e "s|@OUTFILE@|${OUTFILE_NSI}|g" \
  -e "s|@VERSION@|${VERSION}|g" \
  -e "s|@VERSION_QUAD@|${VERSION_QUAD}|g" \
  -e "s|@COPYRIGHT_YEAR@|${COPYRIGHT_YEAR}|g" \
  "$NSI_TEMPLATE" > "$NSI_GENERATED"

echo "=== Building Developer Edition Max Trace Windows installer ==="
echo "Binaries: ${BINARY_DIR}"
echo "Output:   ${INSTALLER_PATH}"
makensis -V2 "$NSI_GENERATED"

ls -lh "$INSTALLER_PATH"
echo "=== Developer Edition Max Trace installer ready ==="
