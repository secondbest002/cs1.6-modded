/*
 * CS2 Faction Loadout & Dual-Faction Dropper Plugin for Counter-Strike 1.6
 *
 * Purpose:
 * Directly resolves the CT vs T weapon drop conflict (w_*.mdl) and viewmodel/
 * playermodel isolation (v_*.mdl, p_*.mdl) when playing on local server against bots.
 *
 * Features:
 * - Intercepts Ham_Item_Deploy to assign faction-specific v_ and p_ models (CT vs T).
 * - Intercepts FM_SetModel to detect weapon drop owner and assign faction-specific w_ model
 *   (models/cs2_loadout/ct/w_<weapon>.mdl for CT or models/cs2_loadout/t/w_<weapon>.mdl for T).
 * - Fallback logic: Automatically falls back to standard/legacy models if faction-specific
 *   model does not exist on disk.
 * - Supports bots and human players seamlessly.
 */

#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "CS2 Faction Loadout & Dropper"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

#define TEAM_CT_INDEX 0
#define TEAM_T_INDEX  1

// CVars
new pCvar_Enable;
new pCvar_DropSync;

// Weapon Index Table (Matches CSW_* constants)
new const g_WeaponEntityNames[CSW_LAST_WEAPON + 1][] = {
    "",
    "weapon_p228",
    "",
    "weapon_scout",
    "weapon_hegrenade",
    "weapon_xm1014",
    "weapon_c4",
    "weapon_mac10",
    "weapon_aug",
    "weapon_smokegrenade",
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
    "weapon_flashbang",
    "weapon_deagle",
    "weapon_sg552",
    "weapon_ak47",
    "weapon_knife",
    "weapon_p90"
};

// Canonical GoldSrc weapon stems
new const g_WeaponStems[CSW_LAST_WEAPON + 1][] = {
    "",
    "p228",
    "",
    "scout",
    "hegrenade",
    "xm1014",
    "c4",
    "mac10",
    "aug",
    "smokegrenade",
    "elite",
    "fiveseven",
    "ump45",
    "sg550",
    "galil",
    "famas",
    "usp",
    "glock18",
    "awp",
    "mp5",
    "m249",
    "m3",
    "m4a1",
    "tmp",
    "g3sg1",
    "flashbang",
    "deagle",
    "sg552",
    "ak47",
    "knife",
    "p90"
};

// Precached model paths: [team: 0=CT, 1=T][weapon_id][path]
new g_VModels[2][CSW_LAST_WEAPON + 1][128];
new g_PModels[2][CSW_LAST_WEAPON + 1][128];
new g_WModels[2][CSW_LAST_WEAPON + 1][128];

// Precache & Model Discovery
public plugin_precache()
{
    new ct_v_count = 0, ct_p_count = 0, ct_w_count = 0;
    new t_v_count = 0, t_p_count = 0, t_w_count = 0;

    for (new i = 1; i <= CSW_LAST_WEAPON; i++)
    {
        if (!g_WeaponStems[i][0])
            continue;

        // -------------------------------------------------------------
        // CT Models: Check cs2_loadout/ct, custom_skins/ct, csgo_skins/ct
        // -------------------------------------------------------------
        ResolveAndPrecacheModel(TEAM_CT_INDEX, "v", g_WeaponStems[i], g_VModels[TEAM_CT_INDEX][i], ct_v_count);
        ResolveAndPrecacheModel(TEAM_CT_INDEX, "p", g_WeaponStems[i], g_PModels[TEAM_CT_INDEX][i], ct_p_count);
        ResolveAndPrecacheModel(TEAM_CT_INDEX, "w", g_WeaponStems[i], g_WModels[TEAM_CT_INDEX][i], ct_w_count);

        // -------------------------------------------------------------
        // T Models: Check cs2_loadout/t, custom_skins/t, csgo_skins/t
        // -------------------------------------------------------------
        ResolveAndPrecacheModel(TEAM_T_INDEX, "v", g_WeaponStems[i], g_VModels[TEAM_T_INDEX][i], t_v_count);
        ResolveAndPrecacheModel(TEAM_T_INDEX, "p", g_WeaponStems[i], g_PModels[TEAM_T_INDEX][i], t_p_count);
        ResolveAndPrecacheModel(TEAM_T_INDEX, "w", g_WeaponStems[i], g_WModels[TEAM_T_INDEX][i], t_w_count);
    }

    server_print("[CS2 Faction Loadout] Precached Models -> CT: [v:%d, p:%d, w:%d] | T: [v:%d, p:%d, w:%d]",
        ct_v_count, ct_p_count, ct_w_count, t_v_count, t_p_count, t_w_count);
}

