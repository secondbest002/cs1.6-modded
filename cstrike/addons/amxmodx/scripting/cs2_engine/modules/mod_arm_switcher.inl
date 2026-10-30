// ==============================================================================
// CS2 MODERN ENGINE - SUB-MODULE: ARM SWITCHER (SWITCHHANDS & REDRAW)
// CS2 MOUSE4 / switchhands redraw weapon deploy and cloth foley audio
// ==============================================================================

#if defined _mod_arm_switcher_included
    #endinput
#endif
#define _mod_arm_switcher_included

// Sound Paths
new const arm_SND_SWITCH[] = "weapons/draw_slide.wav";

// CVars
new arm_pCvar_Enable;
new arm_pCvar_Redraw;
new arm_pCvar_Sound;
new arm_pCvar_Delay;
new arm_pCvar_Cooldown;

// Player Hand State (0 = Left Hand, 1 = Right Hand)
new arm_iPlayerHand[33];
new Float:arm_flLastSwitchTime[33];

// Binary verified weapon draw sequence table (indexed by CSW_*)
new const arm_iWeaponDrawAnim[CSW_LAST_WEAPON + 1] = {
    -1, // 0  CSW_NONE
    6,  // 1  CSW_P228
    -1, // 2  CSW_GLOCK (unused)
    4,  // 3  CSW_SCOUT
    3,  // 4  CSW_HEGRENADE
    6,  // 5  CSW_XM1014
    1,  // 6  CSW_C4
    2,  // 7  CSW_MAC10
    2,  // 8  CSW_AUG
    3,  // 9  CSW_SMOKEGRENADE
    15, // 10 CSW_ELITE
    5,  // 11 CSW_FIVESEVEN
    2,  // 12 CSW_UMP45
    4,  // 13 CSW_SG550
    2,  // 14 CSW_GALIL
    2,  // 15 CSW_FAMAS
    6,  // 16 CSW_USP (Silenced = 6, Unsilenced = 14)
    8,  // 17 CSW_GLOCK18
    5,  // 18 CSW_AWP
    2,  // 19 CSW_MP5NAVY
    4,  // 20 CSW_M249
    6,  // 21 CSW_M3
    5,  // 22 CSW_M4A1 (Silenced = 5, Unsilenced = 12)
    2,  // 23 CSW_TMP
    4,  // 24 CSW_G3SG1
    3,  // 25 CSW_FLASHBANG
    5,  // 26 CSW_DEAGLE
    2,  // 27 CSW_SG552
    2,  // 28 CSW_AK47
    3,  // 29 CSW_KNIFE
    2   // 30 CSW_P90
};

// Precise draw animation durations (in seconds) matching model sequences
new const Float:arm_flWeaponDrawDuration[CSW_LAST_WEAPON + 1] = {
    0.0,  // 0  CSW_NONE
    1.09, // 1  CSW_P228
    0.0,  // 2  CSW_GLOCK (unused)
    1.17, // 3  CSW_SCOUT
    1.00, // 4  CSW_HEGRENADE
    1.03, // 5  CSW_XM1014
    0.96, // 6  CSW_C4
    1.25, // 7  CSW_MAC10
    0.89, // 8  CSW_AUG
    0.96, // 9  CSW_SMOKEGRENADE
    0.69, // 10 CSW_ELITE
    1.04, // 11 CSW_FIVESEVEN
    1.04, // 12 CSW_UMP45
    0.65, // 13 CSW_SG550
    1.08, // 14 CSW_GALIL
    0.77, // 15 CSW_FAMAS
    1.00, // 16 CSW_USP
    1.04, // 17 CSW_GLOCK18
    1.45, // 18 CSW_AWP
    1.03, // 19 CSW_MP5NAVY
    1.13, // 20 CSW_M249
    0.96, // 21 CSW_M3
    1.00, // 22 CSW_M4A1
    1.21, // 23 CSW_TMP
    0.87, // 24 CSW_G3SG1
    0.96, // 25 CSW_FLASHBANG
    0.96, // 26 CSW_DEAGLE
    1.02, // 27 CSW_SG552
    1.04, // 28 CSW_AK47
    1.00, // 29 CSW_KNIFE
    0.80  // 30 CSW_P90
};

