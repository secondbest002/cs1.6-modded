/*
 * ==============================================================================
 * CS2 SKIN INVENTORY & LOADOUT SYSTEM
 * ==============================================================================
 * Author: Antigravity
 * Version: 2.0.0
 *
 * Features:
 *  - Full CS2 Loadout UI with distinct Counter-Terrorist (CT) and Terrorist (T)
 *    equipment trees.
 *  - Complete M4A4 vs M4A1-S mechanics (silencer detachment locking, auto-silence,
 *    dropped world model w_m4a4.mdl, player model p_m4a4.mdl).
 *  - 100% Seamless interoperation with csgo_knife_sound_manager.amxx (detects
 *    active knife model dynamically for inspect, deploy, stab sounds).
 *  - Persistent loadout saves per player via nvault (cs2_loadout).
 *  - Quick chat commands: /loadout, /skin, /inv, /knife, /gloves, /m4.
 *  - Config-driven catalog: cstrike/addons/amxmodx/configs/skin_inventory.ini
 * ==============================================================================
 */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <nvault>
#include <xs>

#define PLUGIN  "CS2 Skin Inventory & Loadout"
#define VERSION "2.0.0"
#define AUTHOR  "Antigravity"

#define TEAM_CT_INDEX 0
#define TEAM_T_INDEX  1

#define MAX_SKINS_PER_WEAPON 16
#define TOTAL_SLOTS (2 * (CSW_LAST_WEAPON + 1))
#define GET_SLOT(%1,%2) (%1 * (CSW_LAST_WEAPON + 1) + %2)

// Weapon categories for CS2 Loadout tree
enum _:WeaponCategory {
    CAT_KNIFE = 0,
    CAT_PISTOLS,
    CAT_MIDTIER,
    CAT_RIFLES
};

// Skin struct data (Pawn max 3 dimensions)
new g_SkinCount[TOTAL_SLOTS];
new g_SkinName[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][32];
new g_SkinVModel[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][128];
new g_SkinPModel[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][128];
new g_SkinWModel[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][128];
new bool:g_SkinIsM4A4[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON];
new g_SkinFireSound1[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][128];
new g_SkinFireSound2[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON][128];
new g_SkinFireSoundCount[TOTAL_SLOTS][MAX_SKINS_PER_WEAPON];
new g_iWeaponEventId[CSW_LAST_WEAPON + 1];

// Player selected skin index [id][slot]
new g_iPlayerSkin[33][TOTAL_SLOTS];

// Active loadout defaults from active_loadout.ini [slot]
new g_ActiveLoadoutSkin[TOTAL_SLOTS];

// CVars
new pCvar_Enable;
new pCvar_AutoSilenceM4A1;
new pCvar_BlockSilencerM4A4;
new pCvar_Notify;
new pCvar_BotM4Mode;

// Bot M4 Configuration & Persistence
new g_iBotM4Override[33];
new Trie:g_tBotM4Preference = Invalid_Trie;

// Vault handle
new g_hVault = INVALID_HANDLE;

// Standard model names for fallback discovery
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

// Friendly weapon display names
new const g_WeaponDisplayNames[CSW_LAST_WEAPON + 1][] = {
    "",
    "P228 / Tec-9 Slot",
    "",
    "SSG 08 (Scout)",
    "HE Grenade",
    "XM1014 / MAG-7 Slot",
    "C4 Explosive",
    "MAC-10 / CZ75-Auto Slot",
    "AUG",
    "Smoke Grenade",
    "Dual Berettas",
    "Five-SeveN",
    "UMP-45",
    "SG 550 Sniper",
    "Galil AR",
    "FAMAS",
    "USP-S",
    "Glock-18",
    "AWP",
    "MP5-SD / MP7 Slot",
    "M249 / Negev Slot",
    "M3 / Sawed-Off Slot",
    "M4 Slot (M4A4 / M4A1-S)",
    "TMP / CZ75-Auto Slot",
    "G3SG1 Auto-Sniper",
    "Flashbang",
    "Desert Eagle",
    "SG 552",
    "AK-47",
    "Knife Slot",
    "P90 / PP-Bizon Slot"
};

new const g_WeaponEventNames[CSW_LAST_WEAPON + 1][] = {
    "",
    "events/p228.sc",          // 1 CSW_P228
    "",                        // 2 CSW_GLOCK (unused)
    "events/scout.sc",         // 3 CSW_SCOUT
    "",                        // 4 CSW_HEGRENADE
    "events/xm1014.sc",        // 5 CSW_XM1014
    "",                        // 6 CSW_C4
    "events/mac10.sc",         // 7 CSW_MAC10
    "events/aug.sc",           // 8 CSW_AUG
    "",                        // 9 CSW_SMOKEGRENADE
    "events/elite_left.sc",    // 10 CSW_ELITE
    "events/fiveseven.sc",     // 11 CSW_FIVESEVEN
    "events/ump45.sc",         // 12 CSW_UMP45
    "events/sg550.sc",         // 13 CSW_SG550
    "events/galil.sc",         // 14 CSW_GALIL
    "events/famas.sc",         // 15 CSW_FAMAS
    "events/usp.sc",           // 16 CSW_USP
    "events/glock18.sc",       // 17 CSW_GLOCK18
    "events/awp.sc",           // 18 CSW_AWP
    "events/mp5n.sc",          // 19 CSW_MP5NAVY
    "events/m249.sc",          // 20 CSW_M249
    "events/m3.sc",            // 21 CSW_M3
    "events/m4a1.sc",          // 22 CSW_M4A1
    "events/tmp.sc",           // 23 CSW_TMP
    "events/g3sg1.sc",         // 24 CSW_G3SG1
    "",                        // 25 CSW_FLASHBANG
    "events/deagle.sc",        // 26 CSW_DEAGLE
    "events/sg552.sc",         // 27 CSW_SG552
    "events/ak47.sc",          // 28 CSW_AK47
    "",                        // 29 CSW_KNIFE
    "events/p90.sc"            // 30 CSW_P90
};

// Task IDs
#define TASK_RESET_HUD   1000
#define TASK_TEAM_CHANGE 2000

// ==============================================================================
// PLUGIN PRECACHE & CONFIG INGESTION
// ==============================================================================

stock bool:ModelFileExists(const path[])
{
    if (!path[0])
        return false;

    if (file_exists(path, true) || file_exists(path, false))
        return true;

    new cstrike_path[160];
    formatex(cstrike_path, charsmax(cstrike_path), "cstrike/%s", path);
    if (file_exists(cstrike_path, false))
        return true;

    return false;
}

public plugin_precache()
{
    // 1. Initialize lists to 0
    for (new s = 0; s < TOTAL_SLOTS; s++)
    {
        g_SkinCount[s] = 0;
    }

    // 2. Parse configs/skin_inventory.ini
    new config_file[128];
    get_configsdir(config_file, charsmax(config_file));
    format(config_file, charsmax(config_file), "%s/skin_inventory.ini", config_file);

    if (file_exists(config_file))
    {
        LoadCatalogConfig(config_file);
    }
    else
    {
        server_print("[CS2 Loadout] Warning: %s not found. Using fallback discovery.", config_file);
    }

    // 3. Fallback discovery for any weapon without configured skins
    LoadFallbackSkins();

    // 3.5. Parse configs/active_loadout.ini for default equipped skins
    new active_config[128];
    get_configsdir(active_config, charsmax(active_config));
    format(active_config, charsmax(active_config), "%s/active_loadout.ini", active_config);

    if (file_exists(active_config))
    {
        LoadActiveLoadoutConfig(active_config);
    }
    else
    {
        for (new s = 0; s < TOTAL_SLOTS; s++)
        {
            g_ActiveLoadoutSkin[s] = 0;
        }
    }

    // 4. Precache all registered models
    new precached_v = 0, precached_p = 0, precached_w = 0, precached_snd = 0;
    for (new slot = 0; slot < TOTAL_SLOTS; slot++)
    {
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (g_SkinVModel[slot][s][0])
            {
                if (ModelFileExists(g_SkinVModel[slot][s]))
                {
                    new m_idx = precache_model(g_SkinVModel[slot][s]);
                    if (m_idx > 0)
                    {
                        precached_v++;
                    }
                    else
                    {
                        g_SkinVModel[slot][s][0] = '^0';
                    }
                }
                else
                {
                    g_SkinVModel[slot][s][0] = '^0';
                }
            }

            if (g_SkinPModel[slot][s][0])
            {
                if (ModelFileExists(g_SkinPModel[slot][s]))
                {
                    new m_idx = precache_model(g_SkinPModel[slot][s]);
                    if (m_idx > 0)
                    {
                        precached_p++;
                    }
                    else
                    {
                        g_SkinPModel[slot][s][0] = '^0';
                    }
                }
                else
                {
                    g_SkinPModel[slot][s][0] = '^0';
                }
            }

            if (g_SkinWModel[slot][s][0])
            {
                if (ModelFileExists(g_SkinWModel[slot][s]))
                {
                    new m_idx = precache_model(g_SkinWModel[slot][s]);
                    if (m_idx > 0)
                    {
                        precached_w++;
                    }
                    else
                    {
                        g_SkinWModel[slot][s][0] = '^0';
                    }
                }
                else
                {
                    g_SkinWModel[slot][s][0] = '^0';
                }
            }

            // Precache custom gunfire sounds
            if (g_SkinFireSoundCount[slot][s] > 0)
            {
                if (g_SkinFireSound1[slot][s][0])
                {
                    new snd_check[140];
                    formatex(snd_check, charsmax(snd_check), "sound/%s", g_SkinFireSound1[slot][s]);
                    if (file_exists(snd_check) || file_exists(snd_check, true) || file_exists(g_SkinFireSound1[slot][s]) || file_exists(g_SkinFireSound1[slot][s], true))
                    {
                        precache_sound(g_SkinFireSound1[slot][s]);
                        precached_snd++;
                    }
                }
                if (g_SkinFireSound2[slot][s][0])
                {
                    new snd_check[140];
                    formatex(snd_check, charsmax(snd_check), "sound/%s", g_SkinFireSound2[slot][s]);
                    if (file_exists(snd_check) || file_exists(snd_check, true) || file_exists(g_SkinFireSound2[slot][s]) || file_exists(g_SkinFireSound2[slot][s], true))
                    {
                        precache_sound(g_SkinFireSound2[slot][s]);
                        precached_snd++;
                    }
                }
            }
        }
    }

    // 5. Precache weapon fire events
    register_forward(FM_PrecacheEvent, "OnPrecacheEvent_Post", 1);
    for (new w = 1; w <= CSW_LAST_WEAPON; w++)
    {
        if (g_WeaponEventNames[w][0] && ModelFileExists(g_WeaponEventNames[w]))
        {
            g_iWeaponEventId[w] = precache_event(1, g_WeaponEventNames[w]);
        }
    }

    server_print("[CS2 Loadout] Catalog loaded: %d viewmodels, %d playermodels, %d worldmodels, %d gunfire sounds precached.",
        precached_v, precached_p, precached_w, precached_snd);
}

public OnPrecacheEvent_Post(type, const name[])
{
    for (new w = 1; w <= CSW_LAST_WEAPON; w++)
    {
        if (g_WeaponEventNames[w][0] && equal(g_WeaponEventNames[w], name))
        {
            g_iWeaponEventId[w] = get_orig_retval();
            break;
        }
    }
}

stock LoadCatalogConfig(const filepath[])
{
    new fp = fopen(filepath, "rt");
    if (!fp) return;

    new line[256];
    new current_team = -1; // -1 = both, 0 = CT, 1 = T
    new current_weapon_id = CSW_NONE;

    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#' || (line[0] == '/' && line[1] == '/'))
            continue;

        // Section header e.g. [CT_KNIVES], [T_KNIVES], [CT_M4A1], [T_AK47]
        if (line[0] == '[' && line[strlen(line) - 1] == ']')
        {
            new section[64];
            copy(section, strlen(line) - 2, line[1]);
            trim(section);

            current_team = -1;
            if (containi(section, "CT_") == 0)
            {
                current_team = TEAM_CT_INDEX;
            }
            else if (containi(section, "T_") == 0)
            {
                current_team = TEAM_T_INDEX;
            }

            current_weapon_id = GetWeaponIdFromSection(section);
            continue;
        }

        if (current_weapon_id == CSW_NONE)
            continue;

        // Parse line: "Display Name" "v_model" ["p_model" "w_model" "snd1" "snd2"]
        new name[32], v_mdl[128], p_mdl[128], w_mdl[128], snd1[128], snd2[128];
        parse(line, name, charsmax(name), v_mdl, charsmax(v_mdl), p_mdl, charsmax(p_mdl), w_mdl, charsmax(w_mdl), snd1, charsmax(snd1), snd2, charsmax(snd2));

        if (!name[0] || !v_mdl[0])
            continue;

        if (!ModelFileExists(v_mdl))
            continue;

        // Add to team(s)
        if (current_team == -1)
        {
            AddSkinToCatalog(TEAM_CT_INDEX, current_weapon_id, name, v_mdl, p_mdl, w_mdl, snd1, snd2);
            AddSkinToCatalog(TEAM_T_INDEX, current_weapon_id, name, v_mdl, p_mdl, w_mdl, snd1, snd2);
        }
        else
        {
            AddSkinToCatalog(current_team, current_weapon_id, name, v_mdl, p_mdl, w_mdl, snd1, snd2);
        }
    }

    fclose(fp);
}

