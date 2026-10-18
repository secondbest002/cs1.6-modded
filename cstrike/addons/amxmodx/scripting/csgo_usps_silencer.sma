#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <fakemeta_util>
#include <hamsandwich>

#define PLUGIN  "CS:GO USP-S Permanent Silencer Lock"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

// CVars
new pCvar_Enable;
new pCvar_CTOnly;
new pCvar_BlockSecondary;
new pCvar_AutoSilence;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable         = register_cvar("amx_usps_lock", "1");
    pCvar_CTOnly         = register_cvar("amx_usps_ct_only", "0"); // Option B: 0 = All players & bots (CT and T)
    pCvar_BlockSecondary = register_cvar("amx_usps_block_secondary", "1"); // Block right-click unsilence
    pCvar_AutoSilence    = register_cvar("amx_usps_auto_silence", "1"); // Force silencer on spawn/deploy/pickup

    // Hook USP Weapon Events via HamSandwich
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_usp", "OnUSPSecondaryAttack_Pre", 0);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "OnUSPDeploy_Pre", 0);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "OnUSPDeploy_Post", 1);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_usp", "OnUSPAddToPlayer_Post", 1);

    // Hook Player Spawn
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);

    // CurWeapon Event
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");

    server_print("[USP-S Lock] Plugin loaded. Silencer permanently enforced.");
}

// -------------------------------------------------------------
// Helper: Check if silencer should be enforced on this player
// -------------------------------------------------------------

stock bool:ShouldEnforceSilencer(id)
{
    if (!get_pcvar_num(pCvar_Enable))
        return false;

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return false;

    if (get_pcvar_num(pCvar_CTOnly))
    {
        return (cs_get_user_team(id) == CS_TEAM_CT);
    }

    return true; // Option B: All players (CT and T)
}

// -------------------------------------------------------------
// 1. Block Right-Click Unsilencing (Secondary Attack)
// -------------------------------------------------------------

public OnUSPSecondaryAttack_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_BlockSecondary) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    // Ensure it is silenced just in case
    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    // Completely supercede / cancel the secondary attack action!
    // No unsilence animation, no sound, no detachment!
    return HAM_SUPERCEDE;
}

// -------------------------------------------------------------
// 2. Ensure Silenced Before & After Deploy
// -------------------------------------------------------------

public OnUSPDeploy_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    // Set silencer BEFORE deploy executes so the engine naturally picks the silenced draw sequence!
    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

public OnUSPDeploy_Post(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

// -------------------------------------------------------------
// 3. Ensure Silenced When Added To Inventory (Spawn / Buy / Pickup)
// -------------------------------------------------------------

public OnUSPAddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    if (!ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

// -------------------------------------------------------------
// 4. Ensure Silenced When Active in Hand (CurWeapon)
// -------------------------------------------------------------

public Event_CurWeapon(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_AutoSilence) || !is_user_alive(id))
        return;

    if (read_data(1) != 1) // Not active
        return;

    new wid = read_data(2);
    if (wid != CSW_USP)
        return;

    if (!ShouldEnforceSilencer(id))
        return;

    new iWpn = fm_find_ent_by_owner(-1, "weapon_usp", id);
    if (pev_valid(iWpn) && !cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }
}

// -------------------------------------------------------------
// 5. Ensure Silenced on Player Spawn
// -------------------------------------------------------------

public OnPlayerSpawn_Post(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_AutoSilence) || !is_user_alive(id))
        return;

    if (!ShouldEnforceSilencer(id))
        return;

    // Delay slightly to let CS finish equipping spawn weapons
    set_task(0.1, "Task_CheckSpawnUSP", id);
}

public Task_CheckSpawnUSP(id)
{
    if (!is_user_alive(id) || !ShouldEnforceSilencer(id))
        return;

    new iWpn = fm_find_ent_by_owner(-1, "weapon_usp", id);
    if (pev_valid(iWpn) && !cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }
}