// -------------------------------------------------------------
// Lifecycle Hooks
// -------------------------------------------------------------
public Mod_ArmSwitcher_Init()
{
    arm_pCvar_Enable   = register_cvar("amx_switchhands_enable", "1");
    arm_pCvar_Redraw   = register_cvar("amx_switchhands_redraw", "1");
    arm_pCvar_Sound    = register_cvar("amx_switchhands_sound", "1");
    arm_pCvar_Delay    = register_cvar("amx_switchhands_delay", "0.0");
    arm_pCvar_Cooldown = register_cvar("amx_switchhands_cooldown", "0.35");

    register_clcmd("cs2_switcharms", "arm_Cmd_SwitchArms");
    register_clcmd("switchhands", "arm_Cmd_SwitchHands");
    register_clcmd("say /switchhands", "arm_Cmd_SwitchHands");
    register_clcmd("say_team /switchhands", "arm_Cmd_SwitchHands");
    register_clcmd("say /arm", "arm_Cmd_SwitchHands");
    register_clcmd("say_team /arm", "arm_Cmd_SwitchHands");
}

public Mod_ArmSwitcher_Precache()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "sound/%s", arm_SND_SWITCH);
    if (file_exists(szPath))
    {
        precache_sound(arm_SND_SWITCH);
    }
}

public Mod_ArmSwitcher_PutInServer(id)
{
    arm_iPlayerHand[id] = 1;
    arm_flLastSwitchTime[id] = 0.0;

    if (!is_user_bot(id))
    {
        query_client_cvar(id, "cl_righthand", "arm_OnQueryRightHandResult");
    }
}

public Mod_ArmSwitcher_Disconnect(id)
{
    arm_iPlayerHand[id] = 1;
    arm_flLastSwitchTime[id] = 0.0;
}

public Mod_ArmSwitcher_NewRound()
{
    for (new i = 1; i <= 32; i++)
    {
        arm_flLastSwitchTime[i] = 0.0;
    }
}

public Mod_ArmSwitcher_RoundEnd()
{
    for (new i = 1; i <= 32; i++)
    {
        arm_flLastSwitchTime[i] = 0.0;
    }
}

public Mod_ArmSwitcher_Spawn(id)
{
    if (is_user_alive(id))
    {
        if (!is_user_bot(id))
        {
            query_client_cvar(id, "cl_righthand", "arm_OnQueryRightHandResult");
        }
    }
}

public arm_OnQueryRightHandResult(id, const cvar[], const value[])
{
    if (is_user_connected(id))
    {
        arm_iPlayerHand[id] = (str_to_num(value) != 0) ? 1 : 0;
    }
}

// -------------------------------------------------------------
// Core Switch Handler
// -------------------------------------------------------------
public arm_Cmd_SwitchArms(id)
{
    new szArg[4];
    read_argv(1, szArg, charsmax(szArg));
    new iTargetHand = (szArg[0] != '^0') ? ((str_to_num(szArg) != 0) ? 1 : 0) : (arm_iPlayerHand[id] ? 0 : 1);

    return arm_ProcessArmSwitch(id, iTargetHand);
}

public arm_Cmd_SwitchHands(id)
{
    new iTargetHand = arm_iPlayerHand[id] ? 0 : 1;
    return arm_ProcessArmSwitch(id, iTargetHand);
}

