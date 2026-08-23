// Copyright (c) 2026 The Vericoin developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <util/devtrace.h>

#if defined(HAVE_CONFIG_H) && defined(DEV_EDITION_MAX_VERBOSITY) && DEV_EDITION_MAX_VERBOSITY

#include <node/context.h>
#include <scheduler.h>
#include <util/activitylog.h>
#include <shutdown.h>
#include <sync.h>
#include <util/devedition.h>
#include <util/system.h>
#include <validation.h>

void ApplyDevMaxTraceLoggingDefaults()
{
    if (!IsDeveloperEditionActive())
        return;

    if (!gArgs.IsArgSet("-debug")) {
        LogInstance().EnableCategory("all");
    }
    if (!gArgs.IsArgSet("-logthreadnames")) {
#ifdef HAVE_THREAD_LOCAL
        LogInstance().m_log_threadnames = true;
#endif
    }
    if (!gArgs.IsArgSet("-logtimemicros")) {
        LogInstance().m_log_time_micros = true;
    }
    gArgs.SoftSetBoolArg("-shrinkdebugfile", false);

    LogActivityEx(ActivityLevel::Info, __FILE__, __LINE__, __func__,
        "Dev max trace: -debug=all, logthreadnames, logtimemicros, shrinkdebugfile=0 (unless overridden)");
}

void StartDevMaxTraceHeartbeat(NodeContext& node)
{
    if (!IsDeveloperEditionActive() || !node.scheduler)
        return;

    node.scheduler->scheduleEvery([]() {
        int height = -1;
        uint256 tip_hash;
        {
            LOCK(cs_main);
            if (ChainActive().Tip()) {
                height = ChainActive().Height();
                tip_hash = ChainActive().Tip()->GetBlockHash();
            }
        }
        LogActivity("heartbeat: chain_height=%d tip=%s shutdown=%s",
            height,
            tip_hash.IsNull() ? "none" : tip_hash.ToString().c_str(),
            ShutdownRequested() ? "yes" : "no");
    }, std::chrono::seconds{15});
}

#endif // DEV_EDITION_MAX_VERBOSITY
