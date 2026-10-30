#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <fakemeta_util>
#include <hamsandwich>

#define PLUGIN  "CS:GO M4A4 & M4A1-S Loadout Switcher"
#define VERSION "1.0.0"
#define AUTHOR  "Antigravity"

#define CHOICE_M4A4   0
#define CHOICE_M4A1_S 1

// CVars
new pCvar_Enable;
new pCvar_DefaultChoice;
new pCvar_BlockSilencer;
new pCvar_AutoSilenceM4A1;
new pCvar_Notify;

// Player selection (0 = M4A4, 1 = M4A1-S)
new g_iM4Choice[33];

// Model filepaths
new g_szModelM4A4_V[128];
new g_szModelM4A4_P[128];
new g_szModelM4A4_W[128];
new g_szModelM4A1_V[128];
new g_szModelM4A1_P[128];

public plugin_precache()
{
    // Resolve M4A4 Models (Custom skins priority, csgo_skins fallback)
    if (file_exists("models/custom_skins/ct/v_m4a4.mdl"))
        copy(g_szModelM4A4_V, charsmax(g_szModelM4A4_V), "models/custom_skins/ct/v_m4a4.mdl");
    else if (file_exists("models/csgo_skins/ct/v_m4a4.mdl"))
        copy(g_szModelM4A4_V, charsmax(g_szModelM4A4_V), "models/csgo_skins/ct/v_m4a4.mdl");

    if (file_exists("models/custom_skins/ct/p_m4a4.mdl"))
        copy(g_szModelM4A4_P, charsmax(g_szModelM4A4_P), "models/custom_skins/ct/p_m4a4.mdl");
    else if (file_exists("models/csgo_skins/ct/p_m4a4.mdl"))
        copy(g_szModelM4A4_P, charsmax(g_szModelM4A4_P), "models/csgo_skins/ct/p_m4a4.mdl");

    if (file_exists("models/custom_skins/ct/w_m4a4.mdl"))
        copy(g_szModelM4A4_W, charsmax(g_szModelM4A4_W), "models/custom_skins/ct/w_m4a4.mdl");
    else if (file_exists("models/csgo_skins/ct/w_m4a4.mdl"))
        copy(g_szModelM4A4_W, charsmax(g_szModelM4A4_W), "models/csgo_skins/ct/w_m4a4.mdl");

    // Resolve M4A1-S Models (Custom skins priority, csgo_skins fallback)
    if (file_exists("models/custom_skins/ct/v_m4a1.mdl"))
        copy(g_szModelM4A1_V, charsmax(g_szModelM4A1_V), "models/custom_skins/ct/v_m4a1.mdl");
    else if (file_exists("models/csgo_skins/ct/v_m4a1.mdl"))
        copy(g_szModelM4A1_V, charsmax(g_szModelM4A1_V), "models/csgo_skins/ct/v_m4a1.mdl");

    if (file_exists("models/custom_skins/ct/p_m4a1.mdl"))
        copy(g_szModelM4A1_P, charsmax(g_szModelM4A1_P), "models/custom_skins/ct/p_m4a1.mdl");
    else if (file_exists("models/p_m4a1.mdl"))
        copy(g_szModelM4A1_P, charsmax(g_szModelM4A1_P), "models/p_m4a1.mdl");

    // Precache all existing models
    if (g_szModelM4A4_V[0]) precache_model(g_szModelM4A4_V);
    if (g_szModelM4A4_P[0]) precache_model(g_szModelM4A4_P);
    if (g_szModelM4A4_W[0]) precache_model(g_szModelM4A4_W);
    if (g_szModelM4A1_V[0]) precache_model(g_szModelM4A1_V);
    if (g_szModelM4A1_P[0]) precache_model(g_szModelM4A1_P);

    server_print("[M4 Loadout] Precached M4A4 and M4A1-S models successfully.");
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable          = register_cvar("amx_m4_loadout", "1");
    pCvar_DefaultChoice   = register_cvar("amx_m4_default", "0"); // 0 = M4A4, 1 = M4A1-S
    pCvar_BlockSilencer   = register_cvar("amx_m4_block_silencer", "1"); // Block right-click silencer on M4A4
    pCvar_AutoSilenceM4A1 = register_cvar("amx_m4_auto_silence", "1"); // Auto attach silencer on M4A1-S
    pCvar_Notify          = register_cvar("amx_m4_notify", "1");

    // Weapon Hooks
    RegisterHam(Ham_Item_Deploy, "weapon_m4a1", "OnM4Deploy_Post", 1);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_m4a1", "OnM4AddToPlayer_Post", 1);
    RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_m4a1", "OnM4SecondaryAttack_Pre", 0);
    register_forward(FM_SetModel, "OnSetModel_Post", 1);

    register_event("CurWeapon", "Event_CurWeapon", "be", "1=1");

    // Commands to open menu
    register_clcmd("say /m4", "Cmd_M4Menu");
    register_clcmd("say_team /m4", "Cmd_M4Menu");
    register_clcmd("say /loadout", "Cmd_M4Menu");
    register_clcmd("say_team /loadout", "Cmd_M4Menu");
    register_clcmd("m4", "Cmd_M4Menu");
    register_clcmd("m4_menu", "Cmd_M4Menu");

    // Direct switch commands
    register_clcmd("m4a4", "Cmd_SelectM4A4");
    register_clcmd("m4a1s", "Cmd_SelectM4A1S");
    register_clcmd("say /m4a4", "Cmd_SelectM4A4");
    register_clcmd("say /m4a1", "Cmd_SelectM4A1S");
}

