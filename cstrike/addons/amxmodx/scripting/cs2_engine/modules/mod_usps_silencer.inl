// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: USP-S PERMANENT SILENCER LOCK
// Lock USP-S silencer permanently, block right-click unsilencing, auto-attach
// ==============================================================================

#if defined _mod_usps_silencer_included
    #endinput
#endif
#define _mod_usps_silencer_included

// CVars
new usps_pCvar_Enable;
new usps_pCvar_CTOnly;
new usps_pCvar_BlockSecondary;
new usps_pCvar_AutoSilence;

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_USPSSilencer_Init()
{
    usps_pCvar_Enable         = register_cvar("amx_usps_lock", "1");
    usps_pCvar_CTOnly         = register_cvar("amx_usps_ct_only", "0");
    usps_pCvar_BlockSecondary = register_cvar("amx_usps_block_secondary", "1");
    usps_pCvar_AutoSilence    = register_cvar("amx_usps_auto_silence", "1");

    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_usp", "usps_OnSecondaryAttack_Pre", 0);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "usps_OnDeploy_Pre", 0);
    RegisterHam(Ham_Item_Deploy, "weapon_usp", "usps_OnDeploy_Post", 1);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_usp", "usps_OnAddToPlayer_Post", 1);

    register_event("CurWeapon", "usps_Event_CurWeapon", "be", "1=1");
}

public Mod_USPSSilencer_Precache()
{
    // No custom assets required for USPS silencer lock
}

public Mod_USPSSilencer_PutInServer(id)
{
    remove_task(TASK_USPS_CHECK_SPAWN + id);
}

public Mod_USPSSilencer_Disconnect(id)
{
    remove_task(TASK_USPS_CHECK_SPAWN + id);
}

public Mod_USPSSilencer_NewRound()
{
    for (new i = 1; i <= 32; i++)
    {
        remove_task(TASK_USPS_CHECK_SPAWN + i);
    }
}

public Mod_USPSSilencer_RoundEnd()
{
    for (new i = 1; i <= 32; i++)
    {
        remove_task(TASK_USPS_CHECK_SPAWN + i);
    }
}

public Mod_USPSSilencer_Spawn(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !usps_ShouldEnforceSilencer(id))
        return;

    remove_task(TASK_USPS_CHECK_SPAWN + id);
    set_task(0.1, "usps_Task_CheckSpawnUSP", TASK_USPS_CHECK_SPAWN + id);
}

// -------------------------------------------------------------
// Helper: Check if silencer should be enforced on this player
// -------------------------------------------------------------
stock bool:usps_ShouldEnforceSilencer(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable))
        return false;

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return false;

    if (get_pcvar_num(usps_pCvar_CTOnly))
    {
        return (cs_get_user_team(id) == CS_TEAM_CT);
    }

    return true;
}

// -------------------------------------------------------------
// 1. Block Right-Click Unsilencing (Secondary Attack)
// -------------------------------------------------------------
public usps_OnSecondaryAttack_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable) || !get_pcvar_num(usps_pCvar_BlockSecondary) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, m_pPlayer, extra_offset_weapon);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!usps_ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_SUPERCEDE;
}

// -------------------------------------------------------------
// 2. Ensure Silenced Before & After Deploy
// -------------------------------------------------------------
public usps_OnDeploy_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable) || !get_pcvar_num(usps_pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, m_pPlayer, extra_offset_weapon);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!usps_ShouldEnforceSilencer(id))
        return HAM_IGNORED;

    if (!cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

public usps_OnDeploy_Post(iWpn)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable) || !get_pcvar_num(usps_pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, m_pPlayer, extra_offset_weapon);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (!usps_ShouldEnforceSilencer(id))
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
public usps_OnAddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable) || !get_pcvar_num(usps_pCvar_AutoSilence) || !pev_valid(iWpn))
        return HAM_IGNORED;

    if (!usps_ShouldEnforceSilencer(id))
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
public usps_Event_CurWeapon(id)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(usps_pCvar_Enable) || !get_pcvar_num(usps_pCvar_AutoSilence) || !is_user_alive(id))
        return;

    if (read_data(1) != 1)
        return;

    new wid = read_data(2);
    if (wid != CSW_USP)
        return;

    if (!usps_ShouldEnforceSilencer(id))
        return;

    new iWpn = find_ent_by_owner(-1, "weapon_usp", id);
    if (pev_valid(iWpn) && !cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }
}

// -------------------------------------------------------------
// 5. Ensure Silenced on Player Spawn
// -------------------------------------------------------------
public usps_Task_CheckSpawnUSP(taskid)
{
    new id = taskid - TASK_USPS_CHECK_SPAWN;
    if (!is_user_alive(id) || !usps_ShouldEnforceSilencer(id))
        return;

    new iWpn = find_ent_by_owner(-1, "weapon_usp", id);
    if (pev_valid(iWpn) && !cs_get_weapon_silen(iWpn))
    {
        cs_set_weapon_silen(iWpn, 1, 0);
    }
}
