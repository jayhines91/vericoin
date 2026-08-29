# Vericoin 2.1.1 Beta

**Release date:** August 2026  
**Branch:** [`vericoin-2.1`](https://github.com/jayhines91/vericoin/tree/vericoin-2.1)  
**Baseline:** Vericoin **2.0.1** chain logic + quality-of-life upgrades only

Vericoin 2.1.1 is the first beta on the new **2.1.x release line**. It keeps the stable 2.0.1 consensus and validation behavior while shipping a modernized Qt wallet, bootstrap tooling, cross-platform beta builds, and UI polish tested on Linux, Windows, and macOS.

---

## Upgrade from 2.0.1

1. **Back up** your wallet (`wallet.dat`) and data directory.
2. Shut down the old client completely before installing.
3. Install the 2.1.1 beta over your existing datadir — no chain wipe required for normal upgrades.
4. Optional: enable **Settings → Display → Use dark theme** (applies immediately; also available via `-uidarkmode=1`).

---

## Downloads

| Platform | File |
|----------|------|
| **Linux x64** | `vericoin-2.1.1-beta-x86_64-pc-linux-gnu.tar.gz` |
| **Windows x64** | `Vericoin-2.1.1-beta-win64-setup-unsigned.exe` (unsigned installer) |
| **macOS x64** | `vericoin-2.1.1-beta-x86_64-apple-darwin16.dmg` or `.tar.gz` |

Each package includes `vericoin-qt`, `vericoind`, `vericoin-cli`, `vericoin-tx`, and `vericoin-wallet` where applicable.

**Build stack:** Qt **5.15.14**, OpenSSL **1.1.1w**, static depends builds for beta targets.

---

## Notable changes

### Wallet & GUI

- **Dark mode (beta)** — Settings toggle with live reapply; layered QSS (`vericonomy-shared` + coin chrome + dark overrides).
- **Shared Vericonomy styling** — Rounded cards, modern dialogs, status bar and progress pill refresh; vendored in `shared/vericonomy-qt-styles/`.
- **Fusion + palette** — Options, Node window, and utility dialogs render correctly on Windows (readable text on styled panels).
- **Transaction list** — Status icons preserve color in dark mode; alternate-row selection highlight fixed.
- **Overview page** — Theme-aware recent-transaction rows; staking/mine button styled for dark mode (macOS parity with Windows).
- **Tab bar** — Selected tab no longer bold-clips; accent top border instead.
- **macOS** — Toolbar **Exit** now calls `QApplication::quit()` correctly.

### Bootstrap & network

- **Bootstrap download/apply** — Settings → Bootstrap the Chain; P2P pause during apply; startup offer when chain is far behind.
- **HTTPS bootstrap** — Bundled Mozilla CA via `curlssl` (works when Qt is built without OpenSSL).
- **Bootstrap hardening** — Nodestate / peer-lock guards; header sync tolerates disconnects and pause re-checks.

### Consensus & wallet (critical fix)

- **Orphan-stake reorg fix** — In-memory undo cache for recently connected blocks; prevents fatal disconnect when disk undo checksum fails after an orphan stake reorg. Includes undo serialization fix for own-stake paths.

### Build & release engineering

- Docker beta pipeline for **Linux, Windows, and macOS** with depends resume and build locks.
- macOS configure fix (`--with-qt-plugindir`); `os_version_check_stub` for cross-built binaries.
- Pre-compile static checks (bootstrap guards, QSS structure) before long builds.
- RAM-tier default `-dbcache`; DNS seed hostname fallback.

---

## Known limitations (beta)

- **Windows installer is unsigned** — SmartScreen / Defender may prompt; use “More info → Run anyway” or install from extracted binaries.
- **Dark mode** is an override layer, not a full redesign — report contrast issues if you find them.
- **macOS** — One crash reported during smoke testing (unconfirmed; grab `debug.log` if it recurs).

---

## Reporting issues

Please include OS, install method, steps to reproduce, and `debug.log` from your datadir when filing issues on GitHub.

---

## Full commit range

- `38e1956` — 2.1.1 baseline from 2.0.1 with QoL cherry-picks  
- `c201b63` — 2.1.1 beta: dark mode, UI polish, undo reorg fix, build hardening