stock AddSkinToCatalog(team, weapon_id, const name[], const v_mdl[], const p_mdl[], const w_mdl[], const snd1[] = "", const snd2[] = "")
{
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    new slot = GET_SLOT(team, weapon_id);
    new idx = g_SkinCount[slot];
    if (idx >= MAX_SKINS_PER_WEAPON)
        return;

    // Check duplicate v_model
    for (new i = 0; i < idx; i++)
    {
        if (equal(g_SkinVModel[slot][i], v_mdl))
            return;
    }

    copy(g_SkinName[slot][idx], charsmax(g_SkinName[][]), name);
    copy(g_SkinVModel[slot][idx], charsmax(g_SkinVModel[][]), v_mdl);

    if (p_mdl[0] && ModelFileExists(p_mdl))
        copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), p_mdl);
    else
        g_SkinPModel[slot][idx][0] = '^0';

    if (w_mdl[0] && ModelFileExists(w_mdl))
        copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), w_mdl);
    else
        g_SkinWModel[slot][idx][0] = '^0';

    g_SkinFireSoundCount[slot][idx] = 0;
    g_SkinFireSound1[slot][idx][0] = '^0';
    g_SkinFireSound2[slot][idx][0] = '^0';

    new snd_check[140];
    if (snd1[0])
    {
        formatex(snd_check, charsmax(snd_check), "sound/%s", snd1);
        if (file_exists(snd1) || file_exists(snd1, true) || file_exists(snd_check) || file_exists(snd_check, true))
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), snd1);
            g_SkinFireSoundCount[slot][idx]++;
        }
    }

    if (snd2[0])
    {
        formatex(snd_check, charsmax(snd_check), "sound/%s", snd2);
        if (file_exists(snd2) || file_exists(snd2, true) || file_exists(snd_check) || file_exists(snd_check, true))
        {
            copy(g_SkinFireSound2[slot][idx], charsmax(g_SkinFireSound2[][]), snd2);
            g_SkinFireSoundCount[slot][idx]++;
        }
    }

    // Modern Weapon Auto-Detection & Fallback Population
    // 1. M4A4
    if (weapon_id == CSW_M4A1)
    {
        if (containi(name, "m4a4") != -1 || containi(v_mdl, "m4a4") != -1)
        {
            g_SkinIsM4A4[slot][idx] = true;

            // Auto-fill fallback p_ and w_ models for M4A4 if omitted
            if (!g_SkinPModel[slot][idx][0])
            {
                if (file_exists("models/pw_models/p_m4a4.mdl") || file_exists("models/pw_models/p_m4a4.mdl", true))
                    copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_m4a4.mdl");
                else if (file_exists("models/csgo_skins/ct/p_m4a4.mdl") || file_exists("models/csgo_skins/ct/p_m4a4.mdl", true))
                    copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/csgo_skins/ct/p_m4a4.mdl");
            }
            if (!g_SkinWModel[slot][idx][0])
            {
                if (file_exists("models/pw_models/w_m4a4.mdl") || file_exists("models/pw_models/w_m4a4.mdl", true))
                    copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_m4a4.mdl");
                else if (file_exists("models/csgo_skins/ct/w_m4a4.mdl") || file_exists("models/csgo_skins/ct/w_m4a4.mdl", true))
                    copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/csgo_skins/ct/w_m4a4.mdl");
            }
            if (g_SkinFireSoundCount[slot][idx] == 0)
            {
                if (file_exists("sound/weapons/csgo/m4a4/m4a4-1.wav") || file_exists("sound/weapons/csgo/m4a4/m4a4-1.wav", true))
                {
                    copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/m4a4/m4a4-1.wav");
                    g_SkinFireSoundCount[slot][idx]++;
                }
                if (file_exists("sound/weapons/csgo/m4a4/m4a4-2.wav") || file_exists("sound/weapons/csgo/m4a4/m4a4-2.wav", true))
                {
                    copy(g_SkinFireSound2[slot][idx], charsmax(g_SkinFireSound2[][]), "weapons/csgo/m4a4/m4a4-2.wav");
                    g_SkinFireSoundCount[slot][idx]++;
                }
            }
        }
        else
        {
            g_SkinIsM4A4[slot][idx] = false;
            if (!g_SkinPModel[slot][idx][0])
            {
                if (file_exists("models/pw_models/p_m4a1.mdl") || file_exists("models/pw_models/p_m4a1.mdl", true))
                    copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_m4a1.mdl");
                else if (file_exists("models/custom_skins/ct/p_m4a1.mdl") || file_exists("models/custom_skins/ct/p_m4a1.mdl", true))
                    copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/custom_skins/ct/p_m4a1.mdl");
                else if (file_exists("models/p_m4a1.mdl") || file_exists("models/p_m4a1.mdl", true))
                    copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/p_m4a1.mdl");
            }
            if (!g_SkinWModel[slot][idx][0])
            {
                if (file_exists("models/pw_models/w_m4a1.mdl") || file_exists("models/pw_models/w_m4a1.mdl", true))
                    copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_m4a1.mdl");
                else if (file_exists("models/w_m4a1.mdl") || file_exists("models/w_m4a1.mdl", true))
                    copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/w_m4a1.mdl");
            }
        }
    }
    // 2. Tec-9 (P228 Slot)
    else if (weapon_id == CSW_P228 && (containi(name, "tec") != -1 || containi(v_mdl, "tec9") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_tec9.mdl") || file_exists("models/pw_models/p_tec9.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_tec9.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_tec9.mdl") || file_exists("models/pw_models/w_tec9.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_tec9.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/tec9/tec9-1.wav");
            g_SkinFireSoundCount[slot][idx] = 1;
        }
    }
    // 3. CZ75-Auto (TMP or MAC-10 Slot)
    else if ((weapon_id == CSW_TMP || weapon_id == CSW_MAC10) && (containi(name, "cz") != -1 || containi(v_mdl, "cz75") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_cz75.mdl") || file_exists("models/pw_models/p_cz75.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_cz75.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_cz75.mdl") || file_exists("models/pw_models/w_cz75.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_cz75.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/cz75a/cz75-1.wav");
            copy(g_SkinFireSound2[slot][idx], charsmax(g_SkinFireSound2[][]), "weapons/csgo/cz75a/cz75-2.wav");
            g_SkinFireSoundCount[slot][idx] = 2;
        }
    }
    // 4. MP7 (MP5 Slot)
    else if (weapon_id == CSW_MP5NAVY && (containi(name, "mp7") != -1 || containi(v_mdl, "mp7") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_mp7.mdl") || file_exists("models/pw_models/p_mp7.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_mp7.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_mp7.mdl") || file_exists("models/pw_models/w_mp7.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_mp7.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/mp7/mp7-1.wav");
            copy(g_SkinFireSound2[slot][idx], charsmax(g_SkinFireSound2[][]), "weapons/csgo/mp7/mp7-2.wav");
            g_SkinFireSoundCount[slot][idx] = 2;
        }
    }
    // 5. PP-Bizon (P90 Slot)
    else if (weapon_id == CSW_P90 && (containi(name, "bizon") != -1 || containi(v_mdl, "bizon") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_bizon.mdl") || file_exists("models/pw_models/p_bizon.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_bizon.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_bizon.mdl") || file_exists("models/pw_models/w_bizon.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_bizon.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/bizon/bizon-1.wav");
            g_SkinFireSoundCount[slot][idx] = 1;
        }
    }
    // 6. MAG-7 (XM1014 Slot)
    else if (weapon_id == CSW_XM1014 && (containi(name, "mag") != -1 || containi(v_mdl, "mag7") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_mag7.mdl") || file_exists("models/pw_models/p_mag7.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_mag7.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_mag7.mdl") || file_exists("models/pw_models/w_mag7.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_mag7.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/mag7/mag7-1.wav");
            g_SkinFireSoundCount[slot][idx] = 1;
        }
    }
    // 7. Sawed-Off (M3 Slot)
    else if (weapon_id == CSW_M3 && (containi(name, "sawed") != -1 || containi(v_mdl, "sawedoff") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_sawedoff.mdl") || file_exists("models/pw_models/p_sawedoff.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_sawedoff.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_sawedoff.mdl") || file_exists("models/pw_models/w_sawedoff.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_sawedoff.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/sawedoff/sawedoff-1.wav");
            g_SkinFireSoundCount[slot][idx] = 1;
        }
    }
    // 8. Negev (M249 Slot)
    else if (weapon_id == CSW_M249 && (containi(name, "negev") != -1 || containi(v_mdl, "negev") != -1))
    {
        if (!g_SkinPModel[slot][idx][0] && (file_exists("models/pw_models/p_negev.mdl") || file_exists("models/pw_models/p_negev.mdl", true)))
            copy(g_SkinPModel[slot][idx], charsmax(g_SkinPModel[][]), "models/pw_models/p_negev.mdl");
        if (!g_SkinWModel[slot][idx][0] && (file_exists("models/pw_models/w_negev.mdl") || file_exists("models/pw_models/w_negev.mdl", true)))
            copy(g_SkinWModel[slot][idx], charsmax(g_SkinWModel[][]), "models/pw_models/w_negev.mdl");
        if (g_SkinFireSoundCount[slot][idx] == 0)
        {
            copy(g_SkinFireSound1[slot][idx], charsmax(g_SkinFireSound1[][]), "weapons/csgo/negev/negev-1.wav");
            copy(g_SkinFireSound2[slot][idx], charsmax(g_SkinFireSound2[][]), "weapons/csgo/negev/negev-2.wav");
            g_SkinFireSoundCount[slot][idx] = 2;
        }
    }

    g_SkinCount[slot]++;
}

stock GetWeaponIdFromSection(const section[])
{
    if (containi(section, "KNIFE") != -1 || containi(section, "KNIVES") != -1) return CSW_KNIFE;
    if (containi(section, "M4A1") != -1 || containi(section, "M4A4") != -1 || containi(section, "M4") != -1) return CSW_M4A1;
    if (containi(section, "AK47") != -1 || containi(section, "AK") != -1) return CSW_AK47;
    if (containi(section, "AWP") != -1) return CSW_AWP;
    if (containi(section, "SCOUT") != -1) return CSW_SCOUT;
    if (containi(section, "DEAGLE") != -1) return CSW_DEAGLE;
    if (containi(section, "USP") != -1) return CSW_USP;
    if (containi(section, "GLOCK18") != -1 || containi(section, "GLOCK") != -1) return CSW_GLOCK18;
    if (containi(section, "FAMAS") != -1) return CSW_FAMAS;
    if (containi(section, "GALIL") != -1) return CSW_GALIL;
    if (containi(section, "MP5NAVY") != -1 || containi(section, "MP5") != -1) return CSW_MP5NAVY;
    if (containi(section, "UMP45") != -1 || containi(section, "UMP") != -1) return CSW_UMP45;
    if (containi(section, "XM1014") != -1) return CSW_XM1014;
    if (containi(section, "M3") != -1) return CSW_M3;
    if (containi(section, "AUG") != -1) return CSW_AUG;
    if (containi(section, "SG552") != -1) return CSW_SG552;
    if (containi(section, "SG550") != -1) return CSW_SG550;
    if (containi(section, "G3SG1") != -1) return CSW_G3SG1;
    if (containi(section, "P90") != -1) return CSW_P90;
    if (containi(section, "P228") != -1) return CSW_P228;
    if (containi(section, "FIVESEVEN") != -1) return CSW_FIVESEVEN;
    if (containi(section, "ELITE") != -1) return CSW_ELITE;
    if (containi(section, "MAC10") != -1) return CSW_MAC10;
    if (containi(section, "TMP") != -1) return CSW_TMP;
    if (containi(section, "M249") != -1) return CSW_M249;

    // Direct Modern Section Names
    if (containi(section, "TEC9") != -1 || containi(section, "TEC") != -1) return CSW_P228;
    if (containi(section, "MP7") != -1) return CSW_MP5NAVY;
    if (containi(section, "BIZON") != -1) return CSW_P90;
    if (containi(section, "MAG7") != -1) return CSW_XM1014;
    if (containi(section, "SAWEDOFF") != -1 || containi(section, "SAWED") != -1) return CSW_M3;
    if (containi(section, "NEGEV") != -1) return CSW_M249;
    if (containi(section, "CZ75") != -1 || containi(section, "CZ") != -1)
    {
        if (containi(section, "CT_") == 0) return CSW_TMP;
        if (containi(section, "T_") == 0) return CSW_MAC10;
        return CSW_TMP;
    }

    return CSW_NONE;
}