public client_putinserver(id)
{
    new szInfo[10];
    get_user_info(id, "_m4_choice", szInfo, charsmax(szInfo));
    if (szInfo[0])
    {
        g_iM4Choice[id] = (szInfo[0] == '1') ? CHOICE_M4A1_S : CHOICE_M4A4;
    }
    else
    {
        g_iM4Choice[id] = get_pcvar_num(pCvar_DefaultChoice) ? CHOICE_M4A1_S : CHOICE_M4A4;
    }
}

public client_disconnected(id)
{
    g_iM4Choice[id] = CHOICE_M4A4;
}

// -------------------------------------------------------------
// Weapon Deployment & Model Setting
// -------------------------------------------------------------

public OnM4AddToPlayer_Post(iWpn, id)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn) || !is_user_alive(id))
        return HAM_IGNORED;

    // Auto-silence when picked up by Terrorist, or by CT using M4A1-S
    if (cs_get_user_team(id) == CS_TEAM_T || (cs_get_user_team(id) == CS_TEAM_CT && g_iM4Choice[id] == CHOICE_M4A1_S))
    {
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
    }

    return HAM_IGNORED;
}

public OnM4Deploy_Post(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    if (cs_get_user_team(id) == CS_TEAM_CT)
    {
        ApplyM4Model(id, iWpn);
    }
    else if (cs_get_user_team(id) == CS_TEAM_T)
    {
        // Terrorist wields scavenged M4A1-S: auto-silence
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
    }

    return HAM_IGNORED;
}

public Event_CurWeapon(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_alive(id))
        return;

    if (read_data(1) != 1)
        return;

    new wid = read_data(2);
    if (wid != CSW_M4A1)
        return;

    new iWpn = fm_find_ent_by_owner(-1, "weapon_m4a1", id);
    if (!pev_valid(iWpn))
        return;

    if (cs_get_user_team(id) == CS_TEAM_CT)
    {
        ApplyM4Model(id, iWpn);
    }
    else if (cs_get_user_team(id) == CS_TEAM_T)
    {
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
    }
}

stock ApplyM4Model(id, iWpn)
{
    if (g_iM4Choice[id] == CHOICE_M4A4)
    {
        // 1. Set Viewmodel (v_)
        if (g_szModelM4A4_V[0])
            set_pev(id, pev_viewmodel2, g_szModelM4A4_V);

        // 2. Set Playermodel (p_)
        if (g_szModelM4A4_P[0])
            set_pev(id, pev_weaponmodel2, g_szModelM4A4_P);

        // 3. M4A4 is always unsuppressed (no silencer)
        if (cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 0, 0);
        }
    }
    else // CHOICE_M4A1_S
    {
        // 1. Set Viewmodel (v_)
        if (g_szModelM4A1_V[0])
            set_pev(id, pev_viewmodel2, g_szModelM4A1_V);

        // 2. Set Playermodel (p_)
        if (g_szModelM4A1_P[0])
            set_pev(id, pev_weaponmodel2, g_szModelM4A1_P);

        // 3. Attach silencer if configured
        if (get_pcvar_num(pCvar_AutoSilenceM4A1) && !cs_get_weapon_silen(iWpn))
        {
            cs_set_weapon_silen(iWpn, 1, 0);
        }
    }
}

// -------------------------------------------------------------
// Silencer Blocking for M4A4 (Right-Click Secondary Attack)
// -------------------------------------------------------------

