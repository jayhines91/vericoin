Vericoin Beta Release Build
===========================
Version: 2.2.5
Built: 2026-06-14 13:18:21 UTC
Status: VALIDATED on 3 Windows test boxes (sync + stable peers, Jun 2026)

Contents
--------
linux64/
  vericoin-qt, vericoind, vericoin-cli, vericoin-tx, vericoin-wallet
  vericoin-2.2.5-beta-x86_64-pc-linux-gnu.tar.gz  (installer)

windows/
  Unstripped .exe binaries
  release/  stripped binaries used by the installer
  Vericoin-2.2.5-beta-win64-setup-unsigned.exe  (installer)

Dependency versions (from preseed)
----------------------------------
Linux Qt:   5.15.14
Windows Qt: 5.15.14
OpenSSL:    1.1.1w

Validated changes (include in upcoming betas)
---------------------------------------------
- Qt upgraded to 5.15.14
- OpenSSL upgraded to 1.1.1w
- Wallet startup deadlock fixes (lock order, postInitProcess timing)
- Bootstrap pindexLast assert fix during sync pause
- Bootstrap download progress throttling + 1 MB write buffer (UI stutter)
- Splash/window title show "Beta" for identification
- About dialog: copyright 2009-2026, veribase source line removed

Build script: Build-Scripts/build-beta-release.sh
