#!/bin/bash
# Static checks run before configure/compile. Exit non-zero on failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  OK  $desc"
    else
        echo "  FAIL  $desc" >&2
        failures=$((failures + 1))
    fi
}

echo "=== Pre-compile checks ==="

# Bootstrap: avoid crashes when pausing P2P during download/sync.
check "bootstrap FinalizeNode tolerates missing nodestate" \
    rg -q 'FinalizeNode: missing nodestate' src/net_processing.cpp

check "bootstrap DisconnectNodes deletes peers under cs_vNodes" \
    rg -q 'cannot finalize the same peer twice' src/net.cpp

check "bootstrap headers skip when pindexLast unset" \
    rg -q 'if \(!pindexLast\)' src/net_processing.cpp && \
    rg -A1 'if \(!pindexLast\)' src/net_processing.cpp | rg -q 'return true'

check "bootstrap headers tolerate peer disconnect mid-flight" \
    rg -q 'Peer disconnected while headers were processed' src/net_processing.cpp

check "bootstrap headers re-check pause before ProcessNewBlockHeaders" \
    test "$(rg -c 'IsChainSyncPausedForBootstrap\(\)' src/net_processing.cpp)" -ge 2

check "bootstrap chain sync pause in validation" \
    rg -q 'IsChainSyncPausedForBootstrap' src/validation.cpp

# GUI: shared Vericonomy styling (VRC + VRM, all platforms).
check "shared QSS source of truth exists" \
    test -f ../shared/vericonomy-qt-styles/vericonomy-shared.qss

check "vericoin res symlinks to shared QSS" \
    test -L src/qt/res/vericonomy-shared.qss && \
    test -L src/qt/res/vrc-chrome.qss

check "shared status bar uses sidebar gray #586A7A" \
    rg -q 'QStatusBar::item' src/qt/res/vericonomy-shared.qss && \
    rg -q 'border: none' src/qt/res/vericonomy-shared.qss && \
    rg -A8 'QWidget#statusBar' src/qt/res/vericonomy-shared.qss | rg -q '#586A7A'

check "shared sync progress bar structure" \
    rg -q 'QProgressBar#syncProgressBar' src/qt/res/vericonomy-shared.qss && \
    rg -q 'border-radius: 10px' src/qt/res/vericonomy-shared.qss

check "vericonomy-shared sidebar uses #586A7A" \
    rg -q 'QToolBar#mainToolBar' -A2 src/qt/res/vericonomy-shared.qss && \
    rg -q '#586A7A' src/qt/res/vericonomy-shared.qss

check "stylesheet applied on QApplication (all OS)" \
    rg -q 'qApp->setStyleSheet\(GUIUtil::LoadWalletStyleSheet\(\)\)' src/qt/bitcoin.cpp

check "vrc-chrome progress chunk tint" \
    rg -q 'QProgressBar#syncProgressBar::chunk' src/qt/res/vrc-chrome.qss

check "vrm-chrome progress chunk tint" \
    rg -q 'QProgressBar#syncProgressBar::chunk' src/qt/res/vrm-chrome.qss

# Static release linkage helpers (Linux + macOS beta tarballs).
check "fix_depends_static_linkage helper" \
    rg -q 'fix_depends_static_linkage\(\)' Build-Scripts/build-common.sh

check "Linux static verify script" \
    test -x Build-Scripts/verify-static-linux.sh

check "macOS static verify script" \
    test -x Build-Scripts/verify-static-macos.sh

check "curl depends postprocess strips brotli" \
    rg -q 'lbrotlidec' depends/packages/curl.mk

check "openssl depends postprocess removes shared libs" \
    rg -q 'libssl.so' depends/packages/openssl.mk

if [ "$failures" -ne 0 ]; then
    echo "=== Pre-compile checks FAILED ($failures) ===" >&2
    exit 1
fi

echo "=== Pre-compile checks passed ==="
