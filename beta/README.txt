Vericoin 2.1.1 Beta
========================
Version: 2.1.1

2.1.1 baseline: clean 2.0.1 chain logic plus QoL upgrades only.
No IBD/catch-up PoST attestation changes from the 2.1.0 beta line.

Build with: Build-Scripts/build-beta-release.sh (all platforms)
             Build-Scripts/build-beta-macos.sh (macOS only)
             Build-Scripts/build-beta-windows-only.sh (Windows only)

Binary artifacts (*.tar.gz, *.exe, *.dmg) are not committed — build locally or
download from GitHub releases when published.

Contents (after build)
----------------------
linux64/   vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet
macos/     Vericoin.app, .dmg, .tar.gz
windows/   release/ binaries + Vericoin-2.1.1-beta-win64-setup-unsigned.exe

Changes in 2.1.1
----------------
- Qt 5.15.14, OpenSSL 1.1.1w, updated depends/build scripts
- Bootstrap download/apply with P2P pause and startup install
- Dark mode (Settings → Display), shared Vericonomy wallet styling
- HTTPS bootstrap downloads (bundled Mozilla CA via curlssl)
- Orphan-stake reorg fix (in-memory undo cache + Ser fix)
- UI polish: tx status icons, tab clip, macOS Exit, dialog QSS (Fusion)
