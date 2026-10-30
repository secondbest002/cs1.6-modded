/*
 * ==============================================================================
 * CS2 MODERN MECHANICS UNIFIED ENGINE (Master Orchestrator)
 * ==============================================================================
 * Architecture: Modular Component Framework
 * Master Plugin: cs2_modern_engine.sma -> cs2_modern_engine.amxx
 *
 * Sub-modules (.inl):
 *   1. mod_kill_feedback.inl  - Chimes 1K-5K ACE, HS Dink, HUD Cards, C4 10s Music
 *   2. mod_kill_reward.inl    - CS2 Per-Weapon Cash Economy Rewards
 *   3. mod_modern_utility.inl - 3-Way Throw, Smoke Tracers & Dispersion, Drop, Refund
 *   4. mod_weapon_pickup.inl  - E-Key +USE Raytrace Weapon Pickup & Smart Swap
 *   5. mod_arm_switcher.inl   - Switchhands & Redraw Deploy Animation & Cloth Foley
 *   6. mod_ammo_refill.inl    - Auto Free Reserve Ammo & Round Start Clip Refill
 *   7. mod_usps_silencer.inl  - USP-S Permanent Silencer Lock & Auto-Attach
 *   8. mod_knife_sounds.inl   - Dynamic Knife Sounds (Deploy, Inspect, Stab)
 *   9. mod_smart_ping.inl     - 3D Contextual Smart Ping & Dynamic Distance HUD
 *  10. mod_silent_reload.inl  - CS2 Rush Hour Hold-R Silent Reload (2x duration, 100% silent)
 * ==============================================================================
 */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <xs>
#include <fun>

// ==============================================================================
// CS2 MODERN ENGINE - COMPILE-TIME MODULE SWITCHBOARD
// Comment out any module (#define) to disable/isolate it during compilation!
// Modules are 100% independent with strict prefixes and partitioned Task IDs.
// ==============================================================================
#define ENABLE_MODULE_KILL_FEEDBACK
#define ENABLE_MODULE_KILL_REWARD
#define ENABLE_MODULE_MODERN_UTILITY
#define ENABLE_MODULE_WEAPON_PICKUP
#define ENABLE_MODULE_ARM_SWITCHER
#define ENABLE_MODULE_AMMO_REFILL
#define ENABLE_MODULE_USPS_SILENCER
#define ENABLE_MODULE_KNIFE_SOUNDS
#define ENABLE_MODULE_SMART_PING
//#define ENABLE_MODULE_SILENT_RELOAD

#include "cs2_engine/core/cs2_engine_defs.inc"
#include "cs2_engine/core/cs2_engine_taskids.inc"

// Master Engine Global CVar
new pCvar_MasterEnable;

// ==============================================================================
// Conditional Inclusion of Sub-Modules
// ==============================================================================
#if defined ENABLE_MODULE_KILL_FEEDBACK
    #include "cs2_engine/modules/mod_kill_feedback.inl"
#endif

#if defined ENABLE_MODULE_KILL_REWARD
    #include "cs2_engine/modules/mod_kill_reward.inl"
#endif

#if defined ENABLE_MODULE_MODERN_UTILITY
    #include "cs2_engine/modules/mod_modern_utility.inl"
#endif

#if defined ENABLE_MODULE_WEAPON_PICKUP
    #include "cs2_engine/modules/mod_weapon_pickup.inl"
#endif

#if defined ENABLE_MODULE_ARM_SWITCHER
    #include "cs2_engine/modules/mod_arm_switcher.inl"
#endif

#if defined ENABLE_MODULE_AMMO_REFILL
    #include "cs2_engine/modules/mod_ammo_refill.inl"
#endif

#if defined ENABLE_MODULE_USPS_SILENCER
    #include "cs2_engine/modules/mod_usps_silencer.inl"
#endif

#if defined ENABLE_MODULE_KNIFE_SOUNDS
    #include "cs2_engine/modules/mod_knife_sounds.inl"
#endif

#if defined ENABLE_MODULE_SMART_PING
    #include "cs2_engine/modules/mod_smart_ping.inl"
#endif

#if defined ENABLE_MODULE_SILENT_RELOAD
    #include "cs2_engine/modules/mod_silent_reload.inl"
#endif

// ==============================================================================
// Master Lifecycle Dispatchers
// ==============================================================================
public plugin_init()
{
    register_plugin("CS2 Modern Mechanics Unified Engine", CS2_ENGINE_VERSION, CS2_ENGINE_AUTHOR);

    pCvar_MasterEnable = register_cvar("amx_cs2_engine", "1");

    // Master Event Registrations
    register_event("HLTV", "Event_MasterNewRound", "a", "1=0", "2=0");
    register_logevent("Event_MasterRoundEnd", 2, "1=Round_End");
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_MasterPost", 1);

    // Dispatch Init to All Enabled Modules
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_Init();
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_Init();
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_Init();
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_Init();
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_Init();
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_Init();
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_Init();
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_Init();
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_Init();
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_Init();
    #endif

    server_print("[CS2 Engine] Master Orchestrator initialized successfully.");
}

public plugin_cfg()
{
    new szCfgFile[128];
    get_configsdir(szCfgFile, charsmax(szCfgFile));
    format(szCfgFile, charsmax(szCfgFile), "%s/cs2_modern_engine.cfg", szCfgFile);
    if (file_exists(szCfgFile))
    {
        server_cmd("exec %s", szCfgFile);
        server_exec();
    }
}

public plugin_precache()
{
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_Precache();
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_Precache();
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_Precache();
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_Precache();
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_Precache();
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_Precache();
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_Precache();
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_Precache();
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_Precache();
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_Precache();
    #endif
}

public client_putinserver(id)
{
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_PutInServer(id);
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_PutInServer(id);
    #endif
}

public client_disconnected(id)
{
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_Disconnect(id);
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_Disconnect(id);
    #endif
}

public OnPlayerSpawn_MasterPost(id)
{
    if (!is_user_alive(id))
        return HAM_IGNORED;

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_Spawn(id);
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_Spawn(id);
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_Spawn(id);
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_Spawn(id);
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_Spawn(id);
    #endif

    return HAM_IGNORED;
}

public Event_MasterNewRound()
{
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_NewRound();
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_NewRound();
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_NewRound();
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_NewRound();
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_NewRound();
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_NewRound();
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_NewRound();
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_NewRound();
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_NewRound();
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_NewRound();
    #endif
}

public Event_MasterRoundEnd()
{
    #if defined ENABLE_MODULE_KILL_FEEDBACK
    Mod_KillFeedback_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_KILL_REWARD
    Mod_KillReward_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_MODERN_UTILITY
    Mod_ModernUtility_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_WEAPON_PICKUP
    Mod_WeaponPickup_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_ARM_SWITCHER
    Mod_ArmSwitcher_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_AMMO_REFILL
    Mod_AmmoRefill_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_USPS_SILENCER
    Mod_USPSSilencer_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_KNIFE_SOUNDS
    Mod_KnifeSounds_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_SMART_PING
    Mod_SmartPing_RoundEnd();
    #endif

    #if defined ENABLE_MODULE_SILENT_RELOAD
    Mod_SilentReload_RoundEnd();
    #endif
}
