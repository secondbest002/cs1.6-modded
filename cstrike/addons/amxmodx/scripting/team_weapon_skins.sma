#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "Team Weapon Skins"
#define VERSION "1.0"
#define AUTHOR  "Antigravity"

#define TEAM_CT_INDEX 0
#define TEAM_T_INDEX  1

new const g_WeaponModelNames[CSW_LAST_WEAPON + 1][] = {
    "",                  // 0 CSW_NONE
    "v_p228.mdl",        // 1 CSW_P228
    "",                  // 2 CSW_GLOCK (unused)
    "v_scout.mdl",       // 3 CSW_SCOUT
    "v_hegrenade.mdl",   // 4 CSW_HEGRENADE
    "v_xm1014.mdl",      // 5 CSW_XM1014
    "v_c4.mdl",          // 6 CSW_C4
    "v_mac10.mdl",       // 7 CSW_MAC10
    "v_aug.mdl",         // 8 CSW_AUG
    "v_smokegrenade.mdl", // 9 CSW_SMOKEGRENADE
    "v_elite.mdl",       // 10 CSW_ELITE
    "v_fiveseven.mdl",   // 11 CSW_FIVESEVEN
    "v_ump45.mdl",       // 12 CSW_UMP45
    "v_sg550.mdl",       // 13 CSW_SG550
    "v_galil.mdl",       // 14 CSW_GALIL
    "v_famas.mdl",       // 15 CSW_FAMAS
    "v_usp.mdl",         // 16 CSW_USP
    "v_glock18.mdl",     // 17 CSW_GLOCK18
    "v_awp.mdl",         // 18 CSW_AWP
    "v_mp5.mdl",         // 19 CSW_MP5NAVY
    "v_m249.mdl",        // 20 CSW_M249
    "v_m3.mdl",          // 21 CSW_M3
    "v_m4a1.mdl",        // 22 CSW_M4A1
    "v_tmp.mdl",         // 23 CSW_TMP
    "v_g3sg1.mdl",       // 24 CSW_G3SG1
    "v_flashbang.mdl",   // 25 CSW_FLASHBANG
    "v_deagle.mdl",      // 26 CSW_DEAGLE
    "v_sg552.mdl",       // 27 CSW_SG552
    "v_ak47.mdl",        // 28 CSW_AK47
    "v_knife.mdl",       // 29 CSW_KNIFE
    "v_p90.mdl"          // 30 CSW_P90
};

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

// [0 = CT, 1 = T][weapon_id][filepath]
new g_WeaponModels[2][CSW_LAST_WEAPON + 1][128];

// Dynamic knife model scanner (checks specific named knives like v_knife_m9.mdl, v_knife_butterfly.mdl)
new const g_KnifeSearchPrefixes[][] = {
    "v_knife_m9",
    "v_knife_butterfly",
    "v_knife_karambit",
    "v_knife_bayonet",
    "v_knife_bowie",
    "v_knife_falchion",
    "v_knife_daggers",
    "v_knife_stiletto",
    "v_knife_talon",
    "v_knife_ursus",
    "v_knife_skeleton",
    "v_knife_flip",
    "v_knife_gut",
    "v_knife_huntsman",
    "v_knife_navaja",
    "v_knife_nomad",
    "v_knife_paracord",
    "v_knife_survival",
    "v_knife_bknife"
};

stock bool:FindCustomKnifeModel(const folder[], output[], maxlen)
{
    new candidate[128];

    // 1. Prioritize specific named knives (e.g. models/custom_skins/ct/v_knife_m9.mdl)
    for (new k = 0; k < sizeof(g_KnifeSearchPrefixes); k++)
    {
        formatex(candidate, charsmax(candidate), "%s/%s.mdl", folder, g_KnifeSearchPrefixes[k]);
        if (file_exists(candidate, true))
        {
            copy(output, maxlen, candidate);
            return true;
        }
    }

    // 2. Check for generic v_knife.mdl in custom folder
    formatex(candidate, charsmax(candidate), "%s/v_knife.mdl", folder);
    if (file_exists(candidate, true))
    {
        copy(output, maxlen, candidate);
        return true;
    }

    return false;
}

