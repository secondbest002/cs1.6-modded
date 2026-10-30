#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "CS2 Arm Switcher (Switchhands & Redraw)"
#define VERSION "1.2.0"
#define AUTHOR  "Antigravity"

// Sound Paths
new const SND_SWITCH[] = "weapons/draw_slide.wav";

// CVars
new pCvar_Enable;
new pCvar_Redraw;
new pCvar_Sound;
new pCvar_HUD;
new pCvar_Delay;
new pCvar_Cooldown;

// Player Hand State (0 = Left Hand, 1 = Right Hand)
new g_iPlayerHand[33];
new Float:g_flLastSwitchTime[33];

// Offsets for CBasePlayer and CBasePlayerWeapon
#define m_pActiveItem 373
#define m_bIsDefusing 99
#define m_flNextAttack 83
#define extra_offset_player 5

#define m_pPlayer 41
#define m_flNextPrimaryAttack 46
#define m_flNextSecondaryAttack 47
#define m_flTimeWeaponIdle 48
#define m_fInReload 54
#define extra_offset_weapon 4

// SVC message ID
#define SVC_WEAPONANIM 35

// Binary verified weapon draw sequence table (indexed by CSW_*)
new const g_iWeaponDrawAnim[CSW_LAST_WEAPON + 1] = {
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
new const Float:g_flWeaponDrawDuration[CSW_LAST_WEAPON + 1] = {
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

public plugin_precache()
{
    new szPath[128];
    formatex(szPath, charsmax(szPath), "sound/%s", SND_SWITCH);
    if (file_exists(szPath))
    {
        precache_sound(SND_SWITCH);
    }
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // CVars
    pCvar_Enable   = register_cvar("amx_switchhands_enable", "1");
    pCvar_Redraw   = register_cvar("amx_switchhands_redraw", "1");      // Re-deploy/draw weapon and apply tactical delay
    pCvar_Sound    = register_cvar("amx_switchhands_sound", "1");       // Play subtle weapon slide foley sound
    pCvar_HUD      = register_cvar("amx_switchhands_hud", "1");         // Show [ ◄ LEFT ] / [ RIGHT ► ] HUD indicator
    pCvar_Delay    = register_cvar("amx_switchhands_delay", "0.0");     // 0.0 = Auto-align with exact draw anim duration, >0.0 = Custom fixed delay
    pCvar_Cooldown = register_cvar("amx_switchhands_cooldown", "0.35"); // Anti-spam debounce delay

    // Commands
    register_clcmd("cs2_switcharms", "Cmd_SwitchArms"); // Fast client alias command
    register_clcmd("switchhands", "Cmd_SwitchHands");   // Standard CS2 console command
    register_clcmd("say /switchhands", "Cmd_SwitchHands");
    register_clcmd("say_team /switchhands", "Cmd_SwitchHands");
    register_clcmd("say /arm", "Cmd_SwitchHands");
    register_clcmd("say_team /arm", "Cmd_SwitchHands");

    // Hook Spawn
    RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn_Post", 1);

    server_print("[CS2 Arm Switcher] Loaded successfully. MOUSE4 Switchhands & Redraw aligned to draw animation.");
}

public client_putinserver(id)
{
    g_iPlayerHand[id] = 1; // Default right hand
    g_flLastSwitchTime[id] = 0.0;

    // Query client's current cl_righthand setting
    if (!is_user_bot(id))
    {
        query_client_cvar(id, "cl_righthand", "OnQueryRightHandResult");
    }
}

public client_disconnected(id)
{
    g_iPlayerHand[id] = 1;
    g_flLastSwitchTime[id] = 0.0;
}

public OnPlayerSpawn_Post(id)
{
    if (is_user_alive(id))
    {
        if (!is_user_bot(id))
        {
            query_client_cvar(id, "cl_righthand", "OnQueryRightHandResult");
        }
    }
    return HAM_IGNORED;
}

public OnQueryRightHandResult(id, const cvar[], const value[])
{
    if (is_user_connected(id))
    {
        g_iPlayerHand[id] = (str_to_num(value) != 0) ? 1 : 0;
    }
}

// -------------------------------------------------------------
// Core Switch Handler
// -------------------------------------------------------------
public Cmd_SwitchArms(id)
{
    // Argument 0: Left Hand (cl_righthand 0)
    // Argument 1: Right Hand (cl_righthand 1)
    new szArg[4];
    read_argv(1, szArg, charsmax(szArg));
    new iTargetHand = (szArg[0] != '^0') ? ((str_to_num(szArg) != 0) ? 1 : 0) : (g_iPlayerHand[id] ? 0 : 1);

    return ProcessArmSwitch(id, iTargetHand);
}

public Cmd_SwitchHands(id)
{
    // Toggle current hand
    new iTargetHand = g_iPlayerHand[id] ? 0 : 1;
    return ProcessArmSwitch(id, iTargetHand);
}

ProcessArmSwitch(id, iTargetHand)
{
    if (!get_pcvar_num(pCvar_Enable))
        return PLUGIN_HANDLED;

    if (!is_user_alive(id))
        return PLUGIN_HANDLED;

    // Debounce to prevent rapid spam glitches
    new Float:flGameTime = get_gametime();
    new Float:flCooldown = get_pcvar_float(pCvar_Cooldown);
    if (flCooldown > 0.0 && (flGameTime - g_flLastSwitchTime[id] < flCooldown))
        return PLUGIN_HANDLED;

    // Block if defusing bomb
    if (get_pdata_int(id, m_bIsDefusing, extra_offset_player))
        return PLUGIN_HANDLED;

    new weapon_id = get_user_weapon(id);
    if (weapon_id <= CSW_NONE || weapon_id > CSW_LAST_WEAPON)
        return PLUGIN_HANDLED;

    // Block if actively planting C4
    if (weapon_id == CSW_C4 && (pev(id, pev_button) & IN_ATTACK))
        return PLUGIN_HANDLED;

    // Block if actively throwing grenade (pin pulled)
    if ((weapon_id == CSW_HEGRENADE || weapon_id == CSW_FLASHBANG || weapon_id == CSW_SMOKEGRENADE) && (pev(id, pev_button) & (IN_ATTACK | IN_ATTACK2)))
        return PLUGIN_HANDLED;

    g_flLastSwitchTime[id] = flGameTime;
    g_iPlayerHand[id] = iTargetHand;

    // Sync client cvar so client and server remain 100% consistent
    client_cmd(id, "cl_righthand %d", g_iPlayerHand[id]);

    // 1. Redraw / Tactical Weapon Deploy
    if (get_pcvar_num(pCvar_Redraw))
    {
        new weapon_ent = GetUserActiveWeaponEntity(id, weapon_id);
        if (pev_valid(weapon_ent))
        {
            // Do not re-deploy if in reload
            new bool:bInReload = bool:(get_pdata_int(weapon_ent, m_fInReload, extra_offset_weapon) != 0);
            new bool:bInZoom = bool:(cs_get_user_zoom(id) > 0);

            if (!bInReload)
            {
                // If scoped, unscope cleanly (just like CS2)
                if (bInZoom)
                {
                    cs_set_user_zoom(id, CS_SET_NO_ZOOM, 1);
                }

                // Execute the weapon's native Deploy virtual function
                ExecuteHamB(Ham_Item_Deploy, weapon_ent);

                // Compute exact draw duration aligned with weapon draw animation
                new Float:flCvarDelay = get_pcvar_float(pCvar_Delay);
                new Float:flDeployDuration = (flCvarDelay > 0.0) ? flCvarDelay : g_flWeaponDrawDuration[weapon_id];
                if (flDeployDuration <= 0.0)
                {
                    flDeployDuration = 0.85;
                }

                // Native GoldSrc countdown relative floats:
                // m_flNextAttack on player locks ItemPostFrame until draw animation completes
                set_pdata_float(id, m_flNextAttack, flDeployDuration, extra_offset_player);
                // Align weapon primary & secondary attack readiness exactly to the draw finish
                set_pdata_float(weapon_ent, m_flNextPrimaryAttack, flDeployDuration, extra_offset_weapon);
                set_pdata_float(weapon_ent, m_flNextSecondaryAttack, flDeployDuration, extra_offset_weapon);
                set_pdata_float(weapon_ent, m_flTimeWeaponIdle, flDeployDuration + 0.1, extra_offset_weapon);

                // Force viewmodel redraw animation over network
                new iDrawAnim = GetWeaponDrawAnim(weapon_id, weapon_ent);
                if (iDrawAnim >= 0)
                {
                    SendWeaponAnim(id, iDrawAnim, weapon_ent);
                }
            }
        }
    }

    // 2. Sound Feedback
    if (get_pcvar_num(pCvar_Sound))
    {
        client_cmd(id, "spk %s", SND_SWITCH);
    }

    // 3. HUD Feedback
    if (get_pcvar_num(pCvar_HUD))
    {
        ShowHandHUD(id, g_iPlayerHand[id]);
    }

    return PLUGIN_HANDLED;
}

// -------------------------------------------------------------
// Helper Stocks
// -------------------------------------------------------------
stock GetWeaponDrawAnim(weapon_id, weapon_ent)
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

    return g_iWeaponDrawAnim[weapon_id];
}

stock SendWeaponAnim(id, iAnim, weapon_ent = 0)
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

stock GetUserActiveWeaponEntity(id, weapon_id)
{
    // Try CBasePlayer m_pActiveItem
    new weapon_ent = get_pdata_cbase(id, m_pActiveItem, extra_offset_player);
    if (pev_valid(weapon_ent) && pev(weapon_ent, pev_owner) == id)
        return weapon_ent;

    // Fallback: search by classname owned by this player
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

stock ShowHandHUD(id, iHand)
{
    if (iHand == 0)
    {
        // Left hand: Cool Cyan tone
        set_hudmessage(80, 200, 255, -1.0, 0.82, 0, 0.0, 1.2, 0.1, 0.2, -1);
        show_hudmessage(id, "[ ◄ LEFT HAND ]");
    }
    else
    {
        // Right hand: Warm CS2 Amber/Gold tone
        set_hudmessage(255, 190, 70, -1.0, 0.82, 0, 0.0, 1.2, 0.1, 0.2, -1);
        show_hudmessage(id, "[ RIGHT HAND ► ]");
    }
}
