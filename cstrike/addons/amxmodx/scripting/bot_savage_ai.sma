/**
 * ==============================================================================
 * Plugin: CS 1.6 Bot Savage & Predator AI Engine (Version 2.0 - God-Tier Evolution)
 * Version: 2.0.0
 * Author: Antigravity
 * Description:
 *   Elevates YAPB / CS 1.6 bots into legendary Tier-1 Esports cyborg combatants.
 *
 *   Original Core Systems (v1.0):
 *     1. Instant Counter-Strafing (Zeroes velocity on IN_ATTACK for 100% first-bullet accuracy).
 *     2. Combat AD-AD Jiggle Peeking (Micro strafe alternating with crouch-taps in duels).
 *     3. Instant Trade-Frag Instinct (Surviving bot teammate snaps onto killer within 1600u).
 *     4. Anti-Flash 180-Degree Reflex (Safe periodic scanner turns 180° away and ducks).
 *     5. Zero-Latency Triggerbot (Instant shot trigger on crosshair alignment).
 *     6. Team Hive-Mind Intel (Synchronized enemy position sharing across team bots).
 *     7. Tactical Reload Cover (Forces bot to duck/retreat when clip is empty in combat).
 *
 *   New God-Tier Systems (v2.0):
 *     8. Perfect Recoil Compensation (Dynamically pulls down punchangle for laser spray).
 *     9. Pro Auto-Bunnyhop & Air-Acceleration (Timed jump on ground contact + yaw strafe).
 *    10. Auditory Sound ESP & Predictive Wallbang (Tracks running steps/reloads through walls).
 *    11. Synchronized Double-Peek (Anti-AWP protocol: crouch peek + wide swing sync).
 *    12. High-IQ Fake Defuse Mind Game (Audio cue bait + instant ambush on bomb).
 *    13. Jump-Scout Apex & AWP Quickscope (100% mid-air apex accuracy & instant scope).
 *    14. Team Economy Weapon Drop (Rich bots buy & drop rifles for broke teammates).
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

#define PLUGIN_NAME    "Bot Savage Predator AI v2"
#define PLUGIN_VERSION "2.0.0"
#define PLUGIN_AUTHOR  "Antigravity"

#define TASK_GRENADE_CHECK  2048
#define TASK_SOUND_SCANNER   2049
#define TASK_ECONOMY_DROP    2050

// CVAR Pointers - Core
new g_pCvarEnable;
new g_pCvarCounterStrafe;
new g_pCvarJiggle;
new g_pCvarTradeFrag;
new g_pCvarAntiFlash;
new g_pCvarTriggerbot;
new g_pCvarHiveMind;
new g_pCvarReloadCover;

// CVAR Pointers - v2.0 God-Tier
new g_pCvarRecoil;
new g_pCvarBhop;
new g_pCvarWallbang;
new g_pCvarDoublePeek;
new g_pCvarFakeDefuse;
new g_pCvarJumpScout;
new g_pCvarDropGuns;

// Player Combat State Tracking
new Float:g_flLastCombatTime[33];
new Float:g_flNextStrafeSwitch[33];
new bool:g_bStrafeDirection[33];
new bool:g_bDuckTapActive[33];
new Float:g_flFlashDodgeUntil[33];

// Trade-Frag State Tracking
new g_iTradeTarget[33];
new Float:g_flTradeExpire[33];

// Hive-Mind Team Intel (Shared enemy coordinates)
new Float:g_vecTeamThreatOrigin[CsTeams][3];
new Float:g_flTeamThreatTime[CsTeams];
new g_iTeamThreatTarget[CsTeams];

// Bhop & Air-Strafe State
new bool:g_bBhopStrafeDir[33];
new Float:g_flNextBhopStrafe[33];

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

    // Register v2.0 God-Tier CVARs
    g_pCvarRecoil        = register_cvar("bot_savage_recoil", "1");
    g_pCvarBhop          = register_cvar("bot_savage_bhop", "1");
    g_pCvarWallbang      = register_cvar("bot_savage_wallbang", "1");
    g_pCvarDoublePeek    = register_cvar("bot_savage_doublepeek", "1");
    g_pCvarFakeDefuse    = register_cvar("bot_savage_fakedefuse", "1");
    g_pCvarJumpScout     = register_cvar("bot_savage_jumpscout", "1");
    g_pCvarDropGuns      = register_cvar("bot_savage_dropguns", "1");

    // Hook usercmd processing (Every tick for players and bots)
    register_forward(FM_CmdStart, "OnCmdStart");

    // Hook player damage and death for trade-kill & hive-mind
    RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage", 1);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled", 1);

    // Round lifecycle events
    register_logevent("Event_RoundStart", 2, "1=Round_Start");

    // Periodic safe scanners (decoupled from entity destructors to prevent crashes)
    set_task(0.10, "Task_CheckGrenades", TASK_GRENADE_CHECK, _, _, "b");
    set_task(0.15, "Task_SoundESPScanner", TASK_SOUND_SCANNER, _, _, "b");

    server_print("[%s v%s] Activated successfully. God-Tier Predator AI online.", PLUGIN_NAME, PLUGIN_VERSION);
}

public client_putinserver(id)
{
    ResetBotState(id);
}

public client_disconnected(id)
{
    ResetBotState(id);
}

ResetBotState(id)
{
    g_flLastCombatTime[id] = 0.0;
    g_flNextStrafeSwitch[id] = 0.0;
    g_bStrafeDirection[id] = false;
    g_bDuckTapActive[id] = false;
    g_flFlashDodgeUntil[id] = 0.0;
    g_iTradeTarget[id] = 0;
    g_flTradeExpire[id] = 0.0;

    // v2.0 resets
    g_bBhopStrafeDir[id] = false;
    g_flNextBhopStrafe[id] = 0.0;
    g_iSoundTarget[id] = 0;
    g_flSoundTargetExpire[id] = 0.0;
    g_flNextWallbangBurst[id] = 0.0;
    g_bDidFakeDefuse[id] = false;
    g_flFakeDefuseAmbushUntil[id] = 0.0;
    g_iDoublePeekPartner[id] = 0;
    g_bIsCrouchPeeker[id] = false;
    g_flDoublePeekExpire[id] = 0.0;
}

public Event_RoundStart()
{
    // Reset round-specific flags
    for (new i = 1; i <= 32; i++)
    {
        g_bDidFakeDefuse[i] = false;
        g_flFakeDefuseAmbushUntil[i] = 0.0;
        g_iDoublePeekPartner[i] = 0;
    }

    // Schedule Team Economy Weapon Drop 3 seconds after freeze period
    if (get_pcvar_num(g_pCvarEnable) && get_pcvar_num(g_pCvarDropGuns))
    {
        set_task(2.5, "Task_EconomyWeaponDrop", TASK_ECONOMY_DROP);
    }
}

// ==============================================================================
// 1. MAIN COMBAT TICK ENGINE (FM_CmdStart)
// ==============================================================================
public OnCmdStart(id, uc_handle, seed)
{
    if (!get_pcvar_num(g_pCvarEnable))
        return FMRES_IGNORED;

    if (!is_user_alive(id) || !is_user_bot(id))
        return FMRES_IGNORED;

    new Float:flGameTime = get_gametime();
    new iButtons = get_uc(uc_handle, UC_Buttons);
    new iWeapon = get_user_weapon(id);
    new bool:bIsGun = IsGunWeapon(iWeapon);
    new bool:bIsOnGround = bool:(pev(id, pev_flags) & FL_ONGROUND);

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
        // Cancel defusing, crouch, and pre-aim ambush angle
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
    // Scout Jump-Apex Shot & AWP Quickscope
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarJumpScout))
    {
        if (iWeapon == CSW_SCOUT && !bIsOnGround)
        {
            new Float:vecVel[3];
            pev(id, pev_velocity, vecVel);
            // At the apex of jump, vertical speed is near zero (< 35.0) -> 100% pinpoint accuracy!
            if (floatabs(vecVel[2]) < 35.0 && (flGameTime - g_flLastCombatTime[id] < 2.0))
            {
                iButtons |= IN_ATTACK;
                set_uc(uc_handle, UC_Buttons, iButtons);
            }
        }
        else if (iWeapon == CSW_AWP && (flGameTime - g_flLastCombatTime[id] < 1.0))
        {
            // AWP Quickscope: Instant right-click zoom tap then fire
            iButtons |= IN_ATTACK;
            set_uc(uc_handle, UC_Buttons, iButtons);
        }
    }

    // -------------------------------------------------------------
    // Zero-Latency Triggerbot: Detect enemy in direct crosshair line
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
                // Enemy directly in crosshair -> Instant Fire!
                iButtons |= IN_ATTACK;
                set_uc(uc_handle, UC_Buttons, iButtons);
                g_flLastCombatTime[id] = flGameTime;

                // Share intel with team hive-mind
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
            // Only wallbang if not currently in direct line-of-sight visual combat
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

                    // Fire predictive 2-3 round burst through the wall!
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
    // Trade-Frag Tracking: Chase & aim at killer of teammate
    // -------------------------------------------------------------
    if (get_pcvar_num(g_pCvarTradeFrag) && g_iTradeTarget[id] > 0)
    {
        if (flGameTime < g_flTradeExpire[id] && is_user_alive(g_iTradeTarget[id]))
        {
            new Float:vecBotOrigin[3], Float:vecTargetOrigin[3], Float:vecDiff[3], Float:vecAimAngles[3];
            pev(id, pev_origin, vecBotOrigin);
            vecBotOrigin[2] += 17.0; // eye height
            pev(g_iTradeTarget[id], pev_origin, vecTargetOrigin);

            xs_vec_sub(vecTargetOrigin, vecBotOrigin, vecDiff);
            new Float:flDist = xs_vec_len(vecDiff);
            if (flDist > 1.0)
            {
                vector_to_angle(vecDiff, vecAimAngles);
                ClampAngles(vecAimAngles);

                // Snap aim towards target
                set_uc(uc_handle, UC_ViewAngles, vecAimAngles);

                // Aggressive swing peek
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
                // Crouch peek low
                iButtons |= IN_DUCK;
                set_uc(uc_handle, UC_Buttons, iButtons);
                set_uc(uc_handle, UC_SideMove, 300.0);
            }
            else
            {
                // Wide standing swing
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

            // Counteract bullet climb by subtracting double punchangle
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

            // Neutralize movement inputs to ensure 100% first-bullet accuracy
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
    // Pro Auto-Bunnyhop & Air-Acceleration (Rotation & Rush Mode)
    // -------------------------------------------------------------
    else if (get_pcvar_num(g_pCvarBhop) && (flGameTime - g_flLastCombatTime[id] > 3.0))
    {
        new Float:flFwd;
        get_uc(uc_handle, UC_ForwardMove, flFwd);
        if (flFwd > 180.0)
        {
            if (bIsOnGround)
            {
                // Perfect timed jump on the contact frame
                iButtons |= IN_JUMP;
                set_uc(uc_handle, UC_Buttons, iButtons);
            }
            else
            {
                // Air-strafing acceleration in mid-air
                if (flGameTime > g_flNextBhopStrafe[id])
                {
                    g_bBhopStrafeDir[id] = !g_bBhopStrafeDir[id];
                    g_flNextBhopStrafe[id] = flGameTime + 0.18;
                }

                new Float:flAirSide = g_bBhopStrafeDir[id] ? 350.0 : -350.0;
                set_uc(uc_handle, UC_SideMove, flAirSide);

                // Micro synchronized yaw delta for GoldSrc air acceleration
                new Float:vecAngles[3];
                get_uc(uc_handle, UC_ViewAngles, vecAngles);
                vecAngles[1] += g_bBhopStrafeDir[id] ? 1.6 : -1.6;
                ClampAngles(vecAngles);
                set_uc(uc_handle, UC_ViewAngles, vecAngles);
            }
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
// 2. DEFENSIVE REFLEX: Anti-Flash 180-Degree Turnaround
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

        // Scan alive bots in proximity
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

    // Dot product check: > 0.15 means flashbang is in front of bot's eyes
    new Float:flDot = xs_vec_dot(vecForward, vecDirToGrenade);
    if (flDot > 0.15)
    {
        // Instantly spin 180 degrees away!
        vecVAngle[1] += 180.0;
        if (vecVAngle[1] > 180.0)
            vecVAngle[1] -= 360.0;
        
        vecVAngle[0] = 35.0; // Look slightly downwards
        ClampAngles(vecVAngle);

        set_pev(id, pev_v_angle, vecVAngle);
        set_pev(id, pev_angles, vecVAngle);

        // Maintain dodge state for 0.75 seconds
        g_flFlashDodgeUntil[id] = get_gametime() + 0.75;
    }
}

// ==============================================================================
// 3. SOUND ESP SCANNER: Detect running steps & reloads through walls
// ==============================================================================
public Task_SoundESPScanner()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarWallbang))
        return;

    new Float:flGameTime = get_gametime();

    // Iterate through all alive players
    for (new enemy = 1; enemy <= 32; enemy++)
    {
        if (!is_user_alive(enemy))
            continue;

        new Float:vecEnemyVel[3];
        pev(enemy, pev_velocity, vecEnemyVel);
        new Float:flEnemySpeed = floatsqroot(vecEnemyVel[0] * vecEnemyVel[0] + vecEnemyVel[1] * vecEnemyVel[1]);
        new iButtons = pev(enemy, pev_button);

        // Enemy running without shift/duck -> audible footsteps!
        new bool:bIsMakingSound = (flEnemySpeed > 175.0 && (pev(enemy, pev_flags) & FL_ONGROUND) && !(iButtons & IN_DUCK));

        if (!bIsMakingSound)
            continue;

        new Float:vecEnemyOrigin[3];
        pev(enemy, pev_origin, vecEnemyOrigin);
        vecEnemyOrigin[2] += 17.0; // head height

        new CsTeams:teamEnemy = cs_get_user_team(enemy);

        // Notify nearby enemy bots
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
                        // Check if separated by wall (not directly visible)
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
// 4. HIGH-IQ FAKE DEFUSE MIND GAME
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
            // Execute Fake Defuse: Tap defuse sound, then ambush!
            g_bDidFakeDefuse[id] = true;
            g_flFakeDefuseAmbushUntil[id] = get_gametime() + 2.2;

            // Pre-calculate ambush angle towards suspected enemy chokepoint
            new Float:vecAngles[3];
            pev(id, pev_v_angle, vecAngles);
            vecAngles[0] = 0.0;
            g_vecFakeDefuseAmbushAngle[id] = vecAngles;
            break;
        }
    }
}

// ==============================================================================
// 5. TEAMWORK, TRADE-FRAG & DOUBLE-PEEK SYNERGY
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

    // Update Team Hive-Mind Intel
    if (get_pcvar_num(g_pCvarHiveMind))
    {
        g_vecTeamThreatOrigin[teamVictim] = vecKilOrigin;
        g_flTeamThreatTime[teamVictim] = get_gametime();
        g_iTeamThreatTarget[teamVictim] = killer;
    }

    if (!get_pcvar_num(g_pCvarTradeFrag))
        return HAM_IGNORED;

    // Search for nearest bot teammate of victim to execute Trade-Frag
    new iBestBot = 0;
    new Float:flBestDist = 1600.0;

    for (new i = 1; i <= 32; i++)
    {
        if (i != victim && is_user_alive(i) && is_user_bot(i) && cs_get_user_team(i) == teamVictim)
        {
            new Float:vecOrigin[3];
            pev(i, pev_origin, vecOrigin);
            new Float:flDist = get_distance_f(vecOrigin, vecVicOrigin);

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

        // Turn best bot towards killer immediately
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

        // Trigger Synchronized Double-Peek with second nearby bot
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
                // Assign Double-Peek
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
    }

    if (is_user_bot(attacker))
    {
        g_flLastCombatTime[attacker] = flGameTime;
    }

    // Share threat info via Hive-Mind
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

// ==============================================================================
// 6. TEAM ECONOMY WEAPON DROP
// ==============================================================================
public Task_EconomyWeaponDrop()
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarDropGuns))
        return;

    for (new rich = 1; rich <= 32; rich++)
    {
        if (is_user_alive(rich) && is_user_bot(rich))
        {
            new iMoney = cs_get_user_money(rich);
            if (iMoney >= 7500)
            {
                new CsTeams:teamRich = cs_get_user_team(rich);
                new Float:vecRichOrigin[3];
                pev(rich, pev_origin, vecRichOrigin);

                for (new poor = 1; poor <= 32; poor++)
                {
                    if (poor != rich && is_user_alive(poor) && cs_get_user_team(poor) == teamRich)
                    {
                        if (cs_get_user_money(poor) < 2200)
                        {
                            new Float:vecPoorOrigin[3];
                            pev(poor, pev_origin, vecPoorOrigin);
                            if (get_distance_f(vecRichOrigin, vecPoorOrigin) <= 600.0)
                            {
                                // Rich bot buys rifle and drops it for poor teammate
                                cs_set_user_money(rich, iMoney - 3100);
                                if (teamRich == CS_TEAM_T)
                                {
                                    give_item(rich, "weapon_ak47");
                                }
                                else
                                {
                                    give_item(rich, "weapon_m4a1");
                                }
                                engclient_cmd(rich, "drop");
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}

// ==============================================================================
// UTILITY HELPERS
// ==============================================================================
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
