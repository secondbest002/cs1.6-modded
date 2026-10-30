/*
 * ==============================================================================
 * CS2 WEAPON VARIANTS SYSTEM
 * ==============================================================================
 * Author: Antigravity
 * Version: 1.0.0
 *
 * Responsibilities:
 *   1. Dynamic Weapon Pricing & Economy Refunds matching CS:GO/CS2 meta:
 *      - MAG-7:     $1,300 (XM1014 $3,000 -> $1,700 refunded)
 *      - Negev:     $1,700 (M249   $5,750 -> $4,050 refunded)
 *      - Sawed-Off: $1,100 (M3     $1,700 -> $600 refunded)
 *      - PP-Bizon:  $1,400 (P90    $2,350 -> $950 refunded)
 *      - CZ75-Auto: $500   (TMP $1,250 -> $750 / MAC-10 $1,400 -> $900 refunded)
 *      - Tec-9:     $500   (P228   $600   -> $100 refunded)
 *      - MP7:       $1,500 (MP5    $1,500 -> $0 refunded)
 *
 *   2. Authentic Clip Size Overrides & Magazine Mechanics:
 *      - MAG-7:     5 clip (fast box magazine reload cycle)
 *      - PP-Bizon:  64 clip (helical magazine)
 *      - Negev:     150 clip (drum belt box)
 *      - CZ75-Auto: 12 clip & 12 reserve
 *      - Tec-9:     18 clip
 *
 *   3. Shared Native Query API for Single Source of Truth across all plugins:
 *      - cs2_is_user_holding_variant(id, weapon_id, variant_name)
 *      - cs2_get_user_weapon_variant(id, weapon_id, buffer, maxlen)
 *      - cs2_get_variant_price(weapon_id, variant_name)
 * ==============================================================================
 */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN_NAME    "CS2 Weapon Variants System"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR  "Antigravity"

// Offsets
#define m_pPlayer               41
#define extra_offset_weapon     4
#define extra_offset_player     5
#define m_flNextPrimaryAttack   46
#define m_flNextSecondaryAttack 47
#define m_flTimeWeaponIdle      48
#define m_iClip                 51
#define m_fInReload             54
#define m_iSpecialReload        55
#define m_flNextAttack          83

// CVars
new g_pCvarEnable;
new g_pCvarPricing;
new g_pCvarClipOverride;
new g_pCvarNotify;

// Hud Sync
new g_HudSyncEco;

// Active loadout cache from active_loadout.ini
new g_szActiveLoadoutCT[CSW_LAST_WEAPON + 1][64];
new g_szActiveLoadoutT[CSW_LAST_WEAPON + 1][64];

// Reload state tracking per weapon entity
new bool:g_bWeaponInReload[1024];

// Purchase detection tracking per player
new g_iPendingBuyWeapon[33];
new Float:g_flPendingBuyTime[33];

// Weapon entity classnames
new const g_szVariantWeapons[][] = {
    "weapon_p228",      // Tec-9
    "weapon_xm1014",    // MAG-7
    "weapon_mac10",     // CZ75-Auto (T)
    "weapon_tmp",       // CZ75-Auto (CT)
    "weapon_mp5navy",   // MP7
    "weapon_m249",      // Negev
    "weapon_m3",        // Sawed-Off
    "weapon_p90"        // PP-Bizon
};

// ==============================================================================
// PLUGIN INITIALIZATION & NATIVE EXPORTS
// ==============================================================================