stock LoadFallbackSkins()
{
    // Ensure every weapon has at least 1 default skin populated from models/custom_skins/ or models/csgo_skins/
    for (new w = 1; w <= CSW_LAST_WEAPON; w++)
    {
        if (!g_WeaponModelNames[w][0])
            continue;

        new ct_slot = GET_SLOT(TEAM_CT_INDEX, w);
        if (g_SkinCount[ct_slot] == 0)
        {
            new path_custom[128], path_csgo[128];
            formatex(path_custom, charsmax(path_custom), "models/custom_skins/ct/%s", g_WeaponModelNames[w]);
            formatex(path_csgo, charsmax(path_csgo), "models/csgo_skins/ct/%s", g_WeaponModelNames[w]);

            if (ModelFileExists(path_custom))
            {
                AddSkinToCatalog(TEAM_CT_INDEX, w, "Default Skin", path_custom, "", "");
            }
            else if (ModelFileExists(path_csgo))
            {
                AddSkinToCatalog(TEAM_CT_INDEX, w, "Default Skin", path_csgo, "", "");
            }
        }

        new t_slot = GET_SLOT(TEAM_T_INDEX, w);
        if (g_SkinCount[t_slot] == 0)
        {
            new path_custom[128], path_csgo[128];
            formatex(path_custom, charsmax(path_custom), "models/custom_skins/t/%s", g_WeaponModelNames[w]);
            formatex(path_csgo, charsmax(path_csgo), "models/csgo_skins/t/%s", g_WeaponModelNames[w]);

            if (ModelFileExists(path_custom))
            {
                AddSkinToCatalog(TEAM_T_INDEX, w, "Default Skin", path_custom, "", "");
            }
            else if (ModelFileExists(path_csgo))
            {
                AddSkinToCatalog(TEAM_T_INDEX, w, "Default Skin", path_csgo, "", "");
            }
        }
    }
}

// ==============================================================================
// ACTIVE LOADOUT INGESTION (DESKTOP COMPANION SYNC)
// ==============================================================================

stock LoadActiveLoadoutConfig(const filepath[])
{
    for (new s = 0; s < TOTAL_SLOTS; s++)
    {
        g_ActiveLoadoutSkin[s] = 0;
    }

    new fp = fopen(filepath, "rt");
    if (!fp)
    {
        server_print("[CS2 Loadout] Error: Could not open %s", filepath);
        return;
    }

    new line[256];
    new current_team = -1;

    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);

        if (!line[0] || line[0] == ';' || line[0] == '#' || (line[0] == '/' && line[1] == '/'))
            continue;

        // Section header [CT_ACTIVE], [T_ACTIVE], [CT], [T]
        if (line[0] == '[' && line[strlen(line) - 1] == ']')
        {
            new section[64];
            copy(section, strlen(line) - 2, line[1]);
            trim(section);

            current_team = -1;
            if (equali(section, "CT_ACTIVE") || equali(section, "CT") || containi(section, "CT_") == 0)
            {
                current_team = TEAM_CT_INDEX;
            }
            else if (equali(section, "T_ACTIVE") || equali(section, "T") || containi(section, "T_") == 0)
            {
                current_team = TEAM_T_INDEX;
            }
            continue;
        }

        if (current_team == -1)
            continue;

        // Parse KEY = "VALUE" or KEY "VALUE"
        new key[64], val[128];
        new eq_pos = contain(line, "=");
        if (eq_pos != -1)
        {
            copy(key, eq_pos, line);
            copy(val, charsmax(val), line[eq_pos + 1]);
        }
        else
        {
            parse(line, key, charsmax(key), val, charsmax(val));
        }

        trim(key);
        trim(val);

        // Strip enclosing quotes from val
        if (val[0] == '^"')
        {
            copy(val, charsmax(val), val[1]);
            new len = strlen(val);
            if (len > 0 && val[len - 1] == '^"')
            {
                val[len - 1] = '^0';
            }
            trim(val);
        }

        if (!key[0] || !val[0])
            continue;

        // Normalize slashes in val
        for (new i = 0; val[i]; i++)
        {
            if (val[i] == '\') val[i] = '/';
        }

        new weapon_id = GetWeaponIdFromSection(key);
        if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
            continue;

        new slot = GET_SLOT(current_team, weapon_id);
        if (g_SkinCount[slot] <= 0)
            continue;

        // Find skin matching by model path or display name
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            new model_norm[128];
            copy(model_norm, charsmax(model_norm), g_SkinVModel[slot][s]);
            for (new i = 0; model_norm[i]; i++)
            {
                if (model_norm[i] == '\') model_norm[i] = '/';
            }

            if (equali(val, model_norm) || containi(model_norm, val) != -1 ||
                containi(val, model_norm) != -1 || equali(val, g_SkinName[slot][s]) ||
                containi(g_SkinName[slot][s], val) != -1)
            {
                g_ActiveLoadoutSkin[slot] = s;
                server_print("[CS2 Loadout] Active loadout set: %s [%s] -> %s (index %d)",
                    (current_team == TEAM_CT_INDEX) ? "CT" : "T", key, g_SkinName[slot][s], s);
                break;
            }
        }
    }

    fclose(fp);
}

// ==============================================================================
// PLUGIN INITIALIZATION
// ==============================================================================

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable             = register_cvar("cs2_loadout_enable", "1");
    pCvar_AutoSilenceM4A1    = register_cvar("cs2_m4_auto_silence", "1");
    pCvar_BlockSilencerM4A4  = register_cvar("cs2_m4_block_silencer", "1");
    pCvar_Notify             = register_cvar("cs2_loadout_notify", "1");
    pCvar_BotM4Mode          = register_cvar("cs2_bot_m4_mode", "1");

    // Chat / Client Commands
    register_clcmd("say /loadout", "Cmd_OpenLoadout");
    register_clcmd("say_team /loadout", "Cmd_OpenLoadout");
    register_clcmd("say /skin", "Cmd_OpenLoadout");
    register_clcmd("say_team /skin", "Cmd_OpenLoadout");
    register_clcmd("say /inv", "Cmd_OpenLoadout");
    register_clcmd("say_team /inv", "Cmd_OpenLoadout");
    register_clcmd("say /knife", "Cmd_OpenKnifeMenu");
    register_clcmd("say_team /knife", "Cmd_OpenKnifeMenu");
    register_clcmd("say /gloves", "Cmd_OpenGloveInfo");
    register_clcmd("say_team /gloves", "Cmd_OpenGloveInfo");
    register_clcmd("say /m4", "Cmd_OpenM4Menu");
    register_clcmd("say_team /m4", "Cmd_OpenM4Menu");
    register_clcmd("say /m4a4", "Cmd_SelectM4A4Direct");
    register_clcmd("say_team /m4a4", "Cmd_SelectM4A4Direct");
    register_clcmd("say /m4a1", "Cmd_SelectM4A1Direct");
    register_clcmd("say_team /m4a1", "Cmd_SelectM4A1Direct");
    register_clcmd("say /resetloadout", "Cmd_ResetLoadout");
    register_clcmd("say_team /resetloadout", "Cmd_ResetLoadout");

    // Modern Weapons Direct Commands
    register_clcmd("say /tec9", "Cmd_SelectTec9Direct");
    register_clcmd("say_team /tec9", "Cmd_SelectTec9Direct");
    register_clcmd("tec9", "Cmd_SelectTec9Direct");
    register_clcmd("say /cz75", "Cmd_SelectCZ75Direct");
    register_clcmd("say_team /cz75", "Cmd_SelectCZ75Direct");
    register_clcmd("say /cz", "Cmd_SelectCZ75Direct");
    register_clcmd("say_team /cz", "Cmd_SelectCZ75Direct");
    register_clcmd("cz75", "Cmd_SelectCZ75Direct");
    register_clcmd("cz", "Cmd_SelectCZ75Direct");
    register_clcmd("say /mp7", "Cmd_SelectMP7Direct");
    register_clcmd("say_team /mp7", "Cmd_SelectMP7Direct");
    register_clcmd("mp7", "Cmd_SelectMP7Direct");
    register_clcmd("say /bizon", "Cmd_SelectBizonDirect");
    register_clcmd("say_team /bizon", "Cmd_SelectBizonDirect");
    register_clcmd("bizon", "Cmd_SelectBizonDirect");
    register_clcmd("say /mag7", "Cmd_SelectMAG7Direct");
    register_clcmd("say_team /mag7", "Cmd_SelectMAG7Direct");
    register_clcmd("mag7", "Cmd_SelectMAG7Direct");
    register_clcmd("say /sawedoff", "Cmd_SelectSawedOffDirect");
    register_clcmd("say_team /sawedoff", "Cmd_SelectSawedOffDirect");
    register_clcmd("sawedoff", "Cmd_SelectSawedOffDirect");
    register_clcmd("say /negev", "Cmd_SelectNegevDirect");
    register_clcmd("say_team /negev", "Cmd_SelectNegevDirect");
    register_clcmd("negev", "Cmd_SelectNegevDirect");

    // CT Bot M4 Management Commands
    register_clcmd("say /botm4", "Cmd_BotM4Command");
    register_clcmd("say_team /botm4", "Cmd_BotM4Command");
    register_clcmd("say /m4bot", "Cmd_BotM4Command");
    register_clcmd("say_team /m4bot", "Cmd_BotM4Command");
    register_clcmd("botm4", "Cmd_BotM4Command");
    register_clcmd("m4bot", "Cmd_BotM4Command");

    // Console commands
    register_clcmd("loadout", "Cmd_OpenLoadout");
    register_clcmd("skin", "Cmd_OpenLoadout");
    register_clcmd("inv", "Cmd_OpenLoadout");
    register_clcmd("knife", "Cmd_OpenKnifeMenu");
    register_clcmd("gloves", "Cmd_OpenGloveInfo");
    register_clcmd("m4", "Cmd_OpenM4Menu");
    register_clcmd("m4a4", "Cmd_SelectM4A4Direct");
    register_clcmd("m4a1", "Cmd_SelectM4A1Direct");
    register_clcmd("m4a1s", "Cmd_SelectM4A1Direct");
    register_clcmd("say /reloadloadout", "Cmd_ReloadActiveLoadout");
    register_concmd("cs2_reload_loadout", "Cmd_ReloadActiveLoadout", ADMIN_CFG, "Reload active_loadout.ini");

    // Events
    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");
    register_event("ResetHUD", "Event_ResetHUD", "b");
    register_event("TeamInfo", "Event_TeamInfo", "a", "2=TERRORIST", "2=CT");
    register_logevent("Event_RoundStart_Skin", 2, "1=Round_Start");

    // Player Spawn Hook
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);

    // Weapon Hooks
    for (new i = 1; i <= CSW_LAST_WEAPON; i++)
    {
        if (g_WeaponEntityNames[i][0])
        {
            RegisterHam(Ham_Item_Deploy, g_WeaponEntityNames[i], "OnItemDeploy_Post", 1);
            if (i != CSW_M4A1)
            {
                RegisterHam(Ham_Item_AddToPlayer, g_WeaponEntityNames[i], "OnItemAddToPlayer_Post", 1);
            }
        }
    }

    // Specific M4 hooks for M4A4 vs M4A1-S mechanics
    RegisterHam(Ham_Item_Deploy, "weapon_m4a1", "OnM4Deploy_Pre", 0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_m4a1", "OnM4AddToPlayer_Post", 1);
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_m4a1", "OnM4SecondaryAttack_Pre", 0);
    register_forward(FM_SetModel, "OnSetModel_Post", 1);

    // Gunfire sound suppression & custom playback
    register_forward(FM_UpdateClientData, "OnUpdateClientData_Post", 1);
    register_forward(FM_PlaybackEvent, "OnPlaybackEvent_Pre", 0);
    CacheGunshotDecals();

    // Initialize session-persistent Bot M4 preference Trie
    g_tBotM4Preference = TrieCreate();

    // Open persistent NVault storage
    g_hVault = nvault_open("cs2_loadout");
    if (g_hVault == INVALID_HANDLE)
    {
        server_print("[CS2 Loadout] Warning: Could not open cs2_loadout vault!");
    }

    server_print("[CS2 Loadout] System initialized successfully. Commands: /loadout, /knife, /m4, /gloves, /botm4");
}

