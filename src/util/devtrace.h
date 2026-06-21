// Copyright (c) 2026 The Vericoin developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_UTIL_DEVTRACE_H
#define BITCOIN_UTIL_DEVTRACE_H

#include <logging.h>

#if defined(HAVE_CONFIG_H)
#include <config/bitcoin-config.h>
#endif

struct NodeContext;

#if defined(HAVE_CONFIG_H) && defined(DEV_EDITION_MAX_VERBOSITY) && DEV_EDITION_MAX_VERBOSITY
#include <util/activitylog.h>

void ApplyDevMaxTraceLoggingDefaults();
void StartDevMaxTraceHeartbeat(NodeContext& node);

#define LogConsensus(...)                                                      \
    do {                                                                       \
        LogPrint(BCLog::CONSENSUS, __VA_ARGS__);                               \
        LogActivityEx(ActivityLevel::Info, __FILE__, __LINE__, __func__,         \
            __VA_ARGS__);                                                      \
    } while (0)
#else
inline void ApplyDevMaxTraceLoggingDefaults() {}
inline void StartDevMaxTraceHeartbeat(NodeContext&) {}
#define LogConsensus(...) LogPrint(BCLog::CONSENSUS, __VA_ARGS__)
#endif

#endif // BITCOIN_UTIL_DEVTRACE_H
