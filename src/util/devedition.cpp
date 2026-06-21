// Copyright (c) 2026 The Vericoin developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <util/devedition.h>

#include <crypto/sha256.h>
#include <util/activitylog.h>
#if defined(HAVE_CONFIG_H)
#include <config/bitcoin-config.h>
#endif
#include <util/devhelperconfig.h>
#include <util/strencodings.h>
#include <util/system.h>

static bool g_dev_tools_unlocked = false;
static bool g_dev_startup_prompt_complete = false;

bool IsDevStartupPromptComplete()
{
    return g_dev_startup_prompt_complete;
}

void MarkDevStartupPromptComplete()
{
    g_dev_startup_prompt_complete = true;
}

bool IsDeveloperEditionBuild()
{
#if ENABLE_DEV_HELPER_WINDOW
    return true;
#else
    return false;
#endif
}

bool IsDeveloperEditionActive()
{
#if !ENABLE_DEV_HELPER_WINDOW
    return false;
#else
#if DEV_EDITION_REQUIRE_CMDLINE_SWITCH
    return gArgs.GetBoolArg("-devedition", false);
#else
    return true;
#endif
#endif
}

bool IsDevToolsUnlocked()
{
    return IsDeveloperEditionActive() && g_dev_tools_unlocked;
}

bool UnlockDevToolsWithPassword(const std::string& password)
{
#if !ENABLE_DEV_HELPER_WINDOW
    return false;
#else
    if (!IsDeveloperEditionActive())
        return false;

    CSHA256 hasher;
    hasher.Write(reinterpret_cast<const unsigned char*>(password.data()), password.size());
    unsigned char hash[CSHA256::OUTPUT_SIZE];
    hasher.Finalize(hash);
    const std::string hex = HexStr(hash, hash + CSHA256::OUTPUT_SIZE);

    if (hex != DEV_EDITION_MASTER_PASSWORD_HASH) {
        LogActivityEx(ActivityLevel::Warning, __FILE__, __LINE__, __func__, "Developer tools unlock failed (bad password)");
        return false;
    }

    g_dev_tools_unlocked = true;
    LogActivityEx(ActivityLevel::Info, __FILE__, __LINE__, __func__, "Developer tools unlocked");
    return true;
#endif
}

void LockDevTools()
{
    if (g_dev_tools_unlocked) {
        g_dev_tools_unlocked = false;
        LogActivityEx(ActivityLevel::Info, __FILE__, __LINE__, __func__, "Developer tools locked");
    }
}

std::string GetDeveloperEditionVersionString()
{
#if ENABLE_DEV_HELPER_WINDOW
    if (IsDeveloperEditionActive()) {
#if defined(DEV_EDITION_MAX_VERBOSITY) && DEV_EDITION_MAX_VERBOSITY
        return std::string(DEV_EDITION_VERSION_STRING) + " Dev Max Trace";
#else
        return std::string(DEV_EDITION_VERSION_STRING) + " " + DEV_EDITION_LABEL;
#endif
    }
#endif
    return {};
}

std::string GetDeveloperEditionTitle()
{
#if ENABLE_DEV_HELPER_WINDOW
    if (IsDeveloperEditionActive()) {
#if defined(DEV_EDITION_MAX_VERBOSITY) && DEV_EDITION_MAX_VERBOSITY
        return std::string("Vericoin ") + DEV_EDITION_VERSION_STRING + " Dev Max Trace";
#else
        return std::string("Vericoin ") + DEV_EDITION_VERSION_STRING + " " + DEV_EDITION_LABEL;
#endif
    }
#endif
    return {};
}