public plugin_natives()
{
    register_native("cs2_is_user_holding_variant", "native_is_user_holding_variant");
    register_native("cs2_get_user_weapon_variant", "native_get_user_weapon_variant");
    register_native("cs2_get_variant_price",       "native_get_variant_price");
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_pCvarEnable       = register_cvar("amx_cs2_variants", "1");
    g_pCvarPricing      = register_cvar("amx_cs2_variant_pricing", "1");
    g_pCvarClipOverride = register_cvar("amx_cs2_variant_clips", "1");
    g_pCvarNotify       = register_cvar("amx_cs2_variant_notify", "1");

    g_HudSyncEco = CreateHudSyncObj();

    // Register Ham hooks for all variant-compatible weapons
    for (new i = 0; i < sizeof(g_szVariantWeapons); i++)
    {
        RegisterHam(Ham_Item_Deploy,    g_szVariantWeapons[i], "OnVariantDeploy_Post",    1);
        RegisterHam(Ham_Item_PostFrame, g_szVariantWeapons[i], "OnVariantPostFrame_Post", 1);
        RegisterHam(Ham_Item_AddToPlayer, g_szVariantWeapons[i], "OnVariantAddToPlayer_Post", 1);
    }

    // CurWeapon hook for real-time HUD clip counter synchronization
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");

    // Client buy command intercepts
    HookBuyCommands();

    server_print("[CS2 Variants] Initialized successfully. Modern weapons economics & mechanics active.");
}

public plugin_cfg()
{
    LoadActiveLoadouts();
}

public Event_NewRound()
{
    LoadActiveLoadouts();
}

// ==============================================================================
// LOADOUT CACHE & CONFIG INGESTION
// ==============================================================================

