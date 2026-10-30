/**
 * ==============================================================================
 * Plugin: CS 1.6 Bot Savage & Predator AI Engine (Version 3.4 - Tactical Chat & Danger Callouts)
 * Version: 3.4.0
 * Author: Antigravity
 * Description:
 *   Elevates YAPB / CS 1.6 bots into disciplined, coordinated Tier-1 Esports combatants.
 *
 *   New Tactical & Synchronization Systems (v3.4):
 *     1. Esports Player-to-Bot Chat Communication Engine (Full English Esports Persona Responses).
 *     2. Dynamic 'care [zone]' System (care a, care b, care short, care long, care mid, care awp, care flank).
 *     3. On-Demand Tactical Utility Coordination (flash me, popflash, smoke choke/cross).
 *     4. Real-Time Objective & C4 Management (drop c4/bomb, rotate a/b, save guns, cover defuse).
 *     5. Interactive Squad Intel & Economy Queries (utility?, money?, status?, damage?).
 *     6. Squad Pacing & Stealth Synchronization (walk/shift silent pacing, hold passive angles).
 *
 *   Preserved Core Systems:
 *     7. Dynamic Weapon Scavenging & Round-End Opportunity Hunting.
 *     8. Freeze Time Role Priority Delivery & Esports Role Economy.
 *     9. Competitive 5-Role Architecture & Player Menu (/role).
 *    10. Common Angle & Holding Angle Engine (Head-level crosshair lock & pre-scope).
 *    11. Interactive Weapon Drop Engine ('drop', /drop, radio Need backup).
 *    12. Instant Counter-Strafing & Spray Recoil Compensation.
 *    13. Auditory Sound ESP & Predictive Wallbang.
 *    14. Instant Trade-Frag Snapping & Anti-Flash 180° Reflex.
 *    15. High-IQ Fake Defuse Ambush & Synchronized Double-Peek.
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

#define PLUGIN_NAME    "Bot Savage Predator AI v3"
#define PLUGIN_VERSION "3.4.0"
#define PLUGIN_AUTHOR  "Antigravity"

#define TASK_GRENADE_CHECK    2048
#define TASK_SOUND_SCANNER     2049
#define TASK_ECONOMY_DROP      2050
#define TASK_ROLE_MENU         2051
#define TASK_TACTICAL_CALL     2052
#define TASK_ENFORCE_LOADOUTS  2053
#define TASK_ROLE_DELIVER      2054
#define TASK_SCAVENGE_SCAN     2055
#define TASK_SCAN_SPAWN_WPNS   2056

// Competitive 5-Role Enum
enum {
    ROLE_NONE = 0,
    ROLE_ENTRY,    // Entry Fragger: Aggressive push, first contact, wide swing, high triggerbot
    ROLE_AWPER,    // Sniper/AWPer: Long angles, pre-scoped holding, deagle backup
    ROLE_SUPPORT,  // Support/Utility: Stays near Entry, throws utility, buys kit, drops weapons, trades frags
    ROLE_LURKER,   // Lurker / Site Anchor: Silent walk (shift), flanks or site anchor
    ROLE_IGL       // In-Game Leader: Calls strats in freeze time, coordinates team radio
};

new const g_szRoleNames[][] = {
    "Unassigned",
    "Entry Fragger",
    "AWPer",
    "Support",
    "Lurker / Anchor",
    "IGL"
};

new const g_szRoleTags[][] = {
    "[NONE]",
    "[Entry]",
    "[AWPer]",
    "[Support]",
    "[Lurker]",
    "[IGL]"
};

// Strategic Calls Enum
enum {
    STRAT_NONE = 0,
    STRAT_RUSH_A,
    STRAT_RUSH_B,
    STRAT_DEFAULT,
    STRAT_SPLIT,
    STRAT_ECO
};

new const g_szStratNames[][] = {
    "None",
    "Fast Rush Bombsite A",
    "Execute Bombsite B",
    "Default 1-3-1 (Hold for Picks)",
    "Split Mid to Site",
    "Full Eco / Group Save"
};

// CVAR Pointers - Core
new g_pCvarEnable;
new g_pCvarCounterStrafe;
new g_pCvarJiggle;
new g_pCvarTradeFrag;
new g_pCvarAntiFlash;
new g_pCvarTriggerbot;
new g_pCvarHiveMind;
new g_pCvarReloadCover;

// CVAR Pointers - Combat & Movement
new g_pCvarRecoil;
new g_pCvarBhop;
new g_pCvarWallbang;
new g_pCvarDoublePeek;
new g_pCvarFakeDefuse;
new g_pCvarJumpScout;
new g_pCvarDropGuns;

// CVAR Pointers - Competitive & Tactics
new g_pCvarRoles;
new g_pCvarHolding;
new g_pCvarCalls;
new g_pCvarKnifeMidBrawl;
new g_pCvarKnifeRoundActive;
new g_pCvarWeaponScavenge;
new g_pCvarRoleDeliver;
new g_pCvarChatCalls;
new g_pCvarChatCooldown;

// Danger & Care Zones Enum (v3.4)
enum {
    ZONE_NONE = 0,
    ZONE_SITE_A,
    ZONE_SITE_B,
    ZONE_MID,
    ZONE_SHORT,
    ZONE_LONG,
    ZONE_FLANK,
    ZONE_AWP,
    ZONE_PUSH
};
new g_iActiveDangerZone[CsTeams];
new Float:g_flDangerZoneExpire[CsTeams];
new Float:g_vecDangerPoint[CsTeams][3];

// Tactical Chat & Pacing State Tracking (v3.4)
new g_iTradeLeader[33];
new Float:g_flTradeFollowUntil[33];
new Float:g_flRearFlankUntil[33];
new Float:g_vecRearFlankAngle[33][3];
new Float:g_flSilentWalkUntil[CsTeams];
new Float:g_flHoldAngleUntil[CsTeams];
new Float:g_flLastChatCallTime[33];

// Damage Tracking for Tactical Intel
new g_iLastDamageTarget[33];
new g_iLastDamageDealt[33];
new Float:g_flLastDamageTime[33];

// State Tracking
new g_iPlayerRole[33];
new bool:g_bRoleSelected[33];
new g_iTeamStrat[CsTeams];
new bool:g_bInFreezeTime = false;
new g_iRoundCount = 0;
new Float:g_flRoundStartTime = 0.0;

// Team Economy Mode Enum & Interactive Calls
enum {
    ECON_NORMAL = 0,
    ECON_ECO,
    ECON_FORCE,
    ECON_HALF,
    ECON_FULL
};
new g_iTeamEconomyCall[CsTeams] = { ECON_NORMAL, ECON_NORMAL, ECON_NORMAL };

// Tactical Mid Lineup & Bombsite Tracking
new bool:g_bMidSmokedThisRound[CsTeams] = { false, false, false };
new bool:g_bMidFlashedThisRound[CsTeams] = { false, false, false };
new Float:g_vecBombsiteA[3];
new Float:g_vecBombsiteB[3];
new bool:g_bBombsitesFound = false;
new Float:g_flLineupThrowUntil[33];
new Float:g_vecLineupAngles[33][3];
new bool:g_bLineupActive[33];

// Saved Weapon & Role Delivery State Tracking
new g_iSavedWeapon[33];
new bool:g_bSavedWeaponForRole[33];
new bool:g_bRoundEnded = false;
new Float:g_flRoundEndTime;
new g_iScavengeTarget[33];
new Float:g_flScavengeExpire[33];
new Float:g_flLastWeaponSwapTime[33];

// Holding Angle State Tracking
new bool:g_bHoldingAngle[33];
new Float:g_flHoldingUntil[33];

// Mid Point & Knife Round Tracking
new Float:g_vecMapMidPoint[3];
new bool:g_bMidPointCalculated;
new Float:g_flKnifeRoundStartTime;
new bool:g_bAntiStallTriggered;

// Combat State Tracking
new Float:g_flLastCombatTime[33];
new Float:g_flNextStrafeSwitch[33];
new Float:g_flNextTriggerCheck[33];
new bool:g_bStrafeDirection[33];
new bool:g_bDuckTapActive[33];
new Float:g_flFlashDodgeUntil[33];

// Trade-Frag State Tracking
new g_iTradeTarget[33];
new Float:g_flTradeExpire[33];

// Hive-Mind Team Intel
new Float:g_vecTeamThreatOrigin[CsTeams][3];
new Float:g_flTeamThreatTime[CsTeams];
new g_iTeamThreatTarget[CsTeams];

// Sound ESP & Wallbang Tracking
new g_iSoundTarget[33];
new Float:g_flSoundTargetExpire[33];
new Float:g_vecSoundTargetOrigin[33][3];
new Float:g_flNextWallbangBurst[33];

// Fake Defuse State Tracking
new bool:g_bDidFakeDefuse[33];
new Float:g_flFakeDefuseAmbushUntil[33];
new Float:g_vecFakeDefuseAmbushAngle[33][3];

// Double-Peek Pair Assignment
new g_iDoublePeekPartner[33];
new bool:g_bIsCrouchPeeker[33];
new Float:g_flDoublePeekExpire[33];

// Tactical Callout Cooldowns
new Float:g_flNextContactCall[CsTeams];
new Float:g_flNextBombCall[CsTeams];

public plugin_precache()
{
    precache_model("models/w_ak47.mdl");
    precache_model("models/w_m4a1.mdl");
    if (file_exists("models/csgo_skins/ct/w_m4a4.mdl") || file_exists("models/csgo_skins/ct/w_m4a4.mdl", true))
        precache_model("models/csgo_skins/ct/w_m4a4.mdl");
    precache_model("models/w_awp.mdl");
    precache_model("models/w_deagle.mdl");
    precache_model("models/w_galil.mdl");
    precache_model("models/w_famas.mdl");
    precache_model("models/w_mp5.mdl");
    precache_model("models/w_scout.mdl");

    // Modern CS weapon models
    if (file_exists("models/pw_models/w_tec9.mdl") || file_exists("models/pw_models/w_tec9.mdl", true))
        precache_model("models/pw_models/w_tec9.mdl");
    if (file_exists("models/pw_models/w_cz75.mdl") || file_exists("models/pw_models/w_cz75.mdl", true))
        precache_model("models/pw_models/w_cz75.mdl");
    if (file_exists("models/pw_models/w_mp7.mdl") || file_exists("models/pw_models/w_mp7.mdl", true))
        precache_model("models/pw_models/w_mp7.mdl");
    if (file_exists("models/pw_models/w_bizon.mdl") || file_exists("models/pw_models/w_bizon.mdl", true))
        precache_model("models/pw_models/w_bizon.mdl");
    if (file_exists("models/pw_models/w_mag7.mdl") || file_exists("models/pw_models/w_mag7.mdl", true))
        precache_model("models/pw_models/w_mag7.mdl");
    if (file_exists("models/pw_models/w_sawedoff.mdl") || file_exists("models/pw_models/w_sawedoff.mdl", true))
        precache_model("models/pw_models/w_sawedoff.mdl");
    if (file_exists("models/pw_models/w_negev.mdl") || file_exists("models/pw_models/w_negev.mdl", true))
        precache_model("models/pw_models/w_negev.mdl");

    precache_sound("items/gunpickup2.wav");
}

public plugin_natives()
{
    register_native("savage_get_player_role", "_native_get_player_role");
}

public _native_get_player_role(plugin_id, num_params)
{
    new id = get_param(1);
    if (id < 1 || id > 32 || !is_user_connected(id))
        return ROLE_NONE;

    if (g_iPlayerRole[id] == ROLE_NONE && is_user_bot(id))
    {
        new CsTeams:team = cs_get_user_team(id);
        if (team == CS_TEAM_T || team == CS_TEAM_CT)
        {
            BalanceTeamRoles(team);
        }
    }
    return g_iPlayerRole[id];
}

public savage_get_bot_role(id)
{
    if (id < 1 || id > 32 || !is_user_connected(id))
        return ROLE_NONE;

    if (g_iPlayerRole[id] == ROLE_NONE && is_user_bot(id))
    {
        new CsTeams:team = cs_get_user_team(id);
        if (team == CS_TEAM_T || team == CS_TEAM_CT)
        {
            BalanceTeamRoles(team);
        }
    }
    return g_iPlayerRole[id];
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // Register Core CVARs
    g_pCvarEnable        = register_cvar("bot_savage_enable", "1");
    g_pCvarCounterStrafe = register_cvar("bot_savage_counterstrafe", "1");
    g_pCvarJiggle        = register_cvar("bot_savage_jiggle", "1");
    g_pCvarTradeFrag     = register_cvar("bot_savage_tradefrag", "1");
    g_pCvarAntiFlash     = register_cvar("bot_savage_antiflash", "1");
    g_pCvarTriggerbot    = register_cvar("bot_savage_triggerbot", "1");
    g_pCvarHiveMind      = register_cvar("bot_savage_hivemind", "1");
    g_pCvarReloadCover   = register_cvar("bot_savage_reloadcover", "1");

    // Register Combat CVARs
    g_pCvarRecoil        = register_cvar("bot_savage_recoil", "1");
    g_pCvarBhop          = register_cvar("bot_savage_bhop", "0"); // Default 0: Clean smooth movement!
    g_pCvarWallbang      = register_cvar("bot_savage_wallbang", "1");
    g_pCvarDoublePeek    = register_cvar("bot_savage_doublepeek", "1");
    g_pCvarFakeDefuse    = register_cvar("bot_savage_fakedefuse", "1");
    g_pCvarJumpScout     = register_cvar("bot_savage_jumpscout", "1");
    g_pCvarDropGuns      = register_cvar("bot_savage_dropguns", "1");

    // Register v3.2 & v3.3 Competitive CVARs
    g_pCvarRoles            = register_cvar("bot_savage_roles", "1");
    g_pCvarHolding          = register_cvar("bot_savage_holding", "1");
    g_pCvarCalls            = register_cvar("bot_savage_calls", "1");
    g_pCvarKnifeMidBrawl    = register_cvar("bot_savage_knife_midbrawl", "1");
    g_pCvarKnifeRoundActive = register_cvar("bot_savage_kniferound", "0");
    g_pCvarWeaponScavenge   = register_cvar("bot_savage_scavenge", "1");
    g_pCvarRoleDeliver      = register_cvar("bot_savage_roledeliver", "1");

    // Register v3.4 Tactical Chat & Callout CVARs
    g_pCvarChatCalls        = register_cvar("bot_savage_chat_calls", "1");
    g_pCvarChatCooldown     = register_cvar("bot_savage_chat_cooldown", "1.5");

    // Chat & Console Commands
    register_clcmd("say", "HandleSay");
    register_clcmd("say_team", "HandleSay");
    register_clcmd("role", "Cmd_OpenRoleMenu");
    register_clcmd("strat", "Cmd_OpenStratMenu");
    register_clcmd("needbackup", "Cmd_RadioNeedBackup");
    register_clcmd("coverme", "Cmd_RadioNeedBackup");
    register_clcmd("drop", "Cmd_PlayerDropWeaponPre");
    register_clcmd("+ping", "Cmd_PlayerPingPointPre");
    register_clcmd("amx_ping", "Cmd_PlayerPingPointPre");
    register_clcmd("ping_point", "Cmd_PlayerPingPointPre");

    // Hook usercmd processing (Every tick for players and bots)
    register_forward(FM_CmdStart, "OnCmdStart");

    // Ham Hooks
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawnPost", 1);
    RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage", 1);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled", 1);
    RegisterHam(Ham_Touch, "info_target", "OnDroppedRifleTouch");
    RegisterHam(Ham_Think, "info_target", "OnDroppedRifleThink");
    RegisterHam(Ham_Touch, "weaponbox", "OnWeaponBoxTouchPre", 0);

    // True Freeze Time & Round Lifecycle Events
    register_event("HLTV", "Event_FreezeTimeStart", "a", "1=0", "2=0");
    register_event("TextMsg", "Event_GameRestart", "a", "2=#Game_will_restart_in", "2=#Game_Commencing");
    register_logevent("Event_RoundStart", 2, "1=Round_Start");
    register_logevent("Event_RoundEnd", 2, "1=Round_End");
    register_event("SendAudio", "Event_RoundEndAudio", "a", "2=%!MRAD_terwin");
    register_event("SendAudio", "Event_RoundEndAudio", "a", "2=%!MRAD_ctwin");
    register_event("SendAudio", "Event_RoundEndAudio", "a", "2=%!MRAD_rounddraw");
    register_logevent("Event_PlantTheBomb", 3, "2=Planted_The_Bomb");
    register_logevent("Event_DefusedTheBomb", 3, "2=Defused_The_Bomb");

    // Periodic safe scanners
    set_task(0.10, "Task_CheckGrenades", TASK_GRENADE_CHECK, _, _, "b");
    set_task(0.15, "Task_SoundESPScanner", TASK_SOUND_SCANNER, _, _, "b");
    set_task(0.35, "Task_ScavengeGroundWeapons", TASK_SCAVENGE_SCAN, _, _, "b");
    set_task(0.30, "Task_TacticalMidLineupScanner", _, _, _, "b");

    server_print("[%s v%s] Activated successfully. Tier-1 Esports AI online.", PLUGIN_NAME, PLUGIN_VERSION);
}

public plugin_cfg()
{
    new szCfgPath[128];
    get_configsdir(szCfgPath, charsmax(szCfgPath));
    format(szCfgPath, charsmax(szCfgPath), "%s/bot_savage_roles.cfg", szCfgPath);

    if (file_exists(szCfgPath))
    {
        server_cmd("exec %s", szCfgPath);
        server_exec();
    }

    InitMapMidPoint();
    InitBombsites();

    // Ensure YaPB follow settings are tuned for full teamplay
    set_cvar_num("yb_user_follow_percent", 100);
    set_cvar_num("yb_user_max_followers", 4);
}

public client_putinserver(id)
{
    ResetBotState(id);
    g_iPlayerRole[id] = ROLE_NONE;
    g_bRoleSelected[id] = false;
}

public client_disconnected(id)
{
    ResetBotState(id);
    g_iPlayerRole[id] = ROLE_NONE;
    g_bRoleSelected[id] = false;
}

ResetBotState(id)
{
    g_flLastCombatTime[id] = 0.0;
    g_flNextStrafeSwitch[id] = 0.0;
    g_flNextTriggerCheck[id] = 0.0;
    g_bStrafeDirection[id] = false;
    g_bDuckTapActive[id] = false;
    g_flFlashDodgeUntil[id] = 0.0;
    g_iTradeTarget[id] = 0;
    g_flTradeExpire[id] = 0.0;

    g_bHoldingAngle[id] = false;
    g_flHoldingUntil[id] = 0.0;

    g_iSoundTarget[id] = 0;
    g_flSoundTargetExpire[id] = 0.0;
    g_flNextWallbangBurst[id] = 0.0;
    g_bDidFakeDefuse[id] = false;
    g_flFakeDefuseAmbushUntil[id] = 0.0;
    g_iDoublePeekPartner[id] = 0;
    g_bIsCrouchPeeker[id] = false;
    g_flDoublePeekExpire[id] = 0.0;

    g_iSavedWeapon[id] = 0;
    g_bSavedWeaponForRole[id] = false;
    g_iScavengeTarget[id] = 0;
    g_flScavengeExpire[id] = 0.0;
    g_flLastWeaponSwapTime[id] = 0.0;

    // Tactical Chat States Reset
    g_iTradeLeader[id] = 0;
    g_flTradeFollowUntil[id] = 0.0;
    g_flRearFlankUntil[id] = 0.0;
    g_flLastChatCallTime[id] = 0.0;
    g_iLastDamageTarget[id] = 0;
    g_iLastDamageDealt[id] = 0;
    g_flLastDamageTime[id] = 0.0;
}

// ==============================================================================
// 1. FREEZE TIME EVENT & IGL STRAT CALLS (At 0.0s Freeze Time)
// ==============================================================================
public Event_GameRestart()
{
    g_iRoundCount = 0;
}

public Event_FreezeTimeStart()
{
    if (IsWarmupActive())
    {
        g_bInFreezeTime = false;
        return;
    }

    g_bInFreezeTime = true;
    g_bRoundEnded = false;

    // Freeze all bots in spawn during freeze time
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i))
        {
            new flags = pev(i, pev_flags);
            set_pev(i, pev_flags, flags | FL_FROZEN);
            set_pev(i, pev_velocity, Float:{0.0, 0.0, 0.0});
        }
    }

    new Float:flGameTime = get_gametime();
    g_flNextContactCall[CS_TEAM_T] = flGameTime;
    g_flNextContactCall[CS_TEAM_CT] = flGameTime;
    g_flNextBombCall[CS_TEAM_T] = flGameTime;
    g_flNextBombCall[CS_TEAM_CT] = flGameTime;

    if (!g_bMidPointCalculated)
    {
        InitMapMidPoint();
    }
    if (!g_bBombsitesFound)
    {
        InitBombsites();
    }

    g_bMidSmokedThisRound[CS_TEAM_T] = false;
    g_bMidSmokedThisRound[CS_TEAM_CT] = false;
    g_bMidFlashedThisRound[CS_TEAM_T] = false;
    g_bMidFlashedThisRound[CS_TEAM_CT] = false;

    // Balance bot roles for both teams
    BalanceTeamRoles(CS_TEAM_T);
    BalanceTeamRoles(CS_TEAM_CT);

    // Reset round-specific states
    g_flSilentWalkUntil[CS_TEAM_T] = 0.0;
    g_flSilentWalkUntil[CS_TEAM_CT] = 0.0;
    g_flHoldAngleUntil[CS_TEAM_T] = 0.0;
    g_flHoldAngleUntil[CS_TEAM_CT] = 0.0;
    g_iActiveDangerZone[CS_TEAM_T] = ZONE_NONE;
    g_iActiveDangerZone[CS_TEAM_CT] = ZONE_NONE;
    g_flDangerZoneExpire[CS_TEAM_T] = 0.0;
    g_flDangerZoneExpire[CS_TEAM_CT] = 0.0;

    for (new i = 1; i <= 32; i++)
    {
        g_bDidFakeDefuse[i] = false;
        g_flFakeDefuseAmbushUntil[i] = 0.0;
        g_iDoublePeekPartner[i] = 0;
        g_bHoldingAngle[i] = false;
        g_flLineupThrowUntil[i] = 0.0;
        g_bLineupActive[i] = false;
        g_flRearFlankUntil[i] = 0.0;
        g_iTradeLeader[i] = 0;
        g_flTradeFollowUntil[i] = 0.0;
    }

    // Check Knife Round Condition
    if (IsKnifeRoundActive())
    {
        g_iRoundCount = 0;
        g_flKnifeRoundStartTime = flGameTime;
        g_bAntiStallTriggered = false;

        // Force YaPB to stop doing bombsite objectives & stop camping!
        set_cvar_num("yb_ignore_objectives", 1);
        set_cvar_num("yb_camping_allowed", 0);
        set_cvar_num("yb_user_follow_percent", 100);
        set_cvar_num("yb_user_max_followers", 4);

        if (get_pcvar_num(g_pCvarKnifeMidBrawl))
        {
            BroadcastTeamCall(CS_TEAM_T, "^4[IGL Knife Call]^3 ⚔ KNIFE ROUND! All units RUSH MID for the brawl! ⚔");
            PlayTeamAudio(CS_TEAM_T, "spk radio/stormfront");

            BroadcastTeamCall(CS_TEAM_CT, "^4[IGL Knife Call]^3 ⚔ KNIFE ROUND! All units RUSH MID for the brawl! ⚔");
            PlayTeamAudio(CS_TEAM_CT, "spk radio/stormfront");
            return;
        }
    }
    else
    {
        g_iRoundCount++;

        // Restore standard competitive objectives for gun rounds
        set_cvar_num("yb_ignore_objectives", 0);
        set_cvar_num("yb_camping_allowed", 1);
    }

    // LIVE MATCH GUN ROUND: Check if human player is IGL
    new bool:bHumanIsIglT = false;
    new bool:bHumanIsIglCT = false;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && g_iPlayerRole[i] == ROLE_IGL)
        {
            new CsTeams:team = cs_get_user_team(i);
            if (team == CS_TEAM_T)
            {
                bHumanIsIglT = true;
                ShowIglStratMenu(i);
            }
            else if (team == CS_TEAM_CT)
            {
                bHumanIsIglCT = true;
                ShowIglStratMenu(i);
            }
        }
    }

    // If IGL is a bot, schedule callout at 0.8s into Freeze Time (while still in spawn!)
    if (get_pcvar_num(g_pCvarCalls))
    {
        if (!bHumanIsIglT)
            set_task(0.8, "Task_AnnounceTStrat", TASK_TACTICAL_CALL);

        if (!bHumanIsIglCT)
            set_task(0.8, "Task_AnnounceCTStrat", TASK_TACTICAL_CALL);
    }

    // Schedule Spawn Dropped Weapon Claiming in Freeze Time (0.4s & 0.9s)
    set_task(0.4, "Task_ScanSpawnDroppedWeapons", TASK_SCAN_SPAWN_WPNS);
    set_task(0.9, "Task_ScanSpawnDroppedWeapons", TASK_SCAN_SPAWN_WPNS);

    // Schedule Role Priority Weapon Delivery at 1.0s into Freeze Time
    if (get_pcvar_num(g_pCvarEnable) && get_pcvar_num(g_pCvarRoleDeliver))
    {
        set_task(1.0, "Task_DeliverSavedWeapons", TASK_ROLE_DELIVER);
    }

    // Schedule Role Loadout Enforcement at 1.4s into Freeze Time
    set_task(1.4, "Task_EnforceRoleLoadouts", TASK_ENFORCE_LOADOUTS);

    // Schedule Team Economy Weapon Drop at 2.0s into Freeze Time
    if (get_pcvar_num(g_pCvarEnable) && get_pcvar_num(g_pCvarDropGuns))
    {
        set_task(2.0, "Task_EconomyWeaponDrop", TASK_ECONOMY_DROP);
    }
}

public Task_AnnounceTStrat()
{
    ExecuteTeamStrat(CS_TEAM_T);
}

public Task_AnnounceCTStrat()
{
    ExecuteTeamStrat(CS_TEAM_CT);
}

ExecuteTeamStrat(CsTeams:team)
{
    new iIgl = GetTeamIgl(team);
    if (iIgl <= 0)
        return;

    new szIglName[32];
    get_user_name(iIgl, szIglName, charsmax(szIglName));

    if (team == CS_TEAM_T)
    {
        new iStrat = random_num(1, 5);
        g_iTeamStrat[team] = iStrat;

        switch (iStrat)
        {
            case STRAT_RUSH_A:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Fast Rush Bombsite A^1! Flash out and take entry!", szIglName);
                PlayTeamAudio(team, "spk radio/stormfront");
            }
            case STRAT_RUSH_B:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Execute Bombsite B^1! Smoke tunnels, stick together!", szIglName);
                PlayTeamAudio(team, "spk radio/go_go_go");
            }
            case STRAT_DEFAULT:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Default 1-3-1 & Hold for Picks^1! Do not rush, play slow!", szIglName);
                PlayTeamAudio(team, "spk radio/sticktog");
            }
            case STRAT_SPLIT:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Split Mid to Bombsite^1! Cut off rotators!", szIglName);
                PlayTeamAudio(team, "spk radio/flankthem");
            }
            case STRAT_ECO:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Eco Stack^1! Group up, hunt for rifle drops!", szIglName);
                PlayTeamAudio(team, "spk radio/regroup");
            }
        }
    }
    else if (team == CS_TEAM_CT)
    {
        new iStrat = random_num(1, 4);
        g_iTeamStrat[team] = iStrat;

        switch (iStrat)
        {
            case 1:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Standard 2-1-2 Crossfire Hold^1! Anchors stay on sites!", szIglName);
                PlayTeamAudio(team, "spk radio/sticktog");
            }
            case 2:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Aggressive Chokepoint Information Push^1!", szIglName);
                PlayTeamAudio(team, "spk radio/stormfront");
            }
            case 3:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Site Stack Defense^1! Fall back and play retake if overwhelmed!", szIglName);
                PlayTeamAudio(team, "spk radio/fallback");
            }
            case 4:
            {
                BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4Eco Crossfire Stack^1! Play close angles with Deagles!", szIglName);
                PlayTeamAudio(team, "spk radio/regroup");
            }
        }
    }
}

// ==============================================================================
// 2. ROUND START (FREEZE TIME ENDS - MOVEMENT UNFREEZES)
// ==============================================================================
public Event_RoundStart()
{
    g_bInFreezeTime = false;
    g_flRoundStartTime = get_gametime();

    g_bMidSmokedThisRound[CS_TEAM_T] = false;
    g_bMidSmokedThisRound[CS_TEAM_CT] = false;
    g_bMidFlashedThisRound[CS_TEAM_T] = false;
    g_bMidFlashedThisRound[CS_TEAM_CT] = false;

    // Unfreeze all bots now that freeze time expired
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i))
        {
            new flags = pev(i, pev_flags);
            set_pev(i, pev_flags, flags & ~FL_FROZEN);
        }
    }

    // Dispatch real engine radio command so YaPB bot engine actually obeys!
    DispatchIglEngineCommand(CS_TEAM_T);
    DispatchIglEngineCommand(CS_TEAM_CT);
}

DispatchIglEngineCommand(CsTeams:team)
{
    new iIgl = GetTeamIgl(team);
    if (iIgl <= 0 || !is_user_alive(iIgl))
        return;

    if (IsKnifeRoundActive())
    {
        engclient_cmd(iIgl, "stormfront");
        set_cvar_num("yb_user_follow_percent", 100);
        set_cvar_num("yb_user_max_followers", 4);
        return;
    }

    new iStrat = g_iTeamStrat[team];
    switch (iStrat)
    {
        case STRAT_RUSH_A, STRAT_RUSH_B:
        {
            engclient_cmd(iIgl, "stormfront");
            set_cvar_num("yb_user_follow_percent", 100);
            set_cvar_num("yb_user_max_followers", 4);
        }
        case STRAT_DEFAULT:
        {
            engclient_cmd(iIgl, "sticktog");
            set_cvar_num("yb_user_follow_percent", 35);
            set_cvar_num("yb_user_max_followers", 1);
        }
        case STRAT_SPLIT:
        {
            engclient_cmd(iIgl, "flankthem");
            set_cvar_num("yb_user_follow_percent", 60);
            set_cvar_num("yb_user_max_followers", 2);
        }
        case STRAT_ECO:
        {
            engclient_cmd(iIgl, "regroup");
            set_cvar_num("yb_user_follow_percent", 100);
            set_cvar_num("yb_user_max_followers", 4);
        }
        default:
        {
            engclient_cmd(iIgl, "go");
        }
    }
}

// ==============================================================================
// 3. ROLE LOADOUT ENFORCEMENT (Equips bots according to assigned role)
// ==============================================================================
public Task_EnforceRoleLoadouts()
{
    if (IsKnifeRoundActive() || !get_pcvar_num(g_pCvarRoles))
        return;

    // First ensure any dropped weapons in spawn are claimed before spending team cash!
    ScanAndClaimSpawnDroppedWeapons(CS_TEAM_T);
    ScanAndClaimSpawnDroppedWeapons(CS_TEAM_CT);

    for (new id = 1; id <= 32; id++)
    {
        if (is_user_alive(id) && is_user_bot(id))
        {
            new iRole = g_iPlayerRole[id];
            new CsTeams:team = cs_get_user_team(id);
            new iMoney = cs_get_user_money(id);

            new iCurrentPrim = GetUserPrimaryWeapon(id);
            new iPrimTier = GetRoleWeaponTier(id, iCurrentPrim, false);

            // =========================================================
            // A. BOT ALREADY HOLDS A TOP-TIER WEAPON (Tier 3 or Tier 4)
            // (Survived last round or scavenged rifle/AWP from dead body)
            // NEVER DOWNGRADE THEM! Preserve weapon, refill ammo & armor!
            // =========================================================
            if (iPrimTier >= 3)
            {
                if (iCurrentPrim == CSW_AWP)
                    cs_set_user_bpammo(id, CSW_AWP, 30);
                else
                    cs_set_user_bpammo(id, iCurrentPrim, 90);

                give_item(id, "item_assaultsuit");

                if (team == CS_TEAM_CT)
                {
                    give_item(id, "item_thighpack"); // defuse kit
                }

                if (iRole == ROLE_SUPPORT)
                {
                    give_item(id, "weapon_smokegrenade");
                    give_item(id, "weapon_flashbang");
                    give_item(id, "weapon_hegrenade");
                }
                else if (iRole == ROLE_ENTRY || iRole == ROLE_IGL)
                {
                    give_item(id, "weapon_flashbang");
                    give_item(id, "weapon_hegrenade");
                }
                continue;
            }

            // Check Full Eco Call: Stop spending completely
            if (g_iTeamEconomyCall[team] == ECON_ECO)
            {
                continue;
            }

            // =========================================================
            // B. ESPORTS PISTOL ROUND ($800) ROLE-BASED LOADOUTS
            // =========================================================
            if (iMoney <= 1000 && iCurrentPrim <= 0)
            {
                switch (iRole)
                {
                    case ROLE_ENTRY:
                    {
                        if (team == CS_TEAM_T && random_num(1, 2) == 1)
                        {
                            // T Entry Fragger loves Tec-9 rush ($500) + Flashbang ($200)!
                            give_item(id, "weapon_p228");
                            cs_set_user_bpammo(id, CSW_P228, 36);
                            give_item(id, "weapon_flashbang");
                            cs_set_user_money(id, max(0, iMoney - 700));
                        }
                        else
                        {
                            // Entry Fragger: Kevlar Armor ($650) to prevent aim punch in duels!
                            give_item(id, "item_kevlar");
                            cs_set_user_armor(id, 100, CS_ARMOR_KEVLAR);
                            cs_set_user_money(id, max(0, iMoney - 650));
                        }
                    }
                    case ROLE_AWPER:
                    {
                        // AWPer: Deagle ($650) for long-range 1-tap duels!
                        give_item(id, "weapon_deagle");
                        cs_set_user_bpammo(id, CSW_DEAGLE, 14);
                        cs_set_user_money(id, max(0, iMoney - 650));
                    }
                    case ROLE_SUPPORT:
                    {
                        if (team == CS_TEAM_CT)
                        {
                            // CT Support: Defuse Kit ($200) + Smoke Grenade ($300) + Flashbang ($200) = $700!
                            give_item(id, "item_thighpack");
                            give_item(id, "weapon_smokegrenade");
                            give_item(id, "weapon_flashbang");
                            cs_set_user_money(id, max(0, iMoney - 700));
                        }
                        else
                        {
                            // T Support: Smoke Grenade ($300) + Flashbang ($200) + HE Grenade ($300) = $800!
                            give_item(id, "weapon_smokegrenade");
                            give_item(id, "weapon_flashbang");
                            give_item(id, "weapon_hegrenade");
                            cs_set_user_money(id, max(0, iMoney - 800));
                        }
                    }
                    case ROLE_LURKER:
                    {
                        // Lurker: Kevlar Armor ($650)
                        give_item(id, "item_kevlar");
                        cs_set_user_armor(id, 100, CS_ARMOR_KEVLAR);
                        cs_set_user_money(id, max(0, iMoney - 650));
                    }
                    case ROLE_IGL:
                    {
                        if (team == CS_TEAM_CT)
                        {
                            // CT IGL: Defuse Kit ($200) + HE Grenade ($300) + Flashbang ($200) = $700!
                            give_item(id, "item_thighpack");
                            give_item(id, "weapon_hegrenade");
                            give_item(id, "weapon_flashbang");
                            cs_set_user_money(id, max(0, iMoney - 700));
                        }
                        else
                        {
                            // T IGL: Kevlar Armor ($650)
                            give_item(id, "item_kevlar");
                            cs_set_user_armor(id, 100, CS_ARMOR_KEVLAR);
                            cs_set_user_money(id, max(0, iMoney - 650));
                        }
                    }
                }
                continue;
            }

            // Check Half Buy Call: If below safe threshold, preserve money
            if (g_iTeamEconomyCall[team] == ECON_HALF && iMoney < 2650)
            {
                continue;
            }

            // =========================================================
            // C. BOT NEEDS TO BUY A PRIMARY WEAPON
            // =========================================================
            switch (iRole)
            {
                case ROLE_AWPER:
                {
                    if (iMoney >= 4750)
                    {
                        cs_set_user_money(id, iMoney - 4750);
                        give_item(id, "weapon_awp");
                        cs_set_user_bpammo(id, CSW_AWP, 30);
                        give_item(id, "weapon_deagle");
                        cs_set_user_bpammo(id, CSW_DEAGLE, 35);
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 3100)
                    {
                        // Broke AWPer buys strong primary rifle instead of waiting
                        if (team == CS_TEAM_T)
                        {
                            cs_set_user_money(id, iMoney - 2700);
                            give_item(id, "weapon_ak47");
                            cs_set_user_bpammo(id, CSW_AK47, 90);
                        }
                        else
                        {
                            cs_set_user_money(id, iMoney - 3100);
                            give_item(id, "weapon_m4a1");
                            cs_set_user_bpammo(id, CSW_M4A1, 90);
                        }
                        give_item(id, "weapon_deagle");
                        cs_set_user_bpammo(id, CSW_DEAGLE, 35);
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 2750)
                    {
                        cs_set_user_money(id, iMoney - 2750);
                        give_item(id, "weapon_scout");
                        cs_set_user_bpammo(id, CSW_SCOUT, 90);
                        give_item(id, "weapon_deagle");
                        cs_set_user_bpammo(id, CSW_DEAGLE, 35);
                        give_item(id, "item_assaultsuit");
                    }
                }
                case ROLE_ENTRY:
                {
                    if (iMoney >= 2700)
                    {
                        if (team == CS_TEAM_T)
                        {
                            cs_set_user_money(id, iMoney - 2700);
                            give_item(id, "weapon_ak47");
                            cs_set_user_bpammo(id, CSW_AK47, 90);
                        }
                        else
                        {
                            cs_set_user_money(id, iMoney - 3100);
                            give_item(id, "weapon_m4a1");
                            cs_set_user_bpammo(id, CSW_M4A1, 90);
                        }
                        give_item(id, "weapon_flashbang");
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 2000)
                    {
                        // Entry Fragger Force-Buy meta: MP7 or Sawed-Off preference
                        if (team == CS_TEAM_T && random_num(1, 2) == 1)
                        {
                            // T Entry loves Sawed-Off close-quarter breaching ($1,100) + Assaultsuit ($1,000)!
                            cs_set_user_money(id, iMoney - 2100);
                            give_item(id, "weapon_m3");
                            cs_set_user_bpammo(id, CSW_M3, 32);
                        }
                        else if (random_num(1, 2) == 1)
                        {
                            // MP7 high-mobility spray ($1,500) + Assaultsuit ($1,000)
                            cs_set_user_money(id, max(0, iMoney - 2500));
                            give_item(id, "weapon_mp5navy");
                            cs_set_user_bpammo(id, CSW_MP5NAVY, 90);
                        }
                        else if (team == CS_TEAM_T)
                        {
                            cs_set_user_money(id, iMoney - 2000);
                            give_item(id, "weapon_galil");
                            cs_set_user_bpammo(id, CSW_GALIL, 90);
                        }
                        else
                        {
                            cs_set_user_money(id, iMoney - 2250);
                            give_item(id, "weapon_famas");
                            cs_set_user_bpammo(id, CSW_FAMAS, 90);
                        }
                        give_item(id, "weapon_flashbang");
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 1500)
                    {
                        // Entry Fragger Budget Buy ($1,500 - $1,999): MP7 or Sawed-Off + Armor
                        if (team == CS_TEAM_T && random_num(1, 2) == 1)
                        {
                            cs_set_user_money(id, max(0, iMoney - 1750));
                            give_item(id, "weapon_m3"); // Sawed-Off ($1,100)
                            cs_set_user_bpammo(id, CSW_M3, 32);
                        }
                        else
                        {
                            cs_set_user_money(id, max(0, iMoney - 1500));
                            give_item(id, "weapon_mp5navy"); // MP7 ($1,500)
                            cs_set_user_bpammo(id, CSW_MP5NAVY, 90);
                        }
                        give_item(id, "item_kevlar");
                    }
                }
                case ROLE_SUPPORT:
                {
                    if (team == CS_TEAM_CT)
                    {
                        give_item(id, "item_thighpack"); // defuse kit
                    }

                    // POINT 1 FIX: When rich, Support PRIORITIZES THE STRONGEST WEAPON (AK-47 / M4A1)!
                    if ((team == CS_TEAM_T && iMoney >= 3700) || (team == CS_TEAM_CT && iMoney >= 4100) || iMoney >= 3100)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_ak47");
                            cs_set_user_bpammo(id, CSW_AK47, 90);
                            cs_set_user_money(id, iMoney - 2700);
                        }
                        else
                        {
                            give_item(id, "weapon_m4a1");
                            cs_set_user_bpammo(id, CSW_M4A1, 90);
                            cs_set_user_money(id, iMoney - 3100);
                        }
                        give_item(id, "weapon_smokegrenade");
                        give_item(id, "weapon_flashbang");
                        give_item(id, "weapon_hegrenade");
                        give_item(id, "item_assaultsuit");
                    }
                    // Budget buy: Only when Support cannot afford AK-47 / M4A1 full buy!
                    else if (iMoney >= 2500)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_galil");
                            cs_set_user_bpammo(id, CSW_GALIL, 90);
                        }
                        else
                        {
                            give_item(id, "weapon_famas");
                            cs_set_user_bpammo(id, CSW_FAMAS, 90);
                        }
                        give_item(id, "weapon_smokegrenade");
                        give_item(id, "weapon_flashbang");
                        give_item(id, "weapon_hegrenade");
                        give_item(id, "item_assaultsuit");
                        cs_set_user_money(id, iMoney - 2500);
                    }
                }
                case ROLE_LURKER:
                {
                    if (team == CS_TEAM_CT && (g_iTeamEconomyCall[team] == ECON_FORCE || g_iTeamEconomyCall[team] == ECON_HALF || iMoney < 3100) && iMoney >= 1300)
                    {
                        // CT Site Anchor loves MAG-7 ($1,300) for lockdown on force-buy / budget rounds!
                        give_item(id, "weapon_xm1014");
                        cs_set_user_bpammo(id, CSW_XM1014, 32);
                        if (iMoney >= 1950)
                        {
                            give_item(id, "item_kevlar");
                            cs_set_user_money(id, iMoney - 1950);
                        }
                        else
                        {
                            cs_set_user_money(id, iMoney - 1300);
                        }
                    }
                    else if (iMoney >= 2700)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_ak47");
                            cs_set_user_bpammo(id, CSW_AK47, 90);
                            cs_set_user_money(id, iMoney - 2700);
                        }
                        else
                        {
                            give_item(id, "weapon_m4a1");
                            cs_set_user_bpammo(id, CSW_M4A1, 90);
                            cs_set_user_money(id, iMoney - 3100);
                        }
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 2000)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_galil");
                            cs_set_user_bpammo(id, CSW_GALIL, 90);
                            cs_set_user_money(id, iMoney - 2000);
                        }
                        else
                        {
                            give_item(id, "weapon_famas");
                            cs_set_user_bpammo(id, CSW_FAMAS, 90);
                            cs_set_user_money(id, iMoney - 2250);
                        }
                        give_item(id, "item_assaultsuit");
                    }
                }
                case ROLE_IGL:
                {
                    if (iMoney >= 2700)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_ak47");
                            cs_set_user_bpammo(id, CSW_AK47, 90);
                            cs_set_user_money(id, iMoney - 2700);
                        }
                        else
                        {
                            give_item(id, "weapon_m4a1");
                            cs_set_user_bpammo(id, CSW_M4A1, 90);
                            cs_set_user_money(id, iMoney - 3100);
                        }
                        give_item(id, "weapon_hegrenade");
                        give_item(id, "weapon_flashbang");
                        give_item(id, "item_assaultsuit");
                    }
                    else if (iMoney >= 2000)
                    {
                        if (team == CS_TEAM_T)
                        {
                            give_item(id, "weapon_galil");
                            cs_set_user_bpammo(id, CSW_GALIL, 90);
                            cs_set_user_money(id, iMoney - 2000);
                        }
                        else
                        {
                            give_item(id, "weapon_famas");
                            cs_set_user_bpammo(id, CSW_FAMAS, 90);
                            cs_set_user_money(id, iMoney - 2250);
                        }
                        give_item(id, "item_assaultsuit");
                    }
                }
            }

            // Low-Budget / Force Buy Fallback: Modern CS2 Variant Affinities (Tec-9, Sawed-Off, MP7, MAG-7, PP-Bizon, Negev, CZ75)
            if (GetUserPrimaryWeapon(id) <= 0)
            {
                new iRemainMoney = cs_get_user_money(id);

                // 1. CT Site Anchor loves MAG-7 ($1,300)
                if (iRole == ROLE_LURKER && team == CS_TEAM_CT && iRemainMoney >= 1300)
                {
                    give_item(id, "weapon_xm1014");
                    cs_set_user_bpammo(id, CSW_XM1014, 32);
                    if (iRemainMoney >= 1950)
                    {
                        give_item(id, "item_kevlar");
                        cs_set_user_money(id, max(0, iRemainMoney - 1950));
                    }
                    else
                    {
                        cs_set_user_money(id, max(0, iRemainMoney - 1300));
                    }
                }
                // 2. T Entry Fragger loves Sawed-Off ($1,100)
                else if (iRole == ROLE_ENTRY && team == CS_TEAM_T && iRemainMoney >= 1100 && iRemainMoney < 1800)
                {
                    give_item(id, "weapon_m3");
                    cs_set_user_bpammo(id, CSW_M3, 32);
                    if (iRemainMoney >= 1750)
                    {
                        give_item(id, "item_kevlar");
                        cs_set_user_money(id, max(0, iRemainMoney - 1750));
                    }
                    else
                    {
                        cs_set_user_money(id, max(0, iRemainMoney - 1100));
                    }
                }
                // 3. Negev Heavy Firepower ($1,700) for Support / Anti-Rush
                else if (iRemainMoney >= 1700 && (iRole == ROLE_SUPPORT || random_num(1, 4) == 1))
                {
                    give_item(id, "weapon_m249");
                    cs_set_user_bpammo(id, CSW_M249, 150);
                    cs_set_user_money(id, max(0, iRemainMoney - 1700));
                }
                // 4. PP-Bizon ($1,400) - 64-round mobile anti-eco rush
                else if (iRemainMoney >= 1400 && (g_iTeamEconomyCall[team] == ECON_FORCE || random_num(1, 2) == 1))
                {
                    give_item(id, "weapon_p90");
                    cs_set_user_bpammo(id, CSW_P90, 100);
                    cs_set_user_money(id, max(0, iRemainMoney - 1400));
                }
                // 5. MP7 ($1,500) high-mobility SMG
                else if (iRemainMoney >= 1500)
                {
                    give_item(id, "weapon_mp5navy");
                    cs_set_user_bpammo(id, CSW_MP5NAVY, 90);
                    give_item(id, "item_kevlar");
                    cs_set_user_money(id, max(0, iRemainMoney - 1500));
                }
                // 6. Secondary Pistol Fallback (Tec-9 / CZ75-Auto / Deagle)
                else if (iRemainMoney >= 500)
                {
                    if (team == CS_TEAM_T && (iRole == ROLE_ENTRY || random_num(1, 2) == 1))
                    {
                        give_item(id, "weapon_p228"); // Tec-9 ($500)
                        cs_set_user_bpammo(id, CSW_P228, 36);
                        cs_set_user_money(id, max(0, iRemainMoney - 500));
                    }
                    else if (team == CS_TEAM_T && random_num(1, 2) == 1)
                    {
                        give_item(id, "weapon_mac10"); // CZ75-Auto (T slot, $500)
                        cs_set_user_bpammo(id, CSW_MAC10, 12);
                        cs_set_user_money(id, max(0, iRemainMoney - 500));
                    }
                    else if (team == CS_TEAM_CT && random_num(1, 2) == 1)
                    {
                        give_item(id, "weapon_tmp"); // CZ75-Auto (CT slot, $500)
                        cs_set_user_bpammo(id, CSW_TMP, 12);
                        cs_set_user_money(id, max(0, iRemainMoney - 500));
                    }
                    else if (iRemainMoney >= 650 && GetUserSecondaryWeapon(id) != CSW_DEAGLE)
                    {
                        give_item(id, "weapon_deagle");
                        cs_set_user_bpammo(id, CSW_DEAGLE, 21);
                        give_item(id, "item_kevlar");
                        cs_set_user_money(id, max(0, iRemainMoney - 650));
                    }
                }
            }
        }
    }
}

// ==============================================================================
// 4. HUMAN PLAYER IGL STRAT SELECTION MENU
// ==============================================================================
public ShowIglStratMenu(id)
{
    new menu = menu_create("\y[IGL Command] Call Strat for this Round:", "HandleIglStratMenu");

    menu_additem(menu, "\w⚡ Fast Rush Bombsite A", "1");
    menu_additem(menu, "\w🔥 Execute Bombsite B", "2");
    menu_additem(menu, "\w🛡️ Default 1-3-1 (Hold for Picks)", "3");
    menu_additem(menu, "\w⚔️ Split Mid to Site", "4");
    menu_additem(menu, "\w💰 Full Eco / Group Save", "5");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public HandleIglStratMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    new iStrat = str_to_num(szData);

    if (iStrat >= 1 && iStrat <= 5)
    {
        new CsTeams:team = cs_get_user_team(id);
        g_iTeamStrat[team] = iStrat;

        new szPlayerName[32];
        get_user_name(id, szPlayerName, charsmax(szPlayerName));

        BroadcastTeamCall(team, "^4[IGL Call]^3 %s^1: Strat: ^4%s^1!", szPlayerName, g_szStratNames[iStrat]);

        // Bot teammates acknowledge
        for (new b = 1; b <= 32; b++)
        {
            if (is_user_alive(b) && is_user_bot(b) && cs_get_user_team(b) == team)
            {
                client_cmd(id, "spk radio/roger");
                break;
            }
        }
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public Cmd_OpenStratMenu(id)
{
    if (is_user_connected(id) && g_iPlayerRole[id] == ROLE_IGL)
    {
        ShowIglStratMenu(id);
    }
    else
    {
        client_print_color(id, print_team_default, "^4[IGL]^1 You must have the ^3IGL role^1 (/role) to call team strategies!");
    }
    return PLUGIN_HANDLED;
}

// ==============================================================================
// 5. ROLE SELECTION MENU
// ==============================================================================
public OnPlayerSpawnPost(id)
{
    if (!is_user_alive(id))
        return HAM_IGNORED;

    ResetBotState(id);

    // Freeze bots during freeze time in live match & knife round
    if (is_user_bot(id) && g_bInFreezeTime && !IsWarmupActive())
    {
        new flags = pev(id, pev_flags);
        set_pev(id, pev_flags, flags | FL_FROZEN);
        set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0});
    }

    // Never show role menu during Warmup or Knife Round
    if (IsWarmupActive() || IsKnifeRoundActive())
    {
        return HAM_IGNORED;
    }

    if (!is_user_bot(id) && !g_bRoleSelected[id] && get_pcvar_num(g_pCvarRoles))
    {
        set_task(0.5, "Task_ShowRoleMenuDelayed", id + TASK_ROLE_MENU);
    }

    return HAM_IGNORED;
}

public Task_ShowRoleMenuDelayed(taskid)
{
    new id = taskid - TASK_ROLE_MENU;
    if (is_user_connected(id) && !is_user_bot(id))
    {
        ShowRoleMenu(id);
    }
}

public Cmd_OpenRoleMenu(id)
{
    if (is_user_connected(id))
    {
        ShowRoleMenu(id);
    }
    return PLUGIN_HANDLED;
}

public ShowRoleMenu(id)
{
    new menu = menu_create("\y[Competitive CS] Choose Your Role:", "HandleRoleMenu");

    menu_additem(menu, "\w🎯 Entry Fragger \d(First Duel / Aggressive Peek)", "1");
    menu_additem(menu, "\w🔭 AWPer \d(Sniper / Long Angles / Area Denial)", "2");
    menu_additem(menu, "\w🛡️ Support \d(Utility / Drops / Trade Kills)", "3");
    menu_additem(menu, "\w🥷 Lurker / Anchor \d(Flanker / Stealth / Site Hold)", "4");
    menu_additem(menu, "\w👑 IGL \d(Tactician / Calls Strategies in Freeze)", "5");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public HandleRoleMenu(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    new iRole = str_to_num(szData);

    if (iRole >= ROLE_ENTRY && iRole <= ROLE_IGL)
    {
        g_iPlayerRole[id] = iRole;
        g_bRoleSelected[id] = true;

        new szPlayerName[32];
        get_user_name(id, szPlayerName, charsmax(szPlayerName));

        client_print_color(0, print_team_default, "^4[Role System]^3 %s^1 selected role: ^4%s^1!", szPlayerName, g_szRoleNames[iRole]);

        new CsTeams:team = cs_get_user_team(id);
        if (team == CS_TEAM_T || team == CS_TEAM_CT)
        {
            BalanceTeamRoles(team);
        }
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

BalanceTeamRoles(CsTeams:team)
{
    if (!get_pcvar_num(g_pCvarRoles))
        return;

    new iHumanAwpCount = 0;
    new iHumanIglCount = 0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && cs_get_user_team(i) == team)
        {
            if (g_iPlayerRole[i] == ROLE_AWPER) iHumanAwpCount++;
            if (g_iPlayerRole[i] == ROLE_IGL)   iHumanIglCount++;
        }
    }

    new bool:bHasIgl = (iHumanIglCount > 0);
    new bool:bHasAwp = (iHumanAwpCount > 0);
    new bool:bHasSupport = false;
    new bool:bHasLurker = false;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            if (!bHasIgl)
            {
                g_iPlayerRole[i] = ROLE_IGL;
                bHasIgl = true;
            }
            else if (!bHasAwp)
            {
                g_iPlayerRole[i] = ROLE_AWPER;
                bHasAwp = true;
            }
            else if (!bHasSupport)
            {
                g_iPlayerRole[i] = ROLE_SUPPORT;
                bHasSupport = true;
            }
            else if (!bHasLurker)
            {
                g_iPlayerRole[i] = ROLE_LURKER;
                bHasLurker = true;
            }
            else
            {
                g_iPlayerRole[i] = ROLE_ENTRY;
            }
            g_bRoleSelected[i] = true;
        }
    }
}

// ==============================================================================
// M4A4 vs M4A1-S DETECTION HELPERS
// ==============================================================================
stock fm_find_weapon_ent_by_owner(id, const classname[])
{
    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)) > 0)
    {
        if (pev(ent, pev_owner) == id || get_pdata_cbase(ent, 41, 4) == id)
            return ent;
    }
    return 0;
}

stock bool:IsPlayerM4A4(id)
{
    if (id < 1 || id > 32 || !is_user_connected(id))
        return false;

    // 1. Check currently carried weapon entity pev_iuser1 first (1 = M4A4, 2 = M4A1-S)
    new iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
    if (pev_valid(iWpn))
    {
        new iVar = pev(iWpn, pev_iuser1);
        if (iVar == 1) return true;
        if (iVar == 2) return false;
    }

    // 2. Check cs2_skin_inventory dynamic query for player's active loadout
    if (callfunc_begin("cs2_is_m4a4", "cs2_skin_inventory.amxx") == 1)
    {
        callfunc_push_int(id);
        new res = callfunc_end();
        if (res == 1) return true;
        if (res == 0) return false;
    }

    // 3. Fallback: Entry Fraggers & Site Anchors equip M4A4
    if (g_iPlayerRole[id] == ROLE_ENTRY || g_iPlayerRole[id] == ROLE_LURKER)
        return true;

    return false;
}

// ==============================================================================
// 6. ESPORTS PLAYER-TO-BOT CHAT & CALLOUT ENGINE (v3.4)
// ==============================================================================
stock GetFirstBotTeammate(CsTeams:team)
{
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
            return i;
    }
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == team)
            return i;
    }
    return 0;
}

bool:Execute_CareZoneCall(id, iZone, const szZoneName[])
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    g_iActiveDangerZone[team] = iZone;
    g_flDangerZoneExpire[team] = flGameTime + 18.0;

    new Float:vecPlayerOrigin[3], Float:vecVAngle[3], Float:vecForward[3];
    pev(id, pev_origin, vecPlayerOrigin);
    pev(id, pev_v_angle, vecVAngle);
    angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);

    if (iZone == ZONE_SITE_A && g_bBombsitesFound)
        xs_vec_copy(g_vecBombsiteA, g_vecDangerPoint[team]);
    else if (iZone == ZONE_SITE_B && g_bBombsitesFound)
        xs_vec_copy(g_vecBombsiteB, g_vecDangerPoint[team]);
    else if (iZone == ZONE_MID && g_bMidPointCalculated)
        xs_vec_copy(g_vecMapMidPoint, g_vecDangerPoint[team]);
    else
    {
        xs_vec_mul_scalar(vecForward, 500.0, vecForward);
        xs_vec_add(vecPlayerOrigin, vecForward, g_vecDangerPoint[team]);
    }

    new iResponder = GetTeamIgl(team);
    if (iResponder <= 0 || !is_user_alive(iResponder))
        iResponder = GetFirstBotTeammate(team);

    if (iResponder > 0)
    {
        new szBotName[32];
        get_user_name(iResponder, szBotName, charsmax(szBotName));
        new iRole = g_iPlayerRole[iResponder];

        switch (iZone)
        {
            case ZONE_SITE_A:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Copy that! Watching angles on ^4Bombsite A^1. Danger flagged, do not dry peek!", g_szRoleTags[iRole], szBotName);
            case ZONE_SITE_B:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Understood! ^4Sector B^1 flagged as hot. Clear corners with utility!", g_szRoleTags[iRole], szBotName);
            case ZONE_SHORT:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Watching ^4Short / Catwalk^1! Crosshair locked, playing cautious.", g_szRoleTags[iRole], szBotName);
            case ZONE_LONG:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Acknowledged, scope locked on ^4Long A^1. Ready for their sniper!", g_szRoleTags[iRole], szBotName);
            case ZONE_MID:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: ^4Mid is dangerous^1! Hold passive angles, don't give first blood!", g_szRoleTags[iRole], szBotName);
            case ZONE_FLANK:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Flank alert confirmed! Anchoring our ^4rear six^1.", g_szRoleTags[iRole], szBotName);
            case ZONE_AWP:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: ^4Enemy sniper spotted^1! Pop flashes and smokes before challenging!", g_szRoleTags[iRole], szBotName);
            case ZONE_PUSH:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: ^4Enemy push incoming^1! Fall into defensive crossfire positions!", g_szRoleTags[iRole], szBotName);
            default:
                BroadcastTeamCall(team, "^4[Danger Intel]^3 %s %s^1: Copy, danger flagged at ^4%s^1. Proceeding with caution!", g_szRoleTags[iRole], szBotName, szZoneName);
        }

        PlayTeamAudio(team, (iZone == ZONE_AWP || iZone == ZONE_PUSH) ? "spk radio/takingfire" : "spk radio/spotted");
    }
    return true;
}

bool:Execute_DropC4Call(id)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T)
    {
        client_print_color(id, print_team_default, "^4[Objective]^1 Only Terrorists manage C4 explosives!");
        return true;
    }

    if (user_has_weapon(id, CSW_C4))
    {
        client_print_color(id, print_team_default, "^4[Objective]^1 You already carry the ^4C4 Backpack^1! Lead the site execute!");
        return true;
    }

    new iCarrier = 0;
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && cs_get_user_team(i) == CS_TEAM_T && user_has_weapon(i, CSW_C4))
        {
            iCarrier = i;
            break;
        }
    }

    if (iCarrier <= 0)
    {
        client_print_color(id, print_team_default, "^4[Objective]^1 No teammate is currently holding the C4 (dropped or planted).");
        return true;
    }

    if (!is_user_bot(iCarrier))
    {
        new szCarrierName[32];
        get_user_name(iCarrier, szCarrierName, charsmax(szCarrierName));
        client_print_color(id, print_team_default, "^4[Objective]^3 %s^1 is carrying the C4!", szCarrierName);
        return true;
    }

    new Float:vecCarrier[3], Float:vecPlayer[3];
    pev(iCarrier, pev_origin, vecCarrier);
    pev(id, pev_origin, vecPlayer);
    new Float:flDist = get_distance_f(vecCarrier, vecPlayer);

    new szBotName[32];
    get_user_name(iCarrier, szBotName, charsmax(szBotName));
    new iRole = g_iPlayerRole[iCarrier];

    if (flDist <= 350.0)
    {
        new Float:vecDiff[3], Float:vecAimAngles[3];
        xs_vec_sub(vecPlayer, vecCarrier, vecDiff);
        vector_to_angle(vecDiff, vecAimAngles);
        ClampAngles(vecAimAngles);
        set_pev(iCarrier, pev_v_angle, vecAimAngles);
        set_pev(iCarrier, pev_angles, vecAimAngles);

        engclient_cmd(iCarrier, "weapon_c4");
        engclient_cmd(iCarrier, "drop", "weapon_c4");

        BroadcastTeamCall(CS_TEAM_T, "^4[Objective]^3 %s %s^1: Dropping the C4 to you! Plant safe!", g_szRoleTags[iRole], szBotName);
        PlayTeamAudio(CS_TEAM_T, "spk radio/roger");
    }
    else
    {
        g_iTradeLeader[iCarrier] = id;
        g_flTradeFollowUntil[iCarrier] = get_gametime() + 18.0;

        BroadcastTeamCall(CS_TEAM_T, "^4[Objective]^3 %s %s^1: Bringing the C4 to your location! Hold position!", g_szRoleTags[iRole], szBotName);
        PlayTeamAudio(CS_TEAM_T, "spk radio/sticktog");
    }
    return true;
}

bool:Execute_PopFlashCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    new Float:vecPlayerOrigin[3], Float:vecBotOrigin[3];
    pev(id, pev_origin, vecPlayerOrigin);

    new iBestBot = 0;
    new Float:flBestDist = 1200.0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            if (user_has_weapon(i, CSW_FLASHBANG))
            {
                pev(i, pev_origin, vecBotOrigin);
                new Float:flDist = get_distance_f(vecBotOrigin, vecPlayerOrigin);
                if (g_iPlayerRole[i] == ROLE_SUPPORT)
                    flDist *= 0.65;

                if (flDist < flBestDist)
                {
                    flBestDist = flDist;
                    iBestBot = i;
                }
            }
        }
    }

    if (iBestBot > 0)
    {
        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        new Float:vecBotEyes[3], Float:vecForward[3], Float:vecVAngle[3], Float:vecTarget[3], Float:vecDiff[3], Float:vecAimAngles[3];
        pev(iBestBot, pev_origin, vecBotEyes);
        vecBotEyes[2] += 17.0;

        pev(id, pev_v_angle, vecVAngle);
        angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);
        xs_vec_mul_scalar(vecForward, 350.0, vecForward);
        xs_vec_add(vecPlayerOrigin, vecForward, vecTarget);
        vecTarget[2] += 180.0; // High popflash apex

        xs_vec_sub(vecTarget, vecBotEyes, vecDiff);
        vector_to_angle(vecDiff, vecAimAngles);
        vecAimAngles[0] = -38.0; // Lob pitch
        ClampAngles(vecAimAngles);

        xs_vec_copy(vecAimAngles, g_vecLineupAngles[iBestBot]);
        g_bLineupActive[iBestBot] = true;
        g_flLineupThrowUntil[iBestBot] = flGameTime + 0.45;

        engclient_cmd(iBestBot, "weapon_flashbang");

        BroadcastTeamCall(team, "^4[Utility Support]^3 %s %s^1: Flashing high for you! Turn away!",
            g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        PlayTeamAudio(team, "spk radio/fireinhole");
        return true;
    }

    new iAnyBot = GetFirstBotTeammate(team);
    if (iAnyBot > 0)
    {
        new szBotName[32];
        get_user_name(iAnyBot, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Utility Support]^3 %s %s^1: Negative! We have no flashbangs left in reserve.",
            g_szRoleTags[g_iPlayerRole[iAnyBot]], szBotName);
        PlayTeamAudio(team, "spk radio/negative");
    }
    return true;
}

bool:Execute_SmokeCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    new Float:vecPlayerOrigin[3], Float:vecBotOrigin[3];
    pev(id, pev_origin, vecPlayerOrigin);

    new iBestBot = 0;
    new Float:flBestDist = 1400.0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            if (user_has_weapon(i, CSW_SMOKEGRENADE))
            {
                pev(i, pev_origin, vecBotOrigin);
                new Float:flDist = get_distance_f(vecBotOrigin, vecPlayerOrigin);
                if (g_iPlayerRole[i] == ROLE_SUPPORT)
                    flDist *= 0.65;

                if (flDist < flBestDist)
                {
                    flBestDist = flDist;
                    iBestBot = i;
                }
            }
        }
    }

    if (iBestBot > 0)
    {
        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        new Float:vecBotEyes[3], Float:vecForward[3], Float:vecVAngle[3], Float:vecTarget[3], Float:vecDiff[3], Float:vecAimAngles[3];
        pev(iBestBot, pev_origin, vecBotEyes);
        vecBotEyes[2] += 17.0;

        pev(id, pev_v_angle, vecVAngle);
        angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);
        xs_vec_mul_scalar(vecForward, 450.0, vecForward);
        xs_vec_add(vecPlayerOrigin, vecForward, vecTarget);

        xs_vec_sub(vecTarget, vecBotEyes, vecDiff);
        vector_to_angle(vecDiff, vecAimAngles);
        vecAimAngles[0] = -28.0;
        ClampAngles(vecAimAngles);

        xs_vec_copy(vecAimAngles, g_vecLineupAngles[iBestBot]);
        g_bLineupActive[iBestBot] = true;
        g_flLineupThrowUntil[iBestBot] = flGameTime + 0.45;

        engclient_cmd(iBestBot, "weapon_smokegrenade");

        BroadcastTeamCall(team, "^4[Utility Support]^3 %s %s^1: Smoking the choke point, 3 seconds!",
            g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        PlayTeamAudio(team, "spk radio/roger");
        return true;
    }

    new iAnyBot = GetFirstBotTeammate(team);
    if (iAnyBot > 0)
    {
        new szBotName[32];
        get_user_name(iAnyBot, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Utility Support]^3 %s %s^1: Negative! Out of smoke grenades.",
            g_szRoleTags[g_iPlayerRole[iAnyBot]], szBotName);
        PlayTeamAudio(team, "spk radio/negative");
    }
    return true;
}

bool:Execute_TradeFragCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:vecPlayerOrigin[3], Float:vecBotOrigin[3];
    pev(id, pev_origin, vecPlayerOrigin);

    new iBestBot = 0;
    new Float:flBestDist = 1200.0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            pev(i, pev_origin, vecBotOrigin);
            new Float:flDist = get_distance_f(vecBotOrigin, vecPlayerOrigin);
            if (g_iPlayerRole[i] == ROLE_ENTRY || g_iPlayerRole[i] == ROLE_SUPPORT)
                flDist *= 0.70;

            if (flDist < flBestDist)
            {
                flBestDist = flDist;
                iBestBot = i;
            }
        }
    }

    if (iBestBot > 0)
    {
        g_iTradeLeader[iBestBot] = id;
        g_flTradeFollowUntil[iBestBot] = get_gametime() + 20.0;

        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        BroadcastTeamCall(team, "^4[Trade Duo]^3 %s %s^1: Right behind you, I'll trade your contact!",
            g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        PlayTeamAudio(team, "spk radio/go_go_go");
        return true;
    }
    return false;
}

bool:Execute_RearFlankCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:vecPlayerOrigin[3], Float:vecBotOrigin[3];
    pev(id, pev_origin, vecPlayerOrigin);

    new iBestBot = 0;
    new Float:flBestDist = 1400.0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            pev(i, pev_origin, vecBotOrigin);
            new Float:flDist = get_distance_f(vecBotOrigin, vecPlayerOrigin);
            if (g_iPlayerRole[i] == ROLE_LURKER)
                flDist *= 0.60;

            if (flDist < flBestDist)
            {
                flBestDist = flDist;
                iBestBot = i;
            }
        }
    }

    if (iBestBot > 0)
    {
        g_flRearFlankUntil[iBestBot] = get_gametime() + 15.0;

        new Float:vecPlayerAngles[3];
        pev(id, pev_v_angle, vecPlayerAngles);
        vecPlayerAngles[1] += 180.0;
        if (vecPlayerAngles[1] > 180.0)
            vecPlayerAngles[1] -= 360.0;
        vecPlayerAngles[0] = 0.0;

        xs_vec_copy(vecPlayerAngles, g_vecRearFlankAngle[iBestBot]);

        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        BroadcastTeamCall(team, "^4[Flank Anchor]^3 %s %s^1: Covering our rear flank! Holding the six.",
            g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        PlayTeamAudio(team, "spk radio/sticktog");
        return true;
    }
    return false;
}

bool:Execute_DefuseCoverCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT)
    {
        client_print_color(id, print_team_default, "^4[Objective]^1 Defuse cover is only applicable for Counter-Terrorists!");
        return true;
    }

    new Float:vecPlayerOrigin[3], Float:vecBotOrigin[3];
    pev(id, pev_origin, vecPlayerOrigin);

    new iBestBot = 0;
    new Float:flBestDist = 1200.0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == CS_TEAM_CT)
        {
            pev(i, pev_origin, vecBotOrigin);
            new Float:flDist = get_distance_f(vecBotOrigin, vecPlayerOrigin);
            if (user_has_weapon(i, CSW_SMOKEGRENADE))
                flDist *= 0.60;

            if (flDist < flBestDist)
            {
                flBestDist = flDist;
                iBestBot = i;
            }
        }
    }

    if (iBestBot > 0)
    {
        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        if (user_has_weapon(iBestBot, CSW_SMOKEGRENADE))
        {
            new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
            pev(iBestBot, pev_origin, vecBotEyes);
            vecBotEyes[2] += 17.0;

            xs_vec_sub(vecPlayerOrigin, vecBotEyes, vecDiff);
            vector_to_angle(vecDiff, vecAimAngles);
            vecAimAngles[0] = -25.0;
            ClampAngles(vecAimAngles);

            xs_vec_copy(vecAimAngles, g_vecLineupAngles[iBestBot]);
            g_bLineupActive[iBestBot] = true;
            g_flLineupThrowUntil[iBestBot] = get_gametime() + 0.45;
            engclient_cmd(iBestBot, "weapon_smokegrenade");

            BroadcastTeamCall(CS_TEAM_CT, "^4[Objective]^3 %s %s^1: Laying smoke on bomb and covering your defuse!",
                g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        }
        else
        {
            BroadcastTeamCall(CS_TEAM_CT, "^4[Objective]^3 %s %s^1: Providing suppressive body-block & crossfire for your defuse!",
                g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName);
        }

        g_iTradeLeader[iBestBot] = id;
        g_flTradeFollowUntil[iBestBot] = get_gametime() + 12.0;

        PlayTeamAudio(CS_TEAM_CT, "spk radio/coverme");
        return true;
    }
    return false;
}

bool:Execute_RotateCall(id, iStrat)
{
    SetPlayerStrat(id, iStrat);
    return true;
}

bool:Execute_SaveGunsCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    g_iTeamStrat[team] = STRAT_ECO;

    new iAnyBot = GetFirstBotTeammate(team);
    if (iAnyBot > 0)
    {
        new szBotName[32];
        get_user_name(iAnyBot, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Tactical Order]^3 %s %s^1: Conceding site! Falling back to save weapons for next round.",
            g_szRoleTags[g_iPlayerRole[iAnyBot]], szBotName);
        PlayTeamAudio(team, "spk radio/fallback");
    }
    return true;
}

bool:Execute_UtilityReport(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new bool:bFound = false;

    for (new b = 1; b <= 32; b++)
    {
        if (is_user_alive(b) && is_user_bot(b) && cs_get_user_team(b) == team)
        {
            new iSmokes = cs_get_user_bpammo(b, CSW_SMOKEGRENADE);
            new iFlashes = cs_get_user_bpammo(b, CSW_FLASHBANG);
            new iHE = cs_get_user_bpammo(b, CSW_HEGRENADE);
            new bool:bKit = (team == CS_TEAM_CT && cs_get_user_defuse(b));
            new iMoney = cs_get_user_money(b);
            new szBotName[32];
            get_user_name(b, szBotName, charsmax(szBotName));

            client_print_color(id, print_team_default, "^4[Utility Intel]^3 %s %s^1: %d Smoke, %d Flash, %d HE%s ($%d)",
                g_szRoleTags[g_iPlayerRole[b]], szBotName, iSmokes, iFlashes, iHE, bKit ? ", Defuse Kit" : "", iMoney);
            bFound = true;
        }
    }

    if (!bFound)
    {
        client_print_color(id, print_team_default, "^4[Utility Intel]^1 No living bot teammates to report utility.");
    }
    else
    {
        client_cmd(id, "spk radio/roger");
    }
    return true;
}

bool:Execute_EconomyReport(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new iTotalMoney = 0, iCount = 0;

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && cs_get_user_team(i) == team)
        {
            iTotalMoney += cs_get_user_money(i);
            iCount++;
        }
    }

    if (iCount <= 0) iCount = 1;
    new iAvg = iTotalMoney / iCount;

    new iIgl = GetTeamIgl(team);
    if (iIgl <= 0 || !is_user_alive(iIgl))
        iIgl = GetFirstBotTeammate(team);

    if (iIgl > 0)
    {
        new szIglName[32];
        get_user_name(iIgl, szIglName, charsmax(szIglName));
        new iRole = g_iPlayerRole[iIgl];

        if (iAvg >= 4200)
            BroadcastTeamCall(team, "^4[Economy Intel]^3 %s %s^1: Team Avg: ^4$%d^1. Recommendation: ^4FULL BUY^1 (Rifles + Full Utility)!", g_szRoleTags[iRole], szIglName, iAvg);
        else if (iAvg >= 2400)
            BroadcastTeamCall(team, "^4[Economy Intel]^3 %s %s^1: Team Avg: ^4$%d^1. Recommendation: ^3HALF BUY / FORCE^1 (Keep $2k savings buffer)!", g_szRoleTags[iRole], szIglName, iAvg);
        else
            BroadcastTeamCall(team, "^4[Economy Intel]^3 %s %s^1: Team Avg: ^4$%d^1. Recommendation: ^1FULL ECO / SAVE^1 (Preserve cash for full rifles next round)!", g_szRoleTags[iRole], szIglName, iAvg);

        PlayTeamAudio(team, "spk radio/regroup");
    }
    return true;
}

bool:Execute_ReconReport(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    new bool:bFound = false;

    for (new b = 1; b <= 32; b++)
    {
        if (is_user_alive(b) && is_user_bot(b) && cs_get_user_team(b) == team)
        {
            new Float:vecOrigin[3];
            pev(b, pev_origin, vecOrigin);

            new szLocation[32];
            if (g_bBombsitesFound && get_distance_f(vecOrigin, g_vecBombsiteA) <= 650.0)
                copy(szLocation, charsmax(szLocation), "Bombsite A");
            else if (g_bBombsitesFound && get_distance_f(vecOrigin, g_vecBombsiteB) <= 650.0)
                copy(szLocation, charsmax(szLocation), "Bombsite B");
            else if (g_bMidPointCalculated && get_distance_f(vecOrigin, g_vecMapMidPoint) <= 650.0)
                copy(szLocation, charsmax(szLocation), "Middle Corridor");
            else
                copy(szLocation, charsmax(szLocation), "Transit Chokepoint");

            new bool:bContact = (g_iSoundTarget[b] > 0 && g_flSoundTargetExpire[b] > flGameTime);
            new szBotName[32];
            get_user_name(b, szBotName, charsmax(szBotName));

            client_print_color(id, print_team_default, "^4[Recon Intel]^3 %s %s^1: Holding ^4%s^1 - %s",
                g_szRoleTags[g_iPlayerRole[b]], szBotName, szLocation,
                bContact ? "^1[Heard Enemy Steps Nearby!]" : "^3[Clear, No Immediate Contact]");
            bFound = true;
        }
    }

    if (bFound)
    {
        client_cmd(id, "spk radio/clear");
    }
    return true;
}

bool:Execute_DamageReport(id)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();
    new bool:bFound = false;

    for (new b = 1; b <= 32; b++)
    {
        if (is_user_connected(b) && is_user_bot(b) && cs_get_user_team(b) == team)
        {
            if (g_iLastDamageTarget[b] > 0 && (flGameTime - g_flLastDamageTime[b] < 12.0))
            {
                new szBotName[32], szEnemyName[32];
                get_user_name(b, szBotName, charsmax(szBotName));
                get_user_name(g_iLastDamageTarget[b], szEnemyName, charsmax(szEnemyName));

                BroadcastTeamCall(team, "^4[Damage Intel]^3 %s %s^1: Tagged ^4%s^1 for -^3%d HP^1! He is low!",
                    g_szRoleTags[g_iPlayerRole[b]], szBotName, szEnemyName, g_iLastDamageDealt[b]);
                bFound = true;
            }
        }
    }

    if (!bFound)
    {
        new iBot = GetFirstBotTeammate(team);
        if (iBot > 0)
        {
            new szBotName[32];
            get_user_name(iBot, szBotName, charsmax(szBotName));
            BroadcastTeamCall(team, "^4[Damage Intel]^3 %s %s^1: No recent combat damage dealt to enemies.",
                g_szRoleTags[g_iPlayerRole[iBot]], szBotName);
        }
    }

    PlayTeamAudio(team, "spk radio/reportin");
    return true;
}

bool:Execute_SilentWalkCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    g_flSilentWalkUntil[team] = get_gametime() + 12.0;

    new iAnyBot = GetFirstBotTeammate(team);
    if (iAnyBot > 0)
    {
        new szBotName[32];
        get_user_name(iAnyBot, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Squad Pacing]^3 %s %s^1: Going silent. Shift walking contact!",
            g_szRoleTags[g_iPlayerRole[iAnyBot]], szBotName);
        PlayTeamAudio(team, "spk radio/roger");
    }
    return true;
}

bool:Execute_HoldAngleCall(id)
{
    new CsTeams:team = cs_get_user_team(id);
    g_flHoldAngleUntil[team] = get_gametime() + 15.0;

    new iAnyBot = GetFirstBotTeammate(team);
    if (iAnyBot > 0)
    {
        new szBotName[32];
        get_user_name(iAnyBot, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Squad Pacing]^3 %s %s^1: Holding passive off-angles. Waiting for their peek!",
            g_szRoleTags[g_iPlayerRole[iAnyBot]], szBotName);
        PlayTeamAudio(team, "spk radio/sticktog");
    }
    return true;
}

bool:ProcessTacticalChatCall(id, const szMessage[])
{
    new Float:flGameTime = get_gametime();
    new Float:flCooldown = get_pcvar_float(g_pCvarChatCooldown);
    if (flCooldown < 0.5) flCooldown = 0.5;

    // Anti-spam cooldown per player
    if (flGameTime - g_flLastChatCallTime[id] < flCooldown)
        return false;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return false;

    // -------------------------------------------------------------
    // 1. CARE & DANGER ZONE WARNINGS ("care [zone]")
    // -------------------------------------------------------------
    if (containi(szMessage, "care") != -1 || containi(szMessage, "awas") != -1 || containi(szMessage, "hati-hati") != -1 || containi(szMessage, "watch out") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        if (containi(szMessage, "short") != -1 || containi(szMessage, "cat") != -1)
            return Execute_CareZoneCall(id, ZONE_SHORT, "Short");
        else if (containi(szMessage, "long") != -1 || containi(szMessage, "pit") != -1)
            return Execute_CareZoneCall(id, ZONE_LONG, "Long A");
        else if (containi(szMessage, "mid") != -1 || containi(szMessage, "tengah") != -1)
            return Execute_CareZoneCall(id, ZONE_MID, "Middle");
        else if (containi(szMessage, "flank") != -1 || containi(szMessage, "behind") != -1 || containi(szMessage, "back") != -1 || containi(szMessage, "bokong") != -1 || containi(szMessage, "belakang") != -1)
            return Execute_CareZoneCall(id, ZONE_FLANK, "Rear Flank");
        else if (containi(szMessage, "awp") != -1 || containi(szMessage, "sniper") != -1)
            return Execute_CareZoneCall(id, ZONE_AWP, "Enemy Sniper");
        else if (containi(szMessage, "push") != -1 || containi(szMessage, "rush") != -1 || containi(szMessage, "maju") != -1)
            return Execute_CareZoneCall(id, ZONE_PUSH, "Aggressive Push");
        else if (containi(szMessage, "site a") != -1 || containi(szMessage, " a") != -1)
            return Execute_CareZoneCall(id, ZONE_SITE_A, "Bombsite A");
        else if (containi(szMessage, "site b") != -1 || containi(szMessage, " b") != -1)
            return Execute_CareZoneCall(id, ZONE_SITE_B, "Bombsite B");
        else
            return Execute_CareZoneCall(id, ZONE_MID, "Target Sector");
    }

    // -------------------------------------------------------------
    // 2. C4 / BOMB MANAGEMENT (Drop C4, pass bomb)
    // -------------------------------------------------------------
    if (containi(szMessage, "drop c4") != -1 || containi(szMessage, "drop bomb") != -1 || 
        containi(szMessage, "give bomb") != -1 || containi(szMessage, "bagi c4") != -1 || 
        containi(szMessage, "bagi bom") != -1 || containi(szMessage, "sini bom") != -1 ||
        containi(szMessage, "kasih bom") != -1 || containi(szMessage, "pass bomb") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_DropC4Call(id);
    }

    // -------------------------------------------------------------
    // 3. UTILITY ASSISTANCE (Pop-Flash, Smoke)
    // -------------------------------------------------------------
    if (containi(szMessage, "flash me") != -1 || containi(szMessage, "popflash") != -1 || 
        containi(szMessage, "minta flash") != -1 || containi(szMessage, "lempar flash") != -1 || 
        containi(szMessage, "flash bang") != -1 || equali(szMessage, "flash") || equali(szMessage, "/flash"))
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_PopFlashCall(id);
    }

    if (containi(szMessage, "smoke") != -1 || containi(szMessage, "tutup asap") != -1 || 
        containi(szMessage, "asap sini") != -1 || containi(szMessage, "lempar smoke") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_SmokeCall(id);
    }

    // -------------------------------------------------------------
    // 4. COMBAT COORDINATION (Trade-Frag, Rear Flank)
    // -------------------------------------------------------------
    if (containi(szMessage, "trade") != -1 || containi(szMessage, "push with me") != -1 || 
        containi(szMessage, "double peek") != -1 || containi(szMessage, "ikut aku") != -1 || 
        containi(szMessage, "maju bareng") != -1 || containi(szMessage, "backup me") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_TradeFragCall(id);
    }

    if (containi(szMessage, "watch back") != -1 || containi(szMessage, "watch flank") != -1 || 
        containi(szMessage, "cover rear") != -1 || containi(szMessage, "jaga belakang") != -1 || 
        containi(szMessage, "pantau bokong") != -1 || containi(szMessage, "tengok belakang") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_RearFlankCall(id);
    }

    // -------------------------------------------------------------
    // 5. OBJECTIVE DEFENSE & RETAKE (Defuse Cover, Rotations, Save)
    // -------------------------------------------------------------
    if (containi(szMessage, "cover defuse") != -1 || containi(szMessage, "stick defuse") != -1 || 
        containi(szMessage, "tutup defuse") != -1 || containi(szMessage, "lindungin defuse") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_DefuseCoverCall(id);
    }

    if (containi(szMessage, "rotate a") != -1 || containi(szMessage, "rotasi a") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_RotateCall(id, STRAT_RUSH_A);
    }
    if (containi(szMessage, "rotate b") != -1 || containi(szMessage, "rotasi b") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_RotateCall(id, STRAT_RUSH_B);
    }

    if (containi(szMessage, "save gun") != -1 || containi(szMessage, "save senjata") != -1 || 
        equali(szMessage, "save") || equali(szMessage, "/save") || containi(szMessage, "fallback") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_SaveGunsCall(id);
    }

    // -------------------------------------------------------------
    // 6. SQUAD INTEL & STATUS QUERIES (Utility, Economy, Recon, Damage)
    // -------------------------------------------------------------
    if (containi(szMessage, "utility?") != -1 || containi(szMessage, "nades?") != -1 || 
        containi(szMessage, "granat?") != -1 || containi(szMessage, "ada flash?") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_UtilityReport(id);
    }

    if (containi(szMessage, "money?") != -1 || containi(szMessage, "cash?") != -1 || 
        containi(szMessage, "duit?") != -1 || containi(szMessage, "eco apa buy?") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_EconomyReport(id);
    }

    if (containi(szMessage, "status?") != -1 || containi(szMessage, "where?") != -1 || 
        containi(szMessage, "posisi?") != -1 || containi(szMessage, "clear?") != -1 || 
        containi(szMessage, "laporan?") != -1 || containi(szMessage, "aman ga?") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_ReconReport(id);
    }

    if (containi(szMessage, "damage?") != -1 || containi(szMessage, "hp?") != -1 || 
        containi(szMessage, "musuh kena berapa?") != -1 || containi(szMessage, "hit berapa?") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_DamageReport(id);
    }

    // -------------------------------------------------------------
    // 7. SQUAD PACING & STEALTH (Walk, Shift, Hold, Play Slow)
    // -------------------------------------------------------------
    if (containi(szMessage, "walk") != -1 || containi(szMessage, "shift") != -1 || 
        containi(szMessage, "quiet") != -1 || containi(szMessage, "jalan pelan") != -1 || 
        containi(szMessage, "step") != -1 || containi(szMessage, "jangan lari") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_SilentWalkCall(id);
    }

    if (containi(szMessage, "hold") != -1 || containi(szMessage, "play slow") != -1 || 
        containi(szMessage, "wait for pick") != -1 || containi(szMessage, "tahan") != -1 || 
        containi(szMessage, "jangan intip") != -1)
    {
        g_flLastChatCallTime[id] = flGameTime;
        return Execute_HoldAngleCall(id);
    }

    return false;
}

// ==============================================================================
// 7. INTERACTIVE WEAPON DROP ENGINE
// ==============================================================================
public HandleSay(id)
{
    new szMessage[64];
    read_args(szMessage, charsmax(szMessage));
    remove_quotes(szMessage);
    trim(szMessage);

    if (szMessage[0] == EOS)
        return PLUGIN_CONTINUE;

    // Process v3.4 Tactical Chat Calls first if enabled
    if (get_pcvar_num(g_pCvarChatCalls) && is_user_connected(id) && !is_user_bot(id))
    {
        if (ProcessTacticalChatCall(id, szMessage))
            return PLUGIN_CONTINUE;
    }

    if (equali(szMessage, "/role") || equali(szMessage, "role") || equali(szMessage, "/roles"))
    {
        ShowRoleMenu(id);
        return PLUGIN_HANDLED;
    }

    if (equali(szMessage, "/strat") || equali(szMessage, "/strats") || equali(szMessage, "strat"))
    {
        Cmd_OpenStratMenu(id);
        return PLUGIN_HANDLED;
    }

    // -------------------------------------------------------------
    // INTERACTIVE TEAM ECONOMY CALLS (Eco, Force Buy, Half Buy, Full Buy)
    // -------------------------------------------------------------
    if (equali(szMessage, "/eco") || equali(szMessage, "eco") || equali(szMessage, "save") || equali(szMessage, "full eco"))
    {
        Cmd_SetTeamEconomy(id, ECON_ECO);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/force") || equali(szMessage, "force") || equali(szMessage, "/forcebuy") || 
             equali(szMessage, "force buy") || equali(szMessage, "forcebuy"))
    {
        Cmd_SetTeamEconomy(id, ECON_FORCE);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/half") || equali(szMessage, "half") || equali(szMessage, "/halfbuy") || 
             equali(szMessage, "half buy") || equali(szMessage, "halfbuy") || equali(szMessage, "semi buy"))
    {
        Cmd_SetTeamEconomy(id, ECON_HALF);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/full") || equali(szMessage, "full buy") || equali(szMessage, "/fullbuy") || equali(szMessage, "buy"))
    {
        Cmd_SetTeamEconomy(id, ECON_FULL);
        return PLUGIN_HANDLED;
    }

    // -------------------------------------------------------------
    // INTERACTIVE TACTICAL STRAT CALLS (Rush A, Rush B, Default, Split)
    // -------------------------------------------------------------
    if (equali(szMessage, "/rusha") || equali(szMessage, "rush a") || equali(szMessage, "rush site a") || equali(szMessage, "a"))
    {
        SetPlayerStrat(id, STRAT_RUSH_A);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/rushb") || equali(szMessage, "rush b") || equali(szMessage, "rush site b") || equali(szMessage, "b"))
    {
        SetPlayerStrat(id, STRAT_RUSH_B);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/default") || equali(szMessage, "default") || equali(szMessage, "play slow") || equali(szMessage, "hold"))
    {
        SetPlayerStrat(id, STRAT_DEFAULT);
        return PLUGIN_HANDLED;
    }
    else if (equali(szMessage, "/split") || equali(szMessage, "split") || equali(szMessage, "split mid") || equali(szMessage, "mid"))
    {
        SetPlayerStrat(id, STRAT_SPLIT);
        return PLUGIN_HANDLED;
    }

    if (containi(szMessage, "drop") != -1)
    {
        new targetWeapon = 0;
        new m4Variant = 0;
        if (containi(szMessage, "deagle") != -1 || containi(szMessage, "dgl") != -1)
            targetWeapon = CSW_DEAGLE;
        else if (containi(szMessage, "awp") != -1 || containi(szMessage, "sniper") != -1)
            targetWeapon = CSW_AWP;
        else if (containi(szMessage, "ak") != -1 || containi(szMessage, "ak47") != -1 || containi(szMessage, "kalash") != -1)
            targetWeapon = CSW_AK47;
        else if (containi(szMessage, "m4a4") != -1 || containi(szMessage, "a4") != -1)
        {
            targetWeapon = CSW_M4A1;
            m4Variant = 1;
        }
        else if (containi(szMessage, "m4a1") != -1 || containi(szMessage, "a1") != -1)
        {
            targetWeapon = CSW_M4A1;
            m4Variant = 2;
        }
        else if (containi(szMessage, "m4") != -1)
        {
            targetWeapon = CSW_M4A1;
            m4Variant = 0; // Default to requester's preferred variant
        }
        else if (containi(szMessage, "galil") != -1)
            targetWeapon = CSW_GALIL;
        else if (containi(szMessage, "famas") != -1)
            targetWeapon = CSW_FAMAS;
        else if (containi(szMessage, "mp7") != -1 || containi(szMessage, "mp5") != -1)
            targetWeapon = CSW_MP5NAVY;
        else if (containi(szMessage, "tec9") != -1 || containi(szMessage, "tec") != -1)
            targetWeapon = CSW_P228;
        else if (containi(szMessage, "cz75") != -1 || containi(szMessage, "cz") != -1)
            targetWeapon = (cs_get_user_team(id) == CS_TEAM_T) ? CSW_MAC10 : CSW_TMP;
        else if (containi(szMessage, "bizon") != -1 || containi(szMessage, "p90") != -1)
            targetWeapon = CSW_P90;
        else if (containi(szMessage, "mag7") != -1 || containi(szMessage, "mag") != -1 || containi(szMessage, "xm1014") != -1)
            targetWeapon = CSW_XM1014;
        else if (containi(szMessage, "sawedoff") != -1 || containi(szMessage, "sawed") != -1 || containi(szMessage, "m3") != -1)
            targetWeapon = CSW_M3;
        else if (containi(szMessage, "negev") != -1 || containi(szMessage, "m249") != -1)
            targetWeapon = CSW_M249;
        else if (containi(szMessage, "scout") != -1)
            targetWeapon = CSW_SCOUT;
        else
            targetWeapon = 0; // Default team rifle

        RequestWeaponDrop(id, targetWeapon, m4Variant);
        return PLUGIN_CONTINUE;
    }

    return PLUGIN_CONTINUE;
}

SetPlayerStrat(id, iStrat)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    g_iTeamStrat[team] = iStrat;

    new szPlayerName[32];
    get_user_name(id, szPlayerName, charsmax(szPlayerName));

    BroadcastTeamCall(team, "^4[Team Strat]^3 %s^1: Calling Strat: ^4%s^1!", szPlayerName, g_szStratNames[iStrat]);
    client_cmd(id, "spk radio/roger");

    // Squad bot confirmation
    new iBotTeammate = 0;
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            iBotTeammate = i;
            break;
        }
    }
    if (iBotTeammate > 0)
    {
        new szBotName[32];
        get_user_name(iBotTeammate, szBotName, charsmax(szBotName));
        BroadcastTeamCall(team, "^4[Squad Bot]^3 %s^1: Roger that! Moving into position for ^4%s^1.", szBotName, g_szStratNames[iStrat]);
    }

    // Immediately dispatch engine radio & follow orders
    DispatchIglEngineCommand(team);
}

stock Cmd_SetTeamEconomy(id, iEconMode)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    g_iTeamEconomyCall[team] = iEconMode;

    new szCallerName[32];
    get_user_name(id, szCallerName, charsmax(szCallerName));

    switch (iEconMode)
    {
        case ECON_ECO:
        {
            BroadcastTeamCall(team, "^4[Team Economy]^3 %s^1 called: ^4FULL ECO / SAVE^1! Bots will save 100%% cash.", szCallerName);
            PlayTeamAudio(team, "spk radio/regroup");
        }
        case ECON_FORCE:
        {
            BroadcastTeamCall(team, "^4[Team Economy]^3 %s^1 called: ^4FORCE BUY^1! Spending all available cash on weapons/armor!", szCallerName);
            PlayTeamAudio(team, "spk radio/stormfront");
        }
        case ECON_HALF:
        {
            BroadcastTeamCall(team, "^4[Team Economy]^3 %s^1 called: ^4HALF BUY^1! Preserving $2,000 savings buffer for next round.", szCallerName);
            PlayTeamAudio(team, "spk radio/sticktog");
        }
        case ECON_FULL:
        {
            BroadcastTeamCall(team, "^4[Team Economy]^3 %s^1 called: ^4FULL BUY^1! Buying rifles and full equipment.", szCallerName);
            PlayTeamAudio(team, "spk radio/go_go_go");
        }
    }

    new iBotTeammate = 0;
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            iBotTeammate = i;
            break;
        }
    }
    if (iBotTeammate > 0)
    {
        new szBotName[32];
        get_user_name(iBotTeammate, szBotName, charsmax(szBotName));
        if (iEconMode == ECON_ECO)
            BroadcastTeamCall(team, "^4[Squad Bot]^3 %s^1: Copy that! Holding all money, zero spending.", szBotName);
        else if (iEconMode == ECON_FORCE)
            BroadcastTeamCall(team, "^4[Squad Bot]^3 %s^1: Understood! Buying best weapons and armor now.", szBotName);
        else if (iEconMode == ECON_HALF)
            BroadcastTeamCall(team, "^4[Squad Bot]^3 %s^1: Confirmed! Keeping money buffer for next round.", szBotName);
        else
            BroadcastTeamCall(team, "^4[Squad Bot]^3 %s^1: Roger that, full buy ready!", szBotName);
    }

    if (g_bInFreezeTime)
    {
        remove_task(TASK_ENFORCE_LOADOUTS);
        set_task(0.2, "Task_EnforceRoleLoadouts", TASK_ENFORCE_LOADOUTS);
    }
}

public Cmd_RadioNeedBackup(id)
{
    if (is_user_alive(id) && !is_user_bot(id))
    {
        new iPrimary = cs_get_user_weapon(id);
        if (!IsPrimaryRifle(iPrimary) && cs_get_user_money(id) < 2500)
        {
            RequestWeaponDrop(id, 0, 0);
        }
    }
    return PLUGIN_CONTINUE;
}

RequestWeaponDrop(requester, targetWeapon = 0, m4Variant = 0)
{
    if (!is_user_alive(requester) || !get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarDropGuns))
        return;

    new CsTeams:teamRequester = cs_get_user_team(requester);
    if (teamRequester != CS_TEAM_T && teamRequester != CS_TEAM_CT)
        return;

    new szReqName[32];
    get_user_name(requester, szReqName, charsmax(szReqName));

    if (targetWeapon <= 0)
    {
        targetWeapon = (teamRequester == CS_TEAM_T) ? CSW_AK47 : CSW_M4A1;
    }

    // Adapt weapon to team allegiance (CTs buy M4/Famas/TMP, Ts buy AK/Galil/MAC-10)
    if (teamRequester == CS_TEAM_CT)
    {
        if (targetWeapon == CSW_AK47)
            targetWeapon = CSW_M4A1;
        else if (targetWeapon == CSW_GALIL)
            targetWeapon = CSW_FAMAS;
        else if (targetWeapon == CSW_MAC10)
            targetWeapon = CSW_TMP;
    }
    else if (teamRequester == CS_TEAM_T)
    {
        if (targetWeapon == CSW_M4A1)
            targetWeapon = CSW_AK47;
        else if (targetWeapon == CSW_FAMAS)
            targetWeapon = CSW_GALIL;
        else if (targetWeapon == CSW_TMP)
            targetWeapon = CSW_MAC10;
    }

    new iCost = 0;
    new szWpnName[32];
    new bool:isSecondary = false;

    switch (targetWeapon)
    {
        case CSW_DEAGLE:
        {
            iCost = 650;
            copy(szWpnName, charsmax(szWpnName), "Desert Eagle");
            isSecondary = true;
        }
        case CSW_P228:
        {
            iCost = 600;
            copy(szWpnName, charsmax(szWpnName), "Tec-9");
            isSecondary = true;
        }
        case CSW_AK47:
        {
            iCost = 2700;
            copy(szWpnName, charsmax(szWpnName), "AK-47");
        }
        case CSW_M4A1:
        {
            iCost = 3100;
            if (m4Variant == 1)
                copy(szWpnName, charsmax(szWpnName), "M4A4");
            else if (m4Variant == 2)
                copy(szWpnName, charsmax(szWpnName), "M4A1-S");
            else
                copy(szWpnName, charsmax(szWpnName), IsPlayerM4A4(requester) ? "M4A4" : "M4A1-S");
        }
        case CSW_AWP:
        {
            iCost = 4750;
            copy(szWpnName, charsmax(szWpnName), "AWP");
        }
        case CSW_GALIL:
        {
            iCost = 2000;
            copy(szWpnName, charsmax(szWpnName), "Galil");
        }
        case CSW_FAMAS:
        {
            iCost = 2250;
            copy(szWpnName, charsmax(szWpnName), "Famas");
        }
        case CSW_MP5NAVY:
        {
            iCost = 1500;
            copy(szWpnName, charsmax(szWpnName), "MP7");
        }
        case CSW_TMP:
        {
            iCost = 1250;
            copy(szWpnName, charsmax(szWpnName), "CZ75-Auto");
        }
        case CSW_MAC10:
        {
            iCost = 1400;
            copy(szWpnName, charsmax(szWpnName), "CZ75-Auto");
        }
        case CSW_P90:
        {
            iCost = 2350;
            copy(szWpnName, charsmax(szWpnName), "PP-Bizon");
        }
        case CSW_XM1014:
        {
            iCost = 3000;
            copy(szWpnName, charsmax(szWpnName), "MAG-7");
        }
        case CSW_M3:
        {
            iCost = 1700;
            copy(szWpnName, charsmax(szWpnName), "Sawed-Off");
        }
        case CSW_M249:
        {
            iCost = 5750;
            copy(szWpnName, charsmax(szWpnName), "Negev");
        }
        case CSW_SCOUT:
        {
            iCost = 2750;
            copy(szWpnName, charsmax(szWpnName), "Scout");
        }
        default:
        {
            targetWeapon = (teamRequester == CS_TEAM_T) ? CSW_AK47 : CSW_M4A1;
            iCost = (teamRequester == CS_TEAM_T) ? 2700 : 3100;
            if (teamRequester == CS_TEAM_T)
                copy(szWpnName, charsmax(szWpnName), "AK-47");
            else
                copy(szWpnName, charsmax(szWpnName), IsPlayerM4A4(requester) ? "M4A4" : "M4A1-S");
        }
    }

    // Slot Conflict Check
    if (isSecondary)
    {
        new iCurSec = GetUserSecondaryWeapon(requester);
        if (iCurSec == targetWeapon)
        {
            client_print_color(requester, print_team_default, "^4[Weapon Drop]^1 You already have a ^4%s^1, ^4%s^1!", szWpnName, szReqName);
            return;
        }
    }
    else
    {
        new iCurPrim = GetUserPrimaryWeapon(requester);
        if (iCurPrim == targetWeapon)
        {
            client_print_color(requester, print_team_default, "^4[Weapon Drop]^1 You already have a ^4%s^1, ^4%s^1!", szWpnName, szReqName);
            return;
        }
    }

    new Float:vecReqOrigin[3];
    pev(requester, pev_origin, vecReqOrigin);

    // Search for the wealthiest bot or Support bot
    new iBestBot = 0;
    new iMaxMoney = iCost + 800; // Minimum money threshold to drop with safety buffer

    for (new i = 1; i <= 32; i++)
    {
        if (i != requester && is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == teamRequester)
        {
            new iMoney = cs_get_user_money(i);
            if (g_iPlayerRole[i] == ROLE_SUPPORT)
                iMoney += 1200;

            if (iMoney >= iMaxMoney)
            {
                new Float:vecBotOrigin[3];
                pev(i, pev_origin, vecBotOrigin);
                if (get_distance_f(vecBotOrigin, vecReqOrigin) <= 1200.0)
                {
                    iMaxMoney = iMoney;
                    iBestBot = i;
                }
            }
        }
    }

    if (iBestBot > 0)
    {
        new szBotName[32];
        get_user_name(iBestBot, szBotName, charsmax(szBotName));

        // Bot voice & chat confirmation (broadcast ONLY to teammates)
        client_cmd(requester, "spk radio/roger");
        BroadcastTeamCall(teamRequester, "^4[Weapon Drop]^3 %s %s^1: Dropping you a ^4%s^1, ^4%s^1! Catch!", 
            g_szRoleTags[g_iPlayerRole[iBestBot]], szBotName, szWpnName, szReqName);

        // Deduct money from bot
        new iCurrentMoney = cs_get_user_money(iBestBot);
        cs_set_user_money(iBestBot, max(0, iCurrentMoney - iCost));

        // Turn bot to face player
        new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
        pev(iBestBot, pev_origin, vecBotEyes);
        vecBotEyes[2] += 17.0;
        xs_vec_sub(vecReqOrigin, vecBotEyes, vecDiff);
        vector_to_angle(vecDiff, vecAimAngles);
        ClampAngles(vecAimAngles);

        set_pev(iBestBot, pev_v_angle, vecAimAngles);
        set_pev(iBestBot, pev_angles, vecAimAngles);

        // Spawn realistic dropped weapon toss
        SpawnDroppedWeaponToss(iBestBot, requester, targetWeapon, m4Variant);
    }
    else
    {
        client_print_color(requester, print_team_default, "^4[Weapon Drop]^1 No teammates have enough money ($%d) nearby to drop a %s!", iCost, szWpnName);
    }
}

SpawnDroppedWeaponToss(donor, recipient, weaponId, m4Variant = 0)
{
    new Float:vecBotEyes[3], Float:vecRecOrigin[3], Float:vecDiff[3], Float:vecAimAngles[3];
    pev(donor, pev_origin, vecBotEyes);
    vecBotEyes[2] += 17.0;
    pev(recipient, pev_origin, vecRecOrigin);

    xs_vec_sub(vecRecOrigin, vecBotEyes, vecDiff);
    vector_to_angle(vecDiff, vecAimAngles);
    ClampAngles(vecAimAngles);

    set_pev(donor, pev_v_angle, vecAimAngles);
    set_pev(donor, pev_angles, vecAimAngles);

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
    if (pev_valid(ent))
    {
        set_pev(ent, pev_classname, "cs2_dropped_rifle");
        set_pev(ent, pev_origin, vecBotEyes);

        new Float:vecVel[3];
        xs_vec_normalize(vecDiff, vecVel);
        xs_vec_mul_scalar(vecVel, 320.0, vecVel);
        vecVel[2] = 160.0; // slight arc
        set_pev(ent, pev_velocity, vecVel);

        set_pev(ent, pev_movetype, MOVETYPE_TOSS);
        set_pev(ent, pev_solid, SOLID_TRIGGER);
        set_pev(ent, pev_gravity, 1.0);
        set_pev(ent, pev_friction, 0.85);
        set_pev(ent, pev_owner, donor);
        set_pev(ent, pev_iuser1, weaponId);

        new Float:mins[3] = {-16.0, -16.0, -10.0};
        new Float:maxs[3] = {16.0, 16.0, 16.0};
        engfunc(EngFunc_SetSize, ent, mins, maxs);

        if (weaponId == CSW_AWP)
            engfunc(EngFunc_SetModel, ent, "models/w_awp.mdl");
        else if (weaponId == CSW_AK47)
            engfunc(EngFunc_SetModel, ent, "models/w_ak47.mdl");
        else if (weaponId == CSW_DEAGLE)
            engfunc(EngFunc_SetModel, ent, "models/w_deagle.mdl");
        else if (weaponId == CSW_GALIL)
            engfunc(EngFunc_SetModel, ent, "models/w_galil.mdl");
        else if (weaponId == CSW_FAMAS)
            engfunc(EngFunc_SetModel, ent, "models/w_famas.mdl");
        else if (weaponId == CSW_MP5NAVY)
        {
            if (file_exists("models/pw_models/w_mp7.mdl") || file_exists("models/pw_models/w_mp7.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_mp7.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_mp5.mdl");
        }
        else if (weaponId == CSW_SCOUT)
            engfunc(EngFunc_SetModel, ent, "models/w_scout.mdl");
        else if (weaponId == CSW_P228)
        {
            if (file_exists("models/pw_models/w_tec9.mdl") || file_exists("models/pw_models/w_tec9.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_tec9.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_p228.mdl");
        }
        else if (weaponId == CSW_TMP || weaponId == CSW_MAC10)
        {
            if (file_exists("models/pw_models/w_cz75.mdl") || file_exists("models/pw_models/w_cz75.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_cz75.mdl");
            else
                engfunc(EngFunc_SetModel, ent, (weaponId == CSW_TMP) ? "models/w_tmp.mdl" : "models/w_mac10.mdl");
        }
        else if (weaponId == CSW_P90)
        {
            if (file_exists("models/pw_models/w_bizon.mdl") || file_exists("models/pw_models/w_bizon.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_bizon.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_p90.mdl");
        }
        else if (weaponId == CSW_XM1014)
        {
            if (file_exists("models/pw_models/w_mag7.mdl") || file_exists("models/pw_models/w_mag7.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_mag7.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_xm1014.mdl");
        }
        else if (weaponId == CSW_M3)
        {
            if (file_exists("models/pw_models/w_sawedoff.mdl") || file_exists("models/pw_models/w_sawedoff.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_sawedoff.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_m3.mdl");
        }
        else if (weaponId == CSW_M249)
        {
            if (file_exists("models/pw_models/w_negev.mdl") || file_exists("models/pw_models/w_negev.mdl", true))
                engfunc(EngFunc_SetModel, ent, "models/pw_models/w_negev.mdl");
            else
                engfunc(EngFunc_SetModel, ent, "models/w_m249.mdl");
        }
        else if (weaponId == CSW_M4A1)
        {
            new bool:bM4A4 = false;
            if (m4Variant == 1)
                bM4A4 = true;
            else if (m4Variant == 2)
                bM4A4 = false;
            else
                bM4A4 = (recipient >= 1 && recipient <= 32 && is_user_connected(recipient)) ? IsPlayerM4A4(recipient) : IsPlayerM4A4(donor);

            if (bM4A4)
            {
                engfunc(EngFunc_SetModel, ent, "models/csgo_skins/ct/w_m4a4.mdl");
                set_pev(ent, pev_iuser2, 1);
            }
            else
            {
                engfunc(EngFunc_SetModel, ent, "models/w_m4a1.mdl");
                set_pev(ent, pev_iuser2, 0);
            }
        }
        else
            engfunc(EngFunc_SetModel, ent, "models/w_m4a1.mdl");

        // Despawn after 60 seconds if untouched
        set_pev(ent, pev_nextthink, get_gametime() + 60.0);
    }
}

public OnDroppedRifleTouch(ent, id)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new szClass[32];
    pev(ent, pev_classname, szClass, charsmax(szClass));
    if (!equal(szClass, "cs2_dropped_rifle"))
        return HAM_IGNORED;

    if (!is_user_alive(id))
        return HAM_IGNORED;

    new weaponId = pev(ent, pev_iuser1);
    new iGroundTier = GetRoleWeaponTier(id, weaponId, g_bRoundEnded);

    new bool:isSecondary = IsSecondaryWeapon(weaponId);
    if (isSecondary)
    {
        new iCurSec = GetUserSecondaryWeapon(id);
        if (iCurSec > 0 && iCurSec != weaponId)
        {
            DropUserSecondary(id);
        }
    }
    else
    {
        new iCurPrim = GetUserPrimaryWeapon(id);
        new iCurTier = GetRoleWeaponTier(id, iCurPrim, g_bRoundEnded);
        if (iCurPrim > 0)
        {
            if (iGroundTier > iCurTier || !is_user_bot(id))
            {
                DropUserPrimary(id);
                g_flLastWeaponSwapTime[id] = get_gametime();
            }
            else
            {
                return HAM_IGNORED;
            }
        }
    }

    if (weaponId == CSW_AK47)
    {
        give_item(id, "weapon_ak47");
        cs_set_user_bpammo(id, CSW_AK47, 90);
    }
    else if (weaponId == CSW_M4A1)
    {
        new iWpn = give_item(id, "weapon_m4a1");
        cs_set_user_bpammo(id, CSW_M4A1, 90);
        if (pev_valid(iWpn))
        {
            new iIsM4A4 = pev(ent, pev_iuser2);
            set_pev(iWpn, pev_iuser1, (iIsM4A4 == 1) ? 1 : 2);
            if (iIsM4A4 == 1 && cs_get_weapon_silen(iWpn))
                cs_set_weapon_silen(iWpn, 0, 0);
            else if (iIsM4A4 == 0 && !cs_get_weapon_silen(iWpn))
                cs_set_weapon_silen(iWpn, 1, 0);

            if (is_user_alive(id) && cs_get_user_weapon(id) == CSW_M4A1)
            {
                ExecuteHamB(Ham_Item_Deploy, iWpn);
            }
        }
    }
    else if (weaponId == CSW_AWP)
    {
        give_item(id, "weapon_awp");
        cs_set_user_bpammo(id, CSW_AWP, 30);
    }
    else if (weaponId == CSW_DEAGLE)
    {
        give_item(id, "weapon_deagle");
        cs_set_user_bpammo(id, CSW_DEAGLE, 35);
    }
    else if (weaponId == CSW_GALIL)
    {
        give_item(id, "weapon_galil");
        cs_set_user_bpammo(id, CSW_GALIL, 90);
    }
    else if (weaponId == CSW_FAMAS)
    {
        give_item(id, "weapon_famas");
        cs_set_user_bpammo(id, CSW_FAMAS, 90);
    }
    else if (weaponId == CSW_MP5NAVY)
    {
        give_item(id, "weapon_mp5navy");
        cs_set_user_bpammo(id, CSW_MP5NAVY, 120);
    }
    else if (weaponId == CSW_SCOUT)
    {
        give_item(id, "weapon_scout");
        cs_set_user_bpammo(id, CSW_SCOUT, 90);
    }
    else if (weaponId == CSW_P228)
    {
        give_item(id, "weapon_p228");
        cs_set_user_bpammo(id, CSW_P228, 52);
    }
    else if (weaponId == CSW_TMP)
    {
        give_item(id, "weapon_tmp");
        cs_set_user_bpammo(id, CSW_TMP, 90);
    }
    else if (weaponId == CSW_MAC10)
    {
        give_item(id, "weapon_mac10");
        cs_set_user_bpammo(id, CSW_MAC10, 100);
    }
    else if (weaponId == CSW_P90)
    {
        give_item(id, "weapon_p90");
        cs_set_user_bpammo(id, CSW_P90, 100);
    }
    else if (weaponId == CSW_XM1014)
    {
        give_item(id, "weapon_xm1014");
        cs_set_user_bpammo(id, CSW_XM1014, 32);
    }
    else if (weaponId == CSW_M3)
    {
        give_item(id, "weapon_m3");
        cs_set_user_bpammo(id, CSW_M3, 32);
    }
    else if (weaponId == CSW_M249)
    {
        give_item(id, "weapon_m249");
        cs_set_user_bpammo(id, CSW_M249, 200);
    }

    emit_sound(id, CHAN_ITEM, "items/gunpickup2.wav", 0.9, ATTN_NORM, 0, PITCH_NORM);

    new szGunName[16];
    if (weaponId == CSW_M4A1)
    {
        copy(szGunName, charsmax(szGunName), (pev(ent, pev_iuser2) == 1) ? "M4A4" : "M4A1-S");
    }
    else
    {
        GetWeaponCleanName(weaponId, szGunName, charsmax(szGunName));
    }
    client_print(id, print_center, "Picked up %s", szGunName);

    if (g_bRoundEnded && is_user_bot(id))
    {
        g_iSavedWeapon[id] = weaponId;
        g_bSavedWeaponForRole[id] = true;
    }

    engfunc(EngFunc_RemoveEntity, ent);
    return HAM_HANDLED;
}

public OnDroppedRifleThink(ent)
{
    if (!pev_valid(ent))
        return HAM_IGNORED;

    new szClass[32];
    pev(ent, pev_classname, szClass, charsmax(szClass));
    if (equal(szClass, "cs2_dropped_rifle"))
    {
        engfunc(EngFunc_RemoveEntity, ent);
        return HAM_HANDLED;
    }
    return HAM_IGNORED;
}

public OnWeaponBoxTouchPre(ent, id)
{
    if (!pev_valid(ent) || !is_user_alive(id) || !is_user_bot(id))
        return HAM_IGNORED;

    if (g_bInFreezeTime || !get_pcvar_num(g_pCvarWeaponScavenge) || IsWarmupActive() || IsKnifeRoundActive())
        return HAM_IGNORED;

    new Float:flGameTime = get_gametime();
    // Anti-thrashing cooldown: prevent bot from fluttering/swapping repeatedly within 4 seconds!
    if (flGameTime - g_flLastWeaponSwapTime[id] < 4.0)
        return HAM_IGNORED;

    new iGroundWpn = GetGroundWeaponType(ent);
    if (!iGroundWpn || !IsPrimaryWeapon(iGroundWpn))
        return HAM_IGNORED;

    new iGroundTier = GetRoleWeaponTier(id, iGroundWpn, g_bRoundEnded);
    new iCurPrim = GetUserPrimaryWeapon(id);
    new iCurTier = GetRoleWeaponTier(id, iCurPrim, g_bRoundEnded);

    // If ground weapon is strictly superior to currently held weapon according to role:
    if (iGroundTier > iCurTier)
    {
        if (iCurPrim > 0)
        {
            DropUserPrimary(id);
        }
        g_flLastWeaponSwapTime[id] = flGameTime;

        new szBotName[32], szGroundWpnName[32], szOldWpnName[32];
        get_user_name(id, szBotName, charsmax(szBotName));
        GetWeaponCleanName(iGroundWpn, szGroundWpnName, charsmax(szGroundWpnName));
        GetWeaponCleanName(iCurPrim, szOldWpnName, charsmax(szOldWpnName));

        new CsTeams:team = cs_get_user_team(id);
        if (iCurPrim > 0)
        {
            BroadcastTeamCall(team, "^4[Weapon Upgrade]^3 %s %s^1 upgraded: ^3%s^1 -> ^4%s^1!", 
                g_szRoleTags[g_iPlayerRole[id]], szBotName, szOldWpnName, szGroundWpnName);
        }
        else
        {
            BroadcastTeamCall(team, "^4[Weapon Pickup]^3 %s %s^1 picked up ^4%s^1!", 
                g_szRoleTags[g_iPlayerRole[id]], szBotName, szGroundWpnName);
        }

        if (g_bRoundEnded)
        {
            g_iSavedWeapon[id] = iGroundWpn;
            g_bSavedWeaponForRole[id] = true;
        }

        set_task(0.05, "Task_RefillUserAmmoDelayed", id);
    }

    return HAM_IGNORED;
}

public Task_RefillUserAmmoDelayed(id)
{
    if (is_user_alive(id))
    {
        new iPrim = GetUserPrimaryWeapon(id);
        if (iPrim > 0)
        {
            if (iPrim == CSW_AWP)
                cs_set_user_bpammo(id, CSW_AWP, 30);
            else
                cs_set_user_bpammo(id, iPrim, 90);
        }
    }
}

public Task_DeliverSavedWeapons()
{
    if (IsKnifeRoundActive() || IsWarmupActive() || !get_pcvar_num(g_pCvarRoles) || !get_pcvar_num(g_pCvarRoleDeliver))
        return;

    DeliverTeamSavedWeapons(CS_TEAM_T);
    DeliverTeamSavedWeapons(CS_TEAM_CT);
}

DeliverTeamSavedWeapons(CsTeams:team)
{
    // -------------------------------------------------------------
    // 1. AWP DELIVERY: Deliver saved AWP to team AWPer if they need it!
    // -------------------------------------------------------------
    new iAwper = 0;
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] == ROLE_AWPER)
        {
            iAwper = i;
            break;
        }
    }

    if (iAwper > 0 && GetUserPrimaryWeapon(iAwper) != CSW_AWP)
    {
        for (new donor = 1; donor <= 32; donor++)
        {
            if (donor != iAwper && is_user_alive(donor) && is_user_bot(donor) && cs_get_user_team(donor) == team)
            {
                if (GetUserPrimaryWeapon(donor) == CSW_AWP)
                {
                    new szDonorName[32], szAwperName[32];
                    get_user_name(donor, szDonorName, charsmax(szDonorName));
                    get_user_name(iAwper, szAwperName, charsmax(szAwperName));

                    if (!is_user_bot(iAwper))
                    {
                        SpawnDroppedWeaponToss(donor, iAwper, CSW_AWP);
                        StripUserPrimary(donor);
                        PlayTeamAudio(team, "spk radio/roger");
                        BroadcastTeamCall(team, "^4[Role Delivery]^3 %s %s^1: Saved an ^4AWP^1 last round! Dropped for Sniper ^4%s^1!", 
                            g_szRoleTags[g_iPlayerRole[donor]], szDonorName, szAwperName);
                    }
                    else
                    {
                        if (cs_get_user_hasprim(iAwper))
                        {
                            StripUserPrimary(iAwper);
                        }
                        StripUserPrimary(donor);
                        give_item(iAwper, "weapon_awp");
                        cs_set_user_bpammo(iAwper, CSW_AWP, 30);
                        give_item(iAwper, "weapon_deagle");
                        cs_set_user_bpammo(iAwper, CSW_DEAGLE, 35);
                        give_item(iAwper, "item_assaultsuit");

                        BroadcastTeamCall(team, "^4[Role Delivery]^3 %s %s^1 passed saved ^4AWP^1 to Sniper %s %s^1!", 
                            g_szRoleTags[g_iPlayerRole[donor]], szDonorName, g_szRoleTags[ROLE_AWPER], szAwperName);
                    }

                    g_iSavedWeapon[donor] = 0;
                    g_bSavedWeaponForRole[donor] = false;
                    break;
                }
            }
        }
    }

    // -------------------------------------------------------------
    // 2. RIFLE DELIVERY (AK-47 / M4A1): Drop saved rifle to broke or Entry
    // -------------------------------------------------------------
    for (new donor = 1; donor <= 32; donor++)
    {
        if (is_user_alive(donor) && is_user_bot(donor) && cs_get_user_team(donor) == team)
        {
            new iDonorPrim = GetUserPrimaryWeapon(donor);
            new bool:bHasRifle = (iDonorPrim == CSW_AK47 || iDonorPrim == CSW_M4A1);

            if ((g_bSavedWeaponForRole[donor] && bHasRifle) || (g_iPlayerRole[donor] == ROLE_SUPPORT && cs_get_user_money(donor) >= 5500 && bHasRifle))
            {
                new iRecipient = 0;

                // Priority A: Human player with no primary
                for (new p = 1; p <= 32; p++)
                {
                    if (is_user_alive(p) && !is_user_bot(p) && cs_get_user_team(p) == team)
                    {
                        if (!cs_get_user_hasprim(p))
                        {
                            iRecipient = p;
                            break;
                        }
                    }
                }

                // Priority B: Entry Fragger with no primary or broke
                if (!iRecipient)
                {
                    for (new p = 1; p <= 32; p++)
                    {
                        if (p != donor && is_user_alive(p) && cs_get_user_team(p) == team && g_iPlayerRole[p] == ROLE_ENTRY)
                        {
                            if (!cs_get_user_hasprim(p) && cs_get_user_money(p) < 2500)
                            {
                                iRecipient = p;
                                break;
                            }
                        }
                    }
                }

                // Priority C: Any broke teammate
                if (!iRecipient)
                {
                    for (new p = 1; p <= 32; p++)
                    {
                        if (p != donor && is_user_alive(p) && cs_get_user_team(p) == team)
                        {
                            if (!cs_get_user_hasprim(p) && cs_get_user_money(p) < 2500)
                            {
                                iRecipient = p;
                                break;
                            }
                        }
                    }
                }

                if (iRecipient > 0)
                {
                    new szDonorName[32], szRecipName[32];
                    get_user_name(donor, szDonorName, charsmax(szDonorName));
                    get_user_name(iRecipient, szRecipName, charsmax(szRecipName));

                    new wpnId = (team == CS_TEAM_T) ? CSW_AK47 : CSW_M4A1;
                    new bool:bDonorM4A4 = (wpnId == CSW_M4A1) ? IsPlayerM4A4(donor) : false;

                    if (!is_user_bot(iRecipient))
                    {
                        SpawnDroppedWeaponToss(donor, iRecipient, wpnId, bDonorM4A4 ? 1 : 2);
                        StripUserPrimary(donor);
                        PlayTeamAudio(team, "spk radio/roger");
                        BroadcastTeamCall(team, "^4[Role Delivery]^3 %s %s^1 dropped saved ^4%s^1 for ^4%s^1!", 
                            g_szRoleTags[g_iPlayerRole[donor]], szDonorName, (wpnId == CSW_AK47) ? "AK-47" : (bDonorM4A4 ? "M4A4" : "M4A1-S"), szRecipName);
                    }
                    else
                    {
                        if (cs_get_user_hasprim(iRecipient))
                        {
                            StripUserPrimary(iRecipient);
                        }
                        StripUserPrimary(donor);
                        if (team == CS_TEAM_T)
                        {
                            give_item(iRecipient, "weapon_ak47");
                            cs_set_user_bpammo(iRecipient, CSW_AK47, 90);
                        }
                        else
                        {
                            new iWpn = give_item(iRecipient, "weapon_m4a1");
                            cs_set_user_bpammo(iRecipient, CSW_M4A1, 90);
                            if (pev_valid(iWpn))
                            {
                                set_pev(iWpn, pev_iuser1, bDonorM4A4 ? 1 : 2);
                                if (bDonorM4A4 && cs_get_weapon_silen(iWpn))
                                    cs_set_weapon_silen(iWpn, 0, 0);
                                else if (!bDonorM4A4 && !cs_get_weapon_silen(iWpn))
                                    cs_set_weapon_silen(iWpn, 1, 0);

                                if (is_user_alive(iRecipient) && cs_get_user_weapon(iRecipient) == CSW_M4A1)
                                {
                                    ExecuteHamB(Ham_Item_Deploy, iWpn);
                                }
                            }
                        }
                        give_item(iRecipient, "item_assaultsuit");

                        BroadcastTeamCall(team, "^4[Role Delivery]^3 %s %s^1 passed saved ^4%s^1 to %s %s^1!", 
                            g_szRoleTags[g_iPlayerRole[donor]], szDonorName, (wpnId == CSW_AK47) ? "AK-47" : (bDonorM4A4 ? "M4A4" : "M4A1-S"), 
                            g_szRoleTags[g_iPlayerRole[iRecipient]], szRecipName);
                    }

                    g_iSavedWeapon[donor] = 0;
                    g_bSavedWeaponForRole[donor] = false;
                }
            }
        }
    }
}

public Event_RoundEnd()
{
    g_bRoundEnded = true;
    g_flRoundEndTime = get_gametime();
}

public Event_RoundEndAudio()
{
    g_bRoundEnded = true;
    g_flRoundEndTime = get_gametime();
}

public Task_ScavengeGroundWeapons()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarWeaponScavenge) || g_bInFreezeTime || IsWarmupActive() || IsKnifeRoundActive())
        return;

    new Float:flGameTime = get_gametime();

    for (new id = 1; id <= 32; id++)
    {
        if (!is_user_alive(id) || !is_user_bot(id))
            continue;

        // Skip if currently engaged in close dueling (unless round ended)
        if (!g_bRoundEnded && (flGameTime - g_flLastCombatTime[id] < 2.0))
            continue;

        // Only scavenge for 7 seconds after round end
        if (g_bRoundEnded && (flGameTime - g_flRoundEndTime > 7.0))
            continue;

        // Skip scavenging if bot recently swapped weapons (< 4.0s)
        if (flGameTime - g_flLastWeaponSwapTime[id] < 4.0)
            continue;

        new iCurPrim = GetUserPrimaryWeapon(id);
        new iCurTier = GetRoleWeaponTier(id, iCurPrim, g_bRoundEnded);

        // If bot already has their role's top weapon (Tier 4), skip scavenging unless round ended (saving for teammate)
        if (iCurTier >= 4 && !g_bRoundEnded)
            continue;

        new iBestEnt = 0;
        new iBestTier = iCurTier;
        new Float:flBestDist = g_bRoundEnded ? 2500.0 : 650.0;
        new Float:vecBotOrigin[3];
        pev(id, pev_origin, vecBotOrigin);

        // 1. Scan dropped weaponbox entities
        new ent = -1;
        while ((ent = find_ent_by_class(ent, "weaponbox")))
        {
            if (!pev_valid(ent))
                continue;

            new iWpn = GetGroundWeaponType(ent);
            new iTier = GetRoleWeaponTier(id, iWpn, g_bRoundEnded);

            if (iTier > iBestTier)
            {
                new Float:vecWpnOrigin[3];
                pev(ent, pev_origin, vecWpnOrigin);
                new Float:flDist = get_distance_f(vecBotOrigin, vecWpnOrigin);

                if (flDist < flBestDist)
                {
                    flBestDist = flDist;
                    iBestEnt = ent;
                    iBestTier = iTier;
                }
            }
        }

        // 2. Scan custom cs2_dropped_rifle entities
        ent = -1;
        while ((ent = find_ent_by_class(ent, "cs2_dropped_rifle")))
        {
            if (!pev_valid(ent))
                continue;

            new iWpn = pev(ent, pev_iuser1);
            new iTier = GetRoleWeaponTier(id, iWpn, g_bRoundEnded);

            if (iTier > iBestTier)
            {
                new Float:vecWpnOrigin[3];
                pev(ent, pev_origin, vecWpnOrigin);
                new Float:flDist = get_distance_f(vecBotOrigin, vecWpnOrigin);

                if (flDist < flBestDist)
                {
                    flBestDist = flDist;
                    iBestEnt = ent;
                    iBestTier = iTier;
                }
            }
        }

        if (iBestEnt > 0)
        {
            g_iScavengeTarget[id] = iBestEnt;
            g_flScavengeExpire[id] = flGameTime + (g_bRoundEnded ? 6.0 : 3.5);
        }
    }
}

public Task_EconomyWeaponDrop()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarDropGuns) || IsWarmupActive() || IsKnifeRoundActive())
        return;

    RunTeamEconomyDrop(CS_TEAM_T);
    RunTeamEconomyDrop(CS_TEAM_CT);
}

stock GetMatchRoundNumber()
{
    new pCvar = get_cvar_pointer("amx_csgo_current_round");
    if (pCvar)
    {
        new iCvarRound = get_pcvar_num(pCvar);
        if (iCvarRound > 0)
            return iCvarRound;
    }
    return g_iRoundCount;
}

stock RunTeamEconomyDrop(CsTeams:team)
{
    if (IsKnifeRoundActive())
        return;

    new iRoundNum = GetMatchRoundNumber();
    new iRoundInHalf = ((iRoundNum - 1) % 12) + 1; // Round within MR12 half
    // Pistol rounds: Round 1 of Half 1 or Round 1 of Half 2 (nobody drops rifles)
    if (iRoundNum <= 1 || iRoundInHalf <= 1)
        return;

    // Scan for broke bots on this team who need a weapon
    for (new poor = 1; poor <= 32; poor++)
    {
        if (is_user_alive(poor) && is_user_bot(poor) && cs_get_user_team(poor) == team)
        {
            if (cs_get_user_hasprim(poor) || GetUserPrimaryWeapon(poor) > 0)
                continue;

            new iPoorMoney = cs_get_user_money(poor);
            if (iPoorMoney >= 2200)
                continue; // Can afford budget rifle/SMG

            new wpnId = (team == CS_TEAM_T) ? CSW_AK47 : CSW_M4A1;
            new wpnCost = (team == CS_TEAM_T) ? 2700 : 3100;
            new szWpnTag[16];
            copy(szWpnTag, charsmax(szWpnTag), (team == CS_TEAM_T) ? "AK-47" : (IsPlayerM4A4(poor) ? "M4A4" : "M4A1-S"));

            // AWPer role asks for AWP ONLY if round in half >= 3 AND someone on team actually has AWP money ($5750+)
            if (g_iPlayerRole[poor] == ROLE_AWPER && iRoundInHalf >= 3)
            {
                new bool:bCanAffordAwp = false;
                for (new i = 1; i <= 32; i++)
                {
                    if (i != poor && is_user_alive(i) && cs_get_user_team(i) == team)
                    {
                        new iM = cs_get_user_money(i);
                        if (is_user_bot(i) && iM >= 5750)
                        {
                            bCanAffordAwp = true;
                            break;
                        }
                        else if (!is_user_bot(i) && (cs_get_user_hasprim(i) || GetUserPrimaryWeapon(i) > 0) && iM >= 6250)
                        {
                            bCanAffordAwp = true;
                            break;
                        }
                    }
                }

                if (bCanAffordAwp)
                {
                    wpnId = CSW_AWP;
                    wpnCost = 4750;
                    copy(szWpnTag, charsmax(szWpnTag), "AWP");
                }
            }

            // Step A: Search for wealthy bot teammate
            new iBestRichBot = 0;
            new iMaxMoney = wpnCost + 1000;

            for (new rich = 1; rich <= 32; rich++)
            {
                if (rich != poor && is_user_alive(rich) && is_user_bot(rich) && cs_get_user_team(rich) == team)
                {
                    new iMoney = cs_get_user_money(rich);
                    if (g_iPlayerRole[rich] == ROLE_SUPPORT)
                        iMoney += 800;

                    if (iMoney >= iMaxMoney)
                    {
                        iMaxMoney = iMoney;
                        iBestRichBot = rich;
                    }
                }
            }

            if (iBestRichBot > 0)
            {
                new szPoorName[32], szRichName[32];
                get_user_name(poor, szPoorName, charsmax(szPoorName));
                get_user_name(iBestRichBot, szRichName, charsmax(szRichName));

                // Broadcast drop ONLY to this specific team!
                BroadcastTeamCall(team, "^4[Weapon Drop]^3 %s %s^1: Got you, ^4%s^1! Dropping ^4%s^1! Catch!",
                    g_szRoleTags[g_iPlayerRole[iBestRichBot]], szRichName, szPoorName, szWpnTag);

                new iCurMoney = cs_get_user_money(iBestRichBot);
                cs_set_user_money(iBestRichBot, max(0, iCurMoney - wpnCost));

                SpawnDroppedWeaponToss(iBestRichBot, poor, wpnId, IsPlayerM4A4(poor) ? 1 : 2);
                return; // Limit to 1 drop per freeze time to preserve economy
            }
            else
            {
                // Step B: No bot can afford it. Check if HUMAN player is wealthy on the SAME team!
                new iRichHuman = 0;
                for (new h = 1; h <= 32; h++)
                {
                    if (is_user_alive(h) && !is_user_bot(h) && cs_get_user_team(h) == team)
                    {
                        if ((cs_get_user_hasprim(h) || GetUserPrimaryWeapon(h) > 0) && cs_get_user_money(h) >= (wpnCost + 1500))
                        {
                            iRichHuman = h;
                            break;
                        }
                    }
                }

                if (iRichHuman > 0)
                {
                    new szPoorName[32], szHumanName[32];
                    get_user_name(poor, szPoorName, charsmax(szPoorName));
                    get_user_name(iRichHuman, szHumanName, charsmax(szHumanName));

                    // Announce politely to the human player on the SAME team only
                    BroadcastTeamCall(team, "^4[Drop Request]^3 %s %s^1: Hey ^4%s^1, you're rich ($%d)! Can you drop me an ^4%s^1 please?",
                        g_szRoleTags[g_iPlayerRole[poor]], szPoorName, szHumanName, cs_get_user_money(iRichHuman), szWpnTag);
                    client_cmd(iRichHuman, "spk radio/needbackup");
                    return; // Limit to 1 request per freeze time
                }
            }
        }
    }
}

// ==============================================================================
// 7. MAIN COMBAT TICK ENGINE (FM_CmdStart)
// ==============================================================================
public OnCmdStart(id, uc_handle, seed)
{
    if (!get_pcvar_num(g_pCvarEnable))
        return FMRES_IGNORED;

    if (!is_user_alive(id) || !is_user_bot(id))
        return FMRES_IGNORED;

    // Freeze Time Enforcer: Keep bots 100% stationary in spawn alongside human players
    if (g_bInFreezeTime && !IsWarmupActive())
    {
        set_uc(uc_handle, UC_ForwardMove, 0.0);
        set_uc(uc_handle, UC_SideMove, 0.0);
        set_uc(uc_handle, UC_UpMove, 0.0);

        new iButtons = get_uc(uc_handle, UC_Buttons);
        iButtons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP | IN_ATTACK | IN_ATTACK2);
        set_uc(uc_handle, UC_Buttons, iButtons);

        set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0});
        return FMRES_HANDLED;
    }

    new Float:flGameTime = get_gametime();
    new iButtons = get_uc(uc_handle, UC_Buttons);
    new iWeapon = get_user_weapon(id);
    new bool:bIsGun = IsGunWeapon(iWeapon);
    new bool:bIsOnGround = bool:(pev(id, pev_flags) & FL_ONGROUND);
    new iRole = g_iPlayerRole[id];

    // -------------------------------------------------------------
    // KNIFE ROUND MID BRAWL & GLADIATOR COMBAT ENGINE
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarKnifeMidBrawl) && IsKnifeRoundActive() && iWeapon == CSW_KNIFE)
    {
        // Anti-Stall Tracker: After 35 seconds, alert remaining survivors
        if (flGameTime - g_flKnifeRoundStartTime > 35.0 && !g_bAntiStallTriggered)
        {
            g_bAntiStallTriggered = true;
            client_print_color(0, print_team_default, "^4[Anti-Stall]^3 Knife round > 35s! Radar beacon active, finish the brawl!");
            PlayTeamAudio(CS_TEAM_T, "spk radio/enemys");
            PlayTeamAudio(CS_TEAM_CT, "spk radio/enemys");
        }

        new CsTeams:teamBot = cs_get_user_team(id);
        new Float:vecBotOrigin[3], Float:vecBotEyes[3];
        pev(id, pev_origin, vecBotOrigin);
        pev(id, pev_view_ofs, vecBotEyes);
        xs_vec_add(vecBotOrigin, vecBotEyes, vecBotEyes);

        // Scan for nearest living enemy
        new iNearestEnemy = 0;
        new Float:flNearestDist = 999999.0;
        new Float:vecEnemyOrigin[3];

        for (new enemy = 1; enemy <= 32; enemy++)
        {
            if (is_user_alive(enemy))
            {
                new CsTeams:teamEnemy = cs_get_user_team(enemy);
                if (teamEnemy != teamBot && teamEnemy != CS_TEAM_UNASSIGNED && teamEnemy != CS_TEAM_SPECTATOR)
                {
                    pev(enemy, pev_origin, vecEnemyOrigin);
                    new Float:flDist = get_distance_f(vecBotOrigin, vecEnemyOrigin);
                    if (flDist < flNearestDist)
                    {
                        flNearestDist = flDist;
                        iNearestEnemy = enemy;
                    }
                }
            }
        }

        // Target Enemy if in pursuit range (< 950u), directly visible, or Anti-Stall is active!
        if (iNearestEnemy > 0 && (flNearestDist < 950.0 || g_bAntiStallTriggered || CanSeeDirectly(id, iNearestEnemy)))
        {
            pev(iNearestEnemy, pev_origin, vecEnemyOrigin);
            vecEnemyOrigin[2] += 12.0;

            new Float:vecDiff[3], Float:vecAimAngles[3];
            xs_vec_sub(vecEnemyOrigin, vecBotEyes, vecDiff);
            vector_to_angle(vecDiff, vecAimAngles);
            ClampAngles(vecAimAngles);

            set_uc(uc_handle, UC_ViewAngles, vecAimAngles);
            set_uc(uc_handle, UC_ForwardMove, 400.0);

            // Close-range Melee Combat
            if (flNearestDist <= 85.0)
            {
                // Heavy Right-Click Stab (195 Backstab / 65 Frontal)
                iButtons |= IN_ATTACK2;

                // Side-strafe around enemy for backstab
                new Float:flSide = (id % 2 == 0) ? 250.0 : -250.0;
                set_uc(uc_handle, UC_SideMove, flSide);
            }
            else if (flNearestDist <= 115.0)
            {
                // Fast Left-Click Slash
                iButtons |= IN_ATTACK;
            }

            if (flNearestDist < 130.0 && flNearestDist > 70.0 && bIsOnGround && random_num(1, 100) <= 25)
            {
                iButtons |= IN_JUMP;
            }

            set_uc(uc_handle, UC_Buttons, iButtons);
            return FMRES_IGNORED;
        }
        else
        {
            // During open navigation: If bot has direct line of sight to Mid, guide forward
            if (CanSeeDirectlyToPoint(vecBotEyes, g_vecMapMidPoint))
            {
                new Float:vecDiff[3], Float:vecAimAngles[3];
                xs_vec_sub(g_vecMapMidPoint, vecBotEyes, vecDiff);
                vector_to_angle(vecDiff, vecAimAngles);
                ClampAngles(vecAimAngles);

                set_uc(uc_handle, UC_ViewAngles, vecAimAngles);
                set_uc(uc_handle, UC_ForwardMove, 400.0);
                set_uc(uc_handle, UC_SideMove, 0.0);
                set_uc(uc_handle, UC_Buttons, iButtons);
                return FMRES_IGNORED;
            }
            // Otherwise, let YaPB's waypoint graph pathfind out of corridors naturally at full speed!
            set_uc(uc_handle, UC_ForwardMove, 400.0);
            return FMRES_IGNORED;
        }
    }

    // -------------------------------------------------------------
    // Tactical Lineup Throw Execution (Mid Smoke & Pop-Flash)
    // -------------------------------------------------------------
    if (g_bLineupActive[id])
    {
        if (flGameTime < g_flLineupThrowUntil[id])
        {
            set_uc(uc_handle, UC_ViewAngles, g_vecLineupAngles[id]);
            iButtons |= IN_ATTACK;
            set_uc(uc_handle, UC_Buttons, iButtons);
            set_uc(uc_handle, UC_ForwardMove, 150.0);
            return FMRES_HANDLED;
        }
        else
        {
            g_bLineupActive[id] = false;
            engclient_cmd(id, "lastinv");
        }
    }

    // -------------------------------------------------------------
    // Squad Pacing & Stealth Synchronization (v3.4)
    // -------------------------------------------------------------
    new CsTeams:teamPlayer = cs_get_user_team(id);
    if (flGameTime < g_flSilentWalkUntil[teamPlayer])
    {
        iButtons |= IN_RUN;
        iButtons &= ~IN_JUMP;
        new Float:flFwd, Float:flSide;
        get_uc(uc_handle, UC_ForwardMove, flFwd);
        get_uc(uc_handle, UC_SideMove, flSide);
        if (flFwd > 130.0) set_uc(uc_handle, UC_ForwardMove, 130.0);
        else if (flFwd < -130.0) set_uc(uc_handle, UC_ForwardMove, -130.0);
        if (flSide > 130.0) set_uc(uc_handle, UC_SideMove, 130.0);
        else if (flSide < -130.0) set_uc(uc_handle, UC_SideMove, -130.0);
    }

    // Hold Angle & Passive Defense
    if (flGameTime < g_flHoldAngleUntil[teamPlayer] && (flGameTime - g_flLastCombatTime[id] > 2.0))
    {
        set_uc(uc_handle, UC_ForwardMove, 0.0);
        set_uc(uc_handle, UC_SideMove, 0.0);
        iButtons |= IN_DUCK;
    }

    // Rear Flank Anchor Protocol
    if (flGameTime < g_flRearFlankUntil[id] && (flGameTime - g_flLastCombatTime[id] > 2.0))
    {
        set_uc(uc_handle, UC_ViewAngles, g_vecRearFlankAngle[id]);
        set_uc(uc_handle, UC_ForwardMove, 0.0);
        set_uc(uc_handle, UC_SideMove, 0.0);
        iButtons |= IN_DUCK;
    }

    // Trade-Frag Buddy Tether
    if (g_iTradeLeader[id] > 0 && is_user_alive(g_iTradeLeader[id]) && flGameTime < g_flTradeFollowUntil[id])
    {
        new Float:vecLeaderOrigin[3], Float:vecCurBotOrigin[3], Float:vecTetherDiff[3], Float:vecTetherAim[3];
        pev(g_iTradeLeader[id], pev_origin, vecLeaderOrigin);
        pev(id, pev_origin, vecCurBotOrigin);
        new Float:flLeaderDist = get_distance_f(vecCurBotOrigin, vecLeaderOrigin);
        if (flLeaderDist > 220.0)
        {
            xs_vec_sub(vecLeaderOrigin, vecCurBotOrigin, vecTetherDiff);
            vector_to_angle(vecTetherDiff, vecTetherAim);
            ClampAngles(vecTetherAim);
            set_uc(uc_handle, UC_ViewAngles, vecTetherAim);
            set_uc(uc_handle, UC_ForwardMove, 350.0);
        }
    }

    // Care & Danger Zone Awareness
    if (flGameTime < g_flDangerZoneExpire[teamPlayer] && (flGameTime - g_flLastCombatTime[id] > 2.0))
    {
        new Float:vecCurBotOrigin[3];
        pev(id, pev_origin, vecCurBotOrigin);
        new Float:flDistToDanger = get_distance_f(vecCurBotOrigin, g_vecDangerPoint[teamPlayer]);
        if (flDistToDanger <= 650.0 && flDistToDanger > 60.0)
        {
            new Float:vecEyes[3], Float:vecDiffToDanger[3], Float:vecDangerAngles[3];
            pev(id, pev_view_ofs, vecEyes);
            xs_vec_add(vecCurBotOrigin, vecEyes, vecEyes);
            xs_vec_sub(g_vecDangerPoint[teamPlayer], vecEyes, vecDiffToDanger);
            vector_to_angle(vecDiffToDanger, vecDangerAngles);
            ClampAngles(vecDangerAngles);
            set_uc(uc_handle, UC_ViewAngles, vecDangerAngles);
            set_uc(uc_handle, UC_ForwardMove, 160.0);
            iButtons |= IN_RUN;
        }
    }

    // -------------------------------------------------------------
    // Bombsite Rush / Strat Objective Guidance (First 25s of gun round)
    // -------------------------------------------------------------
    if (!IsKnifeRoundActive() && g_bBombsitesFound && (flGameTime - g_flRoundStartTime < 25.0) && (flGameTime - g_flLastCombatTime[id] > 3.0))
    {
        new CsTeams:teamBot = cs_get_user_team(id);
        new iStrat = g_iTeamStrat[teamBot];
        if (iStrat == STRAT_RUSH_A || iStrat == STRAT_RUSH_B)
        {
            new Float:vecTargetSite[3];
            xs_vec_copy((iStrat == STRAT_RUSH_A) ? g_vecBombsiteA : g_vecBombsiteB, vecTargetSite);

            new Float:vecBotOrigin[3], Float:vecBotEyes[3];
            pev(id, pev_origin, vecBotOrigin);
            pev(id, pev_view_ofs, vecBotEyes);
            xs_vec_add(vecBotOrigin, vecBotEyes, vecBotEyes);

            if (CanSeeDirectlyToPoint(vecBotEyes, vecTargetSite))
            {
                new Float:vecDiff[3], Float:vecAimAngles[3];
                xs_vec_sub(vecTargetSite, vecBotEyes, vecDiff);
                vector_to_angle(vecDiff, vecAimAngles);
                ClampAngles(vecAimAngles);

                set_uc(uc_handle, UC_ViewAngles, vecAimAngles);
                set_uc(uc_handle, UC_ForwardMove, 400.0);
                set_uc(uc_handle, UC_SideMove, 0.0);
                set_uc(uc_handle, UC_Buttons, iButtons);
                return FMRES_IGNORED;
            }
        }
    }

    // -------------------------------------------------------------
    // Anti-Flash Dodge State: Bot is currently turning away & ducking
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarAntiFlash) && g_flFlashDodgeUntil[id] > flGameTime)
    {
        iButtons |= IN_DUCK;
        iButtons &= ~IN_ATTACK;
        set_uc(uc_handle, UC_Buttons, iButtons);
        return FMRES_IGNORED;
    }

    // -------------------------------------------------------------
    // High-IQ Fake Defuse Ambush State
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarFakeDefuse) && g_flFakeDefuseAmbushUntil[id] > flGameTime)
    {
        iButtons &= ~IN_USE;
        iButtons |= IN_DUCK;
        set_uc(uc_handle, UC_Buttons, iButtons);
        set_uc(uc_handle, UC_ViewAngles, g_vecFakeDefuseAmbushAngle[id]);
        set_uc(uc_handle, UC_ForwardMove, 0.0);
        set_uc(uc_handle, UC_SideMove, 0.0);
        return FMRES_IGNORED;
    }

    // -------------------------------------------------------------
    // Tactical Reload Cover: If out of ammo in combat, duck and back away
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarReloadCover) && bIsGun && (flGameTime - g_flLastCombatTime[id] < 3.0))
    {
        new iClip, iAmmo;
        get_user_weapon(id, iClip, iAmmo);
        if (iClip <= 0 && iAmmo > 0)
        {
            iButtons |= IN_DUCK;
            set_uc(uc_handle, UC_Buttons, iButtons);
            set_uc(uc_handle, UC_ForwardMove, -350.0);
            return FMRES_IGNORED;
        }
    }

    // -------------------------------------------------------------
    // Scout Jump-Apex Shot (CS 1.6 100% accuracy midair apex)
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarJumpScout))
    {
        if (iWeapon == CSW_SCOUT && !bIsOnGround)
        {
            new Float:vecVel[3];
            pev(id, pev_velocity, vecVel);
            if (floatabs(vecVel[2]) < 35.0 && (flGameTime - g_flLastCombatTime[id] < 1.5))
            {
                new Float:vecStart[3], Float:vecViewOfs[3], Float:vecVAngle[3], Float:vecForward[3], Float:vecEnd[3], Float:vecHitEnd[3];
                pev(id, pev_origin, vecStart);
                pev(id, pev_view_ofs, vecViewOfs);
                xs_vec_add(vecStart, vecViewOfs, vecStart);

                pev(id, pev_v_angle, vecVAngle);
                angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);
                xs_vec_mul_scalar(vecForward, 3500.0, vecForward);
                xs_vec_add(vecStart, vecForward, vecEnd);

                new iHit = trace_line(id, vecStart, vecEnd, vecHitEnd);
                if (iHit > 0 && iHit <= 32 && is_user_alive(iHit) && cs_get_user_team(id) != cs_get_user_team(iHit))
                {
                    iButtons |= IN_ATTACK;
                    set_uc(uc_handle, UC_Buttons, iButtons);
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Zero-Latency Triggerbot & Enemy Contact Callout
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarTriggerbot) && bIsGun)
    {
        new Float:vecStart[3], Float:vecViewOfs[3], Float:vecVAngle[3], Float:vecForward[3], Float:vecEnd[3], Float:vecHitEnd[3];
        pev(id, pev_origin, vecStart);
        pev(id, pev_view_ofs, vecViewOfs);
        xs_vec_add(vecStart, vecViewOfs, vecStart);

        pev(id, pev_v_angle, vecVAngle);
        angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);
        xs_vec_mul_scalar(vecForward, 3500.0, vecForward);
        xs_vec_add(vecStart, vecForward, vecEnd);

        new iHit = trace_line(id, vecStart, vecEnd, vecHitEnd);
        if (iHit > 0 && iHit <= 32 && is_user_alive(iHit))
        {
            new CsTeams:teamBot = cs_get_user_team(id);
            new CsTeams:teamHit = cs_get_user_team(iHit);

            if (teamBot != teamHit && teamHit != CS_TEAM_UNASSIGNED && teamHit != CS_TEAM_SPECTATOR)
            {
                iButtons |= IN_ATTACK;
                set_uc(uc_handle, UC_Buttons, iButtons);
                g_flLastCombatTime[id] = flGameTime;
                g_bHoldingAngle[id] = false;

                if (get_pcvar_num(g_pCvarCalls) && flGameTime > g_flNextContactCall[teamBot])
                {
                    g_flNextContactCall[teamBot] = flGameTime + 5.0;
                    new szBotName[32];
                    get_user_name(id, szBotName, charsmax(szBotName));
                    BroadcastTeamCall(teamBot, "^4[Intel]^3 %s %s^1: Enemy spotted! Watch the angle!", g_szRoleTags[iRole], szBotName);
                    PlayTeamAudio(teamBot, "spk radio/enemys");
                }

                if (get_pcvar_num(g_pCvarHiveMind))
                {
                    new Float:vecEnemyOrigin[3];
                    pev(iHit, pev_origin, vecEnemyOrigin);
                    g_vecTeamThreatOrigin[teamBot] = vecEnemyOrigin;
                    g_flTeamThreatTime[teamBot] = flGameTime;
                    g_iTeamThreatTarget[teamBot] = iHit;
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Auditory Sound Wallbang Burst Engine
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarWallbang) && g_iSoundTarget[id] > 0 && CanWallbang(iWeapon))
    {
        if (flGameTime < g_flSoundTargetExpire[id] && is_user_alive(g_iSoundTarget[id]))
        {
            if (flGameTime - g_flLastCombatTime[id] > 1.0)
            {
                new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
                pev(id, pev_origin, vecBotEyes);
                vecBotEyes[2] += 17.0;

                xs_vec_sub(g_vecSoundTargetOrigin[id], vecBotEyes, vecDiff);
                new Float:flDist = xs_vec_len(vecDiff);
                if (flDist > 1.0)
                {
                    vector_to_angle(vecDiff, vecAimAngles);
                    ClampAngles(vecAimAngles);
                    set_uc(uc_handle, UC_ViewAngles, vecAimAngles);

                    if (flGameTime > g_flNextWallbangBurst[id])
                    {
                        iButtons |= IN_ATTACK;
                        set_uc(uc_handle, UC_Buttons, iButtons);
                        g_flNextWallbangBurst[id] = flGameTime + random_float(0.12, 0.22);
                    }
                }
            }
        }
        else
        {
            g_iSoundTarget[id] = 0;
        }
    }

    // -------------------------------------------------------------
    // Trade-Frag Tracking
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarTradeFrag) && g_iTradeTarget[id] > 0)
    {
        if (flGameTime < g_flTradeExpire[id] && is_user_alive(g_iTradeTarget[id]))
        {
            new Float:vecBotOrigin[3], Float:vecTargetOrigin[3], Float:vecDiff[3], Float:vecAimAngles[3];
            pev(id, pev_origin, vecBotOrigin);
            vecBotOrigin[2] += 17.0;
            pev(g_iTradeTarget[id], pev_origin, vecTargetOrigin);

            xs_vec_sub(vecTargetOrigin, vecBotOrigin, vecDiff);
            new Float:flDist = xs_vec_len(vecDiff);
            if (flDist > 1.0)
            {
                vector_to_angle(vecDiff, vecAimAngles);
                ClampAngles(vecAimAngles);

                set_uc(uc_handle, UC_ViewAngles, vecAimAngles);
                set_uc(uc_handle, UC_ForwardMove, 400.0);
                g_flLastCombatTime[id] = flGameTime;
            }
        }
        else
        {
            g_iTradeTarget[id] = 0;
        }
    }

    // -------------------------------------------------------------
    // Synchronized Double-Peek (Anti-AWP Protocol)
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarDoublePeek) && g_iDoublePeekPartner[id] > 0)
    {
        if (flGameTime < g_flDoublePeekExpire[id] && is_user_alive(g_iDoublePeekPartner[id]))
        {
            if (g_bIsCrouchPeeker[id])
            {
                iButtons |= IN_DUCK;
                set_uc(uc_handle, UC_Buttons, iButtons);
                set_uc(uc_handle, UC_SideMove, 300.0);
            }
            else
            {
                set_uc(uc_handle, UC_SideMove, 400.0);
                set_uc(uc_handle, UC_ForwardMove, 250.0);
            }
        }
        else
        {
            g_iDoublePeekPartner[id] = 0;
        }
    }

    // -------------------------------------------------------------
    // Perfect Recoil Compensation (Laser Spray Transfer)
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarRecoil) && (iButtons & IN_ATTACK) && bIsGun)
    {
        new Float:vecPunch[3];
        pev(id, pev_punchangle, vecPunch);

        if (vecPunch[0] != 0.0 || vecPunch[1] != 0.0)
        {
            new Float:vecAngles[3];
            get_uc(uc_handle, UC_ViewAngles, vecAngles);

            vecAngles[0] -= (vecPunch[0] * 2.0);
            vecAngles[1] -= (vecPunch[1] * 2.0);

            ClampAngles(vecAngles);
            set_uc(uc_handle, UC_ViewAngles, vecAngles);
        }
    }

    // -------------------------------------------------------------
    // Instant Counter-Strafing: Cancel inertia when shooting
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarCounterStrafe) && (iButtons & IN_ATTACK) && bIsGun)
    {
        if (bIsOnGround)
        {
            new Float:vecVel[3];
            pev(id, pev_velocity, vecVel);
            vecVel[0] *= 0.08;
            vecVel[1] *= 0.08;
            set_pev(id, pev_velocity, vecVel);

            set_uc(uc_handle, UC_ForwardMove, 0.0);
            set_uc(uc_handle, UC_SideMove, 0.0);
        }
        g_flLastCombatTime[id] = flGameTime;
    }
    // -------------------------------------------------------------
    // Combat AD-AD Jiggle Strafe & Crouch-Tap during duels
    // -------------------------------------------------------------
    else if (get_pcvar_num(g_pCvarJiggle) && (flGameTime - g_flLastCombatTime[id] < 2.5) && bIsOnGround)
    {
        if (flGameTime > g_flNextStrafeSwitch[id])
        {
            g_bStrafeDirection[id] = !g_bStrafeDirection[id];
            g_flNextStrafeSwitch[id] = flGameTime + random_float(0.20, 0.35);
            g_bDuckTapActive[id] = (random_num(1, 100) <= 45);
        }

        new Float:flSide = g_bStrafeDirection[id] ? 400.0 : -400.0;
        set_uc(uc_handle, UC_SideMove, flSide);

        if (g_bDuckTapActive[id])
        {
            iButtons |= IN_DUCK;
            set_uc(uc_handle, UC_Buttons, iButtons);
        }
    }
    // -------------------------------------------------------------
    // Ground Weapon Scavenge & Upgrade Navigation
    // -------------------------------------------------------------
    else if (get_pcvar_num(g_pCvarWeaponScavenge) && g_iScavengeTarget[id] > 0 && !IsWarmupActive() && !IsKnifeRoundActive())
    {
        if (pev_valid(g_iScavengeTarget[id]) && flGameTime < g_flScavengeExpire[id])
        {
            if (!g_bRoundEnded && (flGameTime - g_flLastCombatTime[id] < 1.0))
            {
                g_iScavengeTarget[id] = 0;
            }
            else
            {
                new Float:vecBotOrigin[3], Float:vecWpnOrigin[3];
                pev(id, pev_origin, vecBotOrigin);
                pev(g_iScavengeTarget[id], pev_origin, vecWpnOrigin);

                new Float:flDist = get_distance_f(vecBotOrigin, vecWpnOrigin);

                if (flDist <= 95.0)
                {
                    new iGroundWpn = GetGroundWeaponType(g_iScavengeTarget[id]);
                    new iCurPrim = GetUserPrimaryWeapon(id);
                    if (GetRoleWeaponTier(id, iGroundWpn, g_bRoundEnded) > GetRoleWeaponTier(id, iCurPrim, g_bRoundEnded))
                    {
                        DropUserPrimary(id);
                        ExecuteHamB(Ham_Touch, g_iScavengeTarget[id], id);
                        g_flLastWeaponSwapTime[id] = flGameTime;
                    }
                    g_iScavengeTarget[id] = 0;
                }
                else if (CanSeeDirectlyToPoint(vecBotOrigin, vecWpnOrigin) || g_bRoundEnded)
                {
                    new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
                    pev(id, pev_view_ofs, vecBotEyes);
                    xs_vec_add(vecBotOrigin, vecBotEyes, vecBotEyes);
                    xs_vec_sub(vecWpnOrigin, vecBotEyes, vecDiff);
                    vector_to_angle(vecDiff, vecAimAngles);
                    ClampAngles(vecAimAngles);

                    set_uc(uc_handle, UC_ViewAngles, vecAimAngles);
                    set_uc(uc_handle, UC_ForwardMove, 400.0);
                    set_uc(uc_handle, UC_SideMove, 0.0);
                    return FMRES_IGNORED;
                }
            }
        }
        else
        {
            g_iScavengeTarget[id] = 0;
        }
    }
    // -------------------------------------------------------------
    // COMMON ANGLE & HOLDING ANGLE SENSE (Head-Level Crosshair Lock)
    // -------------------------------------------------------------
    else if (get_pcvar_num(g_pCvarHolding) && (flGameTime - g_flLastCombatTime[id] > 4.0))
    {
        new CsTeams:team = cs_get_user_team(id);

        if (iRole == ROLE_AWPER || team == CS_TEAM_CT || iRole == ROLE_LURKER)
        {
            if (g_bHoldingAngle[id])
            {
                if (flGameTime < g_flHoldingUntil[id])
                {
                    set_uc(uc_handle, UC_ForwardMove, 0.0);
                    set_uc(uc_handle, UC_SideMove, 0.0);

                    new Float:vecAngles[3];
                    get_uc(uc_handle, UC_ViewAngles, vecAngles);
                    vecAngles[0] = 0.0;
                    ClampAngles(vecAngles);
                    set_uc(uc_handle, UC_ViewAngles, vecAngles);

                    if (iWeapon == CSW_AWP || iWeapon == CSW_SCOUT)
                    {
                        iButtons |= IN_DUCK;
                    }

                    set_uc(uc_handle, UC_Buttons, iButtons);
                    return FMRES_IGNORED;
                }
                else
                {
                    g_bHoldingAngle[id] = false;
                }
            }
            else
            {
                if (random_num(1, 100) <= 15 && bIsOnGround)
                {
                    g_bHoldingAngle[id] = true;
                    g_flHoldingUntil[id] = flGameTime + random_float(2.0, 4.0);
                }
            }
        }

        // Stealth shift-walking for Lurker
        if (iRole == ROLE_LURKER && bIsOnGround)
        {
            new Float:flFwd;
            get_uc(uc_handle, UC_ForwardMove, flFwd);
            if (flFwd > 120.0)
            {
                set_uc(uc_handle, UC_ForwardMove, 130.0);
            }
        }

        // Tactical Jump-Peek (Only if bot_savage_bhop is explicitly enabled)
        if (get_pcvar_num(g_pCvarBhop) && bIsOnGround && random_num(1, 100) <= 8)
        {
            iButtons |= IN_JUMP;
            set_uc(uc_handle, UC_Buttons, iButtons);
        }
    }

    // -------------------------------------------------------------
    // Fake Defuse Trigger Check (Near planted C4)
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarFakeDefuse) && !g_bDidFakeDefuse[id] && cs_get_user_team(id) == CS_TEAM_CT)
    {
        CheckForPlantedC4FakeDefuse(id);
    }

    return FMRES_IGNORED;
}

// ==============================================================================
// 8. DEFENSIVE REFLEX: Anti-Flash 180-Degree Turnaround
// ==============================================================================
public Task_CheckGrenades()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarAntiFlash))
        return;

    new ent = -1;
    while ((ent = find_ent_by_class(ent, "grenade")))
    {
        if (!pev_valid(ent) || (pev(ent, pev_flags) & FL_KILLME))
            continue;

        new szModel[32];
        pev(ent, pev_model, szModel, charsmax(szModel));

        if (containi(szModel, "flashbang") == -1)
            continue;

        new Float:vecGrenadeOrigin[3];
        pev(ent, pev_origin, vecGrenadeOrigin);

        for (new i = 1; i <= 32; i++)
        {
            if (is_user_alive(i) && is_user_bot(i))
            {
                new Float:vecBotOrigin[3];
                pev(i, pev_origin, vecBotOrigin);

                new Float:flDist = get_distance_f(vecBotOrigin, vecGrenadeOrigin);
                if (flDist <= 650.0)
                {
                    TriggerAntiFlashReflex(i, vecGrenadeOrigin);
                }
            }
        }
    }
}

TriggerAntiFlashReflex(id, Float:vecGrenadeOrigin[3])
{
    new Float:vecBotOrigin[3], Float:vecViewOfs[3], Float:vecBotEyes[3];
    pev(id, pev_origin, vecBotOrigin);
    pev(id, pev_view_ofs, vecViewOfs);
    xs_vec_add(vecBotOrigin, vecViewOfs, vecBotEyes);

    new Float:vecDirToGrenade[3];
    xs_vec_sub(vecGrenadeOrigin, vecBotEyes, vecDirToGrenade);
    new Float:flDist = xs_vec_len(vecDirToGrenade);
    if (flDist < 1.0)
        return;

    xs_vec_normalize(vecDirToGrenade, vecDirToGrenade);

    new Float:vecVAngle[3], Float:vecForward[3];
    pev(id, pev_v_angle, vecVAngle);
    angle_vector(vecVAngle, ANGLEVECTOR_FORWARD, vecForward);

    new Float:flDot = xs_vec_dot(vecForward, vecDirToGrenade);
    if (flDot > 0.15)
    {
        vecVAngle[1] += 180.0;
        if (vecVAngle[1] > 180.0)
            vecVAngle[1] -= 360.0;
        
        vecVAngle[0] = 35.0;
        ClampAngles(vecVAngle);

        set_pev(id, pev_v_angle, vecVAngle);
        set_pev(id, pev_angles, vecVAngle);

        g_flFlashDodgeUntil[id] = get_gametime() + 0.75;
    }
}

// ==============================================================================
// 9. SOUND ESP SCANNER
// ==============================================================================
public Task_SoundESPScanner()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarWallbang))
        return;

    new Float:flGameTime = get_gametime();

    for (new enemy = 1; enemy <= 32; enemy++)
    {
        if (!is_user_alive(enemy))
            continue;

        new Float:vecEnemyVel[3];
        pev(enemy, pev_velocity, vecEnemyVel);
        new Float:flEnemySpeed = floatsqroot(vecEnemyVel[0] * vecEnemyVel[0] + vecEnemyVel[1] * vecEnemyVel[1]);
        new iButtons = pev(enemy, pev_button);

        new bool:bIsMakingSound = (flEnemySpeed > 175.0 && (pev(enemy, pev_flags) & FL_ONGROUND) && !(iButtons & IN_DUCK));

        if (!bIsMakingSound)
            continue;

        new Float:vecEnemyOrigin[3];
        pev(enemy, pev_origin, vecEnemyOrigin);
        vecEnemyOrigin[2] += 17.0;

        new CsTeams:teamEnemy = cs_get_user_team(enemy);

        for (new bot = 1; bot <= 32; bot++)
        {
            if (is_user_alive(bot) && is_user_bot(bot))
            {
                new CsTeams:teamBot = cs_get_user_team(bot);
                if (teamBot != teamEnemy && teamBot != CS_TEAM_UNASSIGNED && teamBot != CS_TEAM_SPECTATOR)
                {
                    new Float:vecBotOrigin[3];
                    pev(bot, pev_origin, vecBotOrigin);

                    new Float:flDist = get_distance_f(vecBotOrigin, vecEnemyOrigin);
                    if (flDist <= 750.0)
                    {
                        if (!CanSeeDirectly(bot, enemy))
                        {
                            g_iSoundTarget[bot] = enemy;
                            g_flSoundTargetExpire[bot] = flGameTime + 1.2;
                            g_vecSoundTargetOrigin[bot] = vecEnemyOrigin;
                        }
                    }
                }
            }
        }
    }
}

// ==============================================================================
// 10. HIGH-IQ FAKE DEFUSE MIND GAME
// ==============================================================================
CheckForPlantedC4FakeDefuse(id)
{
    new ent = -1;
    while ((ent = find_ent_by_class(ent, "grenade")))
    {
        if (!pev_valid(ent))
            continue;

        new szModel[32];
        pev(ent, pev_model, szModel, charsmax(szModel));
        if (containi(szModel, "c4") == -1)
            continue;

        new Float:vecC4Origin[3], Float:vecBotOrigin[3];
        pev(ent, pev_origin, vecC4Origin);
        pev(id, pev_origin, vecBotOrigin);

        if (get_distance_f(vecBotOrigin, vecC4Origin) <= 120.0)
        {
            g_bDidFakeDefuse[id] = true;
            g_flFakeDefuseAmbushUntil[id] = get_gametime() + 2.2;

            new Float:vecAngles[3];
            pev(id, pev_v_angle, vecAngles);
            vecAngles[0] = 0.0;
            g_vecFakeDefuseAmbushAngle[id] = vecAngles;
            break;
        }
    }
}

// ==============================================================================
// 11. TEAMWORK, TRADE-FRAG & EVENT CALLOUTS
// ==============================================================================
public OnPlayerKilled(victim, killer, shouldgib)
{
    if (!get_pcvar_num(g_pCvarEnable))
        return HAM_IGNORED;

    if (!is_user_connected(victim) || !is_user_connected(killer) || victim == killer)
        return HAM_IGNORED;

    new CsTeams:teamVictim = cs_get_user_team(victim);
    new CsTeams:teamKiller = cs_get_user_team(killer);

    if (teamVictim == teamKiller || teamVictim == CS_TEAM_UNASSIGNED || teamVictim == CS_TEAM_SPECTATOR)
        return HAM_IGNORED;

    new Float:vecVicOrigin[3], Float:vecKilOrigin[3];
    pev(victim, pev_origin, vecVicOrigin);
    pev(killer, pev_origin, vecKilOrigin);

    if (get_pcvar_num(g_pCvarHiveMind))
    {
        g_vecTeamThreatOrigin[teamVictim] = vecKilOrigin;
        g_flTeamThreatTime[teamVictim] = get_gametime();
        g_iTeamThreatTarget[teamVictim] = killer;
    }

    if (!get_pcvar_num(g_pCvarTradeFrag))
        return HAM_IGNORED;

    new iBestBot = 0;
    new Float:flBestDist = 1600.0;

    for (new i = 1; i <= 32; i++)
    {
        if (i != victim && is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == teamVictim)
        {
            new Float:vecOrigin[3];
            pev(i, pev_origin, vecOrigin);
            new Float:flDist = get_distance_f(vecOrigin, vecVicOrigin);

            if (g_iPlayerRole[i] == ROLE_SUPPORT)
                flDist *= 0.70;

            if (flDist < flBestDist)
            {
                flBestDist = flDist;
                iBestBot = i;
            }
        }
    }

    if (iBestBot > 0 && is_user_alive(killer))
    {
        g_iTradeTarget[iBestBot] = killer;
        g_flTradeExpire[iBestBot] = get_gametime() + 3.5;
        g_flLastCombatTime[iBestBot] = get_gametime();

        new Float:vecBotEyes[3], Float:vecDiff[3], Float:vecAimAngles[3];
        pev(iBestBot, pev_origin, vecBotEyes);
        vecBotEyes[2] += 17.0;
        xs_vec_sub(vecKilOrigin, vecBotEyes, vecDiff);
        new Float:flDist = xs_vec_len(vecDiff);
        if (flDist > 1.0)
        {
            vector_to_angle(vecDiff, vecAimAngles);
            ClampAngles(vecAimAngles);

            set_pev(iBestBot, pev_v_angle, vecAimAngles);
            set_pev(iBestBot, pev_angles, vecAimAngles);
        }

        if (get_pcvar_num(g_pCvarDoublePeek))
        {
            SetupDoublePeekPair(iBestBot, teamVictim);
        }
    }

    return HAM_IGNORED;
}

SetupDoublePeekPair(bot1, CsTeams:team)
{
    new Float:vecBot1Origin[3];
    pev(bot1, pev_origin, vecBot1Origin);

    for (new i = 1; i <= 32; i++)
    {
        if (i != bot1 && is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team)
        {
            new Float:vecBot2Origin[3];
            pev(i, pev_origin, vecBot2Origin);
            if (get_distance_f(vecBot1Origin, vecBot2Origin) <= 400.0)
            {
                g_iDoublePeekPartner[bot1] = i;
                g_iDoublePeekPartner[i] = bot1;
                g_bIsCrouchPeeker[bot1] = true;
                g_bIsCrouchPeeker[i] = false;
                new Float:flExpire = get_gametime() + 2.0;
                g_flDoublePeekExpire[bot1] = flExpire;
                g_flDoublePeekExpire[i] = flExpire;
                break;
            }
        }
    }
}

public OnPlayerTakeDamage(victim, inflictor, attacker, Float:damage, damage_type)
{
    if (!get_pcvar_num(g_pCvarEnable))
        return HAM_IGNORED;

    if (!is_user_connected(victim) || !is_user_connected(attacker) || victim == attacker)
        return HAM_IGNORED;

    new Float:flGameTime = get_gametime();

    if (is_user_bot(victim))
    {
        g_flLastCombatTime[victim] = flGameTime;
        g_bHoldingAngle[victim] = false;
    }

    if (is_user_bot(attacker))
    {
        g_flLastCombatTime[attacker] = flGameTime;
    }

    if (attacker >= 1 && attacker <= 32 && victim >= 1 && victim <= 32)
    {
        g_iLastDamageTarget[attacker] = victim;
        g_iLastDamageDealt[attacker] = floatround(damage);
        g_flLastDamageTime[attacker] = flGameTime;
    }

    if (get_pcvar_num(g_pCvarHiveMind))
    {
        new CsTeams:teamVictim = cs_get_user_team(victim);
        new CsTeams:teamAttacker = cs_get_user_team(attacker);

        if (teamVictim != teamAttacker)
        {
            new Float:vecAttackerOrigin[3];
            pev(attacker, pev_origin, vecAttackerOrigin);
            g_vecTeamThreatOrigin[teamVictim] = vecAttackerOrigin;
            g_flTeamThreatTime[teamVictim] = flGameTime;
            g_iTeamThreatTarget[teamVictim] = attacker;
        }
    }

    return HAM_IGNORED;
}

public Event_PlantTheBomb()
{
    if (!get_pcvar_num(g_pCvarCalls))
        return;

    BroadcastTeamCall(CS_TEAM_T, "^4[Bomb Intel]^3 Bomb has been planted! Hold defensive crossfires!");
    PlayTeamAudio(CS_TEAM_T, "spk radio/coverme");

    BroadcastTeamCall(CS_TEAM_CT, "^4[Bomb Intel]^1 The bomb is planted! Coordinate retake together!");
    PlayTeamAudio(CS_TEAM_CT, "spk radio/regroup");
}

public Event_DefusedTheBomb()
{
    if (!get_pcvar_num(g_pCvarCalls))
        return;

    BroadcastTeamCall(CS_TEAM_CT, "^4[Bomb Intel]^4 Bomb defused! Sector secured!");
    PlayTeamAudio(CS_TEAM_CT, "spk radio/clear");
}

// ==============================================================================
// 12. UTILITY HELPERS & AUDIO CALLS
// ==============================================================================
GetTeamIgl(CsTeams:team)
{
    // First check human IGL
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] == ROLE_IGL)
        {
            return i;
        }
    }

    // Then check bot IGL
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] == ROLE_IGL)
        {
            return i;
        }
    }

    return 0;
}

BroadcastTeamCall(CsTeams:team, const szFormat[], any:...)
{
    new szBuffer[192];
    vformat(szBuffer, charsmax(szBuffer), szFormat, 3);

    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && cs_get_user_team(i) == team)
        {
            client_print_color(i, print_team_default, "%s", szBuffer);
        }
    }
}

PlayTeamAudio(CsTeams:team, const szCommand[])
{
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_connected(i) && !is_user_bot(i) && cs_get_user_team(i) == team)
        {
            client_cmd(i, szCommand);
        }
    }
}

InitMapMidPoint()
{
    new szMap[32];
    get_mapname(szMap, charsmax(szMap));

    if (containi(szMap, "dust2") != -1)
    {
        g_vecMapMidPoint[0] = -380.0;
        g_vecMapMidPoint[1] = -800.0;
        g_vecMapMidPoint[2] = -120.0;
        g_bMidPointCalculated = true;
        return;
    }
    else if (containi(szMap, "inferno") != -1)
    {
        g_vecMapMidPoint[0] = 350.0;
        g_vecMapMidPoint[1] = 1200.0;
        g_vecMapMidPoint[2] = 160.0;
        g_bMidPointCalculated = true;
        return;
    }
    else if (containi(szMap, "mirage") != -1)
    {
        g_vecMapMidPoint[0] = -650.0;
        g_vecMapMidPoint[1] = -600.0;
        g_vecMapMidPoint[2] = -160.0;
        g_bMidPointCalculated = true;
        return;
    }
    else if (containi(szMap, "nuke") != -1)
    {
        g_vecMapMidPoint[0] = 200.0;
        g_vecMapMidPoint[1] = -600.0;
        g_vecMapMidPoint[2] = -220.0;
        g_bMidPointCalculated = true;
        return;
    }
    else if (containi(szMap, "train") != -1)
    {
        g_vecMapMidPoint[0] = 100.0;
        g_vecMapMidPoint[1] = 400.0;
        g_vecMapMidPoint[2] = -200.0;
        g_bMidPointCalculated = true;
        return;
    }
    else if (containi(szMap, "tuscan") != -1)
    {
        g_vecMapMidPoint[0] = -150.0;
        g_vecMapMidPoint[1] = 300.0;
        g_vecMapMidPoint[2] = -80.0;
        g_bMidPointCalculated = true;
        return;
    }

    new Float:vecCtSum[3], Float:vecTSum[3], Float:vecOrigin[3];
    new iCtCount = 0, iTCount = 0;

    new ent = -1;
    while ((ent = find_ent_by_class(ent, "info_player_start")))
    {
        if (pev_valid(ent))
        {
            pev(ent, pev_origin, vecOrigin);
            xs_vec_add(vecCtSum, vecOrigin, vecCtSum);
            iCtCount++;
        }
    }

    ent = -1;
    while ((ent = find_ent_by_class(ent, "info_player_deathmatch")))
    {
        if (pev_valid(ent))
        {
            pev(ent, pev_origin, vecOrigin);
            xs_vec_add(vecTSum, vecOrigin, vecTSum);
            iTCount++;
        }
    }

    if (iCtCount > 0 && iTCount > 0)
    {
        xs_vec_div_scalar(vecCtSum, float(iCtCount), vecCtSum);
        xs_vec_div_scalar(vecTSum, float(iTCount), vecTSum);

        xs_vec_add(vecCtSum, vecTSum, g_vecMapMidPoint);
        xs_vec_div_scalar(g_vecMapMidPoint, 2.0, g_vecMapMidPoint);

        new Float:vecStart[3], Float:vecEnd[3], Float:vecHit[3];
        xs_vec_copy(g_vecMapMidPoint, vecStart);
        vecStart[2] += 64.0;
        xs_vec_copy(vecStart, vecEnd);
        vecEnd[2] -= 1000.0;

        trace_line(0, vecStart, vecEnd, vecHit);
        g_vecMapMidPoint[2] = vecHit[2] + 36.0;
        g_bMidPointCalculated = true;
    }
    else
    {
        g_vecMapMidPoint[0] = 0.0;
        g_vecMapMidPoint[1] = 0.0;
        g_vecMapMidPoint[2] = 0.0;
    }
}

stock InitBombsites()
{
    g_bBombsitesFound = false;
    new ent = -1;
    new iFound = 0;
    while ((ent = find_ent_by_class(ent, "func_bomb_target")))
    {
        if (!pev_valid(ent)) continue;

        new Float:vecOrigin[3];
        pev(ent, pev_origin, vecOrigin);
        if (vecOrigin[0] == 0.0 && vecOrigin[1] == 0.0 && vecOrigin[2] == 0.0)
        {
            new Float:absmin[3], Float:absmax[3];
            pev(ent, pev_absmin, absmin);
            pev(ent, pev_absmax, absmax);
            xs_vec_add(absmin, absmax, vecOrigin);
            xs_vec_div_scalar(vecOrigin, 2.0, vecOrigin);
        }

        if (iFound == 0)
        {
            xs_vec_copy(vecOrigin, g_vecBombsiteA);
            iFound++;
        }
        else if (iFound == 1)
        {
            xs_vec_copy(vecOrigin, g_vecBombsiteB);
            iFound++;
            g_bBombsitesFound = true;
            break;
        }
    }

    if (!g_bBombsitesFound)
    {
        ent = -1;
        while ((ent = find_ent_by_class(ent, "info_bomb_target")))
        {
            if (!pev_valid(ent)) continue;

            new Float:vecOrigin[3];
            pev(ent, pev_origin, vecOrigin);
            if (iFound == 0)
            {
                xs_vec_copy(vecOrigin, g_vecBombsiteA);
                iFound++;
            }
            else if (iFound == 1)
            {
                xs_vec_copy(vecOrigin, g_vecBombsiteB);
                iFound++;
                g_bBombsitesFound = true;
                break;
            }
        }
    }
}

bool:IsKnifeRoundActive()
{
    if (get_pcvar_num(g_pCvarKnifeRoundActive) == 1)
        return true;

    return false;
}

public Task_TacticalMidLineupScanner()
{
    if (!get_pcvar_num(g_pCvarEnable) || g_bInFreezeTime || IsKnifeRoundActive() || IsWarmupActive())
        return;

    new Float:flGameTime = get_gametime();
    // Only run during opening mid clash phase (first 25 seconds)
    if (flGameTime - g_flRoundStartTime > 25.0)
        return;

    for (new id = 1; id <= 32; id++)
    {
        if (!is_user_alive(id) || !is_user_bot(id))
            continue;

        new CsTeams:team = cs_get_user_team(id);
        if (team != CS_TEAM_T && team != CS_TEAM_CT)
            continue;

        if (flGameTime - g_flLastCombatTime[id] < 3.0 || g_bLineupActive[id])
            continue;

        new iRole = g_iPlayerRole[id];
        new Float:vecBotOrigin[3];
        pev(id, pev_origin, vecBotOrigin);

        // 1. MID SMOKE LINEUP (Support / IGL / Entry / AWPer)
        if (!g_bMidSmokedThisRound[team] && (iRole == ROLE_SUPPORT || iRole == ROLE_IGL || iRole == ROLE_ENTRY || iRole == ROLE_AWPER))
        {
            if (user_has_weapon(id, CSW_SMOKEGRENADE))
            {
                new Float:flDistToMid = get_distance_f(vecBotOrigin, g_vecMapMidPoint);
                if (flDistToMid >= 350.0 && flDistToMid <= 1800.0)
                {
                    TriggerMidLineup(id, true);
                    continue;
                }
            }
        }

        // 2. MID FLASHBANG LINEUP (Entry / Support)
        if (!g_bMidFlashedThisRound[team] && (iRole == ROLE_ENTRY || iRole == ROLE_SUPPORT))
        {
            if (user_has_weapon(id, CSW_FLASHBANG))
            {
                new Float:flDistToMid = get_distance_f(vecBotOrigin, g_vecMapMidPoint);
                if (flDistToMid >= 300.0 && flDistToMid <= 1300.0)
                {
                    TriggerMidLineup(id, false);
                    continue;
                }
            }
        }
    }
}

TriggerMidLineup(id, bool:isSmoke)
{
    new CsTeams:team = cs_get_user_team(id);
    new Float:flGameTime = get_gametime();

    new Float:vecBotEyes[3], Float:vecTarget[3];
    pev(id, pev_origin, vecBotEyes);
    vecBotEyes[2] += 17.0;

    new szMapName[32];
    get_mapname(szMapName, charsmax(szMapName));

    if (containi(szMapName, "dust2") != -1)
    {
        if (team == CS_TEAM_CT)
        {
            // Smoke CT Cross & Mid Doors to cut off sniper sightline from T spawn
            vecTarget[0] = -380.0;
            vecTarget[1] = 1750.0;
            vecTarget[2] = -100.0;
        }
        else
        {
            // Smoke Mid Doors / Xbox from T side
            vecTarget[0] = -360.0;
            vecTarget[1] = 1600.0;
            vecTarget[2] = -100.0;
        }
    }
    else
    {
        xs_vec_copy(g_vecMapMidPoint, vecTarget);
    }

    new Float:vecDiff[3], Float:vecAimAngles[3];
    xs_vec_sub(vecTarget, vecBotEyes, vecDiff);
    vector_to_angle(vecDiff, vecAimAngles);

    // Set upward arc pitch for realistic esports lob throw (-28° to -38°)
    vecAimAngles[0] = isSmoke ? -28.0 : -38.0;
    ClampAngles(vecAimAngles);

    xs_vec_copy(vecAimAngles, g_vecLineupAngles[id]);
    g_bLineupActive[id] = true;
    g_flLineupThrowUntil[id] = flGameTime + 0.45;

    new szName[32];
    get_user_name(id, szName, charsmax(szName));

    if (isSmoke)
    {
        engclient_cmd(id, "weapon_smokegrenade");
        g_bMidSmokedThisRound[team] = true;
        BroadcastTeamCall(team, "^4[Tactical Lineup]^3 %s %s^1: Smoking Mid! Sightline blocked.",
            g_szRoleTags[g_iPlayerRole[id]], szName);
        PlayTeamAudio(team, "spk radio/stormfront");
    }
    else
    {
        engclient_cmd(id, "weapon_flashbang");
        g_bMidFlashedThisRound[team] = true;
        BroadcastTeamCall(team, "^4[Tactical Lineup]^3 %s %s^1: Pop-flashing Mid! Turn away!",
            g_szRoleTags[g_iPlayerRole[id]], szName);
        PlayTeamAudio(team, "spk radio/takingfire");
    }
}

bool:IsWarmupActive()
{
    new pCvarWarmup = get_cvar_pointer("amx_csgo_is_warmup");
    if (pCvarWarmup && get_pcvar_num(pCvarWarmup) == 1)
        return true;

    return false;
}

stock bool:CanSeeDirectlyToPoint(Float:vecStart[3], Float:vecTarget[3])
{
    new Float:vecHitEnd[3];
    new iHit = trace_line(0, vecStart, vecTarget, vecHitEnd);
    if (iHit <= 0)
    {
        new Float:flDistTotal = get_distance_f(vecStart, vecTarget);
        new Float:flDistHit = get_distance_f(vecStart, vecHitEnd);
        return (floatabs(flDistTotal - flDistHit) < 40.0);
    }
    return false;
}

stock bool:IsGunWeapon(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_P228, CSW_SCOUT, CSW_XM1014, CSW_MAC10, CSW_AUG,
             CSW_ELITE, CSW_FIVESEVEN, CSW_UMP45, CSW_SG550, CSW_GALIL,
             CSW_FAMAS, CSW_USP, CSW_GLOCK18, CSW_AWP, CSW_MP5NAVY,
             CSW_M249, CSW_M3, CSW_M4A1, CSW_TMP, CSW_G3SG1,
             CSW_DEAGLE, CSW_SG552, CSW_AK47, CSW_P90:
        {
            return true;
        }
    }
    return false;
}

stock bool:IsPrimaryRifle(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_AK47, CSW_M4A1, CSW_AWP, CSW_GALIL, CSW_FAMAS, CSW_AUG, CSW_SG552, CSW_SCOUT:
        {
            return true;
        }
    }
    return false;
}

stock bool:CanWallbang(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_AK47, CSW_M4A1, CSW_AWP, CSW_DEAGLE, CSW_SG552, CSW_AUG, CSW_G3SG1, CSW_SG550:
        {
            return true;
        }
    }
    return false;
}

stock bool:CanSeeDirectly(ent1, ent2)
{
    new Float:vecStart[3], Float:vecEnd[3], Float:vecHitEnd[3];
    pev(ent1, pev_origin, vecStart);
    vecStart[2] += 17.0;
    pev(ent2, pev_origin, vecEnd);
    vecEnd[2] += 17.0;

    new iHit = trace_line(ent1, vecStart, vecEnd, vecHitEnd);
    return (iHit == ent2);
}

stock ClampAngles(Float:angles[3])
{
    if (angles[0] < -89.0) angles[0] = -89.0;
    if (angles[0] > 89.0)  angles[0] = 89.0;

    while (angles[1] < -180.0) angles[1] += 360.0;
    while (angles[1] > 180.0)  angles[1] -= 360.0;

    angles[2] = 0.0;
}

stock GetGroundWeaponType(ent)
{
    if (!pev_valid(ent))
        return 0;

    new szClass[32];
    pev(ent, pev_classname, szClass, charsmax(szClass));

    if (equal(szClass, "cs2_dropped_rifle"))
    {
        return pev(ent, pev_iuser1);
    }

    if (equal(szClass, "weaponbox"))
    {
        new szModel[64];
        pev(ent, pev_model, szModel, charsmax(szModel));

        if (containi(szModel, "w_awp") != -1)     return CSW_AWP;
        if (containi(szModel, "w_ak47") != -1)    return CSW_AK47;
        if (containi(szModel, "w_m4a1") != -1 || containi(szModel, "w_m4a4") != -1)    return CSW_M4A1;
        if (containi(szModel, "w_sg552") != -1)   return CSW_SG552;
        if (containi(szModel, "w_aug") != -1)     return CSW_AUG;
        if (containi(szModel, "w_scout") != -1)   return CSW_SCOUT;
        if (containi(szModel, "w_galil") != -1)   return CSW_GALIL;
        if (containi(szModel, "w_famas") != -1)   return CSW_FAMAS;
        if (containi(szModel, "w_mp5") != -1)     return CSW_MP5NAVY;
        if (containi(szModel, "w_ump45") != -1)   return CSW_UMP45;
        if (containi(szModel, "w_p90") != -1)     return CSW_P90;
        if (containi(szModel, "w_m3") != -1)      return CSW_M3;
        if (containi(szModel, "w_xm1014") != -1)  return CSW_XM1014;
        if (containi(szModel, "w_m249") != -1)    return CSW_M249;
        if (containi(szModel, "w_g3sg1") != -1)   return CSW_G3SG1;
        if (containi(szModel, "w_sg550") != -1)   return CSW_SG550;
        if (containi(szModel, "w_deagle") != -1)  return CSW_DEAGLE;
    }

    return 0;
}

public Cmd_PlayerDropWeaponPre(id)
{
    if (g_bInFreezeTime && is_user_alive(id) && !is_user_bot(id))
    {
        // Player dropped a weapon in freeze time: scan spawn in 0.1s to allow entity to touch ground
        set_task(0.1, "Task_ScanSpawnDroppedWeapons", TASK_SCAN_SPAWN_WPNS);
    }
    return PLUGIN_CONTINUE;
}

public Cmd_PlayerPingPointPre(id)
{
    if (g_bInFreezeTime && is_user_alive(id) && !is_user_bot(id))
    {
        // Player pinged during freeze time: instantly scan spawn for handoff
        set_task(0.05, "Task_ScanSpawnDroppedWeapons", TASK_SCAN_SPAWN_WPNS);
    }
    return PLUGIN_CONTINUE;
}

public Task_ScanSpawnDroppedWeapons()
{
    if (IsWarmupActive() || IsKnifeRoundActive())
        return;

    ScanAndClaimSpawnDroppedWeapons(CS_TEAM_T);
    ScanAndClaimSpawnDroppedWeapons(CS_TEAM_CT);
}

stock ScanAndClaimSpawnDroppedWeapons(CsTeams:team)
{
    if (!g_bInFreezeTime || IsKnifeRoundActive() || IsWarmupActive())
        return;

    // 1. Scan dropped weaponbox entities in spawn
    new ent = -1;
    while ((ent = find_ent_by_class(ent, "weaponbox")))
    {
        if (!pev_valid(ent))
            continue;

        new Float:vecWpnOrigin[3];
        pev(ent, pev_origin, vecWpnOrigin);

        // Verify the dropped weapon is in spawn / near team players (within 1400 units)
        new bool:bNearTeam = false;
        for (new p = 1; p <= 32; p++)
        {
            if (is_user_alive(p) && cs_get_user_team(p) == team)
            {
                new Float:vecPOrigin[3];
                pev(p, pev_origin, vecPOrigin);
                if (get_distance_f(vecPOrigin, vecWpnOrigin) <= 1400.0)
                {
                    bNearTeam = true;
                    break;
                }
            }
        }

        if (!bNearTeam)
            continue;

        new iWpn = GetGroundWeaponType(ent);
        if (!iWpn || !IsPrimaryWeapon(iWpn))
            continue;

        // A. If AWP: Claim for team's AWPer bot if they need it!
        if (iWpn == CSW_AWP)
        {
            new iAwper = GetTeamAwperBot(team);
            if (iAwper > 0 && is_user_alive(iAwper) && GetUserPrimaryWeapon(iAwper) != CSW_AWP)
            {
                ClaimGroundWeaponForBot(iAwper, ent, CSW_AWP, team);
                continue;
            }
        }
        // B. If AK-47 / M4A1: Claim for Entry Fragger or broke bot without a rifle
        else if (iWpn == CSW_AK47 || iWpn == CSW_M4A1)
        {
            new iRecipient = GetTeamBestRifleRecipient(team);
            if (iRecipient > 0)
            {
                ClaimGroundWeaponForBot(iRecipient, ent, iWpn, team);
                continue;
            }
        }
    }

    // 2. Scan custom cs2_dropped_rifle in spawn
    ent = -1;
    while ((ent = find_ent_by_class(ent, "cs2_dropped_rifle")))
    {
        if (!pev_valid(ent))
            continue;

        new Float:vecWpnOrigin[3];
        pev(ent, pev_origin, vecWpnOrigin);

        new bool:bNearTeam = false;
        for (new p = 1; p <= 32; p++)
        {
            if (is_user_alive(p) && cs_get_user_team(p) == team)
            {
                new Float:vecPOrigin[3];
                pev(p, pev_origin, vecPOrigin);
                if (get_distance_f(vecPOrigin, vecWpnOrigin) <= 1400.0)
                {
                    bNearTeam = true;
                    break;
                }
            }
        }

        if (!bNearTeam)
            continue;

        new iWpn = pev(ent, pev_iuser1);
        if (!iWpn || !IsPrimaryWeapon(iWpn))
            continue;

        if (iWpn == CSW_AWP)
        {
            new iAwper = GetTeamAwperBot(team);
            if (iAwper > 0 && is_user_alive(iAwper) && GetUserPrimaryWeapon(iAwper) != CSW_AWP)
            {
                ClaimGroundWeaponForBot(iAwper, ent, CSW_AWP, team);
                continue;
            }
        }
        else if (iWpn == CSW_AK47 || iWpn == CSW_M4A1)
        {
            new iRecipient = GetTeamBestRifleRecipient(team);
            if (iRecipient > 0)
            {
                ClaimGroundWeaponForBot(iRecipient, ent, iWpn, team);
                continue;
            }
        }
    }
}

stock ClaimGroundWeaponForBot(bot, ent, weaponId, CsTeams:team)
{
    new szBotName[32];
    get_user_name(bot, szBotName, charsmax(szBotName));

    // Strip previous inferior primary weapon if holding one
    new iCurPrim = GetUserPrimaryWeapon(bot);
    if (iCurPrim > 0)
    {
        StripUserPrimary(bot);
    }

    // Remove ground entity cleanly
    if (pev_valid(ent))
    {
        engfunc(EngFunc_RemoveEntity, ent);
    }

    // Equip the bot
    if (weaponId == CSW_AWP)
    {
        give_item(bot, "weapon_awp");
        cs_set_user_bpammo(bot, CSW_AWP, 30);
        give_item(bot, "weapon_deagle");
        cs_set_user_bpammo(bot, CSW_DEAGLE, 35);
        give_item(bot, "item_assaultsuit");

        BroadcastTeamCall(team, "^4[Freeze Time Drop]^3 %s (AWPer)^1: Claimed dropped ^4AWP^1 from spawn! Kept $4750 team economy!", szBotName);
        PlayTeamAudio(team, "spk radio/roger");
    }
    else if (weaponId == CSW_AK47)
    {
        give_item(bot, "weapon_ak47");
        cs_set_user_bpammo(bot, CSW_AK47, 90);
        give_item(bot, "item_assaultsuit");

        BroadcastTeamCall(team, "^4[Freeze Time Drop]^3 %s %s^1: Claimed dropped ^4AK-47^1 from spawn!",
            g_szRoleTags[g_iPlayerRole[bot]], szBotName);
        PlayTeamAudio(team, "spk radio/roger");
    }
    else if (weaponId == CSW_M4A1)
    {
        new iWpn = give_item(bot, "weapon_m4a1");
        cs_set_user_bpammo(bot, CSW_M4A1, 90);
        if (pev_valid(iWpn))
        {
            new bool:bM4A4 = IsPlayerM4A4(bot);
            set_pev(iWpn, pev_iuser1, bM4A4 ? 1 : 2);
            if (bM4A4 && cs_get_weapon_silen(iWpn))
                cs_set_weapon_silen(iWpn, 0, 0);
            else if (!bM4A4 && !cs_get_weapon_silen(iWpn))
                cs_set_weapon_silen(iWpn, 1, 0);
        }
        give_item(bot, "item_assaultsuit");

        BroadcastTeamCall(team, "^4[Freeze Time Drop]^3 %s %s^1: Claimed dropped ^4%s^1 from spawn!",
            g_szRoleTags[g_iPlayerRole[bot]], szBotName, IsPlayerM4A4(bot) ? "M4A4" : "M4A1-S");
        PlayTeamAudio(team, "spk radio/roger");
    }

    emit_sound(bot, CHAN_ITEM, "items/gunpickup2.wav", 0.9, ATTN_NORM, 0, PITCH_NORM);
    g_flLastWeaponSwapTime[bot] = get_gametime();
}

stock GetTeamAwperBot(CsTeams:team)
{
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] == ROLE_AWPER)
            return i;
    }
    return 0;
}

stock GetTeamBestRifleRecipient(CsTeams:team)
{
    // Priority 1: Entry Fragger without primary
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] == ROLE_ENTRY)
        {
            if (GetUserPrimaryWeapon(i) == 0)
                return i;
        }
    }
    // Priority 2: Any non-AWP bot without primary
    for (new i = 1; i <= 32; i++)
    {
        if (is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == team && g_iPlayerRole[i] != ROLE_AWPER)
        {
            if (GetUserPrimaryWeapon(i) == 0)
                return i;
        }
    }
    return 0;
}

stock GetRoleWeaponTier(id, weapon_id, bool:bRoundEnded)
{
    if (weapon_id <= 0)
        return 0;

    new iRole = (id >= 1 && id <= 32) ? g_iPlayerRole[id] : ROLE_NONE;

    // For AWPer: AWP is always Tier 4 (pinnacle weapon)
    if (iRole == ROLE_AWPER)
    {
        switch (weapon_id)
        {
            case CSW_AWP: return 4;
            case CSW_AK47, CSW_M4A1, CSW_SG552, CSW_AUG: return 3;
            case CSW_GALIL, CSW_FAMAS, CSW_SCOUT, CSW_G3SG1, CSW_SG550: return 2;
            case CSW_MP5NAVY, CSW_UMP45, CSW_P90, CSW_MAC10, CSW_TMP, CSW_XM1014, CSW_M3, CSW_M249: return 1;
        }
        return 0;
    }

    // For non-AWPers (Entry, Support, Lurker, IGL):
    // When the round has ended, any bot can scavenge an AWP to save it for the AWPer next round!
    if (bRoundEnded)
    {
        switch (weapon_id)
        {
            case CSW_AWP: return 4;
            case CSW_AK47, CSW_M4A1, CSW_SG552, CSW_AUG: return 3;
            case CSW_GALIL, CSW_FAMAS, CSW_SCOUT, CSW_G3SG1, CSW_SG550: return 2;
            case CSW_MP5NAVY, CSW_UMP45, CSW_P90, CSW_MAC10, CSW_TMP, CSW_XM1014, CSW_M3, CSW_M249: return 1;
        }
        return 0;
    }

    // During active combat (!bRoundEnded):
    // AK-47 & M4A1 are Tier 4 (Pinnacle Assault Rifles) for Entry, Support, Lurker, IGL!
    // AWP is Tier 2 (only picked up in emergency if bot has NO primary or only a pistol/SMG, never replacing AK/M4!)
    switch (weapon_id)
    {
        case CSW_AK47, CSW_M4A1: return 4;
        case CSW_SG552, CSW_AUG, CSW_GALIL, CSW_FAMAS: return 3;
        case CSW_AWP, CSW_SCOUT, CSW_G3SG1, CSW_SG550: return 2;
        case CSW_MP5NAVY, CSW_UMP45, CSW_P90, CSW_MAC10, CSW_TMP, CSW_XM1014, CSW_M3, CSW_M249: return 1;
    }
    return 0;
}

stock GetWeaponTier(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_AWP: return 4;
        case CSW_AK47, CSW_M4A1, CSW_SG552, CSW_AUG: return 3;
        case CSW_GALIL, CSW_FAMAS, CSW_SCOUT, CSW_G3SG1, CSW_SG550: return 2;
        case CSW_MP5NAVY, CSW_UMP45, CSW_P90, CSW_MAC10, CSW_TMP, CSW_XM1014, CSW_M3, CSW_M249: return 1;
    }
    return 0;
}

stock GetUserPrimaryWeapon(id)
{
    if (!is_user_alive(id))
        return 0;

    new weapons[32], numWeapons;
    get_user_weapons(id, weapons, numWeapons);
    for (new i = 0; i < numWeapons; i++)
    {
        if (IsPrimaryWeapon(weapons[i]))
            return weapons[i];
    }
    return 0;
}

stock bool:IsPrimaryWeapon(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_AK47, CSW_M4A1, CSW_AWP, CSW_GALIL, CSW_FAMAS,
             CSW_AUG, CSW_SG552, CSW_SCOUT, CSW_MP5NAVY, CSW_UMP45,
             CSW_P90, CSW_MAC10, CSW_TMP, CSW_XM1014, CSW_M3,
             CSW_M249, CSW_G3SG1, CSW_SG550:
        {
            return true;
        }
    }
    return false;
}

stock GetWeaponCleanName(weapon_id, szBuffer[], iMaxLen)
{
    switch (weapon_id)
    {
        case CSW_AK47:      copy(szBuffer, iMaxLen, "AK-47");
        case CSW_M4A1:      copy(szBuffer, iMaxLen, "M4A1");
        case CSW_AWP:       copy(szBuffer, iMaxLen, "AWP");
        case CSW_GALIL:     copy(szBuffer, iMaxLen, "Galil");
        case CSW_FAMAS:     copy(szBuffer, iMaxLen, "FAMAS");
        case CSW_SCOUT:     copy(szBuffer, iMaxLen, "Scout");
        case CSW_SG552:     copy(szBuffer, iMaxLen, "SG552");
        case CSW_AUG:       copy(szBuffer, iMaxLen, "AUG");
        case CSW_DEAGLE:    copy(szBuffer, iMaxLen, "Deagle");
        case CSW_MP5NAVY:   copy(szBuffer, iMaxLen, "MP7");
        case CSW_P228:      copy(szBuffer, iMaxLen, "Tec-9");
        case CSW_TMP:       copy(szBuffer, iMaxLen, "CZ75-Auto");
        case CSW_MAC10:     copy(szBuffer, iMaxLen, "CZ75-Auto");
        case CSW_P90:       copy(szBuffer, iMaxLen, "PP-Bizon");
        case CSW_XM1014:    copy(szBuffer, iMaxLen, "MAG-7");
        case CSW_M3:        copy(szBuffer, iMaxLen, "Sawed-Off");
        case CSW_M249:      copy(szBuffer, iMaxLen, "Negev");
        case CSW_UMP45:     copy(szBuffer, iMaxLen, "UMP-45");
        case CSW_G3SG1:     copy(szBuffer, iMaxLen, "G3SG1");
        case CSW_SG550:     copy(szBuffer, iMaxLen, "SG550");
        case CSW_USP:       copy(szBuffer, iMaxLen, "USP");
        case CSW_GLOCK18:   copy(szBuffer, iMaxLen, "Glock");
        case CSW_ELITE:     copy(szBuffer, iMaxLen, "Dual Berettas");
        case CSW_FIVESEVEN: copy(szBuffer, iMaxLen, "Five-SeveN");
        default:            copy(szBuffer, iMaxLen, "Weapon");
    }
}

stock DropUserPrimary(id)
{
    if (!is_user_alive(id))
        return 0;

    new iWeapons[32], iNum;
    get_user_weapons(id, iWeapons, iNum);
    for (new i = 0; i < iNum; i++)
    {
        if (IsPrimaryWeapon(iWeapons[i]))
        {
            new szWeapon[32];
            get_weaponname(iWeapons[i], szWeapon, charsmax(szWeapon));
            engclient_cmd(id, szWeapon);
            engclient_cmd(id, "drop", szWeapon);
            return iWeapons[i];
        }
    }
    return 0;
}

stock StripUserPrimary(id)
{
    if (!is_user_alive(id))
        return;

    new iWeapons[32], iNum;
    get_user_weapons(id, iWeapons, iNum);
    for (new i = 0; i < iNum; i++)
    {
        if (IsPrimaryWeapon(iWeapons[i]))
        {
            new szWeapon[32];
            get_weaponname(iWeapons[i], szWeapon, charsmax(szWeapon));
            ham_strip_weapon(id, szWeapon);
            break;
        }
    }
}

stock ham_strip_weapon(id, const weapon[])
{
    if (!equal(weapon, "weapon_", 7)) return 0;
    new wId = get_weaponid(weapon);
    if (!wId) return 0;
    new wEnt;
    while ((wEnt = engfunc(EngFunc_FindEntityByString, wEnt, "classname", weapon)) && pev(wEnt, pev_owner) != id) {}
    if (!pev_valid(wEnt)) return 0;
    
    if (get_user_weapon(id) == wId)
    {
        ExecuteHamB(Ham_Item_Holster, wEnt, 0);

        new activeItem = get_pdata_cbase(id, 373, 5); // m_pActiveItem
        if (activeItem == wEnt)
        {
            new knife = -1;
            while ((knife = engfunc(EngFunc_FindEntityByString, knife, "classname", "weapon_knife")) > 0)
            {
                if (pev(knife, pev_owner) == id && knife != wEnt)
                    break;
            }

            if (pev_valid(knife) && knife != wEnt)
            {
                set_pdata_cbase(id, 373, knife, 5);
                ExecuteHamB(Ham_Item_Deploy, knife);
            }
            else
            {
                set_pdata_cbase(id, 373, 0, 5);
            }
        }
    }
    ExecuteHamB(Ham_RemovePlayerItem, id, wEnt);
    set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1<<wId));
    set_pev(wEnt, pev_flags, pev(wEnt, pev_flags) | FL_KILLME);
    dllfunc(DLLFunc_Think, wEnt);
    return 1;
}

stock bool:IsSecondaryWeapon(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_P228, CSW_ELITE, CSW_FIVESEVEN, CSW_USP, CSW_GLOCK18, CSW_DEAGLE:
            return true;
    }
    return false;
}

stock GetUserSecondaryWeapon(id)
{
    if (!is_user_alive(id))
        return 0;

    new weapons[32], num;
    get_user_weapons(id, weapons, num);
    for (new i = 0; i < num; i++)
    {
        if (IsSecondaryWeapon(weapons[i]))
            return weapons[i];
    }
    return 0;
}

stock DropUserSecondary(id)
{
    if (!is_user_alive(id))
        return 0;

    new iWeapons[32], iNum;
    get_user_weapons(id, iWeapons, iNum);
    for (new i = 0; i < iNum; i++)
    {
        if (IsSecondaryWeapon(iWeapons[i]))
        {
            new szWeapon[32];
            get_weaponname(iWeapons[i], szWeapon, charsmax(szWeapon));
            engclient_cmd(id, szWeapon);
            engclient_cmd(id, "drop", szWeapon);
            return iWeapons[i];
        }
    }
    return 0;
}