public plugin_end()
{
    if (g_hVault != INVALID_HANDLE)
    {
        nvault_close(g_hVault);
        g_hVault = INVALID_HANDLE;
    }

    if (g_tBotM4Preference != Invalid_Trie)
    {
        TrieDestroy(g_tBotM4Preference);
        g_tBotM4Preference = Invalid_Trie;
    }
}

// ==============================================================================
// CLIENT CONNECTION & PERSISTENT NVAULT STORAGE
// ==============================================================================

public client_putinserver(id)
{
    g_iBotM4Override[id] = -1;

    for (new slot = 0; slot < TOTAL_SLOTS; slot++)
    {
        g_iPlayerSkin[id][slot] = g_ActiveLoadoutSkin[slot];
    }

    if (!is_user_bot(id))
    {
        LoadPlayerLoadout(id);
    }
    else
    {
        AssignBotModernLoadouts(id);
    }
}

public client_authorized(id)
{
    if (id >= 1 && id <= MaxClients && !is_user_bot(id) && is_user_connected(id))
    {
        LoadPlayerLoadout(id);
    }
}

public client_disconnected(id)
{
    g_iBotM4Override[id] = -1;
    remove_task(TASK_RESET_HUD + id);
    remove_task(TASK_TEAM_CHANGE + id);
}

stock GetPlayerKey(id, output[], maxlen)
{
    if (is_user_bot(id))
    {
        formatex(output, maxlen, "BOT_%d", id);
        return;
    }

    new auth[36];
    get_user_authid(id, auth, charsmax(auth));

    if (!auth[0] || equal(auth, "STEAM_ID_LAN") || equal(auth, "VALVE_ID_LAN") || equal(auth, "STEAM_ID_PENDING"))
    {
        get_user_name(id, output, maxlen);
    }
    else
    {
        copy(output, maxlen, auth);
    }

    // Sanitize key prefix for nvault (strip spaces, quotes, delimiters)
    for (new i = 0; output[i]; i++)
    {
        if (output[i] <= 32 || output[i] == 34 || output[i] == 39 || output[i] == ';' || output[i] == '#' || output[i] == ':')
            output[i] = '_';
    }
}

stock LoadPlayerLoadout(id)
{
    // 1. Initialize player skins from pre-game active loadout
    for (new slot = 0; slot < TOTAL_SLOTS; slot++)
    {
        if (g_ActiveLoadoutSkin[slot] >= 0 && g_ActiveLoadoutSkin[slot] < g_SkinCount[slot])
        {
            g_iPlayerSkin[id][slot] = g_ActiveLoadoutSkin[slot];
        }
        else
        {
            g_iPlayerSkin[id][slot] = 0;
        }
    }

    // 2. Load persistent choices from nvault if player is not a bot
    if (g_hVault != INVALID_HANDLE && !is_user_bot(id))
    {
        new key_prefix[64];
        GetPlayerKey(id, key_prefix, charsmax(key_prefix));

        for (new t = 0; t < 2; t++)
        {
            new team_str[4];
            copy(team_str, charsmax(team_str), (t == TEAM_CT_INDEX) ? "ct" : "t");

            for (new w = 1; w <= CSW_LAST_WEAPON; w++)
            {
                new slot = GET_SLOT(t, w);
                if (g_SkinCount[slot] <= 0)
                    continue;

                new vkey[96], saved_val[64];
                formatex(vkey, charsmax(vkey), "%s_%s_%d", key_prefix, team_str, w);
                if (nvault_get(g_hVault, vkey, saved_val, charsmax(saved_val)))
                {
                    for (new s = 0; s < g_SkinCount[slot]; s++)
                    {
                        if (equali(saved_val, g_SkinName[slot][s]))
                        {
                            g_iPlayerSkin[id][slot] = s;
                            break;
                        }
                    }
                }
            }
        }
    }
}

stock SavePlayerWeaponSkin(id, team, weapon_id)
{
    if (g_hVault == INVALID_HANDLE || is_user_bot(id))
        return;

    new key_prefix[64];
    GetPlayerKey(id, key_prefix, charsmax(key_prefix));

    new team_str[4];
    copy(team_str, charsmax(team_str), (team == TEAM_CT_INDEX) ? "ct" : "t");

    new slot = GET_SLOT(team, weapon_id);
    new s_idx = g_iPlayerSkin[id][slot];
    new vkey[96];
    formatex(vkey, charsmax(vkey), "%s_%s_%d", key_prefix, team_str, weapon_id);

    if (s_idx >= 0 && s_idx < g_SkinCount[slot])
    {
        nvault_set(g_hVault, vkey, g_SkinName[slot][s_idx]);
    }
}

// ==============================================================================
// VIEWMODEL & WEAPON DEPLOYMENT LOGIC
// ==============================================================================

public OnItemDeploy_Post(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(iWpn);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
    {
        weapon_id = cs_get_user_weapon(id);
    }

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return HAM_IGNORED;

    ApplyViewModel(id, weapon_id, iWpn, true);
    return HAM_IGNORED;
}

public Event_CurWeapon(id)
{
    if (!get_pcvar_num(pCvar_Enable) || id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    if (read_data(1) != 1)
        return;

    new weapon_id = read_data(2);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, 0, false);
}

public Event_ResetHUD(id)
{
    if (id >= 1 && id <= MaxClients && is_user_connected(id))
    {
        remove_task(TASK_RESET_HUD + id);
        set_task(0.1, "Task_ResetHUD", TASK_RESET_HUD + id);
    }
}

public OnPlayerSpawn_Post(id)
{
    if (id >= 1 && id <= MaxClients && is_user_alive(id))
    {
        remove_task(TASK_RESET_HUD + id);
        set_task(0.1, "Task_ResetHUD", TASK_RESET_HUD + id);
    }
    return HAM_IGNORED;
}

public Task_ResetHUD(taskid)
{
    new id = taskid - TASK_RESET_HUD;
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    if (is_user_bot(id))
    {
        AssignBotModernLoadouts(id);
        if (cs_get_user_team(id) == CS_TEAM_CT)
        {
            AssignBotM4Loadout(id);
        }
    }

    new weapon_id = cs_get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, 0, true);
}

public Event_RoundStart_Skin()
{
    set_task(0.2, "Task_RoundStartSyncBots");
}

public Task_RoundStartSyncBots()
{
    SyncAllCTBots();
}

public Event_TeamInfo()
{
    new id = read_data(1);
    if (id >= 1 && id <= MaxClients && is_user_alive(id))
    {
        remove_task(TASK_TEAM_CHANGE + id);
        set_task(0.1, "Task_TeamChange", TASK_TEAM_CHANGE + id);
    }
}

public Task_TeamChange(taskid)
{
    new id = taskid - TASK_TEAM_CHANGE;
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return;

    if (is_user_bot(id))
    {
        AssignBotModernLoadouts(id);
        if (cs_get_user_team(id) == CS_TEAM_CT)
        {
            AssignBotM4Loadout(id);
        }
    }

    new weapon_id = cs_get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return;

    ApplyViewModel(id, weapon_id, 0, true);
}

// ==============================================================================
// CT BOT M4 LOADOUT MANAGEMENT & ROLE INTEGRATION
// ==============================================================================

stock bool:CanAccessBotM4Menu(id)
{
    if (!is_dedicated_server())
        return true;
    if (is_user_admin(id) || access(id, ADMIN_CFG) || access(id, ADMIN_BAN))
        return true;
    return false;
}

stock GetBotRole(id)
{
    if (callfunc_begin("savage_get_bot_role", "bot_savage_ai.amxx") == 1)
    {
        callfunc_push_int(id);
        return callfunc_end();
    }
    return 0; // ROLE_NONE
}

stock GetCatalogM4Index(bool:bM4A4)
{
    new slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);
    for (new s = 0; s < g_SkinCount[slot]; s++)
    {
        if (bM4A4 && g_SkinIsM4A4[slot][s])
            return s;
        if (!bM4A4 && !g_SkinIsM4A4[slot][s])
            return s;
    }
    return 0;
}

stock AssignBotModernLoadouts(id)
{
    if (!is_user_connected(id) || !is_user_bot(id))
        return;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    for (new w = 1; w <= CSW_LAST_WEAPON; w++)
    {
        if (w == CSW_M4A1)
            continue; // Handled by AssignBotM4Loadout

        new slot = GET_SLOT(team_index, w);
        if (g_SkinCount[slot] > 0)
        {
            new active_idx = g_ActiveLoadoutSkin[slot];
            if (active_idx >= 0 && active_idx < g_SkinCount[slot])
            {
                g_iPlayerSkin[id][slot] = active_idx;
                if (is_user_alive(id) && g_WeaponEntityNames[w][0])
                {
                    new iWpn = fm_find_weapon_ent_by_owner(id, g_WeaponEntityNames[w]);
                    if (pev_valid(iWpn))
                    {
                        set_pev(iWpn, pev_iuser2, active_idx + 1);
                    }
                }
            }
        }
    }
}

stock AssignBotM4Loadout(id)
{
    if (!is_user_connected(id) || !is_user_bot(id) || !is_user_alive(id))
        return;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT)
        return;

    new slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);
    if (g_SkinCount[slot] <= 0)
        return;

    new szBotName[32];
    get_user_name(id, szBotName, charsmax(szBotName));

    new bool:chooseM4A4 = false;

    // 1. Check individual override first
    if (g_iBotM4Override[id] == 0) // Force M4A4
    {
        chooseM4A4 = true;
    }
    else if (g_iBotM4Override[id] == 1) // Force M4A1-S
    {
        chooseM4A4 = false;
    }
    else
    {
        new mode = get_pcvar_num(pCvar_BotM4Mode);
        switch (mode)
        {
            case 0: // Mirror Active Loadout
            {
                new active_idx = g_ActiveLoadoutSkin[slot];
                if (active_idx >= 0 && active_idx < g_SkinCount[slot])
                    chooseM4A4 = g_SkinIsM4A4[slot][active_idx];
                else
                    chooseM4A4 = false;
            }
            case 1: // Smart Role-Based (Default)
            {
                new role = GetBotRole(id);
                // ROLE_ENTRY (1), ROLE_LURKER (4) -> M4A4
                // ROLE_SUPPORT (3), ROLE_IGL (5), ROLE_AWPER (2) -> M4A1-S
                if (role == 1 || role == 4)
                {
                    chooseM4A4 = true;
                }
                else if (role == 3 || role == 5 || role == 2)
                {
                    chooseM4A4 = false;
                }
                else
                {
                    // Fallback if role is not yet determined: check session preference or alternate by id
                    new savedPref = 0;
                    if (g_tBotM4Preference != Invalid_Trie && TrieGetCell(g_tBotM4Preference, szBotName, savedPref))
                    {
                        chooseM4A4 = (savedPref == 1);
                    }
                    else
                    {
                        chooseM4A4 = (id % 2 == 1);
                    }
                }
            }
            case 2: // Mixed 50/50
            {
                new ct_bot_index = 0;
                for (new i = 1; i <= MaxClients; i++)
                {
                    if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == CS_TEAM_CT)
                    {
                        ct_bot_index++;
                        if (i == id)
                            break;
                    }
                }
                chooseM4A4 = (ct_bot_index % 2 == 1);
            }
            case 3: // Force All M4A4
            {
                chooseM4A4 = true;
            }
            case 4: // Force All M4A1-S
            {
                chooseM4A4 = false;
            }
            default:
            {
                chooseM4A4 = true;
            }
        }
    }

    g_iPlayerSkin[id][slot] = GetCatalogM4Index(chooseM4A4);
    if (g_tBotM4Preference != Invalid_Trie)
    {
        TrieSetCell(g_tBotM4Preference, szBotName, chooseM4A4 ? 1 : 2);
    }

    new iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
    if (pev_valid(iWpn))
    {
        new target_variant = chooseM4A4 ? 1 : 2;
        set_pev(iWpn, pev_iuser1, target_variant);
        if (target_variant == 1 && cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 0, 0);
        }
        else if (target_variant == 2 && get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
    }
}

stock SyncAllCTBots()
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i) && is_user_bot(i))
        {
            AssignBotModernLoadouts(i);
            new CsTeams:team = cs_get_user_team(i);
            if (team == CS_TEAM_CT)
            {
                AssignBotM4Loadout(i);
                if (is_user_alive(i) && cs_get_user_weapon(i) == CSW_M4A1)
                {
                    ApplyViewModel(i, CSW_M4A1, 0, true);
                }
            }
        }
    }
}

