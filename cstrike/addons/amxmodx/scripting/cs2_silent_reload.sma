/*
 * ==============================================================================
 * CS2 SILENT RELOAD (STANDALONE COMPONENT)
 * ==============================================================================
 * Replicates the Counter-Strike 2 "Rush Hour" update mechanic in CS 1.6:
 * - Press and hold 'R' (or Shift/Duck + 'R') to perform a silent reload.
 * - Slower reload duration (default 2.0x, exactly like CS2).
 * - Third-person body animation framerate reduced (0.5x).
 * - 100% audio suppression to enemies & teammates via FM_EmitSound.
 * - Fluid control: Releasing 'R' mid-reload accelerates back to normal speed!
 * ==============================================================================
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "CS2 Silent Reload"
#define VERSION "1.1.0"
#define AUTHOR  "Antigravity"

// Engine Offsets
#define m_pPlayer 41
#define m_flNextPrimaryAttack 46
#define m_flNextSecondaryAttack 47
#define m_flTimeWeaponIdle 48
#define m_fInReload 54
#define extra_offset_weapon 4

#define m_flNextAttack 83
#define extra_offset_player 5

// CVars
new sr_pCvar_Enable;
new sr_pCvar_Multiplier;
new sr_pCvar_WalkTrigger;

// User Message ID for Network Reload Sound Suppression
new sr_iMsgReloadSound;

// Active Reloading Player tracking during DefaultReload
new sr_iCurrentReloadingPlayer;

// Player States
new bool:sr_bInReloadCycle[33];            // Tracking an active reload
new bool:sr_bIsSilentReloading[33];        // Silent reload multiplier active
new bool:sr_bInstantTrigger[33];           // Shift or Duck held at reload start
new bool:sr_bCancelled[33];                // Player released 'R' and accelerated back to normal
new sr_iCurrentWeapon[33];                 // Active weapon entity
new Float:sr_flOriginalDuration[33];       // Normal reload duration (seconds)
new Float:sr_flStartTime[33];              // Gametime when reload started
new Float:sr_flSilentStartTime[33];        // Gametime when silent reload engaged
new Float:sr_flSilentTotalRemaining[33];   // Stretched remaining duration in silent mode
new Float:sr_flNormalRemainingAtStart[33]; // Normal duration remaining when silent started

// All reloadable weapons in CS 1.6
new const sr_szReloadableWeapons[][] = {
    "weapon_p228",
    "weapon_scout",
    "weapon_xm1014",
    "weapon_mac10",
    "weapon_aug",
    "weapon_elite",
    "weapon_fiveseven",
    "weapon_ump45",
    "weapon_sg550",
    "weapon_galil",
    "weapon_famas",
    "weapon_usp",
    "weapon_glock18",
    "weapon_awp",
    "weapon_mp5navy",
    "weapon_m249",
    "weapon_m3",
    "weapon_m4a1",
    "weapon_tmp",
    "weapon_g3sg1",
    "weapon_deagle",
    "weapon_sg552",
    "weapon_ak47",
    "weapon_p90"
};

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    sr_pCvar_Enable      = register_cvar("amx_cs2_silentreload", "1");
    sr_pCvar_Multiplier  = register_cvar("amx_cs2_silentreload_mult", "2.0");
    sr_pCvar_WalkTrigger = register_cvar("amx_cs2_silentreload_walk", "1");

    for (new i = 0; i < sizeof(sr_szReloadableWeapons); i++)
    {
        RegisterHam(Ham_Weapon_Reload, sr_szReloadableWeapons[i], "sr_OnReload_Pre", 0);
        RegisterHam(Ham_Weapon_Reload, sr_szReloadableWeapons[i], "sr_OnReload_Post", 1);
        RegisterHam(Ham_Item_Holster,  sr_szReloadableWeapons[i], "sr_OnHolster", 1);
    }

    RegisterHam(Ham_Item_PostFrame, "weapon_m3",     "sr_OnPostFrame_Pre",  0);
    RegisterHam(Ham_Item_PostFrame, "weapon_m3",     "sr_OnPostFrame_Post", 1);
    RegisterHam(Ham_Item_PostFrame, "weapon_xm1014", "sr_OnPostFrame_Pre",  0);
    RegisterHam(Ham_Item_PostFrame, "weapon_xm1014", "sr_OnPostFrame_Post", 1);

    RegisterHam(Ham_Killed, "player", "sr_OnPlayerKilled_Post", 1);
    register_forward(FM_CmdStart, "sr_OnCmdStart");
    register_forward(FM_EmitSound, "sr_OnEmitSound");

    sr_iMsgReloadSound = get_user_msgid("ReloadSound");
    if (sr_iMsgReloadSound)
    {
        register_message(sr_iMsgReloadSound, "sr_Msg_ReloadSound");
    }
}

public client_putinserver(id)
{
    sr_ResetPlayer(id);
}

public client_disconnected(id)
{
    sr_ResetPlayer(id);
}

// -------------------------------------------------------------
// Core Reload Interceptions
// -------------------------------------------------------------
public sr_OnReload_Pre(weapon)
{
    if (!pev_valid(weapon))
        return HAM_IGNORED;

    if (!get_pcvar_num(sr_pCvar_Enable))
        return HAM_IGNORED;

    new id = get_pdata_cbase(weapon, m_pPlayer, extra_offset_weapon);
    if (!is_user_alive(id))
        return HAM_IGNORED;

    new buttons = pev(id, pev_button);
    // Walk trigger is exclusively Shift (IN_RUN) to prevent crouching (IN_DUCK) from forcing 2x slow reload
    new bool:bWalkModifier = bool:(get_pcvar_num(sr_pCvar_WalkTrigger) && (buttons & IN_RUN));

    sr_iCurrentReloadingPlayer = id;
    sr_bInstantTrigger[id] = bWalkModifier;
    return HAM_IGNORED;
}

public sr_OnReload_Post(weapon)
{
    if (!pev_valid(weapon))
    {
        sr_iCurrentReloadingPlayer = 0;
        return HAM_IGNORED;
    }

    if (!get_pcvar_num(sr_pCvar_Enable))
    {
        sr_iCurrentReloadingPlayer = 0;
        return HAM_IGNORED;
    }

    new id = get_pdata_cbase(weapon, m_pPlayer, extra_offset_weapon);
    if (!is_user_alive(id))
    {
        sr_iCurrentReloadingPlayer = 0;
        return HAM_IGNORED;
    }

    // Check if the weapon actually entered reload mode
    if (get_pdata_int(weapon, m_fInReload, extra_offset_weapon))
    {
        new Float:flGameTime = get_gametime();
        new Float:flNextAttack = get_pdata_float(id, m_flNextAttack, extra_offset_player);
        new Float:flDuration = flNextAttack - flGameTime;

        // Fallback safeguard if engine set relative duration instead of absolute timestamp
        if (flDuration <= 0.0 && flNextAttack > 0.0)
        {
            flDuration = flNextAttack;
        }

        if (flDuration > 0.1)
        {
            sr_bInReloadCycle[id]          = true;
            sr_bCancelled[id]              = false;
            sr_iCurrentWeapon[id]          = weapon;
            sr_flOriginalDuration[id]      = flDuration;
            sr_flStartTime[id]             = flGameTime;

            // If Shift or Duck was held at start, engage Silent Reload immediately!
            if (sr_bInstantTrigger[id])
            {
                sr_ActivateSilent(id, weapon, flDuration);
            }
            else
            {
                // Normal reload: will become silent if player continues to hold 'R' (> 0.22s)
                sr_bIsSilentReloading[id] = false;
            }
        }
    }

    sr_bInstantTrigger[id] = false;
    sr_iCurrentReloadingPlayer = 0;
    return HAM_IGNORED;
}

// -------------------------------------------------------------
// Activate Silent Reload (Scales remaining duration by multiplier)
// -------------------------------------------------------------
stock sr_ActivateSilent(id, weapon, Float:flRemainingNormal)
{
    new Float:flMult = get_pcvar_float(sr_pCvar_Multiplier);
    if (flMult < 1.0) flMult = 1.0;

    new Float:flNewRemaining = flRemainingNormal * flMult;
    new Float:flGameTime = get_gametime();

    sr_bIsSilentReloading[id]        = true;
    sr_flSilentStartTime[id]        = flGameTime;
    sr_flSilentTotalRemaining[id]   = flNewRemaining;
    sr_flNormalRemainingAtStart[id] = flRemainingNormal;

    // Player attack cooldown: absolute gametime timestamp
    set_pdata_float(id, m_flNextAttack, flGameTime + flNewRemaining, extra_offset_player);

    // Weapon idle & attack timers: absolute gametime timestamps
    set_pdata_float(weapon, m_flTimeWeaponIdle, flGameTime + flNewRemaining + 0.1, extra_offset_weapon);
    set_pdata_float(weapon, m_flNextPrimaryAttack, flGameTime + flNewRemaining, extra_offset_weapon);
    set_pdata_float(weapon, m_flNextSecondaryAttack, flGameTime + flNewRemaining, extra_offset_weapon);

    // Slow down third-person body animation tempo to match stealth speed
    set_pev(id, pev_framerate, 1.0 / flMult);
}

// -------------------------------------------------------------
// Fluid Control (Hold R to engage silent, release R to accelerate)
// -------------------------------------------------------------
public sr_OnCmdStart(id, uc_handle, seed)
{
    if (!is_user_alive(id) || !sr_bInReloadCycle[id])
        return FMRES_IGNORED;

    new weapon = sr_iCurrentWeapon[id];
    new Float:flGameTime = get_gametime();

    // Check if reload finished naturally or weapon became invalid
    if (!pev_valid(weapon) || !get_pdata_int(weapon, m_fInReload, extra_offset_weapon))
    {
        // Safety: Ensure attack readiness is not blocked once reload has ended
        if (pev_valid(weapon))
        {
            new Float:flNextPrimary = get_pdata_float(weapon, m_flNextPrimaryAttack, extra_offset_weapon);
            if (flNextPrimary > flGameTime)
            {
                set_pdata_float(weapon, m_flNextPrimaryAttack, flGameTime, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextSecondaryAttack, flGameTime, extra_offset_weapon);
            }
            new Float:flNextPlayerAttack = get_pdata_float(id, m_flNextAttack, extra_offset_player);
            if (flNextPlayerAttack > flGameTime)
            {
                set_pdata_float(id, m_flNextAttack, flGameTime, extra_offset_player);
            }
        }
        sr_ResetPlayer(id);
        return FMRES_IGNORED;
    }

    new buttons = get_uc(uc_handle, UC_Buttons);

    // Mode 1: Currently in Normal Reload
    if (!sr_bIsSilentReloading[id])
    {
        // If not already cancelled, check if player holds 'R' to switch to silent
        if (!sr_bCancelled[id])
        {
            if (buttons & IN_RELOAD)
            {
                new Float:flHeldDuration = flGameTime - sr_flStartTime[id];
                // Player held 'R' past standard tap threshold (0.22s) -> transition to silent!
                if (flHeldDuration >= 0.22)
                {
                    new Float:flRemainingNormal = sr_flOriginalDuration[id] - flHeldDuration;
                    if (flRemainingNormal > 0.1)
                    {
                        sr_ActivateSilent(id, weapon, flRemainingNormal);
                    }
                    else
                    {
                        sr_bCancelled[id] = true;
                    }
                }
            }
            else
            {
                // Player released 'R' before 0.22s: this is a standard tap reload.
                // Mark cancelled so crouching, walking, or subsequent R taps during this
                // reload cycle NEVER trigger silent reload or flap timers!
                sr_bCancelled[id] = true;
            }
        }
    }
    // Mode 2: Currently in Silent Reload
    else
    {
        // Check if player is maintaining stealth:
        // Either holding 'R' OR holding Walk (Shift / IN_RUN) if walk trigger enabled
        new bool:bStealthHeld = bool:((buttons & IN_RELOAD) || (get_pcvar_num(sr_pCvar_WalkTrigger) && (buttons & IN_RUN)));

        // Releasing keys past the initial tap grace period (0.22s) accelerates back to normal speed
        if ((flGameTime - sr_flStartTime[id] >= 0.22) && !bStealthHeld)
        {
            new Float:flElapsedSilent = flGameTime - sr_flSilentStartTime[id];
            new Float:flProgress = (sr_flSilentTotalRemaining[id] > 0.0)
                ? (flElapsedSilent / sr_flSilentTotalRemaining[id])
                : 1.0;

            if (flProgress < 1.0)
            {
                new Float:flRemaining = sr_flNormalRemainingAtStart[id] * (1.0 - flProgress);
                if (flRemaining < 0.05) flRemaining = 0.05;

                set_pdata_float(id, m_flNextAttack, flGameTime + flRemaining, extra_offset_player);
                set_pdata_float(weapon, m_flTimeWeaponIdle, flGameTime + flRemaining + 0.1, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextPrimaryAttack, flGameTime + flRemaining, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextSecondaryAttack, flGameTime + flRemaining, extra_offset_weapon);
            }
            else
            {
                set_pdata_float(id, m_flNextAttack, flGameTime, extra_offset_player);
                set_pdata_float(weapon, m_flTimeWeaponIdle, flGameTime + 0.1, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextPrimaryAttack, flGameTime, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextSecondaryAttack, flGameTime, extra_offset_weapon);
            }

            // Restore normal framerate and mark cancelled to prevent flapping back to silent
            set_pev(id, pev_framerate, 1.0);
            sr_bIsSilentReloading[id] = false;
            sr_bCancelled[id] = true;
        }
    }

    return FMRES_IGNORED;
}

// -------------------------------------------------------------
// Audio Suppression: Block network user message ReloadSound
// -------------------------------------------------------------
public sr_Msg_ReloadSound(msg_id, msg_dest, msg_entity)
{
    if (!get_pcvar_num(sr_pCvar_Enable))
        return PLUGIN_CONTINUE;

    // During Ham_Weapon_Reload, check if the reloading player is silent
    if (1 <= sr_iCurrentReloadingPlayer <= 32)
    {
        if (sr_bInstantTrigger[sr_iCurrentReloadingPlayer] || sr_bIsSilentReloading[sr_iCurrentReloadingPlayer])
        {
            return PLUGIN_HANDLED; // Block network reload audio to teammates/enemies
        }
    }
    else
    {
        // Outside Ham_Weapon_Reload (e.g. shotguns shell insert), check if any active player is silently reloading
        for (new i = 1; i <= 32; i++)
        {
            if (sr_bIsSilentReloading[i] && is_user_alive(i))
            {
                return PLUGIN_HANDLED;
            }
        }
    }

    return PLUGIN_CONTINUE;
}

// -------------------------------------------------------------
// Audio Suppression: Block reload sound events
// -------------------------------------------------------------
public sr_OnEmitSound(entity, channel, const sample[], Float:volume, Float:attenuation, flags, pitch)
{
    if (!get_pcvar_num(sr_pCvar_Enable))
        return FMRES_IGNORED;

    new id = 0;
    if (1 <= entity <= 32)
    {
        id = entity;
    }
    else if (pev_valid(entity))
    {
        id = get_pdata_cbase(entity, m_pPlayer, extra_offset_weapon);
    }

    if (1 <= id <= 32 && sr_bIsSilentReloading[id])
    {
        if (sr_IsReloadSound(sample))
        {
            return FMRES_SUPERCEDE; // Block sound transmission completely
        }
    }

    return FMRES_IGNORED;
}

// -------------------------------------------------------------
// Helper: Check if audio sample is a weapon reload sound
// -------------------------------------------------------------
stock bool:sr_IsReloadSound(const sample[])
{
    if (sample[0] != 'w' || sample[1] != 'e' || sample[2] != 'a')
    {
        if (containi(sample, "weapons/") == -1)
            return false;
    }

    if (containi(sample, "clip") != -1 ||
        containi(sample, "bolt") != -1 ||
        containi(sample, "slide") != -1 ||
        containi(sample, "insert") != -1 ||
        containi(sample, "box") != -1 ||
        containi(sample, "chain") != -1 ||
        containi(sample, "cover") != -1 ||
        containi(sample, "reload") != -1)
    {
        return true;
    }

    return false;
}

// -------------------------------------------------------------
// State Cleanup Hooks
// -------------------------------------------------------------
public sr_OnHolster(weapon)
{
    if (!pev_valid(weapon))
        return HAM_IGNORED;

    new id = get_pdata_cbase(weapon, m_pPlayer, extra_offset_weapon);
    if (1 <= id <= 32)
    {
        // Zero-lockout safeguard: If player switched/holstered weapon mid-reload,
        // clear player attack lockout so deployed secondary or knife can attack immediately!
        if (sr_bInReloadCycle[id])
        {
            new Float:flGameTime = get_gametime();
            new Float:flPlayerAttack = get_pdata_float(id, m_flNextAttack, extra_offset_player);
            if (flPlayerAttack > flGameTime)
            {
                set_pdata_float(id, m_flNextAttack, flGameTime, extra_offset_player);
            }

            new Float:flPrimaryAttack = get_pdata_float(weapon, m_flNextPrimaryAttack, extra_offset_weapon);
            if (flPrimaryAttack > flGameTime)
            {
                set_pdata_float(weapon, m_flNextPrimaryAttack, flGameTime, extra_offset_weapon);
                set_pdata_float(weapon, m_flNextSecondaryAttack, flGameTime, extra_offset_weapon);
            }
        }
        sr_ResetPlayer(id);
    }
    return HAM_IGNORED;
}

public sr_OnPostFrame_Pre(weapon)
{
    if (pev_valid(weapon))
    {
        sr_iCurrentReloadingPlayer = get_pdata_cbase(weapon, m_pPlayer, extra_offset_weapon);
    }
    return HAM_IGNORED;
}

public sr_OnPostFrame_Post(weapon)
{
    sr_iCurrentReloadingPlayer = 0;
    return HAM_IGNORED;
}

public sr_OnPlayerKilled_Post(victim, killer, shouldgib)
{
    if (1 <= victim <= 32)
    {
        sr_ResetPlayer(victim);
    }
    return HAM_IGNORED;
}

stock sr_ResetPlayer(id)
{
    sr_bInReloadCycle[id]           = false;
    sr_bIsSilentReloading[id]       = false;
    sr_bInstantTrigger[id]          = false;
    sr_bCancelled[id]               = false;
    sr_iCurrentWeapon[id]           = 0;
    sr_flOriginalDuration[id]       = 0.0;
    sr_flStartTime[id]              = 0.0;
    sr_flSilentStartTime[id]        = 0.0;
    sr_flSilentTotalRemaining[id]   = 0.0;
    sr_flNormalRemainingAtStart[id] = 0.0;

    if (is_user_alive(id))
    {
        set_pev(id, pev_framerate, 1.0);
    }
}
