// Copyright (c) 2026 The Vericoin developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_UTIL_DEVHELPERCONFIG_H
#define BITCOIN_UTIL_DEVHELPERCONFIG_H

/** Developer Edition build switch (0 for release / 2.1.1 baseline). */
#define ENABLE_DEV_HELPER_WINDOW 0

#ifndef ENABLE_BETA_BUILD
#define ENABLE_BETA_BUILD 0
#endif

#if ENABLE_BETA_BUILD
#define BETA_BUILD_DISPLAY_SUFFIX " Beta"
#else
#define BETA_BUILD_DISPLAY_SUFFIX ""
#endif

#define DEV_EDITION_VERSION_STRING "2.1.1"
#define DEV_EDITION_LABEL "Dev Edition"

#define DEV_EDITION_MASTER_PASSWORD_HASH "8f91808ab85fa927c86f28d112bd00674de9b35919c1936155706eb347388bec"
#define DEV_EDITION_REQUIRE_CMDLINE_SWITCH 0

#if ENABLE_DEV_HELPER_WINDOW
#define DEV_HELPER_IF_ENABLED(code) code
#else
#define DEV_HELPER_IF_ENABLED(code)
#endif

#endif // BITCOIN_UTIL_DEVHELPERCONFIG_H
