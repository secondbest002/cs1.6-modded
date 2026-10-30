#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <hamsandwich>

#define PLUGIN  "CS2 Per-Weapon Kill Rewards"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

// Cvars
new pCvar_Enable;
new pCvar_Notify;

// Hud Sync
new g_HudSyncMoney;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    pCvar_Enable = register_cvar("amx_cs2_kill_reward", "1");
    pCvar_Notify = register_cvar("amx_cs2_kill_reward_notify", "1");

    RegisterHam(Ham_Killed, "player", "OnPlayerKilledPost", 1);

    g_HudSyncMoney = CreateHudSyncObj();
}

public OnPlayerKilledPost(victim, attacker, shouldgib)
{
    if (!get_pcvar_num(pCvar_Enable))
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (attacker == victim)
        return HAM_IGNORED;

    if (cs_get_user_team(attacker) == cs_get_user_team(victim))
        return HAM_IGNORED;

    new weaponId, clip, ammo;
    weaponId = get_user_weapon(attacker, clip, ammo);

    new targetReward = 300;
    new weaponName[24] = "Firearm";

    switch (weaponId)
    {
        // Knife: $1500
        case CSW_KNIFE:
        {
            targetReward = 1500;
            copy(weaponName, charsmax(weaponName), "Knife");
        }
        // Shotguns: $900
        case CSW_M3, CSW_XM1014:
        {
            targetReward = 900;
            copy(weaponName, charsmax(weaponName), "Shotgun");
        }
        // SMGs: $600 (Except P90: $300)
        case CSW_MP5NAVY, CSW_UMP45, CSW_MAC10, CSW_TMP:
        {
            targetReward = 600;
            copy(weaponName, charsmax(weaponName), "SMG");
        }
        case CSW_P90:
        {
            targetReward = 300;
            copy(weaponName, charsmax(weaponName), "P90");
        }
        // Snipers: AWP gives only $100
        case CSW_AWP:
        {
            targetReward = 100;
            copy(weaponName, charsmax(weaponName), "AWP");
        }
        // Scout & Autosnipers
        case CSW_SCOUT:
        {
            targetReward = 300;
            copy(weaponName, charsmax(weaponName), "Scout");
        }
        case CSW_G3SG1, CSW_SG550:
        {
            targetReward = 300;
            copy(weaponName, charsmax(weaponName), "Sniper");
        }
        // Heavy Machine Gun
        case CSW_M249:
        {
            targetReward = 300;
            copy(weaponName, charsmax(weaponName), "M249");
        }
        // Pistols & Rifles: default $300
        default:
        {
            targetReward = 300;
            copy(weaponName, charsmax(weaponName), "Rifle/Pistol");
        }
    }

    // Engine already gives $300 on kill.
    // We adjust by (targetReward - 300).
    new deltaMoney = targetReward - 300;
    new currentMoney = cs_get_user_money(attacker);
    new newMoney = currentMoney + deltaMoney;

    if (newMoney < 0) newMoney = 0;
    if (newMoney > 16000) newMoney = 16000;

    if (deltaMoney != 0)
    {
        cs_set_user_money(attacker, newMoney, 1);
    }

    // Notification to player
    if (get_pcvar_num(pCvar_Notify))
    {
        set_hudmessage(50, 220, 50, 0.78, 0.82, 0, 0.05, 2.5, 0.1, 0.1);
        ShowSyncHudMsg(attacker, g_HudSyncMoney, "+$%d^n(%s Kill)", targetReward, weaponName);
    }

    return HAM_IGNORED;
}