stock SetBotM4Mode(mode, issuer)
{
    set_pcvar_num(pCvar_BotM4Mode, mode);

    for (new i = 1; i <= MaxClients; i++)
    {
        g_iBotM4Override[i] = -1;
    }

    SyncAllCTBots();

    new const szModeNames[][] = {
        "Ikuti Active Loadout",
        "Role-Based (Smart)",
        "Campuran 50/50",
        "Semua M4A4",
        "Semua M4A1-S"
    };

    new issuer_name[32];
    if (issuer > 0 && is_user_connected(issuer))
        get_user_name(issuer, issuer_name, charsmax(issuer_name));
    else
        copy(issuer_name, charsmax(issuer_name), "Server Host");

    client_print_color(0, print_team_default,
        "^4[CS2 Loadout]^1 Mode M4 Bot CT disetel ke: ^3%s^1 oleh ^4%s^1.",
        szModeNames[mode], issuer_name);
}

public cs2_is_m4a4(id)
{
    if (id < 1 || id > MaxClients || !is_user_connected(id))
        return 0;

    new iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
    if (pev_valid(iWpn))
    {
        new iVar = pev(iWpn, pev_iuser1);
        if (iVar == 1) return 1;
        if (iVar == 2) return 0;
    }

    new slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);
    new s_idx = g_iPlayerSkin[id][slot];
    if (s_idx < 0 || s_idx >= g_SkinCount[slot])
        s_idx = 0;
    return g_SkinIsM4A4[slot][s_idx] ? 1 : 0;
}

stock ApplyViewModel(id, weapon_id, iWpn, bool:force)
{
    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, weapon_id);
    new s_idx = g_iPlayerSkin[id][slot];

    if (!pev_valid(iWpn) && weapon_id > CSW_NONE && weapon_id <= CSW_LAST_WEAPON && g_WeaponEntityNames[weapon_id][0])
    {
        iWpn = fm_find_weapon_ent_by_owner(id, g_WeaponEntityNames[weapon_id]);
    }

    if (weapon_id != CSW_M4A1 && pev_valid(iWpn))
    {
        new iSaved = pev(iWpn, pev_iuser2);
        if (iSaved > 0 && (iSaved - 1) < g_SkinCount[slot])
        {
            s_idx = iSaved - 1;
        }
        else
        {
            set_pev(iWpn, pev_iuser2, s_idx + 1);
        }
    }

    if (s_idx < 0 || s_idx >= g_SkinCount[slot])
    {
        s_idx = 0;
        g_iPlayerSkin[id][slot] = 0;
    }

    if (g_SkinCount[slot] == 0)
        return;

    if (!g_SkinVModel[slot][s_idx][0])
        return;

    // Viewmodel v_
    if (force)
    {
        set_pev(id, pev_viewmodel2, g_SkinVModel[slot][s_idx]);
    }
    else
    {
        new current_v[128];
        pev(id, pev_viewmodel2, current_v, charsmax(current_v));
        if (!equal(current_v, g_SkinVModel[slot][s_idx]))
        {
            set_pev(id, pev_viewmodel2, g_SkinVModel[slot][s_idx]);
        }
    }

    // Playermodel p_ (if defined)
    if (g_SkinPModel[slot][s_idx][0])
    {
        set_pev(id, pev_weaponmodel2, g_SkinPModel[slot][s_idx]);
    }

    // Special M4 mechanics (Both CT & T)
    if (weapon_id == CSW_M4A1 && (team == CS_TEAM_CT || team == CS_TEAM_T))
    {
        if (!pev_valid(iWpn))
        {
            iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
        }

        if (pev_valid(iWpn))
        {
            new iVariant = pev(iWpn, pev_iuser1);
            if (iVariant == 0)
            {
                iVariant = g_SkinIsM4A4[slot][s_idx] ? 1 : 2;
                set_pev(iWpn, pev_iuser1, iVariant);
            }

            if (iVariant == 1) // M4A4
            {
                new ct_slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);
                new target_idx = (team == CS_TEAM_CT && g_SkinIsM4A4[ct_slot][s_idx]) ? s_idx : GetCatalogM4Index(true);
                if (target_idx < 0 || target_idx >= g_SkinCount[ct_slot])
                    target_idx = 0;

                if (g_SkinVModel[ct_slot][target_idx][0])
                    set_pev(id, pev_viewmodel2, g_SkinVModel[ct_slot][target_idx]);
                if (g_SkinPModel[ct_slot][target_idx][0])
                    set_pev(id, pev_weaponmodel2, g_SkinPModel[ct_slot][target_idx]);

                if (cs_get_weapon_silen(iWpn))
                {
                    cs_set_weapon_silen(iWpn, 0, 0);
                }
            }
            else // M4A1-S (iVariant == 2)
            {
                new target_idx = (!g_SkinIsM4A4[slot][s_idx]) ? s_idx : GetCatalogM4Index(false);
                if (target_idx < 0 || target_idx >= g_SkinCount[slot])
                    target_idx = 0;

                if (g_SkinVModel[slot][target_idx][0])
                    set_pev(id, pev_viewmodel2, g_SkinVModel[slot][target_idx]);
                if (g_SkinPModel[slot][target_idx][0])
                    set_pev(id, pev_weaponmodel2, g_SkinPModel[slot][target_idx]);

                if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
                {
                    cs_set_weapon_silen(iWpn, 1, 0);
                }
            }
        }
    }
}

stock fm_find_weapon_ent_by_owner(id, const classname[])
{
    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)) > 0)
    {
        if (pev(ent, pev_owner) == id || get_pdata_cbase(ent, 41, 4) == id)
            return ent;
    }
    return 0;
}

// ==============================================================================
// M4A4 vs M4A1-S MECHANICS (Silencer Locking & World Drop)
// ==============================================================================

public OnM4Deploy_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return HAM_IGNORED;

    if (is_user_bot(id) && team == CS_TEAM_CT && pev(iWpn, pev_iuser1) == 0)
    {
        AssignBotM4Loadout(id);
    }

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, CSW_M4A1);
    new s_idx = g_iPlayerSkin[id][slot];
    if (s_idx < 0 || s_idx >= g_SkinCount[slot])
        s_idx = 0;

    new iVariant = pev(iWpn, pev_iuser1);
    if (iVariant == 0)
    {
        iVariant = g_SkinIsM4A4[slot][s_idx] ? 1 : 2;
        set_pev(iWpn, pev_iuser1, iVariant);
    }

    if (iVariant == 1) // M4A4
    {
        if (cs_get_weapon_silen(iWpn))
            cs_set_weapon_silen(iWpn, 0, 0);
    }
    else // M4A1-S
    {
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
            cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

public OnM4AddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn) || !is_user_alive(id))
        return HAM_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return HAM_IGNORED;

    if (is_user_bot(id) && team == CS_TEAM_CT && pev(iWpn, pev_iuser1) == 0)
    {
        AssignBotM4Loadout(id);
    }

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, CSW_M4A1);
    new s_idx = g_iPlayerSkin[id][slot];
    if (s_idx < 0 || s_idx >= g_SkinCount[slot])
        s_idx = 0;

    new iVariant = pev(iWpn, pev_iuser1);
    if (iVariant == 0)
    {
        iVariant = g_SkinIsM4A4[slot][s_idx] ? 1 : 2;
        set_pev(iWpn, pev_iuser1, iVariant);
    }

    if (iVariant == 1) // M4A4
    {
        if (cs_get_weapon_silen(iWpn))
            cs_set_weapon_silen(iWpn, 0, 0);
    }
    else // M4A1-S
    {
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
            cs_set_weapon_silen(iWpn, 1, 0);
    }

    return HAM_IGNORED;
}

public OnM4SecondaryAttack_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    new iVariant = pev(iWpn, pev_iuser1);
    if (iVariant == 1) // M4A4: block silencer completely
    {
        if (cs_get_weapon_silen(iWpn))
            cs_set_weapon_silen(iWpn, 0, 0);
        return HAM_SUPERCEDE;
    }

    // M4A1-S: CS2 permanent silencer lock (never allow detachment)
    if (get_pcvar_num(pCvar_BlockSilencerM4A4))
    {
        if (!cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
        return HAM_SUPERCEDE;
    }

    return HAM_IGNORED;
}

static bool:g_bSettingDropModel = false;

stock GetWeaponShootAnim(weapon_id)
{
    switch (weapon_id)
    {
        case CSW_P228:    return random_num(1, 3);
        case CSW_TMP:     return random_num(3, 5);
        case CSW_MAC10:   return random_num(3, 5);
        case CSW_MP5NAVY: return random_num(3, 5);
        case CSW_P90:     return random_num(3, 5);
        case CSW_XM1014:  return random_num(1, 2);
        case CSW_M3:      return random_num(1, 2);
        case CSW_M249:    return random_num(1, 2);
        case CSW_M4A1:    return random_num(8, 10);
    }
    return -1;
}

stock SendWeaponAnim(id, anim)
{
    set_pev(id, pev_weaponanim, anim);
    message_begin(MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, _, id);
    write_byte(anim);
    write_byte(pev(id, pev_body));
    message_end();
}

public OnSetModel_Post(ent, const model[])
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(ent))
        return FMRES_IGNORED;

    if (g_bSettingDropModel)
        return FMRES_IGNORED;

    new classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));

    // Only process dropped weaponbox entities
    if (!equal(classname, "weaponbox"))
        return FMRES_IGNORED;

    new id = pev(ent, pev_owner);
    new CsTeams:team = CS_TEAM_UNASSIGNED;
    if (id >= 1 && id <= MaxClients && is_user_connected(id))
    {
        team = cs_get_user_team(id);
    }

    new team_index = (team == CS_TEAM_T) ? TEAM_T_INDEX : TEAM_CT_INDEX;

    // Check weapon entity inside weaponbox
    new iWpn = cs_get_weaponbox_item(ent);
    new weapon_id = CSW_NONE;
    if (pev_valid(iWpn))
    {
        weapon_id = cs_get_weapon_id(iWpn);
    }
    else
    {
        // Fallback identification from model name
        for (new w = 1; w <= CSW_LAST_WEAPON; w++)
        {
            if (g_WeaponModelNames[w][0] && containi(model, g_WeaponModelNames[w][2]) != -1)
            {
                weapon_id = w;
                break;
            }
        }
    }

    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return FMRES_IGNORED;

    // 1. M4A1 / M4A4 Handling
    if (weapon_id == CSW_M4A1)
    {
        new slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);
        new s_idx = (id >= 1 && id <= MaxClients) ? g_iPlayerSkin[id][slot] : 0;
        new bool:is_a4 = false;

        if (pev_valid(iWpn))
        {
            new iVar = pev(iWpn, pev_iuser1);
            if (iVar == 1) is_a4 = true;
            else if (iVar == 2) is_a4 = false;
            else
            {
                is_a4 = (team == CS_TEAM_CT) ? g_SkinIsM4A4[slot][s_idx] : false;
                set_pev(iWpn, pev_iuser1, is_a4 ? 1 : 2);
            }
        }
        else
        {
            is_a4 = (team == CS_TEAM_CT) ? g_SkinIsM4A4[slot][s_idx] : false;
        }

        new target_idx = GetCatalogM4Index(is_a4);
        if (target_idx >= 0 && target_idx < g_SkinCount[slot] && g_SkinWModel[slot][target_idx][0])
        {
            if (!equal(model, g_SkinWModel[slot][target_idx]))
            {
                g_bSettingDropModel = true;
                engfunc(EngFunc_SetModel, ent, g_SkinWModel[slot][target_idx]);
                g_bSettingDropModel = false;
            }
            set_pev(ent, pev_iuser1, is_a4 ? 1 : 2);
            return FMRES_SUPERCEDE;
        }
        return FMRES_IGNORED;
    }

    // 2. All other weapons (Tec-9, CZ75, MP7, PP-Bizon, MAG-7, Sawed-Off, Negev, etc.)
    new slot = GET_SLOT(team_index, weapon_id);
    new s_idx = (id >= 1 && id <= MaxClients) ? g_iPlayerSkin[id][slot] : 0;

    if (pev_valid(iWpn))
    {
        new iSaved = pev(iWpn, pev_iuser2);
        if (iSaved > 0 && (iSaved - 1) < g_SkinCount[slot])
        {
            s_idx = iSaved - 1;
        }
        else if (s_idx >= 0 && s_idx < g_SkinCount[slot])
        {
            set_pev(iWpn, pev_iuser2, s_idx + 1);
        }
    }

    if (s_idx >= 0 && s_idx < g_SkinCount[slot] && g_SkinWModel[slot][s_idx][0])
    {
        if (!equal(model, g_SkinWModel[slot][s_idx]))
        {
            g_bSettingDropModel = true;
            engfunc(EngFunc_SetModel, ent, g_SkinWModel[slot][s_idx]);
            g_bSettingDropModel = false;
            set_pev(ent, pev_iuser2, s_idx + 1);
            set_pev(ent, pev_iuser1, weapon_id);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

public OnItemAddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn) || !is_user_alive(id))
        return HAM_IGNORED;

    new weapon_id = cs_get_weapon_id(iWpn);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON || weapon_id == CSW_M4A1)
        return HAM_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return HAM_IGNORED;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, weapon_id);

    // If weapon has no skin stamped yet (e.g. freshly purchased), stamp player's equipped skin
    new iSaved = pev(iWpn, pev_iuser2);
    if (iSaved == 0)
    {
        new s_idx = g_iPlayerSkin[id][slot];
        set_pev(iWpn, pev_iuser2, s_idx + 1);
    }

    return HAM_IGNORED;
}