public OnM4SecondaryAttack_Pre(iWpn)
{
    if (!get_pcvar_num(pCvar_Enable) || !get_pcvar_num(pCvar_BlockSilencer) || !pev_valid(iWpn))
        return HAM_IGNORED;

    new id = get_pdata_cbase(iWpn, 41, 4);
    if (id < 1 || id > MaxClients || !is_user_alive(id))
        id = pev(iWpn, pev_owner);

    if (id < 1 || id > MaxClients || !is_user_alive(id))
        return HAM_IGNORED;

    if (cs_get_user_team(id) != CS_TEAM_CT)
        return HAM_IGNORED;

    // Block right-click silencer completely when holding M4A4!
    if (g_iM4Choice[id] == CHOICE_M4A4)
    {
        return HAM_SUPERCEDE;
    }

    return HAM_IGNORED;
}

// -------------------------------------------------------------
// Dropped Weapon (World Model w_)
// -------------------------------------------------------------

public OnSetModel_Post(ent, const model[])
{
    if (!get_pcvar_num(pCvar_Enable) || !pev_valid(ent))
        return FMRES_IGNORED;

    if (containi(model, "w_m4a1.mdl") == -1)
        return FMRES_IGNORED;

    new id = pev(ent, pev_owner);
    if (id >= 1 && id <= MaxClients)
    {
        if (g_iM4Choice[id] == CHOICE_M4A4 && g_szModelM4A4_W[0])
        {
            engfunc(EngFunc_SetModel, ent, g_szModelM4A4_W);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

// -------------------------------------------------------------
// Loadout Selection Menu (/m4, /loadout)
// -------------------------------------------------------------

public Cmd_M4Menu(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    ShowM4Menu(id);
    return PLUGIN_HANDLED;
}

public Cmd_SelectM4A4(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    SelectM4(id, CHOICE_M4A4);
    return PLUGIN_HANDLED;
}

public Cmd_SelectM4A1S(id)
{
    if (!get_pcvar_num(pCvar_Enable) || !is_user_connected(id))
        return PLUGIN_CONTINUE;

    SelectM4(id, CHOICE_M4A1_S);
    return PLUGIN_HANDLED;
}

public ShowM4Menu(id)
{
    new menu = menu_create("\y[CS:GO Loadout] Pilih Senjata M4 CT:\w", "Handler_M4Menu");

    new szItem1[96], szItem2[96];
    formatex(szItem1, charsmax(szItem1), "M4A4 \y[30/90, Suara Keras, No Silencer]%s", (g_iM4Choice[id] == CHOICE_M4A4) ? " \r(Aktif)" : "");
    formatex(szItem2, charsmax(szItem2), "M4A1-S \y[Silenced, Senyap]%s", (g_iM4Choice[id] == CHOICE_M4A1_S) ? " \r(Aktif)" : "");

    menu_additem(menu, szItem1, "1");
    menu_additem(menu, szItem2, "2");

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public Handler_M4Menu(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new szData[6], szName[64], iAccess, iCallback;
    menu_item_getinfo(menu, item, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback);
    menu_destroy(menu);

    new iChoice = str_to_num(szData);
    if (iChoice == 1)
    {
        SelectM4(id, CHOICE_M4A4);
    }
    else if (iChoice == 2)
    {
        SelectM4(id, CHOICE_M4A1_S);
    }

    return PLUGIN_HANDLED;
}

stock SelectM4(id, iChoice)
{
    g_iM4Choice[id] = iChoice;

    if (iChoice == CHOICE_M4A4)
    {
        client_cmd(id, "setinfo _m4_choice 0");
        if (get_pcvar_num(pCvar_Notify))
        {
            client_print_color(id, print_team_default, "^4[CS:GO Loadout]^1 Loadout CT dipilih: ^3M4A4^1 (30 Peluru, Suara Keras, Tanpa Silencer).");
        }
    }
    else
    {
        client_cmd(id, "setinfo _m4_choice 1");
        if (get_pcvar_num(pCvar_Notify))
        {
            client_print_color(id, print_team_default, "^4[CS:GO Loadout]^1 Loadout CT dipilih: ^3M4A1-S^1 (Bersilencer, Suara Senyap).");
        }
    }

    // Refresh model instantly if player is currently holding M4A1
    if (is_user_alive(id) && cs_get_user_team(id) == CS_TEAM_CT)
    {
        new wid = cs_get_user_weapon(id);
        if (wid == CSW_M4A1)
        {
            new iWpn = fm_find_ent_by_owner(-1, "weapon_m4a1", id);
            if (pev_valid(iWpn))
            {
                ApplyM4Model(id, iWpn);
            }
        }
    }
}