public LoadActiveLoadouts()
{
    new szCfgDir[128], szPath[160];
    get_configsdir(szCfgDir, charsmax(szCfgDir));
    formatex(szPath, charsmax(szPath), "%s/active_loadout.ini", szCfgDir);

    for (new w = 0; w <= CSW_LAST_WEAPON; w++)
    {
        g_szActiveLoadoutCT[w][0] = '^0';
        g_szActiveLoadoutT[w][0] = '^0';
    }

    if (!file_exists(szPath))
        return;

    new f = fopen(szPath, "rt");
    if (!f)
        return;

    new szLine[128], szSection[32];
    new currentSection = 0; // 1 = CT, 2 = T

    while (!feof(f))
    {
        fgets(f, szLine, charsmax(szLine));
        trim(szLine);

        if (!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue;

        if (szLine[0] == '[')
        {
            copyc(szSection, charsmax(szSection), szLine[1], ']');
            if (containi(szSection, "CT") != -1)
                currentSection = 1;
            else if (containi(szSection, "T") != -1)
                currentSection = 2;
            else
                currentSection = 0;
            continue;
        }

        if (currentSection == 0)
            continue;

        new szKey[32], szVal[64];
        new eqPos = contain(szLine, "=");
        if (eqPos != -1)
        {
            copy(szKey, eqPos, szLine);
            copy(szVal, charsmax(szVal), szLine[eqPos + 1]);
            trim(szKey);
            trim(szVal);

            // Strip quotes
            if (szVal[0] == '"')
            {
                copy(szVal, charsmax(szVal), szVal[1]);
                new len = strlen(szVal);
                if (len > 0 && szVal[len - 1] == '"')
                {
                    szVal[len - 1] = '^0';
                }
                trim(szVal);
            }

            new wpnId = ParseWeaponId(szKey);
            if (wpnId > CSW_NONE && wpnId <= CSW_LAST_WEAPON)
            {
                if (currentSection == 1)
                    copy(g_szActiveLoadoutCT[wpnId], charsmax(g_szActiveLoadoutCT[]), szVal);
                else
                    copy(g_szActiveLoadoutT[wpnId], charsmax(g_szActiveLoadoutT[]), szVal);
            }
        }
    }
    fclose(f);
}

stock ParseWeaponId(const szKey[])
{
    if (equali(szKey, "P228"))     return CSW_P228;
    if (equali(szKey, "XM1014"))   return CSW_XM1014;
    if (equali(szKey, "MAC10"))    return CSW_MAC10;
    if (equali(szKey, "TMP"))      return CSW_TMP;
    if (equali(szKey, "MP5NAVY"))  return CSW_MP5NAVY;
    if (equali(szKey, "M249"))     return CSW_M249;
    if (equali(szKey, "M3"))       return CSW_M3;
    if (equali(szKey, "P90"))      return CSW_P90;
    return CSW_NONE;
}

// ==============================================================================
// VARIANT RECOGNITION HELPERS
// ==============================================================================

stock bool:IsPlayerUsingVariant(id, weapon_id, const variant_name[] = "")
{
    if (!is_user_connected(id))
        return false;

    if (weapon_id <= CSW_NONE)
    {
        weapon_id = cs_get_user_weapon(id);
    }

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return false;

    // 1. Inspect player's currently active viewmodel if alive
    new szVm[128];
    if (is_user_alive(id))
    {
        pev(id, pev_viewmodel2, szVm, charsmax(szVm));
        if (szVm[0])
        {
            if (variant_name[0])
            {
                if (containi(szVm, variant_name) != -1)
                    return true;
            }
            else
            {
                // Check if current viewmodel matches any known modern variant
                if (containi(szVm, "mag7") != -1 ||
                    containi(szVm, "negev") != -1 ||
                    containi(szVm, "sawed") != -1 ||
                    containi(szVm, "bizon") != -1 ||
                    containi(szVm, "cz75") != -1 ||
                    containi(szVm, "tec9") != -1 ||
                    containi(szVm, "mp7") != -1)
                {
                    return true;
                }
            }
        }
    }

    // 2. Fallback to active loadout cache by player's team
    new CsTeams:team = cs_get_user_team(id);
    new szLoadoutModel[64];
    if (team == CS_TEAM_CT)
        copy(szLoadoutModel, charsmax(szLoadoutModel), g_szActiveLoadoutCT[weapon_id]);
    else if (team == CS_TEAM_T)
        copy(szLoadoutModel, charsmax(szLoadoutModel), g_szActiveLoadoutT[weapon_id]);

    if (szLoadoutModel[0])
    {
        if (variant_name[0])
        {
            return (containi(szLoadoutModel, variant_name) != -1);
        }
        else
        {
            return (containi(szLoadoutModel, "mag7") != -1 ||
                    containi(szLoadoutModel, "negev") != -1 ||
                    containi(szLoadoutModel, "sawed") != -1 ||
                    containi(szLoadoutModel, "bizon") != -1 ||
                    containi(szLoadoutModel, "cz75") != -1 ||
                    containi(szLoadoutModel, "tec9") != -1 ||
                    containi(szLoadoutModel, "mp7") != -1);
        }
    }

    return false;
}

stock GetVariantInfo(id, weapon_id, szVariantName[], nameLen, &targetPrice, &refundAmount, &targetClip)
{
    targetPrice = 0;
    refundAmount = 0;
    targetClip = 0;
    szVariantName[0] = '^0';

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return 0;

    switch (weapon_id)
    {
        case CSW_XM1014: // MAG-7
        {
            if (IsPlayerUsingVariant(id, weapon_id, "mag7") || IsPlayerUsingVariant(id, weapon_id, "mag"))
            {
                copy(szVariantName, nameLen, "MAG-7");
                targetPrice = 1300;
                refundAmount = 1700; // XM1014 $3,000 - $1,300
                targetClip = 5;
                return 1;
            }
        }
        case CSW_M249: // Negev
        {
            if (IsPlayerUsingVariant(id, weapon_id, "negev"))
            {
                copy(szVariantName, nameLen, "Negev");
                targetPrice = 1700;
                refundAmount = 4050; // M249 $5,750 - $1,700
                targetClip = 150;
                return 1;
            }
        }
        case CSW_M3: // Sawed-Off
        {
            if (IsPlayerUsingVariant(id, weapon_id, "sawed") || IsPlayerUsingVariant(id, weapon_id, "sawedoff"))
            {
                copy(szVariantName, nameLen, "Sawed-Off");
                targetPrice = 1100;
                refundAmount = 600; // M3 $1,700 - $1,100
                targetClip = 8;
                return 1;
            }
        }
        case CSW_P90: // PP-Bizon
        {
            if (IsPlayerUsingVariant(id, weapon_id, "bizon"))
            {
                copy(szVariantName, nameLen, "PP-Bizon");
                targetPrice = 1400;
                refundAmount = 950; // P90 $2,350 - $1,400
                targetClip = 64;
                return 1;
            }
        }
        case CSW_TMP: // CZ75-Auto (CT)
        {
            if (IsPlayerUsingVariant(id, weapon_id, "cz") || IsPlayerUsingVariant(id, weapon_id, "cz75"))
            {
                copy(szVariantName, nameLen, "CZ75-Auto");
                targetPrice = 500;
                refundAmount = 750; // TMP $1,250 - $500
                targetClip = 12;
                return 1;
            }
        }
        case CSW_MAC10: // CZ75-Auto (T)
        {
            if (IsPlayerUsingVariant(id, weapon_id, "cz") || IsPlayerUsingVariant(id, weapon_id, "cz75"))
            {
                copy(szVariantName, nameLen, "CZ75-Auto");
                targetPrice = 500;
                refundAmount = 900; // MAC-10 $1,400 - $500
                targetClip = 12;
                return 1;
            }
        }
        case CSW_P228: // Tec-9
        {
            if (IsPlayerUsingVariant(id, weapon_id, "tec") || IsPlayerUsingVariant(id, weapon_id, "tec9"))
            {
                copy(szVariantName, nameLen, "Tec-9");
                targetPrice = 500;
                refundAmount = 100; // P228 $600 - $500
                targetClip = 18;
                return 1;
            }
        }
        case CSW_MP5NAVY: // MP7
        {
            if (IsPlayerUsingVariant(id, weapon_id, "mp7"))
            {
                copy(szVariantName, nameLen, "MP7");
                targetPrice = 1500;
                refundAmount = 0; // MP5NAVY $1,500 - $1,500
                targetClip = 30;
                return 1;
            }
        }
    }
    return 0;
}

// ==============================================================================
// 1. DYNAMIC WEAPON PRICING & ECONOMY REFUND
// ==============================================================================

stock HookBuyCommands()
{
    // Shotguns
    register_clcmd("xm1014",      "Cmd_BuyXM1014");
    register_clcmd("autoshotgun", "Cmd_BuyXM1014");
    register_clcmd("m3",          "Cmd_BuyM3");
    register_clcmd("12gauge",     "Cmd_BuyM3");

    // Heavy
    register_clcmd("m249",        "Cmd_BuyM249");

    // SMGs
    register_clcmd("p90",         "Cmd_BuyP90");
    register_clcmd("c90",         "Cmd_BuyP90");
    register_clcmd("tmp",         "Cmd_BuyTMP");
    register_clcmd("mp",          "Cmd_BuyTMP");
    register_clcmd("mac10",       "Cmd_BuyMAC10");
    register_clcmd("mp5",         "Cmd_BuyMP5");
    register_clcmd("mp5navy",     "Cmd_BuyMP5");
    register_clcmd("smg",         "Cmd_BuyMP5");

    // Pistols
    register_clcmd("p228",        "Cmd_BuyP228");
    register_clcmd("228compact",  "Cmd_BuyP228");

    // General buy / autobuy
    register_clcmd("cl_autobuy",  "Cmd_AutoBuy");
    register_clcmd("cl_rebuy",    "Cmd_ReBuy");
    register_clcmd("autobuy",     "Cmd_AutoBuy");
    register_clcmd("rebuy",       "Cmd_ReBuy");
    register_clcmd("menuselect",  "Cmd_MenuSelect");
    register_clcmd("buy",         "Cmd_Buy");
    register_clcmd("buyequip",    "Cmd_Buy");

    // Loadout reload command
    register_concmd("cs2_reload_loadout", "Cmd_ReloadActiveLoadout", ADMIN_CFG);
}

public Cmd_BuyXM1014(id) { SetPendingBuy(id, CSW_XM1014); return PLUGIN_CONTINUE; }
public Cmd_BuyM249(id)   { SetPendingBuy(id, CSW_M249);   return PLUGIN_CONTINUE; }
public Cmd_BuyM3(id)     { SetPendingBuy(id, CSW_M3);     return PLUGIN_CONTINUE; }
public Cmd_BuyP90(id)    { SetPendingBuy(id, CSW_P90);    return PLUGIN_CONTINUE; }
public Cmd_BuyTMP(id)    { SetPendingBuy(id, CSW_TMP);    return PLUGIN_CONTINUE; }
public Cmd_BuyMAC10(id)  { SetPendingBuy(id, CSW_MAC10);  return PLUGIN_CONTINUE; }
public Cmd_BuyP228(id)   { SetPendingBuy(id, CSW_P228);   return PLUGIN_CONTINUE; }
public Cmd_BuyMP5(id)    { SetPendingBuy(id, CSW_MP5NAVY); return PLUGIN_CONTINUE; }

public Cmd_AutoBuy(id)   { g_flPendingBuyTime[id] = get_gametime(); return PLUGIN_CONTINUE; }
public Cmd_ReBuy(id)     { g_flPendingBuyTime[id] = get_gametime(); return PLUGIN_CONTINUE; }
public Cmd_MenuSelect(id){ g_flPendingBuyTime[id] = get_gametime(); return PLUGIN_CONTINUE; }
public Cmd_Buy(id)       { g_flPendingBuyTime[id] = get_gametime(); return PLUGIN_CONTINUE; }
public Cmd_ReloadActiveLoadout(id, level, cid) { LoadActiveLoadouts(); return PLUGIN_CONTINUE; }

stock SetPendingBuy(id, weaponId)
{
    g_iPendingBuyWeapon[id] = weaponId;
    g_flPendingBuyTime[id]  = get_gametime();
}

public OnVariantAddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(g_pCvarEnable) || !pev_valid(iWpn) || !is_user_alive(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(iWpn);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return HAM_IGNORED;

    // Check if weapon is freshly spawned/purchased (pev_iuser3 == 0)
    new iHandled = pev(iWpn, pev_iuser3);
    if (iHandled != 0)
        return HAM_IGNORED;

    set_pev(iWpn, pev_iuser3, 1);

    // Apply CS2 Meta Pricing & Economy refund if genuine purchase occurred in buyzone
    if (get_pcvar_num(g_pCvarPricing))
    {
        new bool:bInBuyzone = bool:cs_get_user_buyzone(id);
        new Float:flTimeDiff = get_gametime() - g_flPendingBuyTime[id];
        new bool:bRecentlyBought = (flTimeDiff < 2.0 && g_flPendingBuyTime[id] > 0.0);

        if (bInBuyzone && bRecentlyBought)
        {
            new szName[32], targetPrice, refundAmount, targetClip;
            if (GetVariantInfo(id, weapon_id, szName, charsmax(szName), targetPrice, refundAmount, targetClip))
            {
                if (refundAmount > 0)
                {
                    new curMoney = cs_get_user_money(id);
                    new newMoney = min(16000, curMoney + refundAmount);
                    cs_set_user_money(id, newMoney, 1);

                    // User notification
                    if (get_pcvar_num(g_pCvarNotify) && !is_user_bot(id))
                    {
                        // Chat message
                        client_print_color(id, print_team_default, "^4[CS2 Economy]^1 %s purchased for ^4$%d^1 (^3$%d^1 refunded)",
                            szName, targetPrice, refundAmount);

                        // HUD display
                        set_hudmessage(50, 220, 50, -1.0, 0.72, 0, 0.05, 3.0, 0.1, 0.2);
                        ShowSyncHudMsg(id, g_HudSyncEco, "[CS2 Economy] %s: $%d ($%d Refunded)",
                            szName, targetPrice, refundAmount);
                    }
                }
            }
        }
    }

    g_iPendingBuyWeapon[id] = 0;
    g_flPendingBuyTime[id]  = 0.0;
    return HAM_IGNORED;
}

// ==============================================================================
// 2. AUTHENTIC CLIP SIZE OVERRIDES & MAGAZINE BEHAVIOR
// ==============================================================================

public OnVariantDeploy_Post(iWpn)
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarClipOverride) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, m_pPlayer, extra_offset_weapon);
    if (!is_user_alive(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(iWpn);
    new szName[32], targetPrice, refundAmount, targetClip;

    if (!GetVariantInfo(id, weapon_id, szName, charsmax(szName), targetPrice, refundAmount, targetClip))
        return HAM_IGNORED;

    new curClip = cs_get_weapon_ammo(iWpn);
    new iClipInited = pev(iWpn, pev_iuser4);

    if (!iClipInited)
    {
        set_pev(iWpn, pev_iuser4, 1);

        switch (weapon_id)
        {
            case CSW_XM1014: // MAG-7: 5 clip
            {
                if (curClip > 5)
                {
                    new excess = curClip - 5;
                    cs_set_weapon_ammo(iWpn, 5);
                    cs_set_user_bpammo(id, CSW_XM1014, cs_get_user_bpammo(id, CSW_XM1014) + excess);
                }
            }
            case CSW_P90: // PP-Bizon: 64 clip
            {
                if (curClip < 64)
                {
                    new bp = cs_get_user_bpammo(id, CSW_P90);
                    new need = 64 - curClip;
                    new add = min(need, bp);
                    if (add > 0)
                    {
                        cs_set_weapon_ammo(iWpn, curClip + add);
                        cs_set_user_bpammo(id, CSW_P90, bp - add);
                    }
                    else if (curClip == 50)
                    {
                        cs_set_weapon_ammo(iWpn, 64);
                    }
                }
            }
            case CSW_M249: // Negev: 150 clip
            {
                if (curClip < 150)
                {
                    new bp = cs_get_user_bpammo(id, CSW_M249);
                    new need = 150 - curClip;
                    new add = min(need, bp);
                    if (add > 0)
                    {
                        cs_set_weapon_ammo(iWpn, curClip + add);
                        cs_set_user_bpammo(id, CSW_M249, bp - add);
                    }
                    else if (curClip == 100)
                    {
                        cs_set_weapon_ammo(iWpn, 150);
                    }
                }
            }
            case CSW_TMP, CSW_MAC10: // CZ75-Auto: 12 clip, 12 reserve
            {
                if (curClip > 12)
                {
                    cs_set_weapon_ammo(iWpn, 12);
                }
                if (cs_get_user_bpammo(id, weapon_id) > 12)
                {
                    cs_set_user_bpammo(id, weapon_id, 12);
                }
            }
            case CSW_P228: // Tec-9: 18 clip
            {
                if (curClip < 18)
                {
                    new bp = cs_get_user_bpammo(id, CSW_P228);
                    new need = 18 - curClip;
                    new add = min(need, bp);
                    if (add > 0)
                    {
                        cs_set_weapon_ammo(iWpn, curClip + add);
                        cs_set_user_bpammo(id, CSW_P228, bp - add);
                    }
                    else if (curClip == 13)
                    {
                        cs_set_weapon_ammo(iWpn, 18);
                    }
                }
            }
        }
    }

    return HAM_IGNORED;
}

public OnVariantPostFrame_Post(iWpn)
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarClipOverride) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, m_pPlayer, extra_offset_weapon);
    if (!is_user_alive(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(iWpn);
    new szName[32], targetPrice, refundAmount, targetClip;

    if (!GetVariantInfo(id, weapon_id, szName, charsmax(szName), targetPrice, refundAmount, targetClip))
        return HAM_IGNORED;

    new iEntIdx = iWpn;
    if (iEntIdx >= sizeof(g_bWeaponInReload))
        iEntIdx = 0;

    // Shotgun MAG-7 Special Reload Loop
    if (weapon_id == CSW_XM1014)
    {
        new iSpecialReload = get_pdata_int(iWpn, m_iSpecialReload, extra_offset_weapon);
        if (iSpecialReload == 1)
        {
            // Box magazine fast load: fill up to 5 immediately and cock
            new cur = cs_get_weapon_ammo(iWpn);
            new bp = cs_get_user_bpammo(id, CSW_XM1014);
            new need = 5 - cur;
            if (need > 0 && bp > 0)
            {
                new add = min(need, bp);
                cs_set_weapon_ammo(iWpn, cur + add);
                cs_set_user_bpammo(id, CSW_XM1014, bp - add);
            }
            // Transition directly to pump/cock finish
            set_pdata_int(iWpn, m_iSpecialReload, 3, extra_offset_weapon);
            set_pdata_float(iWpn, m_flTimeWeaponIdle, 0.75, extra_offset_weapon);
            set_pdata_float(id, m_flNextAttack, 0.75, extra_offset_player);
        }
        else if (iSpecialReload == 2)
        {
            if (cs_get_weapon_ammo(iWpn) >= 5)
            {
                set_pdata_int(iWpn, m_iSpecialReload, 3, extra_offset_weapon);
            }
        }
        return HAM_IGNORED;
    }

    // Magazine Weapons Reload Finish Detection
    new inReload = get_pdata_int(iWpn, m_fInReload, extra_offset_weapon);
    if (inReload == 1)
    {
        if (iEntIdx > 0)
            g_bWeaponInReload[iEntIdx] = true;
    }
    else
    {
        if (iEntIdx > 0 && g_bWeaponInReload[iEntIdx])
        {
            g_bWeaponInReload[iEntIdx] = false;

            // Reload just completed! Adjust clip sizes
            switch (weapon_id)
            {
                case CSW_P90: // PP-Bizon: 64
                {
                    new cur = cs_get_weapon_ammo(iWpn);
                    if (cur < 64)
                    {
                        new bp = cs_get_user_bpammo(id, CSW_P90);
                        new need = 64 - cur;
                        new add = min(need, bp);
                        if (add > 0)
                        {
                            cs_set_weapon_ammo(iWpn, cur + add);
                            cs_set_user_bpammo(id, CSW_P90, bp - add);
                        }
                    }
                }
                case CSW_M249: // Negev: 150
                {
                    new cur = cs_get_weapon_ammo(iWpn);
                    if (cur < 150)
                    {
                        new bp = cs_get_user_bpammo(id, CSW_M249);
                        new need = 150 - cur;
                        new add = min(need, bp);
                        if (add > 0)
                        {
                            cs_set_weapon_ammo(iWpn, cur + add);
                            cs_set_user_bpammo(id, CSW_M249, bp - add);
                        }
                    }
                }
                case CSW_TMP, CSW_MAC10: // CZ75-Auto: 12
                {
                    new cur = cs_get_weapon_ammo(iWpn);
                    if (cur > 12)
                    {
                        new excess = cur - 12;
                        cs_set_weapon_ammo(iWpn, 12);
                        new bp = cs_get_user_bpammo(id, weapon_id);
                        cs_set_user_bpammo(id, weapon_id, min(12, bp + excess));
                    }
                }
                case CSW_P228: // Tec-9: 18
                {
                    new cur = cs_get_weapon_ammo(iWpn);
                    if (cur < 18)
                    {
                        new bp = cs_get_user_bpammo(id, CSW_P228);
                        new need = 18 - cur;
                        new add = min(need, bp);
                        if (add > 0)
                        {
                            cs_set_weapon_ammo(iWpn, cur + add);
                            cs_set_user_bpammo(id, CSW_P228, bp - add);
                        }
                    }
                }
            }
        }
    }

    return HAM_IGNORED;
}

public Event_CurWeapon(id)
{
    if (!get_pcvar_num(g_pCvarEnable) || !get_pcvar_num(g_pCvarClipOverride) || !is_user_alive(id))
        return;

    new weapon_id = read_data(2);
    new clip = read_data(3);

    // Enforce limits on active HUD update
    if (weapon_id == CSW_XM1014 && clip > 5)
    {
        if (IsPlayerUsingVariant(id, weapon_id, "mag7") || IsPlayerUsingVariant(id, weapon_id, "mag"))
        {
            new iWpn = get_pdata_cbase(id, 373, extra_offset_player);
            if (pev_valid(iWpn))
            {
                new excess = clip - 5;
                cs_set_weapon_ammo(iWpn, 5);
                cs_set_user_bpammo(id, CSW_XM1014, cs_get_user_bpammo(id, CSW_XM1014) + excess);
            }
        }
    }
    else if ((weapon_id == CSW_TMP || weapon_id == CSW_MAC10) && clip > 12)
    {
        if (IsPlayerUsingVariant(id, weapon_id, "cz") || IsPlayerUsingVariant(id, weapon_id, "cz75"))
        {
            new iWpn = get_pdata_cbase(id, 373, extra_offset_player);
            if (pev_valid(iWpn))
            {
                cs_set_weapon_ammo(iWpn, 12);
                if (cs_get_user_bpammo(id, weapon_id) > 12)
                    cs_set_user_bpammo(id, weapon_id, 12);
            }
        }
    }
}

// ==============================================================================
// 3. SHARED NATIVE & PUBLIC INTEROP API
// ==============================================================================

public bool:native_is_user_holding_variant(numParams)
{
    new id = get_param(1);
    new weapon_id = get_param(2);
    new szVariant[32];
    get_string(3, szVariant, charsmax(szVariant));

    return IsPlayerUsingVariant(id, weapon_id, szVariant);
}

public bool:native_get_user_weapon_variant(numParams)
{
    new id = get_param(1);
    new weapon_id = get_param(2);
    new maxlen = get_param(4);

    new szName[32], targetPrice, refundAmount, targetClip;
    if (GetVariantInfo(id, weapon_id, szName, charsmax(szName), targetPrice, refundAmount, targetClip))
    {
        set_string(3, szName, maxlen);
        return true;
    }
    return false;
}

public native_get_variant_price(numParams)
{
    new weapon_id = get_param(1);
    new szVariant[32];
    get_string(2, szVariant, charsmax(szVariant));

    if (szVariant[0])
    {
        if (containi(szVariant, "mag") != -1)     return 1300;
        if (containi(szVariant, "negev") != -1)   return 1700;
        if (containi(szVariant, "sawed") != -1)   return 1100;
        if (containi(szVariant, "bizon") != -1)   return 1400;
        if (containi(szVariant, "cz") != -1)      return 500;
        if (containi(szVariant, "tec") != -1)     return 500;
        if (containi(szVariant, "mp7") != -1)     return 1500;
    }

    switch (weapon_id)
    {
        case CSW_XM1014: return 1300; // MAG-7
        case CSW_M249:   return 1700; // Negev
        case CSW_M3:     return 1100; // Sawed-Off
        case CSW_P90:    return 1400; // PP-Bizon
        case CSW_TMP, CSW_MAC10: return 500; // CZ75-Auto
        case CSW_P228:   return 500;  // Tec-9
        case CSW_MP5NAVY: return 1500; // MP7
    }
    return 0;
}

// Public functions for dynamic callfunc interoperability across AMXX modules
public bool:cs2_is_user_holding_variant(id, weapon_id, const szVariant[])
{
    return IsPlayerUsingVariant(id, weapon_id, szVariant);
}

public bool:cs2_get_user_weapon_variant(id, weapon_id, szBuffer[], maxlen)
{
    new szName[32], targetPrice, refundAmount, targetClip;
    if (GetVariantInfo(id, weapon_id, szName, charsmax(szName), targetPrice, refundAmount, targetClip))
    {
        copy(szBuffer, maxlen, szName);
        return true;
    }
    return false;
}

public cs2_get_variant_price(weapon_id, const szVariant[])
{
    if (szVariant[0])
    {
        if (containi(szVariant, "mag") != -1)     return 1300;
        if (containi(szVariant, "negev") != -1)   return 1700;
        if (containi(szVariant, "sawed") != -1)   return 1100;
        if (containi(szVariant, "bizon") != -1)   return 1400;
        if (containi(szVariant, "cz") != -1)      return 500;
        if (containi(szVariant, "tec") != -1)     return 500;
        if (containi(szVariant, "mp7") != -1)     return 1500;
    }

    switch (weapon_id)
    {
        case CSW_XM1014: return 1300; // MAG-7
        case CSW_M249:   return 1700; // Negev
        case CSW_M3:     return 1100; // Sawed-Off
        case CSW_P90:    return 1400; // PP-Bizon
        case CSW_TMP, CSW_MAC10: return 500; // CZ75-Auto
        case CSW_P228:   return 500;  // Tec-9
        case CSW_MP5NAVY: return 1500; // MP7
    }
    return 0;
}