public OnUpdateClientData_Post(id, sendweapons, cd_handle)
{
    if (!is_user_alive(id) || !get_pcvar_num(pCvar_Enable))
        return FMRES_IGNORED;

    new weapon_id = cs_get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return FMRES_IGNORED;

    new CsTeams:team = cs_get_user_team(id);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return FMRES_IGNORED;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, weapon_id);
    new s_idx = g_iPlayerSkin[id][slot];

    if (weapon_id == CSW_M4A1)
    {
        new iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
        if (pev_valid(iWpn))
        {
            new iVar = pev(iWpn, pev_iuser1);
            if (iVar == 1)
                s_idx = GetCatalogM4Index(true);
            else if (iVar == 2)
                s_idx = GetCatalogM4Index(false);
        }
    }
    else
    {
        new iWpn = fm_find_weapon_ent_by_owner(id, g_WeaponEntityNames[weapon_id]);
        if (pev_valid(iWpn))
        {
            new iSaved = pev(iWpn, pev_iuser2);
            if (iSaved > 0 && (iSaved - 1) < g_SkinCount[slot])
            {
                s_idx = iSaved - 1;
            }
        }
    }

    if (s_idx >= 0 && s_idx < g_SkinCount[slot] && g_SkinFireSoundCount[slot][s_idx] > 0)
    {
        set_cd(cd_handle, CD_flNextAttack, get_gametime() + 0.001);
        return FMRES_HANDLED;
    }

    return FMRES_IGNORED;
}

// ==============================================================================
// GUNSHOT BULLET DECALS & IMPACT EFFECTS (For Superceded Custom Gunfire Sounds)
// ==============================================================================
new const g_GunshotDecals[][] = {
    "{shot1",
    "{shot2",
    "{shot3",
    "{shot4",
    "{shot5"
};
new g_iGunshotDecalIndices[5] = { -1, -1, -1, -1, -1 };

stock CacheGunshotDecals()
{
    for (new i = 0; i < sizeof(g_GunshotDecals); i++)
    {
        g_iGunshotDecalIndices[i] = engfunc(EngFunc_DecalIndex, g_GunshotDecals[i]);
    }
}

stock GetRandomGunshotDecal()
{
    new idx = random_num(0, sizeof(g_GunshotDecals) - 1);
    if (g_iGunshotDecalIndices[idx] >= 0)
    {
        return g_iGunshotDecalIndices[idx];
    }

    new decal = engfunc(EngFunc_DecalIndex, g_GunshotDecals[idx]);
    if (decal >= 0)
    {
        g_iGunshotDecalIndices[idx] = decal;
        return decal;
    }

    return 41 + idx;
}

stock DrawGunshotDecalsAndEffects(invoker, weapon_id, const Float:angles[3])
{
    if (invoker < 1 || invoker > MaxClients || !is_user_alive(invoker))
        return;

    new Float:vStart[3], Float:vViewOfs[3], Float:vOrigin[3];
    pev(invoker, pev_origin, vOrigin);
    pev(invoker, pev_view_ofs, vViewOfs);
    xs_vec_add(vOrigin, vViewOfs, vStart);

    new Float:vAimAngles[3];
    if (angles[0] != 0.0 || angles[1] != 0.0 || angles[2] != 0.0)
    {
        xs_vec_copy(angles, vAimAngles);
        if (vAimAngles[0] == 0.0)
        {
            // When torso angles are passed, pitch is 0.0; pull authoritative camera pitch
            new Float:vEyeAngles[3];
            pev(invoker, pev_v_angle, vEyeAngles);
            vAimAngles[0] = vEyeAngles[0];
        }
        new Float:vPunch[3];
        pev(invoker, pev_punchangle, vPunch);
        xs_vec_add(vAimAngles, vPunch, vAimAngles);
    }
    else
    {
        pev(invoker, pev_v_angle, vAimAngles);
        new Float:vPunch[3];
        pev(invoker, pev_punchangle, vPunch);
        xs_vec_add(vAimAngles, vPunch, vAimAngles);
    }

    new Float:vForward[3], Float:vRight[3], Float:vUp[3];
    angle_vector(vAimAngles, ANGLEVECTOR_FORWARD, vForward);
    angle_vector(vAimAngles, ANGLEVECTOR_RIGHT, vRight);
    angle_vector(vAimAngles, ANGLEVECTOR_UP, vUp);

    new bool:isShotgun = (weapon_id == CSW_M3 || weapon_id == CSW_XM1014);
    new numShots = isShotgun ? ((weapon_id == CSW_M3) ? 8 : 6) : 1;

    for (new s = 0; s < numShots; s++)
    {
        new Float:vDir[3], Float:vEnd[3];
        if (isShotgun)
        {
            new Float:flSpreadX = random_float(-0.045, 0.045);
            new Float:flSpreadY = random_float(-0.045, 0.045);
            vDir[0] = vForward[0] + (vRight[0] * flSpreadX) + (vUp[0] * flSpreadY);
            vDir[1] = vForward[1] + (vRight[1] * flSpreadX) + (vUp[1] * flSpreadY);
            vDir[2] = vForward[2] + (vRight[2] * flSpreadX) + (vUp[2] * flSpreadY);
            xs_vec_normalize(vDir, vDir);
        }
        else
        {
            xs_vec_copy(vForward, vDir);
        }

        xs_vec_mul_scalar(vDir, 8192.0, vEnd);
        xs_vec_add(vStart, vEnd, vEnd);

        engfunc(EngFunc_TraceLine, vStart, vEnd, DONT_IGNORE_MONSTERS, invoker, 0);

        new Float:flFraction;
        get_tr2(0, TR_flFraction, flFraction);
        if (flFraction >= 1.0)
            continue;

        new pHit = get_tr2(0, TR_pHit);
        if (pHit > 0 && pHit <= MaxClients)
            continue; // Player flesh impact, no bullet decal on players

        if (pev_valid(pHit))
        {
            new classname[32];
            pev(pHit, pev_classname, classname, charsmax(classname));
            if (equal(classname, "player") || equal(classname, "bot"))
                continue;
        }

        new Float:vecEndPos[3];
        get_tr2(0, TR_vecEndPos, vecEndPos);

        // 1. Particle effect (sparks and dust puff)
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_GUNSHOT);
        write_coord_f(vecEndPos[0]);
        write_coord_f(vecEndPos[1]);
        write_coord_f(vecEndPos[2]);
        message_end();

        // 2. Gunshot bullet hole decal
        new decalIndex = GetRandomGunshotDecal();
        message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
        write_byte(TE_GUNSHOTDECAL);
        write_coord_f(vecEndPos[0]);
        write_coord_f(vecEndPos[1]);
        write_coord_f(vecEndPos[2]);
        write_short(pHit > 0 ? pHit : 0);
        write_byte(decalIndex);
        message_end();
    }
}

public OnPlaybackEvent_Pre(flags, invoker, eventid, Float:delay, Float:origin[3], Float:angles[3], Float:fparam1, Float:fparam2, iParam1, iParam2, bParam1, bParam2)
{
    if (!get_pcvar_num(pCvar_Enable) || invoker < 1 || invoker > MaxClients || !is_user_alive(invoker))
        return FMRES_IGNORED;

    new weapon_id = cs_get_user_weapon(invoker);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return FMRES_IGNORED;

    if (eventid != g_iWeaponEventId[weapon_id] || eventid == 0)
        return FMRES_IGNORED;

    new CsTeams:team = cs_get_user_team(invoker);
    if (team != CS_TEAM_CT && team != CS_TEAM_T)
        return FMRES_IGNORED;

    new team_index = (team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;
    new slot = GET_SLOT(team_index, weapon_id);
    new s_idx = g_iPlayerSkin[invoker][slot];

    if (weapon_id == CSW_M4A1)
    {
        new iWpn = fm_find_weapon_ent_by_owner(invoker, "weapon_m4a1");
        if (pev_valid(iWpn))
        {
            new iVar = pev(iWpn, pev_iuser1);
            if (iVar == 1)
                s_idx = GetCatalogM4Index(true);
            else if (iVar == 2)
                s_idx = GetCatalogM4Index(false);
        }
    }
    else
    {
        new iWpn = fm_find_weapon_ent_by_owner(invoker, g_WeaponEntityNames[weapon_id]);
        if (pev_valid(iWpn))
        {
            new iSaved = pev(iWpn, pev_iuser2);
            if (iSaved > 0 && (iSaved - 1) < g_SkinCount[slot])
            {
                s_idx = iSaved - 1;
            }
        }
    }

    if (s_idx < 0 || s_idx >= g_SkinCount[slot])
        return FMRES_IGNORED;

    new snd_count = g_SkinFireSoundCount[slot][s_idx];
    if (snd_count <= 0)
        return FMRES_IGNORED;

    new sound_file[128];
    if (snd_count == 1 || (snd_count > 1 && random_num(0, 1) == 0))
    {
        copy(sound_file, charsmax(sound_file), g_SkinFireSound1[slot][s_idx]);
    }
    else
    {
        copy(sound_file, charsmax(sound_file), g_SkinFireSound2[slot][s_idx]);
    }

    if (!sound_file[0])
        return FMRES_IGNORED;

    // Play custom gunfire sound cleanly without playing default 1.6 event sound!
    emit_sound(invoker, CHAN_WEAPON, sound_file, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    // Provide visual recoil and muzzleflash to invoker and observers
    set_pev(invoker, pev_effects, pev(invoker, pev_effects) | EF_MUZZLEFLASH);

    if (!is_user_bot(invoker))
    {
        new shoot_anim = GetWeaponShootAnim(weapon_id);
        if (shoot_anim >= 0)
        {
            SendWeaponAnim(invoker, shoot_anim);
        }
    }

    // Render bullet holes, wall impact sparks & dust particles for weapons with custom gunfire audio
    DrawGunshotDecalsAndEffects(invoker, weapon_id, angles);

    return FMRES_SUPERCEDE;
}

// ==============================================================================
// CS2 LOADOUT MENUS
// ==============================================================================

public Cmd_OpenLoadout(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    ShowMainMenu(id);
    return PLUGIN_HANDLED;
}

public Cmd_OpenKnifeMenu(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    ShowDirectKnifeMenu(id);
    return PLUGIN_HANDLED;
}

public Cmd_OpenM4Menu(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new CsTeams:team = cs_get_user_team(id);
    new team_index = (team == CS_TEAM_T) ? TEAM_T_INDEX : TEAM_CT_INDEX;
    ShowWeaponSkinMenu(id, team_index, CSW_M4A1);
    return PLUGIN_HANDLED;
}

public Cmd_OpenGloveInfo(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    ShowGloveInfoMenu(id);
    return PLUGIN_HANDLED;
}

public Cmd_SelectM4A4Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new CsTeams:team = cs_get_user_team(id);
    new team_index = (team == CS_TEAM_T) ? TEAM_T_INDEX : TEAM_CT_INDEX;
    new slot = GET_SLOT(team_index, CSW_M4A1);
    for (new s = 0; s < g_SkinCount[slot]; s++)
    {
        if (g_SkinIsM4A4[slot][s])
        {
            SelectWeaponSkin(id, team_index, CSW_M4A1, s);
            return PLUGIN_HANDLED;
        }
    }

    client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No M4A4 skin found in catalog.");
    return PLUGIN_HANDLED;
}

public Cmd_SelectM4A1Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new CsTeams:team = cs_get_user_team(id);
    new team_index = (team == CS_TEAM_T) ? TEAM_T_INDEX : TEAM_CT_INDEX;
    new slot = GET_SLOT(team_index, CSW_M4A1);
    for (new s = 0; s < g_SkinCount[slot]; s++)
    {
        if (!g_SkinIsM4A4[slot][s])
        {
            SelectWeaponSkin(id, team_index, CSW_M4A1, s);
            return PLUGIN_HANDLED;
        }
    }

    client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No M4A1-S skin found in catalog.");
    return PLUGIN_HANDLED;
}