public plugin_precache()
{
    new ct_count = 0, t_count = 0;

    for (new i = 1; i <= CSW_LAST_WEAPON; i++)
    {
        if (!g_WeaponModelNames[i][0])
            continue;

        // CT Model check
        new ct_custom[128], ct_fallback[128];
        formatex(ct_fallback, charsmax(ct_fallback), "models/csgo_skins/ct/%s", g_WeaponModelNames[i]);

        if (i == CSW_KNIFE)
        {
            if (FindCustomKnifeModel("models/custom_skins/ct", ct_custom, charsmax(ct_custom)))
            {
                copy(g_WeaponModels[TEAM_CT_INDEX][i], charsmax(g_WeaponModels[][]), ct_custom);
            }
            else if (file_exists(ct_fallback) || file_exists(ct_fallback, true))
            {
                copy(g_WeaponModels[TEAM_CT_INDEX][i], charsmax(g_WeaponModels[][]), ct_fallback);
            }
        }
        else
        {
            formatex(ct_custom, charsmax(ct_custom), "models/custom_skins/ct/%s", g_WeaponModelNames[i]);
            if (file_exists(ct_custom) || file_exists(ct_custom, true))
            {
                copy(g_WeaponModels[TEAM_CT_INDEX][i], charsmax(g_WeaponModels[][]), ct_custom);
            }
            else if (file_exists(ct_fallback) || file_exists(ct_fallback, true))
            {
                copy(g_WeaponModels[TEAM_CT_INDEX][i], charsmax(g_WeaponModels[][]), ct_fallback);
            }
        }

        if (g_WeaponModels[TEAM_CT_INDEX][i][0])
        {
            precache_model(g_WeaponModels[TEAM_CT_INDEX][i]);
            ct_count++;
        }

        // T Model check
        new t_custom[128], t_fallback[128];
        formatex(t_fallback, charsmax(t_fallback), "models/csgo_skins/t/%s", g_WeaponModelNames[i]);

        if (i == CSW_KNIFE)
        {
            if (FindCustomKnifeModel("models/custom_skins/t", t_custom, charsmax(t_custom)))
            {
                copy(g_WeaponModels[TEAM_T_INDEX][i], charsmax(g_WeaponModels[][]), t_custom);
            }
            else if (file_exists(t_fallback) || file_exists(t_fallback, true))
            {
                copy(g_WeaponModels[TEAM_T_INDEX][i], charsmax(g_WeaponModels[][]), t_fallback);
            }
        }
        else
        {
            formatex(t_custom, charsmax(t_custom), "models/custom_skins/t/%s", g_WeaponModelNames[i]);
            if (file_exists(t_custom) || file_exists(t_custom, true))
            {
                copy(g_WeaponModels[TEAM_T_INDEX][i], charsmax(g_WeaponModels[][]), t_custom);
            }
            else if (file_exists(t_fallback) || file_exists(t_fallback, true))
            {
                copy(g_WeaponModels[TEAM_T_INDEX][i], charsmax(g_WeaponModels[][]), t_fallback);
            }
        }

        if (g_WeaponModels[TEAM_T_INDEX][i][0])
        {
            precache_model(g_WeaponModels[TEAM_T_INDEX][i]);
            t_count++;
        }
    }

    server_print("[Team Skins] Precached %d CT models and %d T models.", ct_count, t_count);
    server_print("[Team Skins] Knife CT: %s | Knife T: %s", g_WeaponModels[TEAM_CT_INDEX][CSW_KNIFE], g_WeaponModels[TEAM_T_INDEX][CSW_KNIFE]);
}

#define TASK_RESET_HUD   1000
#define TASK_TEAM_CHANGE 2000

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_event("ResetHUD", "Event_ResetHUD", "b");
    register_event("TeamInfo", "Event_TeamInfo", "a", "2=TERRORIST", "2=CT");

    for (new i = 1; i <= CSW_LAST_WEAPON; i++)
    {
        if (g_WeaponEntityNames[i][0])
        {
            RegisterHam(Ham_Item_Deploy, g_WeaponEntityNames[i], "OnItemDeployPost", 1);
        }
    }

    server_print("[Team Skins] Plugin loaded successfully.");
}

public OnItemDeployPost(weapon_ent)
{
    if (!pev_valid(weapon_ent))
        return HAM_IGNORED;

    new id = get_pdata_cbase(weapon_ent, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id) || is_user_bot(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(weapon_ent);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
    {
        weapon_id = cs_get_user_weapon(id);
    }

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return HAM_IGNORED;

    ApplyViewModel(id, weapon_id, true);
    return HAM_IGNORED;
}

public Event_CurWeapon(id)
{
    if (id < 1 || id > MaxClients || !is_user_alive(id) || is_user_bot(id))
        return;

    if (read_data(1) != 1)
        return;

    new weapon_id = read_data(2);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, false);
}

public Event_ResetHUD(id)
{
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && !is_user_bot(id))
    {
        remove_task(TASK_RESET_HUD + id);
        set_task(0.1, "Task_ResetHUD", TASK_RESET_HUD + id);
    }
}

public Task_ResetHUD(taskid)
{
    new id = taskid - TASK_RESET_HUD;
    if (id < 1 || id > MaxClients || !is_user_alive(id) || is_user_bot(id))
        return;

    new weapon_id = cs_get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, true);
}

public Event_TeamInfo()
{
    new id = read_data(1);
    if (id >= 1 && id <= MaxClients && is_user_alive(id) && !is_user_bot(id))
    {
        remove_task(TASK_TEAM_CHANGE + id);
        set_task(0.1, "Task_TeamChange", TASK_TEAM_CHANGE + id);
    }
}

public Task_TeamChange(taskid)
{
    new id = taskid - TASK_TEAM_CHANGE;
    if (id < 1 || id > MaxClients || !is_user_alive(id) || is_user_bot(id))
        return;

    new weapon_id = cs_get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, true);
}

stock ApplyViewModel(id, weapon_id, bool:force)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    if (!g_WeaponModels[team_index][weapon_id][0])
        return;

    // Delegate CT M4A1 to M4 Loadout plugin (M4A4 vs M4A1-S)
    if (team == CS_TEAM_CT && weapon_id == CSW_M4A1)
        return;

    if (!force)
    {
        new current_model[128];
        pev(id, pev_viewmodel2, current_model, charsmax(current_model));
        if (equal(current_model, g_WeaponModels[team_index][weapon_id]))
            return;
    }

    set_pev(id, pev_viewmodel2, g_WeaponModels[team_index][weapon_id]);
}
