#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <hamsandwich>
#include <fakemeta>
#include <fakemeta_util>

#define PLUGIN  "CS:GO/CS2 Auto Ammo & Round Refill"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

#define TASK_BOUGHT_REFILL 2000
#define TASK_SPAWN_REFILL  3000
#define TASK_ROUND_REFILL  4000

// CVars
new pCvar_Enable;
new pCvar_OnBuy;
new pCvar_RoundStart;
new pCvar_InstantClip;
new pCvar_BlockCmds;

// Bitmask tracking weapons purchased by player during this frame/tick
new g_iBoughtMask[33];

// Max Clip per weapon
new const g_iMaxClip[CSW_LAST_WEAPON + 1] = {
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

// Max Backpack Reserve Ammo per weapon (Standard CS 1.6 capacities)
new const g_iMaxBPAmmo[CSW_LAST_WEAPON + 1] = {
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
new g_msgCurWeapon;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable      = register_cvar("amx_csgo_ammo", "1");
    pCvar_OnBuy       = register_cvar("amx_csgo_ammo_on_buy", "1");
    pCvar_RoundStart  = register_cvar("amx_csgo_ammo_round_start", "1");
    pCvar_InstantClip = register_cvar("amx_csgo_ammo_instant_clip", "1");
    pCvar_BlockCmds   = register_cvar("amx_csgo_ammo_block_cmds", "1");

    // Events
    register_event("HLTV", "event_round_start", "a", "1=0", "2=0");
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);

    // Block ammo buy commands (free & auto in CS:GO/CS2)
    register_clcmd("buyammo1", "cmd_block_ammo");
    register_clcmd("buyammo2", "cmd_block_ammo");
    register_clcmd("primammo", "cmd_block_ammo");
    register_clcmd("secammo", "cmd_block_ammo");

    g_msgCurWeapon = get_user_msgid("CurWeapon");
}

public client_disconnected(id)
{
    g_iBoughtMask[id] = 0;
    remove_task(TASK_BOUGHT_REFILL + id);
    remove_task(TASK_SPAWN_REFILL + id);
}

// -------------------------------------------------------------
// Weapon Purchase Interception (CS_OnBuy & CS_OnBuyAttempt)
// -------------------------------------------------------------

public CS_OnBuyAttempt(id, item)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_BlockCmds))
        return PLUGIN_CONTINUE;

    // Block attempts to buy ammo (free & auto like CS:GO/CS2)
    if (item == CSI_PRIAMMO || item == CSI_SECAMMO)
    {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CS_OnBuy(id, item)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_OnBuy))
        return PLUGIN_CONTINUE;

    // Block ammo purchase if somehow reached here
    if (item == CSI_PRIAMMO || item == CSI_SECAMMO)
    {
        return PLUGIN_HANDLED;
    }

    // Check if the item bought is a firearm
    if (item > CSI_NONE && item <= CSI_LAST_WEAPON)
    {
        if (is_gun(item))
        {
            g_iBoughtMask[id] |= (1 << item);
            remove_task(TASK_BOUGHT_REFILL + id);
            set_task(0.05, "task_refill_bought", TASK_BOUGHT_REFILL + id);
        }
    }

    return PLUGIN_CONTINUE;
}

public task_refill_bought(taskid)
{
    new id = taskid - TASK_BOUGHT_REFILL;
    if (!is_user_alive(id))
    {
        g_iBoughtMask[id] = 0;
        return;
    }

    for (new wid = 1; wid <= CSW_LAST_WEAPON; wid++)
    {
        if (g_iBoughtMask[id] & (1 << wid))
        {
            // Maximize backpack reserve ammo
            cs_set_user_bpammo(id, wid, g_iMaxBPAmmo[wid]);

            // Ensure clip is full
            new szWpnName[32];
            get_weaponname(wid, szWpnName, charsmax(szWpnName));
            new iWpn = fm_find_ent_by_owner(-1, szWpnName, id);
            if (pev_valid(iWpn))
            {
                cs_set_weapon_ammo(iWpn, g_iMaxClip[wid]);
            }

            // If player is holding this weapon, refresh HUD immediately
            if (get_user_weapon(id) == wid)
            {
                update_hud_ammo(id, wid);
            }
        }
    }

    g_iBoughtMask[id] = 0;
}