public Cmd_SelectTec9Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_P228);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "tec") != -1 || containi(g_SkinVModel[slot][s], "tec9") != -1)
            {
                SelectWeaponSkin(id, t, CSW_P228, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No Tec-9 skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectCZ75Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    // CT slot: TMP
    new ct_slot = GET_SLOT(TEAM_CT_INDEX, CSW_TMP);
    for (new s = 0; s < g_SkinCount[ct_slot]; s++)
    {
        if (containi(g_SkinName[ct_slot][s], "cz") != -1 || containi(g_SkinVModel[ct_slot][s], "cz75") != -1)
        {
            SelectWeaponSkin(id, TEAM_CT_INDEX, CSW_TMP, s);
            found = true;
            break;
        }
    }

    // T slot: MAC-10
    new t_slot = GET_SLOT(TEAM_T_INDEX, CSW_MAC10);
    for (new s = 0; s < g_SkinCount[t_slot]; s++)
    {
        if (containi(g_SkinName[t_slot][s], "cz") != -1 || containi(g_SkinVModel[t_slot][s], "cz75") != -1)
        {
            SelectWeaponSkin(id, TEAM_T_INDEX, CSW_MAC10, s);
            found = true;
            break;
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No CZ75-Auto skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectMP7Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_MP5NAVY);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "mp7") != -1 || containi(g_SkinVModel[slot][s], "mp7") != -1)
            {
                SelectWeaponSkin(id, t, CSW_MP5NAVY, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No MP7 skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectBizonDirect(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_P90);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "bizon") != -1 || containi(g_SkinVModel[slot][s], "bizon") != -1)
            {
                SelectWeaponSkin(id, t, CSW_P90, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No PP-Bizon skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectMAG7Direct(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_XM1014);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "mag") != -1 || containi(g_SkinVModel[slot][s], "mag7") != -1)
            {
                SelectWeaponSkin(id, t, CSW_XM1014, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No MAG-7 skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectSawedOffDirect(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_M3);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "sawed") != -1 || containi(g_SkinVModel[slot][s], "sawedoff") != -1)
            {
                SelectWeaponSkin(id, t, CSW_M3, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No Sawed-Off skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_SelectNegevDirect(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    new bool:found = false;
    for (new t = 0; t < 2; t++)
    {
        new slot = GET_SLOT(t, CSW_M249);
        for (new s = 0; s < g_SkinCount[slot]; s++)
        {
            if (containi(g_SkinName[slot][s], "negev") != -1 || containi(g_SkinVModel[slot][s], "negev") != -1)
            {
                SelectWeaponSkin(id, t, CSW_M249, s);
                found = true;
                break;
            }
        }
    }

    if (!found)
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 No Negev skin found in catalog.");

    return PLUGIN_HANDLED;
}

public Cmd_ResetLoadout(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    ResetPlayerLoadout(id);
    return PLUGIN_HANDLED;
}

public Cmd_ReloadActiveLoadout(id, level, cid)
{

    new active_config[128];
    get_configsdir(active_config, charsmax(active_config));
    format(active_config, charsmax(active_config), "%s/active_loadout.ini", active_config);

    if (file_exists(active_config))
    {
        LoadActiveLoadoutConfig(active_config);
        for (new i = 1; i <= MaxClients; i++)
        {
            if (is_user_connected(i))
            {
                for (new s = 0; s < TOTAL_SLOTS; s++)
                {
                    g_iPlayerSkin[i][s] = g_ActiveLoadoutSkin[s];
                }
                if (is_user_alive(i))
                {
                    new wid = cs_get_user_weapon(i);
                    if (wid > CSW_NONE && wid <= CSW_LAST_WEAPON)
                    {
                        ApplyViewModel(i, wid, 0, true);
                    }
                }
            }
        }
        if (id == 0)
            server_print("[CS2 Loadout] active_loadout.ini reloaded successfully.");
        else
            client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 active_loadout.ini reloaded successfully.");
    }
    else
    {
        if (id == 0)
            server_print("[CS2 Loadout] active_loadout.ini not found.");
        else
            client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 active_loadout.ini not found.");
    }

    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Main Menu
// ------------------------------------------------------------------------------

public ShowMainMenu(id)
{
    new title[128];
    formatex(title, charsmax(title), "\y[CS2 LOADOUT & INVENTORY]\w^n\dSesuaikan Skin, Knife & Loadout Tim Anda:\w");
    new menu = menu_create(title, "Handler_MainMenu");

    menu_additem(menu, "\w[CT] Counter-Terrorists Loadout", "1");
    menu_additem(menu, "\w[T]  Terrorists Loadout", "2");
    menu_additem(menu, "\w[Knife] Knife Selection (CT & T)", "3");
    menu_additem(menu, "\w[Gloves] Glove Options & Guide", "4");
    menu_additem(menu, "\w[Bot M4] CT Bot M4 Loadout System", "5");
    menu_additem(menu, "\r[Reset] Reset All to Defaults", "6");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_MainMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    switch (str_to_num(szData))
    {
        case 1: ShowTeamLoadoutMenu(id, TEAM_CT_INDEX);
        case 2: ShowTeamLoadoutMenu(id, TEAM_T_INDEX);
        case 3: ShowDirectKnifeMenu(id);
        case 4: ShowGloveInfoMenu(id);
        case 5: ShowBotM4Menu(id);
        case 6: ResetPlayerLoadout(id);
    }

    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Team Loadout Menu (CT or T)
// ------------------------------------------------------------------------------

public ShowTeamLoadoutMenu(id, team_index)
{
    new title[128];
    formatex(title, charsmax(title), "\y[CS2 %s Loadout]\w^nPilih Kategori Senjata:",
        (team_index == TEAM_CT_INDEX) ? "Counter-Terrorist" : "Terrorist");

    new menu = menu_create(title, (team_index == TEAM_CT_INDEX) ? "Handler_CTLoadout" : "Handler_TLoadout");

    // Knife slot line with active knife name
    new knife_slot = GET_SLOT(team_index, CSW_KNIFE);
    new knife_s = g_iPlayerSkin[id][knife_slot];
    new knife_item[96], k_name[32];
    copy(k_name, charsmax(k_name), g_SkinName[knife_slot][knife_s]);
    if (!k_name[0]) copy(k_name, charsmax(k_name), "Default Knife");
    formatex(knife_item, charsmax(knife_item), "\w[Knife] Knife Slot \y[%s]\w", k_name);
    menu_additem(menu, knife_item, "0");

    menu_additem(menu, "\w[Pistols] Pistols (USP-S, Glock, Deagle, Berettas...)", "1");
    menu_additem(menu, "\w[Mid-Tier] Mid-Tier (MP5-SD, UMP-45, XM1014, Shotguns...)", "2");
    menu_additem(menu, "\w[Rifles] Rifles & Snipers (M4 Slot, AK-47, AWP, Scout...)", "3");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_CTLoadout(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new choice = str_to_num(szData);
    if (choice == 0)
    {
        ShowWeaponSkinMenu(id, TEAM_CT_INDEX, CSW_KNIFE);
    }
    else
    {
        ShowCategoryMenu(id, TEAM_CT_INDEX, choice);
    }

    return PLUGIN_HANDLED;
}

public Handler_TLoadout(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new choice = str_to_num(szData);
    if (choice == 0)
    {
        ShowWeaponSkinMenu(id, TEAM_T_INDEX, CSW_KNIFE);
    }
    else
    {
        ShowCategoryMenu(id, TEAM_T_INDEX, choice);
    }

    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Category Menu
// ------------------------------------------------------------------------------

public ShowCategoryMenu(id, team_index, category_index)
{
    new title[128];
    new cat_name[32];
    switch (category_index)
    {
        case 1: copy(cat_name, charsmax(cat_name), "Pistols");
        case 2: copy(cat_name, charsmax(cat_name), "Mid-Tier");
        case 3: copy(cat_name, charsmax(cat_name), "Rifles & Snipers");
    }

    formatex(title, charsmax(title), "\y[CS2 %s] %s:\w",
        (team_index == TEAM_CT_INDEX) ? "CT" : "T", cat_name);

    new menu = menu_create(title, "Handler_CategoryMenu");

    // Populate category weapons
    new weapons_to_show[12], wep_count = 0;

    if (category_index == 1) // Pistols
    {
        if (team_index == TEAM_CT_INDEX)
        {
            weapons_to_show[wep_count++] = CSW_USP;
            weapons_to_show[wep_count++] = CSW_DEAGLE;
            weapons_to_show[wep_count++] = CSW_FIVESEVEN;
            weapons_to_show[wep_count++] = CSW_P228;
            weapons_to_show[wep_count++] = CSW_ELITE;
        }
        else
        {
            weapons_to_show[wep_count++] = CSW_GLOCK18;
            weapons_to_show[wep_count++] = CSW_DEAGLE;
            weapons_to_show[wep_count++] = CSW_ELITE;
            weapons_to_show[wep_count++] = CSW_P228;
        }
    }
    else if (category_index == 2) // Mid-Tier
    {
        weapons_to_show[wep_count++] = CSW_MP5NAVY;
        weapons_to_show[wep_count++] = CSW_UMP45;
        weapons_to_show[wep_count++] = CSW_XM1014;
        weapons_to_show[wep_count++] = CSW_M3;
        weapons_to_show[wep_count++] = CSW_P90;
        if (team_index == TEAM_CT_INDEX)
            weapons_to_show[wep_count++] = CSW_TMP;
        else
            weapons_to_show[wep_count++] = CSW_MAC10;
        weapons_to_show[wep_count++] = CSW_M249;
    }
    else if (category_index == 3) // Rifles
    {
        if (team_index == TEAM_CT_INDEX)
        {
            weapons_to_show[wep_count++] = CSW_M4A1; // M4 slot (M4A4 & M4A1-S)
            weapons_to_show[wep_count++] = CSW_AWP;
            weapons_to_show[wep_count++] = CSW_SCOUT;
            weapons_to_show[wep_count++] = CSW_FAMAS;
            weapons_to_show[wep_count++] = CSW_AUG;
            weapons_to_show[wep_count++] = CSW_SG550;
        }
        else
        {
            weapons_to_show[wep_count++] = CSW_AK47;
            weapons_to_show[wep_count++] = CSW_M4A1; // M4 slot (M4A4 & M4A1-S)
            weapons_to_show[wep_count++] = CSW_AWP;
            weapons_to_show[wep_count++] = CSW_SCOUT;
            weapons_to_show[wep_count++] = CSW_GALIL;
            weapons_to_show[wep_count++] = CSW_SG552;
            weapons_to_show[wep_count++] = CSW_G3SG1;
        }
    }

    for (new i = 0; i < wep_count; i++)
    {
        new wid = weapons_to_show[i];
        new slot = GET_SLOT(team_index, wid);
        new s_idx = g_iPlayerSkin[id][slot];
        new item_str[96], item_info[16];
        new skin_name[32];
        copy(skin_name, charsmax(skin_name), g_SkinName[slot][s_idx]);
        if (!skin_name[0]) copy(skin_name, charsmax(skin_name), "Default");

        formatex(item_str, charsmax(item_str), "%s \y[%s]\w",
            g_WeaponDisplayNames[wid], skin_name);
        formatex(item_info, charsmax(item_info), "%d_%d", team_index, wid);

        menu_additem(menu, item_str, item_info);
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_CategoryMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[16], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new team_str[6], wid_str[6];
    strtok(szData, team_str, charsmax(team_str), wid_str, charsmax(wid_str), '_');

    new team_idx = str_to_num(team_str);
    new wid = str_to_num(wid_str);

    ShowWeaponSkinMenu(id, team_idx, wid);
    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Weapon Skin Selection Menu
// ------------------------------------------------------------------------------

public ShowWeaponSkinMenu(id, team_index, weapon_id)
{
    new title[128];
    formatex(title, charsmax(title), "\y[CS2 %s] Pilih Skin: %s\w",
        (team_index == TEAM_CT_INDEX) ? "CT" : "T", g_WeaponDisplayNames[weapon_id]);

    new menu = menu_create(title, "Handler_WeaponSkinMenu");

    new slot = GET_SLOT(team_index, weapon_id);
    new cur_skin = g_iPlayerSkin[id][slot];
    new total_skins = g_SkinCount[slot];

    if (total_skins == 0)
    {
        menu_additem(menu, "\d(Tidak ada skin kustom terdaftar - menggunakan model default)\w", "none");
    }
    else
    {
        for (new s = 0; s < total_skins; s++)
        {
            new item_str[96], item_data[16];
            new bool:is_equipped = (s == cur_skin);

            formatex(item_str, charsmax(item_str), "%s%s",
                g_SkinName[slot][s], is_equipped ? " \r(Equipped)\w" : "");
            formatex(item_data, charsmax(item_data), "%d_%d_%d", team_index, weapon_id, s);

            menu_additem(menu, item_str, item_data);
        }
    }

    if (weapon_id == CSW_M4A1 && team_index == TEAM_CT_INDEX)
    {
        menu_additem(menu, "\y[Bot Loadout] Pengaturan M4 CT Bot...\w", "bot_m4_manage");
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_WeaponSkinMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[24], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    if (equal(szData, "bot_m4_manage"))
    {
        ShowBotM4Menu(id);
        return PLUGIN_HANDLED;
    }

    if (equal(szData, "none"))
        return PLUGIN_HANDLED;

    new team_str[6], rest[16], wid_str[6], skin_str[6];
    strtok(szData, team_str, charsmax(team_str), rest, charsmax(rest), '_');
    strtok(rest, wid_str, charsmax(wid_str), skin_str, charsmax(skin_str), '_');

    new team_idx = str_to_num(team_str);
    new wid = str_to_num(wid_str);
    new skin_idx = str_to_num(skin_str);

    SelectWeaponSkin(id, team_idx, wid, skin_idx);
    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Direct Knife Menu (/knife)
// ------------------------------------------------------------------------------

public ShowDirectKnifeMenu(id)
{
    new title[128];
    formatex(title, charsmax(title), "\y[CS2 Knife Loadout] Pilih Tim:\w");
    new menu = menu_create(title, "Handler_DirectKnifeMenu");

    new ct_slot = GET_SLOT(TEAM_CT_INDEX, CSW_KNIFE);
    new t_slot = GET_SLOT(TEAM_T_INDEX, CSW_KNIFE);

    new ct_k = g_iPlayerSkin[id][ct_slot];
    new t_k = g_iPlayerSkin[id][t_slot];

    new ct_line[96], t_line[96];
    new ct_name[32], t_name[32];
    copy(ct_name, charsmax(ct_name), g_SkinName[ct_slot][ct_k]);
    if (!ct_name[0]) copy(ct_name, charsmax(ct_name), "Default Knife");
    copy(t_name, charsmax(t_name), g_SkinName[t_slot][t_k]);
    if (!t_name[0]) copy(t_name, charsmax(t_name), "Default Knife");

    formatex(ct_line, charsmax(ct_line), "[CT] Knife Slot \y[%s]\w", ct_name);
    formatex(t_line, charsmax(t_line), "[T]  Knife Slot \y[%s]\w", t_name);

    menu_additem(menu, ct_line, "0");
    menu_additem(menu, t_line, "1");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_DirectKnifeMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new team_idx = str_to_num(szData);
    ShowWeaponSkinMenu(id, team_idx, CSW_KNIFE);
    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Glove Guide Menu (/gloves)
// ------------------------------------------------------------------------------

public ShowGloveInfoMenu(id)
{
    new menu = menu_create("\y[CS2 Glove System & Guide]\w", "Handler_GloveInfoMenu");

    menu_additem(menu, "\w- Glove terintegrasi langsung pada model weapon pilihan Anda.", "1");
    menu_additem(menu, "\w- CT sleeve & T bare arm selalu dipertahankan otomatis.", "2");
    menu_additem(menu, "\w- Gunakan: \ytools/cs2_model_baker.py\w untuk inject glove baru.", "3");
    menu_additem(menu, "\w- Kembali ke Main Loadout", "4");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_GloveInfoMenu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    menu_destroy(menu);
    ShowMainMenu(id);
    return PLUGIN_HANDLED;
}

// ------------------------------------------------------------------------------
// Skin Selection Logic & Persistence
// ------------------------------------------------------------------------------

stock SelectWeaponSkin(id, team, weapon_id, skin_idx)
{
    new slot = GET_SLOT(team, weapon_id);
    if (skin_idx < 0 || skin_idx >= g_SkinCount[slot])
        return;

    g_iPlayerSkin[id][slot] = skin_idx;
    SavePlayerWeaponSkin(id, team, weapon_id);

    if (get_pcvar_num(pCvar_Notify))
    {
        client_print_color(id, print_team_default,
            "^4[CS2 Loadout]^1 Equiped ^3%s^1 untuk ^4%s^1 (%s)!",
            g_SkinName[slot][skin_idx],
            g_WeaponDisplayNames[weapon_id],
            (team == TEAM_CT_INDEX) ? "CT" : "T");
    }

    // Instantly update active weapon viewmodel if player is currently holding it
    if (is_user_alive(id))
    {
        new CsTeams:user_team = cs_get_user_team(id);
        new user_team_idx = (user_team == CS_TEAM_CT) ? TEAM_CT_INDEX : TEAM_T_INDEX;

        if (user_team_idx == team && cs_get_user_weapon(id) == weapon_id)
        {
            if (weapon_id == CSW_M4A1)
            {
                new iWpn = fm_find_weapon_ent_by_owner(id, "weapon_m4a1");
                if (pev_valid(iWpn))
                {
                    new bool:is_a4 = g_SkinIsM4A4[slot][skin_idx];
                    set_pev(iWpn, pev_iuser1, is_a4 ? 1 : 2);
                    if (is_a4 && cs_get_weapon_silen(iWpn))
                    {
                        cs_set_weapon_silen(iWpn, 0, 0);
                    }
                    else if (!is_a4 && get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
                    {
                        cs_set_weapon_silen(iWpn, 1, 0);
                    }
                }
            }
            else
            {
                new iWpn = fm_find_weapon_ent_by_owner(id, g_WeaponEntityNames[weapon_id]);
                if (pev_valid(iWpn))
                {
                    set_pev(iWpn, pev_iuser2, skin_idx + 1);
                }
            }
            ApplyViewModel(id, weapon_id, 0, true);
        }
    }
}

stock ResetPlayerLoadout(id)
{
    for (new t = 0; t < 2; t++)
    {
        for (new w = 0; w <= CSW_LAST_WEAPON; w++)
        {
            new slot = GET_SLOT(t, w);
            g_iPlayerSkin[id][slot] = g_ActiveLoadoutSkin[slot];
            if (g_SkinCount[slot] > 0)
            {
                SavePlayerWeaponSkin(id, t, w);
            }
        }
    }

    if (is_user_alive(id))
    {
        new wid = cs_get_user_weapon(id);
        if (wid > CSW_NONE && wid <= CSW_LAST_WEAPON)
        {
            ApplyViewModel(id, wid, 0, true);
        }
    }

    client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 Seluruh loadout CT & T telah direset ke default.");
}

// ==============================================================================
// CT BOT M4 LOADOUT MENUS & COMMANDS (/botm4)
// ==============================================================================

public Cmd_BotM4Command(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    if (!CanAccessBotM4Menu(id))
    {
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 Akses ditolak. Hanya server host / admin yang dapat mengatur Bot M4.");
        return PLUGIN_HANDLED;
    }

    new args[32];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    if (containi(args, "role") != -1 || containi(args, "smart") != -1)
    {
        SetBotM4Mode(1, id);
        return PLUGIN_HANDLED;
    }
    else if (containi(args, "mix") != -1 || containi(args, "50") != -1)
    {
        SetBotM4Mode(2, id);
        return PLUGIN_HANDLED;
    }
    else if (containi(args, "m4a4") != -1 || containi(args, "a4") != -1)
    {
        SetBotM4Mode(3, id);
        return PLUGIN_HANDLED;
    }
    else if (containi(args, "m4a1") != -1 || containi(args, "a1") != -1)
    {
        SetBotM4Mode(4, id);
        return PLUGIN_HANDLED;
    }
    else if (containi(args, "auto") != -1 || containi(args, "mirror") != -1 || containi(args, "default") != -1)
    {
        SetBotM4Mode(0, id);
        return PLUGIN_HANDLED;
    }

    ShowBotM4Menu(id);
    return PLUGIN_HANDLED;
}

public ShowBotM4Menu(id)
{
    if (!CanAccessBotM4Menu(id))
    {
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 Menu pengaturan Bot M4 hanya dapat diakses oleh Admin.");
        return;
    }

    new cur_mode = get_pcvar_num(pCvar_BotM4Mode);
    new title[192];
    formatex(title, charsmax(title), "\y[CS2 CT BOT M4 LOADOUT]\w^nMode Aktif: \r%s\w^n^nPilih Distribusi M4 Bot CT:",
        (cur_mode == 1) ? "Role-Based (Smart)" :
        (cur_mode == 2) ? "Campuran 50/50" :
        (cur_mode == 3) ? "Semua M4A4" :
        (cur_mode == 4) ? "Semua M4A1-S" : "Ikuti Active Loadout");

    new menu = menu_create(title, "Handler_BotM4Menu");

    new item[128];
    formatex(item, charsmax(item), "\wRole-Based (Smart) \d(Entry=M4A4, Supp=M4A1-S)\w %s", (cur_mode == 1) ? "\y[AKTIF]\w" : "");
    menu_additem(menu, item, "1");

    formatex(item, charsmax(item), "\wCampuran 50/50 \d(Roster Split Realistis)\w %s", (cur_mode == 2) ? "\y[AKTIF]\w" : "");
    menu_additem(menu, item, "2");

    formatex(item, charsmax(item), "\wSemua M4A4 \d(Seluruh Bot CT Memakai M4A4)\w %s", (cur_mode == 3) ? "\y[AKTIF]\w" : "");
    menu_additem(menu, item, "3");

    formatex(item, charsmax(item), "\wSemua M4A1-S \d(Seluruh Bot CT Memakai M4A1-S)\w %s", (cur_mode == 4) ? "\y[AKTIF]\w" : "");
    menu_additem(menu, item, "4");

    formatex(item, charsmax(item), "\wIkuti Active Loadout \d(Default Companion)\w %s", (cur_mode == 0) ? "\y[AKTIF]\w" : "");
    menu_additem(menu, item, "0");

    menu_additem(menu, "\yKustomisasi Bot Individu...\w", "99");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_BotM4Menu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new choice = str_to_num(szData);
    if (choice == 99)
    {
        ShowIndividualBotM4Menu(id);
    }
    else
    {
        SetBotM4Mode(choice, id);
        ShowBotM4Menu(id);
    }

    return PLUGIN_HANDLED;
}

public ShowIndividualBotM4Menu(id)
{
    new menu = menu_create("\y[Kustomisasi Bot M4 Individu]\w^nPilih Bot CT untuk toggle (Auto -> M4A4 -> M4A1-S):", "Handler_IndividualBotM4Menu");

    new bot_count = 0;
    new slot = GET_SLOT(TEAM_CT_INDEX, CSW_M4A1);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (is_user_connected(i) && is_user_bot(i) && cs_get_user_team(i) == CS_TEAM_CT)
        {
            bot_count++;
            new szBotName[32], item_str[128], item_data[8];
            get_user_name(i, szBotName, charsmax(szBotName));

            new s_idx = g_iPlayerSkin[i][slot];
            new bool:is_a4 = g_SkinIsM4A4[slot][s_idx];

            new status[24];
            if (g_iBotM4Override[i] == -1)
            {
                formatex(status, charsmax(status), "Auto (%s)", is_a4 ? "M4A4" : "M4A1-S");
            }
            else if (g_iBotM4Override[i] == 0)
            {
                copy(status, charsmax(status), "Force M4A4");
            }
            else
            {
                copy(status, charsmax(status), "Force M4A1-S");
            }

            formatex(item_str, charsmax(item_str), "%s \y[%s]\w", szBotName, status);
            num_to_str(i, item_data, charsmax(item_data));
            menu_additem(menu, item_str, item_data);
        }
    }

    if (bot_count == 0)
    {
        menu_additem(menu, "\d(Tidak ada Bot di tim CT saat ini)\w", "0");
    }

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_IndividualBotM4Menu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[8], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new target_bot = str_to_num(szData);
    if (target_bot >= 1 && target_bot <= MaxClients && is_user_connected(target_bot))
    {
        if (g_iBotM4Override[target_bot] == -1)
            g_iBotM4Override[target_bot] = 0; // Force M4A4
        else if (g_iBotM4Override[target_bot] == 0)
            g_iBotM4Override[target_bot] = 1; // Force M4A1-S
        else
            g_iBotM4Override[target_bot] = -1; // Auto

        AssignBotM4Loadout(target_bot);
        if (is_user_alive(target_bot) && cs_get_user_weapon(target_bot) == CSW_M4A1)
        {
            ApplyViewModel(target_bot, CSW_M4A1, 0, true);
        }

        new szBotName[32];
        get_user_name(target_bot, szBotName, charsmax(szBotName));
        client_print_color(id, print_team_default, "^4[CS2 Loadout]^1 Bot ^3%s^1 diatur ke: ^4%s^1.",
            szBotName,
            (g_iBotM4Override[target_bot] == 0) ? "Force M4A4" :
            (g_iBotM4Override[target_bot] == 1) ? "Force M4A1-S" : "Auto (Mode Tim)");

        ShowIndividualBotM4Menu(id);
    }

    return PLUGIN_HANDLED;
}