stock ResolveAndPrecacheModel(team_idx, const prefix[], const stem[], output[128], &count)
{
    new team_dir[4];
    if (team_idx == TEAM_CT_INDEX)
    {
        copy(team_dir, charsmax(team_dir), "ct");
    }
    else
    {
        copy(team_dir, charsmax(team_dir), "t");
    }
    new candidate[128];

    // Priority 1: models/cs2_loadout/<faction>/<prefix>_<stem>.mdl
    formatex(candidate, charsmax(candidate), "models/cs2_loadout/%s/%s_%s.mdl", team_dir, prefix, stem);
    if (file_exists(candidate, true))
    {
        copy(output, charsmax(output), candidate);
        precache_model(output);
        count++;
        return;
    }

    // Priority 2: models/custom_skins/<faction>/<prefix>_<stem>.mdl
    formatex(candidate, charsmax(candidate), "models/custom_skins/%s/%s_%s.mdl", team_dir, prefix, stem);
    if (file_exists(candidate, true))
    {
        copy(output, charsmax(output), candidate);
        precache_model(output);
        count++;
        return;
    }

    // Priority 3: models/csgo_skins/<faction>/<prefix>_<stem>.mdl
    formatex(candidate, charsmax(candidate), "models/csgo_skins/%s/%s_%s.mdl", team_dir, prefix, stem);
    if (file_exists(candidate, true))
    {
        copy(output, charsmax(output), candidate);
        precache_model(output);
        count++;
        return;
    }

    // Fallback: None specified, will use standard game default
    output[0] = '^0';
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    pCvar_Enable   = register_cvar("amx_cs2_faction_loadout", "1");
    pCvar_DropSync = register_cvar("amx_cs2_faction_drop", "1");

    // Hook weapon deployment for all weapons
    for (new i = 1; i <= CSW_LAST_WEAPON; i++)
    {
        if (g_WeaponEntityNames[i][0])
        {
            RegisterHam(Ham_Item_Deploy, g_WeaponEntityNames[i], "OnItemDeploy_Post", 1);
        }
    }

    // Intercept world model assignment when a weapon is dropped
    register_forward(FM_SetModel, "OnSetModel_Post", 1);

    server_print("[CS2 Faction Loadout] Initialized successfully. Dual-faction dropper active.");
}

// ==============================================================================
// ITEM DEPLOY (v_ and p_ model assignment per player team)
// ==============================================================================

public OnItemDeploy_Post(weapon_ent)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(weapon_ent))
        return HAM_IGNORED;

    new id = get_pdata_cbase(weapon_ent, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return HAM_IGNORED;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;

    new weapon_id = cs_get_weapon_id(weapon_ent);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
    {
        weapon_id = cs_get_user_weapon(id);
    }

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return HAM_IGNORED;

    // Apply viewmodel (v_*.mdl) if custom faction model exists
    if (g_VModels[team_index][weapon_id][0])
    {
        set_pev(id, pev_viewmodel2, g_VModels[team_index][weapon_id]);
    }

    // Apply playermodel (p_*.mdl) if custom faction model exists
    if (g_PModels[team_index][weapon_id][0])
    {
        set_pev(id, pev_weaponmodel2, g_PModels[team_index][weapon_id]);
    }

    return HAM_IGNORED;
}

// ==============================================================================
// WEAPON DROP (FM_SetModel - w_*.mdl assignment per dropper team)
// ==============================================================================

static bool:g_bSettingDropModel = false;

public OnSetModel_Post(ent, const model[])
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_DropSync) || !pev_valid(ent))
        return FMRES_IGNORED;

    if (g_bSettingDropModel)
        return FMRES_IGNORED;

    // Ensure model is a dropped world model (w_*.mdl)
    if (containi(model, "w_") == -1)
        return FMRES_IGNORED;

    // Identify owner / dropper entity
    new id = pev(ent, pev_owner);
    if (id < 1 || id > MaxClients || !is_user_connected(id))
        return FMRES_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return FMRES_IGNORED;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;

    // Match dropped model against known weapon stems
    for (new w = 1; w <= CSW_LAST_WEAPON; w++)
    {
        if (!g_WeaponStems[w][0])
            continue;

        // Check if model contains weapon stem (e.g. w_ak47.mdl contains ak47, or w_backpack is c4)
        if (containi(model, g_WeaponStems[w]) != -1 || (w == CSW_C4 && containi(model, "backpack") != -1))
        {
            // If faction-specific world model exists, assign it!
            if (g_WModels[team_index][w][0])
            {
                if (!equal(model, g_WModels[team_index][w]))
                {
                    g_bSettingDropModel = true;
                    engfunc(EngFunc_SetModel, ent, g_WModels[team_index][w]);
                    g_bSettingDropModel = false;
                    return FMRES_SUPERCEDE;
                }
            }
            break;
        }
    }

    // Fallback: If no faction-specific model was found, default model is kept intact
    return FMRES_IGNORED;
}