arm_ProcessArmSwitch(id, iTargetHand)
{
    if (!get_pcvar_num(pCvar_MasterEnable) || !get_pcvar_num(arm_pCvar_Enable))
        return PLUGIN_HANDLED;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    new Float:flGameTime = get_gametime();
    new Float:flCooldown = get_pcvar_float(arm_pCvar_Cooldown);
    if (flCooldown > 0.0 && (flGameTime - arm_flLastSwitchTime[id] < flCooldown))
        return PLUGIN_HANDLED;

    if (get_pdata_int(id, m_bIsDefusing, extra_offset_player))
        return PLUGIN_HANDLED;

    new weapon_id = get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return PLUGIN_HANDLED;

    if (weapon_id == CSW_C4 && (pev(id, pev_button) & IN_ATTACK))
        return PLUGIN_HANDLED;

    if ((weapon_id == CSW_HEGRENADE || weapon_id == CSW_FLASHBANG || weapon_id == CSW_SMOKEGRENADE) && (pev(id, pev_button) & (IN_ATTACK | IN_ATTACK2)))
        return PLUGIN_HANDLED;

    arm_flLastSwitchTime[id] = flGameTime;
    arm_iPlayerHand[id] = iTargetHand;

    client_cmd(id, "cl_righthand %d", arm_iPlayerHand[id]);

    if (get_pcvar_num(arm_pCvar_Redraw))
    {
        new weapon_ent = arm_GetUserActiveWeaponEntity(id, weapon_id);
        if (pev_valid(weapon_ent))
        {
            new bool:bInReload = bool:(get_pdata_int(weapon_ent, m_fInReload, extra_offset_weapon) != 0);
            new bool:bInZoom = bool:(cs_get_user_zoom(id) > 0);

            if (!bInReload)
            {
                if (bInZoom)
                {
                    cs_set_user_zoom(id, CS_SET_NO_ZOOM, 1);
                }

                // Play redraw animation on the active viewmodel
                new iDrawAnim = arm_GetWeaponDrawAnim(weapon_id, weapon_ent);
                if (iDrawAnim >= 0)
                {
                    arm_SendWeaponAnim(id, iDrawAnim, weapon_ent);
                }

                // Tactical firing delay:
                // 0.0 = instant shooting (no lockout, default smooth CS 1.6 gameplay)
                // >0.0 = custom fixed delay in seconds
                // <0.0 = auto delay matching weapon draw animation length
                new Float:flCvarDelay = get_pcvar_float(arm_pCvar_Delay);
                new Float:flLockDelay = 0.0;
                if (flCvarDelay > 0.0)
                {
                    flLockDelay = flCvarDelay;
                }
                else if (flCvarDelay < 0.0)
                {
                    flLockDelay = arm_flWeaponDrawDuration[weapon_id];
                }

                if (flLockDelay > 0.0)
                {
                    set_pdata_float(id, m_flNextAttack, flGameTime + flLockDelay, extra_offset_player);
                    set_pdata_float(weapon_ent, m_flNextPrimaryAttack, flGameTime + flLockDelay, extra_offset_weapon);
                    set_pdata_float(weapon_ent, m_flNextSecondaryAttack, flGameTime + flLockDelay, extra_offset_weapon);
                    set_pdata_float(weapon_ent, m_flTimeWeaponIdle, flGameTime + flLockDelay + 0.1, extra_offset_weapon);
                }
            }
        }
    }

    if (get_pcvar_num(arm_pCvar_Sound))
    {
        client_cmd(id, "spk %s", arm_SND_SWITCH);
    }

    return PLUGIN_HANDLED;
}

stock arm_GetWeaponDrawAnim(weapon_id, weapon_ent)
{
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return -1;

    if (weapon_id == CSW_USP)
    {
        return (pev_valid(weapon_ent) && cs_get_weapon_silen(weapon_ent)) ? 6 : 14;
    }
    else if (weapon_id == CSW_M4A1)
    {
        return (pev_valid(weapon_ent) && cs_get_weapon_silen(weapon_ent)) ? 5 : 12;
    }

    return arm_iWeaponDrawAnim[weapon_id];
}

stock arm_SendWeaponAnim(id, iAnim, weapon_ent = 0)
{
    if (!is_user_alive(id) || iAnim < 0)
        return;

    set_pev(id, pev_weaponanim, iAnim);

    new iBody = (pev_valid(weapon_ent)) ? pev(weapon_ent, pev_body) : 0;

    message_begin(MSG_ONE, SVC_WEAPONANIM, _, id);
    write_byte(iAnim);
    write_byte(iBody);
    message_end();
}

stock arm_GetUserActiveWeaponEntity(id, weapon_id)
{
    // Native AMX Mod X: 100% OS-safe active weapon entity resolution
    new weapon_ent = cs_get_user_weapon_entity(id);
    if (pev_valid(weapon_ent) && cs_get_weapon_id(weapon_ent) == weapon_id)
        return weapon_ent;

    new weapon_name[32];
    get_weaponname(weapon_id, weapon_name, charsmax(weapon_name));

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", weapon_name)) > 0)
    {
        if (pev(ent, pev_owner) == id)
            return ent;
    }

    return 0;
}