// -------------------------------------------------------------
// Round Start & Player Spawn Refill
// -------------------------------------------------------------

public event_round_start()
{
    if (!get_pcvar_num(pCvar_Enable))
        return;

    // Delay slightly to let round logic finish placing players
    remove_task(TASK_ROUND_REFILL);
    set_task(0.2, "task_round_refill_all", TASK_ROUND_REFILL);
}

public task_round_refill_all()
{
    if (!get_pcvar_num(pCvar_Enable))
        return;

    new iPlayers[32], iNum;
    get_players(iPlayers, iNum, "a"); // Alive players only
    for (new i = 0; i < iNum; i++)
    {
        refill_player_weapons(iPlayers[i]);
    }
}

public OnPlayerSpawn_Post(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(pCvar_Enable))
        return;

    // Small delay to allow CS 1.6 to finish giving default spawn weapons
    remove_task(TASK_SPAWN_REFILL + id);
    set_task(0.1, "task_spawn_refill", TASK_SPAWN_REFILL + id);
}

public task_spawn_refill(taskid)
{
    new id = taskid - TASK_SPAWN_REFILL;
    if (is_user_alive(id))
    {
        refill_player_weapons(id);
    }
}

// Refills all guns in a player's inventory
stock refill_player_weapons(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(pCvar_Enable))
        return;

    new iWeapons[32], iNum;
    get_user_weapons(id, iWeapons, iNum);
    new iActiveWpn = get_user_weapon(id);

    new bool:bRefillBp   = bool:get_pcvar_num(pCvar_RoundStart);
    new bool:bRefillClip = bool:get_pcvar_num(pCvar_InstantClip);

    for (new i = 0; i < iNum; i++)
    {
        new wid = iWeapons[i];

        if (!is_gun(wid))
            continue;

        // 1. Refill reserve ammo (backpack)
        if (bRefillBp)
        {
            cs_set_user_bpammo(id, wid, g_iMaxBPAmmo[wid]);
        }

        // 2. Reset clip to full (no manual reload needed)
        if (bRefillClip)
        {
            new szWpnName[32];
            get_weaponname(wid, szWpnName, charsmax(szWpnName));
            new iWpn = fm_find_ent_by_owner(-1, szWpnName, id);
            if (pev_valid(iWpn))
            {
                cs_set_weapon_ammo(iWpn, g_iMaxClip[wid]);
            }
        }
    }

    // Immediately update HUD for currently held weapon
    if (is_gun(iActiveWpn))
    {
        update_hud_ammo(id, iActiveWpn);
    }
}

// -------------------------------------------------------------
// Helper Stocks
// -------------------------------------------------------------

stock bool:is_gun(wid)
{
    if (wid <= CSW_NONE || wid > CSW_LAST_WEAPON)
        return false;

    return bool:((1 << wid) & CSW_ALL_GUNS);
}

stock update_hud_ammo(id, wid)
{
    if (!is_user_alive(id))
        return;

    new szWpnName[32];
    get_weaponname(wid, szWpnName, charsmax(szWpnName));
    new iWpn = fm_find_ent_by_owner(-1, szWpnName, id);
    new iClip = 0;
    if (pev_valid(iWpn))
    {
        iClip = cs_get_weapon_ammo(iWpn);
    }
    else
    {
        iClip = g_iMaxClip[wid];
    }

    message_begin(MSG_ONE, g_msgCurWeapon, _, id);
    write_byte(1);     // IsActive
    write_byte(wid);   // WeaponID
    write_byte(iClip); // Clip ammo
    message_end();
}

public cmd_block_ammo(id)
{
    if (get_pcvar_num(pCvar_Enable) && get_pcvar_num(pCvar_BlockCmds))
    {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}
