// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: AUTO AMMO & ROUND REFILL
// CS:GO / CS2 automated full reserve ammunition and round start clip refills
// ==============================================================================

#if defined _mod_ammo_refill_included
    #endinput
#endif
#define _mod_ammo_refill_included

// CVars
new ammo_pCvar_Enable;
new ammo_pCvar_OnBuy;
new ammo_pCvar_RoundStart;
new ammo_pCvar_InstantClip;
new ammo_pCvar_BlockCmds;

// Bitmask tracking weapons purchased by player during this frame/tick
new ammo_iBoughtMask[33];

// Max Clip per weapon
new const ammo_iMaxClip[CSW_LAST_WEAPON + 1] = {
    0,
    13, // CSW_P228
    0,  // CSW_GLOCK
    10, // CSW_SCOUT
    0,  // CSW_HEGRENADE
    7,  // CSW_XM1014
    0,  // CSW_C4
    30, // CSW_MAC10
    30, // CSW_AUG
    0,  // CSW_SMOKEGRENADE
    30, // CSW_ELITE
    20, // CSW_FIVESEVEN
    25, // CSW_UMP45
    30, // CSW_SG550
    35, // CSW_GALIL
    25, // CSW_FAMAS
    12, // CSW_USP
    20, // CSW_GLOCK18
    10, // CSW_AWP
    30, // CSW_MP5NAVY
    100,// CSW_M249
    8,  // CSW_M3
    30, // CSW_M4A1
    30, // CSW_TMP
    20, // CSW_G3SG1
    0,  // CSW_FLASHBANG
    7,  // CSW_DEAGLE
    30, // CSW_SG552
    30, // CSW_AK47
    0,  // CSW_KNIFE
    50  // CSW_P90
};

// Max Backpack Reserve Ammo per weapon (Standard CS capacities)
new const ammo_iMaxBPAmmo[CSW_LAST_WEAPON + 1] = {
    0,
    52,  // CSW_P228
    0,   // CSW_GLOCK
    90,  // CSW_SCOUT
    0,   // CSW_HEGRENADE (protected)
    32,  // CSW_XM1014
    0,   // CSW_C4 (protected)
    100, // CSW_MAC10
    90,  // CSW_AUG
    0,   // CSW_SMOKEGRENADE (protected)
    120, // CSW_ELITE
    100, // CSW_FIVESEVEN
    100, // CSW_UMP45
    90,  // CSW_SG550
    90,  // CSW_GALIL
    90,  // CSW_FAMAS
    100, // CSW_USP
    120, // CSW_GLOCK18
    30,  // CSW_AWP
    120, // CSW_MP5NAVY
    200, // CSW_M249
    32,  // CSW_M3
    90,  // CSW_M4A1
    120, // CSW_TMP
    90,  // CSW_G3SG1
    0,   // CSW_FLASHBANG (protected)
    35,  // CSW_DEAGLE
    90,  // CSW_SG552
    90,  // CSW_AK47
    0,   // CSW_KNIFE
    100  // CSW_P90
};

// Cached message IDs
new ammo_msgCurWeapon;

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_AmmoRefill_Init()
{
    ammo_pCvar_Enable      = register_cvar("amx_csgo_ammo", "1");
    ammo_pCvar_OnBuy       = register_cvar("amx_csgo_ammo_on_buy", "1");
    ammo_pCvar_RoundStart  = register_cvar("amx_csgo_ammo_round_start", "1");
    ammo_pCvar_InstantClip = register_cvar("amx_csgo_ammo_instant_clip", "1");
    ammo_pCvar_BlockCmds   = register_cvar("amx_csgo_ammo_block_cmds", "1");

    register_clcmd("buyammo1", "ammo_Cmd_BlockAmmo");
    register_clcmd("buyammo2", "ammo_Cmd_BlockAmmo");
    register_clcmd("primammo", "ammo_Cmd_BlockAmmo");
    register_clcmd("secammo", "ammo_Cmd_BlockAmmo");

    ammo_msgCurWeapon = get_user_msgid("CurWeapon");
}

public Mod_AmmoRefill_Precache()
{
    // No custom assets required for ammo refill
}

public Mod_AmmoRefill_PutInServer(id)
{
    ammo_iBoughtMask[id] = 0;
    remove_task(TASK_AMMO_BOUGHT_REFILL + id);
    remove_task(TASK_AMMO_SPAWN_REFILL + id);
}

public Mod_AmmoRefill_Disconnect(id)
{
    ammo_iBoughtMask[id] = 0;
    remove_task(TASK_AMMO_BOUGHT_REFILL + id);
    remove_task(TASK_AMMO_SPAWN_REFILL + id);
}

public Mod_AmmoRefill_NewRound()
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable))
        return;

    remove_task(TASK_AMMO_ROUND_REFILL);
    set_task(0.2, "ammo_Task_RoundRefillAll", TASK_AMMO_ROUND_REFILL);
}

public Mod_AmmoRefill_RoundEnd()
{
    remove_task(TASK_AMMO_ROUND_REFILL);
    for (new i = 1; i <= 32; i++)
    {
        ammo_iBoughtMask[i] = 0;
        remove_task(TASK_AMMO_BOUGHT_REFILL + i);
        remove_task(TASK_AMMO_SPAWN_REFILL + i);
    }
}

