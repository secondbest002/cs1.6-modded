// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: KILL REWARD CASH ECONOMY
// Per-weapon CS2 kill rewards: Knife ($1500), Shotgun ($900), SMG ($600), AWP ($100)
// ==============================================================================

#if defined _mod_kill_reward_included
    #endinput
#endif
#define _mod_kill_reward_included

// CVars
new kr_pCvar_Enable;
new kr_pCvar_Notify;

// Hud Sync
new kr_HudSyncMoney;

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_KillReward_Init()
{
    kr_pCvar_Enable = register_cvar("amx_cs2_kill_reward", "1");
    kr_pCvar_Notify = register_cvar("amx_cs2_kill_reward_notify", "1");

    RegisterHam(Ham_Killed, "player", "kr_OnPlayerKilledPost", 1);

    kr_HudSyncMoney = CreateHudSyncObj();
}

public Mod_KillReward_Precache()
{
    // No custom assets required for kill rewards
}

public Mod_KillReward_PutInServer(id)
{
    // Stateless per player
}

public Mod_KillReward_Disconnect(id)
{
    // Stateless per player
}

public Mod_KillReward_NewRound()
{
    // Round economy is event-driven
}

public Mod_KillReward_RoundEnd()
{
    // Round economy is event-driven
}

stock bool:kr_IsHoldingVariant(id, weapon_id, const variant_name[])
{
    if (callfunc_begin("cs2_is_user_holding_variant", "cs2_weapon_variants.amxx") == 1)
    {
        callfunc_push_int(id);
        callfunc_push_int(weapon_id);
        callfunc_push_str(variant_name);
        return bool:callfunc_end();
    }

    // Direct fallback inspect of viewmodel
    new szVm[128];
    pev(id, pev_viewmodel2, szVm, charsmax(szVm));
    if (szVm[0] && containi(szVm, variant_name) != -1)
        return true;

    return false;
}

// -------------------------------------------------------------
// Ham_Killed Post Handler
// -------------------------------------------------------------
public kr_OnPlayerKilledPost(victim, attacker, shouldgib)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(kr_pCvar_Enable))
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
        case CSW_M3:
        {
            targetReward = 900;
            if (kr_IsHoldingVariant(attacker, CSW_M3, "sawed"))
                copy(weaponName, charsmax(weaponName), "Sawed-Off");
            else
                copy(weaponName, charsmax(weaponName), "M3 Shotgun");
        }
        case CSW_XM1014:
        {
            targetReward = 900;
            if (kr_IsHoldingVariant(attacker, CSW_XM1014, "mag"))
                copy(weaponName, charsmax(weaponName), "MAG-7");
            else
                copy(weaponName, charsmax(weaponName), "XM1014");
        }
        // SMGs: $600 (Except CZ75: $100 penalty, P90 standard: $300, PP-Bizon: $600)
        case CSW_MP5NAVY, CSW_UMP45:
        {
            targetReward = 600;
            if (weaponId == CSW_MP5NAVY && kr_IsHoldingVariant(attacker, CSW_MP5NAVY, "mp7"))
                copy(weaponName, charsmax(weaponName), "MP7");
            else
                copy(weaponName, charsmax(weaponName), "SMG");
        }
        case CSW_MAC10, CSW_TMP:
        {
            if (kr_IsHoldingVariant(attacker, weaponId, "cz"))
            {
                // CS2 / CS:GO meta penalty: CZ75-Auto kill reward is only $100!
                targetReward = 100;
                copy(weaponName, charsmax(weaponName), "CZ75-Auto");
            }
            else
            {
                targetReward = 600;
                copy(weaponName, charsmax(weaponName), (weaponId == CSW_TMP) ? "TMP" : "MAC-10");
            }
        }
        case CSW_P90:
        {
            if (kr_IsHoldingVariant(attacker, CSW_P90, "bizon"))
            {
                // CS2 / CS:GO meta: PP-Bizon is a standard SMG rewarded with $600!
                targetReward = 600;
                copy(weaponName, charsmax(weaponName), "PP-Bizon");
            }
            else
            {
                // Standard P90 kill reward is $300 in CS2/CS:GO
                targetReward = 300;
                copy(weaponName, charsmax(weaponName), "P90");
            }
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
            if (kr_IsHoldingVariant(attacker, CSW_M249, "negev"))
                copy(weaponName, charsmax(weaponName), "Negev");
            else
                copy(weaponName, charsmax(weaponName), "M249");
        }
        // Pistols: P228 / Tec-9
        case CSW_P228:
        {
            targetReward = 300;
            if (kr_IsHoldingVariant(attacker, CSW_P228, "tec"))
                copy(weaponName, charsmax(weaponName), "Tec-9");
            else
                copy(weaponName, charsmax(weaponName), "P228");
        }
        // Other Pistols & Rifles: default $300
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
    if (get_pcvar_num(kr_pCvar_Notify))
    {
        set_hudmessage(50, 220, 50, 0.78, 0.82, 0, 0.05, 2.5, 0.1, 0.1);
        ShowSyncHudMsg(attacker, kr_HudSyncMoney, "+$%d^n(%s Kill)", targetReward, weaponName);
    }

    return HAM_IGNORED;
}