public Mod_AmmoRefill_Spawn(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable))
        return;

    remove_task(TASK_AMMO_SPAWN_REFILL + id);
    set_task(0.1, "ammo_Task_SpawnRefill", TASK_AMMO_SPAWN_REFILL + id);
}

// -------------------------------------------------------------
// Weapon Purchase Interception (CS_OnBuy & CS_OnBuyAttempt)
// -------------------------------------------------------------
public CS_OnBuyAttempt(id, item)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable) || !get_pcvar_num(ammo_pCvar_BlockCmds))
        return PLUGIN_CONTINUE;

    if (item == CSI_PRIAMMO || item == CSI_SECAMMO)
    {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CS_OnBuy(id, item)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable) || !get_pcvar_num(ammo_pCvar_OnBuy))
        return PLUGIN_CONTINUE;

    if (item == CSI_PRIAMMO || item == CSI_SECAMMO)
    {
        return PLUGIN_HANDLED;
    }

    if (item > CSI_NONE && item <= CSI_LAST_WEAPON)
    {
        if (ammo_IsGun(item))
        {
            ammo_iBoughtMask[id] |= (1 << item);
            remove_task(TASK_AMMO_BOUGHT_REFILL + id);
            set_task(0.05, "ammo_Task_RefillBought", TASK_AMMO_BOUGHT_REFILL + id);
        }
    }

    return PLUGIN_CONTINUE;
}

public ammo_Task_RefillBought(taskid)
{
    new id = taskid - TASK_AMMO_BOUGHT_REFILL;
    if (!is_user_alive(id))
    {
        ammo_iBoughtMask[id] = 0;
        return;
    }

    for (new wid = 1; wid <= CSW_LAST_WEAPON; wid++)
    {
        if (ammo_iBoughtMask[id] & (1 << wid))
        {
            cs_set_user_bpammo(id, wid, ammo_iMaxBPAmmo[wid]);

            new szWpnName[32];
            get_weaponname(wid, szWpnName, charsmax(szWpnName));
            new iWpn = find_ent_by_owner(-1, szWpnName, id);
            if (pev_valid(iWpn))
            {
                cs_set_weapon_ammo(iWpn, ammo_iMaxClip[wid]);
            }

            if (get_user_weapon(id) == wid)
            {
                ammo_UpdateHudAmmo(id, wid);
            }
        }
    }

    ammo_iBoughtMask[id] = 0;
}

public ammo_Task_RoundRefillAll()
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable))
        return;

    new iPlayers[32], iNum;
    get_players(iPlayers, iNum, "a");
    for (new i = 0; i < iNum; i++)
    {
        ammo_RefillPlayerWeapons(iPlayers[i]);
    }
}

public ammo_Task_SpawnRefill(taskid)
{
    new id = taskid - TASK_AMMO_SPAWN_REFILL;
    if (is_user_alive(id))
    {
        ammo_RefillPlayerWeapons(id);
    }
}

stock ammo_RefillPlayerWeapons(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(ammo_pCvar_Enable))
        return;

    new iWeapons[32], iNum;
    get_user_weapons(id, iWeapons, iNum);
    new iActiveWpn = get_user_weapon(id);

    new bool:bRefillBp   = bool:get_pcvar_num(ammo_pCvar_RoundStart);
    new bool:bRefillClip = bool:get_pcvar_num(ammo_pCvar_InstantClip);

    for (new i = 0; i < iNum; i++)
    {
        new wid = iWeapons[i];

        if (!ammo_IsGun(wid))
            continue;

        if (bRefillBp)
        {
            cs_set_user_bpammo(id, wid, ammo_iMaxBPAmmo[wid]);
        }

        if (bRefillClip)
        {
            new szWpnName[32];
            get_weaponname(wid, szWpnName, charsmax(szWpnName));
            new iWpn = find_ent_by_owner(-1, szWpnName, id);
            if (pev_valid(iWpn))
            {
                cs_set_weapon_ammo(iWpn, ammo_iMaxClip[wid]);
            }
        }
    }

    if (ammo_IsGun(iActiveWpn))
    {
        ammo_UpdateHudAmmo(id, iActiveWpn);
    }
}

stock bool:ammo_IsGun(wid)
{
    if (wid <= CSW_NONE || wid > CSW_LAST_WEAPON)
        return false;

    return bool:((1 << wid) & CSW_ALL_GUNS);
}

stock ammo_UpdateHudAmmo(id, wid)
{
    if (!is_user_alive(id))
        return;

    new szWpnName[32];
    get_weaponname(wid, szWpnName, charsmax(szWpnName));
    new iWpn = find_ent_by_owner(-1, szWpnName, id);
    new iClip = 0;
    if (pev_valid(iWpn))
    {
        iClip = cs_get_weapon_ammo(iWpn);
    }
    else
    {
        iClip = ammo_iMaxClip[wid];
    }

    message_begin(MSG_ONE, ammo_msgCurWeapon, _, id);
    write_byte(1);
    write_byte(wid);
    write_byte(iClip);
    message_end();
}

public ammo_Cmd_BlockAmmo(id)
{
    if (get_pcvar_num(pCvar_MasterEnable) && get_pcvar_num(ammo_pCvar_Enable) && get_pcvar_num(ammo_pCvar_BlockCmds))
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}
